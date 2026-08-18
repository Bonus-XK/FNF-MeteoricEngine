# hxcpp mac→windows 交叉编译补丁（hxcpp 4.3.2）

官方 hxcpp 4.3.2 的 setDefaultToolchain 只支持 mac→linux 交叉，
mac + -Dwindows 会落入 else 分支选 mac toolchain（clang 编 mac 目标）。
本目录提供两个改版文件（与本机开发环境一致）：

- BuildTool.hx      → tools/hxcpp/BuildTool.hx 的 mac 分支增加 windows→mingw 交叉
- mingw-toolchain.xml → toolchain/mingw-toolchain.xml 增加 mac_host 分支
                       （HXCPP_MINGW_EXE / MINGW_ROOT / Homebrew dll 拷贝）

CI 用法（Windows job）：
  HXCPP_DIR="$HOME/haxelib/hxcpp/4,3,2"
  cp ci/hxcpp-mac-cross/BuildTool.hx      "$HXCPP_DIR/tools/hxcpp/BuildTool.hx"
  cp ci/hxcpp-mac-cross/mingw-toolchain.xml "$HXCPP_DIR/toolchain/mingw-toolchain.xml"
  cd "$HXCPP_DIR" && haxe tools/hxcpp/compile.hxml   # 重编 hxcpp.n（hxml 默认 classpath=其所在目录）

注意：只改 .hx 源码不生效，hxcpp.n 是预编译 neko 字节码，必须重编。
