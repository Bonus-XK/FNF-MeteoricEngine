package psychlua;

import llua.Lua;
import llua.LuaL;
import llua.State;
import Type.ValueType;

/**
 * Lua 对象桥（Object Bridge）—— 让 Lua 脚本持有 Haxe 对象的一等引用。
 *
 * 背景：`llua/Convert.hx` 无法把 Haxe 类实例（FlxSprite / Character / FlxCamera 等）
 * 传入 Lua（一律变 nil），所以传统 Lua 只能靠字符串路径间接操作
 * （`setProperty('boyfriend.x', 100)`），能力远弱于源码。
 *
 * 本模块给 Lua 提供「对象句柄」：句柄是一个携带 `__hxid` 的 Lua 表，
 * 挂上 metatable 后，读写属性 / 调用方法直接落在 Haxe 对象上：
 *
 * ```lua
 * local bf = getObj('boyfriend')      -- 按路径解析（等价 getProperty 的路径语义）
 * bf.x = bf.x + 10                    -- 写属性（__newindex → Reflect.setProperty）
 * bf:playAnim('hey', true)            -- 调方法（__index 返回绑定闭包 → Reflect.callMethod）
 * local s = newObj('flixel.FlxSprite', {0, 0})  -- 构造任意类
 * s:screenCenter()
 * local g = getObj('flixel.FlxG')     -- 任意类的静态成员
 * g.sound:play(Paths.music('freakyMenu'))
 * ```
 *
 * 实现要点（都是出于栈安全，见 AGENTS.md / Convert.hx 的教训）：
 * - metatable 用 LuaL.dostring 注入的 Lua 胶水搭建，元方法回调全部走
 *   `Lua_helper.add_callback`（参数经 Convert 转换，返回值经 Convert 压栈），
 *   **不触碰任何裸指针 / pushcclosure API**；
 * - 句柄表 = 匿名对象 `{__hxid=N}` 经 Convert.anonToLua 复制进 Lua 后补挂 metatable，
 *   对象本体存在 Haxe 侧注册表 `registry`（Int → Dynamic）；
 * - 传回 Haxe 的参数若带 `__hxid`（句柄表被 Convert 复制成匿名对象），自动还原为注册表里的对象；
 * - 返回给 Lua 的 Haxe 对象一律重新包装为句柄；原始类型 / Array / String 直接传值
 *   （Array 是快照：嵌套对象不会保持引用，见 docs/LUA-OBJECT-BRIDGE.md）。
 *
 * 生命周期：注册表是全局的（句柄可跨脚本共享），`PlayState.destroy()` 时
 * 调 `clearRegistry()` 整体释放；脚本也可用 `releaseObj(h)` 单独释放。
 *
 * 重入警告：`objCall` / 方法调用会执行任意 Haxe 方法；若该方法内部触发
 * callOnScripts（如 startSong），与既有 `callMethod`/`callMethodFromClass` 有相同的
 * LuaJIT 嵌套 pcall 风险（FunkinLua.luaCallDepth 只保护 FunkinLua.call 路径）。
 * 不要在 onUpdate 等高频回调里调用会触发脚本回调的方法。
 */
#if LUA_ALLOWED
class ObjectBridge
{
	// ===== 注册表 =====
	/** id → Haxe 对象。句柄表里的 __hxid 就是对应的 key。 */
	public static var registry:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	static var nextId:Int = 0;
	/** 对象 → id 的反向索引（同一对象重复包装时复用句柄；key 失败则退化为每次新 id）。 */
	static var reverse:haxe.ds.ObjectMap<Dynamic, Int> = new haxe.ds.ObjectMap<Dynamic, Int>();

	/** 整体释放注册表（PlayState.destroy 调用）。 */
	public static function clearRegistry():Void
	{
		registry = new Map<Int, Dynamic>();
		reverse = new haxe.ds.ObjectMap<Dynamic, Int>();
		nextId = 0;
	}

	// ===== 核心工具 =====

	/** 把 Haxe 对象包成句柄标记（匿名对象，经 Convert 复制进 Lua 后由胶水补挂 metatable）。 */
	static function wrapNew(obj:Dynamic):Dynamic
	{
		if (obj == null) return null;
		if (reverse.exists(obj))
			return {__hxid: reverse.get(obj)};
		nextId++;
		registry.set(nextId, obj);
		try reverse.set(obj, nextId) catch (e:Dynamic) {}
		return {__hxid: nextId};
	}

