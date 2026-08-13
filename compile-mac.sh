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

if [ "$1" = "test" ]; then
  exec haxelib run lime test macos -release
else
  exec haxelib run lime build macos -release
fi
