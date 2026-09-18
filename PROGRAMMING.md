# Meteoric 编程层（CNE 式 HScript）

> 实现参考：Codename Engine（CodenameCrew，Apache-2.0）的 `Script` / `ScriptPack` / `GlobalScript` / `ModState` 语义。
> Meteoric 不复制 CNE 的 hscript 引擎，而是复用自身 `psychlua.HScript`（SScript 4.0.1 + 184 项 preset API）。
> 入口：设置 → **编程**（主设置与暂停内设置两个入口都在）。

## 1. 开关

| 选项 | 存档字段 | 默认 | 作用 |
|---|---|---|---|
| CNE 式 HScript 编程层 | `cneScripting` | 关 | 总开关；关闭时以下所有能力都不加载，引擎行为与改动前一致 |
| 状态脚本 | `cneStateScripts` | 开 | 允许 `data/states/<界面类名>/LIB_<mod>.hx` |
| 全局脚本 | `cneGlobalScripts` | 开 | 允许 `data/global/LIB_<mod>.hx` |
| ModState / ModSubState | `cneModStates` | 开 | 允许用 HScript 写完整界面 |
| 界面重定向 | `cneStateRedirects` | 关 | 允许 mod 用 `flags.ini [StateRedirects]` 把引擎界面替换成自己的 HScript 界面 |
| 脚本热重载 | `cneHotReload` | 开 | F5 原地重建当前界面脚本；Shift+F5 重建全局脚本 |
| 脚本定义/继承类 | `cneScriptClasses` | 开 | 仅当脚本文件里真的出现 `class` 时才启用 SScript EX 模式 |
| 脚本加载日志 | `cneScriptLogs` | 关 | 控制台打印 `[CNE]` 加载/重载/错误日志 |
| CNE 模组兼容 | `cneModCompat` | 关 | 加载 **CNE 格式的 mod**（CNE 谱面/音频/人物/周目/zip 包）；与编程层相互独立，详见第 8 节 |

> 安全提示：HScript 可访问 `Sys` / `File` / `FileSystem` 等引擎能力，只在信任 mod 时打开总开关。

## 2. 目录约定

```
mods/<mod>/data/global/LIB_<mod>.hx                  # 全局脚本（常驻）
mods/<mod>/data/states/<界面类名>/LIB_<mod>.hx        # 状态脚本（该界面）
mods/<mod>/data/states/<界面类名>.hx                  # 状态脚本简写（可选）
```

- 扩展名支持 `.hx` / `.hscript` / `.hsc` / `.hxs`。
- `<界面类名>` 是 Haxe 类名末段，例如 `TitleState`、`MainMenuState`、`PlayState`。
- 每个启用的 mod 各自提供一个 `LIB_<mod>` 文件；多个 mod 的脚本会在同一个界面里同时运行。
- 当前只支持文件夹 mod；zip 内脚本未验证。

## 3. 脚本可用的变量与生命周期

脚本内可用：

- `state`：当前宿主界面对象（`TitleState` / `MainMenuState` / `PlayState` …）。
- `game`：PlayState 宿主（仅 PlayState 脚本；与 `state` 同对象）。
- `CNE`：`cne.ProgrammingManager` 静态入口，可调用：
  - `CNE.reloadCurrentStateScripts()`：原地重建当前界面脚本组。
  - `CNE.reloadGlobalScripts()`：重建全局脚本组。
- 其余变量/类沿用 `psychlua.HScript.preset()` 的 184 项 API（`FlxG`、`Paths`、`ClientPrefs`、`Character`、`Note`、`Mods`、`DesignTokens`、`setThemeColor`、`runTimer` …）。

生命周期回调（在脚本顶层定义同名函数即可）：

| 回调 | 时机 |
|---|---|
| `create()` | 界面创建后、脚本加载完成 |
| `update(elapsed)` | 每帧（状态脚本由宿主 state 的 update 驱动；全局脚本由 `FlxG.signals.postUpdate` 驱动） |
| `stepHit(step)` | 步进变化 |
| `beatHit(beat)` | 节拍变化 |
| `postUpdate(elapsed)` | 全局脚本专用，`update` 之后 |
| `destroy()` | 界面销毁或热重载替换旧脚本之前 |

未定义的回调会被静默跳过；单个脚本报错不会中断同一组内其它脚本。

## 4. 热重载语义

- **F5**：原地重建当前界面的脚本组。
  - 先对旧脚本调用 `destroy()`，再销毁实例；随后从磁盘重新读取并 `create()` 新脚本。
  - 宿主 state 与其视觉对象**不重建**、不重进关卡。
  - 新脚本组构建失败（文件被删/全部解析失败）时保留旧脚本组。
