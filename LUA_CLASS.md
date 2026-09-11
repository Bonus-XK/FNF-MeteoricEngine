# Lua class 系统（支持继承）

游玩脚本（`data/...`、`custom_events/...` 等）与界面脚本（`menus/<界面名>.lua`）都内置了 class 功能，无需任何前置操作即可使用。

## 基本用法

```lua
-- 定义类
Class.new('Enemy')

-- 构造函数（可选）：用 new 关键字
function Enemy:new(x, y)
	self.x = x or 0
	self.y = y or 0
	self.hp = 10
end

-- 普通方法
function Enemy:update()
	self.x = self.x + 1
end

-- 创建实例（两种写法等价）
local e1 = Enemy.new(5, 6)
local e2 = Enemy(5, 6)

e1:update()
print(e1.x)      -- 6
```

## 继承

```lua
Class.new('Boss', Enemy)   -- Boss 继承 Enemy

function Boss:new(x, y, hp)
	Enemy.new(self, x, y)   -- 调用父类构造函数
	self.hp = hp or 999
end

function Boss:update()
	Enemy.update(self)      -- 调用父类方法
	self.hp = self.hp - 1
end

local b = Boss(1, 2, 100)
print(b.hp)                -- 100
```

- 子类不写 `new` 时会自动使用父类的构造函数。
- 支持多层继承：`Class.new('C', B)` 后 C 可继续继承 B 的父类方法。
- 继承链上的静态方法也可以直接调用（`GrandBoss.someStatic()`）。

## 类型判断

```lua
Enemy.isInstanceOf(e)        -- true（子类实例也返回 true）
e:isInstanceOf(Enemy)        -- 等价写法
Class.isInstanceOf(e, Enemy) -- 等价写法
Class.isSubclassOf(Boss, Enemy) -- true

e.__class                    -- 所属类（如 Enemy）
e.__name                     -- 类名（'Enemy'）
```

## 其他 API

```lua
Class.new('Empty')           -- 无构造函数的类
Class.extend('Dog', Animal)  -- 等价于 Class.new('Dog', Animal)
Class.exists('Enemy')        -- 是否已定义
Class.get('Enemy')           -- 按名字取类表
```

## 注意事项

- 类定义后会写入全局（`_G`），请避免使用引擎已有 API 的名字（如 `import`、`set`、`get` 等）。
- `Class` 是保留名，不能作为类名。
- 重复定义同名类会报错。
- 每个脚本的 Lua 状态相互独立；**跨脚本共享类**请把类写进库文件，再用 `import('xxx.lua')` 导入。
- 在 `new` 里给实例赋值直接写 `self.xxx = ...` 即可，方法内调用其他方法用 `self:method()`。

## 测试示例

`mods/My-Mod/menus/class_demo.lua` 是一份完整的可运行示例（在界面文字上展示 class、继承、类型判断的测试结果）。临时把它重命名为 `menus/main_menu.lua` 即可在主菜单看到效果。
