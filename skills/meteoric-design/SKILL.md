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

固定色板（无壁纸动态取色）。新代码**禁止**随意写十六进制色值，必须引用下表（可先在 `backend` 建 `DesignTokens.hx` 统一放常量，或沿用现有字面量但保持同值）。

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
