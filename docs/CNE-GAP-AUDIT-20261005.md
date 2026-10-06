# CNE 模组兼容缺口清单（2026-10-05 静态调研）

> **本文档只记录调研结论，未改动任何代码。**
> 全部结论来自源码比对 + 离线数据推演，**未经实机验证**的条目已显式标注。
> 参照物：`~/Documents/CodenameEngine-main`（CNE 源码）、`~/Downloads/saturday_morning_alive/mods/SMA`（真实模组）。

---

## 0. 本轮结论摘要

| # | 缺口 | 严重度 | 状态 | 实机验证 |
|---|---|---|---|---|
| 1 | `Play Animation` 丢失第 3、4 参数（`Is forced?` / `Animation Context`） | **高** | 未修 | ❌ |
| 2 | 角色无 `Context` / `LOCK` 概念，动画播完必回 idle | **高**（与 #1 同源） | 未修 | ❌ |
| 3 | `strumLines[].characters[1+]` 被丢弃，多角色无法同时站位 | 中 | 未修 | ❌ |
| 4 | `strumLines[].characters[1+]` 缺 `charSpacingX` 错位机制 | 中（#3 附属） | 未修 | ❌ |
| 5 | `defaultCamZoom = -1.8`（负数）来源未定位 | 中 | 阻塞中 | ❌ |
| 6 | CNE 独立 `songs/*/events.json` 不加载（3 首歌依赖） | 中 | 未修 | ❌ |
| 7 | CNE 脚本 API 缺口（`strumLines` / `setIcon` / `getIcon` / `Character.xml` / `CoolUtil.fpsLerp`） | 中 | 未修 | ❌ |
| 8 | `Camera Position` 与 `CameraHudDomain.moveCamera` 架构冲突 | 中 | 已放弃回退 | ❌ |
| 9 | `'GF FEAR'` vs `'GF FEAR '`（尾部空格）| 低 | 按用户决定不修 | ❌ |

**已修复并实机确认**：`GF 变普通 GF`（2026-10-05，用户确认「成功」）。

---

## 1. 缺口 #1 + #2：`Play Animation` 参数截断 + 无 LOCK 语义

### 1.1 CNE 的权威语义

`CodenameEngine-main/source/funkin/backend/chart/EventsData.hx:114-121` 定义该事件有 **4 个参数**：

```haxe
"Play Animation" => [
    {name: "Character",          type: TStrumLine, defValue: 0},
    {name: "Animation",          type: TString,    defValue: "animation"},
    {name: "Is forced?",         type: TBool,      defValue: true},
    {name: "Animation Context",  type: TDropDown(["NONE","SING","DANCE","MISS","LOCK"]),
                                 defValue: "NONE"}
]
```

CNE 的执行（`funkin/game/PlayState.hx:1727-1729`）：

```haxe
case "Play Animation":
    if (strumLines.members[event.params[0]] != null && ...characters != null)
        for (char in strumLines.members[event.params[0]].characters)
            if (char != null && char.hasAnim(event.params[1]))
                char.playAnim(event.params[1], event.params[2],
                              event.params[3] == "NONE" ? null : event.params[3]);
```

注意两点：
- **遍历该 strumLine 的全部 `characters`**（不是只取 `[0]`）→ 与缺口 #3 联动。
- **`hasAnim` 前置检查**：动画不存在就静默跳过。

### 1.2 `PlayAnimContext` 五态定义

`funkin/backend/scripting/events/sprite/PlayAnimContext.hx`：

| 值 | 文档原文 | 作用 |
|---|---|---|
| `NONE` | "The character won't dance until the animation is finished" | 播完前不 dance |
| `SING` | "The character will only dance after their holdTime is reached" | 配合长按 |
| `DANCE` | "The character's dancing wont be blocked" | 正常 |
| `MISS` | "Only for scripting, since it has the same effects as SING" | 脚本用 |
| **`LOCK`** | **"Locks the character's animation. Prevents the character from dancing, even if the animation ended."** | **播完也停住，永久** |

### 1.3 LOCK 的实际实现机制

`LOCK` 不是靠一次性标志，而是靠 `FunkinSprite` 上的**持久字段** `lastAnimContext`：

```haxe
// FunkinSprite.hx:229
public var lastAnimContext:PlayAnimContext = DANCE;   // 默认 DANCE

// FunkinSprite.hx:247（playAnim 内）
lastAnimContext = Context;

// FunkinSprite.hx:161-168（beatHit 内）—— LOCK 时整个 beat 动画轮播被跳过
public function beatHit(curBeat:Int) {
    if(!animEnabled) return;
    if (lastAnimContext != LOCK && beatAnims.length > 0 && (curBeat + beatOffset) % beatInterval == 0) {
        var anim = beatAnims[FlxMath.wrap(countedBeat++, 0, beatAnims.length - 1)];
        if (anim.name != null && ...)
            playAnim(anim.name, anim.forced);
    }
}
```

