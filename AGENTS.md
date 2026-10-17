# AGENTS.md — Meteoric Engine

## 项目

Meteoric Engine —— 基于 **Psych Engine 0.7.1h** 二次开发的 FNF 模组引擎（Haxe / OpenFL / Lime / hxcpp）。
仓库根：`/Users/raidbounce/Documents/FNF-MeteoricEngine`，分支 `master`，remote `git@github.com:Bonus-XK/FNF-MeteoricEngine.git`。
上游是 Psych，**不要**按原版 FNF / 旧版 Psych 的写法想当然。

## 界面改动前必读

**`docs/UI-DESIGN.md` 是权威约束**（不是建议）。任何 State / Substate / 面板 / 选项页的改动之前先读它。核心几条：

- **复用，不自造**：开关一律 `objects.ToggleSwitch`（96×32 胶囊 + 22px 白圆滑块，与设置界面、更新界面同一个类）；面板用各 State 内的 `makePanel`；选项用 `options.Option` + `BaseOptionsMenu`；几何基线抄 `substates.ScriptManagerSubstate`。同一语义的控件在两处长得不一样就是 bug。不要用 ■/□ 字符代替开关。
- **主题色走 `DesignTokens.*` 运行时令牌**，禁止硬编码主题色字面值。`DesignTokens.secondary` 偏黄，**不要**拿它当正文色 / 信息色 / 路径色。位图类控件（ToggleSwitch 轨道、面板）必须接 `DesignTokens.addThemeListener` 并在 `destroy()` 里 `removeThemeListener`。
- **`FlxText` 一律 autoSize**：`new FlxText(x, y, 0, '', size)` + `wordWrap = false` + `textField.x/y = 1`（避免描边被裁）。右对齐用 `x = 右缘 - width`，**不用** `alignment = RIGHT`（那需要固定宽度盒子，会引出折行/裁切）。
- **长文本裁剪**：先赋 `val.text` 再量 `val.width`；省略号只在入口加一次，循环体内**只截不加**（`t.substr(1)`），并加迭代次数硬上界。`'…' + t.substr(1)` 每轮长度恒定，只判长度 = 死循环卡死。
- **字体字形要先验**：`assets/fonts/future.ttf` **没有** `☑ U+2611` `☐ U+2610` `▸ U+25B8` `▶ U+25B6` `↵ U+21B5` `⎋ U+238B` `⌫ U+232B` 等；**有** `■ □ ● ◆ √ × → ↑ ↓ ← … ·` 及全部 CJK。用没有的字形 = 整块空白且不报错。能用组件就别用字符。
- **选中态三项齐全**：整行 `DesignTokens.rowHighlight` 磨砂条 + 标签纯白 + 行内开关 `setAlpha(1)`（未选中 `0.85`）。选中条是整行圆角条，不是竖线。
- **同屏行数必须验算**：`ROW_START_Y + (n-1)*ROW_GAP + 行高 ≤ PANEL_Y + PANEL_H`，不满足就做滚动窗口（照 `ScriptManagerSubstate` 的 `MAX_VISIBLE` + `scrollOffset`）。
- **交互接线**：回车冷却写成 `if (nextAccept <= 0 && ACCEPT) …; if (nextAccept > 0) nextAccept -= 1;`（写成 if/else 且要求 `nextAccept < 0` 会让整个导航变成死代码）；整屏 State 必须在 `create()` 里 `FlxG.mouse.visible = true`；命中用 `FlxG.mouse.getScreenPosition(cameras[0])` + 固定 `FlxRect` 热区；滚轮走 `backend.WheelScroll`；返回按钮放右上角 `FlxG.width - 72`（左上角被 FPS 计数器压住）；输入统一走 `Controls.instance`（手柄可用）。
- **副作用成对**：暂停 BGM 就要记得恢复；改 `ClientPrefs.data.*` 就要 `ClientPrefs.saveSettings()`；新建 `ToggleSwitch` 就要在 `destroy()` 里 `sw.destroy()`；开关整屏页就要设/复位 `OptionsState.onPlayState`。
- **`makePanel` 两条硬规矩**：主题色默认参数传 `null` 在函数体内解析（默认参数必须是编译期常量）；`makeGraphic(…, unique = true)`（否则原地重绘串图）。
- **一个语义一个字段**：「导出时打包回放」与「回放目录是否跟随便携模式」不能共用一个 `Bool`，勾错会静默移动用户数据。

## 构建与验证

```bash
cd /Users/raidbounce/Documents/FNF-MeteoricEngine
METEORIC_BACKUP_MODS=0 METEORIC_BACKUP_CONTAINERS=0 ./compile-mac.sh typecheck   # 4~5 分钟，退出码 0 = 通过
METEORIC_BACKUP_MODS=0 METEORIC_SKIP_CODESIGN=1 ./compile-mac.sh                # 本地迭代 ~25 秒（跳过签名，勿分发）
python3 tools/i18n/check_i18n.py                                                 # 语言包自检，退出码 0 = PASS
```

- 两个门禁（typecheck + i18n）都要过。
- **编译通过 ≠ 能用**，必须真机跑一次；提交信息里如实标注「未验证」项。
- 凡是 `while` 先证明一定会终止（见 `docs/UI-DESIGN.md` §6）。
- **不要删**用户的录像产物和 `Contents/Resources/mods` 里的谱面数据。
- 本机 haxe/lime/hxcpp 装在 `/usr/local`（Intel Homebrew），工具链跑在 Rosetta 下；已用自编 arm64 `tools/lime.ndll.wallclock-arm64` 修正。`METEORIC_ARCH=x86_64` 可退回 Intel 构建。`codesign` 这个 bundle 要 4 分钟以上，构建需 `idleTimeoutSeconds: 1800`。
- 启动游戏必须走终端（访达双击 trace 不可见）：
  `cd ".../Meteoric.app/Contents/MacOS" && ./Meteoric > /tmp/meteoric_debug.log 2>&1 &`
- 提交用 Conventional Commits，一个改动一个 commit。

## 产品约束（用户明确要求）

- **不许为速度吃内存**；加载优化方案必须通用，禁止硬编码官方曲目。
- **降采样完全放弃**，不要再提。
- 新功能默认关闭、零行为变化。
- 用户会反复要求「爆改 lib」（改 lime ndll / C++ 层），纯 Haxe 方案说清楚代价后再上。

## Haxe / 本项目限制（实测）

- `source/import.hx` 是全局自动导入且含 `import llua.*` → **任何 `#if macro` 宏类都编译失败**（宏上下文禁止 `cpp.RawPointer`）。编译期信息用构建脚本生成数据文件。
- 类内不能定义类；`enum` / `enum abstract` 不能嵌套在类里，一律提为顶层文件。
- Haxe 不支持 `?.` 安全导航；`Math.floorMod` 不存在；`%` 对负数返回负值，要自己纠正。
- `haxe.zip` 没有 `addEntry` / `writeToFile` / `loadEntriesFromDisk`，与 JS 版 API 完全不同。
- `BytesBuffer` 只有 `addByte` / `add` / `addBytes`，没有 `writeInt32` / `bigEndian`。
- `@:privateAccess` 只作用于紧随其后的那一条语句；插入式修改容易把它顶到别处。
- **写任何 API 前先查源码，不要凭印象。**
