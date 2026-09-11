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
| 复选框 | `checkBgs` / `checkFills`（`CHECK_SIZE` 26，背景 `0x66161622`/描边 `0x8CFFFFFF`，勾选白色圆角块） | 现状为白色勾选；MD3 升级目标：选中 = `primary` 填充、未选中 = `outline` 描边；切换 ≤100ms |
| 选项行 | `rows:Array<FlxText>` + `selectorBar` | 选中行 α=1 + `selectorBar` 跟随；未选中 0.55；`selectorTween` 先 `cancel()`（`kill()` 同义）再启动 |
| 滑块/数值 | 键盘 hold + 移动端 `◀▶` 长按 | `PAD_HOLD_DELAY = 0.5` 秒延迟、`PAD_STRING_STEP = 0.2` 秒步进；改为 `primary` 进度条时保留长按计时 |
| 下拉/字符串档 | `Option.hx` 档位 | 弹出子面板（非全屏 State）；圆角 14；选项表用 `MenuText` |
| 按钮 | `BackButton`、文本链接 | filled / tonal / text 三种语义；按下 0.97 缩放 100ms；触控目标 ≥56×56 逻辑 px |
| 对话框 | `Prompt`、`TextInputPrompt`、`CrashTestPrompt` | 圆角 14 + `scrim` 遮罩；确认/取消按钮 `error`（危险操作）/`primary`（主操作） |

- 状态层：hover `0x18` 白、pressed `0x30` 白叠加，非实体色块。
- 新组件必须提供**键盘/鼠标/触控三套**操作路径；触控长按与键盘 hold 分别独立计时（现有 `padHoldTime` 模式）。

### 输入（三套，既有已验证模式）

1. `WheelScroll` 滚轮限速；`mouseActive` 输入分离（键盘后冻结鼠标，移动 > 10px 恢复）。
2. 进入界面防误触：`nextAccept = 5`（忽略确认帧）+ `timeForMoving = 0.1`（子状态忽略输入）。
3. 移动端菜单 pad：右下 `A` 确认、`◀▶` 调节（`menuPad`）；GameOver 用 A/B pad。
4. 系统返回键（Android）：返回上一级界面（Options → 主菜单；Pause → 游戏；不带 * 的页面 → 上一页），**禁止**直接退出游戏。

## 各界面细则

### Options（BaseOptionsMenu + 子页）

- 布局：左面板（40,70,680,570，选项列表 + 标题）、右面板（740,70,460,570，说明）、底部条（120,662,1040,48）。
- 选项行：`LIST_X 108`、`LIST_Y 152`、`ROW_GAP 56`、`ROWS_VISIBLE 8`；说明文字单行，超出宽度截断为省略号。
- `scrollIndex` 翻页：低频动效（200ms，`quadOut`）；值变化即时（不 tween）。
- 子页（Graphics/Interface/Gameplay/Note/Controls…）继承 `BaseOptionsMenu`，禁止复制粘贴布局常量；新增子页直接继承。

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
