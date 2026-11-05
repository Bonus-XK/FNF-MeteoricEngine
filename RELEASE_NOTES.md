# NovaComet Engine v1.2.0 Pre-release 1 — "bigshot"

> 基于 Psych Engine 0.7.1h 深度魔改的 FNF 引擎。**v1.2.0 Pre-release 1（代号 bigshot）** 是引擎更名 **NovaComet Engine** 后的第一个公开预发布版，自 v1.1.3 以来共 270+ 项提交：全新多语言系统、Modchart 工具链、模组体系独立化、全局 CRT 着色器、任意键数 1-12、弹窗与小图标跳动全面重做、Lua 对象桥，以及一轮贯穿全界面的性能优化与稳定性修复。

---

## ✨ 版本亮点

- **引擎更名 NovaComet Engine**：新品牌 + 全新紫色彗星应用图标；构建产物、环境变量与内部代号沿用 Meteoric
- **多语言系统（i18n）**：内置简体中文 / English 语言包（各 1554 key），玩家可见文案全量接入，支持社区语言包与回退链
- **Modchart 工具链**：移植 FNF-Modcharting-Tools（Apache-2.0）运行时，新增 Lua/HScript 模表 API 与**镜头自由化**（补间层 / 脚本 API / 自定义相机 / 谱面事件）
- **模组体系独立化**：`mod.json` 元数据、`meteoric-mods.txt`、Psych 1.0.4 兼容开关
- **全局 CRT 着色器**：移植 Timothy Lottes 的 public domain CRT shader（单 pass），Lua/HScript 脚本 API 控制，默认关闭
- **任意键数 1-12**：谱面 `"keys"` 字段声明，缺省 4 键零行为变化
- **五平台 CI 自动构建**：Windows x64/x86、macOS x64/arm64、Linux x64、Android arm64、iOS，构建成功自动发布 Pre-release 并附 SHA256 校验和

## 🌍 多语言系统（i18n）

- `backend/Lang` 运行时 + JSON 语言包，回退链：当前语言 → en → zh → key
- 设置新增「语言」分区；成就 / 主题 / 选项文案按 key 派生；官方曲目内容不汉化
- 配套只读门禁 `tools/i18n/check_i18n.py`（7 项自检），新增「转义过度」检测——本轮据此批量修复语言包 81 处假换行（zh 43 + en 38）

## 🥁 打击反馈与手感

- **评分 / 连击弹窗**：新增 4 种弹出方式（classic / **pop 新默认** / slide / fade）+ 可选**立体层**（弹窗挂到游戏世界层，跟随舞台镜头，对齐 Codename Engine 口径）；时长选项同步新增，变速下节奏不变
- **小图标跳动**：两个 bool 重构为单枚举 **7 档**（关闭 / 脉冲 / 错拍 / 点头 / 跳跃 / 挤压 / KE 引擎），底层改为真·阻尼弹簧（离线扫参 ω=24 / ζ=0.45），支持对局中途切档、旧存档自动迁移
- **毫秒加权准确率** + BackButton 按压反馈

## 🎬 画面与转场

- **转场样式可选**：淡入淡出（默认）/ 移动 / 陨星 / 星辉四种，设置存档持久化
- **时间条贴图层级**：自动检测 / 贴图在上 / 贴图在下，贴图分层对齐 Psych 0.7.1h
- **全局 CRT 着色器**（脚本开关，默认关闭）：桶形畸变 / 扫描线 / shadow mask / bloom / gamma，支持 curvature、scan、vignette、rgbsplit、time 五参数

## 🧩 脚本与模组

- **Lua 对象桥（Object Bridge）**：Lua 脚本获得 Haxe 对象一等引用；界面脚本（`menus/<界面名>.lua`）接入同一套 API；HScript 同款 `import` + `class` 继承 Haxe 类
- **模组体系独立化**：mod.json 声明式元数据，Psych 1.0.4 兼容开关
- 修复 `ScriptGlobals` 在 `FlxG.sound.music` 为 null 时的 SEGV

