---
name: meteoric-system
description: Meteoric Engine 系统域（MD3 化）界面规范：Options、Pause、GameOver、Results、Mods 管理与联机/脚本子界面。圆角面板、MD3 令牌、统一动效与三套输入；所有系统域改动先读本 skill。
---

# Meteoric 系统域：Options / Pause / GameOver / Results / Mods

## 域判定

以下界面属于**系统域**（MD3 化）：`OptionsState` 及其全部子页（`BaseOptionsMenu` 派生）、`PauseSubState`、
`GameOverSubstate`、`ResultsSubState`、`ModsMenuState`、`OnlineMenuState`、`ModInstallUI`、
脚本/输入/重置类子界面（`ScriptManagerSubstate`、`ResetScoreSubState`、`GameplayChangersSubstate`、`ControlsSubState` 等）。

系统域 = 现有"圆角磨砂玻璃 + 三套操作"语言的 MD3 升级版：**令牌化色彩、统一形状、克制动效、即时反馈**。
视觉上不得出现涂鸦贴图、卡通描边海报、节拍跳动。

## 统一结构（现状即基准）

### 面板（panel）

- 绘制：`BaseOptionsMenu.makePanel(x, y, w, h, ?radius = 20, ?fill = 0xCC161622, ?border = 0x45FFFFFF)`。
  实现 = `FlxSprite.makeGraphic` + `FlxSpriteUtil.drawRoundRect` × 2（填充 + 1.5px 描边），**一次绘制**，禁止逐帧重建。
- 圆角：大面板 22，底部条/小卡 14，按钮 10 或全圆。
- 面板间距 14px；面板内边距 ≥ 20px；文本左缘 ≥ 72（含面板偏移后），右缘 ≤ 1100，底部 ≤ 648。
- 弹层背景：暂停内嵌 = 0.6 α 黑遮罩（`FlxSprite.makeGraphic` 黑 + `alpha 0.6`，不做 `menuDesat` 整屏换图）；主菜单路径 = `menuDesat` tint `0xFFea71fd`。

### 文本

- 标题 `future.ttf` 30 白 + 黑描边 2（如 `BaseOptionsMenu` `titleText`）；栏目标题 26 `0xFFD7D7E0`。
- 正文/选项 20–24 白；次级说明 `0xFFCFCFDC`；数值右对齐（`VALUE_X = 420`、`VALUE_W = 240` 模式）。
- 中文简体；判定缩写保留英文。
- 行距：新代码 32/40/48/56；存量 34（Pause/Results）不动。

### 组件（MD3 组件语义）

| 组件 | 现有实现 | 规范 |
| --- | --- | --- |
| **开关（胶囊 toggle）** | `objects/ToggleSwitch.hx`（**系统域布尔项的唯一形态**） | 轨道胶囊 **96×32**（圆角 = 高的一半）+ **22px 纯白圆钮**；开 = `DesignTokens.primary` 填充 **+ primary 描边**，关 = `0x66161622` 填充 + `panelOutline` 描边（1.5px）；切换动画在**圆心空间** `FlxMath.lerp(..., elapsed * 18)`，首次落位**直接吸附**（否则会从错误初值滑进来）；命中区外扩 12px → 高 **56**（触控红线） |
| 选项行 | `rows:Array<FlxText>` + `selectorBar` | 选中行 α=1 + `selectorBar` 跟随；未选中 0.55–0.78；tween 先 `cancel()` 再启动 |
| 滑块/数值 | 键盘 hold + 移动端 `◀▶` 长按 | `PAD_HOLD_DELAY = 0.5` 秒延迟、`PAD_STRING_STEP = 0.2` 秒步进 |
| 下拉/字符串档 | `Option.hx` 档位 | 弹出子面板（非全屏 State）；圆角 14；选项表用 `MenuText` |
| 按钮 | `BackButton`、文本按钮 | filled / tonal / text 三种语义；按下 0.97 缩放 100ms；触控目标 ≥56×56 逻辑 px |
| 对话框 | `Prompt`、`TextInputPrompt`、`CrashTestPrompt` | 圆角 14 + `scrim` 遮罩；确认/取消按钮 `error`（危险操作）/`primary`（主操作） |

#### 开关（胶囊）落地细节 —— 踩过的坑，改前必读

