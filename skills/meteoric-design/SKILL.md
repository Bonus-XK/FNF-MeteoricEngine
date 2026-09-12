---
name: meteoric-design
description: Meteoric Engine（Psych 0.7.1h 基座）UI 设计总纲：手绘域/系统域分域原则、MD3 设计令牌、动画决策框架与 Before/After 审阅规范。所有引擎界面改动先读本 skill。
---

# Meteoric 设计总纲

## Initial Response

当本 skill 首次被调用且没有具体问题时，只回复：

> 我已就绪。我是 Meteoric Engine 的设计工程规则：分域（手绘域 vs MD3 系统域）、MD3 令牌、动效决策与审阅格式都已编码。请告诉我你要改哪个界面，我会先判定归属域，再给出符合规则的实现。

## 适用范围

- 引擎：Meteoric Engine v1.1.2+（Psych Engine 0.7.1h 基座），Haxe/OpenFL + Flixel。
- 画布基准：1280 × 720 逻辑像素；Android 上按 `scaleMode` 缩放，布局常量一律写在逻辑坐标。
- 所有 UI 状态：`MusicBeatState` / `MusicBeatSubstate` / `FlxSubState` 与 Lua 自定义界面（`loadUIscripts`）。

## 第一原则：分域（Domain Split）

**任何界面改动，先判定归属域，再按该域规范实现。跨域混用是最高优先级错误。**

| 域 | 界面 | 视觉语言 | 动效语言 |
| --- | --- | --- | --- |
| **手绘域** | 主菜单、Story Mode、Freeplay、Gameplay（HUD/音符） | FNF 涂鸦/卡通描边、英文 Art 精灵、`future.ttf` 粗体 + 黑描边 | 节拍同步（`beatHit`）、Psych 式精灵动画、时间插值滚动 |
| **系统域** | Options、Pause、GameOver、Results、Mods 管理、联机、脚本/输入类子界面、`ModInstallUI` | MD3 令牌 + 圆角面板（现有"圆角磨砂玻璃"升级版）、`future.ttf` 标题 + 正文 | MD3 缓动（ease-out 入场 / ease-in 出场）、200–500ms、fade-through 转场、**禁用节拍同步** |

- 手绘域**禁止**：MD3 filled/tonal 按钮、圆角卡片包住列表、磨砂面板（Freeplay 的右上/底部信息条是既存例外，保持现状）。
- 系统域**禁止**：涂鸦贴图、`logoBumpin` 式节拍跳动、卡通描边大字体海报。
- 例外必须写注释说明"本例外属于手绘域 / 系统域"，例如 Freeplay 右上磨砂信息条（系统域语言，但服务于手绘域列表）。

## 设计令牌（MD3 Tokens）

固定色板（无壁纸动态取色）。新代码**禁止**随意写十六进制色值，必须引用下表。

> **已落地（主题色功能）**：`source/backend/DesignTokens.hx` 是**唯一色彩来源**，已实现「固定 10 色 + 设置内用户可选主题色」。
> 下表 `primary` / `secondary` / `tertiary` 的 ARGB 是**默认主题（青，themeIndex 0）**的取值；
> 运行时会随玩家色板切换，因此：
> - 代码里写 `DesignTokens.primary`（**运行时读取**），**禁止**写 `static final THEME = DesignTokens.primary`
>   —— `static final` 在类初始化时取一次值就冻结，主题切换后不会更新（本功能实现时已修掉
>   `OnlineMenuState` / `CharacterSelectState` 的这类写法）。
> - 令牌必须在界面 **`create()` 内**读取；已创建界面不会自动重绘，切换主题后下次进入生效。
> - 判定色（MARVELOUS/SICK/GOOD…）、成功/失败语义色（`0xFF7BFF9E` / `0xFFFF6B6B`）、
>   音符与 KE 图颜色属**内容色例外**，永不参与主题化。
> - 组件若要「主题色一变就跟着刷新」（例如色块选择器的选中环），用
>   `DesignTokens.addThemeListener(fn)` 注册，并在 `destroy()` 里 `removeThemeListener(fn)` 摘除
>   ——监听表是**静态**的，不摘会留下对已销毁精灵的僵尸回调。**禁止**在 `update()` 里轮询 `themeIndex`。
> - 横向定位别凭感觉：`BaseOptionsMenu.swatchRowStartX()` 曾把"减单个色块直径"当成"居中整行"，
>   整行右移 (10−1)×58/2 = 261px 冲进右面板。凡是"整行/整块居中"，减的必须是**整行总宽**，
>   并代进常量算一遍——代码里看不出这种错。