## ⌨️ 谱面与玩法

- **任意键数 1-12**：谱面 `keys` 字段声明，中心模块 `backend/ExtraKeys.hx`，缺省 4 键零行为变化
- 长条尾段渲染优化（离屏裁剪守卫 / 无旋转快路径 / dense 档尾段步距 ×4 限自动游玩与回放，修复手动长条缩短跳变）
- 谱面尾部超出音频长度时曲尾冻结永不结算的兜底
- 「启用 GC」开关真正生效（全项目手动 GC 回收点补守卫 + 切换即时生效）
- 启动参数直进曲目：`--meteoric-song / --meteoric-diff / --meteoric-botplay`
- `METEORIC_SAVE_DIR` 测试隔离存档（测试跑谱不再覆盖玩家真实存档）

## ⚡ 性能

- 全界面每帧分配清理：菜单态 / 子状态 / Freeplay / 游戏内热路径零分配化
- 进曲加载洪峰后主动 major GC（自适应阈值），游玩期内存平稳
- 判定计数侧边栏 5Hz 刷新节流
- 密集墙谱三连优化（1.1.3 后继续收敛）

## 🛠 稳定性修复

- **根治 macOS 间歇性 SEGV**：PerfProbe 采样改 Mach task_info 直读
- **全局 shader 顶部黑带**：根级 filter 纹理对齐窗口（隐藏音量条被计入渲染边界所致）
- **音量提示音连响**：快速连按 +/- 时多声 beep 叠加 —— 改常驻单实例 ForceRestart，每次有效调整一声
- Hurt Note 特殊箭头在 `disableNoteRGB` 曲目下整条初始化失败
- Weekend1 在 Freeplay 不显示正确小图标（补 `-pe` 命名档）
- 更新检查 / 下载 URL 随品牌更名同步

## 🏗 工程与架构

- **PlayState 域拆分**：7,946 → 3,853 行（−51.5%），迁入 8 个域模块，全仓调用点零改动
- 新增 `source/bridge/` 外围边界（Editor / CNE / LuaGraph），主流程对编辑器 import 清零
- 新增只读工具链：`tools/scope/`（作用域分析与迁移）、`tools/boundary/`（耦合测绘）、`tools/i18n/`
- CI：workflow 拆分为可复用编排 + hxcpp 编译缓存；SDL3 Linux（evdev / ALSA / tray 等）与 iOS 驱动补齐；Windows 链接期符号表（崩溃可定位到函数）+ exe 图标注入校验；macOS 14 镜像迁移 macos-26

## 📦 下载

| 平台 | 文件 |
|---|---|
| Windows x64 / x86 | `Meteoric-Windows-x64-<版本>.zip` / `Meteoric-Windows-x86-<版本>.zip` |
| macOS（Intel / Apple Silicon） | `Meteoric-macOS-x86_64-<版本>.zip` / `Meteoric-macOS-arm64-<版本>.zip` |
| Android arm64 | `Meteoric-Android-arm64-<版本>.apk` |
| Linux x86_64 | `Meteoric-Linux-x64-<版本>.tar.gz`（视频支持暂缺） |
| iOS（未签名） | `Meteoric-iOS-unsigned-<版本>.ipa`（AltStore / Sideloadly 侧载自动重签） |

完整性校验：下载后核对 `SHA256SUMS.txt`。

## 🔢 版本校验

- 引擎版本 **1.2.0**，更新校验索引 **5**
- 本版本为 **Pre-release**：功能与手感仍在迭代，正式版前可能再有破坏性调整，欢迎反馈

## ⚠️ 已知事项

- 实机验证以 macOS 为主；Windows / Linux / Android / iOS 端以 CI 构建成功为准
- 全局 CRT 着色器为脚本 API（无设置页入口），默认关闭
- 视频支持在 Linux 端暂缺
