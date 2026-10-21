# Meteoric 脚本系统（编程层）

> 让 mod 作者**不碰引擎源码**也能改玩法 / 界面：用 HScript 写脚本，改一行按 F5 即生效。
>
> 实现说明：脚本引擎复用 Meteoric 自身的 `psychlua.HScript`（SScript 4.0.1 + 187 项 preset API），
> **不复制任何第三方引擎的 hscript 实现**；宿主、目录约定、事件层、生命周期全是 Meteoric 自研。
> 入口：设置 → **编程**（主设置与暂停内设置两个入口都���）。

## 1. 开关

全部在 设置 → 编程 里。**总开关默认关**；关闭时引擎行为与本系统落地前完全一致（不加载脚本、
不注册事件钩子、不轮询热重载按键）。

| 选项 | 存档字段 | 默认 | 作用 |
|---|---|---|---|
| 脚本系统（总开关） | `scriptingEnabled` | **关** | 总闸；关闭时下面所有能力都不生效 |
| 全局常驻脚本 | `scriptingGlobalScripts` | 开 | 允许 `scripting/global/` 下的脚本（跨界面常驻） |
| 状态脚本（覆盖界面） | `scriptingStateScripts` | 开 | 允许 `scripting/states/<界面名>.hx` |
| 脚本热重载 | `scriptingHotReload` | 开 | F5 重建当前界面脚本；Shift+F5 重建全局脚本 |
| 可取消事件 | `scriptingEvents` | 开 | 允许脚本拦截引擎决策点（见第 5 节） |

> 分项开关只在总开关打开时才有意义；分项在总开关关闭时仍然可见，靠说明文字提示（不引入新的禁用态样式）。
>
> ⚠ 安全提示：HScript 可访问 `Sys` / `File` / `FileSystem` / `Process` 等引擎能力。
> 只在信任的 mod 上开启总开关。

## 2. 目录约定

```
mods/<mod>/scripting/global/<任意名>.hx        # 全局常驻脚本（跨所有界面）
mods/<mod>/scripting/states/<界面名>.hx        # 状态脚本（接管某个界面）
```

- 扩展名：`.hx`（`.hscript` / `.hsc` / `.hxs` 亦可）。
- `<界面名>` = 目标界面的 Haxe 类名末段，例如 `MainMenuState`、`PauseSubState`、`PlayState`。
- 每个启用的 mod 各自提供一份；多个 mod 的脚本会在同一个界面里**同时运行**（按 mod 启用顺序）。
- 目录不存在就当没有脚本 —— 引擎不会为每个 mod 反复探盘。

## 3. 脚本能拿到什么

- `psychlua.HScript` 的 **187 项 preset**（引擎类 `PlayState` / `Paths` / `FlxSprite` / `Character` /
  `Note` / `Mods` / `DesignTokens` / `Lang`、Flixel 类、`Reflect` / `Type` 反射、`sys` 文件系统 …）——
  与既有 mod 脚本同一套 API。
- 编程层额外注入三个变量：

| 变量 | 含义 |
|---|---|
| `state` | 当前界面对象（`TitleState` / `MainMenuState` / `PlayState` …）；状态脚本里固定是自己的宿主，全局脚本里随界面切换刷新 |
| `game` | PlayState 实例（非游玩界面为 null） |
| `scripting` | 编程层入口（静态类）：`scripting.reloadGlobalScripts()` / `scripting.reloadCurrentStateScripts()` / `scripting.log(msg)` |

- 多语言：`Lang`（整个类）、`tr(key[, args])`、`trOr(key, fallback)`、`getLanguage()`。
  模组脚本里推荐 `trOr(key, '自带的原文')` —— 玩家语言包没这个 key 时自动显示原文，不会露出裸 key。

## 4. 生命周期回调

在脚本顶层定义同名函数即可；**未定义的回调会被静默跳过**，单个脚本报错不会中断同组其它脚本。

| 回调 | 时机 | 范围 |
|---|---|---|
| `create()` | 脚本加载完成 | 状态脚本 + 全局脚本 |
| `update(elapsed)` | 每帧 | 状态脚本（由宿主界面驱动）+ 全局脚本（由 `FlxG.signals.postUpdate` 驱动） |
| `postUpdate(elapsed)` | `update` 之后 | 同上 |
| `stepHit(step)` | 步进变化 | 状态脚本 + 全局脚本 |
| `beatHit(beat)` | 节拍变化 | 状态脚本 + 全局脚本 |
| `destroy()` | 界面销毁 / 热重载替换旧脚本**之前** | 状态脚本 + 全局脚本 |

引擎级回调（**仅全局脚本**，来自 Flixel 信号）：

`preUpdate` / `postUpdate` / `preStateSwitch` / `postStateSwitch` / `preDraw` / `postDraw` /
`focusGained` / `focusLost` / `gameResized(w, h)` / `preGameStart` / `postGameStart`

## 5. 可取消事件（`scriptingEvents` 打开时）

事件在引擎的**关键决策点**派发。脚本可以：

- 改事件字段（都是 public var，直接赋值）；
- `event.cancel()` —— **阻止引擎的默认行为**（自己接管这一段逻辑）；
- `event.cancel(true)` —— 阻止默认行为，但**继续**广播给后续脚本（默认 `cancel()` 会中断广播）。