### 色彩

| Token | ARGB | 引擎现状对应 | 用途 |
| --- | --- | --- | --- |
| `primary` | `0xFF9CE8FF` | ControlsSubState 高亮 | 选中/聚焦/激活 |
| `onPrimary` | `0xFF06221F` | — | primary 上的文字/图标 |
| `secondary` | `0xFFFFD9A0` | ControlsSubState 暖色 | 次强调/提示/标记 |
| `tertiary` | `0xFFEA71FD` | OptionsState 背景 tint | 品牌色点缀（少用） |
| `error` | `0xFFFF6B6B` | — | 危险/失败/重置确认 |
| `surface` | `0xFF1A1A26` | — | 面板基础底（不透） |
| `surfaceDim` | `0xCC161622` | `makePanel` fill | 面板半透明底（80% α） |
| `surfaceVariant` | `0xFF2A2A38` | — | 次级面板/分区 |
| `outline` | `0x45FFFFFF` | `makePanel` border | 面板描边（27% α，1.5px） |
| `onSurface` | `0xFFFFFFFF` | 各处白字 | 主文本 |
| `onSurfaceVariant` | `0xFFD7D7E0` / `0xFFCFCFDC` | BaseOptionsMenu | 次级文本/说明 |
| `scrim` | `0x99000000` / 暂停用 `0xCC000000`（α 0.6 黑） | PauseSubState 遮罩 | 弹层压暗 |

- 透明度：状态层**选中/按压统一 `0x3AFFFFFF`**（23% 白，Options/Pause/Results 高亮条已一致）；悬浮（如需新增）用 `0x2EFFFFFF`（18% 白）；**不要**用实体色块模拟。
- 对比：正文 `onSurface` 与 `surfaceDim` 对比必须 ≥ 4.5:1；`onSurfaceVariant` 只用于非关键说明。

### 形状

| 用途 | 圆角 | 现有实现 |
| --- | --- | --- |
| 大面板（列表/统计） | 20–22px（存量 Pause/Results 20、Options 22；新代码统一 22） | `BaseOptionsMenu` `makePanel(..., 22)`；Pause/Results `makePanel(..., 20)` |
| 底部条/小卡片 | 14px | `makePanel(x, 662, 1040, 48, 14)` |
| 按钮 | 10px（或全圆 pill） | 新按钮组件 |
| 复选框 | 小圆角 6px / 现 26px 方框 | `BaseOptionsMenu` `CHECK_SIZE = 26` |

- 系统域**不允许 0 圆角**的面板/按钮；小组件圆角不小于 6px。
- 禁止为圆角生成临时贴图/实时模糊；统一用 `FlxSpriteUtil.drawRoundRect` 静态绘制（现有 `makePanel` 模式）。

### 字体与字号

| 层级 | 字体 | 字号 | 现有对应 |
| --- | --- | --- | --- |
| 界面标题 | `future.ttf` | 30 | BaseOptionsMenu 标题 |
| 栏目标题 | `future.ttf` | 26 | 右栏标题 |
| 正文/选项 | `future.ttf`（后续可换 Noto Sans SC 需先入库 `assets/fonts`） | 20–24 | 选项行 |
| 数值 | `future.ttf` | 20 | 值文字 |
| 辅助/提示 | `future.ttf` | 16 | 底部提示、版本号 |

- 描边：标题可黑描边（`borderSize 2`）；正文默认**不描边**，靠面板底色保证可读。
- 中文文本：结论文字用简体中文（引擎既有约定），判定缩写（SICK/GOOD/BAD/SHIT/MISS）保留英文。

### 间距