即：`LOCK` 同时阻止「动画结束回 idle」和「后续 beat 触发 dance」两件事。

### 1.4 引擎侧的截断点

**`source/states/editors/content/CneExport.hx:574-576`**：

```haxe
subEvents.push(['Play Animation',
    (params.length > 1 ? paramText(params[1]) : ''),   // ① 动画名
    animTarget(params, lineTypes)]);                     // ② 角色
// params[2] = Is forced?        ← 丢弃
// params[3] = Animation Context ← 丢弃
```

**`source/backend/EventDomain.hx:228-252`**：

```haxe
case 'Play Animation':
    var char:Character = ps.dad;
    switch(value2.toLowerCase().trim()) { /* bf / gf / 0 / 1 / 2 → 选角色 */ }
    if (char != null) {
        char.playAnim(value1, true);      // Force 硬编码 true
        char.specialAnim = true;
    }
```

引擎侧 `Character.playAnim`（`source/objects/Character.hx:487`）签名里**没有 Context 参数**：

```haxe
public function playAnim(AnimName:String, Force:Bool = false,
                         Reversed:Bool = false, Frame:Int = 0):Void
```

### 1.5 为什么表现为「不变身」——完整因果链

`source/objects/Character.hx:337-339`：

```haxe
else if(specialAnim && isAnimationFinished()) {
    specialAnim = false;
    dance();          // ← 无条件回 idle
}
```

以 SMA `really-happy` 的 `death` 事件（t=187886）为例：

```
CNE:  Play Animation [0,'death',True,'LOCK']
      → reallyhappyrat 播 death，lastAnimContext=LOCK
      → 动画播完，beatHit 因 LOCK 被跳过 → 永远停在 death  ← CNE 的「变身」

引擎: Play Animation ['death','dad']        ← Context 丢了
      → dad.playAnim('death', true); specialAnim = true
      → 动画播完 → Character.hx:337 dance() → 立刻弹回 idle
      → 视觉上「什么都没发生」
```

### 1.6 SMA 全部 `Play Animation` 事件（离线枚举确认）

```
really-happy  t=65829   params=[0, 'dance', True, 'NONE']
really-happy  t=187886  params=[0, 'death', True, 'LOCK']   ← LOCK
smile         t=90286   params=[0, 'hi',    True, 'LOCK']   ← LOCK
```

三首都指向 `strumLine 0`（`type=0` → 对手）。`animTarget` 映射（`CneExport.hx:680-690`）已正确产出 `'dad'`，目标角色 `reallyhappyrat.xml` 确有 `dance` / `death` 动画（已 grep 确认）。

**结论：角色选对了、动画名也对，唯一丢失的是 Context。** 这解释了用户报告的「人物仍然不变身」。

### 1.7 潜在修法（未实施，供决策）

引擎侧需要两处协同，缺一不可：

1. **`Character` 增加锁定状态**——类似 CNE 的 `lastAnimContext`，例如 `public var animLock:Bool = false;`，并在 `Character.hx:337` 的 `else if(specialAnim && isAnimationFinished())` 分支里加 `&& !animLock`，同时在 `PlayState` 的 `beatHit`→`dance()` 路径上同样跳过。
2. **`CneExport` 透传第 3、4 参数**——但 Psych 的 `SwagSong` 事件是 `[String, String, String]`（name + value1 + value2），**只有两个值槽**（`source/objects/Note.hx:38-43` 的 `EventNote` typedef 印证）。两个多余参数无处安放。

**因此这是架构级缺口，不是补一行能解决的。** 可选方向（需用户决策）：
- 把 `Context` 编码进 value1/value2 的约定（如前缀 `lock:`），由 `EventDomain` 解析；
- 或在 `CneExport` 里为带 `LOCK` 的事件额外注入一条引擎自定义事件（如 `'Lock Animation'`），走现有事件通道。

---

## 2. 缺口 #3 + #4：`characters[1+]` 被丢弃

### 2.1 SMA 的实际数据

```
happy         line0 type=0 characters=['sadrat', 'happyrat', 'happierrat']   ← 3 个
smile         line0 type=0 characters=['randah', 'randy']                    ← 2 个
              line1 type=1 characters=['boyfunkle', 'bfsma']                 ← 2 个
really-happy  line0 type=0 characters=['reallyhappyrat']
Unhappy       line0 type=0 characters=['sadrat']
whispers      line0 type=0 characters=['whispers']
```

### 2.2 CNE 的语义：**全部创建、同时在台上**

`funkin/game/PlayState.hx:810-821`：

