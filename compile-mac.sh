#!/bin/sh
# Meteoric Engine macOS 增量编译脚本 (-release)
# 用法: ./compile-mac.sh          # 增量编译
#       ./compile-mac.sh test     # 编译并运行
set -e
cd "$(dirname "$0")"

# ---- 目标架构：Apple Silicon 上默认出 arm64 原生二进制 ----
# 为什么必须显式指定：haxe/lime 装在 /usr/local（Intel Homebrew 路径），在 M 系列 Mac 上
# 整个工具链跑在 Rosetta 2 下，`System.hostArchitecture` 因此返回 X64 —— lime 的
# MacPlatform.rebuild() 据此走 `case X64` 分支，编出 x86_64 目标，游戏**整个跑在
# Rosetta 转译器上**（`oahd` 进程可见）。实测 PNG 解码惩罚 ~2.0×、纯计算 ~1.76×，
# 进曲加载里 64% 的时间花在 BitmapData.fromFile，这部分白丢一半。
# 覆盖方式：METEORIC_ARCH=x86_64 强制回退 Intel 构建。
case "${METEORIC_ARCH:-auto}" in
  arm64)  TARGET_ARCH="arm64" ;;
  x86_64) TARGET_ARCH="x86_64" ;;
  auto)
    if [ "$(uname -m)" = "arm64" ] && [ -f "tools/lime.ndll.wallclock-arm64" ]; then
      TARGET_ARCH="arm64"
    else
      TARGET_ARCH="x86_64"
    fi
    ;;
  *) echo "未知 METEORIC_ARCH=${METEORIC_ARCH}（可选 auto/arm64/x86_64）" >&2; exit 2 ;;
esac
if [ "$TARGET_ARCH" = "arm64" ]; then
  ARCH_FLAG="-Darm64"
  NDLL_SRC="tools/lime.ndll.wallclock-arm64"
else
  ARCH_FLAG=""
  NDLL_SRC="tools/lime.ndll.wallclock"
fi
export METEORIC_TARGET_ARCH="$TARGET_ARCH"

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
#
# ⚠ 体积陷阱（实测 2026-10-16）：mods 目录里可能塞着几十 GB 的谱面数据
#   （stupid-griefer 66 个 Part × 1.2GB = 78GB）。这个备份 + 下方 post-build 的
#   还原，每次构建各拷一遍 → 单次构建多花 30-40 分钟（实测 typecheck 从 4 分钟
#   涨到 41 分钟，脚本 CPU 时间为 0，全是 I/O 等待）。
#
#   开关：METEORIC_BACKUP_MODS=0 跳过 / =1 强制备份 / 不设 = auto
#     auto 规则：mods 超过 2GB 就跳过（这么大的目录逐次全量拷贝显然不是本意）。
#
#   ⚠ 跳过备份时**必须同时跳过还原**：post-build 的还原流程是
#     `rm_force "$RES/mods"` 再拷回，没有备份就会把玩家的 mods 直接删光。
#     两侧由同一个变量 BACKUP_MODS 门控。
RES="export/release/macos/bin/Meteoric.app/Contents/Resources"
BACKUP_MODS="${METEORIC_BACKUP_MODS:-auto}"
BACKUP_MODS_THRESHOLD_MB="${METEORIC_BACKUP_MODS_THRESHOLD_MB:-2048}"