	/** 判断匿名对象是不是句柄标记（有 __hxid 且不是方法标记）。 */
	static function isHandleAnon(v:Dynamic):Bool
	{
		if (v == null) return false;
		var t = Type.typeof(v);
		if (t != ValueType.TObject) return false;
		if (!Reflect.hasField(v, '__hxid')) return false;
		return !Reflect.hasField(v, '__hxcall');
	}

	/** 还原参数：句柄标记 → 注册表对象；数组元素做一层同样处理；其余原样。 */
	static function unwrapArg(v:Dynamic):Dynamic
	{
		if (v == null) return null;
		if (isHandleAnon(v))
		{
			var obj:Dynamic = registry.get(Reflect.field(v, '__hxid'));
			return obj != null ? obj : v;
		}
		if (Std.isOfType(v, Array))
		{
			var arr:Array<Dynamic> = cast v;
			var out:Array<Dynamic> = [];
			for (e in arr)
			{
				if (isHandleAnon(e))
				{
					var obj:Dynamic = registry.get(Reflect.field(e, '__hxid'));
					out.push(obj != null ? obj : e);
				}
				else out.push(e);
			}
			return out;
		}
		return v;
	}

	/** 把 Haxe 值编码成可传回 Lua 的形式：原始类型/Array/String 直接传，对象包句柄。 */
	static function encodeValue(val:Dynamic):Dynamic
	{
		if (val == null) return null;
		switch (Type.typeof(val))
		{
			case ValueType.TNull:
				return null;
			case ValueType.TInt | ValueType.TFloat | ValueType.TBool:
				return val;
			case ValueType.TClass(c):
				if (c == String) return val;
				// 一切对象（含 Array、Map、Flx 类、engine 类、类对象）都是句柄：
				// 数组/Map 若走 Convert 快照，嵌套对象会整体丢失（变 nil），句柄才能保持引用
				return wrapNew(val);
			case ValueType.TObject:
				return wrapNew(val);
			case ValueType.TEnum(_):
				return wrapNew(val);
			default:
				return null; // 裸函数等无法有意义地传回
		}
	}

	// ===== 内部实现（由 __hx_* 回调转发） =====

	/** 读属性。key 支持字符串（含 'members[0]' 括号语法）与数字（数组 0 基索引）。 */
	static function objIndex(id:Int, key:Dynamic):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;

		var kt = Type.typeof(key);
		if (kt == ValueType.TInt || kt == ValueType.TFloat)
		{
			var idx:Int = Std.int(key);
			if (Std.isOfType(obj, Array))
			{
				var arr:Array<Dynamic> = cast obj;
				if (idx < 0 || idx >= arr.length) return null;
				return encodeValue(arr[idx]);
			}
			return null; // 数字键只对数组有意义（容器请走 .members）
		}

		var keyStr:String = Std.string(key);
		var val:Dynamic = null;
		try val = LuaUtils.getVarInArray(obj, keyStr, true) catch (e:Dynamic) return null;