1. **轨道必须"原地重绘"**：`makeGraphic(..., unique: true)` 建一次，之后每次切换
   `track.pixels.fillRect(track.pixels.rect, TRANSPARENT)` 清底再画。**禁止**用 `makeGraphic` "重建"——
   尺寸不变时命中的是缓存里同一张 BitmapData，旧像素不会被清 → 「开」态的 primary 填充会残留在「关」态上
   （同尺寸精灵还会互相串图）。
2. **夹取的是圆心、不是精灵左边框**；精灵 x 由圆心换算 `x = track.x + center − 半径`。
   从前把"轨道内相对量"（16/80）直接写进 `knob.x`，圆钮被画到屏幕左侧、距轨道 409px —— 即「圆点飞出」事故。
3. **行位动态的列表**（如模组列表）用 `ToggleSwitch.setPosition(x, y)` 整组移动（轨道 + 圆钮一起），
   不要只改 `track.y`，否则圆钮会留在旧行高。
4. **主题色**：开态填充/描边是 `DesignTokens.primary`（运行时令牌）→ 宿主在刷新行时调 `refreshTheme()` 重绘。
5. 组合方式：组件**两个精灵由宿主自己 `add()`**（与 `ColorSwatchPicker` 同款），宿主负责命中、音效与存档；
   组件**不碰** `ClientPrefs` / `Option`。

**开关统一清单（2026-09-16 完成，新代码禁止再写方框复选框）**：

| 界面 | 实现 |
| --- | --- |
| 单界面设置内容区 `OptionsPane` | `switchCols:Array<ToggleSwitch>`（原 `checkBgs/checkFills` 已删） |
| 分页设置页 `BaseOptionsMenu`（暂停内嵌 7 页） | 同上；`LIST_X` 108 → **164**（胶囊 96 宽后让位），`CHECK_X` 56 |
| 模组列表 `ModsMenuState` | 同上；行位动态 → `setPosition()`；`LIST_X` 88 → **164** |
| 更新界面 `OutdatedState` | 私有胶囊实现**已收敛**为共用组件（圆钮坐标模型随之固化） |
| 4 个编辑器页（对话/角色/周目编辑器） | **不动**：`FlxUICheckBox` 属非主题域工具界面（见 meteoric-design 例外表） |


- 状态层：hover `0x18` 白、pressed `0x30` 白叠加，非实体色块。
- 新组件必须提供**键盘/鼠标/触控三套**操作路径；触控长按与键盘 hold 分别独立计时（现有 `padHoldTime` 模式）。

### 绘制层级（z-order）

绘制顺序 = `FlxGroup.members` 顺序 = `add()` 的先后，**后 add 的盖住先 add 的**。列表类界面的硬性顺序：

```
背景 → 面板 → 选中高亮条（selectorBar / rowBar） → 行文字 → 按钮 / 状态行
```

- 高亮条必须在**行文字之前** add。反了就是「选中框把分类文字压住/糊住」——列表文字与框在几何上必然重叠，
  只有靠层级才不会互相打架（2026-09-12 `OptionsState` 实测：`selectorBar` 建在 rows 循环之后 → 文字被盖）。
  已按此修正：`OptionsState`。**做新列表界面时按上面这条顺序写，不要照抄旧文件的历史顺序。**
- 反例警示：容器列表 `ContainersMenuState` 用的是**每行一个 `rowBar`**，它把 bar 与文字写在同一个循环里
  （`add(bar)` 在 `add(t)` 之前）—— 结果正确，但顺序是巧合而非契约，别当成模板。
- 同类界面（`ModsMenuState`、`MasterEditorMenu`）仍是 selectorBar 后 add 的历史顺序，**尚未收敛**；
  要动它们的层级时，按本节顺序改，别只改一处造成两套约定。

### 输入（三套，既有已验证模式）

1. `WheelScroll` 滚轮限速；`mouseActive` 输入分离（键盘后冻结鼠标，移动 > 10px 恢复）。
2. 进入界面防误触：`nextAccept = 5`（忽略确认帧）+ `timeForMoving = 0.1`（子状态忽略输入）。
3. 移动端菜单 pad：右下 `A` 确认、`◀▶` 调节（`menuPad`）；GameOver 用 A/B pad。
4. 系统返回键（Android）：返回上一级界面（Options → 主菜单；Pause → 游戏；不带 * 的页面 → 上一页），**禁止**直接退出游戏。

