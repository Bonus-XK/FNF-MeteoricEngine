#!/bin/sh
# Meteoric Engine Android 构建脚本 (-release)
# 用法: ./compile-android.sh          # 增量构建
#       ./compile-android.sh install  # 构建并安装到已连接的设备/模拟器
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

# Android SDK / NDK 环境检查（lime 需要 ANDROID_SDK 与 ANDROID_NDK_ROOT）
if [ -z "$ANDROID_SDK" ]; then
  if [ -n "$ANDROID_SDK_ROOT" ]; then
    export ANDROID_SDK="$ANDROID_SDK_ROOT"
  elif [ -n "$ANDROID_HOME" ]; then
    export ANDROID_SDK="$ANDROID_HOME"
  fi
fi

if [ -z "$ANDROID_SDK" ] || [ ! -d "$ANDROID_SDK" ]; then
  echo "错误：未找到 Android SDK。"
  echo ""
  echo "安装步骤（macOS）："
  echo "  1. brew install --cask android-commandlinetools"
  echo "  2. sdkmanager --install \"platform-tools\" \"platforms;android-28\" \"build-tools;28.0.3\""
  echo "  3. sdkmanager --install \"ndk;21.4.7075529\""
  echo "  4. 在 ~/.zprofile 中添加："
  echo "     export ANDROID_SDK=/usr/local/share/android-commandlinetools"
  echo "     export ANDROID_NDK_ROOT=/usr/local/share/android-commandlinetools/ndk/21.4.7075529"
  exit 1
fi

if [ -z "$ANDROID_NDK_ROOT" ] || [ ! -d "$ANDROID_NDK_ROOT" ]; then
  echo "错误：未找到 Android NDK（请设置 ANDROID_NDK_ROOT）。"
  exit 1
fi

# JDK 检查：Gradle 7 + R8 3.3 不支持过新的 JDK（如 24），强制优先 JDK 17
for p in /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
         /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
         /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home; do
  if [ -x "$p/bin/java" ]; then
    export JAVA_HOME="$p"
    break
  fi
done
if [ -n "$JAVA_HOME" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

export ANDROID_SDK
export ANDROID_NDK_ROOT
export ANDROID_SETUP=true

if [ "$1" = "install" ]; then
  # lime 8.x 已移除 `install` 命令：构建后直接用 adb 安装
  haxelib run lime build android -release
  ADB="${ANDROID_SDK}/platform-tools/adb"
  if [ ! -x "$ADB" ]; then ADB="$(command -v adb || true)"; fi
  APK="$(find export/release/android/bin -name '*.apk' -type f | head -1)"
  if [ -z "$APK" ] || [ ! -f "$APK" ]; then
    echo "错误：未找到构建产物 APK"
    exit 1
  fi
  echo "安装 $APK ..."
  exec "$ADB" install -r "$APK"
else
  exec haxelib run lime build android -release
fi
