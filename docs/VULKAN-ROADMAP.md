# Vulkan 轨道路线图（渲染后端二开）

> 状态基线：2026-10-25 深夜。**P0/P1/P2 全部完成**：
> P0 已合入 master（`15f13d9`）；P1 沙盒跑通；P2 合并树构建 + 引擎完整验证通过
> （真机：默认 GL 零变化 + vulkan 档「Vulkan 子系统就绪」）。
> lime-meteoric 工作树：`~/Documents/lime-meteoric`，分支 `meteoric-vulkan-sdl3`
> （提交 `e39f7490` + `00ed4c8f`）。**引擎默认仍用 8.2.2**（见「切换状态」）。

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
  （MoltenVK v1.4.2 universal2，**持久存档**：`~/Documents/meteoric-libs/MoltenVK/`
  （含 dylib 与原始 tar）；运行需 `DYLD_LIBRARY_PATH=~/Documents/meteoric-libs/MoltenVK/MoltenVK/dynamic/dylib/macOS`。
  `/usr/local/lib` 与 `~/lib` 都不在 SDL 的 dlopen 搜索路径内（实测）——P2 要在 fork 里
  加「优先从引擎目录显式 `SDL_Vulkan_LoadLibrary(绝对路径)`」的加载逻辑，彻底去掉环境变量）

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

## P2：lime-meteoric（develop + Meteoric 补丁重放）—— ✅ 2026-10-25 完成并真机验证

**验证结果**（mac arm64 / Apple M4 / MoltenVK 1.4.2）：
- ndll（release/debug，`-Dlime-vulkan`）构建 EXIT=0；
- 沙盒全链路（窗口→引导→instance→物理设备枚举 Apple M4→300 帧）✓；
- **引擎**（OpenFL 9.2.1 + flixel 5.2.2 + 全量源码）在 lime-meteoric 上：typecheck EXIT=0、
  完整构建 EXIT=0、真机默认 GL 启动零变化（0 缺原语 / 0 探测输出）、
  **vulkan 档真机打出「[Renderer] Vulkan 子系统就绪；主画面渲染仍为 OpenGL」**。

**P2 实际执行中追加修的坑（全部已修，勿再踩）**：
1. `SetAlwaysOnTop` 在 8.4 基类升为纯虚 → SDLWindow 必须实现（SDL3 `SDL_SetWindowAlwaysOnTop`）。
2. SDL3 仍有 `SDL_WINDOW_VULKAN` 窗口标志且**必须设置**（SDL_video.c：带标志建窗自动
   LoadLibrary，失败=窗口创建干净失败；`SDL_Vulkan_CreateSurface` 也检查它）。
   「SDL3 删了该标志」是误记。
3. Meteoric 的 SDL_build_config.h **src 副本**未开 `SDL_VIDEO_VULKAN`（include 副本开了，
   两份不一致！）→ cocoa 驱动无 Vulkan，报「Vulkan support is either not configured in SDL」。
4. `SDL_cocoavulkan` 链接缺 `QuartzCore`（CAMetalLayer）。
5. SDL3 把 **loader 层扩展** `VK_KHR_portability_enumeration` 无条件列入 mac 必需扩展；
   直连 MoltenVK（无 Vulkan loader）时驱动不提供它 → `vkCreateInstance` 返回
   `VK_ERROR_EXTENSION_NOT_PRESENT(-7)`。修法：ExternalInterface 的
   CreateManagedVulkanInstance 按 `vkEnumerateInstanceExtensionProperties` 可用性过滤必需表。
6. `lime rebuild` 不从工程 XML 继承 `lime-vulkan`（见 P1 坑 3）；**引擎侧的 haxedef 还必须在
   Project.xml 任何 `<haxelib>` 之前声明**——lime 的 include.xml 在依赖解析早期求值，
   放在 Haxedefines 区（库声明之后）完全失效（实测，`meteoric_no_sdl_sound` 的 unless
   逃生口因此不可达，最终在 fork 里翻转默认极性解决）。