## 各界面细则

### 单界面设置（OptionsState = 侧栏 + 内容区，2026-09-16 落地）

**结构**（一个界面代替原来的"两级跳转"）：

```
┌ 侧栏 SettingsRail 230×570 ┐┌ 内容区 OptionsPane 956×570 ─────────────┐
│ 40,70 起；行距 50、可见 9 ││ 284,70 起；标题 y100；行首 y152、行距 52 │
│ 「设置」标题 + 13 个分区  ││ 可见 8 行（带预览带的分区 6 行）        │
└───────────────────────────┘└ 说明行 / 色板条 / 预览带 y464..632 ─────┘
              底部提示条 40,662,1200,48（Tab 切换焦点 · ↑↓ 选择 · ←→ 调整 · Enter 切换 · R 重置）
```

- **分区三类**（`OptionsState.buildRoster()`）：
  ① **选项分区**（7 个）：`BaseOptionsMenu` 子类在 **headless** 模式下构造 —— 子类照旧 `addOption()` 并挂 `onChange`，
  只是不建 UI；选项表与回调由 `OptionsPane` 渲染/驱动（**选项定义只有一份，禁止在新宿主里重抄选项表**）；
  ② **画布分区**（箭头配色 `NotesPane` / 按键设置 `ControlsPane`）：自带绝对布局，接受内容区矩形（`hosted` 分支），
  整屏路径（暂停内嵌）用 `new XXXPane(null)` 跑同一份代码；宿主焦点离开内容区时置 `inputEnabled = false`（只绘制不吃键）；
  ③ **整屏页出口**（调整延迟/自定义界面/容器/移动触控）：**点侧栏即一步直达**（不进内容区），容器因"启动即整机重启"不做就地化。
- **焦点模型**：默认焦点在内容区；`Tab` 在两区间迁移；侧栏 ↑↓=逐项、**滚轮 = 页面滚动**（一格翻一整页 = `ROWS_VISIBLE` 项，
  间隔 ≥110ms，位移走时间插值 `elapsed * SCROLL_LERP(14)`，因此观感是"整栏滑过去"而不是逐项闪）；点侧栏行 = 选分区并接管焦点。
- **预览带**：分区声明 `BaseOptionsMenu.previewRows = 6` 即可把选项行窗口缩短、腾出 y 464..572 的预览带；
  预览容器经 `BaseOptionsMenu.headlessVisualHost`（静态口，因为子类在**构造期**就 `addVisual()`）交给宿主，
  宿主按**叶子精灵包围盒**在带内居中（普通 `FlxGroup` 没有 x/y，且分区常再套一层 `FlxTypedGroup` → 递归收集叶子；
  同一容器只摆一次，重复平移会累加）。例：音符皮肤预览（5 个真尺寸箭头）。
- **落盘点**：单界面没有"关子页"这一步 → 必须在 `goBack()` / 整屏页出口 / `destroy()` 三处 `saveSettings()`，
  否则 `destroy()` 里的 `loadPrefs()` 会把本次改动读没。
- **兼容契约（勿破）**：`OptionsState.onPlayState`（曲目内进设置后返回要重载曲目）、`pendingSelectLabel`
  （整屏页返回按标签恢复分区 —— 旧实现靠 `static curSelected`，融合后必须显式记标签）、`enterContainersMenu()`
  （容器入口"不挂转场"，黑屏回归风险点）。
- **行窗口是变量**：`OptionsPane.rowsVisible`（默认 8，预览带分区 6）。`refreshRows()` 末尾**必须显式隐藏尾部未用行**
  （`for (r in rowsVisible...rows.length)`）—— 漏了就会在预览带上留下"没有文字的空开关"（2026-09-16 实测）。

### Options（BaseOptionsMenu + 子页）

- 布局：左面板（40,70,680,570，选项列表 + 标题）、右面板（740,70,460,570，说明）、底部条（120,662,1040,48）。
- 选项行：`LIST_X 108`、`LIST_Y 152`、`ROW_GAP 56`、`ROWS_VISIBLE 8`；说明文字单行，超出宽度截断为省略号。
- **值文本（右列 VALUE_X/VALUE_W）必须单行**：`FlxText` 默认 `wordWrap = true`，固定宽 240 下长值会折行
  压到相邻行（实测：Score 栏格式那一大串 `{score} // {misses} // …`）。
  `BaseOptionsMenu` 已对 `valueTexts` 统一设 `wordWrap = false`，超出部分由 fieldWidth 裁掉。
