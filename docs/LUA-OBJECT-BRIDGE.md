# Lua 对象桥（Object Bridge）—— Lua 直接操作 Haxe 对象

> 2026-10-27 引入。目标：让 Lua 脚本获得接近「改源码」的对象操作能力。
> 本模块是**纯增量**功能：不改任何既有 Lua 函数的行为，旧 mod 零影响。

## 为什么需要它

Meteoric 的 Lua 层（`llua/Convert.hx`）无法把 Haxe 类实例传进 Lua——`Convert.toLua`
遇到 FlxSprite / Character / FlxCamera 等对象一律压 nil。所以传统 Lua 只能靠
字符串路径间接操作（`setProperty('boyfriend.x', 100)`），每次读写都要重新解析路径，
且无法持有对象引用、无法链式调用、无法调用返回对象的方法。

对象桥给 Lua 一等公民对象句柄：拿到一次，之后所有属性读写和方法调用直接落在
Haxe 对象上（等价于在源码里操作这个对象）。

## 快速上手

```lua
function onCreate()
    -- 1. 按路径取对象（路径语义与 getProperty 一致，另支持完整类路径）
    local bf = getObj('boyfriend')

    -- 2. 属性读写：像 Lua 表一样直接用点号（实际触发 Reflect 读写）
    bf.x = bf.x + 100
    debugPrint(bf.y)                -- 读属性返回原始值

    -- 3. 方法调用：冒号语法（等价 Reflect.callMethod）
    bf:playAnim('hey', true)

    -- 4. 构造任意类（完整类名 + 构造参数表）
    local spr = newObj('flixel.FlxSprite', {0, 0})
    spr:makeGraphic(100, 100, 0xFFFF0000)
    spr:screenCenter()
    objCall(getObj('game'), 'add', spr)   -- 句柄作为参数传回 Haxe（Lua 无 add 全局函数）

    -- 5. 任意类的静态成员
    local flxg = getObj('flixel.FlxG')
    flxg.sound:play(Paths.music('freakyMenu'))

    -- 6. 容器成员：0 基索引（Haxe 风格，不是 Lua 的 1 基！）
    local notes = getObj('game.notes')
    local note0 = notes.members[0]
    note0.alpha = 0.5

    -- 7. 链式调用：返回对象的地方全部自动包成句柄
    local cam = getObj('game').camera
    cam:shake(0.01, 0.2)
end
```

## 完整 API（13 个新全局函数）

| 函数 | 说明 |
|---|---|
| `getObj(path)` | 按路径解析对象为句柄。支持 `boyfriend`、`game.notes`、`flixel.FlxG`（类静态）；解析失败返回 nil |
| `newObj(className, ?args)` | `Type.createInstance` 构造任意类。`args` 为 Lua 数组 `{x, y}` |
| `objGet(h, key)` | 显式读属性（key 支持 `'members[0]'` 括号语法） |
| `objSet(h, key, v)` | 显式写属性（v 是句柄时自动还原为对象） |
| `objCall(h, name, ...)` | 显式调方法（等价 `h:name(...)` 冒号语法） |
| `objEq(a, b)` | 判断两个句柄是否指向同一对象 |
| `isObj(v)` | 判断一个值是否为句柄 |
| `objType(h)` | 返回对象类名，如 `'Character'`、`'flixel.FlxSprite(class)'` |
| `objKeys(h)` | 返回字段名数组（`Reflect.fields`；数组返回自身） |
| `objLen(h)` | 数组长度；FlxTypedGroup 等容器取 `.members` 长度 |
| `releaseObj(h)` | 释放句柄对应的注册表槽位（长期大量建句柄时建议手动释放） |
| `objCount()` | 当前注册表句柄数（调试用） |
| `runHaxeCodeObj(code, ?vars, ?func, ?args)` | 同 `runHaxeCode`，但返回的**对象**不再被压成 nil，而是包成句柄 |

内部另有 10 个 `__hx_*` 回调名（已冻结进 `tools/contract/script-surface.tsv`）与
胶水名 `__HXOBJ_MT` / `__HX_WRAP`，请勿在脚本里占用。

## import 与 class（HScript 同款语义）

**import**——绑定 Haxe 类/枚举到脚本全局：

```lua
import('flixel.FlxSprite')              -- _G.FlxSprite = 类句柄（自动取末段短名）
import('backend.WeekData', 'WD')        -- _G.WD = 类句柄
import('flixel.util.*')                 -- 包懒解析表（访问成员时按需绑定并缓存）
import('mylib.lua') / import('lib')     -- 旧语义：Lua 库文件导入（不变）
```

类句柄支持静态访问与 **`Foo(...)` 直接构造**（`__call` 元方法）。

**class 继承 Haxe 类**——`Class.new` 的 parent 传类句柄即可：

```lua
Class.new('MySprite', FlxSprite)
function MySprite:new(x, y) self.hp = 99 end   -- 构造参数同时给 Haxe 构造与 new()
local m = MySprite(30, 40)
m:makeGraphic(20, 20, 0xFFFFFF00)              -- Haxe 方法（继承）
m.x = m.x + 5                                  -- 写穿透：Haxe 侧有的字段写 Haxe，没有的写 Lua 表
self.__hxobj.x = 1                             -- 显式直写 Haxe 属性
```

限制（诚实版）：**引擎主动回调的虚方法（update/draw 等）不会进 Lua**——真对象上没有
override，引擎 C++ 调用绕过脚本层；Lua 侧能覆盖的是「脚本自己调用」的方法。

