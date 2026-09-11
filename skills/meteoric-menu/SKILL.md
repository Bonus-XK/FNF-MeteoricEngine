---
name: meteoric-menu
description: Meteoric Engine 手绘域界面规范：主菜单（经典 v2）、Story Mode 选周、Freeplay 选曲。保留 FNF 涂鸦气质，禁止 MD3 组件；规定布局常量、三套输入（键盘/鼠标/触控）与动效。
---

# Meteoric 手绘域：主菜单 / 选歌

## 域判定

主菜单、StoryMode、Freeplay 属于**手绘域**：视觉语言 = FNF 涂鸦/卡通描边。
**禁止**在这里引入 MD3 组件（filled/tonal 按钮、圆角卡片列表、磨砂面板包列表）。
唯一既存例外：Freeplay 右上/底部磨砂信息条（系统域语言、服务手绘域列表）——保持现状，不扩展。

本 skill 只在该域生效；通用令牌/动效总纲见 `meteoric-design`。

## 主菜单（MainMenuState，经典 v2 现状）

### 布局常量（1280×720 逻辑坐标，改布局必须先改此处）

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `ITEM_RIGHT` | 1220 | 菜单项右边缘（右对齐） |
| `LIST_CENTER_Y` | 360 | 选中项中心 Y |
| `ROW_GAP` | 130 | 相邻项间距（经典 Psych 行距，防叠压） |
| `SCROLL_LERP` | 14 | 时间插值系数（与 Freeplay 同款手感） |

- 菜单项：`mainmenu/menu_<id>` Sparrow 图集，`idle` = `<id> basic`，`selected` = `<id> white`，24fps。
- 选项顺序（`optionShit`，受编译宏影响）：`story_mode` → `freeplay` → `mods` → `awards` → `credits` → `donate` → `options`。
- 左上 FNF 标志：`logoBumpin` 图集 @ (30,70)，scale 0.6，仅 `ClientPrefs.data.menuBeatBump` 开启时随 `beatHit` 播放 `bump`。
- 左下信息区：版本号（`Meteoric Engine v' + Main.meVersion`）、新版本链接（`0xFFFFD166`，可点击）、联机入口（`0xFF8AD7FF`，可点击），均 `future.ttf` 16 + 黑描边 2。
- 底部提示：`触控/滚轮 选择 · A / Enter 确认 · Esc 返回`（`future.ttf` 16，居中，宽 1160）。
- 右上返回按钮：`BackButton(FlxG.width - 72, 12)`（`< 返回标题界面`）。

### 状态机（选中/未选中）

- 选中项 `alpha = 1` 并播放 `selected`（white）帧；未选中 `alpha = 0.55` 播放 `idle`。
- `changeItem()` 只做三件事：更新 `curSelected`、播放对应动画、设置 α。**禁止**在这里启动长 tween。
- 首次进入用 `snapItems()` 直接落位（**无入场动画**；菜单是高频界面）。
- 滚动：每帧 `FlxMath.lerp` 按 `elapsed * SCROLL_LERP` 插值到目标位置，**禁止**直接赋值造成跳帧。
- 确认选中：选中项走经典 `FlxFlicker`（**存量 1s，按设计总纲应收敛至 ≤0.4s**），其余项 `FlxTween.tween(alpha: 0, 0.4, quadOut)` 后 `kill()`；切换在 flicker `onComplete` 中执行，`selectedSomethin` 守卫防重复输入。
- 背景：`menuBG` 放大 1.175 居中；彩蛋背景 `menuDesat` tint `0xFFfd719b`（`magenta`，默认隐藏）。

### 三套输入（互不冲突，既有已验证模式）

1. **键盘**：`UI_UP_P` / `UI_DOWN_P` → `changeItem(±1)` + `scrollMenu` 音效；`ACCEPT` → `selectItem()`；`BACK` → `TitleState`；`debug_1`（桌面）→ `MasterEditorMenu`。
2. **鼠标**：悬浮**只高亮不抢焦点**；滚轮经 `WheelScroll` 限速；点击选中项 = 确认；点击链接 = 外部打开。键盘操作后冻结鼠标激活（`mouseActive`，鼠标移动 > `MOUSE_REACTIVATE_DIST` 10px 恢复）。
3. **触控**：点按 = 确认；滚动/拖拽 = 列表移动；与键盘同逻辑但走 touch 事件，禁止复用键盘 hold 计时（参照 BaseOptionsMenu 的 `padHoldTime` 独立计时模式）。

