# Meteoric Engine — 界面设计规范

> 本文件是**权威约束**，不是建议。新写或改动任何界面（State / Substate / 面板 / 选项页）之前先读一遍。
> 规范里每一条都对应一次真实返工，不接受「先跑起来再说」。

---

## 0. 最高原则：复用，不自造

| 需求 | 用这个 | 禁止 |
|---|---|---|
| 开关（开/关） | `objects.ToggleSwitch`（96×32 胶囊 + 22px 白圆滑块） | ■/□ 文字、26px 方框 + 白勾、自绘胶囊 |
| 磨砂面板 / 圆角条 | 各 State 内的 `makePanel(x,y,w,h,radius,fill,border)` 局部工具 | `makeGraphic` + 手画圆角 |
| 行文字色 / 强调色 | `DesignTokens.*` 运行时令牌 | 硬编码主题色字面值 |
| 选项条目 | `options.Option` + `BaseOptionsMenu` | 自己再造一套选项系统 |
| 返回按钮 | `objects.BackButton` | 自绘 |
| 滚轮限速 | `backend.WheelScroll`（2 格 / 70ms） | 直接读 `FlxG.mouse.wheel` 累加 |
| 几何基线 | `substates.ScriptManagerSubstate` | 自创一套间距体系 |

设置界面、更新界面、备份界面里的开关必须是**同一个类**（`objects.ToggleSwitch`）。同一个语义控件在两处长得不一样就是 bug。

---

## 1. 颜色

### 1.1 主题色一律走令牌

```haxe
FlxColor // 硬编码 —— 只用于「跟主题无关」的固定暗色
DesignTokens.primary      // 强调 / 值列 / 选中强调
DesignTokens.secondary    // 次强调（⚠ 偏黄，**不要**拿它当正文色或信息色）
DesignTokens.tertiary
DesignTokens.panelFill    // 磨砂面板底
DesignTokens.panelOutline // 面板描边
DesignTokens.rowHighlight // 选中行高亮条
DesignTokens.rowHover     // 行悬停
```

固定暗色（可硬编码，全项目通用）：

| 用途 | 值 |
|---|---|
| 行文字（未选中） | `0xFF9A9AA8` |
| 行文字（悬停） | `0xFFD7D7E0` |
| 底部操作提示 | `0xFFA9A9B8` |
| 行文字描边 | `FlxColor.BLACK` + `borderSize` |

**不要用 `DesignTokens.secondary` 显示路径、正文、说明文字** —— 它在默认主题下是黄橙色（`0xFFFFD9A0`），会让信息行看起来像警告。

### 1.2 像素类控件必须接主题监听

`FlxText` 的颜色是属性，改令牌即生效；**位图**（`ToggleSwitch` 轨道、`makePanel` 面板）不会自动跟着变，必须重绘：

```haxe
// create()
themeListener = function() rethemeNow();
DesignTokens.addThemeListener(themeListener);

// destroy()  ← 静态监听表，不摘除会留下对已销毁精灵的僵尸回调
if (themeListener != null) { DesignTokens.removeThemeListener(themeListener); themeListener = null; }
```

---

## 2. 文字（`FlxText`）

### 2.1 一律 autoSize

```haxe
var t = new FlxText(x, y, 0, '', SIZE);   // ← 宽度 0 = autoSize
t.setFormat(Paths.font('future.ttf'), SIZE, COLOR, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
t.wordWrap = false;                       // autoSize 的前提
t.textField.x = 1;                        // 1px 内边距，抵消桌面端 (-1,-1) 平移对描边的裁切
t.textField.y = 1;
t.antialiasing = ClientPrefs.data.antialiasing;
```

OpenFL 会把文本框宽度锁成「文字实际宽度 + 4」，无论文案多长都完整绘制。固定宽度盒子 + 默认 `wordWrap=true` 会让长文案**折行顶掉下一行**。

### 2.2 右对齐 = 手动算 x，不是 alignment=RIGHT

```haxe
t.x = VALUE_RIGHT - t.width;    // autoSize 文本框宽度 = 文字宽度，RIGHT 对齐对它无效
```

`alignment=RIGHT` 需要一个固定宽度盒子，而固定宽度盒子又会引出折行/裁切问题（§2.1）。两者互斥。

### 2.3 长文本裁剪：先赋值，再量宽度，且循环必须能终止

```haxe
val.text = t;                                   // ← 必须先赋，否则量到的是上一段的宽度
var fullW:Float = val.width;                    // 实测整串宽度
if (fullW > MAX_W && t.length > 5)
{
    // ① 按比例一次性估出字符预算（留 8% 余量给字宽不均）
    var keep:Int = Math.floor(t.length * (MAX_W / fullW) * 0.92) - 1;
    if (keep < 4) keep = 4;
    if (keep > t.length - 1) keep = t.length - 1;
    t = '…' + t.substr(t.length - keep);
    val.text = t;

    // ② 兜底逐字符收尾：**只截不加** → 长度严格递减
    var step:Int = 0;
    while (val.width > MAX_W && step < FIT_MAX_STEPS && t.length > 4)
    {
        t = t.substr(1);
        val.text = t;
        step++;
    }
}
```

