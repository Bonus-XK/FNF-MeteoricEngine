#!/bin/bash
# ============================================================
# 构建 SDL3 版 lime（在 CI 环境准备 /tmp/lime-full）
# 用法: bash ci/setup-lime-sdl3.sh
# 依赖: git curl tar haxelib（haxe/neko 已装）
#
# 网络加速: GitHub 源默认走 GH_PROXY（gh.xmly.dev 等 ghproxy 类服务，
#   用法 = 前缀 + 原始 URL）。CI 直连请在调用时传 GH_PROXY=""（见 build.yml）。
#   gitlab.freedesktop.org 源不支持加速，保持直连 + 失败重试。
# ============================================================
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LIME_DIR=/tmp/lime-full

# GitHub 加速前缀（环境变量可覆盖；设为空 = 直连）
GH_PROXY="${GH_PROXY:-https://gh.xmly.dev/}"

# gitlab.freedesktop.org 的 HTTP/2 流不稳定（PROTOCOL_ERROR/early EOF），强制 HTTP/1.1
git config --global http.version HTTP/1.1 2>/dev/null || true

# 返回加速后的 URL：github 加前缀；gitlab 直连
proxy_url() {
  case "$1" in
    https://github.com/*) [ -n "$GH_PROXY" ] && echo "${GH_PROXY}${1}" || echo "$1" ;;
    *) echo "$1" ;;
  esac
}

echo "==> [1/6] clone lime 8.2.2 源码（含 submodule 库，走 ${GH_PROXY:-直连}）"
rm -rf "$LIME_DIR" /tmp/SDL-release-3.2.8 /tmp/sdl3.tar.gz
git clone --depth 1 --branch 8.2.2 "$(proxy_url https://github.com/openfl/lime.git)" "$LIME_DIR"
# 子模块 URL 全部改走加速（.gitmodules 里是原始 github/gitlab 地址）
if [ -n "$GH_PROXY" ]; then
  while IFS= read -r line; do
    case "$line" in
      '[submodule '*)
        smpath="${line#\[submodule \"}"; smpath="${smpath%\"\]}" ;;
      '	url = '*)
        smurl="${line#*url = }"
        smnew=$(proxy_url "$smurl")
        if [ "$smnew" != "$smurl" ]; then
          git -C "$LIME_DIR" config "submodule.$smpath.url" "$smnew"
        fi ;;
    esac
  done < "$LIME_DIR/.gitmodules"
fi
# cairo/pixman 只有 gitlab 源（无 GitHub 镜像，直连慢）：
# 从子模块体系完全移除（gitlink + 配置 + .gitmodules），
# 改由第 3 步 fetch_lib_url 用 cairographics.org 发布包下载
git -C "$LIME_DIR" rm --cached -f project/lib/cairo project/lib/pixman 2>/dev/null || true
for sm in project/lib/cairo project/lib/pixman; do
  git -C "$LIME_DIR" config --remove-section "submodule.$sm" 2>/dev/null || true
  git -C "$LIME_DIR" config -f .gitmodules --remove-section "submodule.$sm" 2>/dev/null || true
done
git -C "$LIME_DIR" submodule update --init --depth 1 --recursive || true
echo "子模块拉取完成（cairo/pixman 由第 3 步 fetch_lib_url 下载）"

