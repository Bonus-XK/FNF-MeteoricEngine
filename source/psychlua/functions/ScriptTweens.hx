package psychlua.functions;

import psychlua.FunkinLua;
import psychlua.LuaUtils.LuaTweenOptions;

//
// ScriptTweens —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class ScriptTweens
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "startTween", function(tag:String, vars:String, values:Any = null, duration:Float, options:Any = null) {
			var penisExam:Dynamic = LuaUtils.tweenPrepare(tag, vars);
			var props:Array<String> = values != null ? Reflect.fields(values) : [];
			var canTween:Bool = penisExam != null && Reflect.isObject(penisExam) && props.length > 0;
			if(canTween) {
				for(prop in props) {
					if(Reflect.getProperty(penisExam, prop) == null) {
						canTween = false;
						break;
					}
				}
			}
			if(canTween) {
				if(values != null) {
					var myOptions:LuaTweenOptions = LuaUtils.getLuaTween(options);
					game.modchartTweens.set(tag, FlxTween.tween(penisExam, values, duration, {
						type: myOptions.type,
						ease: myOptions.ease,
						startDelay: myOptions.startDelay,
						loopDelay: myOptions.loopDelay,

						onUpdate: function(twn:FlxTween) {
							if(myOptions.onUpdate != null) game.callOnLuas(myOptions.onUpdate, [tag, vars]);
						},
						onStart: function(twn:FlxTween) {
							if(myOptions.onStart != null) game.callOnLuas(myOptions.onStart, [tag, vars]);
						},
						onComplete: function(twn:FlxTween) {
							if(myOptions.onComplete != null) game.callOnLuas(myOptions.onComplete, [tag, vars]);
							if(twn.type == FlxTweenType.ONESHOT || twn.type == FlxTweenType.BACKWARD) game.modchartTweens.remove(tag);
						}
					}));
				} else {
					FunkinLua.luaTrace('startTween: No values on 2nd argument!', false, false, FlxColor.RED);
				}
			} else {
				FunkinLua.luaTrace('startTween: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});

		Lua_helper.add_callback(lua, "doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String) {
			psychlua.functions.ScriptTweens.oldTweenFunction(tag, vars, {x: value}, duration, ease, 'doTweenX');
		});

		Lua_helper.add_callback(lua, "doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String) {
			psychlua.functions.ScriptTweens.oldTweenFunction(tag, vars, {y: value}, duration, ease, 'doTweenY');
		});

		Lua_helper.add_callback(lua, "doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String) {
			psychlua.functions.ScriptTweens.oldTweenFunction(tag, vars, {angle: value}, duration, ease, 'doTweenAngle');
		});

		Lua_helper.add_callback(lua, "doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String) {
			psychlua.functions.ScriptTweens.oldTweenFunction(tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha');
		});

		Lua_helper.add_callback(lua, "doTweenZoom", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String) {
			psychlua.functions.ScriptTweens.oldTweenFunction(tag, vars, {zoom: value}, duration, ease, 'doTweenZoom');
		});

		Lua_helper.add_callback(lua, "doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ease:String) {
			var penisExam:Dynamic = LuaUtils.tweenPrepare(tag, vars);
			if(penisExam != null && Reflect.isObject(penisExam) && Reflect.getProperty(penisExam, 'color') != null && Reflect.getProperty(penisExam, 'alpha') != null) {
				var curColor:FlxColor = penisExam.color;
				curColor.alphaFloat = penisExam.alpha;
				game.modchartTweens.set(tag, FlxTween.color(penisExam, duration, curColor, CoolUtil.colorFromString(targetColor), {ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween) {
						game.modchartTweens.remove(tag);
						game.callOnLuas('onTweenCompleted', [tag, vars]);
					}
				}));
			} else {
				FunkinLua.luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});

		Lua_helper.add_callback(lua, "cancelTween", function(tag:String) {
			LuaUtils.cancelTween(tag);
		});
	}

	// 由 FunkinLua.hx 搬入（阶段 A）：doTween* 系列的旧版实现。
	// 使用全限定名调用，避免与模块名同名导致的解析歧义。
	public static function oldTweenFunction(tag:String, vars:String, tweenValue:Any, duration:Float, ease:String, funcName:String)
	{
		#if LUA_ALLOWED
		var target:Dynamic = LuaUtils.tweenPrepare(tag, vars);
		var props:Array<String> = Reflect.fields(tweenValue);
		var canTween:Bool = target != null && Reflect.isObject(target) && props.length > 0;
		if(canTween) {
			for(prop in props) {
				if(Reflect.getProperty(target, prop) == null) {
					canTween = false;
					break;
				}
			}
		}
		if(canTween) {
			PlayState.instance.modchartTweens.set(tag, FlxTween.tween(target, tweenValue, duration, {ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween) {
					PlayState.instance.modchartTweens.remove(tag);
					PlayState.instance.callOnLuas('onTweenCompleted', [tag, vars]);
				}
			}));
		} else {
			FunkinLua.luaTrace('$funcName: Couldnt find object or property: $vars', false, false, FlxColor.RED);
		}
		#end
	}
}
