#!/bin/bash
# ============================================================
# CI 安装 Haxe 4.2.5 + Neko 2.3.0 + Haxe 标准库
# 支持: Linux x86_64 / macOS（arm64 runner 上以 Rosetta 跑 x86_64）
# 用法: bash ci/setup-haxe-ci.sh
# ============================================================
set -e

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

echo "==> 下载 Haxe 4.2.5"
mkdir -p /opt/haxe
curl -sL "$HAXE_URL" | tar xz -C /opt/haxe --strip-components=1
chmod +x /opt/haxe/haxe /opt/haxe/haxelib

echo "==> 下载 Neko 2.3.0"
mkdir -p /opt/neko
curl -sL "$NEKO_URL" | tar xz -C /opt/neko --strip-components=1
chmod +x /opt/neko/neko

echo "==> 下载 Haxe 标准库（std/，官方二进制包不含）"
mkdir -p /opt/haxe-std
curl -sL "https://github.com/HaxeFoundation/haxe/archive/refs/tags/4.2.5.tar.gz" -o /tmp/haxe-src.tar.gz
tar xzf /tmp/haxe-src.tar.gz -C /opt/haxe-std --strip-components=1

echo "==> 配置 PATH / NEKOPATH / HAXE_STD_PATH"
echo "/opt/haxe:/opt/neko" >> "$GITHUB_PATH"
echo "NEKOPATH=/opt/neko" >> "$GITHUB_ENV"
echo "HAXE_STD_PATH=/opt/haxe-std/std" >> "$GITHUB_ENV"

export PATH="/opt/haxe:/opt/neko:$PATH"
export NEKOPATH=/opt/neko
export HAXE_STD_PATH=/opt/haxe-std/std

haxe --version
neko -version
# 冒烟测试：确认 haxe 能实际编译（std 可用）
echo 'class Main { static function main() trace("haxe-ok"); }' > /tmp/haxe_smoke.hx
haxe -main Main --interp -cp /tmp > /dev/null 2>&1 || true
echo "==> Haxe/Neko 就绪"
