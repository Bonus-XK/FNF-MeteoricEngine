#!/bin/bash
# ============================================================
# 重建 64 位 Windows 用的「墙钟补丁版」lime.ndll（在 macOS 上交叉编译）
# 用法: bash ci/build-lime-win64-ndll.sh
#
# 产物: tools/lime.ndll.win64.wallclock
#       （compile-windows.sh 会在 `lime build` 之后把它恢复进产物目录 ——
#         lime 构建会拿 haxelib 发行版里的老 ndll 覆盖产物，这是 64 位包长期
#         带老 ndll、「无上限」档位被摘掉的根因）
#
# 为什么需要这个脚本 / 这些参数（每一条都是实测踩出来的，别凭直觉改）：
#   1) 必须先跑 ci/setup-lime-sdl3.sh 组装 /tmp/lime-full（SDL3 源码 + 全部 pinned
#      依赖），再在它上面编。haxelib 发行版的 lime 树没有 project/src 与 project/lib。
#   2) **不加 -Dstatic_link**：加它会编译出静态库 liblime.a 而不是 lime.ndll，而引擎
#      是通过 `<ndll name="lime">` 动态加载 lime.ndll 的，静态库对交付无用。
#   3) 不能给 Lime 源码注册 cffi 原语（DEFINE_PRIME*）：hxcpp 规定一个模块只能有一次
#      且需 IMPLEMENT_API，而 src/ExternalInterface.cpp 已占用；多一个就报一大片
#      multiple definition of `hx_register_prim'。能力标记改为纯 C 导出符号。
#   4) **-Dmeteoric_no_mojoal**：lime 的 Build.xml 在 static_link/switch/winrt 下会选
#      mojoal 作音频后端，而 mojoal 是为 SDL2 写的（`#include "SDL.h"` + SDL2 音频 API），
#      本项目已换 SDL3 → 编译必然失败。该开关让它回到 openal-soft（交付包一直用的后端）。
#   5) CI 的 Windows job 若仍用 -Dstatic_link 编译原生库，会产出 liblime.a；请以
#      artifacts 里实际交付的 lime.ndll 为准（本脚本产出的就是可直接交付/替换的那份）。
# ============================================================
set -e
cd "$(dirname "$0")/.."

LIME_DIR="${LIME_DIR:-/tmp/lime-full}"
NDLL_OUT="tools/lime.ndll.win64.wallclock"

# ---- 环境（与 compile-windows.sh 对齐）----
if [ -f "$HOME/.zprofile" ]; then . "$HOME/.zprofile" 2>/dev/null || true; fi
if [ ! -d "$NEKOPATH" ] || [ ! -f "$NEKOPATH/std.ndll" ]; then
  for p in /usr/local/lib/neko /opt/homebrew/lib/neko; do
    if [ -f "$p/std.ndll" ]; then export NEKOPATH="$p"; break; fi
  done
fi
for m in /opt/homebrew/opt/mingw-w64/bin /usr/local/opt/mingw-w64/bin; do
  if [ -d "$m" ]; then export PATH="$m:$PATH"; break; fi
done
export MINGW_ROOT="${MINGW_ROOT:-/opt/homebrew/opt/mingw-w64/toolchain-x86_64/x86_64-w64-mingw32}"

if ! command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
  echo "错误：未找到 x86_64-w64-mingw32-g++（brew install mingw-w64）"; exit 1
fi

# ---- 1) 组装补丁树 ----
if [ ! -f "$LIME_DIR/project/src/backend/sdl/SDLApplication.cpp" ]; then
  echo "==> $LIME_DIR 缺 SDL3 源码，先跑 ci/setup-lime-sdl3.sh 组装"
  bash ci/setup-lime-sdl3.sh
else
  echo "==> 复用已组装的 $LIME_DIR"
  # 已组装过的树也要重打补丁：补丁内容会随仓库更新（本次就新增了能力标记文件）
  cp ci/lime-sdl3-patch/project/Build.xml "$LIME_DIR/project/Build.xml"
  cp ci/lime-sdl3-patch/project/lib/*-files.xml "$LIME_DIR/project/lib/"
  cp -R ci/lime-sdl3-patch/project/src/backend/sdl/* "$LIME_DIR/project/src/backend/sdl/"
  echo "    已重新应用 ci/lime-sdl3-patch"
fi

# ---- 2) 编译 lime.ndll（x64；参数理由见文件头）----
echo "==> 交叉编译 64 位 lime.ndll"
cd "$LIME_DIR/project"
export PATH="$NEKOPATH:$PATH"
haxelib run hxcpp Build.xml \
  -Dwindows -DHXCPP_M64 -Dmeteoric_no_mojoal \
  -Dlime-openal -Dlime-curl -Dlime-harfbuzz -Dlime-cairo -Dlime-opengl \
  -Dlime-vorbis -Dlime-cffi -Dlime-threads \
  -Dnative -Dtools=8.2.2 -Drebuild=1 -Dlime-native -Dmingw
cd - >/dev/null

BUILT="$LIME_DIR/ndll/Windows64/lime.ndll"
[ -f "$BUILT" ] || { echo "错误：没有产出 $BUILT"; exit 1; }

# ---- 3) 校验能力标记确实导出（引擎启动自检用的就是这个符号）----
echo "==> 校验导出符号 lime_meteoric_frame_loop_patch"
if ! x86_64-w64-mingw32-objdump -p "$BUILT" 2>/dev/null | grep -q 'lime_meteoric_frame_loop_patch'; then
  echo "错误：产物里没有能力标记符号 —— 说明补丁没进这次构建，拒绝落位"
  exit 1
fi

mkdir -p "$(dirname "$NDLL_OUT")"
cp "$BUILT" "$NDLL_OUT"
echo "==> 完成：$NDLL_OUT"
echo "    $(stat -f%z "$NDLL_OUT") bytes   md5 $(md5 -q "$NDLL_OUT")"
echo "    下一步：./compile-windows.sh（会在构建后自动恢复这份 ndll 并校验）"