- **值放不下时用 `Option.valueHint` 显示固定提示**（如 `点击查看`），而不是硬塞真实值；
  显示优先级：`valueHint` > `displayFormatter` > `displayFormat` / `displayOptions`。
  三者都**只影响显示，不写回存储值**；`valueHint` 分支刻意放在读存档之前（省一次反射）。
- `scrollIndex` 翻页：低频动效（200ms，`quadOut`）；值变化即时（不 tween）。
- 子页（Graphics/Interface/Gameplay/Note/Controls…）继承 `BaseOptionsMenu`，禁止复制粘贴布局常量；新增子页直接继承。

### 主题色（Theme Color，已落地）

系统域强调色**一律走令牌**，不再写字面量；令牌中心 = `source/backend/DesignTokens.hx`。

- 入口：**设置 → 界面 → 主题色**。固定 10 色：
  青（默认）/蓝/紫/品红/橙/金/绿/青绿/红/粉；存 `ClientPrefs.data.themeIndex`（`Int`，全字段反射存档 → 无需迁移代码）。
- **两套输入并存（三套覆盖）**：选项行负责键盘/手柄（左右调节）；色块区负责鼠标/触控（直接点）。
  两者共用**同一条**取值链路 —— 点色块最终也是走 `changeOptionValue(1)`，
  因此音效、存档、`onChange` 即时换色、长按连发行为完全一致，不会出现"两套行为"。
- 色块区实现：`source/objects/ColorSwatchPicker.hx`（可复用组件）+ `BaseOptionsMenu.setupThemeSwatches()`（默认关闭的挂载点）。
  组件只负责绘制/命中/演出，**不碰** ClientPrefs 与 Option；子类在 `super()` **之前**调用挂载
  （基类构造末尾的 `changeSelection()` 会读 `themeSwatches`）。
- 色块区几何（**已核算，勿随意改**）：底板 y 586 高 52、色块圆心 y 612、直径 44、步进 58、10 格总宽 522 在左面板居中。
  末行 `selectorBar` 占 541–585，色块区必须 **≥586** 才不重叠；再往下会被底部条（662）挡住。
  热区 44+6×2 = **56 逻辑 px**（移动端触摸目标红线）。
  另：色板**只在该行被选中时显示整块**（`refreshSwatches()` → `ColorSwatchPicker.setVisible()`）。
  切到其它选项时必须 `visible = false`（含底板），**不能只降 alpha**：右面板的 `descText` 自 y=170 起
  向下延伸且无裁剪，会与 y 602–636 的色块区视觉打架，且半透明残留会让人误以为仍可点（实测反馈）。
  `setVisible(false)` 内部需同时复位悬停态与缩放，否则重现时会出现「鼠标不在上面、环却亮着」的残留。
- 状态表达（不得只用颜色）：选中 = 圆环（键盘焦点时主题色环 / 鼠标时白环）；悬停 = 放大 1.08；
  按压 = 缩小 0.94；均为 100ms `quadOut`，且复用的 tween 先 `cancel`。
  **悬停不改变选中**，只做预览放大。
- 绘制纪律：全部在 `new()` 内一次画好（`FlxSpriteUtil.drawCircle`，BackButton 同款），
  `update()` 里**零绘制调用**；禁止逐帧 `makeGraphic`。
- 脚本联动：脚本 `setThemeColor` 后会经 `DesignTokens` 的监听者模式通知色块同步选中环
  （`addThemeListener` / `removeThemeListener`）；**宿主必须在 `destroy()` 摘除监听**，否则留下僵尸回调。
