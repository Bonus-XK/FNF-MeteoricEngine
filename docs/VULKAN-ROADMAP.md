# Vulkan 轨道路线图（渲染后端二开）

> 状态基线：2026-10-25。P0 已合入 master（`15f13d9`）；P1 沙盒与本文件同期；
> P2 为待执行计划（合并面已完整测绘）。

## 背景与事实（查证过的，别凭印象推翻）

- **上游 lime 8.4.0 develop（未发布）有实验性 Vulkan**：`<window renderer="vulkan">` 置
  `lime-vulkan` define → C++ 侧 `VKRenderer.cpp`（1750 行，仅引导 + swapchain + 同步，
  **没有任何管线/绘制调用**）；Haxe 侧 `lime.graphics.vulkan.*`（~30 类 / 4271 行）+
  `VulkanRenderContext`。平台：Windows / Linux / Android；**macOS 无**（需 MoltenVK，lime 未接线）。
- **OpenFL ≤ 9.5.2 没有 Vulkan 渲染器**（CHANGELOG 全是 GL/Stage3D）→ 主画面渲染换
  Vulkan 需要 OpenFL 层移植，**不做**，等上游。
- lime 8.4 的 Vulkan 绑定是**窗口耦合**的：`VK.createInstance` 必须传 `VulkanRenderContext`
  （只有 Vulkan 窗口才有）。探测可用性 = 真开一个隐藏 Vulkan 窗口。
- **上游 develop 的 SDL 子模块仍是 SDL2（2.32.10）**；SDL3 是 Meteoric 自己移植的
  （`ci/lime-sdl3-patch`，SDL 3.2.8）。→ P2 是把 8.4 的 Vulkan 增量**移植进 SDL3 树**，
  而不是把 Meteoric 补丁覆盖到 8.4 上（后者会把 Vulkan 覆盖没）。
- macOS 上 Vulkan 必须走 **MoltenVK**（Vulkan→Metal 翻译层）。SDL 的 Vulkan 加载器
  在 mac 上会依次找 `libvulkan.1.dylib` / `libMoltenVK.dylib` —— 直放 MoltenVK dylib
  + `DYLD_LIBRARY_PATH` 即可，不需要完整 Vulkan SDK。
  （MoltenVK v1.4.2 universal2 已验证可下载：`/tmp/moltenvk/…/dynamic/dylib/macOS/libMoltenVK.dylib`）

## P0：引擎渲染后端选项（已合入 `15f13d9`）

- `ClientPrefs.data.rendererBackend`：`'opengl'`（默认，零行为变化）| `'vulkan'`（实验性）。
- 图像设置页「渲染后端」行（桌面端），英文存储值 + `optionValue.rendererBackend.<i>` 档位。
- `backend/RendererBackend`：TitleState.loadPrefs 后探测——隐藏 Vulkan 窗口 →
  `VK.createInstance` → 枚举物理设备；失败自动回退 OpenGL。全程 Reflect 动态调用，
  lime 8.2.2（现行）/ lime-meteoric 8.4（P2 后）双兼容。
- 语义（如实）：选 vulkan 只初始化 **Vulkan 子系统**（隐藏窗口驻留句柄，后续二开的锚点），
  主画面渲染仍 OpenGL。
- 已验证：双门禁 + 真机（默认零变化；vulkan 选中 + 环境不可用 → 回退 trace + 游戏正常）。

## P1：裸 lime Vulkan 沙盒（stock develop，验证引导链）—— ✅ 2026-10-25 已跑通

**验证结果**（mac arm64 / Apple M4 / MoltenVK v1.4.2 / lime 8.4.0 develop）：

```
[sandbox] window context type = vulkan
[sandbox] OK VulkanRenderContext 就绪
[sandbox] surface 所需 instance extensions: VK_KHR_surface, VK_EXT_metal_surface
[mvk-info] MoltenVK version 1.4.2, supporting Vulkan version 1.4.357.（154 个扩展）
[mvk-info] GPU device: model: Apple M4 / Metal 4 / 12124 MB
[sandbox] OK VkInstance 创建成功
[sandbox] 物理设备 1 个: - Apple M4 | Vulkan 1.0.357 | integrated-gpu
[sandbox] 300 帧存活，Vulkan 引导链验证完成，退出
```

lime 8.4 的 C++ VKRenderer 引导（loader→instance→surface→device→swapchain）+ Haxe 侧
`VK.createInstance` / `enumeratePhysicalDevices` 在 macOS 上全部可用。二开注意：lime 请求的
apiVersion 是保守的 1.0（MoltenVK 支持 1.4），P2 之后可以抬高并按需启用扩展。

工程在 `ci/vk-sandbox/`（project.xml + Source/Main.hx，已归档进仓库），内容：Vulkan 窗口 →
extensions → createInstance → 枚举物理设备 → 300 帧存活退出。

lime develop 组装步骤（照 `ci/setup-lime-sdl3.sh` 适配 develop）：

```bash
git clone --branch develop --single-branch https://github.com/openfl/lime.git <dir>
# 移除 cairo/pixman 子模块（gitlab 源不可达），tarball 补：
#   cairo-1.18.2.tar.xz / pixman-0.46.4.tar.gz（cairographics.org，注意解包后压平一层）
git submodule update --init --recursive --depth 1
(cd tools && haxe tools.hxml)          # 编 tools.n（haxe 4.2.5 可编，已验证）
cp -R /usr/local/lib/haxe/lib/lime/8,2,2/ndll/. ndll/   # host 工具引导
haxelib install native-desktop         # ⚠ 8.4 新依赖，缺了 haxelib run lime 直接报错
haxelib dev lime <dir>
```

