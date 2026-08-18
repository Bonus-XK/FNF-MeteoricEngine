#!/bin/bash
# ============================================================
# CI 安装 Haxe 4.2.5 + Neko 2.3.0 + Haxe 标准库
# 安装到 $HOME（runner 普通用户对 /opt 无写权限）
# 支持: Linux x86_64 / macOS（arm64 runner 上以 Rosetta 跑 x86_64）
# 用法: bash ci/setup-haxe-ci.sh
# ============================================================
set -e

HAXE_DIR="$HOME/haxe"
NEKO_DIR="$HOME/neko"
STD_DIR="$HOME/haxe-std"

case "$(uname -s)" in
  Linux)
    HAXE_URL="https://github.com/HaxeFoundation/haxe/releases/download/4.2.5/haxe-4.2.5-linux64.tar.gz"
    NEKO_URL="https://github.com/HaxeFoundation/neko/releases/download/v2-3-0/neko-2.3.0-linux64.tar.gz"
    ;;
  Darwin)
    HAXE_URL="https://github.com/HaxeFoundation/haxe/releases/download/4.2.5/haxe-4.2.5-osx.tar.gz"
    NEKO_URL="https://github.com/HaxeFoundation/neko/releases/download/v2-3-0/neko-2.3.0-osx64.tar.gz"
    ;;
  *)
    echo "不支持的平台: $(uname -s)"; exit 1 ;;
esac

echo "==> 下载 Haxe 4.2.5 -> $HAXE_DIR"
rm -rf "$HAXE_DIR" && mkdir -p "$HAXE_DIR"
curl -sL "$HAXE_URL" | tar xz -C "$HAXE_DIR" --strip-components=1
chmod +x "$HAXE_DIR/haxe" "$HAXE_DIR/haxelib"

echo "==> 下载 Neko 2.3.0 -> $NEKO_DIR"
rm -rf "$NEKO_DIR" && mkdir -p "$NEKO_DIR"
curl -sL "$NEKO_URL" | tar xz -C "$NEKO_DIR" --strip-components=1
chmod +x "$NEKO_DIR/neko"

echo "==> 下载 Haxe 标准库（std/，官方二进制包不含）"
rm -rf "$STD_DIR" && mkdir -p "$STD_DIR"
curl -sL "https://github.com/HaxeFoundation/haxe/archive/refs/tags/4.2.5.tar.gz" -o /tmp/haxe-src.tar.gz
tar xzf /tmp/haxe-src.tar.gz -C "$STD_DIR" --strip-components=1

echo "==> 配置 PATH / NEKOPATH / HAXE_STD_PATH / 动态库路径"
echo "$HAXE_DIR:$NEKO_DIR" >> "$GITHUB_PATH"
echo "NEKOPATH=$NEKO_DIR" >> "$GITHUB_ENV"
echo "HAXE_STD_PATH=$STD_DIR/std" >> "$GITHUB_ENV"
if [ "$(uname -s)" = "Linux" ]; then
  echo "LD_LIBRARY_PATH=$NEKO_DIR/lib:\$LD_LIBRARY_PATH" >> "$GITHUB_ENV"
else
  echo "DYLD_LIBRARY_PATH=$NEKO_DIR/lib:\$DYLD_LIBRARY_PATH" >> "$GITHUB_ENV"
fi

export PATH="$HAXE_DIR:$NEKO_DIR:$PATH"
export NEKOPATH="$NEKO_DIR"
export HAXE_STD_PATH="$STD_DIR/std"
if [ "$(uname -s)" = "Linux" ]; then
  export LD_LIBRARY_PATH="$NEKO_DIR/lib:$LD_LIBRARY_PATH"
else
  export DYLD_LIBRARY_PATH="$NEKO_DIR/lib:$DYLD_LIBRARY_PATH"
fi

haxe --version
neko -version
echo "==> Haxe/Neko 就绪"