- ⚠⚠ **硬性契约（2026-09-11 两次实测事故，务必遵守）：实例字段与 display group 的一切初始化
  都必须在 `super()` 之后。**
  子类在 `super()` 之前**既不 `add()`、也不给实例字段赋值**——两种做法都会失效：
  ① `add()`：`FlxGroup.members` 由 `FlxGroup.new()` 创建，`super()` 之前 `members` 为 null
     → `Null Object Reference`（报错点是 `FlxGroup.hx` 的 `members.indexOf`，看着像渲染问题）；
  ② **给实例字段赋值**：hxcpp 把字段初始化器（`var x = ...`）放在**基类构造**里执行，
     `super()` 会重跑一遍初始化，把之前赋的值**清回初始值**
     → 表现为「代码明明执行了、对象也创建了，却毫无效果」（本次事故：`themeSwatches` 被清成 null、
     `_themeSwatchesWanted` 被清回 false，守卫直接返回，色块永不挂载）。
  正确形态：子类 `addOption(...)` → `super()` → `setupThemeSwatches()`（登记意图）→
  `ensureThemeSwatchesAdded()`（创建 + 挂载）；另有 `create()` 与首个 update 帧两道兜底。
  排查建议：这类「静默失效」**不要靠读代码推断**，直接在可疑分支落盘日志（见
  `CrashHandler.dumpDevLog()`，`#if meteoric_debug` 下可用），用事实定位。
  原因：`FlxGroup` 的 `members` 数组是在 `FlxGroup.new()` 内 `super(); members = [];` 才创建的
  （flixel 5.2.2 源码），而 `FlxGroup.add()` 入口就是 `members.indexOf(Object)`。
  在 `super()` 之前 `add()` → `members` 为 null → **`Null Object Reference`**，
  报错点正是 `FlxGroup.hx` 的 `members.indexOf` 那一行 —— 堆栈看着像渲染/绘制问题，极易误判方向。
  正确形态：`setupThemeSwatches()` 只构造（不 add）→ `ensureThemeSwatchesAdded()` 在 `create()` 里 add。
  flixel 的 `openSubState()` 是在**构造完成之后**才调 `create()`，那时 group 已就绪。
  通用规则：**任何在 `super()` 之前执行的初始化代码都不得触碰 group（add/remove/insert）**。
- 派生规则：切换色板时 **`primary` / `secondary` / `tertiary` 三个令牌同步更换**
  （外加 `menuTint` = `menuDesat` 背景 tint）。`surface` / `outline` / 判定色 / 成功失败语义色**不参与**。
- 生效时机：`ClientPrefs.loadPrefs()` 末尾调 `DesignTokens.initFromPrefs()`（启动应用存档值）；
  其余界面在**下次 `create()`** 读新令牌。**Options 页内**由
  `BaseOptionsMenu.refreshThemeVisuals()` 做即时预览（只改 menuDesat tint + 重排值文字，不重绘面板、不 tween）。
- 新增系统域界面：颜色写 `DesignTokens.primary` / `.secondary` / `.tertiary`，**禁止**
  `static final X = DesignTokens.primary`（静态初始化会冻结取值，主题切换即失效）。
- 脚本 API：`setThemeColor(index, ?persist=false)` —— 默认**临时覆盖**（不写玩家存档），
  `persist=true` 才落盘；另有 `getThemeColor/getThemeColorName/getThemeColorKey/getThemeColors/
  getThemeColorCount/getThemePrimary/getThemeSecondary/getThemeTertiary`。
  Lua 走 `ExtraFunctions.implement()`，界面脚本走 `MenuScript.addLocalCallback`，HScript 走 `HScript.preset()`。
  注意：界面脚本改色后**已创建**的元素不会自动重绘，需重开界面或等下次进入。

### Pause（PauseSubState）

- 左面板：信息面板（40,70,600,200）+ 菜单面板（y 290）；右统计面板（680,70,560）。
- 文本安全：`SAFE_MARGIN 72`、`SAFE_RIGHT 1100`、全部左对齐（历史截断教训）。
- 菜单项 `MenuText` 行距：`MENU_LINE_GAP 34`（内部 ×1.3 ≈ 44）。
- 打开时压暗 0.6 黑遮罩（非 `menuDesat`）；**必须**维持 SubState 栈（`persistentUpdate/persistentDraw` 规则），禁止改成整屏新 State 造成视觉跳变。
- 功能项：返回游戏/重新开始/跳过时间/更换难度/脚本管理/游玩设置/设置/返回主菜单（顺序与文案保持现状）；新增项追加在"返回主菜单"之前。
- 返回主菜单闪退修复（转场期 `persistentUpdate=false` + LuaJIT `pushing nil`）**不得回归**；改动转场必须复测。

### GameOver（GameOverSubstate）