if [ -d "$RES/mods" ]; then
  if [ "$BACKUP_MODS" = "auto" ]; then
    _mods_mb=$(du -sm "$RES/mods" 2>/dev/null | cut -f1)
    _mods_mb=${_mods_mb:-0}
    if [ "$_mods_mb" -gt "$BACKUP_MODS_THRESHOLD_MB" ]; then
      BACKUP_MODS=0
      echo "[pre-build] mods 目录 ${_mods_mb}MB > ${BACKUP_MODS_THRESHOLD_MB}MB → 自动跳过 mods 备份（省两次全量拷贝）"
    else
      BACKUP_MODS=1
    fi
  fi

  if [ "$BACKUP_MODS" = "1" ]; then
    rm_force tools/user_mods_prev
    mkdir -p tools/user_mods_prev
    cp_clone "$RES/mods" tools/user_mods_prev/mods
    if [ -f "$RES/modsList.txt" ]; then
      cp "$RES/modsList.txt" tools/user_mods_prev/modsList.txt
    fi
    echo "[pre-build] backed up current user mods"
  else
    echo "[pre-build] 已跳过 mods 备份（METEORIC_BACKUP_MODS=$BACKUP_MODS）—— 构建期间不会触碰 $RES/mods"
  fi
else
  BACKUP_MODS=0
fi

# ---- 构建前：单独备份多版本容器（mods/_containers 里是玩家塞进来的整个引擎，体积大）----
# 虽然上面的 mods 备份已包含它，这里额外做一份独立快照：容器目录常达 GB 级，
# 玩家可能清理 tools/user_mods_prev，独立快照能避免“编译一次丢一次容器”。
# 注意：mods 备份 + 恢复（下方 post-build）会整体还原 _containers，本快照只作兜底。
CONTAINERS_SRC="$RES/mods/_containers"
CONTAINERS_SNAP="tools/user_containers_prev"
# 同理受开关控制：容器常驻整个引擎（GB 级），逐次全量拷贝代价不小。
# 目录不存在时引擎侧 ContainerStore.ensureDir() 会自己建空目录，删掉不影响运行。
if [ "${METEORIC_BACKUP_CONTAINERS:-auto}" = "0" ]; then
  echo "[pre-build] 已跳过容器备份（METEORIC_BACKUP_CONTAINERS=0）"
elif [ "${METEORIC_BACKUP_CONTAINERS:-auto}" = "1" ] || [ -d "$CONTAINERS_SRC" ]; then
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

