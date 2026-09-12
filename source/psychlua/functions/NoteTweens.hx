package psychlua.functions;

import psychlua.FunkinLua;
import objects.StrumNote;

//
// NoteTweens —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class NoteTweens
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "noteTweenX", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String) {
			LuaUtils.cancelTween(tag);
			if(note < 0) note = 0;
			var testicle:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];

			if(testicle != null) {
				game.modchartTweens.set(tag, FlxTween.tween(testicle, {x: value}, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			}
		});

		Lua_helper.add_callback(lua, "noteTweenY", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String) {
			LuaUtils.cancelTween(tag);
			if(note < 0) note = 0;
			var testicle:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];

			if(testicle != null) {
				game.modchartTweens.set(tag, FlxTween.tween(testicle, {y: value}, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			}
		});

		Lua_helper.add_callback(lua, "noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String) {
			LuaUtils.cancelTween(tag);
			if(note < 0) note = 0;
			var testicle:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];

			if(testicle != null) {
				game.modchartTweens.set(tag, FlxTween.tween(testicle, {angle: value}, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			}
		});

		Lua_helper.add_callback(lua, "noteTweenDirection", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String) {
			LuaUtils.cancelTween(tag);
			if(note < 0) note = 0;
			var testicle:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];

			if(testicle != null) {
				game.modchartTweens.set(tag, FlxTween.tween(testicle, {direction: value}, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			}
		});

		Lua_helper.add_callback(lua, "noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String) {
			LuaUtils.cancelTween(tag);
			if(note < 0) note = 0;
			var testicle:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];

			if(testicle != null) {
				game.modchartTweens.set(tag, FlxTween.tween(testicle, {angle: value}, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			}
		});

		Lua_helper.add_callback(lua, "noteTweenAlpha", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String) {
			LuaUtils.cancelTween(tag);
			if(note < 0) note = 0;
			var testicle:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];

			if(testicle != null) {
				game.modchartTweens.set(tag, FlxTween.tween(testicle, {alpha: value}, duration, {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			}
		});
	}
}
