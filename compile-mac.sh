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

# ---- 构建前：备份当前用户 mods（构建会重置 Resources）----
# 用"上一次构建产物里的 mods"作备份源，这样用户删除的 mod 不会在下次构建时复活；
# 首次构建（无产物）时回退到 tools/user_mods 快照。
RES="export/release/macos/bin/Meteoric.app/Contents/Resources"
if [ -d "$RES/mods" ]; then
  rm -rf tools/user_mods_prev
  mkdir -p tools/user_mods_prev
  cp -R "$RES/mods" tools/user_mods_prev/mods
  if [ -f "$RES/modsList.txt" ]; then
    cp "$RES/modsList.txt" tools/user_mods_prev/modsList.txt
  fi
  echo "[pre-build] backed up current user mods"
fi

if [ "$1" = "test" ]; then
  haxelib run lime test macos -release
else
  haxelib run lime build macos -release
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
  rm -rf "$RES/mods"
  cp -R "$MODS_SRC/mods" "$RES/mods"
  if [ -f "$MODS_SRC/modsList.txt" ]; then
    cp "$MODS_SRC/modsList.txt" "$RES/modsList.txt"
  fi
  echo "[post-build] restored user mods from $MODS_SRC/"
fi