		if (val == null) return null;
		if (Reflect.isFunction(val))
			return {__hxid: id, __hxmethod: keyStr, __hxcall: true};
		return encodeValue(val);
	}

	/** 写属性。value 若是句柄标记自动还原为对象。 */
	static function objNewIndex(id:Int, key:Dynamic, value:Dynamic):Void
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return;

		var keyStr:String = Std.string(key);
		var v:Dynamic = unwrapArg(value);
		try
		{
			if (keyStr.indexOf('[') >= 0)
				LuaUtils.setVarInArray(obj, keyStr, v);
			else if (Std.isOfType(obj, Array))
			{
				var arr:Array<Dynamic> = cast obj;
				var idx:Null<Int> = Std.parseInt(keyStr);
				if (idx != null && idx >= 0 && idx <= arr.length) arr[idx] = v;
			}
			else if (isMapObject(obj))
				Reflect.callMethod(obj, Reflect.field(obj, 'set'), [keyStr, v]);
			else
				Reflect.setProperty(obj, keyStr, v);
		}
		catch (e:Dynamic)
		{
			FunkinLua.luaTrace('[ObjectBridge] objSet(${objTypeOf(obj)}.$keyStr) 失败: ' + Std.string(e), false, false, FlxColor.RED);
		}
	}

	/** 调方法。packed = {n=个数, [1]=arg1, ...}（胶水打包；数字键经 Convert 变 "1".."n"）。 */
	static function objCall(id:Int, name:Dynamic, packed:Dynamic):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;

		var keyStr:String = Std.string(name);
		var func:Dynamic = null;
		try func = LuaUtils.getVarInArray(obj, keyStr, true) catch (e:Dynamic) {}
		if (func == null || !Reflect.isFunction(func))
		{
			FunkinLua.luaTrace('[ObjectBridge] objCall: ${objTypeOf(obj)}.$keyStr 不是方法', false, false, FlxColor.RED);
			return null;
		}

		var args:Array<Dynamic> = [];
		var cnt:Int = 0;
		if (packed != null)
		{
			var n:Dynamic = null;
			try n = Reflect.field(packed, 'n') catch (e:Dynamic) {}
			if (n != null) cnt = Std.int(n);
			for (i in 0...cnt)
			{
				var a:Dynamic = null;
				try a = Reflect.field(packed, Std.string(i + 1)) catch (e:Dynamic) {}
				args.push(unwrapArg(a));
			}
		}

		var result:Dynamic = Reflect.callMethod(obj, func, args);
		return encodeValue(result);
	}

	/** 按路径解析对象：PlayState 脚本对象 / 实例字段 → 失败则按完整类路径 resolveClass。 */
	static function getObj(path:String, allowMaps:Bool):Dynamic
	{
		if (path == null || path.length == 0) return null;
		var obj:Dynamic = null;
		var split:Array<String> = path.split('.');
		if (split.length == 1)
		{
			try obj = LuaUtils.getObjectDirectly(path, true, allowMaps) catch (e:Dynamic) {}
		}
		else
		{
			var root:Dynamic = null;
			try root = LuaUtils.getObjectDirectly(split[0], true, allowMaps) catch (e:Dynamic) {}
			if (root != null)
			{
				obj = root;
				for (i in 1...split.length)
				{
					try obj = LuaUtils.getVarInArray(obj, split[i], allowMaps) catch (e:Dynamic) { obj = null; break; }
					if (obj == null) break;
				}
			}
		}
		if (obj == null)
		{
			try obj = Type.resolveClass(path) catch (e:Dynamic) {}
		}
		if (obj == null || Reflect.isFunction(obj)) return null;
		return encodeValue(obj);
	}

	/** 构造任意类实例。argsTable：Lua 数组或 {n=..,[1]=..} 打包表（胶水两种都兼容）。 */
	static function newObj(className:String, argsTable:Dynamic):Dynamic
	{
		var cls:Dynamic = null;
		try cls = Type.resolveClass(className) catch (e:Dynamic) {}
		if (cls == null)
		{
			FunkinLua.luaTrace('[ObjectBridge] newObj: 类不存在: ' + className, false, false, FlxColor.RED);
			return null;
		}
		var args:Array<Dynamic> = [];
		if (argsTable != null)
		{
			if (Std.isOfType(argsTable, Array))
			{
				for (a in cast(argsTable, Array<Dynamic>)) args.push(unwrapArg(a));
			}
			else
			{
				var n:Dynamic = null;
				try n = Reflect.field(argsTable, 'n') catch (e:Dynamic) {}
				var cnt:Int = n != null ? Std.int(n) : 0;
				for (i in 0...cnt)
				{
					var a:Dynamic = null;
					try a = Reflect.field(argsTable, Std.string(i + 1)) catch (e:Dynamic) {}
					args.push(unwrapArg(a));
				}
			}
		}
		var inst:Dynamic = null;
		try inst = Type.createInstance(cls, args)
		catch (e:Dynamic)
		{
			FunkinLua.luaTrace('[ObjectBridge] newObj: 构造 $className 失败: ' + Std.string(e), false, false, FlxColor.RED);
			return null;
		}
		return encodeValue(inst);
	}

	static function objType(id:Int):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;
		return objTypeOf(obj);
	}

	static function objTypeOf(obj:Dynamic):String
	{
		if (obj == null) return 'null';
		// 实例
		var cls:Class<Dynamic> = null;
		try cls = Type.getClass(obj) catch (e:Dynamic) {}
		if (cls != null)
		{
			var cn:String = null;
			try cn = Type.getClassName(cls) catch (e:Dynamic) {}
			if (cn != null) return cn;
		}
		// 类对象 / 枚举
		try
		{
			var cn:String = Type.getClassName(obj);
			if (cn != null) return cn + '(class)';
		}
		catch (e:Dynamic) {}
		try
		{
			var en:String = Type.getEnumName(obj);
			if (en != null) return en + '(enum)';
		}
		catch (e:Dynamic) {}
		return Std.string(Type.typeof(obj));
	}

	static function objKeys(id:Int):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;
		if (Std.isOfType(obj, Array)) return obj;
		try
		{
			return Reflect.fields(obj);
		}
		catch (e:Dynamic) {}
		return null;
	}

	static function objLen(id:Int):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;
		if (Std.isOfType(obj, Array)) return cast(obj, Array<Dynamic>).length;
		// FlxTypedGroup 等容器：取 .members.length
		try
		{
			var m:Dynamic = Reflect.getProperty(obj, 'members');
			if (m != null && Std.isOfType(m, Array)) return cast(m, Array<Dynamic>).length;
		}
		catch (e:Dynamic) {}
		return null;
	}

	static function releaseObj(id:Int):Bool
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return false;
		registry.remove(id);
		try
		{
			if (reverse.exists(obj) && reverse.get(obj) == id) reverse.remove(obj);
		}
		catch (e:Dynamic) {}
		return true;
	}

	static function isMapObject(obj:Dynamic):Bool
	{
		try
		{
			return obj.exists != null && obj.set != null && obj.get != null;
		}
		catch (e:Dynamic) {}
		return false;
	}

	// ===== 注册入口 =====

	public static function implement(funk:FunkinLua):Void
	{
		var lua:State = funk.lua;
		if (lua == null) return;

		// 内部回调（字符串字面量名 → 自动进契约基线 tools/contract/script-surface.tsv）
		Lua_helper.add_callback(lua, '__hx_getObj', function(path:String, allowMaps:Dynamic) {
			return getObj(path, allowMaps != null && allowMaps != false);
		});
		Lua_helper.add_callback(lua, '__hx_newObj', function(className:String, argsTable:Dynamic) {
			return newObj(className, argsTable);
		});
		Lua_helper.add_callback(lua, '__hx_obj_index', function(id:Dynamic, key:Dynamic) {
			return objIndex(Std.int(id), key);
		});
		Lua_helper.add_callback(lua, '__hx_obj_newindex', function(id:Dynamic, key:Dynamic, value:Dynamic) {
			objNewIndex(Std.int(id), key, value);
			return null;
		});
		Lua_helper.add_callback(lua, '__hx_obj_call', function(id:Dynamic, name:Dynamic, packed:Dynamic) {
			return objCall(Std.int(id), name, packed);
		});
		Lua_helper.add_callback(lua, '__hx_obj_type', function(id:Dynamic) {
			return objType(Std.int(id));
		});
		Lua_helper.add_callback(lua, '__hx_obj_keys', function(id:Dynamic) {
			return objKeys(Std.int(id));
		});
		Lua_helper.add_callback(lua, '__hx_obj_len', function(id:Dynamic) {
			return objLen(Std.int(id));
		});
		Lua_helper.add_callback(lua, '__hx_obj_release', function(id:Dynamic) {
			return releaseObj(Std.int(id));
		});
		Lua_helper.add_callback(lua, '__hx_obj_count', function() {
			var n:Int = 0;
			for (_ in registry.keys()) n++;
			return n;
		});

		// 与 HScript 层互操作：返回值不像 runHaxeCode 那样把对象压成 nil，而是包装成句柄。
		// 代码以「顶层表达式」语义求值：interp.execute 的返回值 = 最后一个表达式的值
		// （比 runHaxeCode 更强：runHaxeCode 的 returnValue 兜底是死代码，只有 funcToRun 才有返回值）
		#if (HSCRIPT_ALLOWED && SScript >= "3.0.0")
		Lua_helper.add_callback(lua, '__hx_runHaxeCodeObj', function(codeToRun:String, varsToBring:Dynamic, funcToRun:Dynamic, funcArgs:Dynamic) {
			HScript.initHaxeModule(funk);
			if (varsToBring != null)
			{
				for (key in Reflect.fields(varsToBring))
					funk.hscript.set(key, Reflect.field(varsToBring, key));
			}
			var val:Dynamic = null;
			try
			{
				var expr = funk.hscript.parser.parseString(codeToRun, funk.hscript.origin);
				val = funk.hscript.interp.execute(expr);
			}
			catch (err:Dynamic)
			{
				FunkinLua.luaTrace(funk.hscript.origin + ":runHaxeCodeObj - " + Std.string(err), false, false, FlxColor.RED);
				return null;
			}
			if (funcToRun != null)
			{
				var retVal:Dynamic = funk.hscript.executeCode(funcToRun, cast funcArgs);
				if (retVal == null || !retVal.succeeded)
				{
					var e:Dynamic = retVal != null ? retVal.exceptions[0] : null;
					if (e != null)
						FunkinLua.luaTrace(funk.hscript.origin + ":runHaxeCodeObj - " + Std.string(e), false, false, FlxColor.RED);
					return null;
				}
				val = retVal.returnValue;
			}
			if (val == null) return null;
			return encodeValue(val);
		});
		#end

		// Lua 胶水：metatable + 公开函数名（getObj / newObj / objGet / objSet / objCall /
		// objEq / isObj / objType / objKeys / objLen / releaseObj / objCount / runHaxeCodeObj）
		var status:Int = LuaL.dostring(lua, GLUE);
		if (status != 0)
		{
			var err:String = null;
			try err = Lua.tostring(lua, -1) catch (e:Dynamic) {}
			Lua.pop(lua, 1);
			trace('[ObjectBridge] Lua 胶水加载失败($status): ' + Std.string(err));
		}
	}

	// LuaJIT 5.1 胶水。注意：
	// - __hxobj_mt 的 __index 对方法标记返回绑定闭包（方法调用 obj:method(...) 的入口）；
	// - __HX_WRAP 给从 Haxe 回来的句柄标记补挂 metatable；
	// - 打包实参用 {n=个数, [1]=..}，nil 中间参数会缺号，Haxe 侧按 null 处理。
	static final GLUE:String = "
