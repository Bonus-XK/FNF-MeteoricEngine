package psychlua.functions;

import psychlua.FunkinLua;

//
// ScriptCommands —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class ScriptCommands
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "getRunningScripts", function() {
			var runningScripts:Array<String> = [];
			for (script in game.luaArray)
				runningScripts.push(script.scriptName);

			return runningScripts;
		});

		funk.addLocalCallback("setOnScripts", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			if(exclusions == null) exclusions = [];
			if(ignoreSelf && !exclusions.contains(funk.scriptName)) exclusions.push(funk.scriptName);
			game.setOnScripts(varName, arg, exclusions);
		});

		funk.addLocalCallback("setOnHScript", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			if(exclusions == null) exclusions = [];
			if(ignoreSelf && !exclusions.contains(funk.scriptName)) exclusions.push(funk.scriptName);
			game.setOnHScript(varName, arg, exclusions);
		});

		funk.addLocalCallback("setOnLuas", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null) {
			if(exclusions == null) exclusions = [];
			if(ignoreSelf && !exclusions.contains(funk.scriptName)) exclusions.push(funk.scriptName);
			game.setOnLuas(varName, arg, exclusions);
		});

		funk.addLocalCallback("callOnScripts", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops=false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			if(excludeScripts == null) excludeScripts = [];
			if(ignoreSelf && !excludeScripts.contains(funk.scriptName)) excludeScripts.push(funk.scriptName);
			game.callOnScripts(funcName, args, ignoreStops, excludeScripts, excludeValues);
			return true;
		});

		funk.addLocalCallback("callOnLuas", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops=false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			if(excludeScripts == null) excludeScripts = [];
			if(ignoreSelf && !excludeScripts.contains(funk.scriptName)) excludeScripts.push(funk.scriptName);
			game.callOnLuas(funcName, args, ignoreStops, excludeScripts, excludeValues);
			return true;
		});

		funk.addLocalCallback("callOnHScript", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops=false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null) {
			if(excludeScripts == null) excludeScripts = [];
			if(ignoreSelf && !excludeScripts.contains(funk.scriptName)) excludeScripts.push(funk.scriptName);
			game.callOnHScript(funcName, args, ignoreStops, excludeScripts, excludeValues);
			return true;
		});

		Lua_helper.add_callback(lua, "callScript", function(luaFile:String, funcName:String, ?args:Array<Dynamic> = null) {
			if(args == null){
				args = [];
			}

			var foundScript:String = funk.findScript(luaFile);
			if(foundScript != null)
				for (luaInstance in game.luaArray)
					if(luaInstance.scriptName == foundScript)
					{
						luaInstance.call(funcName, args);
						return;
					}
		});

		Lua_helper.add_callback(lua, "getGlobalFromScript", function(luaFile:String, global:String) {
			 // returns the global from a script
						var foundScript:String = funk.findScript(luaFile);
						if(foundScript != null)
							for (luaInstance in game.luaArray)
								if(luaInstance.scriptName == foundScript)
								{
									Lua.getglobal(luaInstance.lua, global);
									if(Lua.isnumber(luaInstance.lua,-1))
										Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -1));
									else if(Lua.isstring(luaInstance.lua,-1))
										Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -1));
									else if(Lua.isboolean(luaInstance.lua,-1))
										Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -1));
									else
										Lua.pushnil(lua);

									// TODO: table

									Lua.pop(luaInstance.lua,1); // remove the global

									return;
								}
		});

		Lua_helper.add_callback(lua, "setGlobalFromScript", function(luaFile:String, global:String, val:Dynamic) {
			 // returns the global from a script
						var foundScript:String = funk.findScript(luaFile);
						if(foundScript != null)
							for (luaInstance in game.luaArray)
								if(luaInstance.scriptName == foundScript)
									luaInstance.set(global, val);
		});

		Lua_helper.add_callback(lua, "isRunning", function(luaFile:String) {
			var foundScript:String = funk.findScript(luaFile);
			if(foundScript != null)
				for (luaInstance in game.luaArray)
					if(luaInstance.scriptName == foundScript)
						return true;
			return false;
		});

		Lua_helper.add_callback(lua, "setVar", function(varName:String, value:Dynamic) {
			PlayState.instance.variables.set(varName, value);
			return value;
		});

		Lua_helper.add_callback(lua, "getVar", function(varName:String) {
			return PlayState.instance.variables.get(varName);
		});

		Lua_helper.add_callback(lua, "addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false) {
			 //would be dope asf.
						var foundScript:String = funk.findScript(luaFile);
						if(foundScript != null)
						{
							if(!ignoreAlreadyRunning)
								for (luaInstance in game.luaArray)
									if(luaInstance.scriptName == foundScript)
									{
										FunkinLua.luaTrace('addLuaScript: The script "' + foundScript + '" is already running!');
										return;
									}

							new FunkinLua(foundScript);
							return;
						}
						FunkinLua.luaTrace("addLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
		});

		Lua_helper.add_callback(lua, "addHScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false) {
			#if HSCRIPT_ALLOWED
			var foundScript:String = funk.findScript(luaFile, '.hx');
			if(foundScript != null)
			{
				if(!ignoreAlreadyRunning)
					for (script in game.hscriptArray)
						if(script.origin == foundScript)
						{
							FunkinLua.luaTrace('addHScript: The script "' + foundScript + '" is already running!');
							return;
						}

				PlayState.instance.initHScript(foundScript);
				return;
			}
			FunkinLua.luaTrace("addHScript: Script doesn't exist!", false, false, FlxColor.RED);
			#else
			FunkinLua.luaTrace("addHScript: HScript is not supported on this platform!", false, false, FlxColor.RED);
			#end
		});

		Lua_helper.add_callback(lua, "removeLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false) {
			var foundScript:String = funk.findScript(luaFile);
			if(foundScript != null)
			{
				if(!ignoreAlreadyRunning)
					for (luaInstance in game.luaArray)
						if(luaInstance.scriptName == foundScript)
						{
							luaInstance.stop();
							trace('Closing script ' + luaInstance.scriptName);
							return true;
						}
			}
			FunkinLua.luaTrace('removeLuaScript: Script $luaFile isn\'t running!', false, false, FlxColor.RED);
			return false;
		});

		Lua_helper.add_callback(lua, "loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0) {
			var split:Array<String> = variable.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			var animated = gridX != 0 || gridY != 0;

			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null && image != null && image.length > 0)
			{
				spr.loadGraphic(Paths.image(image), animated, gridX, gridY);
			}
		});

		Lua_helper.add_callback(lua, "loadFrames", function(variable:String, image:String, spriteType:String = "sparrow") {
			var split:Array<String> = variable.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null && image != null && image.length > 0)
			{
				LuaUtils.loadFrames(spr, image, spriteType);
			}
		});
	}
}