7. 引擎 `source/lime/.../NativeAudioSource.hx` vendor 机制：引擎 source 目录解析优先级
   **高于** lime 库 classpath，vendor 文件一直实际生效（且空模块对 `import` 式引用不穿透）。
   已按 CI.md 原则移除 vendor：音频修复移植进两棵 lime 树（lime-meteoric 8.4 +
   /usr/local 8.2.2 dev 树，内容=原 vendor 版，8.2.2 零行为变化）+ CI 覆盖层补文件
   （`ci/lime-sdl3-patch/src/...` + setup 脚本拷贝行）。
8. **app 构建不会重建 bundle 里的规范名 `lime.ndll`**——`lime rebuild` 产物名是
   `lime-64.ndll`/`lime-debug-64.ndll`，要手动就位 `$LIME/ndll/MacArm64/lime.ndll`
   （app 构建只从这里取）。
9. **compile-mac.sh 的 arm64 自动检测以 `tools/lime.ndll.wallclock-arm64` 存在为前提**
   （第 19 行）——把墙钟文件暂存走会静默落到 x86_64！测试时用 `METEORIC_ARCH=arm64` 显式指定。
10. ndll 还原（wallclock swap）后 bundle 签名失效 → `Taskgated Invalid Signature` 秒杀
    （空日志假象）。`codesign --force --deep -s - <app>` 即恢复。

**切换状态**：会话结束时已回滚——`haxelib dev lime` → 8.2.2、墙钟文件归位、引擎重建+真机
验证正常。**常驻切到 lime-meteoric 的操作**（建议先真机完整游玩验证 8.4 构建：进曲/视频/音频流）：
```bash
haxelib dev lime /Users/raidbounce/Documents/lime-meteoric   # 切
# 构建：METEORIC_ARCH=arm64 ... ./compile-mac.sh；⚠ 需先把 tools/lime.ndll.wallclock* 暂存
# （否则 post-build 会用 8.2.2 老 ndll 覆盖 8.4 产物 → 23 个缺原语崩溃），且 compile-mac.sh
# 的墙钟还原逻辑需要适配 lime-meteoric（跟进项）
haxelib dev lime /usr/local/lib/haxe/lib/lime/8,2,2          # 回滚
```

**P2 遗留（跟进项，非阻塞）**：
- compile-mac.sh 适配 lime-meteoric（ndll 还原逻辑按 lime 版本分流 + 检测条件与墙钟文件解耦）
- `RendererBackend` 探测的设备名为空（cosmetic；上下文就绪已证明 C++ 侧全引导）
- 引擎 Vulkan 档下的进曲/音频流/视频长跑验证（需人工游玩）
- Windows/Android 目标构建、SDLMenu/SDLWindowMac/虚拟手柄移植、sdl_sound 移植或永久放弃
- lime-meteoric push 到 GitHub（现为本地分支）

### P2 执行前的合并面测绘（留档参考，执行结果见上）

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

## 事故记录：2026-10-25 用户存档丢失（已装防护，见引擎提交 e6d17d0）

lime-meteoric 8.4 演练期间，游戏进程被 kill -9 时 sol 非原子写遭截断 → 下次启动
SharedObject 反序列化**静默失败** → loadPrefs 的 6 处启动迁移 saveSettings() 用默认值
覆写残档，用户设置全丢（无 TM/快照可恢复；周目进度/分数/回放/mods 在独立存储未受影响）。
已在 ClientPrefs 装损坏防护（加载率<30% ⇒ 跳过迁移写盘 + .corrupt 留证，真机验证通过）。
**跟进项**：① openfl SharedObject 的 sol 落盘改原子写（tmp+rename，需动 openfl/lime 层）；
② lime-meteoric 8.4 构建下同款防护复验；③ compile-mac.sh 的 typecheck ndll 校验按
lime 版本分流（8.4 ndll 会被当成「未知指纹」走墙钟覆盖分支报错）。

## 远期（不在本轨道内）

- OpenFL 显示列表跑 Vulkan（等上游）。
- Vulkan 渲染管线（SPIR-V / 合批）与离屏特效层 —— P2 落地后，引擎里的 Vulkan 子系统
  （`RendererBackend.vulkanWindow` 驻留句柄）就是接入口。
