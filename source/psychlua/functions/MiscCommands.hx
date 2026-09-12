package psychlua.functions;

import psychlua.FunkinLua;

//
// MiscCommands —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class MiscCommands
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "mouseClicked", function(button:String) {
			var click:Bool = FlxG.mouse.justPressed;
			switch(button){
				case 'middle':
					click = FlxG.mouse.justPressedMiddle;
				case 'right':
					click = FlxG.mouse.justPressedRight;
			}
			return click;
		});

		Lua_helper.add_callback(lua, "mousePressed", function(button:String) {
			var press:Bool = FlxG.mouse.pressed;
			switch(button){
				case 'middle':
					press = FlxG.mouse.pressedMiddle;
				case 'right':
					press = FlxG.mouse.pressedRight;
			}
			return press;
		});

		Lua_helper.add_callback(lua, "mouseReleased", function(button:String) {
			var released:Bool = FlxG.mouse.justReleased;
			switch(button){
				case 'middle':
					released = FlxG.mouse.justReleasedMiddle;
				case 'right':
					released = FlxG.mouse.justReleasedRight;
			}
			return released;
		});

		Lua_helper.add_callback(lua, "runTimer", function(tag:String, time:Float = 1, loops:Int = 1) {
			LuaUtils.cancelTimer(tag);
			game.modchartTimers.set(tag, new FlxTimer().start(time, function(tmr:FlxTimer) {
				if(tmr.finished) {
					game.modchartTimers.remove(tag);
				}
				game.callOnLuas('onTimerCompleted', [tag, tmr.loops, tmr.loopsLeft]);
				//trace('Timer Completed: ' + tag);
			}, loops));
		});

		Lua_helper.add_callback(lua, "cancelTimer", function(tag:String) {
			LuaUtils.cancelTimer(tag);
		});

		Lua_helper.add_callback(lua, "FlxColor", function(color:String) {
			return FlxColor.fromString(color);
		});

		Lua_helper.add_callback(lua, "getColorFromName", function(color:String) {
			return FlxColor.fromString(color);
		});

		Lua_helper.add_callback(lua, "getColorFromString", function(color:String) {
			return FlxColor.fromString(color);
		});

		Lua_helper.add_callback(lua, "getColorFromHex", function(color:String) {
			return FlxColor.fromString('#$color');
		});

		Lua_helper.add_callback(lua, "debugPrint", function(text:Dynamic = '', color:String = 'WHITE') {
			return PlayState.instance.addTextToDebug(text, CoolUtil.colorFromString(color));
		});

		funk.addLocalCallback("close", function() {
			funk.closed = true;
			trace('Closing script ${funk.scriptName}');
			return funk.closed;
		});

		funk.addLocalCallback("import", function(luaFile:String) {
			return funk.importLibrary(luaFile);
		});
	}
}
