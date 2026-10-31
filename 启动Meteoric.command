#!/bin/zsh
# Meteoric 启动器（稳定线 8.2.2）：终端窗口内启动，Trace 直接可见。
# 纯 OpenGL 主渲染，无需任何环境变量。
cd "$(dirname "$0")/export/release/macos/bin/Meteoric.app/Contents/MacOS" || exit 1
exec ./Meteoric
