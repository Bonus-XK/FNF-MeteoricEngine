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

## x86 要点（2024-08 修复）

- MINGW_ROOT 按 arch 分：x64 → toolchain-x86_64，x86 → toolchain-i686
- brew 的 i686 是 sjlj 异常模型，而 lime 只认/只拷 libgcc_s_dw2-1.dll
  （且不拷 sjlj/ssp）→ x86 链接加 -static（全静态，仅依赖 Win10 自带 UCRT），
  dw2 dll 仅作满足 lime 拷贝的占位（ci/mingw-dlls/，由 -D MINGW_DW2_SRC 传入）
- rebuild/lime build x86 必须显式 -DHXCPP_M32（hxcpp 按宿主 uname 默认 m64）
