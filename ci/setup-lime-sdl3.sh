#!/bin/bash
# ============================================================
# 构建 SDL3 版 lime（在 CI 环境准备 /tmp/lime-full）
# 用法: bash ci/setup-lime-sdl3.sh
# 依赖: git curl tar haxelib（haxe/neko 已装）
# ============================================================
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LIME_DIR=/tmp/lime-full

echo "==> [1/6] clone lime 8.2.2 源码（含 submodule 库）"
rm -rf "$LIME_DIR" /tmp/SDL-release-3.2.8 /tmp/sdl3.tar.gz
git clone --depth 1 --branch 8.2.2 --recurse-submodules https://github.com/openfl/lime.git "$LIME_DIR"

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
fetch_lib() { # $1=目标目录  $2=URL
  local dir="$1" url="$2"
  rm -rf "$dir"
  git clone --depth 1 "$url" "$dir"
}

# pixman 0.46.4
fetch_lib "$LIME_DIR/project/lib/pixman" "https://gitlab.freedesktop.org/pixman/pixman.git"
(cd "$LIME_DIR/project/lib/pixman" && git checkout pixman-0.46.4 2>/dev/null || true)
# cairo 1.18.2
fetch_lib "$LIME_DIR/project/lib/cairo" "https://gitlab.freedesktop.org/cairo/cairo.git"
(cd "$LIME_DIR/project/lib/cairo" && git checkout 1.18.2 2>/dev/null || true)
# harfbuzz 8.2.0
fetch_lib "$LIME_DIR/project/lib/harfbuzz" "https://github.com/harfbuzz/harfbuzz.git"
(cd "$LIME_DIR/project/lib/harfbuzz" && git checkout 8.2.0 2>/dev/null || true)
# openal-soft 1.20.1
fetch_lib "$LIME_DIR/project/lib/openal" "https://github.com/kcat/openal-soft.git"
(cd "$LIME_DIR/project/lib/openal" && git checkout openal-soft-1.20.1 2>/dev/null || true)
# curl 7.88.1
fetch_lib "$LIME_DIR/project/lib/curl" "https://github.com/curl/curl.git"
(cd "$LIME_DIR/project/lib/curl" && git checkout curl-7_88_1 2>/dev/null || true)
# efsw 1.6.3
fetch_lib "$LIME_DIR/project/lib/efsw" "https://github.com/SpartanJ/efsw.git"
(cd "$LIME_DIR/project/lib/efsw" && git checkout 1.6.3 2>/dev/null || true)

echo "==> [4/6] 获取 SDL3 release-3.2.8 源码并替换"
curl -sL https://github.com/libsdl-org/SDL/archive/refs/tags/release-3.2.8.tar.gz -o /tmp/sdl3.tar.gz
tar xzf /tmp/sdl3.tar.gz -C /tmp
rm -rf "$LIME_DIR/project/lib/sdl"
mv /tmp/SDL-release-3.2.8 "$LIME_DIR/project/lib/sdl"
# 应用 SDL_build_config.h 定制（三平台驱动宏）
cp ci/lime-sdl3-patch/project/lib/sdl/src/SDL_build_config.h "$LIME_DIR/project/lib/sdl/src/SDL_build_config.h"
cp ci/lime-sdl3-patch/project/lib/sdl/include/SDL3/SDL_build_config.h "$LIME_DIR/project/lib/sdl/include/SDL3/SDL_build_config.h"
# freetype ftmodule.h 定制（去掉 hvf 驱动）
cp ci/lime-sdl3-patch/project/lib/freetype/include/freetype/config/ftmodule.h "$LIME_DIR/project/lib/freetype/include/freetype/config/ftmodule.h"

echo "==> [5/6] SDL3 Android Java 壳（org/libsdl/app）"
rm -rf "$LIME_DIR/templates/android/template/app/src/main/java/org/libsdl"
mkdir -p "$LIME_DIR/templates/android/template/app/src/main/java/org/libsdl"
cp -R "$LIME_DIR/project/lib/sdl/android-project/app/src/main/java/org/libsdl/app" \
      "$LIME_DIR/templates/android/template/app/src/main/java/org/libsdl/"

echo "==> [6/6] haxelib dev 指向"
haxelib dev lime "$LIME_DIR"

echo "==> SDL3 lime 就绪: $LIME_DIR"