- 网格：8px。行距优先 32 / 40 / 48 / 56（现有 `ROW_GAP 56`、`STATS_ROW_GAP 48`）。
- 历史遗留 34px 行距（Pause/Results）**不改动存量**；新代码一律用 8 的倍数。
- 面板内边距 ≥ 20px；面板间距 14px。
- 安全边距：面板右缘 ≤ 1240（1280 − 40）；**左对齐/流动文本**右缘 ≤ 1100（Pause `SAFE_RIGHT` 经验，防截断）；**固定列布局**（Results 右栏 620..1240）以面板右缘 − 20px 为界（约 1220），列宽必须固定且不溢出；底部 ≤ 648（720 − 72）。

### 层级（Elevation）

- **不适用**：真实高斯模糊、大阴影贴图（移动端性能红线）。
- 层级表达：半透明填充（`surfaceDim`）+ 1.5px 描边（`outline`）+ 面板间 14px 间距 + 遮罩（`scrim`）。
- 弹层（SubState）必须压暗背景：整屏 `menuDesat` 或 0.6 黑遮罩，**禁止**无遮罩直接叠面板。

## 面板与高亮令牌（磨砂玻璃，主题色随动）

系统域的「双圆角磨砂玻璃面板」= `FlxSprite.makeGraphic(TRANSPARENT)` + `FlxSpriteUtil.drawRoundRect` × 2
（填充 + 1.5px 描边），全库有 **21 份同名复制实现**（`BaseOptionsMenu` / `PauseSubState` / `ResultsSubState` /
`ModsMenuState` / `OptionsState` / `ControlsSubState` / `FreeplayState` / 各编辑器页 …）。
它们过去共用同一组字面量默认值，现已统一改为**引用令牌**。

| 令牌 | 来源 | 用途 |
| --- | --- | --- |
| `DesignTokens.panelFill` | 派生：`0xFF161622` 混 **10% 当前 primary**，α 恒为 `0xCC` | 所有玻璃面板的填充底色 |
| `DesignTokens.panelOutline` | 固定 `0x45FFFFFF`（白 27%） | 面板描边 |
| `DesignTokens.rowHighlight` | 派生：primary @ **42%**（`0x6B……`） | 面板内**选中/激活**高亮（`selectorBar`、选中行） |
| `DesignTokens.rowHover` | 派生：primary @ **30%**（`0x4C……`） | 面板内**悬浮**高亮（比选中更轻） |

派生后各主题的 `panelFill` 实测值（α 均 `0xCC`，仅 RGB 吸收 10% 主题色）：

| 主题 | primary | panelFill |
| --- | --- | --- |
| 青 | `0xFF9CE8FF` | `0xCC232B38` |
| 蓝 | `0xFF7CB8FF` | `0xCC202638` |
| 品红 | `0xFFF08CF0` | `0xCC2B2136` |
| 橙 | `0xFFFFB27A` | `0xCC2D252A` |
| 绿 | `0xFF8FE8A8` | `0xCC222B2F` |
| 红 | `0xFFFF9A9A` | `0xCC2D232E` |

### 硬性规则

1. **面板一律用令牌，禁止再写字面量** `0xCC161622` / `0xEE161622` / `0xFF161622` 或
   `0x3AFFFFFF` / `0x2EFFFFFF` 作为面板底色/高亮。
2. **`makePanel` 的参数默认值必须是编译期常量** —— Haxe 拒绝 `?fill:Int = DesignTokens.panelFill`
   （*Parameter default value should be constant*）。统一形态：
   `?fill:Null<Int> = null, ?border:Null<Int> = null`，函数体首行解析：

   ```haxe
   if (fill == null) fill = DesignTokens.panelFill;
   if (border == null) border = DesignTokens.panelOutline;
   ```

   顺带好处：取到的是**当前主题**的值，而非类加载时的静态快照。
3. **嵌套在面板内的次级元素保留原半透明深色**（复选框底 `0x66161622`、进度条底、键帽、行内小块）——
   它们的作用是"透出父面板"，换成不透明 `panelFill` 会丢掉玻璃层次。
4. **不得用局部 `static final` 缓存面板色**：`static final PANEL_FILL = DesignTokens.panelFill`
   会在类加载时冻结取值，主题切换后失效（本仓库已两次踩坑，见 `meteoric-system` 的硬性契约）。
