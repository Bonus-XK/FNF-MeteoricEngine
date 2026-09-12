#!/bin/sh
# Meteoric Engine macOS 增量编译脚本 (-release)
# 用法: ./compile-mac.sh          # 增量编译
#       ./compile-mac.sh test     # 编译并运行
set -e
cd "$(dirname "$0")"

# 加载 Homebrew 环境与 NEKOPATH（从 ~/.zprofile）
if [ -f "$HOME/.zprofile" ]; then
  . "$HOME/.zprofile" 2>/dev/null || true
fi

# 修正 NEKOPATH：.zprofile 中的路径可能已失效，回退到实际存在 std.ndll 的目录
if [ ! -d "$NEKOPATH" ] || [ ! -f "$NEKOPATH/std.ndll" ]; then
  for p in /usr/local/lib/neko /opt/homebrew/lib/neko; do
    if [ -f "$p/std.ndll" ]; then
      export NEKOPATH="$p"
      break
    fi
  done
fi

# ---- 自动关闭旧的游戏进程 ----
# 构建会替换 app 文件，旧进程持有旧文件句柄会干扰；测试时重复启动也会冲突。
# 顺带清掉 lime livereload 残留进程（进程名同样是 Meteoric）。
pkill -f "Meteoric" 2>/dev/null && echo "[pre-build] closed old game process(es)" || true
sleep 1

# ---- 工具：APFS 克隆复制 + 删除前补写权限 ----
# 1) cp_clone：优先 `cp -R -c`（APFS copy-on-write 克隆，14GB 的 mods 近乎瞬时且不占额外空间；
#    之后任何一方被修改都会自动写时复制，语义与普通复制完全一致）。不支持时回退普通 cp -R。
# 2) rm_force：删除前先 chmod -R u+w。macOS 上从 zip/外部解压来的 mod 常带只读目录
#    （dr-xr-xr-x），`rm -rf` 会 "Permission denied" 并以非零码退出 —— 本脚本开头是 set -e，
#    会直接把整个构建干掉（实测：2026-09-10 构建就死在这里，产物停在 9-06）。
cp_clone() {
  cp -R -c "$1" "$2" 2>/dev/null || cp -R "$1" "$2"
}
rm_force() {
  if [ -e "$1" ]; then
    chmod -R u+w "$1" 2>/dev/null || true
    rm -rf "$1"
  fi
}

# ---- 构建前：备份当前用户 mods（构建会重置 Resources）----
# 用"上一次构建产物里的 mods"作备份源，这样用户删除的 mod 不会在下次构建时复活；
# 首次构建（无产物）时回退到 tools/user_mods 快照。
RES="export/release/macos/bin/Meteoric.app/Contents/Resources"
if [ -d "$RES/mods" ]; then
  rm_force tools/user_mods_prev
  mkdir -p tools/user_mods_prev
  cp_clone "$RES/mods" tools/user_mods_prev/mods
  if [ -f "$RES/modsList.txt" ]; then
    cp "$RES/modsList.txt" tools/user_mods_prev/modsList.txt
  fi
  echo "[pre-build] backed up current user mods"
fi

# ---- 构建前：单独备份多版本容器（mods/_containers 里是玩家塞进来的整个引擎，体积大）----
# 虽然上面的 mods 备份已包含它，这里额外做一份独立快照：容器目录常达 GB 级，
# 玩家可能清理 tools/user_mods_prev，独立快照能避免“编译一次丢一次容器”。
# 注意：mods 备份 + 恢复（下方 post-build）会整体还原 _containers，本快照只作兜底。
CONTAINERS_SRC="$RES/mods/_containers"
CONTAINERS_SNAP="tools/user_containers_prev"
if [ -d "$CONTAINERS_SRC" ]; then
  rm_force "$CONTAINERS_SNAP"
  mkdir -p "$CONTAINERS_SNAP"
  cp_clone "$CONTAINERS_SRC" "$CONTAINERS_SNAP/_containers"
  echo "[pre-build] backed up containers ($(du -sh "$CONTAINERS_SNAP" 2>/dev/null | cut -f1))"
fi

# ---- 测量模式：./compile-mac.sh profile → 额外加 -D METEORIC_PROFILE ----
# （仅开启性能探针；不改变任何游戏逻辑。正常构建不带此参数时零影响。）
PROFILE_DEFINE=""
if [ "$1" = "profile" ]; then
  PROFILE_DEFINE="-D METEORIC_PROFILE"
  shift
fi

