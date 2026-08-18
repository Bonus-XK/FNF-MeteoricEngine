#!/bin/bash
# ============================================================
# 安装引擎构建所需的 haxelib 依赖（版本与本地开发环境对齐）
# 用法: bash ci/install-deps.sh
# ============================================================
set -e

# haxelib 首次运行需要 setup（指定仓库目录）
if [ ! -d /opt/haxelib ]; then
  echo "==> haxelib setup /opt/haxelib"
  haxelib setup /opt/haxelib
fi

install() { # $1=库名 $2=版本（可空=最新）
  if [ -n "$2" ]; then
    haxelib install "$1" "$2" --quiet 2>/dev/null || haxelib install "$1" "$2"
  else
    haxelib install "$1" --quiet 2>/dev/null || haxelib install "$1"
  fi
}

echo "==> 安装 haxelib 依赖"
install lime 8.2.2
install openfl 9.5.2
install flixel 6.2.0
install flixel-ui 2.5.0
install flixel-addons 3.0.2
install hxcpp 4.3.2
install SScript 4.0.1
install hxCodec 3.0.2
install tjson 1.4.0
install hscript 2.6.0
install actuate 1.9.0
# lime tools 编译所需（CI 需从源码编译 tools.n）
install format 3.8.0
install hxp 1.3.1

echo "==> 安装 git 依赖"
haxelib git discord_rpc https://github.com/Aidan63/linc_discord-rpc main 2>/dev/null || \
  haxelib git discord_rpc https://github.com/Aidan63/linc_discord-rpc
haxelib git linc_luajit https://github.com/superpowers04/linc_luajit main 2>/dev/null || \
  haxelib git linc_luajit https://github.com/superpowers04/linc_luajit

echo "==> 依赖安装完成"
haxelib list | grep -E "^(flixel|openfl|lime|hxcpp|SScript|hxCodec|discord_rpc|linc_luajit|tjson)" | head -12
