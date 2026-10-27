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

## 实现位置

- 实现：`source/psychlua/ObjectBridge.hx`（约 470 行，含 Lua 胶水字符串）
- 注册点：`source/psychlua/FunkinLua.hx`（`ObjectBridge.implement(this)`，在
  `MiscCommands` 之后）
- 清理点：`source/states/PlayState.hx` `destroy()`（`clearRegistry()`）
- 契约：`__hx_getObj` `__hx_newObj` `__hx_obj_index` `__hx_obj_newindex`
  `__hx_obj_call` `__hx_obj_type` `__hx_obj_keys` `__hx_obj_len`
  `__hx_obj_release` `__hx_obj_count`（10 个 Lua 唯一名，基线 lua_unique 227→238）
