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
mods/<mod>/scripting/libs/<任意名>.hx          # 共享脚本库（importScript 加载）
```

- 扩展名：`.hx`（`.hscript` / `.hsc` / `.hxs` 亦可）。
- `<界面名>` = 目标界面的 Haxe 类名末段，例如 `MainMenuState`、`PauseSubState`、`PlayState`。
- 每个启用的 mod 各自提供一份；多个 mod 的脚本会在同一个界面里**同时运行**（按 mod 启用顺序）。
- 目录不存在就当没有脚本 —— 引擎不会为每个 mod 反复探盘。
- **执行顺序**：同一组内可用文件名前缀显式控制（`00_`…`999_` 数字越小越先，`z_` 固定最后，
  无前缀默认 500）。同优先级按 mod 启用顺序、再按文件名。**全部不带前缀时顺序与旧版完全一致**。
  例：`00_input.hx` → `50_ui.hx` → `z_debug.hx`。

### 2.1 脚本库复用（importScript）

把可复用逻辑放 `mods/<mod>/scripting/libs/`，脚本里直接加载：

```haxe
var util = importScript('util');        // → mods/<mod>/scripting/libs/util.hx
var helper = importScript('./helper');  // → 当前脚本同目录的 helper.hx
```

- **路径解析**（不写扩展名时自动试 `.hx` / `.hscript` / `.hsc` / `.hxs`）：
  1. `mods/` 开头 → 按仓库根解析（Android 走 `Paths.mods`）；
  2. `./` / `../` 开头 → 相对当前脚本所在目录；
  3. 其它 → 同 mod 的 `scripting/libs/<路径>` 优先，其次相对当前脚本目录。
- **作用域**：库的顶层函数/变量会并入当前脚本（当前脚本已有的名字优先），
  所以直接写 `helper(...)` 即可，不必 `util.helper(...)`。
- **生命周期**：库脚本挂在当前脚本组里，`create` / `update` / `stepHit` / `destroy` 等回调
  与主脚本一样被自动广播（每个库实例各跑一次，不会双重调用）。
- **控制库**：`importScript` 返回库的 `HScript` 实例 —— `lib.active = false` 停用、
  `lib.invoke('fn', [args])` 取原始返回值、`lib.get('x')` / `lib.set('x', v)` 读写变量。
- 同一个库被不同脚本 import 会各得一份独立实例（不共享状态）；要共享状态请只 import 一次，
  再把返回对象传给其它脚本。
- 无脚本组场景（Lua `runHaxeCode`）也能用：库独立加载，随调用方脚本一起销毁。

## 3. 脚本能拿到什么

- `psychlua.HScript` 的 **189 项 preset**（引擎类 `PlayState` / `Paths` / `FlxSprite` / `Character` /
  `Note` / `Mods` / `DesignTokens` / `Lang`、Flixel 类、`Reflect` / `Type` 反射、`sys` 文件系统 …）——
  与既有 mod 脚本同一套 API。
- 编程层额外注入三个变量：

| 变量 | 含义 |
|---|---|
| `state` | 当前界面对象（`TitleState` / `MainMenuState` / `PlayState` …）；状态脚本里固定是自己的宿主，全局脚本里随界面切换刷新 |
| `game` | PlayState 实例（非游玩界面为 null） |
| `scripting` | 编程层 API（`scripting.ScriptingApi` 实例）：`openState` / `openSubState` / `closeSubState` / `backToMainMenu` / `center` / `centerAxes` / `getPerfStats` / `setPerfOption` / `collectGarbage` / `openRepl` / `log` / `logError` / `reloadGlobalScripts` / `reloadCurrentStateScripts`（完整清单见 `source/scripting/ScriptingApi.hx`）|
| `data` | 仅脚本界面：打开界面时传入的数据（脚本界面里也有 `state.data`，两者同值）|

- **脚本可以直接 `import` 引擎类**（SScript 4.0.1 没有 import 白名单，走 `Type.resolveClass`）：
  ```haxe
  import flixel.group.FlxTypedGroup;
  import states.FreeplayState;
  import objects.Character;
  ```
  ⚠ 被 `--dce full` 裁掉的类解析不到（`Type.resolveClass` 返回 null）—— 引擎内被 Haxe 引用过的类都在。
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

## 7. 脚本界面（用脚本写完整界面）

除了「接管已有界面」（第 2 节的状态脚本），脚本还可以**自己写一个新界面**。

```haxe
// 在任意脚本里：
scripting.openState('MyScreen');                  // 打开脚本界面
scripting.openState('MyScreen', ['数据', 3]);      // 带数据（数组/任何 Dynamic）
scripting.openSubState('MyPanel', ['数据']);       // 打开脚本子状态（盖在当前界面上）
scripting.closeSubState();                        // 关闭当前子状态
scripting.backToMainMenu();                       // 回主菜单
```

- 脚本文件位置：`mods/<mod>/scripting/states/MyScreen.hx`（与状态脚本同一目录约定）。
- 脚本界面里能做什么：
  - `state` —— 宿主（`ScriptState` / `ScriptSubState`）：`state.add(sprite)` 把控件加进界面；
  - `state.data`（或直接用注入的 `data`）—— 打开时传入的数据；
  - `create()` / `update(elapsed)` / `beatHit(beat)` / `stepHit(step)` / `destroy()` 回调；
  - `MenuText` —— 引擎同款字体与描边的文本控件；`FlxSprite` / `FlxText` / `FlxCamera` 等照常可用；
    主题色用 `DesignTokens.*`。
- 生命周期：脚本的 `create()` 在界面初始化过程中执行（宿主 `create()` 末尾），
  `destroy()` 在界面销毁 / F5 重建前执行 —— 脚本自己创建的对象要在 `destroy()` 里清理。
- 界面跳转：`preStateSwitch` 里 return 界面名（见第 6 节）也能跳到脚本界面
  （return 的是**脚本名**，不是类名）。

## 7.1 写脚本必须知道的两个坑（引擎侧限制，不是脚本的错）

**① 只被脚本调用的方法会被 release 构建裁掉**

release 构建开 `--dce full`：只被**脚本反射调用**、Haxe 侧没有引用的方法会被裁掉，
运行时反射拿到 null 方法引用 → 抛 `Null Function Pointer`（脚本表现为「这行一调就炸」）。

- 本引擎的对策：脚本可见的 API 全部做成**实例方法**（`scripting.ScriptingApi`）并标 `@:keep`。
  ⚠ `@:keep` 对 **static 方法无效**（实测：标了照样被裁），对实例方法有效。
- 这条也解释了为什么 `scripting.log()` 一直好用：它同时被引擎侧调用，没被裁。

**② Flixel 的 inline 方法不能被脚本直接调用**

`FlxObject.screenCenter` 是 `inline` 方法，hxcpp 下没有真实函数体 → 反射调用同样抛
`Null Function Pointer`。所以脚本里要写 `scripting.center(sprite)`（Haxe 侧包装），
不能写 `sprite.screenCenter()`。`scripting.centerAxes(sprite, axes)` 是带轴向的版本
（flixel 5.x 的 `screenCenter` 收 `FlxAxes`，不是摄像机）。

## 7.2 性能面（脚本读性能 / 改受控旋钮）

```haxe
var st = scripting.getPerfStats();
trace(st.fps);        // 绘制帧率
trace(st.rssMB);      // 进程常驻内存（MB；采样线程每 2s 问一次 OS，首次调用后约 2s 才有值）
trace(st.visualFold); // 当前视觉折叠档