__HXOBJ_MT = {
	__index = function(t, k)
		local r = __hx_obj_index(t.__hxid, k)
		if type(r) == 'table' then
			if r.__hxcall ~= nil then
				local mid = r.__hxid
				local mname = r.__hxmethod
				return function(s, ...)
					local n = select('#', ...)
					local packed = {n = n}
					for i = 1, n do packed[i] = select(i, ...) end
					return __HX_WRAP(__hx_obj_call(mid, mname, packed))
				end
			elseif r.__hxid ~= nil then
				return setmetatable(r, __HXOBJ_MT)
			end
		end
		return r
	end,
	__newindex = function(t, k, v)
		__hx_obj_newindex(t.__hxid, k, v)
	end
}

function __HX_WRAP(v)
	if type(v) == 'table' and v.__hxid ~= nil then
		return setmetatable(v, __HXOBJ_MT)
	end
	return v
end

function getObj(path) return __HX_WRAP(__hx_getObj(path)) end

function newObj(className, args) return __HX_WRAP(__hx_newObj(className, args)) end

function objGet(h, k)
	if h == nil or h.__hxid == nil then return nil end
	return __HX_WRAP(__hx_obj_index(h.__hxid, k))
end

function objSet(h, k, v)
	if h == nil or h.__hxid == nil then return false end
	__hx_obj_newindex(h.__hxid, k, v)
	return true