两条纪律，**都真实踩过**：

| 坑 | 症状 | 根因 |
|---|---|---|
| 只量不赋 | 长文本撑爆面板、压住相邻标签 | 循环体只改局部变量 `t`，没 `val.text = t`，量到的宽度永远不变 |
| 循环不终止 | **点开界面直接 100% CPU 卡死** | `\'…\' + t.substr(1)` 每轮把省略号加回来，**长度恒定**；只判 `t.length > 4` 永远为真 |

所以：省略号只在**入口**加一次，循环体内只截不加；再叠一个迭代次数硬上界做双保险。裁剪宽度按**像素**算，不按字符数（CJK 与 ASCII 宽度差一倍）。

### 2.4 字体字形要先验，不能凭印象用符号

`assets/fonts/future.ttf` **实际有**：
`■ U+25A0` `□ U+25A1` `● U+25CF` `○ U+25CB` `◆ U+25C6` `◇ U+25C7` `√ U+221A` `× U+00D7` `✓ U+2713` `→ U+2192` `↑ U+2191` `↓ U+2193` `← U+2190` `… U+2026` `· U+00B7` `※ U+203B` `» U+00BB` `› U+203A` 及全部 CJK

`assets/fonts/future.ttf` **没有**：
`☑ U+2611` `☐ U+2610` `▸ U+25B8` `▶ U+25B6` `◻ U+25FB` `▪ U+25AA` `✔ U+2714` `↵ U+21B5` `⎋ U+238B` `⌫ U+232B` `⏎ U+23CE` `⟳ U+27F3` `↺ U+21BA` `⟩ U+27E9`

用没有的字形 = 该处**整块空白**，且不报任何错。要用符号前先验字库（解析 TTF cmap），不要靠肉眼猜。**能用组件就不用字符**（§0）。

---

## 3. 行布局（1280×720 基线，几何抄 `ScriptManagerSubstate`）

| 常量 | 值 |
|---|---|
| `TITLE_Y` / 标题字号 | 22 / 48 |
| `PANEL_X` `PANEL_Y` `PANEL_W` `PANEL_H` | 160 / 96 / 960 / 560 |
| `ROW_X` `ROW_START_Y` `ROW_GAP` | 204 / 164 / 56 |
| 行盒高 `ROW_BOX_H` | 40 |
| `VALUE_RIGHT`（值列右缘） | 1096 |
| `HINT_Y` / 提示字号 | 668 / 18 |

**同屏行数验算（改常量必算）**：

```
ROW_START_Y + (n-1) * ROW_GAP + 行高  ≤  PANEL_Y + PANEL_H
```

例：9 行 → `164 + 8*56 + 30 = 642 ≤ 656` ✓。不满足就必须做滚动窗口（照 `ScriptManagerSubstate` 的 `MAX_VISIBLE` + `scrollOffset`），不能让它掉出面板。

### 选中 / 悬停的视觉区分（必须同时具备三项）

| 状态 | 标签 | 行内开关 | 整行 |
|---|---|---|---|
| 选中 | `FlxColor.WHITE` | `setAlpha(1)` | `DesignTokens.rowHighlight` 磨砂条（tween 0.12s `FlxEase.cubeOut`） |
| 悬停 | `0xFFD7D7E0` | — | — |
| 普通 | `0xFF9A9AA8` | `setAlpha(0.85)` | — |

选中条是**整行圆角条**，不是 4px 竖线。

### 开关状态：渲染时读权威来源，禁止读快照

```haxe
// ❌ 快照：buildRows 时取一次，切换回调改了 ClientPrefs / 标记文件但快照不动
new BackupRow(label, '', BackupKind.TOGGLE, ClientPrefs.data.someFlag, onToggle, null);
// refreshAll(): sw.setOn(rows[i].toggleOn)   ← 拿旧值把刚拨动的开关按回去 → 「拨不动」

// ✅ 读取函数：每次渲染现读权威来源
new BackupRow(label, '', BackupKind.TOGGLE, function() return ClientPrefs.data.someFlag, onToggle, null);
// refreshAll(): sw.setOn(rows[i].readState())
```

配套两条：
- `setOn` 内部会**整块重画轨道像素**，只在 `sw.on != 目标值` 时才调（否则每次悬停变化都白重画一遍）。
- 页面刚建好时用 `setOn(state, true)` **直接吸附**，否则「已开」的开关会从关闭位置滑一段才到位（`ToggleSwitch` 内部有 `placed` 标记）。

### 开关本体有自己的命中区