5. **脚本 API 的默认值保持中性**：`MenuScript.addBox` 的 `?color` 默认仍是 `0xCC161622`，
   避免模组自绘 UI 随玩家主题设置漂移；脚本想跟随主题时**显式**取
   `getThemePanelFill()` / `getThemeRowHighlight()`（Lua 三处 + HScript 均已提供）。

### 特例：Gameplay HUD 的时间条（`backend/TimeBarColor.hx`）

时间条是**唯一**跨越到手绘域/Gameplay 的主题色落点，取色统一走 `TimeBarColor.resolveFill(dad, modernStyle, useOpponent)`：

| 条件 | 填充色 |
| --- | --- |
| 关闭「时间条颜色跟随对方」 | **主题色** `DesignTokens.primary` |
| 开启 + 对手存在 + 颜色正常 | 对手 `healthColorArray` |
| 开启 + 对手颜色过暗 | 新版 → 主题色；贴图样式 → `0xFF00FFFF`（保留 0.6.3 兼容观感） |
| 开启 + 对手颜色过亮 | 仅贴图样式兜底青色 |

**改前必读**：时间条历史上两条分支各写一套取色，导致新版样式硬编码跟随对手、开关失效（2026-09-11 实测 bug）。
任何时间条配色改动**必须走这个单点**，不要在 `PlayState` 里新增分支；
`HUDCustomizeState` 的预览也复用同一函数（避免预览与实机不一致）。

### 不用令牌化的例外（改前必须确认，不要"顺手统一"）

| 位置 | 理由 |
| --- | --- |
| 判定色（MARVELOUS/SICK/GOOD/BAD/SHIT/MISS）、KE 散点图 | 内容色，语义固定 |
| 成功/失败/危险语义色（`0xFF7BFF9E` / `0xFFFF6B6B` / `0xFF8F8F`） | 语义色，与主题无关 |
| `ControlsSubState` 的 `keyboardColor` / `gamepadColor` | 键鼠 vs 手柄的**功能性区分**色 |
| `ModsMenuState.defaultColor = 0xFF665AFF` | Mods 界面品牌色 |
| `MainMenuState` 的 `magenta` 线稿、`AchievementsMenuState` 的 `0xFF4A5C8C` | 手绘域涂鸦配色 / 成就界面专属品牌色 |
| 编辑器页深灰底（`0xFF101010` / `0xFF222222`）、`ChartWidgets` 的 hover 档 | 非主题域的工具界面 |

## 动画决策框架（Adapted from Emil Kowalski + FNF 特化）

写任何动画前，按顺序回答：

### 1. 该动吗？（频率表）

| 频率 | 决策 |
| --- | --- |
| 高频：菜单滚动、选项切换、Gameplay 判定反馈 | ≤150ms 或仅状态切换；键盘重复操作**不等待**动画 |
| 中频：hover / 按压 / 选中 | 100ms 即时反馈，禁长动画 |
| 低频：面板进入、Pause、Results、弹窗 | 200–350ms 标准动画 |
| 稀有：成就、彩蛋、庆祝 | 可加惊喜（≤800ms，单次） |

- **键盘初始化动作勿加长动画**（Enter 确认跳转 ≤ 400ms；方向键滚动是即时的）。
- 手绘域的节拍同步（`beatHit` → `logoBumpin` / `menuBeatBump`）只在开启 `ClientPrefs.data.menuBeatBump` 时使用；系统域一律不用节拍（唯一例外：`NoteOffsetState` 节拍校准以节拍为被测对象，`beatText` 反馈属功能语义，允许 `beatHit`，但视觉仍用 `MenuText` 系统域风格）。

### 2. 目的是什么？

合法目的：空间一致性（进出同向）、状态指示、反馈（按下/选中）、防止突兀（出现/消失必须有过渡）、引导注意。
**无效目的**：为炫技（禁止）、掩盖等待（禁止）、模仿网页动效（禁止）。

### 3. 曲线与时长（MD3 动效规范）

| 场景 | 缓动 | 时长 | Flixel 对应 |
| --- | --- | --- | --- |
| 入场（面板/菜单） | ease-out | 250ms | `FlxEase.quadOut` / `cubicOut` |
| 出场（销毁/切换） | ease-in 或直接淡出 | 200ms | `FlxEase.quadIn` / alpha tween |
| hover / press 反馈 | ease-out | 100ms | `FlxEase.quadOut` |
| 滚动（时间插值） | 每帧 lerp | — | `elapsed * SCROLL_LERP`（Freeplay/MainMenu 同款 14） |
| 数字滚动（结算分数） | ease-out | 500–800ms | `lerpScore` / `lerpRating` 模式 |

