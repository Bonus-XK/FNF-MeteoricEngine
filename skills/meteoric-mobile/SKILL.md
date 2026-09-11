---
name: meteoric-mobile
description: Meteoric Engine Android/触控适配规范：触控目标尺寸、MobileControls 布局模式、即时反馈、长按与防误触、掉帧/低端机性能红线、系统返回键与安全布局。改移动端 UI 先读本 skill。
---

# Meteoric Android / 触控适配

## 适用

- 目标：Android（含 MIUI/HyperOS、ColorOS 等定制 ROM）、触屏设备。
- 逻辑画布 1280 × 720；所有触控目标、间距、布局常量以**逻辑像素**定义。
- 涉及文件：`source/objects/MobileControls.hx`、`MobileControlsSubState.hx`、`BaseOptionsMenu.hx`（`menuPad`/`◀▶`）、`GameOverSubstate.hx`（pad）、`compile-android.sh`。

## 触控目标（MD3 48dp 换算）

- **最小触控目标 ≥ 56 × 56 逻辑 px**（≈ 48dp @ 1280×720 标准密度）；相邻目标间距 ≥ 8px。
- 现有例外：`CHECK_SIZE 26`（选项复选框）——必须放大**命中区**（透明 overlay）到 ≥56×56，视觉尺寸可保持 26。
- 角落按钮（BackButton、pad A/B）避开系统手势区：顶部/底部各留 ≥ 48px。
- 列表行高 ≥ 40px（Freeplay Alphabet 行距 156 满足；新列表不得低于 56 命中行高）。

## MobileControls 布局模式（`ClientPrefs.data.mobileControlsMode`）

| 模式 | 含义 |
| --- | --- |
| 0 | 右手按键（Psych RIGHT_FULL） |
| 1 | 左手按键（Psych LEFT_FULL） |
| 2 | 自定义布局（可拖动保存） |
| 3 | 双手按键（Psych BOTH_FULL） |
| 4 | 全屏判定区（Psych HITBOX 四等分） |
| 5 | 无按键（仅键盘/外设） |

- **禁止改判定区命中逻辑**：物理坐标 → 逻辑坐标换算（与 `FlxTouch` 一致，除以 `scaleMode` 缩放）+ 底层 `stage.TouchEvent` 捕获兜底（掉帧时 flixel 丢失触摸仍能点按）——这是已验证修复，不是可优化项。
- 新增按键/布局模式：必须接入 `ClientPrefs` 持久化 + 设置页可调；默认不改变现有 0–5 语义。

## 反馈与输入节奏

- 触控按压**即时反馈 ≤100ms**（高亮/缩放），不可只靠声音。
- 长按（数值/档位调节）：`PAD_HOLD_DELAY = 0.5` 初始延迟、`PAD_STRING_STEP = 0.2` 步进；**触控计时与键盘 hold 完全独立**（现有 `padHoldTime` / `padHoldDir` / `padStepTimer` 模式）。
- 防误触：进入界面 `nextAccept = 5`（忽略确认帧）+ 子状态 `timeForMoving = 0.1`；点按冷却防一次按下触发两次（`lastPadBtnTap`）。
- 双击/拖动冲突：列表滚动用 tap 队列（StoryMenu 周目拖动模式）；确认与滚动要可区分（位移阈值），避免"想滚动却点了确认"。
- 系统返回键：返回上一级（主菜单/上一页/回到游戏），**禁止**直接 `exit`；音量键与游戏按键绑定保持现状。

## 性能红线（低端机 / 掉帧）

1. **禁止**实时高斯模糊、大阴影、粒子风暴（系统域面板一律静态 `drawRoundRect`）。
2. 禁止每帧 `makeGraphic` / 新建 `FlxSprite`；复用的对象用 `kill`/`revive` 或池（现有音符池 + 视觉预算模式）。
3. 动画时长基于**秒**（`elapsed` 插值），禁止 `frame` 计数推进 UI（掉帧会跳变）。
4. 掉帧时优先生效的路径：逻辑（判定/滚动）优先于装饰（模糊/粒子/光效）；`elapsed * SCROLL_LERP` 时间插值保证滚动手感一致。
5. 低内存：进出界面按现有 `Paths.clearStoredMemory()` / `clearUnusedMemory()` 顺序（进入界面先清理再加载）；新增贴图必须走 `Paths` 缓存，禁止 `Assets` 直读。
6. Android 构建/CI：`compile-android.sh` 与 `.github/workflows` 缓存规则不改动；新增资源注意 32 位/体积预算。

## 安全布局（所有系统域界面，Android 通用）

- 文本（含弹窗）右缘 ≤ 1100、底部 ≤ 648（1280×720 基准），居中内容也须满足：两侧各留 ≥ 48px。
- 顶部/底部条（如 Freeplay 底部提示、Options 底部条）高度 ≤ 56，文字 16px 起。
- 分屏/横屏：布局常量不变，`scaleMode` 负责适配；**禁止**硬编码窗口像素。
- 触摸目标不能依赖 `FlxG.mouse` 路径（触屏无 hover），须有 pressed/selected 态。

## 检查清单（改移动端 UI 后逐条过）

- [ ] 每个新交互都有 ≥56×56 命中区，间距 ≥8px
- [ ] 按压反馈 ≤100ms 可见
- [ ] 长按节奏按 0.5s/0.2s 参数，且与键盘独立
- [ ] 返回键不退出游戏
- [ ] 无每帧 `makeGraphic` / 实时模糊 / 大阴影
- [ ] 动画按秒推进，掉帧不跳变
- [ ] 新资源走 `Paths` 缓存，进出界面按清理顺序
- [ ] 文本右缘 ≤1100、底部 ≤648
- [ ] MobileControls 语义保持 0–5，未破坏触控捕获兜底