# ---- 调试模式：./compile-mac.sh debug（或 METEORIC_DEBUG=1）----
# 定义 `meteoric_debug`，启用源码里挂在 #if meteoric_debug 下的启动诊断
# （目前是 TitleState 的 [FRAMERATE] 行；Windows 侧同款开关见 compile-windows.sh）。
# 正式构建不定义它 → 诊断代码不参与编译，零开销。
# ⚠ 不加 Haxe 的 `-debug`：它定义 `debug` 符号会改变 CrashHandler 分支，
#   使 `source/Main.hx:476` 报 installNativeHandlers 不存在（与 Windows 同因）。
DEBUG_FLAGS=""
if [ "$1" = "debug" ]; then
  DEBUG_FLAGS="-D meteoric_debug"
  shift
fi
if [ "${METEORIC_DEBUG:-0}" = "1" ]; then
  DEBUG_FLAGS="-D meteoric_debug"
fi
if [ -n "$DEBUG_FLAGS" ]; then
  echo "[compile] 调试构建：启用 meteoric_debug 诊断输出"
fi

# ---- 类型检查模式：./compile-mac.sh typecheck ----
# 只做 Haxe 类型检查，**绝不改动 app**：
# `haxelib run lime build macos --no-output` 这个名字很有欺骗性 —— 它**不阻止写出**，
# 仍会把 `lime.ndll`（以及 Resources 等）覆盖成构建树里的版本（实测 2026-09-12：
# app 内 ndll 从墙钟版 9233040 字节 / 96df302c… 被换成 stable 版 8660712 字节 / 01be7172…）。
# 而桌面端 frameRate 哨兵是 100000，缺了墙钟补丁的 ndll 会让主线程 catch-up 循环死转
# → 100% CPU 卡在加载界面（本文件 104 行起记录的事故）。
# 因此本模式自己负责「先备份、检查完无条件还原 + 重新签名」，使类型检查成为**只读**操作。
# 用法：./compile-mac.sh typecheck   （退出码 0 = 通过）
if [ "$1" = "typecheck" ]; then
  shift
  APP_NDLL_TC="export/release/macos/bin/Meteoric.app/Contents/MacOS/lime.ndll"
  TC_BAK=""
  if [ -f "$APP_NDLL_TC" ]; then
    TC_BAK="$(mktemp -t meteoric_ndll_bak)"
    cp "$APP_NDLL_TC" "$TC_BAK"
    echo "[typecheck] 已备份 app 内 lime.ndll ($(md5 -q "$APP_NDLL_TC"))"
  fi
  haxelib run lime build macos --no-output "$@"
  TC_EXIT=$?
  # 无条件还原（无论检查成功与否）
  if [ -n "$TC_BAK" ] && [ -f "$TC_BAK" ]; then
    # lime 返回后仍可能有异步收尾在覆盖，先等干净
    for attempt in $(seq 1 12); do
      if ! pgrep -f "haxe.*(lime|hxcpp)|lime.*(build|no-output)|hxcpp.*Build" >/dev/null 2>&1; then break; fi
      sleep 2
    done
    cp "$TC_BAK" "$APP_NDLL_TC"
    sleep 2
    cp "$TC_BAK" "$APP_NDLL_TC"   # 二次覆盖，防收尾进程竞态

    # ---- 交叉校验：还原目标必须是"墙钟版"，不能只是"和备份一样" ----
    # 2026-09-12 实测事故（复现两次）：lime 收尾进程会在还原**之后**继续覆盖 app 内 ndll，
    # 把它换成构建树里的未打补丁版（8660712 字节，缺 HiResMs/WaitEventTimeout）→
    # 下次启动 100% CPU 卡加载界面。且 app 内那份"本地墙钟拷贝"自身也可能已被覆盖，
    # 所以判据不能只看"是否等于备份"，要识别**已知坏指纹**并用权威副本兜底 + 复验。
    BAD_SIZE=8660712          # build 日志实测的未打补丁版大小
    TC_OK=0
    for attempt in $(seq 1 10); do
      APP_SIZE=$(stat -f%z "$APP_NDLL_TC" 2>/dev/null || echo 0)

      # ① 命中已知坏指纹 → 用权威墙钟版覆盖后再看一轮
      if [ "$APP_SIZE" = "$BAD_SIZE" ]; then
        echo "[typecheck] ⚠ app 内 ndll 命中已知坏指纹（size=$APP_SIZE）→ 用 tools/lime.ndll.wallclock 覆盖"
        cp "tools/lime.ndll.wallclock" "$APP_NDLL_TC"
        sleep 2
        continue
      fi

      # ② 与权威墙钟版一致 → 通过
      if cmp -s "tools/lime.ndll.wallclock" "$APP_NDLL_TC"; then TC_OK=1; break; fi

      # ③ 与备份一致且大小明显不是坏版（可能是另一份墙钟构建）→ 通过
      if cmp -s "$TC_BAK" "$APP_NDLL_TC" && [ "$APP_SIZE" -gt 9000000 ]; then TC_OK=1; break; fi

      # ④ 其余：先还原备份，下一轮再验
      cp "$TC_BAK" "$APP_NDLL_TC"
      sleep 2
    done

    if [ "$TC_OK" = "1" ]; then
      codesign --force --deep -s - "export/release/macos/bin/Meteoric.app" 2>/dev/null || true
      echo "[typecheck] 已还原墙钟版 lime.ndll + 重新签名 (md5: $(md5 -q "$APP_NDLL_TC"), size: $(stat -f%z "$APP_NDLL_TC"))"
    else
      echo "[typecheck] ✘ 还原失败：app 内 ndll 始终不稳定（size=$(stat -f%z "$APP_NDLL_TC" 2>/dev/null)）"
      echo "[typecheck]   → 请直接跑 ./compile-mac.sh 重建（其 post-build 会恢复墙钟版）"
    fi
    rm -f "$TC_BAK"
  fi
  if [ $TC_EXIT -ne 0 ]; then
    echo "[typecheck] ✘ 类型检查未通过 (exit=$TC_EXIT)"
  else
    echo "[typecheck] ✔ 类型检查通过（app 未被改动）"
  fi
  exit $TC_EXIT
