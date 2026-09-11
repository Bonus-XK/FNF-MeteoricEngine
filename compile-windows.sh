#!/bin/sh
# Meteoric Engine Windows 交叉编译脚本 (macOS -> Windows, -release)
# 用法: ./compile-windows.sh          # 正式构建（不含调试诊断）
#       ./compile-windows.sh -debug   # 调试构建（启用 [FRAMERATE] 等启动诊断输出）
set -e
cd "$(dirname "$0")"

# ---- 调试模式 ----
# 传 -debug（或环境变量 METEORIC_DEBUG=1）时定义 `meteoric_debug`，启用源码里
# 挂在 #if meteoric_debug 下的启动诊断（目前是 TitleState 的 [FRAMERATE] 行）。
# 正式构建不定义它 → 那些代码不编译进去，零开销、控制台也干净。
#
# ⚠ 这里刻意**不加** Haxe 的 `-debug`：它会定义 `debug` 符号，改变 CrashHandler 的
#   编译分支，导致 `source/Main.hx:476` 报
#   `Class<backend.CrashHandler> has no field installNativeHandlers`（实测踩过）。
#   诊断只需要 `-D meteoric_debug` 这一个自定义 define。
DEBUG_FLAGS=""
case "${1:-}" in
  -debug|--debug) DEBUG_FLAGS="-D meteoric_debug" ;;
esac
if [ "${METEORIC_DEBUG:-0}" = "1" ]; then
  DEBUG_FLAGS="-D meteoric_debug"
fi
if [ -n "$DEBUG_FLAGS" ]; then
  echo "[compile] 调试构建：启用 meteoric_debug 诊断输出"
fi

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

# mingw-w64 交叉编译工具链（Homebrew）
for m in /opt/homebrew/opt/mingw-w64/bin /usr/local/opt/mingw-w64/bin; do
  if [ -d "$m" ]; then
    export PATH="$m:$PATH"
    break
  fi
done

if ! command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
  echo "错误：未找到 x86_64-w64-mingw32-g++。"
  echo "请先安装: brew install mingw-w64"
  exit 1
fi

NDLL="export/release/windows/bin/lime.ndll"

# ---------------------------------------------------------------------------
# 【2026-09-11 事故防线】lime.ndll 必须带「墙钟帧循环补丁」
# ---------------------------------------------------------------------------
# 背景：本脚本只跑 `lime build`，**不会重建 lime.ndll**（原生库由 CI 的
#   “重建 lime Windows ndll” 步骤或 ci/setup-lime-sdl3.sh + hxcpp 产出）。
#   于是本地构建会把 haxelib 发行版里的**老 ndll** 原样打进交付包 —— 64 位包
#   长期如此（8,281,088 字节、无 SDL3 标记、无墙钟补丁）。而引擎的「无上限」
#   档位需要 100000 哨兵，配上老 ndll 会在启动阶段 100% 死循环、黑屏卡加载界面。
#
# 防线两层：
#   ① 装包后自检：用引擎启动时用的同一个判据（原生 cffi 原语
#      lime_meteoric_frame_loop_patch 的导出符号）确认补丁在位；
#   ② 不通过就**警告并退出 1**：宁可不出包，也不交付一个"选无上限就黑屏"的包。
#      （引擎侧另有运行时兜底：探测不到补丁自动退回 480，不会死循环。）
# ---------------------------------------------------------------------------
verify_ndll() {
  [ -f "$NDLL" ] || { echo "[verify] 错误：找不到 $NDLL"; return 1; }
  # 用 objdump -p 查**导出表**：marker 是纯 C 导出符号，`nm -g` 只看符号表，
  # 在 strip 过/带导出表的 DLL 上会漏判（实测踩过）。
  if x86_64-w64-mingw32-objdump -p "$NDLL" 2>/dev/null | grep -q 'lime_meteoric_frame_loop_patch'; then
    echo "[verify] lime.ndll 带墙钟帧循环补丁（$(stat -f%z "$NDLL") 字节，md5 $(md5 -q "$NDLL")）"
    return 0
  fi
  cat <<'WARN'
[verify] ⚠ 警告：本次产出的 lime.ndll **不带**墙钟帧循环补丁（导出表里没有
         lime_meteoric_frame_loop_patch 符号）。

         这通常是重建树 /tmp/lime-full 缺 SDL3 源码或没打 ci/lime-sdl3-patch 导致的。
         请在构建机上重建原生库（与 CI windows job 同款命令）：

             bash ci/setup-lime-sdl3.sh                       # 组装 /tmp/lime-full
             cd /tmp/lime-full/project
             haxelib run hxcpp Build.xml -Dwindows -DHXCPP_M64 -Dlime-openal -Dlime-curl \
               -Dlime-harfbuzz -Dlime-cairo -Dlime-opengl -Dlime-vorbis -Dlime-cffi \
               -Dlime-threads -Dnative -Dtools=8.2.2 -Drebuild=1 -Dlime-native -Dmingw

         引擎侧有兜底（无补丁时「无上限」自动退回 480，不会黑屏），所以本包**能用**，
         只是拿不到"无上限"的真实帧率。按需决定是否重出包。
WARN
  return 1
}

haxelib run lime build windows -release -mingw $DEBUG_FLAGS

# ---------------------------------------------------------------------------
# 构建后恢复「墙钟补丁版」lime.ndll（与 compile-mac.sh 恢复 tools/lime.ndll.wallclock 同款）
# ---------------------------------------------------------------------------
# 必须做这一步的原因（2026-09-11 实测复现）：`lime build` 会从 haxelib 发行版目录
# （…/lime/8,2,2/ndll/Windows/lime.ndll）把**老 ndll** 原样拷进产物目录，覆盖掉我们
# 预先放好的补丁版 —— 这正是"64 位交付包长期带老 ndll"的机制，也是「无上限」档位
# 当初被摘掉的起因。恢复用的二进制由 `bash ci/build-lime-win64-ndll.sh` 产出并存放于
# tools/lime.ndll.win64.wallclock。
PATCHED_NDLL="tools/lime.ndll.win64.wallclock"
if [ -f "$PATCHED_NDLL" ]; then
  cp "$PATCHED_NDLL" "$NDLL"
  echo "[post-build] restored wallclock lime.ndll  (md5: $(md5 -q "$NDLL"), $(stat -f%z "$NDLL") bytes)"
else
  echo "[post-build] 注意：未找到 $PATCHED_NDLL，跳过恢复（引擎侧会自动退回 480 档，不会黑屏）"
fi

verify_ndll || exit 1