**枚举**：`getEnum(path)` 拿枚举句柄（成员 `cd.ONE` 经 `Type.createEnum` 读取）、
`makeEnum(path, 'CTOR', args)` 构造枚举值。注意：
- 路径用 **hxcpp 运行时类型路径**：模块内声明的子枚举 `Countdown` 是
  `backend.Countdown`（不是 `backend.BaseStage.Countdown`，源码速记在注册表里不存在）；
- String 背书的 abstract enum（如 `FlxTextAlign`）**值就是字符串**，直接传 `'center'`；
- 常用引擎枚举已显式保活（`backend.Countdown` / `objects.Alignment`），hxcpp 的
  `resolveEnum` 对部分枚举拿不到（HScript 同限，其靠 preset 注入常量绕过）。

**迭代**：数组用数字索引；Map 用 `objKeys(map)`（已支持 `keys()` 迭代器）+ `objGet`。

## 界面脚本（menus/*.lua）也支持

对象桥同时接入了界面脚本系统（`MenuScript`）：`menus/<界面名>.lua`（main_menu、
freeplay、story_menu、options、pause、results、gameover）里可用**全部同名 API**。

菜单模式的差异（自动适配，无需开关）：

| 项 | 游玩脚本 | 界面脚本 |
|---|---|---|
| `getObj('xxx')` 根解析 | PlayState 脚本对象 / 实例字段 | `scriptObjects` / 当前界面的字段 / `state` |
| `getObj('state.xxx')` | `state` = PlayState | `state` = 当前界面实例 |
| 完整类路径 + `newObj` | ✓ | ✓（相同） |
| 括号路径 `'members[0]'` | ✓ | ✗（用数字索引 `h.members[0]`） |
| `runHaxeCodeObj` | ✓ | 返回 nil（菜单无 HScript 模块） |
| 句柄注册表清理 | `PlayState.destroy` | 最后一个界面脚本销毁时（不在 PlayState 时） |

界面脚本示例（结算界面）：

```lua
function onCreate()
    local grp = getObj('grpMenuShit')       -- 界面字段 → FlxTypedGroup 句柄
    local item = grp.members[0]             -- 0 基索引 → MenuText 句柄
    item.alpha = 0.8
    local btn = getObj('menuButtons')[0]    -- 数组字段 → 元素句柄
    btn.x = btn.x + 20
    objCall(getObj('state'), 'add', newObj('flixel.FlxSprite', {0, 0}))
end
```

注意：界面脚本加载时机很早（`onCreate` 时部分控件尚未创建），引用界面对象建议
放在 `onUpdate` 延迟若干帧之后。

## 语义与限制（重要）

1. **数组是 0 基**（Haxe 风格）：`notes.members[0]` 是第一个音符。
2. **数组 / Map 也是句柄**（保持引用）：`h.someArray[0]` 取到的元素仍是句柄；
   但它们不支持 `pairs()` / `#`，长度用 `objLen(h)`，字段清单用 `objKeys(h)`。
3. **句柄跨脚本可共享**：`getObj('boyfriend')` 在任何脚本里拿到的是同一个对象
   （`objEq` 为 true）。
4. **生命周期**：句柄注册表在 `PlayState.destroy()` 时整体清空。切换状态后旧句柄
   指向已销毁对象，读写会静默失败（不会崩），建议 `onDestroy` 里 `releaseObj`。
5. **Lua 函数不能传给期望 Haxe 函数的参数**（与既有 `callMethod` 同一限制）。
   Lua 表传给 Haxe 参数时变成匿名对象（字段可被 Haxe 侧 Reflect 读取）。
6. **重入警告**：方法调用执行任意 Haxe 代码；不要在 `onUpdate` 等高频回调里调用
   会触发脚本回调的方法（如 `startSong`），与既有 `callMethodFromClass` 同一风险面。
7. **枚举值**：可作句柄传递，但字段读写未必有意义（hxcpp 枚举内部表示）。
8. `runHaxeCodeObj` 里用 HScript 返回对象时，Lua 侧拿到的句柄与 `getObj` 句柄
   等价互通。
9. 菜单模式下 `LuaUtils` 依赖 PlayState 的特殊通道（括号路径等）不可用，已自动
   回退到 Reflect 通道；`PlayState.instance == null` 是模式检测依据。
10. **【架构性】Lua 函数不能传给 Haxe 回调参数**（tween onComplete / FlxTimer 回调等）：
    桥接后的回调会在任意 Haxe 时机被调用，绕开 `luaCallDepth` 嵌套防护，实测触发
    LuaJIT 栈堆损坏 SEGV（2026-10-28 真机复现）。传函数参数处安全置空并给诊断；
    带回调的逻辑请用 `runHaxeCodeObj`。
11. 对枚举对象做 `Reflect`/`getClass`、ObjectMap 哈希枚举值，在 hxcpp 上均实测 SEGV——
    引擎内部已全部绕开（标记式路由 + `Type.createEnum`），但脚本不要对枚举句柄用
    `pairs`/`rawget` 之类。

## 实现位置

- 实现：`source/psychlua/ObjectBridge.hx`（约 470 行，含 Lua 胶水字符串）
- 注册点：`source/psychlua/FunkinLua.hx`（`ObjectBridge.implement(this)`，在
  `MiscCommands` 之后）
- 清理点：`source/states/PlayState.hx` `destroy()`（`clearRegistry()`）
- 契约：`__hx_getObj` `__hx_newObj` `__hx_obj_index` `__hx_obj_newindex`
  `__hx_obj_call` `__hx_obj_type` `__hx_obj_keys` `__hx_obj_len`
  `__hx_obj_release` `__hx_obj_count`（10 个 Lua 唯一名，基线 lua_unique 227→238）