echo "==> [2/6] 应用 SDL3 定制补丁（ci/lime-sdl3-patch）"
cp -R ci/lime-sdl3-patch/project/Build.xml "$LIME_DIR/project/Build.xml"
cp -R ci/lime-sdl3-patch/project/lib/*-files.xml "$LIME_DIR/project/lib/"
cp -R ci/lime-sdl3-patch/project/lib/custom/* "$LIME_DIR/project/lib/custom/"
cp -R ci/lime-sdl3-patch/project/include/system/System.h "$LIME_DIR/project/include/system/System.h"
cp -R ci/lime-sdl3-patch/project/src/backend/sdl/* "$LIME_DIR/project/src/backend/sdl/"
cp -R ci/lime-sdl3-patch/project/src/system/FileWatcher.cpp "$LIME_DIR/project/src/system/FileWatcher.cpp"
cp -R ci/lime-sdl3-patch/project/src/graphics/opengl/OpenGL.h "$LIME_DIR/project/src/graphics/opengl/OpenGL.h"
cp -R ci/lime-sdl3-patch/tools/platforms/WindowsPlatform.hx "$LIME_DIR/tools/platforms/WindowsPlatform.hx"
cp -R ci/lime-sdl3-patch/templates/android/template/app/src/main/java/org/haxe/lime/GameActivity.java "$LIME_DIR/templates/android/template/app/src/main/java/org/haxe/lime/GameActivity.java"

echo "==> [3/6] 对齐定制库版本（pixman/cairo/harfbuzz/openal/curl/efsw）"
# 注意：浅克隆（--depth 1）后 checkout tag 会失败（tag 不在浅历史），
# 必须用 --branch 直接拉指定 tag；网络不稳定，失败自动重试
fetch_lib() { # $1=目标目录  $2=URL（已加速）  $3=tag
  local dir="$1" url="$2" tag="$3" i
  for i in 1 2 3 4 5; do
    rm -rf "$dir"
    if [ -n "$tag" ]; then
      git clone --depth 1 --branch "$tag" "$url" "$dir" 2>/dev/null && return 0
    else
      git clone --depth 1 "$url" "$dir" 2>/dev/null && return 0
    fi
    echo "拉取 $url 失败（第 $i 次），5 秒后重试..."
    sleep 5
  done
  echo "拉取 $url 最终失败"
  return 1
}

fetch_lib "$LIME_DIR/project/lib/harfbuzz"  "$(proxy_url https://github.com/harfbuzz/harfbuzz.git)" 8.2.0
fetch_lib "$LIME_DIR/project/lib/openal"    "$(proxy_url https://github.com/kcat/openal-soft.git)" openal-soft-1.20.1
fetch_lib "$LIME_DIR/project/lib/curl"      "$(proxy_url https://github.com/curl/curl.git)" curl-7_88_1
fetch_lib "$LIME_DIR/project/lib/efsw"      "$(proxy_url https://github.com/SpartanJ/efsw.git)" 1.6.3

# cairo/pixman 用官方发布站 cairographics.org 的 release 压缩包下载
# （gitlab.freedesktop.org 直连在本机网络下持续断流，不可用）
# curl -C - 断点续传 + tar 完整性校验，中断后从断点继续
fetch_lib_url() { # $1=目标目录  $2=URL
  local dir="$1" url="$2" i extracted
  rm -rf "$dir" /tmp/fetchlib-tar
  mkdir -p /tmp/fetchlib-tar
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sL -C - --max-time 1200 "$url" -o /tmp/fetchlib-tar/lib.tar \
       && tar tf /tmp/fetchlib-tar/lib.tar > /dev/null 2>&1; then
      tar xf /tmp/fetchlib-tar/lib.tar -C /tmp/fetchlib-tar
      extracted=$(find /tmp/fetchlib-tar -mindepth 1 -maxdepth 1 -type d | head -1)
      if [ -n "$extracted" ]; then
        mv "$extracted" "$dir"
        echo "已下载: $url"
        return 0
      fi
    fi
    echo "下载 $url 中断（第 $i 次），5 秒后续传..."
    sleep 5
  done
  echo "下载 $url 最终失败"
  return 1
}

fetch_lib_url "$LIME_DIR/project/lib/cairo"  "https://www.cairographics.org/releases/cairo-1.18.2.tar.xz"
fetch_lib_url "$LIME_DIR/project/lib/pixman" "https://www.cairographics.org/releases/pixman-0.46.4.tar.gz"

echo "==> [4/6] 获取 SDL3 release-3.2.8 源码并替换"
curl -sL "$(proxy_url https://github.com/libsdl-org/SDL/archive/refs/tags/release-3.2.8.tar.gz)" -o /tmp/sdl3.tar.gz
tar xzf /tmp/sdl3.tar.gz -C /tmp
rm -rf "$LIME_DIR/project/lib/sdl"
mv /tmp/SDL-release-3.2.8 "$LIME_DIR/project/lib/sdl"
# 应用 SDL_build_config.h 定制（三平台驱动宏）
cp ci/lime-sdl3-patch/project/lib/sdl/src/SDL_build_config.h "$LIME_DIR/project/lib/sdl/src/SDL_build_config.h"
cp ci/lime-sdl3-patch/project/lib/sdl/include/SDL3/SDL_build_config.h "$LIME_DIR/project/lib/sdl/include/SDL3/SDL_build_config.h"
# freetype ftmodule.h 定制（去掉 hvf 驱动）
cp ci/lime-sdl3-patch/project/lib/freetype/include/freetype/config/ftmodule.h "$LIME_DIR/project/lib/freetype/include/freetype/config/ftmodule.h"
# libpng pngpriv.h 定制：新版 macOS SDK（Xcode 16+/SDK 26+）系统头默认定义
# TARGET_OS_MAC，会触发 pngpriv.h 的老 Mac <fp.h> 分支导致编译失败 → 移除该条件
cp ci/lime-sdl3-patch/project/lib/png/pngpriv.h "$LIME_DIR/project/lib/png/pngpriv.h"
# zlib zutil.h 定制：同上，TARGET_OS_MAC 触发老 Mac 分支定义 fdopen 宏，
# 与新版 SDK 的 <stdio.h> fdopen 声明冲突 → 禁用该宏
cp ci/lime-sdl3-patch/project/lib/zlib/zutil.h "$LIME_DIR/project/lib/zlib/zutil.h"

echo "==> [5/6] SDL3 Android Java 壳（org/libsdl/app）"
rm -rf "$LIME_DIR/templates/android/template/app/src/main/java/org/libsdl"
mkdir -p "$LIME_DIR/templates/android/template/app/src/main/java/org/libsdl"
cp -R "$LIME_DIR/project/lib/sdl/android-project/app/src/main/java/org/libsdl/app" \
      "$LIME_DIR/templates/android/template/app/src/main/java/org/libsdl/"

echo "==> [6/7] 使用 haxelib 发行版 tools.n（git 源码不含；发行版 tools.n 的 optional-cffi 在无 lime.ndll 时正常 fallback）"
HAXELIB_LIME=$(ls -d "$HOME/haxelib/lime/8,2,2" 2>/dev/null || ls -d /usr/local/lib/haxe/lib/lime/8,2,2 2>/dev/null)
if [ -f "$HAXELIB_LIME/tools/tools.n" ]; then
  cp "$HAXELIB_LIME/tools/tools.n" "$LIME_DIR/tools/tools.n"
  echo "已复制: $HAXELIB_LIME/tools/tools.n"
else
  echo "警告: 未找到发行版 tools.n，尝试编译"
  (cd "$LIME_DIR/tools" && haxe tools.hxml)
fi

echo "==> [7/8] 拷贝发行版预编译 ndll（git 源码不含二进制 ndll；tools 处理图标/图像需要 host 版 lime.ndll）"
if [ -d "$HAXELIB_LIME/ndll" ]; then
  cp -R "$HAXELIB_LIME/ndll/." "$LIME_DIR/ndll/"
  echo "已拷贝: $HAXELIB_LIME/ndll → $LIME_DIR/ndll/（后续 rebuild 会覆盖目标平台）"
else
  echo "警告: 未找到发行版 ndll 目录（$HAXELIB_LIME/ndll）"
fi

echo "==> [8/8] haxelib dev 指向"
haxelib dev lime "$LIME_DIR"

echo "==> SDL3 lime 就绪: $LIME_DIR"