- 保留 FNF 经典表现：角色死亡动画、相机跟随、`fnf_loss_sfx` / `gameOver` / `gameOverEnd` 音效流。
- 属于系统域的只有：角落返回/重试按钮与提示、移动端 A/B pad、`deathDelay` 逻辑（Psych 1.0.4 兼容）。
- **不**改造成 MD3 卡片舞台；**不**改变 `resetVariables()` 契约（`characterName` / `deathSoundName` / `loopSoundName` / `endSoundName` / `deathDelay`，Lua 可覆盖）。
- 死亡→GameOver 的延迟动效：单次、≤800ms；期间不响应输入（按钮出现即结束延迟）。

### Results（ResultsSubState）

- 布局（1280×720 基准，`PANEL_TOP 96` 起）：左（40,560 宽）曲目信息 172 高 + 判定统计 168 高 + 操作菜单；右（620,620 宽）本局数据 288 高 + KE 命中散点图。
- 列对齐：`JUDGE_COL0 = X+20`、`JUDGE_COL1 = X+320`、`JUDGE_VAL_GAP 175`（MARVELOUS 较长）。
- 数字滚动：`lerpScore` / `lerpRating` 500–800ms `quadOut`；判定行不滚动（即时）。
- 统计值右对齐标签左对齐；标题 `TITLE_Y 22`；安全底部 648。
- 联机结算（`createSimplified`）：对方成绩栏随面板一起淡入（存量 0.4s `quartInOut`，目标 0.25s `quadOut`）；`refreshOpponentBlock` 每帧文本更新属**网络态内容刷新，禁止对数值做动画**；对方栏次级文本用 `onSurfaceVariant`（`0xFFD7D7E0`）替代 `0xFFA9A9B8`。判定色与 KE 散点图颜色为内容色，不参与令牌化。

### Mods / 联机 / 安装器

- `ModsMenuState`、`OnlineMenuState`、`ModInstallUI` 一律沿用本 skill 的面板/文本/输入规范；不使用手绘域元素。
- 列表行高 ≥ 40；启用/停用状态用 `primary`/`onSurfaceVariant` 区分，**禁止**只用文字颜色表达状态（需 + 图标/勾选）。
- 安装/下载进度：进度条用 `primary` 填充 + `surfaceVariant` 底；更新/取消按钮按语义色。

### Lua 图形化编程编辑器（LuaGraphEditorState）

- 入口：`MasterEditorMenu` → 「Lua 图形化编程」；**Android 上该条目直接隐藏**（`#if mobile` 裁剪 `optionShit`），
  因为本界面依赖鼠标拖拽与键盘，触屏上没有可用的完整操作路径（见 meteoric-mobile 的"不暴露用不了的界面"原则）。
- 域归属：**系统域**。三个圆角磨砂面板（分类 156 / 积木 300 / 画布 720，y 70 起高 570）+ 底部条
  （40,**652**,1200,**58**；2026-09-15 由 662/48 加高：完整键位提示一行装不下）；配色一律走令牌，
  判定/成功失败语义色用局部常量 `COLOR_OK/COLOR_ERROR`
  （`DesignTokens` **没有** `error` 字段，别写 `DesignTokens.error`）。
- **层级契约同样适用**：分类高亮条与积木列表高亮条必须在**行文字之前** `add()`。本界面两处都已按此写。
- 绘制纪律：积木底图在 `LuaBlockSprite` 构造时一次画好（`makeGraphic` + `drawRoundRect`），
  `update()` 里零绘制；画布只在**编辑事件**（落块/改参数/撤销/滚动）时 `rebuildCanvas()`，禁止逐帧重建。
- 三套输入：鼠标（拖拽/点击参数/滚轮滚动）、键盘（`[ ]` 分类、`,`/`.` 与 PgUp/PgDn 选积木、`Insert` 插入、
  `←/→` 选参数并微调枚举/数字、`Enter` 编辑参数、`Del` 删除、`Ctrl+Z/Y/C/X/V/S/O`、`Tab` 预览、`Esc` 返回）、
  触控（**未提供**，见上文 Android 隐藏）。
- 参数槽三态：枚举 = 弹出清单选择；数字/文本/表达式/变量 = `UIInputBox` **就地编辑**（Enter 提交、点外部提交、
  Esc 取消）；槽底属"面板内次级元素"，保留半透明深色（同复选框规则）。