| 事件 | 派发点 | 脚本能改什么 | `cancel()` 的含义 |
|---|---|---|---|
| `onNoteCreation` | 音符生成后 | `event.note`（可改 `noteType` / `texture` / `hitHealth` …） | 这根音符不参与判定与计分（仍显示） |
| `onChartEvent` | 谱面事件处理前 | `event.value1` / `event.value2`（字符串参数） | 跳过这条谱面事件的默认处理（舞台回调与旧脚本回调仍会走） |
| `onRatingShown` | 评级弹窗前 | `event.ratingImage`（换评级贴图）、`event.visible` | 不显示评级弹窗 |
| `onCameraMove` | 相机移动后 | `event.x` / `event.y`（落点）、`event.zoom` | 这一次相机不移动（回到移动前的位置） |
| `onSongEnd` | 歌曲结算前 | `event.songName` | 不结算（停在游玩界面） |
| `onGameOver` | 死亡判定时 | `event.health`（> 0 则作为复活后的血量） | 不死（血量被拉回 0 以上，避免下一帧再次判定死亡） |

事件对象类型：`ScriptEvent`（基类）/ `ScriptNoteEvent` / `ScriptChartEvent` / `ScriptRatingEvent` /
`ScriptCameraEvent` / `ScriptLifecycleEvent`（都在 `source/scripting/`）。

示例：

```haxe
// 谱面事件：把 Camera Movement 的第一个参数翻倍
function onChartEvent(event) {
    if (event.eventName == 'Camera Movement') event.value1 = '2.0';
}

// 评级：换一张评级贴图
function onRatingShown(event) {
    if (event.ratingName == 'sick') event.ratingImage = 'mySick';
}
```

## 6. 界面跳转

全局脚本（或即将被销毁的旧界面的状态脚本）的 `preStateSwitch` 里 **return 一个界面名**，
即可改写这次跳转的目标：

```haxe
function preStateSwitch() {
    if (FlxG.state is MainMenuState) return 'FreeplayState'; // 跳到自由模式
}
```

- 值为 Haxe 类名末段（按 `states.<名>` 解析）或带包名的完整类名（`'options.OptionsState'`）。
- 解析不到 → 打日志并**保持原目标**（不改变引擎行为）。
- 改写点：`FlxG.signals.preStateSwitch`（`FlxGame.switchState()` 在真正换 state 之前派发）。

## 7. 热重载语义

- **F5**：原地重建**当前界面**的状态脚本组。
  - 旧脚本先收 `destroy()` 再释放实例，随后从磁盘重读并 `create()`。
  - 宿主界面与它的视觉对象**不重建**、不重进关卡。
  - 新组构建失败（文件被删 / 全部解析失败）→ **保留旧组**并打日志。
- **Shift+F5**：只重建全局脚本组，当前界面不受影响。
- 脚本必须在 `destroy()` 里清理自己创建的对象，否则热重载会留下旧对象。
- 键位固定为 F5 / Shift+F5（不占用引擎其它键位；引擎全仓无 F5 使用）。

## 8. 与既有 mod 脚本（`mods/<mod>/scripts/`）的关系

**两条独立的线**，互不干扰：

| | 既有脚本 | 本编程层 |
|---|---|---|
| 目录 | `mods/<mod>/scripts/`（另有舞台/角色/事件脚本目录） | `mods/<mod>/scripting/` |
| 语言 | Lua + HScript | HScript |
| 生命周期 | Psych 风格 `onCreate` / `onUpdate` / `onBeatHit` … | `create` / `update` / `beatHit` … |
| 存活范围 | 一局 PlayState | 全局脚本跨界面常驻；状态脚本跟随界面 |
| 开关 | 无（随 mod 加载） | 总开关 + 分项开关 |

编程层**只读** `scripting/` 目录，绝不重复加载 `scripts/` 下的旧脚本。

## 9. 排查与调试

- 脚本加载/重载/错误都打印到终端，前缀 `[Scripting]`（错误是 `[Scripting][错误]`）。
  启动游戏必须走终端才能看到：`cd "…/Meteoric.app/Contents/MacOS" && ./Meteoric > /tmp/meteoric_debug.log 2>&1 &`。
- 脚本解析失败不会影响引擎，只跳过这一个脚本并在终端报出首行错误。

## 10. 当前限制

- **脚本还不能自己写完整界面**（没有 `ModState` 那样的「脚本定义 State/SubState」机制）；
  状态脚本目前是「接管已有界面」，不是「新增界面」。
- 没有沙箱 / 权限分级：打开总开关即等于给了脚本完整引擎权限。
- 脚本不能调 GC / 内存水位 / 加载管线 / 渲染批次这类**性能旋钮**（引擎内部硬编码）。
- 脚本内不能定义 `class`（SScript EX 模式未开启）。
- 未在 Android / Windows 实机验证（只在本机 macOS 跑过）。
- 本系统是 **Meteoric 自研**，与 Codename Engine 无关：既不兼容 CNE 格式的 mod，
  也不使用 CNE 的脚本实现或目录约定（历史上那套已于 2026-10-05 移除，理由见
  `source/backend/CneModProbe.hx` 的类头注释）。