fi

if [ "$1" = "test" ]; then
  haxelib run lime test macos -release $PROFILE_DEFINE $DEBUG_FLAGS
else
  haxelib run lime build macos -release $PROFILE_DEFINE $DEBUG_FLAGS
fi

# ---- 构建后处理：恢复墙钟版 lime.ndll ----
# lime 构建流程会重新编译并覆盖 app 里的 lime.ndll；lime 返回后仍有异步收尾
# （约 1~2 分钟）会再次覆盖 app 里的 ndll，所以先等所有 lime/hxcpp 残留进程结束。
#
# 【v1.1.2 关键】Main.hx 桌面端 frameRate 哨兵已是 100000（无人工限制），
# 必须配合「墙钟帧循环」ndll（nextUpdate/currentUpdate 为 double + HiResMs + WaitEventTimeout）；
# 若沿用 8月17 旧 stable ndll（nextUpdate 是 Uint32），亚毫秒 framePeriod 每次 += 被截断成 +0
# → catch-up 循环 while (nextUpdate <= currentUpdate) 永不前进 → 主线程 100% 死循环
# → 启动后卡死在加载界面（CPU 100%）。因此这里恢复「墙钟版」而不是旧 stable。
STABLE_NDLL="tools/lime.ndll.wallclock"
APP_NDLL="export/release/macos/bin/Meteoric.app/Contents/MacOS/lime.ndll"
echo "[post-build] waiting for lime/hxcpp tail processes to finish..."
for attempt in $(seq 1 30); do
  if ! pgrep -f "haxe.*(lime|hxcpp)|lime.*(build|test)|hxcpp.*Build" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
sleep 3
if [ -f "$STABLE_NDLL" ] && [ -f "$APP_NDLL" ]; then
  cp "$STABLE_NDLL" "$APP_NDLL"
  sleep 3
  if cmp -s "$STABLE_NDLL" "$APP_NDLL"; then
    codesign --force --deep -s - "export/release/macos/bin/Meteoric.app" 2>/dev/null || true
    echo "[post-build] restored wallclock lime.ndll + re-signed  (md5: $(md5 -q "$APP_NDLL"))"
  else
    echo "[post-build] WARNING: lime.ndll was overwritten again after restore"
  fi
fi

# ---- 恢复用户 mods（lime 构建会重置 Resources，用户装过的 mod 会丢）----
# 先删掉目标 mods 目录再拷贝：cp -R 目标已存在时会嵌套成 mods/mods/，
# 被 updateModList 扫成名为 "mods" 的假模组（用户看到的"永远有一个 mods 模组"）。
MODS_SRC="tools/user_mods_prev"
if [ ! -d "$MODS_SRC/mods" ]; then
  MODS_SRC="tools/user_mods" # 首次构建回退快照
fi
if [ -d "$MODS_SRC/mods" ]; then
  rm_force "$RES/mods"
  cp_clone "$MODS_SRC/mods" "$RES/mods"
  if [ -f "$MODS_SRC/modsList.txt" ]; then
    cp "$MODS_SRC/modsList.txt" "$RES/modsList.txt"
  fi
  echo "[post-build] restored user mods from $MODS_SRC/"
fi

# ---- 兜底：mods 恢复后若容器目录仍缺失，用独立快照补回 ----
# 触发场景：玩家清过 tools/user_mods_prev、或 mods 备份里不含 _containers。
if [ ! -d "$RES/mods/_containers" ] && [ -d "$CONTAINERS_SNAP/_containers" ]; then
  mkdir -p "$RES/mods"
  cp_clone "$CONTAINERS_SNAP/_containers" "$RES/mods/_containers"
  echo "[post-build] restored containers from $CONTAINERS_SNAP/ (fallback)"
fi