- **界面不变量（2026-09-15 修完第一版截图缺陷后新增，改动时勿回归）**：
  - 画布顶部固定**两行**：第 1 行面板标题、第 2 行「模组/脚本」（`nameText` 右对齐 + `wordWrap=false` +
    超长 `fitText()` 省略）。内容从 `CAN_CONTENT_Y = CAN_Y + 78` 起，`cullOne()` 上界跟着它走。
  - 空画布判定必须用 `hasDrawableStack()`（有无**可绘制事件栈**），**禁止**用 `GDoc.isEmpty()`：
    后者语义是"没有任何真实积木"，归 `LuaCodeGen.validate` 保存前校验用；用它控提示会在"只拖了事件帽块"
    时提示常显并压住第一条事件栈（叠字缺陷根因）。
  - 底栏 96×32 按钮的标签字号必须显式传 `BAR_BTN_LABEL = 18`：`FlxText.set_fieldWidth()` 在
    `fieldWidth > 0` 时**强制 `wordWrap = true`**，26px 下 96px 只放得下 3 个汉字（"保存生成"折行、
    "预览 Lua" 被截）。
  - 空凹槽（`LuaBlockSprite`）：`EMPTY_BODY_H = 44` + 底色 `0x59000000` + 槽内底部对齐的占位文案；
    帽块凹槽的"空"必须由 `stack.blocks.length == 0` 传入（模型里栈内积木与帽块同级，`block.body` 恒空）。
  - **插入点必须可见**：`addGap()` 的命中带本身不可见，拖拽时必须由 `showDropHints()` 画出插入线、
    由 `updateDropHints()` 高亮最近插入点；画布外松手**禁止静默丢弃**，必须给状态条红色反馈 + 取消音。
  - **浮层永远在积木之上**：`rebuildCanvas()` 会把积木 `add()` 到 `members` 末尾，所以每次重建后必须调
    `raiseOverlay()` 把打开中的弹层/预览层摘除再追加回末尾（`FlxGroup.remove(o,true)` 只摘除不销毁）。
    漏了这一步就是"积木压在弹窗上"的堆叠缺陷（2026-09-15 实测）。
  - **事件栈必须可删除**：帽块的 `blockPath` 是奇数长度 `[栈下标]`（不是任何序列的元素），
    `GDoc.detach()` 对奇数路径直接返回 null。因此 `deleteSelected()` 必须显式处理"奇数路径 = 删整条事件栈"，
    否则「点一下事件积木就新增一条栈、却永远删不掉」——2026-09-15 用户实测缺陷。
    **任何"可新增"的对象都必须同时存在删除路径**（本轮之前事件栈只能加不能减）。
  - **底栏文本必须先量宽再定行**：左侧可用宽度只有 `BAR_TEXT_W = 636`（右侧 512px 是 5 个按钮），
    所以快捷键提示拆成 `HINT_ROW1/HINT_ROW2` 两行，每行 ≤ 636px，并走 `fitText()` 兜底
    （超宽给可见省略号而不是静默裁切）；自检打印 `hint fit: row1=…/636 row2=…/636 truncated=… barBottom=…`。
    改提示文案后必须看这行日志 —— 历史上"提示显示不全"就是这样漏掉的。
    完整键位表不在底栏（放不下），走 **`F1` 操作说明弹层**（`openHelp()` → 通用弹层，10 行 ≤ 556px，
    自检断言 `help fit: max=…/556`）。
  - **释放纪律（本轮新增，务必照做）**：`FlxGroup.remove(o, true)` **只摘除、不销毁**（flixel 5.2.2
    `FlxGroup.hx:396-420`）。所以摘除对象一律走 `disposeSprite()` / `disposeAll()`：
    它们做 `remove` + `destroy()`，并对**纯 FlxSprite** 补 `FlxG.bitmap.removeIfNoUse(graphic)`
    （`FlxSprite.destroy()` 只 `graphic = null` + useCount--，**不摘 `FlxG.bitmap` 缓存**；
    Meteoric 版 `FlxText.set_graphic` 自带摘除，故文本不重复摘）。
    `rebuildCanvas()` 的销毁顺序是契约：**先摘除全部成员 → 销毁 `canvasBits`（= 各 sprite 的 texts+chips）
    → 清空 `spr.texts/chips` → 销毁底图**，颠倒会二次 destroy。`UIInputBox` 必须 `destroy()`
    （其 destroy 才把原生输入框从 stage 摘掉并解绑监听）。
  - 画布没有真正的裁剪遮罩：拖拽的幽灵块与插入指示必须在 `rebuildCanvas()` **之后**创建，否则会被重建出的积木盖住。