- **Shift+F5**：只重建全局脚本组，当前界面不受影响。
- 键位存 `ClientPrefs.data.cneHotReloadKeys`（默认 `[F5]`），与 `keyBinds` 表分离。
- 脚本必须在 `destroy()` 里清理自己创建的对象，否则热重载会留下旧对象。

> 与 CNE 的差异：CNE 默认 F5 是 `FlxG.resetState()`（重进 state），其 in-place 分支 `EXPERMENTAL_SCRIPT_RELOADING` 在本仓库所参照的 CNE 快照中未定义且静态上有 `didLoad` 缺陷。Meteoric 采用“替换脚本组”的原地重建，不采用 `FlxG.resetState()`。

## 5. 用 HScript 写完整界面

```haxe
// 在任意脚本里：
MusicBeatState.switchState(new cne.ModState("MyState"));
// 或子状态：
openSubState(new cne.ModSubState("MySubState"));
```

`ModState` / `ModSubState` 会按传入的 `stateName` 查找：

```
mods/<mod>/data/states/MyState/LIB_<mod>.hx
```

`ModState.lastName` / `lastData` 与 CNE 同语义（同类状态间保持最后的数据）。

## 7. 界面重定向（StateRedirects）

在 `mods/<mod>/flags.ini` 里写：

```ini
[StateRedirects]
MainMenuState = DemoState

[StateRedirects.force]
MainMenuState = AnotherDemoState
```

- 键 = 引擎界面类名末段（`MainMenuState` / `TitleState` / `PlayState` …）。
- 值 = Haxe 类全名（`Type.resolveClass` 能解析时直接实例化）或 HScript 状态名（交给 `cne.ModState(value)`，按 `data/states/<value>/LIB_<mod>.hx` 找脚本）。
- `[StateRedirects]` 先到先得；`[StateRedirects.force]` 后到覆盖并压过普通段。
- 仅在设置 → 编程 → **界面重定向** 打开时生效（默认关）；改写点在 `FlxG.signals.preStateSwitch`，与 CNE 的 `GlobalScript.preStateSwitch` 同点。
- 链式指向最多解析 8 跳；成环或指回自身时放弃重定向。

## 8. CNE 模组兼容（CNE 格式 mod 的加载）

> 与上面 1–7 节的「CNE 式编程层」是两条独立的线：
> `cneScripting` 管的是**脚本能不能跑**，`cneModCompat` 管的是**CNE 格式的 mod 能不能被识别与读进来**。
> 两个开关相互独立：只开编程层不会去读 CNE 布局；只开模组兼容也不会执行 CNE 脚本。

开关：设置 → 编程 → **CNE 模组兼容**（`ClientPrefs.data.cneModCompat`，**默认关**）。
关闭时 mod 加载路径与改动前逐字节一致（不扫 CNE 布局、不挂 zip 暂存、不翻译谱面/人物/周目）。

### 覆盖范围（v1）

| CNE 布局 | Meteoric 侧处理 | 实现位置 |
|---|---|---|
| 谱面 `songs/<song>/charts/<难度>.json` | 解析 `codenameChart`（`strumLines`）→ **psych_v1**（列号绝对方向，`mustHitSection` 只管镜头）；难度缺省对齐 `normal`；`Camera Movement` / `BPM Change` / `Time Signature Change` / `Alt Animation Toggle` 烘焙进 section | `states/editors/content/CneExport.hx`（`cneToPsych`/`isCneFormat`）+ `backend/Song.hx` |
| 歌曲元数据 `songs/<song>/meta.json` | 提供 bpm（**必需**，否则时间轴错）；补 `needsVoices` / `instSuffix` / `vocalsSuffix` | `cne/CneModCompat.hx` |
| 音频 `songs/<song>/song/Inst<suffix>[-<难度>]`、`Voices<suffix>[-<难度>]` | 在 Psych 路径 `songs/<song>/Inst.ogg` 缺失时回退；`.ogg` 优先、`.mp3` 兜底 | `backend/Paths.modsSounds` |
| 人物 `data/characters/<name>.xml` | 解析 `<character sprite/icon/color/holdTime/scale/flipX/x/y/camx/camy>` + `<anim name/anim/x/y/fps/loop/indices>` → Psych 人物 JSON（含 `2..12` 区间索引展开） | `cne/CneModCompat.characterJson` + `objects/Character.hx` |
| 周目 `data/weeks/weeks/*.xml` + `data/weeks/weeks.txt` | 翻译成 Psych `WeekFile`（`chars`→`weekCharacters`、`<song>` 列表、`<difficulty name>`→`difficulties`、`bgColor`→`freeplayColor`），进 Story/Freeplay 列表 | `cne/CneModCompat.cneWeekFiles` + `backend/WeekData.hx` |
| 舞台 `data/stages/<名>.xml` | `<stage zoom>` + `<boyfriend>/<dad>/<girlfriend>` 的 x/y/camxoffset/camyoffset → 合成 Psych `StageFile`（`StageData.getStageFile`）；`<sprite>` 图层 → `states/stages/CneXmlStage`（贴图按 `folder` → `images/<folder>/<sprite>.png` 解析） | `cne/CneModCompat.hx` + `states/stages/CneXmlStage.hx` |
| 人物加载优先级 | mod 的 Psych JSON → **mod 的 CNE `data/characters/<名>.xml`** → 引擎内置 JSON → 兜底人物。CNE 是 mod 覆盖引擎，旧顺序下 mod 的同名人物（gf/bf/dad）永远读不到 | `objects/Character.hx` |
| zip 包 `mods/<名>.zip`（根级即 mod 根） | 识别为 mod；首次访问时透明解包到 `mods/_cnestage/<名>/`（指纹 = zip 体积+mtime，zip 换了自动重解）；`_cnestage` 不进 Mod 列表 | `cne/CneZipStore.hx` + `backend/Mods.hx` + `backend/Paths.mods` |
| Mod 列表识别 | 卡片/信息区标注「CNE 格式」，兼容开关未开时提示开关位置 | `states/ModsMenuState.hx` |