- **入场严禁 ease-in**（显得迟钝）；出场才允许 ease-in。
- 同屏动效并发 ≤ 2 组（移动端）；关闭不必要动画（`ClientPrefs` 有可选开关时优先控制）。
- `FlxTween` 只 tween 具体属性（`alpha` / `x` / `y` / `scale`），禁止 tween 无关字段；复用的 tween 先 `kill()` 再启动（`selectorTween` 模式）。

### 4. 状态反馈（三层）

| 状态 | 视觉 | 触发 |
| --- | --- | --- |
| hover（鼠标）/ 触控触摸 | 高亮/透明度变化（悬浮**只高亮不抢焦点**） | 鼠标移动、触摸 |
| selected / focused | 高亮 + 位置/颜色变化 | 键盘/触控选择 |
| pressed | 即时反馈：缩放 0.97 或亮度变化，≤100ms | 按下瞬间 |

- 鼠标/键盘输入分离：键盘操作后冻结鼠标激活（`mouseActive` / `MOUSE_REACTIVATE_DIST = 10` 现有模式）；鼠标明显移动/滚轮/点击才恢复。
- 触控必须有即时可视反馈；不可仅在声音上反馈。

## 审阅格式（Review Format，必须）

审查任何 UI 代码改动时，**必须**输出 Markdown 表格（`| Before | After | Why |`），逐行问题一行。

| Before | After | Why |
| --- | --- | --- |
| 进入界面直接 `spr.alpha = 1` | `FlxTween.tween(spr, {alpha: 1}, 0.25, {ease: FlxEase.quadOut})` | 真实界面不会凭空出现；入场用 ease-out |
| 菜单滚动直接设 `y = target` | 每帧 `y = FlxMath.lerp(y, target, elapsed * SCROLL_LERP)` | 跳帧感；时间插值任何帧率下手感一致 |
| 选择项直接播放 `selected` 动画 | 先切换动画 + α（选中 1 / 未选中 0.55），再播放选中帧 | 一次性视觉状态，避免残留动画态 |
| 点击按钮 `scale.set(0.9)` 立即返回 | `FlxTween.tween(btn, {scale.x: 0.97, scale.y: 0.97}, 0.1, {ease: FlxEase.quadOut})` 且不再 tween 其它属性 | 按压反馈明确且克制 |
| `FlxTween.tween(obj, {x: a, y: b, alpha: c, angle: d}, 0.3)` | 只 tween 本次需要的属性，其余不动 | 无关属性 tween 造成不可控状态 |
| 新面板 `0xFF000000` 黑块 | `surfaceDim 0xCC161622` + `outline 0x45FFFFFF` 描边 | 半透明深色 + 细描边是现有设计语言 |
| 每帧 `makeGraphic` 重画面板 | `create()` 时绘制一次，缩放用 `scale` | 移动端掉帧元凶 |
| 键盘按下未等待动画 | 维持 <=150ms 即时反馈 | 高频操作必须跟手 |
| `FlxTween.tween(panel, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.2})`（Pause/Results 存量） | `{alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.05}` | 入场 ease-out；低频界面 200–350ms |
| 逐行 `startDelay 0.4 + i * 0.06` 并发动画（Pause/Results 存量） | 容器级单 tween，或 ≤2 组并发动效 | 移动端并发红线；Pause 由 Esc 触发，键盘初始化动作需跟手 |
| `lbl.setFormat(..., 0xFFA9A9B8)`（Results/Pause 次级文本） | `0xFFD7D7E0`（onSurfaceVariant 令牌） | 色彩令牌化；判定/KE 图/音符色属内容色例外 |

**禁止**的格式（永不使用）：

```
Before: alpha=1
After: tween alpha 0.25
条目列表式，无表格、无 Why。
```

## 禁止清单（Do NOT）