# ---- 构建期 git 信息 → GitInfoData.hx（FPS 显示用）----
# 值烘焙进二进制，运行时零开销。
# ⚠ 不用 Haxe 宏：Codename Engine 的 GitCommitMacro 走 #if macro + sys.io.Process，
#   但本项目有全局自动导入 source/import.hx（内含 import llua.*），llua 在宏上下文
#   引用 cpp.RawPointer 被 Haxe 禁止（"You cannot access the cpp package while in a
#   macro"）→ 只要 import.hx 在，任何宏类都编译失败。故改为脚本生成数据文件。
GITDATA="source/backend/GitInfoData.hx"
_git_num=$(git rev-list HEAD --count 2>/dev/null || echo "")
_git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "")
_git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
_git_dirty=$(git status --porcelain 2>/dev/null | head -1)
[ -n "$_git_num" ] || _git_num=0
[ -n "$_git_hash" ] || _git_hash="-"
[ -n "$_git_branch" ] || _git_branch="-"
_git_dirty_flag="false"
[ -n "$_git_dirty" ] && _git_dirty_flag="true"
python3 - "$GITDATA" "$_git_num" "$_git_hash" "$_git_branch" "$_git_dirty_flag" <<'PYEOF'
import re, sys
path, num, h, br, dirty = sys.argv[1:6]
s = open(path, encoding='utf-8').read()
s = re.sub(r'var commitNumber:Int = -?\d+;', 'var commitNumber:Int = %s;' % num, s)
s = re.sub(r'var commitHash:String = "[^"]*";', 'var commitHash:String = "%s";' % h, s)
s = re.sub(r'var branchName:String = "[^"]*";', 'var branchName:String = "%s";' % br, s)
s = re.sub(r'var dirty:Bool = (true|false);', 'var dirty:Bool = %s;' % dirty, s)
open(path, 'w', encoding='utf-8').write(s)
PYEOF
echo "[compile] git: #$_git_num $_git_hash $_git_branch (dirty=$_git_dirty_flag)"

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
    # ⚠ 排除自身 PID：本脚本命令行含 lime/hxcpp 字面量，`pgrep -f` 会把本脚本自己
    #   当成残留构建进程 → 循环永不退出（与 post-build 同款自匹配 bug）。
    TC_SELF=$$
    for attempt in $(seq 1 12); do
      if ! pgrep -f "haxe.*(lime|hxcpp)|lime.*(build|no-output)|hxcpp.*Build" 2>/dev/null | grep -qvE "^(${TC_SELF}|$$)$"; then break; fi
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
        echo "[typecheck] ⚠ app 内 ndll 命中已知坏指纹（size=$APP_SIZE）→ 用 $NDLL_SRC 覆盖"
        cp "$NDLL_SRC" "$APP_NDLL_TC"
        sleep 2
        continue
      fi

      # ② 与权威墙钟版一致 → 通过
      if cmp -s "$NDLL_SRC" "$APP_NDLL_TC"; then TC_OK=1; break; fi

      # ③ 与备份一致且大小明显不是坏版（可能是另一份墙钟构建）→ 通过
      if cmp -s "$TC_BAK" "$APP_NDLL_TC" && [ "$APP_SIZE" -gt 8000000 ]; then TC_OK=1; break; fi

      # ④ 其余：先还原备份，下一轮再验
      cp "$TC_BAK" "$APP_NDLL_TC"
      sleep 2
    done

    if [ "$TC_OK" = "1" ]; then
      # 同 post-build：不带 --deep 的 codesign 才不会替换 ndll（见下方 post-build 注释）
      codesign --force -s - "export/release/macos/bin/Meteoric.app" 2>/dev/null || true
      sleep 2
      # 签名后再确认一次 —— 旧写法用 --deep 会把 ndll 换回 lime 自带版，
      # 而日志却打印「已还原」，是假成功（实测 2026-10-06）
      if cmp -s "$NDLL_SRC" "$APP_NDLL_TC"; then
        echo "[typecheck] ✓ 已还原墙钟版 lime.ndll (md5: $(md5 -q "$APP_NDLL_TC"), size: $(stat -f%z "$APP_NDLL_TC"))"
      else
        cp "$NDLL_SRC" "$APP_NDLL_TC"
        echo "[typecheck] ✓ 已还原墙钟版 lime.ndll（签名过程替换过，已再次覆盖）size: $(stat -f%z "$APP_NDLL_TC")"
      fi
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

# ---- 架构切换：清空 hxcpp 中间产物 ----
# hxcpp 的 obj 目录名是 obj/darwin64/（只区分位宽与 static_link，不含 CPU 架构），
# 跨架构增量编译会把上一架构的 .o 直接链接进新二进制 → 链接期架构混用报错，
# 或更糟：静默产出畸形 Mach-O。因此检测到架构变化就整体清空。
ARCH_STAMP="export/release/macos/.last-arch"
mkdir -p "$(dirname "$ARCH_STAMP")"
if [ -f "$ARCH_STAMP" ] && [ "$(cat "$ARCH_STAMP")" != "$TARGET_ARCH" ]; then
  echo "[pre-build] 架构切换 $(cat "$ARCH_STAMP") → $TARGET_ARCH：清空 hxcpp obj（目录名不含架构，会混用 .o）"
  rm -rf export/release/macos/obj
fi
echo "$TARGET_ARCH" > "$ARCH_STAMP"
echo "[pre-build] 目标架构 $TARGET_ARCH（ndll: $NDLL_SRC）"

# Meteoric: 脚本类 extends 引擎类（壳类宏）—— 默认关闭，METEORIC_CUSTOM_CLASSES=1 开启
CUSTOM_CLASSES_FLAG=""
if [ "${METEORIC_CUSTOM_CLASSES:-0}" = "1" ]; then
  CUSTOM_CLASSES_FLAG="-DCUSTOM_CLASSES"
  echo "[compile] CUSTOM_CLASSES：启用脚本类 extends 引擎类（壳类白名单见 hscript-macros/hscript/macros/ClassExtendMacro.hx）"
