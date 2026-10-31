package scripting.lua;

import Type.ValueType;
import haxe.Constraints;

import substates.GameOverSubstate;

//
// Functions that use a high amount of Reflections, which are somewhat CPU intensive
// These functions are held together by duct tape
//

class ReflectionFunctions
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		Lua_helper.add_callback(lua, "getProperty", function(variable:String, ?allowMaps:Bool = false) {
			var split:Array<String> = variable.split('.');
			if(split.length > 1)
				return LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split, true, true, allowMaps), split[split.length-1], allowMaps);
			return LuaUtils.getVarInArray(LuaUtils.getTargetInstance(), variable, allowMaps);
		});
		Lua_helper.add_callback(lua, "setProperty", function(variable:String, value:Dynamic, allowMaps:Bool = false, ?allowInstances:Bool = false) {
			// Psych 1.0.4：第 4 参 allowInstances 为真时把 instanceArg 占位串还原成对象引用。
			// 返回值保持 Meteoric 原有的 true（1.0.4 返回 value，脚本几乎不接这个返回值）。
			var split:Array<String> = variable.split('.');
			if(split.length > 1) {
				LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split, true, true, allowMaps), split[split.length-1], allowInstances ? parseInstances(value) : value, allowMaps);
				return true;
			}
			LuaUtils.setVarInArray(LuaUtils.getTargetInstance(), variable, allowInstances ? parseInstances(value) : value, allowMaps);
			return true;
		});
		Lua_helper.add_callback(lua, "getPropertyFromClass", function(classVar:String, variable:String, ?allowMaps:Bool = false) {
			var myClass:Dynamic = Type.resolveClass(classVar);
			if(myClass == null)
			{
				FunkinLua.luaTrace('getPropertyFromClass: Class $classVar not found', false, false, FlxColor.RED);
				return null;
			}

			var split:Array<String> = variable.split('.');
			if(split.length > 1) {
				var obj:Dynamic = LuaUtils.getVarInArray(myClass, split[0], allowMaps);
				for (i in 1...split.length-1)
					obj = LuaUtils.getVarInArray(obj, split[i], allowMaps);

				return LuaUtils.getVarInArray(obj, split[split.length-1], allowMaps);
			}
			return LuaUtils.getVarInArray(myClass, variable, allowMaps);
		});
		Lua_helper.add_callback(lua, "setPropertyFromClass", function(classVar:String, variable:String, value:Dynamic, ?allowMaps:Bool = false, ?allowInstances:Bool = false) {
			var myClass:Dynamic = Type.resolveClass(classVar);
			if(myClass == null)
			{
				FunkinLua.luaTrace('getPropertyFromClass: Class $classVar not found', false, false, FlxColor.RED);
				return null;
			}

			var realValue:Dynamic = allowInstances ? parseInstances(value) : value;
			var split:Array<String> = variable.split('.');
			if(split.length > 1) {
				var obj:Dynamic = LuaUtils.getVarInArray(myClass, split[0], allowMaps);
				for (i in 1...split.length-1)
					obj = LuaUtils.getVarInArray(obj, split[i], allowMaps);

				LuaUtils.setVarInArray(obj, split[split.length-1], realValue, allowMaps);
				return value;
			}
			LuaUtils.setVarInArray(myClass, variable, realValue, allowMaps);
			return value;
		});
		Lua_helper.add_callback(lua, "getPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic, ?allowMaps:Bool = false) {
			var split:Array<String> = obj.split('.');
			var realObject:Dynamic = null;
			if(split.length > 1)
				realObject = LuaUtils.getPropertyLoop(split, true, false, allowMaps);
			else
				realObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);

			if(Std.isOfType(realObject, FlxTypedGroup))
			{
				var result:Dynamic = LuaUtils.getGroupStuff(realObject.members[index], variable, allowMaps);
				return result;
			}

			var leArray:Dynamic = realObject[index];
			if(leArray != null) {
				var result:Dynamic = null;
				if(Type.typeof(variable) == ValueType.TInt)
					result = leArray[variable];
				else
					result = LuaUtils.getGroupStuff(leArray, variable, allowMaps);
				return result;
			}
			FunkinLua.luaTrace("getPropertyFromGroup: Object #" + index + " from group: " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return null;
		});
		Lua_helper.add_callback(lua, "setPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic, value:Dynamic, ?allowMaps:Bool = false) {
			var split:Array<String> = obj.split('.');
			var realObject:Dynamic = null;
			if(split.length > 1)
				realObject = LuaUtils.getPropertyLoop(split, true, false, allowMaps);
			else
				realObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);

			if(Std.isOfType(realObject, FlxTypedGroup)) {
				LuaUtils.setGroupStuff(realObject.members[index], variable, value, allowMaps);
				return value;
			}

			var leArray:Dynamic = realObject[index];
			if(leArray != null) {
				if(Type.typeof(variable) == ValueType.TInt) {
					leArray[variable] = value;
					return value;
				}
				LuaUtils.setGroupStuff(leArray, variable, value, allowMaps);
			}
			return value;
		});
		Lua_helper.add_callback(lua, "removeFromGroup", function(obj:String, index:Int, dontDestroy:Bool = false) {
			var groupOrArray:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if(Std.isOfType(groupOrArray, FlxTypedGroup)) {
				var sex = groupOrArray.members[index];
				if(!dontDestroy)
					sex.kill();
				groupOrArray.remove(sex, true);
				if(!dontDestroy)
					sex.destroy();
				return;
			}
			groupOrArray.remove(groupOrArray[index]);
		});
		
		Lua_helper.add_callback(lua, "callMethod", function(funcToRun:String, ?args:Array<Dynamic> = null) {
			return callMethodFromObject(PlayState.instance, funcToRun, args);
			
		});
		Lua_helper.add_callback(lua, "callMethodFromClass", function(className:String, funcToRun:String, ?args:Array<Dynamic> = null) {
			return callMethodFromObject(Type.resolveClass(className), funcToRun, args);
		});

		Lua_helper.add_callback(lua, "createInstance", function(variableToSave:String, className:String, ?args:Array<Dynamic> = null) {
			variableToSave = variableToSave.trim().replace('.', '');
			if(!PlayState.instance.variables.exists(variableToSave))
			{
				if(args == null) args = [];
				var myType:Dynamic = Type.resolveClass(className);
		
				if(myType == null)
				{
					FunkinLua.luaTrace('createInstance: Variable $variableToSave is already being used and cannot be replaced!', false, false, FlxColor.RED);
					return false;
				}

				var obj:Dynamic = Type.createInstance(myType, args);
				if(obj != null)
					PlayState.instance.variables.set(variableToSave, obj);
				else
					FunkinLua.luaTrace('createInstance: Failed to create $variableToSave, arguments are possibly wrong.', false, false, FlxColor.RED);

				return (obj != null);
			}
			else FunkinLua.luaTrace('createInstance: Variable $variableToSave is already being used and cannot be replaced!', false, false, FlxColor.RED);
			return false;
		});
		Lua_helper.add_callback(lua, "addInstance", function(objectName:String, ?inFront:Bool = false) {
			if(PlayState.instance.variables.exists(objectName))
			{
				var obj:Dynamic = PlayState.instance.variables.get(objectName);
				if (inFront)
					LuaUtils.getTargetInstance().add(obj);
				else
				{
					if(!PlayState.instance.isDead)
						PlayState.instance.insert(PlayState.instance.members.indexOf(LuaUtils.getLowestCharacterGroup()), obj);
					else
						GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), obj);
				}
			}
			else FunkinLua.luaTrace('addInstance: Can\'t add what doesn\'t exist~ ($objectName)', false, false, FlxColor.RED);
		});

		// Psych 1.0.4：把对象引用打包成占位串，交给 setProperty(..., true, true) /
		// setPropertyFromClass / callMethodFromClass 等再还原成真正的对象引用。
		Lua_helper.add_callback(lua, "instanceArg", function(instanceName:String, ?className:String = null) {
			var retStr:String = '$instanceStr::$instanceName';
			if(className != null) retStr += '::$className';
			return retStr;
		});
	}

	static function callMethodFromObject(classObj:Dynamic, funcStr:String, args:Array<Dynamic> = null)
	{
		if(args == null) args = [];
		args = cast parseInstances(args); // Psych 1.0.4：instanceArg 占位串还原

		var split:Array<String> = funcStr.split('.');
		var funcToRun:Function = null;
		var obj:Dynamic = classObj;
		//trace('start: $obj');
		if(obj == null)
		{
			return null;
		}

		for (i in 0...split.length)
		{
			obj = LuaUtils.getVarInArray(obj, split[i].trim());
			//trace(obj, split[i]);
		}

		funcToRun = cast obj;
		//trace('end: $obj');
		return funcToRun != null ? Reflect.callMethod(obj, funcToRun, args) : null;
	}

	// ===== Psych 1.0.4 实例占位串（instanceArg）的打包 / 还原 =====
	// 占位串格式：`##PSYCHLUA_STRINGTOOBJ::<变量路径>[::<类名>]`
	// 还原时从 PlayState.instance 的变量表按路径取值；带类名则走 Type.resolveClass。
	static final instanceStr:String = "##PSYCHLUA_STRINGTOOBJ";

	static function parseInstanceArray(arg:Array<Dynamic>):Array<Dynamic> {
		var newArray:Array<Dynamic> = [];
		for (val in arg) newArray.push(parseInstances(val));
		return newArray;
	}

	public static function parseInstances(arg:Dynamic):Dynamic {
		if (arg == null) return null;
		if (Std.isOfType(arg, Array)) return parseInstanceArray(cast arg);
		return parseSingleInstance(arg);
	}

	public static function parseSingleInstance(arg:Dynamic):Dynamic
	{
		// ⚠ 必须先类型判断：hxcpp 下 `cast` 到 String 是静态转换，对非字符串会拿到野指针，
		// 随后访问 .length 直接 SEGV。
		if (!Std.isOfType(arg, String)) return arg;

		var argStr:String = cast arg;
		if(argStr != null && argStr.length > instanceStr.length)
		{
			var index:Int = argStr.indexOf('::');
			if(index > -1)
			{
				argStr = argStr.substring(index+2);
				var lastIndex:Int = argStr.lastIndexOf('::');
				var split:Array<String> = (lastIndex > -1) ? argStr.substring(0, lastIndex).split('.') : argStr.split('.');
				var base:Dynamic = (lastIndex > -1) ? Type.resolveClass(argStr.substring(lastIndex+2)) : PlayState.instance;

				var startIdx:Int = 0;
				if (base == PlayState.instance && split.length > 0)
				{
					// ⚠ 第一段必须走 getObjectDirectly，不能走 getVarInArray：
					// make{Animated,}LuaSprite 把对象存进 game.modchartSprites，而 getVarInArray
					// 只查 PlayState.variables → instanceArg('capsule') 会拿到 null，
					// 再传给 callMethodFromClass 里的原生方法就是 null 解引用 → SIGSEGV。
					//（2026-10-30 Sonic 的 catalogue：capsule.lua 用 mouse.overlaps(instanceArg('capsule'),…)
					//  崩在 lua_pcall，就是这个原因。）
					arg = LuaUtils.getObjectDirectly(split[0]);
					startIdx = 1;
				}
				else arg = base;

				for (j in startIdx...split.length)
					arg = LuaUtils.getVarInArray(arg, split[j].trim());
			}
		}
		return arg;
	}
}