照 `BaseOptionsMenu.getHoveredCheckbox()`：对开关用 `sw.hits(mx, my, 12)`（外扩 12 → 命中高 56，触控红线）单独判一次，**点在开关上时第一次点击就直接切换**，哪怕该行还没选中。否则「点一下开关」只是选中、要点第二下才生效，用起来像失灵。

### `makePanel` 两条硬规矩

```haxe
// ① 默认参数必须是编译期常量 → 主题色传 null，在函数体内解析（否则取到类加载时的快照）
function makePanel(x, y, w, h, ?radius = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null) {
    if (fill == null) fill = DesignTokens.panelFill;
    if (border == null) border = DesignTokens.panelOutline;
    // ② unique = true：同尺寸+同色会命中缓存里同一张 BitmapData，原地重绘会串图
    var spr = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
    ...
}
```

---

## 4. 交互接线

### 4.1 回车冷却门禁（写错 = 整个界面不可操作）

```haxe
// ✅ 正确
if (nextAccept <= 0 && controls.ACCEPT) acceptRow();
if (nextAccept > 0) nextAccept -= 1;

// ❌ 错误：nextAccept 只会被减到 0，else 分支要求 < 0 —— 永远进不去，导航全成死代码
if (nextAccept >= 0) { if (nextAccept > 0) nextAccept--; }
else { navTouch(); navKeyboard(); }
```

### 4.2 整屏 State 必须自己打开光标

```haxe
FlxG.mouse.visible = true;   // create() 里，外层没有别的地方会替你设
```

外层（`OptionsState` 等）在 `destroy()` 里设 `false`，不设 `true` 就是「看不到鼠标」。

### 4.3 鼠标命中

```haxe
var p = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());   // 走相机，不走 FlxG.mouse.x/y
// 热区：固定 FlxRect 整行整宽，绝不靠文本宽度
// 悬停：颜色变化
// 点击：hit != curSelected → 只选中；hit == curSelected → 执行
backBtn.setHovered(p.x, p.y);
if (FlxG.mouse.justPressed && backBtn.over(p.x, p.y)) { ... }
p.put();
```

### 4.4 输入统一走 `Controls.instance`

不要读 `FlxG.keys` —— 手柄就废了。`UI_UP_P` / `UI_DOWN_P` / `UI_LEFT_P` / `UI_RIGHT_P` / `ACCEPT` / `BACK`。鼠标分支包在 `if (!controls.controllerMode)` 里。

### 4.5 返回按钮位置

**右上角** `new BackButton(FlxG.width - 72, 12)`。左上角会被 FPS 计数器压住（看不见也点不到）。

### 4.6 副作用要成对

| 做 | 必须配套 |
|---|---|
| `FlxG.sound.music.pause()` | 记录 `musicWasPlaying`，`onBack()` 里 `play()` |
| `FlxG.mouse.visible = true` | 外层 destroy 会设 false |
| `DesignTokens.addThemeListener` | `destroy()` 里 `removeThemeListener` |
| 改 `ClientPrefs.data.*` | `ClientPrefs.saveSettings()`（否则重启丢失） |
| 新建 `ToggleSwitch` | `destroy()` 里 `sw.destroy()` |
| 打开整屏页 | 设 `OptionsState.onPlayState`，返回时复位 |

---

## 5. 布局与数据的分工

**一个语义一个字段。** 「导出备份时打包回放」和「回放目录是否跟随便携模式」是两件事，不能共用一个 `Bool` —— 勾错会静默移动用户数据。共用的后果是界面上两行看起来无关，实际联动。

---

## 6. 验证纪律

0. **凡是 `while`，先证明它一定会终止。** 本项目最短的死循环：
   `while (w > MAX && t.length > 4) t = '…' + t.substr(1);` —— 省略号每轮加回来，长度恒定。
   自查两问：① 每轮循环变量是否**单调**朝退出方向变化？② 有没有迭代次数硬上界兜底？
1. **交互元素的状态要问「谁是真身」。** 勾选框 / 开关 / 高亮这类控件，回调改了 A 之后，如果渲染读的还是 B，无论刷新多少次都会弹回去。写完问一句：改完之后，界面是从**权威来源**读到的吗？
2. **编译通过 ≠ 能用。** typecheck 只是下限；`./compile-mac.sh` 出来之后必须真机跑一次。
3. **验一个维度 ≠ 验过了。** 这套规范里的每条都踩过一次：字体字形、像素宽度、相机坐标、`nextAccept` 的取值范围……写完问自己「这个结论是从读代码来的还是从猜的」。
4. **i18n 自检 + typecheck 两个门禁都要过**：`python3 tools/i18n/check_i18n.py`、`./compile-mac.sh typecheck`。
5. **改动范围要能一句话说清**，并如实标注「未验证」项 —— 不要把「能编译」写成「能用」。