fi

if [ "$1" = "test" ]; then
  haxelib run lime test macos -release $ARCH_FLAG $PROFILE_DEFINE $DEBUG_FLAGS $CUSTOM_CLASSES_FLAG
else
  haxelib run lime build macos -release $ARCH_FLAG $PROFILE_DEFINE $DEBUG_FLAGS $CUSTOM_CLASSES_FLAG
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
STABLE_NDLL="$NDLL_SRC"
APP_NDLL="export/release/macos/bin/Meteoric.app/Contents/MacOS/lime.ndll"
echo "[post-build] waiting for lime/hxcpp tail processes to finish..."
# ⚠ 必须排除自身 PID：本脚本的命令行里含 lime/hxcpp 等字面量（见上面的构建调用），
#   `pgrep -f` 匹配完整命令行 → 会把**本脚本自己**当成残留构建进程，
#   循环永远不退出，post-build 每次空等满 30×5=150 秒（实测卡死 8 分钟）。
#   `pgrep` 无匹配时返回 1，所以这里用 `pgrep -v "^($$)$"` 反选自身之外的命中。
SELF_PID=$$
for attempt in $(seq 1 30); do
  # 只看真正在跑的编译器：排除本脚本自身，以及 pgrep 自己的瞬时进程
  if ! pgrep -f "haxe.*(lime|hxcpp)|lime.*(build|test)|hxcpp.*Build" 2>/dev/null | grep -qvE "^(${SELF_PID}|$$)$"; then
    break
  fi
  sleep 5