1. 跨域混用：手绘域放 MD3 卡片 / 系统域放涂鸦大标题。
2. 入场用 ease-in；键盘/快捷键带长动画；为动画而动画。
3. 真高斯模糊、大阴影、实时 `makeGraphic`、每帧新建 `FlxSprite`。
4. 未判定"该不该动"就写 tween。
5. 直接写不存在的十六进制色值（先用令牌表）。
6. 弹层不压暗背景；文本右缘越过 1100（1280 基准）。
7. 在系统域使用节拍同步（`beatHit` 驱动的 UI 跳动）。
8. 删除/绕过 `WheelScroll` 限速、`mouseActive` 输入分离、`BackButton` 一致性（这些是既有已验证交互，改动需在表中说明理由）。

## 关联实现（供定位）

- 面板绘制模式：`source/options/BaseOptionsMenu.hx` `makePanel()`（fill `0xCC161622`、border `0x45FFFFFF`、radius 22/14）。
- 文本组件：`source/objects/MenuText.hx`（`isMenuItem` 插值滚动）、`TypedAlphabet.hx`。
- 输入组件：`source/objects/BackButton.hx`、`source/backend/WheelScroll.hx`、`source/objects/MobileControls.hx`。
- 转场：`source/backend/CustomFadeTransition.hx`、`FlxTransitionableState.defaultTransIn/Out`。

### 过场动画（CustomFadeTransition）契约

转场既不属于纯手绘域也不属于系统域面板，属**转场例外**：可染主题色，
但不引入 MD3 组件、不加圆角卡片。三种样式由 `ClientPrefs.data.CustomFade` 选择：

| 样式键 | 观感 | 效果来源 |
| --- | --- | --- |
| `移动` | 左右横幅水平推拉（默认） | `loadingL/R` 素材 |
| `陨星` | 流星斜落 → 撞击闪光 → 横幅推入 | **程序化**：拖尾渐变旋转 + 亮度头 + ADD 环形闪光 |
| `星辉` | 径向光晕 + 星芒爆发 | **程序化**：6 层同心圆叠软边辉光 + 12 道渐变星芒 |

改这个文件前必须知道的事实（全部是踩过的坑）：

1. **`loadingAlpha.png` 不是光效素材**：它是不透明平面图（1925×1083、**alpha 剖面全 255**、
   中心亮度 143 低于边缘 203）。拿它做"星辉"只能得到"贴图贴脸"。**光效一律程序化生成**：
   径向辉光 = 多层同心圆（半径与 α 同时递减，外 2937px α0.90 → 核心 441px），
   星芒 = 24×128「白→透明」渐变旋转多份叠加，`blend = BlendMode.ADD`。
2. **手绘素材不可旋转 / 不可非等比拉伸**。`loadingL/R` 是**成对使用**的箭头横幅，
   单张 `angle=-12°` + `scale.x×1.35` 会变成甩出窗口的畸形色块。斜向动感交给程序化光效。
3. **主题色要"显式混色后染素材"**：`sprite.color = FlxColor.interpolate(WHITE, DesignTokens.primary, 0.45)`。
   直接写 `primary` 是乘法着色，对高亮素材（平均亮度 229/212/172）几乎无效；
   "整屏半透明覆盖层"α0.22 的色差只有个位数、肉眼不可辨 —— 两种都试过，这是唯一有效的。
4. **收尾必须单点**：一律走 `finishOnce()`（`_finished` 闩锁），**禁止**挂到多个 tween 的 `onComplete`。
5. **`close()` 可能是静默空操作**：它只在 `_parentState.subState == this` 时生效，而 `finishCallback()`
   只是把新状态排队（真正交换在下一帧）→ 回调后必须**显式补一次 `close()`**，否则转场层残留。
6. **特效编排用相位时间轴**（`steps[]` + `update()` 推进），不要堆 tween 队列：
   多段动效（下落→撞击→推入）用 tween 的 `startDelay` 拼很容易错位且难调。
7. **`FlxSprite.setData/getData` 在 flixel 5.2.2 不存在** —— 每实例元数据用并行数组存。

其余 API 事实：`flixel 5.2.2` **没有** `FlxTween.timer`（延时用 `update()` 计时）、缓动只有
`cubeIn/Out`（没有 `cubicIn/Out`）；`destroy()` 里必须 `removeThemeListener` + `cancel()` 所有在飞 tween。
