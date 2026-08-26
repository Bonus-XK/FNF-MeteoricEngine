package llua;


import llua.State;
import llua.Lua;
import llua.LuaL;
import llua.Macro.*;
import haxe.DynamicAccess;

/**
 * linc_luajit `Convert` 的项目内 shadow（根源修复，版本对齐 linc_luajit/git）。
 *
 * 唯一改动：`toLua()` 的 default 分支由「失败且不压栈（return false）」改为
 * 「压一个 nil 并返回 true」。原实现下，任何不支持的 Haxe 类型（如 Character、
 * FlxSprite、FlxCamera 等 TClass 实例）被转 Lua 时“什么都不压”，但所有调用方
 * （FunkinLua.set / call 实参 / arrayToLua / mapToLua / anonToLua / setGlobal /
 * callback_handler）都假定“要么压了值、要么压了 nil”，于是反复发生：
 *
 *   - FunkinLua.set()：toLua 失败 → setglobal 仍弹 1 格 → Lua 栈下溢（top < base）
 *   - call() 实参：toLua 失败 → pcall 按 args.length 消费 → 读到垃圾/越界
 *   - arrayToLua/mapToLua/anonToLua：内部 toLua 失败 → settable(-3) 连表一起弹掉
 *
 * 栈指针一旦越界/错位，LuaJIT 的 GC/分配器在错位栈上运行 → lj_alloc_realloc 堆损坏
 * → SIGSEGV（blissful-erect 命中瞬间 / PlayState.destroy 的 Lua.close 均属此类）。
 * 压 nil 后所有路径栈永远平衡；不支持的 Haxe 对象在 Lua 侧表现为 nil（与“无法表示”
 * 语义一致），不再产生越界写入。此改动同时覆盖 set()/call()/表转换/回调返回四条路径。
 */
class Convert {

	/**
	 * To Lua
	 */
	public static var enableUnsupportedTraces = false;
	public static var allowFunctions = true;
	public static var functionReferences:Map<Dynamic,Array<Dynamic>> = new Map<Dynamic,Array<Dynamic>>();
	// It's recommended to purge this every now and then. Note that this'll effect *every* lua state
	@:keep inline public static function cleanFunctionRefs(){
		functionReferences = new Map<Dynamic,Array<Dynamic>>();
	}
	public static function toLua(l:State, val:Any):Bool {

		switch (Type.typeof(val)) {
			case Type.ValueType.TNull:
				Lua.pushnil(l);
			case Type.ValueType.TBool:
				Lua.pushboolean(l, val);
			case Type.ValueType.TInt:
				Lua.pushinteger(l, cast(val, Int));
			// case Type.ValueType.TFunction:
				// if(!allowFunctions) return false;
				// return false;
				// var funcIndex = -1;
				// if(functionReferences[l] == null){
				// 	functionReferences[l] = [val];
				// 	funcIndex = 0;
				// }else{
				// 	for(i => v in functionReferences[l]){
				// 		if(v == val){
				// 			funcIndex = i;
				// 			break;
				// 		}
				// 	}
				// 	if(funcIndex == -1){
				// 		funcIndex = functionReferences[l].length;
				// 		functionReferences[l].push(val);
				// 	}
				// }

				// Lua.pushcfunction(l,
				//
				// {
				// 	return callback_handler(val,l);
				// }),1);
			case Type.ValueType.TFloat:
				Lua.pushnumber(l, val);
			case Type.ValueType.TClass(String):
				Lua.pushstring(l, cast(val, String));
			case Type.ValueType.TClass(Array):
				arrayToLua(l, val);
			case Type.ValueType.TClass(haxe.ds.StringMap) | Type.ValueType.TClass(haxe.ds.ObjectMap):
				mapToLua(l, val);
			case Type.ValueType.TObject:
				anonToLua(l, val); // {}
			default:
				// [Meteoric 修复] 不支持的类型 → 压 nil（绝不“不压栈而失败”），保持 Lua 栈永远平衡
				if(enableUnsupportedTraces) trace('Haxe value of $val of type ${Type.typeof(val)} not supported, pushing nil!' );
				Lua.pushnil(l);
		}
		return true;
	}

	public static function callback_handler(cbf:Dynamic,l:State,?object:Dynamic/*,cbf:Dynamic,lsp:Dynamic*/):Int {
		try{
			final l:State = l;
			final nparams:Int = Lua.gettop(l);

			if(cbf == null) return 0;

			/* return the number of results */
			final ret:Dynamic = Reflect.callMethod(object,cbf,[for (i in 0...nparams) fromLua(l, i + 1)]);
			if(ret != null){
				toLua(l, ret);
				return 1;
			}
		}catch(e){
			trace('${e}');
			throw(e);
		}
		return 0;

	}

	@:keep public static inline function arrayToLua(l:State, arr:Array<Any>) {
		Lua.createtable(l, arr.length, 0);
		for (i => v in arr) {
			Lua.pushnumber(l, i + 1);
			toLua(l, v);
			Lua.settable(l, -3);
		}

	}