### 尚未覆盖（v1 明确不做，等第二轮实机测试后再排期）

- CNE 舞台的 **HScript 版本**（`data/stages/*.hx`）不执行，只支持 XML 舞台；XML 里的 `<sprite>` 目前只做「贴图 + x/y + scale + alpha + flip + scrollx/y」，`skew`、逐帧动画、自定义类不处理。
- 已知**既有引擎 bug（与本兼容层无关）**：谱面事件名只要命中 `custom_events/<事件名>.lua`（mod 内或 mods 根都算），进曲就会 SEGV（`last_stage=PlayState.generateChartNotes:done`；空 body 的 Lua 也崩）。CNE 谱面常用 `Camera Flash` 等事件名，容易被这类全局自定义事件包撞上；临时规避 = 把 `mods/custom_events/Camera Flash.lua` 之类移开。实测：CNE 兼容全关 + 纯 Psych 谱面同样复现。
- CNE 人物 `.hx` 扩展（如 `pico-speakers.hx`、`spirit.hx`）与 CNE 人物编辑器字段。
- CNE 自定义音符行为 `data/notes/*.hx`：谱面里的类型名会透传（`No Anim Note`/`Alt Anim Note` 已别名到 Psych 内建 `No Animation`/`Alt Animation`），但脚本行为不执行。
- CNE 独立事件文件 `songs/<song>/events.json`（CNE 格式 `{events:[...]}`）：不加载，避免把 CNE 事件喂给 Psych 解析器；谱面内嵌 `events` 已转换。
- CNE `.pack` 脚本包、`addons/`、语言文件、`data/config/*` 菜单定制。
- 自定义难度名（非 Easy/Normal/Hard）：Freeplay 里仍按 Psych 三档难度列；CNE 周目声明的 `<difficulty>` 会在 Story 里生效。
- zip 暂存是**落盘解包**（不是内存挂载）：Meteoric/Psych 的资源管线全部基于真实文件路径（`File`/`FileSystem`/`FlxGraphic.fromFile`/`Sound.fromFile`），内存挂载需要重写整条资源管线。暂存目录可随时删除，下次自动重建。

### 排查

- 设置 → 编程 → **脚本加载日志** 打开后，控制台输出 `[CNE-MOD] ...`（谱面转换 / 音频回退 / 人物与周目翻译 / zip 暂存）。
- 调试构建下 `METEORIC_CNE_MOD_FORCE=1` 可无视存档强制开启模组兼容。

## 9. 调试

- 设置 → 编程 → **脚本加载日志** 打开后控制台输出 `[CNE] ...`。
- 调试构建（`./compile-mac.sh debug`）下可用环境变量：
  - `METEORIC_CNE_FORCE=1`：无视存档总开关；
  - `METEORIC_CNE_REDIRECT_FORCE=1`：无视界面重定向子开关；
  - `METEORIC_CNE_MOD_FORCE=1`：无视「CNE 模组兼容」开关。
- 冒烟脚本与证据见 `tools/cne_test_mod/`、`tools/cne_smoke_evidence/`。

## 10. 当前限制

- 不含 Lua：CNE 本身不支持 Lua；本编程层只作用于 HScript，Lua 仍走 Meteoric 原有管线。
- `.pack` 合并脚本格式未移植。
- zip mod 内脚本未验证（zip mod 的包层已支持，见第 8 节）。
- 界面重定向已实现但尚未做实机 smoke（等 UI 测试结束后统一验收）。
- **CNE 模组兼容（第 8 节）尚未做 CNE mod 实机验证**：本轮只过了类型检查与构建，没有 CNE 样本 mod，第二轮由你实机测试。
- 未在 Android / Windows 实机验证。