- **生成物契约**（与 Lua 层的关系，改动时勿破）：
  - 事件帽块 = 真实 Psych 回调（`onCreate` / `onCreatePost` / `onUpdatePost(elapsed)` / `onBeatHit` / `onStepHit` /
    `onKeyPress(key)` / `goodNoteHit(id,noteData,noteType,isSustain)` / `onSongStart` / `onDestroy`）；
  - 「等待 N 秒后继续」= `runTimer` + 续接闭包，靠**本编辑器生成的 `onTimerCompleted` 调度器**驱动
    （仅当图中真的用了等待积木才生成）；自定义代码区若也定义 `onTimerCompleted`，校验会告警"等待将失效"；
  - 生成文件分「受管区」与「自定义代码区」：重新生成整体重写受管区、**永不覆盖**自定义区；
    目标 `.lua` 已存在且**不含**自定义区标记时，必须先经确认，把原内容整体搬进自定义区（不丢手写代码）；
  - 落点：`mods/<当前模组>/scripts/<名字>.lua` + `<名字>.luagraph.json`。`.json` 不会被当脚本加载
    （`PlayState.create` 的 `scripts/` 扫描只认 `.lua` / `.hx`）；
  - 兜底能力：`调用任意 Lua 函数` 与 `直接写一行 Lua` 两块覆盖全部 203 个注册 API，复杂逻辑建议写进自定义区。

### 编辑器菜单（MasterEditorMenu）

- 入口：主菜单按 `7`（debug_1）；界面标题「编辑器菜单」；8 个条目（Android 上裁掉 `luagraph`，见下文）。
- 背景 = **主题色**：`menuDesat` 染 `DesignTokens.menuTint`（= 当前主题 primary，见 `MENU_TINTS`）。
  2026-09-15 由"跟随当前选中条目的强调色（`optionShit[r][4]`）+ 0.4s `FlxTween.color` 过渡"改为跟随主题色，
  与 Options / Pause / Lua 图形化编辑器统一；条目自带的强调色仍保留在表里，但**不再驱动背景**
  （若日后想恢复"每项一色"的辨识度，请改挂在选项名/高亮条上，不要再让整屏背景变色）。
- 令牌在 `create()` 读取 → 切换主题色后**下次进入本界面**生效；不做 `update()` 轮询、不注册主题监听
  （与其它系统域界面同规则）。
- 边界（勿越）：**菜单本体**属系统域（圆角磨砂面板 + 令牌化）；**它打开的编辑器页本体**仍是非主题域
  工具界面（深灰底 `0xFF101010` / `0xFF222222`、`ChartWidgets` 自有 hover 档，见 meteoric-design 例外表），
  本轮没有、后续也不要顺手把它们染成主题色。

## 动效底线（系统域）

1. 面板进入 250ms `quadOut`（α + 位移 8–16px），出场 200ms `quadIn`；子页切换 fade 150ms。**存量偏差（P1 待收敛）**：Pause/Results 现为 0.4s `quartInOut` + startDelay stagger（并发动效 12–15 组），新代码禁止复制该模式。
2. hover/按下即时（≤100ms）；数值变化不 tween；数字滚动仅结算/成绩。
3. **禁用**节拍同步；**禁用**真实模糊/阴影；并发动效 ≤ 2 组。
4. 所有动效必须能被"输入"打断（新输入到达时 tween 先 kill），避免队列堆积。

## 禁止清单（Do NOT in this domain）

1. 涂鸦贴图、卡通描边大标题、节拍跳动、`logoBumpin`（唯一例外：`NoteOffsetState` 节拍校准反馈，见动效底线）。
2. 新面板 0 圆角 / 无描边 / 实体纯黑。
3. 弹层不压暗；文本越 `SAFE_RIGHT`；底部越 648。
4. 面板每帧重建（`makeGraphic` 循环）、真模糊、大阴影。
5. 无键盘路径的触控组件、无触控路径的按钮（三套输入缺一不可）。
6. 暂停/结算改成全屏新 State（破坏 SubState 栈与转场安全）。