```haxe
var chars = [];
...
if (strumLine.characters != null) for(k=>charName in strumLine.characters) {
    var char = new Character(0, 0, charName, stage.isCharFlipped(...));
    stage.applyCharStuff(char, charPosName, k);   // ← k = 数组下标
    chars.push(char);
}
```

`for(k=>...)` 的 `k` 被传给 `applyCharStuff` → `StageCharPos.prepareCharacter`（`funkin/game/Stage.hx:454-457`）：

```haxe
public function prepareCharacter(char:Character, id:Float = 0) {
    _id = id;
    char.setPosition(x + (id * charSpacingX), y + (id * charSpacingY));
    ...
}
```

间距默认值（`Stage.hx:428-429`，可被舞台 XML 的 `spacingx`/`spacingy` 覆盖）：

```haxe
public var charSpacingX:Float = 20;
public var charSpacingY:Float = 0;
```

**结论：CNE 让同一 strumLine 的多个角色同时存在于舞台上，靠 `charSpacingX`（默认 20px）水平错开。** `happy` 的三只老鼠是同时站着的，不是「变身」。

> SMA 的舞台 XML **没有** `spacingx`/`spacingy` 属性（已 grep `mods/SMA/data/stages/*.xml` 确认），故用默认 20/0。

### 2.3 引擎侧截断点

**`source/states/editors/content/CneExport.hx:346-361`**：

```haxe
var chars:Array<Dynamic> = cast line.characters;
if (chars != null && chars.length > 0 && chars[0] != null)
{
    var cname:String = Std.string(chars[0]);    // ← 只取索引 0
    ...
    case 1: player1 = cname;
    case 0: player2 = cname;
    case 2: gfVersion = cname;
}
```

Psych 的 `SwagSong` 只有 `player1` / `player2` / `gfVersion` 三个**单值字段**（`CneExport.hx:330-332` 的默认值声明），无法表达「一条 strumLine 多个角色」。

### 2.4 连带影响

`CneModCompat.iconCharacterForSong`（`source/cne/CneModCompat.hx:761-781`）**已经**正确遍历 `characters` 全数组：

```haxe
for (ch in chars) { ... if (iconUsable(mod, c)) return c; }
```

所以 Freeplay 图标选取不受本缺口影响（见 §3）。

### 2.5 潜在修法（未实施）

需要 Psych 侧支持多角色 strumLine，属引擎架构改动。可选方向：
- 在 `PlayState` 里为每个 strumLine 维护 `Array<Character>`，现有 `boyfriend`/`dad`/`gf` 降级为 `[0]` 的别名（改动面大，风险高）；
- 或仅对 CNE 模组走独立路径（隔离性好，但两套角色生命周期）。

---

## 3. Freeplay 小图标：代码已完备（静态推演 5/5 通过）

### 3.1 已实现的两道兜底

**① `HealthIcon.changeIcon`（`source/objects/HealthIcon.hx:44-59`）** —— CNE 目录形态图标：

```haxe
if(!Paths.fileExists('images/' + name + '.png', IMAGE) && cne.CneModCompat.isEnabled()
    && Paths.fileExists('images/icons/' + char + '/icon.png', IMAGE))
    name = 'icons/' + char + '/icon';
```
之后还有 `-pe` 档与 `icon-face` 兜底。

**② `CneModCompat.cneFreeplayWeek`（`source/cne/CneModCompat.hx:606-624`）** —— `meta.icon` 是占位时改用谱面里的真实角色名：

```haxe
var icon:String = (meta != null && meta.icon != null && ...) ? Std.string(meta.icon) : 'face';
// CNE 的 meta.json `icon` 经常是占位：SMA 全部 5 首曲都写 "face"…
if (!iconUsable(mod, icon)) {
    var fallbackChar:String = iconCharacterForSong(mod, dir, meta);
    if (fallbackChar != null && ... && iconUsable(mod, fallbackChar)) icon = fallbackChar;
}
```

`iconUsable`（`:668-681`）刻意**不把 `icons/icon-face.png` 当作 `face` 的有效图标**，否则会挡住 CNE 目录兜底。

### 3.2 离线推演结果

复刻 `iconUsable` + `HealthIcon.changeIcon` 判定链（含 `Paths.fileExists` 的 mods 分支与引擎 `assets/preload/` 分支），逐曲推演：

| 曲目 | `meta.icon` | 选中角色 | 最终贴图 | 结果 |
|---|---|---|---|---|
| Unhappy | `"face"` | `sadrat` | `icons/sadrat/icon` | ✓ |
| happy | `"face"` | `sadrat` | `icons/sadrat/icon` | ✓ |
| really-happy | `"face"` | `reallyhappyrat` | `icons/reallyhappyrat/icon` | ✓ |
| smile | `"face"` | `randy` | `icons/randy/icon` | ✓ |
| whispers | `"face"` | `bf` | `icons/icon-bf`（引擎内置） | ✓ |