构建：`cp -R ci/vk-sandbox /tmp/vk-sandbox && cd /tmp/vk-sandbox && haxelib run lime build macos -Darm64 -debug`

**三个实测坑（2026-10-25）**：
1. `haxelib install native-desktop` 漏装 → `haxelib run lime` 直接报
   `Could not find haxelib "lime"`（实际是 8.4 的 haxelib.json 新依赖解析失败，报错误导）。
2. 从 8.2.2 发行版拷的引导 `ndll/` 若不重建，app 构建会把这个**旧 ndll 打进 bundle** →
   运行时刷屏 `Could not find primitive lime_application_set_vsync_mode__prime ...` 然后
   `lime_key_code_from_scan_code does not have signature ii` 崩掉。
   必须先 `haxelib run lime rebuild macos -arm64 -debug` 重建 8.4 ndll 再 build app；
   且 rebuild 产物名是 `lime-debug-64.ndll`，工具不会自动替换 bundle 里的 `lime.ndll`，要手动拷。
3. **`lime rebuild` 不从工程 XML 继承 `lime-vulkan` define**（`renderer="vulkan"` 只影响 app
   构建）→ 不显式加 define 时 Vulkan CFFI 全部编成桩，报
   `VK.createInstance 失败: Lime was built without lime-vulkan support`，而窗口的 vulkan
   类型报告/扩展枚举是 SDL 直接调用（未门控）照常工作——症状极隐蔽。重建必须：
   `haxelib run lime rebuild macos -arm64 -debug -Dlime-vulkan`。
   ⚠ P2 引擎侧同理：引擎主窗口是 GL（Project.xml 不写 renderer="vulkan"），要让引擎用的
   lime-meteoric ndll 带真 Vulkan CFFI，编译时必须显式 `-Dlime-vulkan`（或工程里
   `<haxedef name="lime-vulkan" />`），否则 RendererBackend 探测永远落在回退分支。
4. pixman 0.46.4 与 develop 的 pixman-files.xml 不匹配（`pixman_region64f_rectangles`
   链接失败）→ 在 `project/lib/pixman-files.xml` 的 region32 行后加一行
   `pixman-region64f.c`（借自 Meteoric 补丁的解法，已验证）。
运行：`DYLD_LIBRARY_PATH=<MoltenVK dylib 所在目录> ./VKSandbox.app/Contents/MacOS/VKSandbox`

## P2：lime-meteoric（develop + Meteoric 补丁重放）—— 合并面已测绘

**基座**：`~/Documents/lime-meteoric`（develop 8.4.0 已组装，见上）。**不是** overlay
`ci/lime-sdl3-patch`（那是 8.2.2 基座，直接覆盖会把 8.4 的 Vulkan / SDLMenu / Mac 窗口代码抹掉）。

**上游改动过、需三方合并的 22 个文件**（8.2.2-stock ↔ Meteoric ↔ 8.4 三方）：

| 文件 | 难点 |
|---|---|
| `project/src/backend/sdl/SDLWindow.cpp/.h` | **核心**：以 Meteoric SDL3 版为基，回移植 8.4 的 Vulkan 增量（`WINDOW_FLAG_VULKAN`、`VulkanRenderer` 创建、surface/drawable/instance-extension 辅助） |
| `project/src/backend/sdl/SDLApplication.cpp/.h` | 墙钟帧循环（HiResMs/nextUpdate double/WaitEventTimeout + `MeteoricFrameLoopPatch.cpp`）。8.4 该文件**无** vulkan 内容（已查证），MeteorIC 版可直接作基，但要过一遍 8.4 的其它上游修复 |
| `project/src/backend/sdl/SDLSystem.cpp` | 222 行差异照搬 + 上游 diff 复核 |
| `project/Build.xml` | 以 8.4 为基（含 `LIME_VULKAN` 门控 + `VKRenderer.cpp` 条目），合入 Meteoric 构建定制；SDLMenu/Tray 选 Stub 版（SDL 3.2.8 无 tray API） |
| `project/lib/sdl-files.xml`（938 行差异） | Meteoric 的 SDL3 源清单直接用 |
| 其余 files.xml / custom configs | 版本对齐重放（pixman/openal/curl/freetype/harfbuzz 等） |

**8.4 新增、Meteoric 补丁没有的 5 个文件**（需 SDL3 化或走 Stub）：
`SDLMenu.cpp/.h`、`SDLMenuStub.cpp`、`SDLTrayIcon.h`、`SDLWindowMac.mm`（mac 窗口定制，重点核对与 SDL3 的 API 兼容）。

**顺序**：先 mac arm64（本地可全验）→ 引擎 `haxelib dev` 切到 lime-meteoric →
typecheck + i18n + 真机（默认 opengl 必须零变化）→ vulkan 档真探测（装 MoltenVK 后
应打出设备名）→ 再考虑 Windows/Android。

**验收红线**：
1. 默认 opengl：行为与现行 8.2.2-patched 完全一致（墙钟帧循环在位——`hasWallclockFrameLoop()` 通过）；
2. 引擎 CI（`ci/setup-lime-sdl3.sh`）要同步出 develop 版组装脚本，否则 CI 与本地分叉；
3. `haxelib dev lime` 指向切换要有回滚命令记录（`haxelib dev lime /usr/local/lib/haxe/lib/lime/8,2,2`）。

## 远期（不在本轨道内）

- OpenFL 显示列表跑 Vulkan（等上游）。
- Vulkan 渲染管线（SPIR-V / 合批）与离屏特效层 —— P2 落地后，引擎里的 Vulkan 子系统
  （`RendererBackend.vulkanWindow` 驻留句柄）就是接入口。