done
sleep 3
if [ -f "$STABLE_NDLL" ] && [ -f "$APP_NDLL" ]; then
  # ---- 墙钟版 ndll 现在是「性能加成」而非「正确性前提」----
  # Main.hx 的启动帧率已改为 ClientPrefs.unlimitedFramerateValue()（与 Windows 统一）：
  # 启动时读 lime.ndll 内容里的 SDL3_DYNAMIC_API 标记判断有没有墙钟补丁，
  # 有 → 100000（无人工限制），没有 → 1000（老 ndll 上的安全上限）。
  # 因此**即使本步骤失败或被跳过**，引擎也只会退到 1000 帧上限运行，
  # 不会再出现「老 ndll + 100000 → 启动黑屏死循环」。这才是真正"甩掉墙钟依赖"。
  #
  # 顺序：先拷贝、再签名（不带 --deep）。带签名的 ndll 与未签名参考无法逐字节比对
  # （codesign 改写 Mach-O 头的 LC_CODE_SIGNATURE），故只校验签名有效 + 架构匹配。
  # 签名顺序（实测 2026-10-06）：必须**先签 ndll、再签主程序、最后签 bundle**。
  # 只签 bundle 会留下 "code object is not signed at all / In subcomponent: lime.ndll"
  # —— 拷进来的 ndll 是独立代码对象，需要单独签名。只签一次 bundle 不会递归处理它。
  #
  # ⚠ 绝对不要加 --deep：它会用 ndll 目录里 lime 自带的版本覆盖掉刚拷进来的
  #   墙钟版/PNG decodeScale 版（--recursive 重新签名整个 bundle 的子组件），
  #   于是 frame_loop 补丁与解码期缩放原语一起消失，老 ndll + 100000 帧哨兵
  #   → 启动即 100% CPU 死循环。三层分开签（ndll → 主程序 → bundle）即可。
  cp "$STABLE_NDLL" "$APP_NDLL"
  sleep 2
  # ---- 迭代模式：跳过 bundle 层签名 ----
  # bundle 里塞了 79GB 的 mod 谱面数据（stupid-griefer 66 个 Part），codesign 要把
  # 整个 resources 哈希一遍：实测单是「签主程序」就要 30 分钟以上且会被 shell 的 idle
  # 超时砍在半写状态。但终端直接 ./Meteoric 启动只需要 Mach-O 自身的签名 ——
  # 链接器自带的 ad-hoc（linker-signed）已足够，实测可正常进游戏。
  # 只有要分发给别人时才需要完整三层签名。
  if [ "$METEORIC_SKIP_CODESIGN" = "1" ]; then
    echo "[post-build] ⚠ METEORIC_SKIP_CODESIGN=1：跳过签名（仅供本地迭代，勿分发）"
  else
  codesign --force -s - "export/release/macos/bin/Meteoric.app/Contents/MacOS/lime.ndll" 2>/dev/null || true
  codesign --force -s - "export/release/macos/bin/Meteoric.app/Contents/MacOS/Meteoric" 2>/dev/null || true
  codesign --force -s - "export/release/macos/bin/Meteoric.app" 2>/dev/null || true
  fi
  sleep 2
  # 判据：三层签名各自有效 + ndll 架构与主程序一致 + 补丁符号在位。
  # 不再用「尺寸 ≥ 参考」判断 —— ad-hoc 签名会**改写** Mach-O 的 LC_CODE_SIGNATURE，
  # 签完的 ndll 反而比未签名的参考小（arm64 实测 8283872 → 8253840），
  # `-ge` 在 arm64 上恒假 → 每轮都误报「签名未完全成功」（实测 2026-10-12）。
  REF_ARCH=$(lipo -archs "$STABLE_NDLL" 2>/dev/null)
  APP_ARCH=$(lipo -archs "$APP_NDLL" 2>/dev/null)
  MAIN_ARCH=$(lipo -archs "export/release/macos/bin/Meteoric.app/Contents/MacOS/Meteoric" 2>/dev/null)
  if codesign -v "export/release/macos/bin/Meteoric.app" >/dev/null 2>&1 \
     && codesign -v "$APP_NDLL" >/dev/null 2>&1 \
     && [ "$REF_ARCH" = "$APP_ARCH" ] && [ "$APP_ARCH" = "$MAIN_ARCH" ]; then
      echo "[post-build] ✓ 签名有效（bundle/主程序/ndll 三层）+ $NDLL_SRC 已就位 (arch: $APP_ARCH)"
  else
      echo "[post-build] ⚠ 签名或 ndll 还原未完全成功（ndll arch=$APP_ARCH / 主程序 arch=$MAIN_ARCH / 参考=$REF_ARCH）"
      echo "[post-build]    非致命：引擎会按 SDL3_DYNAMIC_API 标记自动回退 1000 帧档运行。"
  fi
else
  echo "[post-build] ⚠ 找不到 $STABLE_NDLL 或产物 ndll，跳过墙钟版还原（引擎自动回退 1000 帧档）"
fi

# ---- 恢复用户 mods（lime 构建会重置 Resources，用户装过的 mod 会丢）----
# 先删掉目标 mods 目录再拷贝：cp -R 目标已存在时会嵌套成 mods/mods/，
# 被 updateModList 扫成名为 "mods" 的假模组（用户看到的"永远有一个 mods 模组"）。
# ⚠ 与 pre-build 同一个开关：跳过备份时这里必须整体跳过。
#   否则下面的 `rm_force "$RES/mods"` 会删掉玩家的 mods 却没有东西可恢复。
MODS_SRC=""
if [ "$BACKUP_MODS" = "1" ]; then
  MODS_SRC="tools/user_mods_prev"
  if [ ! -d "$MODS_SRC/mods" ]; then
    MODS_SRC="tools/user_mods" # 首次构建回退快照
  fi
else
  echo "[post-build] 跳过 mods 还原（pre-build 未备份）"
fi
if [ -n "$MODS_SRC" ] && [ -d "$MODS_SRC/mods" ]; then
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

