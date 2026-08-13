package psychlua;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
#end

/**
 * Lua 脚本 class 系统（支持继承）。
 * 在游玩脚本与界面脚本中均可使用：
 *
 *   Class.new('Enemy')                     定义类
 *   Class.new('Boss', Enemy)               定义类并继承 Enemy
 *
 *   function Enemy:new(x, y) ... end       构造函数（可选，new 关键字）
 *   function Enemy:update(elapsed) ... end 方法
 *
 *   local e = Enemy.new(10, 20)            创建实例
 *   local e2 = Enemy(10, 20)               等价写法
 *
 *   function Boss:new(x, y)
 *       Enemy.new(self, x, y)              子类中调用父类构造函数
 *   end
 *   function Boss:update(elapsed)
 *       Enemy.update(self, elapsed)        子类中调用父类方法
 *   end
 *
 *   Enemy.isInstanceOf(e)                  类型判断
 *   Class.isInstanceOf(e, Enemy)
 *   Class.isSubclassOf(Boss, Enemy)
 *   e.__class / e.__name                   获取实例所属类 / 类名
 *
 * 注意：每个脚本的 Lua 状态相互独立，跨脚本共享类请把类写进库文件，
 * 再用 import('xxx.lua') 导入。
 */
class LuaClass
{
	#if LUA_ALLOWED
	public static function register(lua:State):Void
	{
		var status:Int = LuaL.dostring(lua, classCode);
		if(status != Lua.LUA_OK)
		{
			var err:String = Lua.tostring(lua, -1);
			Lua.pop(lua, 1);
			if(err == null || err.length < 1) err = 'Unknown Error';
			trace('LuaClass: failed to initialize class system: ' + err);
		}
	}
	#end