### 彩蛋

- 键盘缓冲 `meforever` → 字母逐字乱飞变色（`Meteoric Forever!`）；`crash` → `CrashTestPrompt` 崩溃测试弹窗。
- 新增彩蛋必须：不阻塞正常输入、进入前清理状态、可被 Esc 打断；彩蛋动画属"稀有"频率（≤800ms 或持续飞行但可退出）。

## Story Mode（StoryMenuState）

- 保留备份版整体视觉：黄色标题条、每周背景、周目轮播、角色立绘、曲目轨条。**不要重构布局**；新增元素避开这些区域。
- 难度选择器：`◀ 难度 ▶` 固定在 `DIFF_X = 830` 附近（黄色标题条中部偏右），**不锚定周目缩略图**、不随锁定状态隐藏；最后添加、永远最上层。
- 触控：点 `◀▶` 切难度、点周目选中、拖动滚周目（stage tap 队列——Android 上必须可用）。
- 系统返回键（Android）→ 回主菜单，**不是**退出游戏。
- 周目切换动效：保留现有轮播；新增动效频率按"低频"（≤350ms），且不能挡住难度选择器。

## Freeplay（FreeplayState，Psych 0.7.3 版列表）

### 布局常量（现状，改布局先改这里）

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `LIST_X` | 88 | 歌曲列表 X |
| `LIST_CENTER_Y` | 320 | Alphabet 列表中心 |
| `ROW_STEP` | 120 | Alphabet 行距（实际步进 ≈ 1.3 × 120 ≈ 156） |
| `DRAW_DISTANCE` | 4 | 可见窗口 ±4 行（无卡片裁剪） |
| `PANEL_R_*` | 740/14/500/132 | 右上磨砂条（歌名/最高分/准确率/难度） |
| `PANEL_B_*` | 40/662/1160/48 | 底部磨砂提示条 |

### 规范

- **列表无卡片**：Alphabet 歌曲列表直接铺在背景上，Psych 0.7.3 式无限制显示；禁止改成卡片/缩略图列表。
- 选中行：`HealthIcon` 跟随选中曲目；右上成绩区（`lerpScore` / `lerpRating` 数字滚动）常驻。
- 右上/底部磨砂条：样式与 `BaseOptionsMenu.makePanel` 一致（`surfaceDim` + `outline`），圆角按现状：右上条 18、底部条 14；只放信息，**不**放按钮组。
- 滚动：`WheelScroll` 限速 + 时间插值；触控拖动列表；鼠标悬浮高亮不抢焦点。
- 保留特性：试听"灵动岛"、节拍跳动（遵循 `menuBeatBump`）、`CTRL/R/L/P` 子状态（GameplayChangers / ResetScore / ScriptManager / Replay）。
- 曲目选中动效：低频（250ms），默认按键 `FlxEase.quadOut`；不改变列表滚动插值手感。

## 动效底线（手绘域）

1. 菜单滚动 = 时间插值（`elapsed * SCROLL_LERP`），不是逐帧跳位。
2. 节拍同步只用于标志/装饰（`logoBumpin`、`menuBeatBump`），**不**用于列表滚动与信息条。
3. 转换用 `FlxTransitionableState.defaultTransIn/Out` 或 `CustomFadeTransition`；不手写闪屏。
4. 系统域（Options/Pause/Results…）动效规范见 `meteoric-system`，本域不套用。

## 禁止清单（Do NOT in this domain）

1. 主菜单/Story/Freeplay 列表加 MD3 卡片、pill 按钮、磨砂大面板（游离信息条除外）。
2. 滚动直接赋值、无插值；hover 抢焦点（改变选中项）。
3. 未选中项做成不可见/完全移除（应保持 0.55 可见，供扫描）。
4. 新增元素覆盖难度选择器/右上成绩区/底部提示区。
5. 在系统返回键上直接 `exit` 退出游戏。