	@:keep static inline function mapToLua(l:State, res:Map<String,Dynamic>) {
		Lua.createtable(l, 0, 0);
		for (index => val in res){
			Lua.pushstring(l, Std.string(index));
			toLua(l, val);
			Lua.settable(l, -3);
		}

	}

	@:keep static inline function anonToLua(l:State, res:Any) {
		Lua.createtable(l, 0, 0);
		for (n in Reflect.fields(res)){
			Lua.pushstring(l, n);
			toLua(l, Reflect.field(res, n));
			Lua.settable(l, -3);
		}
	}

	@:keep public static inline function setGlobal(l:State, index:String, value:Dynamic) {
		// Lua.getglobal(l, Lua.LUA_GLOBALSINDEX);
		// toLua(l, index);

		toLua(l, value);
		Lua.setfield(l, Lua.LUA_GLOBALSINDEX, index);
		// Lua.settable(l, -3);
		// Lua.pop(l,0);
	}
	/**
	 * From Lua
	 */
	public static function fromLua(l:State, v:Int):Any {

		final luaType = Lua.type(l, v);
		return switch(luaType) {
			case Lua.LUA_TNIL:
				null;
			case Lua.LUA_TBOOLEAN:
				Lua.toboolean(l, v);
			case Lua.LUA_TNUMBER:
				Lua.tonumber(l, v);
			case Lua.LUA_TSTRING:
				Lua.tostring(l, v);
			case Lua.LUA_TTABLE:
				toHaxeObj(l, v);
			case Lua.LUA_TFUNCTION: // From https://github.com/DragShot/linc_luajit/
				new LuaCallback(l, LuaL.ref(l, Lua.LUA_REGISTRYINDEX));
			// 	trace("function\n");
			// case Lua.LUA_TUSERDATA:
			// 	ret = LuaL.ref(l, Lua.LUA_REGISTRYINDEX);
			// 	trace("userdata\n");
			// case Lua.LUA_TLIGHTUSERDATA:
			// 	ret = LuaL.ref(l, Lua.LUA_REGISTRYINDEX);
			// 	trace("lightuserdata\n");
			// case Lua.LUA_TTHREAD:
			// 	ret = null;
			// 	trace("thread\n");
			default:
				if(enableUnsupportedTraces) trace('Return value $v of type $luaType not supported');
				null;
		}

	}

	public static function toHaxeObj(l, i:Int):Any {
		var hasItems = false;
		var array = true;

		loopTable(l, i,{
			hasItems = true;
			if(Lua.type(l, -2) != Lua.LUA_TNUMBER){
				array = false;
			}
			final index = Lua.tonumber(l, -2);
			if(index < 0 || Std.int(index) != index) {
				array = false;
			}
		});
		if(!hasItems) return {}

		if(array) {
			final v:Array<Dynamic> = [];
			loopTable(l, i, {
				v[Std.int(Lua.tonumber(l, -2)) - 1] = fromLua(l, -1);
			});
			return cast v;
		}
		final v:DynamicAccess<Any> = {};
		loopTable(l, i, {
			switch Lua.type(l, -2) {
				case t if(t == Lua.LUA_TSTRING): v.set(Lua.tostring(l, -2), fromLua(l, -1));
				case t if(t == Lua.LUA_TNUMBER):v.set(Std.string(Lua.tonumber(l, -2)), fromLua(l, -1));
			}
		});
		return v;

	}
	/**
		Calls a lua function at `func` with `args`. If multipleReturns is true, return an array of results from the function, else return the first result

		If func is nil, the function at the top of the stack will be run
		If the lua function errors, a llua.LuaException will be thrown
	**/
	public static function callLuaFunction(l, ?func:String,?args:Array<Dynamic> = null,?multipleReturns:Bool=false):Dynamic {
		if(func != null) Lua.getglobal(l, func);
		if(args != null) {
			for(arg in args) Convert.toLua(l,arg);
		}
		LuaException.ifErrorThrow(l,Lua.pcall(l, args == null ? 0 : args.length, multipleReturns ? Lua.LUA_MULTRET : 1,0));

		if(!multipleReturns) return fromLua(l,fromLua(l,-1));
		final returnArray = [];
		for(i in -(Lua.gettop(l)-1)...0){
			returnArray.push(fromLua(l,i));
		}
		return returnArray;

	}
	/**
		Calls a lua function at `func` with `args`.

		If func is nil, the function at the top of the stack will be run
		If the lua function errors, a llua.LuaException will be thrown

		This is SLIGHTLY faster than callLuaFunction since it doesn't do any handling of returns. Useful for things like calling an event that doesn't return anything
	**/
	public static function callLuaFuncNoReturns(l, func:String,?args:Array<Dynamic> = null):Void {
		Lua.getglobal(l, func);
		if(args != null) for(arg in args) Convert.toLua(l,arg);

		LuaException.ifErrorThrow(l,Lua.pcall(l,args == null ? 0 : args.length, 0,0));
	}
}

// Anon_obj from hxcpp
@:include('hxcpp.h')
@:native('hx::Anon')
extern class Anon {

	@:native('hx::Anon_obj::Create')
	public static function create() : Anon;

	@:native('hx::Anon_obj::Add')
	public function add(k:String, v:Any):Void;

}