scripting.setPerfOption('visualFold', 2);   // 0=关 1=75% 2=50% 3=25%（只影响视觉副本，不参与判定）
scripting.setPerfOption('gcBreathing', true);// GC 呼吸阀：进曲设最低空余水位 + 每 20s 强制全量回收
scripting.collectGarbage();                  // 立刻来一次全量 GC（约 20~80ms 顿挫）
```

- **旋钮白名单**（不在名单里的一律拒绝，返回 `false`）：
  `gcBreathing`(bool) / `visualFold`(int 0..3) / `perfMode`(bool) / `runtimePack`(bool)。
- 这 4 个在设置页（性能页 / 图像页）里都能看到，脚本改的就是用户改的那份值。
- **降采样相关项刻意不开放**（`textureScale` / `characterTextureScale` / `backgroundScale`）——
  脚本调它们一律返回 `false`。
- 生效时机：`visualFold` 只影响之后生成的音符，`runtimePack` 只影响之后加载的贴图。

## 8. 热重载语义

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

## 9.1 游戏内 REPL（F2）

游戏内实时执行 HScript —— **改一行立刻生效，不用重开游戏、不用重开歌曲**。

| 操作 | 效果 |
|---|---|
| **F2** | 打开 / 关闭 REPL |
| 回车 | 执行当前输入 |
| ↑ ↓ | 滚动输出区 |
| ESC | 关闭 REPL |
| 鼠标滚轮 | 滚动输出区 |

- **总开关关闭时 F2 无效**（与本层其它能力一致）。
- REPL 是**盖在当前界面上的覆盖层**，不是子状态：游戏照常运行，改一个变量立刻能看到效果。
- 界面里能拿到的东西和脚本**完全一样**（同一套 preset + `state` / `game` / `scripting` / `data`），
  所以「在脚本里能写的东西，在 REPL 里也能试」。
- 输入框用引擎的 `objects.UIInputBox`（原生 TextField，系统输入法可用）。
- REPL 打开期间会屏蔽游戏输入（打字不会被当成按键 —— 游玩时方向键 = 音符）。
- 脚本也可以开 REPL：`scripting.openRepl()`。

```haxe
// 例子：改一个当前界面的属性
state.alpha = 0.5;
// 例子：看性能快照
var st = scripting.getPerfStats();
trace('fps=' + st.fps + ' rss=' + st.rssMB);
```

**变量跨行保留**：

```
> var x = 41
> x + 1
42
```

> 这一条是**特意实现**的：SScript 4.0.1 的 `Interp.execute()` 每次调用都会重建 locals 表，
> 顶层 `var` 在语句块结束时还会被撤销 —— 直接用它做 REPL 只能当一次性沙盒。
> 引擎改走 `Interp.exprReturn()` 并逐条执行顶层语句，locals 不重置，变量跨行可见。

## 9.2 脚本管理器（暂停菜单 / 自由选歌）

「设置 → 暂停」里的**脚本管理**，现在同时管三类脚本：

| 类型 | 位置 | 标记 |
|---|---|---|
| 旧玩法脚本 | `mods/<mod>/scripts/*.lua` / `*.hx` | 无标记 |
| 全局常驻脚本 | `mods/<mod>/scripting/global/*.hx` | `全局 ·` |
| 状态脚本 | `mods/<mod>/scripting/states/*.hx` | `界面 ·` |

| 操作 | 效果 |
|---|---|
| ↑ ↓ | 选择 |
| 回车 | 开关脚本（关闭 = 文件名加 `.disabled` 后缀） |
| **→** | 把选中的**状态脚本**作为脚本界面打开（`scripting.openState`） |
| ESC | 返回 |

- 列表里的脚本来自**与引擎同一份「已启用的 mod」列表**（`Scripting.listInstalledScripts()`），
  所以列出来的就是引擎真的会加载的，不会「列了但不生效」。
- `.disabled` 后缀的脚本也会列出（标成「关」）；引擎侧天然跳过它们（只认 `.hx` 结尾）。

## 10. 当前限制

- **脚本写界面还缺引擎级控件**：脚本能加 `FlxSprite` / `FlxText` / `MenuText`，
  但引擎自己的成套控件（`BackButton` 这类带主题/动效的组件）**没有暴露给脚本**，
  脚本界面里的「返回按钮」得自己用 `FlxSprite` 拼。
- 没有沙箱 / 权限分级：打开总开关即等于给了脚本完整引擎权限。
- 脚本不能调 GC / 内存水位 / 加载管线 / 渲染批次这类**性能旋钮**（引擎内部硬编码）。
- 脚本内不能定义 `class`（SScript EX 模式未开启），也**不支持 map 字面量** `{...}`
  （SScript 4.0.1 的限制，CNE 的 hscript-improved 才支持）—— 传数据用数组或 `__newMap()`。
- **mod 内 `source/` 的 Haxe `class` 不能直接 `import`**：普通解释器只在解析期解析
  **已编译进引擎**的类（SScript `hscriptBase/Parser.hx` 的 `Type.resolveClass`），
  `mods/<mod>/source/.../*.hx` 不在编译产物里；EX 模式（`classSupport=true`）又只允许
  `class` / `package` / `import`，不能与普通脚本语句混用，普通解释器的 `new` 也走
  `Type.createInstance`（`hscriptBase/Interp.hx`），无法实例化 EX 脚本类。
  - 共享逻辑请写成**脚本库**（`scripting/libs/` + `importScript`，见 §2.1）；
  - 强类型 / 高性能工具类请编译进引擎（`source/`）后在脚本里 `import`；
  - 运行期加载 mod 类需要改 SScript 的 `Interp.cnew` / EX 桥接层
    （「爆改 lib」，有维护成本，需单独立项评估）。
- 未在 Android / Windows 实机验证（只在本机 macOS 跑过）。
- 脚本管理器的**列表显示**已实机验证（全局 / 界面两类脚本都正确列出，类型标记、开关状态、
  提示文案都对）；但 **→ 打开脚本界面**这一步未做实机按键验证（自动化按键没送达游戏窗口）。
- REPL 目前只在**当前界面**生效：跨界面的变量（全局脚本里的 var）不在 REPL 的作用域内，
  REPL 的变量也只活在这一次 REPL 会话里（关掉即销毁）。
- 本系统是 **Meteoric 自研**，与 Codename Engine 无关：既不兼容 CNE 格式的 mod，
  也不使用 CNE 的脚本实现或目录约定（历史上那套已于 2026-10-05 移除，理由见
  `source/backend/CneModProbe.hx` 的类头注释）。
