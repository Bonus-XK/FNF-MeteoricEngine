package psychlua;

import llua.Lua;
import llua.LuaL;
import llua.State;
import Type.ValueType;
import backend.BaseStage;
import objects.Alphabet;

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
 * 生命周期：注册表是全局的（句柄可跨脚本共享）。清理点有三处：
 * `PlayState.destroy()` 调 `clearRegistry()`；界面脚本接入时 PlayState 侧不清理，
 * 由最后一个 MenuScript 销毁（`releaseMenu()`）且不在 PlayState 时清空——
 * 覆盖「纯菜单会话」与「暂停子状态挂 PlayState」两种情形。
 *
 * 双模式：resolverId = 0 为 PlayState 语义（LuaUtils 路径解析），>0 为注册表里
 * 对应 MenuScript 的句柄 id（findObject / state 字段）。GLUE 按状态烘焙 resolverId；
 * 所有 __hx_* 回调都是状态无关闭包（Lua_helper.callbacks 是跨状态全局表、按名分发，
 * 捕获单个脚本上下文会被后注册的脚本覆盖）。菜单模式下（PlayState.instance == null）
 * 属性/方法/写路径自动走不依赖 PlayState 的通道（walkVar / Reflect）。
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
	/** 已接入对象桥的界面脚本数（用于最后一个销毁时清空注册表）。 */
	static var liveMenus:Int = 0;

	/** 整体释放注册表（PlayState.destroy 调用）。 */
	public static function clearRegistry():Void
	{
		registry = new Map<Int, Dynamic>();
		reverse = new haxe.ds.ObjectMap<Dynamic, Int>();
		enumTypeIds = new Map<Int, Bool>();
		nextId = 0;
	}

	// ===== 核心工具 =====

	/**
	 * 桥内诊断输出：PlayState 里走 luaTrace（游戏内调试框），菜单里走 trace（终端）。
	 * luaTrace 内部解引用 PlayState.instance，菜单（instance == null）下会 NPE。
	 */
	static function bridgeTrace(msg:String):Void
	{
		if (PlayState.instance != null)
			FunkinLua.luaTrace(msg, false, false, FlxColor.RED);
		else
			trace(msg);
	}

	/**
	 * 取子字段。菜单模式（PlayState.instance == null）下不碰 LuaUtils——
	 * 其内部会解引用 PlayState.instance（variables 表检查），菜单里必 NPE。
	 */
	static function walkVar(obj:Dynamic, seg:String, allowMaps:Bool):Dynamic
	{
		if (PlayState.instance == null)
		{
			if (isMapObject(obj)) return Reflect.callMethod(obj, Reflect.field(obj, 'get'), [seg]);
			if (Std.isOfType(obj, Array))
			{
				var i:Null<Int> = Std.parseInt(seg);
				if (i == null) return null;
				var arr:Array<Dynamic> = cast obj;
				if (i < 0 || i >= arr.length) return null;
				return arr[i];
			}
			return Reflect.getProperty(obj, seg);
		}
		return LuaUtils.getVarInArray(obj, seg, allowMaps);
	}

	/** 把 Haxe 对象包成句柄标记（匿名对象，经 Convert 复制进 Lua 后由胶水补挂 metatable）。 */
	static function wrapNew(obj:Dynamic):Dynamic
	{
		if (obj == null) return null;
		// hxcpp 的 ObjectMap 对枚举值做哈希实测 SEGV（2026-10-28）——枚举值跳过反向索引
		var canHash:Bool = true;
		try
		{
			switch (Type.typeof(obj))
			{
				case ValueType.TEnum(_): canHash = false;
				default:
			}
		}
		catch (e:Dynamic) {}
		if (canHash && reverse.exists(obj))
			return {__hxid: reverse.get(obj)};
		nextId++;
		registry.set(nextId, obj);
		if (canHash)
		{
			try reverse.set(obj, nextId) catch (e:Dynamic) {}
		}
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
		// ⚠【架构性限制】Lua 函数不能桥接成 Haxe 回调：桥接后的回调会在任意 Haxe 时机
		// 被调用（tween/timer 完成点），绕开 FunkinLua.luaCallDepth 的嵌套 pcall 防护，
		// 实测触发 LuaJIT 栈堆损坏 → SEGV（2026-10-28 真机复现）。传函数参数的地方
		// 一律置 null（行为 = 无回调）并给出诊断，带回调的逻辑请用 runHaxeCodeObj。
		if (Std.isOfType(v, LuaCallback))
		{
			bridgeTrace('[ObjectBridge] 不支持把 Lua 函数传给 Haxe 回调参数（LuaJIT 嵌套 pcall 风险），已置为空回调');
			return null;
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
				else if (Std.isOfType(e, LuaCallback))
				{
					bridgeTrace('[ObjectBridge] 不支持把 Lua 函数传给 Haxe 回调参数，已置为空回调');
					out.push(null);
				}
				else out.push(e);
			}
			return out;
		}
		// 匿名对象（如 tween 的 options 表）：函数字段置 null，其余保留
		if (Type.typeof(v) == ValueType.TObject && !isHandleAnon(v))
		{
			var fields:Array<String> = null;
			try fields = Reflect.fields(v) catch (e:Dynamic) {}
			if (fields != null)
			{
				for (f in fields)
				{
					var fv:Dynamic = null;
					try fv = Reflect.field(v, f) catch (e:Dynamic) {}
					if (fv != null && Std.isOfType(fv, LuaCallback))
					{
						bridgeTrace('[ObjectBridge] 不支持把 Lua 函数传给 Haxe 回调参数（字段 $f），已置为空回调');
						try Reflect.setField(v, f, null) catch (e:Dynamic) {}
					}
				}
			}
			return v;
		}
		return v;
	}

	/** 从 {n=..,[1]=..} 打包表（或 Lua 数组）取实参，句柄/函数标记一并还原。 */
	static function argsFromPacked(argsTable:Dynamic):Array<Dynamic>
	{
		var args:Array<Dynamic> = [];
		if (argsTable == null) return args;
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
		return args;
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
		// 枚举对象：绝不反射枚举本体，成员经 Type.createEnum 取值
		if (enumTypeIds.exists(id))
		{
			try return encodeValue(Type.createEnum(cast obj, keyStr, [])) catch (e:Dynamic) return null;
		}
		var val:Dynamic = null;
		try val = walkVar(obj, keyStr, true) catch (e:Dynamic) return null;

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
			// 括号路径走 LuaUtils（内部解引用 PlayState.instance），仅游玩模式可用
			if (PlayState.instance != null && keyStr.indexOf('[') >= 0)
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
			bridgeTrace('[ObjectBridge] objSet(${objTypeOf(obj)}.$keyStr) 失败: $e');
		}
	}

	/** 调方法。packed = {n=个数, [1]=arg1, ...}（胶水打包；数字键经 Convert 变 "1".."n"）。 */
	static function objCall(id:Int, name:Dynamic, packed:Dynamic):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;

		var keyStr:String = Std.string(name);
		var func:Dynamic = null;
		try func = walkVar(obj, keyStr, true) catch (e:Dynamic) {}
		if (func == null || !Reflect.isFunction(func))
		{
			bridgeTrace('[ObjectBridge] objCall: ${objTypeOf(obj)}.$keyStr 不是方法');
			return null;
		}

		var args:Array<Dynamic> = argsFromPacked(packed);
		var result:Dynamic = Reflect.callMethod(obj, func, args);
		return encodeValue(result);
	}

	/**
	 * 构造类实例（类句柄的 `Foo(...)` `__call` 语义入口）。
	 * 仅当注册表对象是类时有效；实例被调用视为脚本错误。
	 */
	static function constructObj(id:Int, packed:Dynamic):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;
		var clsName:String = null;
		try clsName = Type.getClassName(obj) catch (e:Dynamic) {}
		if (clsName == null)
		{
			bridgeTrace('[ObjectBridge] 只有类句柄可以调用构造（${objTypeOf(obj)} 不是类），实例化请用 newObj');
			return null;
		}
		var inst:Dynamic = null;
		try inst = Type.createInstance(obj, argsFromPacked(packed))
		catch (e:Dynamic)
		{
			bridgeTrace('[ObjectBridge] 构造 $clsName 失败: $e');
			return null;
		}
		return encodeValue(inst);
	}

	/**
	 * import 别名 + 类句柄：`importClass('backend.WeekData', 'WeekData')`。
	 * alias 在 Lua 侧由胶水写进 _G（避免跨状态全局表错位）；不传 alias 只返回句柄。
	 */
	static function importClassInternal(path:String):Dynamic
	{
		var cls:Dynamic = null;
		try cls = Type.resolveClass(path) catch (e:Dynamic) {}
		if (cls == null)
		{
			bridgeTrace('[ObjectBridge] importClass: 类不存在: $path');
			return null;
		}
		if (Reflect.isFunction(cls)) return null;
		return encodeValue(cls);
	}

	// hxcpp 的 Type.resolveEnum 依赖 RTTI 注册，部分引擎枚举拿不到（HScript 同限，其靠
	// preset 注入常量值绕过）。这里显式引用保活常用引擎枚举；String 背书的 abstract enum
	// （如 FlxTextAlign）值就是字符串，脚本直接传字符串即可，无需枚举对象。
	// 惰性构建：静态初始化阶段引用其他模块的枚举值可能拿到 null（hxcpp boot 顺序）
	static var enumKeep:Map<String, Dynamic> = null;

	static function resolveEnumLoose(path:String):Dynamic
	{
		var e:Dynamic = null;
		try e = Type.resolveEnum(path) catch (err:Dynamic) {}
		if (e != null) return e;
		if (enumKeep == null)
			enumKeep = [
				// 键 = hxcpp 运行时类型路径（模块子类型的源码速记在注册表里不存在）；
				// 值 = 枚举本体（import backend.BaseStage 已把同文件声明的 Countdown 导入）
				'backend.Countdown' => Countdown,
				'objects.Alignment' => Alignment,
			];
		return enumKeep.get(path);
	}

	/** 取枚举对象为句柄（成员走属性读取；abstract enum 走 enumKeep 或直接传原始值）。 */
	static function getEnumH(path:String):Dynamic
	{
		var e:Dynamic = resolveEnumLoose(path);
		if (e == null)
		{
			bridgeTrace('[ObjectBridge] getEnum: 枚举不存在: $path');
			return null;
		}
		var h:Dynamic = encodeValue(e);
		if (h != null) enumTypeIds[Reflect.field(h, '__hxid')] = true;
		return h;
	}

	/** 构造枚举值：makeEnum('enum.Full.Path', 'ConstructorName', {arg1, arg2})。 */
	static function makeEnumH(path:String, name:String, argsTable:Dynamic):Dynamic
	{
		var e:Dynamic = resolveEnumLoose(path);
		if (e == null)
		{
			bridgeTrace('[ObjectBridge] makeEnum: 枚举不存在: $path');
			return null;
		}
		var val:Dynamic = null;
		try val = Type.createEnum(e, name, argsFromPacked(argsTable))
		catch (err:Dynamic)
		{
			bridgeTrace('[ObjectBridge] makeEnum: $path.$name 构造失败: $err');
			return null;
		}
		return encodeValue(val);
	}

	/**
	 * 按路径解析对象。resolverId = 0：PlayState 语义（脚本对象 / 实例字段 / 完整类路径）；
	 * resolverId > 0：注册表里对应的 MenuScript（scriptObjects / state 字段 / 完整类路径）。
	 * 两者的根段解析之后都走同一套 walkVar 逐段下钻，失败再退回 resolveClass。
	 */
	static function getObj(path:String, allowMaps:Bool, resolverId:Int):Dynamic
	{
		if (path == null || path.length == 0) return null;
		var obj:Dynamic = null;
		var split:Array<String> = path.split('.');

		var root:Dynamic = null;
		if (resolverId > 0)
		{
			var script:MenuScript = registry.get(resolverId);
			if (script != null)
			{
				try
				{
					if (split[0] == 'state' || split[0] == 'this' || split[0] == 'instance')
						root = script.state;
					else
						root = script.findObject(split[0]);
				}
				catch (e:Dynamic) {}
			}
		}
		else
		{
			try root = LuaUtils.getObjectDirectly(split[0], true, allowMaps) catch (e:Dynamic) {}
		}

		if (root != null)
		{
			obj = root;
			for (i in 1...split.length)
			{
				try obj = walkVar(obj, split[i], allowMaps) catch (e:Dynamic) { obj = null; break; }
				if (obj == null) break;
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
			bridgeTrace('[ObjectBridge] newObj: 类不存在: $className');
			return null;
		}
		var args:Array<Dynamic> = argsFromPacked(argsTable);
		var inst:Dynamic = null;
		try inst = Type.createInstance(cls, args)
		catch (e:Dynamic)
		{
			bridgeTrace('[ObjectBridge] newObj: 构造 $className 失败: ' + Std.string(e));
			return null;
		}
		return encodeValue(inst);
	}

	static function objType(id:Int):Dynamic
	{
		var obj:Dynamic = registry.get(id);
		if (obj == null) return null;
		if (enumTypeIds.exists(id)) return 'enum';
		return objTypeOf(obj);
	}

	static function objTypeOf(obj:Dynamic):String
	{
		if (obj == null) return 'null';
		// 枚举值：先于 getClass 处理（hxcpp 上对 enum 值走 getClass 不可靠）
		try
		{
			switch (Type.typeof(obj))
			{
				case ValueType.TEnum(_):
					var en:Dynamic = Type.getEnum(obj);
					if (en != null) return Type.getEnumName(en) + '(enum value)';
				default:
			}
		}
		catch (e:Dynamic) {}
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
		// Map：Reflect.fields 不可靠，走 keys() 迭代器（配合 objGet 即可遍历 Map）
		try
		{
			if (isMapObject(obj))
			{
				var out:Array<Dynamic> = [];
				var it:Dynamic = Reflect.callMethod(obj, Reflect.field(obj, 'keys'), []);
				// hxcpp 不允许 for-in Dynamic，手动推进迭代器
				while (true)
				{
					var hasNext:Bool = false;
					try hasNext = it.hasNext() catch (e:Dynamic) break;
					if (!hasNext) break;
					var k:Dynamic = null;
					try k = it.next() catch (e:Dynamic) break;
					out.push(k);
				}
				return out;
			}
		}
		catch (e:Dynamic) {}
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

	// 枚举对象句柄的 id 标记（hxcpp 上对 enum 对象做 getClass/Reflect 实测 SEGV，
	// 见 2026-10-28 崩溃；所有枚举操作必须走 Type.createEnum，绝不直接反射枚举对象）
	static var enumTypeIds:Map<Int, Bool> = new Map<Int, Bool>();

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

	/**
	 * 游玩脚本（PlayState / FunkinLua）接入：完整模式。
	 * 所有 __hx_* 回调都是状态无关闭包（不捕获 funk/script）——Lua_helper.callbacks
	 * 是跨状态全局表、按名分发，捕获单个脚本上下文会导致后注册者覆盖先注册者；
	 * getObj 的脚本上下文经 GLUE 烘焙的 resolverId（0 = PlayState 语义）显式传入。
	 */
	public static function implement(funk:FunkinLua):Void
	{
		var lua:State = funk.lua;
		if (lua == null) return;
		registerCore(lua, 0);

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

		doGlue(lua, 0);
	}

	/**
	 * 界面脚本（menus/<界面名>.lua / MenuScript）接入：菜单模式。
	 * 根对象解析走 script.findObject / script.state / 完整类路径；菜单里没有
	 * HScript 模块，runHaxeCodeObj 返回 nil（胶水里有 nil 保护）。
	 * @return 注册是否成功（false = lua 状态不可用，调用方不应调 releaseMenu）
	 */
	public static function implementMenu(script:MenuScript):Bool
	{
		var lua:State = script.lua;
		if (lua == null) return false;

		// MenuScript 实例本身注册进注册表：GLUE 里的 resolverId 就是它的句柄 id
		var rid:Dynamic = wrapNew(script);
		var resolverId:Int = rid != null ? Reflect.field(rid, '__hxid') : 0;
		registerCore(lua, resolverId);
		liveMenus++;
		doGlue(lua, resolverId);
		return true;
	}

	/**
	 * 界面脚本销毁时调用。最后一个菜单脚本销毁且不在 PlayState 时清空注册表
	 * （PlayState 场景由 PlayState.destroy 的 clearRegistry 负责）。
	 */
	public static function releaseMenu():Void
	{
		liveMenus--;
		if (liveMenus <= 0 && PlayState.instance == null) clearRegistry();
	}

	/** 共用注册：10 个状态无关的 __hx_* 内部回调（字符串字面量名 → 自动进契约基线）。 */
	static function registerCore(lua:State, resolverId:Int):Void
	{
		Lua_helper.add_callback(lua, '__hx_getObj', function(rid:Dynamic, path:String, allowMaps:Dynamic) {
			var useRid:Int = rid != null ? Std.int(rid) : resolverId;
			return getObj(path, allowMaps != null && allowMaps != false, useRid);
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
		// 类句柄的 Foo(...) 构造入口（GLUE __call 元方法）
		Lua_helper.add_callback(lua, '__hx_obj_construct', function(id:Dynamic, packed:Dynamic) {
			return constructObj(Std.int(id), packed);
		});
		// import 别名 + 类句柄（alias 由胶水写 _G，避免跨状态全局表错位）
		Lua_helper.add_callback(lua, '__hx_importClass', function(path:String) {
			return importClassInternal(path);
		});
		// 枚举：getEnum 拿句柄读成员，makeEnum 构造枚举值（abstract enum 亦可）
		Lua_helper.add_callback(lua, '__hx_getEnum', function(path:String) {
			return getEnumH(path);
		});
		Lua_helper.add_callback(lua, '__hx_makeEnum', function(path:String, name:Dynamic, argsTable:Dynamic) {
			return makeEnumH(path, name != null ? Std.string(name) : null, argsTable);
		});
		// import 路由（状态无关）：类/枚举 → 句柄标记；'pkg.*' → 包标记 {__hxpkg=path}；
		// 解析失败返回 nil，GLUE 层会回落到旧的 Lua 库文件导入（per-script 状态在旧闭包里）
		Lua_helper.add_callback(lua, '__hx_import_route', function(path:String) {
			if (path == null || path.length == 0) return null;
			if (StringTools.endsWith(path, '.*'))
			{
				var pkg:String = path.substr(0, path.length - 2);
				if (pkg.length == 0) return null;
				return {__hxpkg: pkg};
			}
			var cls:Dynamic = null;
			try cls = Type.resolveClass(path) catch (e:Dynamic) {}
			if (cls != null && !Reflect.isFunction(cls)) return encodeValue(cls);
			var en:Dynamic = null;
			try en = Type.resolveEnum(path) catch (e:Dynamic) {}
			if (en != null) return encodeValue(en);
			return null;
		});
	}

	/** 注入当前状态的 GLUE（resolverId 烘焙进 getObj 调用）。 */
	static function doGlue(lua:State, resolverId:Int):Void
	{
		var status:Int = LuaL.dostring(lua, StringTools.replace(GLUE, '__HX_RESOLVER__', Std.string(resolverId)));
		if (status != 0)
		{
			var err:String = null;
			try err = Lua.tostring(lua, -1) catch (e:Dynamic) {}
			Lua.pop(lua, 1);
			trace('[ObjectBridge] Lua 胶水加载失败($status): ' + Std.string(err));
		}
	}

	// LuaJIT 5.1 胶水模板。注意：
	// - __HX_RESOLVER__ 由 doGlue 按状态替换：0 = PlayState 语义，>0 = 注册表里 MenuScript 的句柄 id；
	// - __hxobj_mt 的 __index 对方法标记返回绑定闭包（方法调用 obj:method(...) 的入口）；
	// - __HX_WRAP 给从 Haxe 回来的句柄标记补挂 metatable；
	// - 打包实参用 {n=个数, [1]=..}，nil 中间参数会缺号，Haxe 侧按 null 处理；
	// - runHaxeCodeObj 仅游玩脚本注册（菜单里 __hx_runHaxeCodeObj 为 nil，直接返回 nil）。
	// GLUE 内的 import：先捕获宿主已注册的旧 import 闭包（库文件导入，
	// per-script 状态在其闭包里），再定义 HScript 同款语义的 import。
	static final GLUE:String = "
local __HX_IMPORT_LIB = import

-- HScript-style import (semantics mirror hscript):
--   import('pkg.Class')      -> _G.Class = class handle (auto short name)
--   import('pkg.Class','A')  -> _G.A = class handle
--   import('pkg.*')          -> lazy package table (bind on access)
--   import('mylib.lua')      -> legacy Lua library import
function import(path, alias)
	local r = __hx_import_route(path)
	if type(r) == 'table' then
		if r.__hxid ~= nil then
			r = __HX_WRAP(r)
			local short = alias
			if short == nil or short == '' then
				local p = string.reverse(path)
				local cut = string.find(p, '.', 1, true)
				short = cut ~= nil and string.reverse(string.sub(p, 1, cut - 1)) or path
			end
			if short ~= nil and short ~= '' and short ~= 'Class' then _G[short] = r end
			return r
		end
		if r.__hxpkg ~= nil then
			local pkgPath = r.__hxpkg
			local pkg = setmetatable({}, {__index = function(t, k)
				local h = import(pkgPath .. '.' .. k)
				rawset(t, k, h)
				return h
			end})
			if alias ~= nil and alias ~= '' then _G[alias] = pkg end
			return pkg
		end
	end
	return __HX_IMPORT_LIB(path)
end

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
	end,
	__call = function(h, ...)
		local n = select('#', ...)
		local packed = {n = n}
		for i = 1, n do packed[i] = select(i, ...) end
		return __HX_WRAP(__hx_obj_construct(h.__hxid, packed))
	end
}

function __HX_WRAP(v)
	if type(v) == 'table' and v.__hxid ~= nil then
		return setmetatable(v, __HXOBJ_MT)
	end
	return v
end

function getObj(path) return __HX_WRAP(__hx_getObj(__HX_RESOLVER__, path)) end

-- import alias: importClass('backend.WeekData', 'WeekData') binds _G.WeekData = class handle
function importClass(path, alias)
	local h = __HX_WRAP(__hx_importClass(path))
	if h ~= nil and alias ~= nil and type(alias) == 'string' and alias ~= '' then
		_G[alias] = h
	end
	return h
end

function getEnum(path) return __HX_WRAP(__hx_getEnum(path)) end

function makeEnum(path, name, args) return __HX_WRAP(__hx_makeEnum(path, name, args)) end

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
	if __hx_runHaxeCodeObj == nil then return nil end
	return __HX_WRAP(__hx_runHaxeCodeObj(code, vars, func, args))
end
";
}
#end
