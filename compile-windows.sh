#!/bin/sh
# Meteoric Engine Windows 交叉编译脚本 (macOS -> Windows, -release)
# 用法: ./compile-windows.sh
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

exec haxelib run lime build windows -release -mingw