`whispers` 走的是引擎自带的 `assets/preload/images/icons/icon-bf.png`——该曲谱面里对手是 `whispers`（无图标目录），玩家是 `bf`。

**结论：Freeplay 图标逻辑无需改动，待实机确认。**

### 3.3 角色 XML 的 `icon` 属性交叉核对

```
bf-deadsma       icon="bf-deadsma"   sprite="BOYFRIEND_SMA"
bfsma            （无 → 取名字）      sprite="BOYFRIEND_SMA"
boyfunkle        icon="bfsma"        sprite="boyguy"
dooku            icon="dooku"
happierat        icon="happierat"    sprite="happierrat"
happyrat         （无 → 取名字）
randah           icon="randy"
randy            icon="randy"
reallyhappyrat   icon="reallyhappyrat"
sadrat           （无 → 取名字）
whispers         icon="whispers"     sprite="whisper"
```

`CneModCompat.characterJson:322-324` 已实现 `icon` 属性读取与「缺省用角色名」兜底。

---

## 4. 缺口 #5：`defaultCamZoom = -1.8`（负数，阻塞中）

已定位到计算结果为负（`base=-1 → final=-1.6`），但**负值来源未定位**。

- `ps.defaultCamZoom` 为负 → `Camera Zoom` 事件算出负 zoom
- SMA 各 `Camera Zoom` 事件的 `mode` 全为 `"stage"`（应乘舞台常量 zoom = 0.75）
- 来源不明：可能来自 CNE 舞台 XML 的 `zoom` 属性解析，或引擎侧 `defaultCamZoom` 初始化

**建议**：先埋点打印 `defaultCamZoom` 的赋值链与 CNE 舞台 `zoom` 的解析结果，取真值再写逻辑。**不要再盲改。**

---

## 5. 缺口 #6：CNE 独立 `songs/*/events.json` 不加载

SMA 有 3 首歌依赖独立 events 文件，CNE 会自动合并，引擎侧目前不读。

---

## 6. 缺口 #7：CNE 脚本 API 缺口

SMA 的 `songs/UI.hx` 等脚本使用以下 CNE API，引擎侧缺失：

| API | 用途 |
|---|---|
| `strumLines` | 访问 strumLine 集合 |
| `setIcon` / `getIcon` | 运行时换图标 |
| `Character.xml` | 读取角色 XML |
| `CoolUtil.fpsLerp` | 帧率无关插值 |

---

## 7. 缺口 #8：`Camera Position` 与 `CameraHudDomain.moveCamera` 冲突（已放弃）

`source/backend/CameraHudDomain.hx:280/287` 每 section 重写 `camFollow`，与 CNE 的 `Camera Position` 事件语义冲突。

**历史**：连续四轮修改失败且破坏引擎状态，已回退。**不建议在无明确收益下重启。**

---

## 8. 缺口 #9：`'GF FEAR'` 尾部空格（低优先级）

`saturday_morning_alive/assets/data/characters/gf.xml` 引用 `anim="GF FEAR"`，而图集 `Animation.json` 的符号名是 `'GF FEAR '`（尾部多一个空格）。

11 个动画名匹配 10 个，唯一差异即此。**用户决定暂不修复。**

修法（若将来要做）：`CneModCompat.characterJson` 在转换 `anim` 名前做 `StringTools.trim`，既修此例也对同类笔误免疫。风险：理论上会误改刻意用空格命名的符号（可能性极低）。

---

## 9. 方法论提醒

本次调研中有两处**先前结论被证据推翻**，记录在此以免重犯：

1. **「SMA 的 `ATLAS.SPRITES` 格式需要 CNE 的 `flixel-animate`，stock `flxanimate` 解析不了」——错误。**
   `flxanimate 4.0.0` 的 `FlxAnimateFrames.hx:118` 就写着 `for (sprite in json.ATLAS.SPRITES)`，帧与动画（`AN`/`SD`/`MD`）均为原生支持。SMA 的 GF 图集零改动即可加载。

2. **「人物不变身的根因是 `CneExport.hx:351` 只取 `chars[0]`」——错误。**
   角色选取本身正确（`animTarget` 已按 `strumLine.type` 映射）。真正丢失的是 `Play Animation` 的第 3、4 参数，尤其 `Animation Context = 'LOCK'`。

**通用教训**：移植前须读透目标引擎的**既有设计**（本次是 CNE 的 `lastAnimContext` 字段与 Psych 的双值槽限制）；先埋点取真值再写逻辑；写入数值须校验。