end

function objCall(h, name, ...)
	if h == nil or h.__hxid == nil then return nil end
	local n = select('#', ...)
	local packed = {n = n}
	for i = 1, n do packed[i] = select(i, ...) end
	return __HX_WRAP(__hx_obj_call(h.__hxid, name, packed))
end

function objEq(a, b)
	if type(a) ~= 'table' or type(b) ~= 'table' then return false end
	if a.__hxid == nil or b.__hxid == nil then return false end
	return a.__hxid == b.__hxid
end

function isObj(v) return type(v) == 'table' and v.__hxid ~= nil end

function objType(h)
	if h == nil or h.__hxid == nil then return nil end
	return __hx_obj_type(h.__hxid)
end

function objKeys(h)
	if h == nil or h.__hxid == nil then return nil end
	return __hx_obj_keys(h.__hxid)
end

function objLen(h)
	if h == nil or h.__hxid == nil then return nil end
	return __hx_obj_len(h.__hxid)
end

function releaseObj(h)
	if h == nil or h.__hxid == nil then return false end
	return __hx_obj_release(h.__hxid)
end

function objCount() return __hx_obj_count() end

function runHaxeCodeObj(code, vars, func, args)
	return __HX_WRAP(__hx_runHaxeCodeObj(code, vars, func, args))
end
";
}
#end