	public static var classCode(default, null) =
			'-- Meteoric Engine Lua Class System\n'
		+ 		'local classRegistry = {}\n'
		+ 		'local instanceMetas = {}\n'
		+ 		'\n'
		+ 		'local function classLookup(cls, key)\n'
		+ 		'    local c = cls\n'
		+ 		'    while c ~= nil do\n'
		+ 		'        local v = rawget(c, key)\n'
		+ 		'        if v ~= nil then return v end\n'
		+ 		'        c = rawget(c, \'__parent\')\n'
		+ 		'    end\n'
		+ 		'    return nil\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'local function newInstance(cls, ...)\n'
		+ 		'    local instMeta = instanceMetas[cls]\n'
		+ 		'    if instMeta == nil then\n'
		+ 		'        error(\'Class: "\' .. tostring(cls) .. \'" is not a class\', 2)\n'
		+ 		'    end\n'
		+ 		'    local obj = setmetatable({}, instMeta)\n'
		+ 		'    local ctor = classLookup(cls, \'__constructor\')\n'
		+ 		'    if ctor ~= nil then\n'
		+ 		'        ctor(obj, ...)\n'
		+ 		'    end\n'
		+ 		'    return obj\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'local Class = {}\n'
		+ 		'\n'
		+ 		'function Class.new(name, parent)\n'
		+ 		'    if type(name) ~= \'string\' or name == \'\' then\n'
		+ 		'        error(\'Class.new: name must be a non-empty string\', 2)\n'
		+ 		'    end\n'
		+ 		'    if name == \'Class\' then\n'
		+ 		'        error(\'Class.new: "Class" is a reserved name\', 2)\n'
		+ 		'    end\n'
		+ 		'    if classRegistry[name] ~= nil then\n'
		+ 		'        error(\'Class.new: class "\' .. name .. \'" already exists\', 2)\n'
		+ 		'    end\n'
		+ 		'    if parent ~= nil and instanceMetas[parent] == nil then\n'
		+ 		'        error(\'Class.new: parent must be a class or nil\', 2)\n'
		+ 		'    end\n'
		+ 		'\n'
		+ 		'    local cls = { __name = name, __parent = parent }\n'
		+ 		'\n'
		+ 		'    -- new 包装：第一个参数是本类实例时视为调用构造函数（子类里写\n'
		+ 		'    -- Parent.new(self, ...) 即可初始化父类部分），否则创建新实例。\n'
		+ 		'    -- 包装器不存进类表，用户写 function Enemy:new(...) 时\n'
		+ 		'    -- 会触发 __newindex 存到 __constructor，不会覆盖包装器。\n'
		+ 		'    local newWrapper = function(first, ...)\n'
		+ 		'        if Class.isInstanceOf(first, cls) then\n'
		+ 		'            local ctor = classLookup(cls, \'__constructor\')\n'
		+ 		'            if ctor ~= nil then\n'
		+ 		'                ctor(first, ...)\n'
		+ 		'            end\n'
		+ 		'            return first\n'
		+ 		'        end\n'
		+ 		'        return newInstance(cls, first, ...)\n'
		+ 		'    end\n'
		+ 		'\n'
		+ 		'    -- Enemy.isInstanceOf(instance) 与 instance:isInstanceOf(Enemy) 均可用\n'
		+ 		'    cls.isInstanceOf = function(...)\n'
		+ 		'        if select(\'#\', ...) >= 2 then\n'
		+ 		'            local obj, target = ...\n'
		+ 		'            return Class.isInstanceOf(obj, target)\n'
		+ 		'        end\n'
		+ 		'        return Class.isInstanceOf(select(1, ...), cls)\n'
		+ 		'    end\n'
		+ 		'\n'
		+ 		'    setmetatable(cls, {\n'
		+ 		'        __index = function(_, key)\n'
		+ 		'            if key == \'new\' then return newWrapper end\n'
		+ 		'            if parent ~= nil then return classLookup(parent, key) end\n'
		+ 		'            return nil\n'
		+ 		'        end,\n'
		+ 		'        __newindex = function(t, key, value)\n'
		+ 		'            if key == \'new\' then\n'
		+ 		'                rawset(t, \'__constructor\', value)\n'
		+ 		'            else\n'
		+ 		'                rawset(t, key, value)\n'
		+ 		'            end\n'
		+ 		'        end,\n'
		+ 		'        __call = function(_, ...) return newInstance(cls, ...) end,\n'
		+ 		'        __tostring = function() return \'class \' .. name end\n'
		+ 		'    })\n'
		+ 		'\n'
		+ 		'    instanceMetas[cls] = {\n'
		+ 		'        __class = cls,\n'
		+ 		'        __index = function(_, key)\n'
		+ 		'            if key == \'new\' then return nil end\n'
		+ 		'            if key == \'__class\' then return cls end\n'
		+ 		'            return classLookup(cls, key)\n'
		+ 		'        end,\n'
		+ 		'        __tostring = function() return name .. \' instance\' end\n'
		+ 		'    }\n'
		+ 		'\n'
		+ 		'    classRegistry[name] = cls\n'
		+ 		'    _G[name] = cls\n'
		+ 		'    return cls\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'function Class.extend(name, parent)\n'
		+ 		'    return Class.new(name, parent)\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'function Class.get(name)\n'
		+ 		'    return classRegistry[name]\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'function Class.exists(name)\n'
		+ 		'    return classRegistry[name] ~= nil\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'function Class.isInstanceOf(obj, cls)\n'
		+ 		'    if type(obj) ~= \'table\' or type(cls) ~= \'table\' then return false end\n'
		+ 		'    local mt = getmetatable(obj)\n'
		+ 		'    if mt == nil then return false end\n'
		+ 		'    local c = rawget(mt, \'__class\')\n'
		+ 		'    while c ~= nil do\n'
		+ 		'        if c == cls then return true end\n'
		+ 		'        c = rawget(c, \'__parent\')\n'
		+ 		'    end\n'
		+ 		'    return false\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'function Class.isSubclassOf(sub, base)\n'
		+ 		'    if type(sub) ~= \'table\' or type(base) ~= \'table\' then return false end\n'
		+ 		'    local c = rawget(sub, \'__parent\')\n'
		+ 		'    while c ~= nil do\n'
		+ 		'        if c == base then return true end\n'
		+ 		'        c = rawget(c, \'__parent\')\n'
		+ 		'    end\n'
		+ 		'    return false\n'
		+ 		'end\n'
		+ 		'\n'
		+ 		'_G.Class = Class';
}
