package psychlua.functions;

import psychlua.MenuScript;
import psychlua.FunkinLua;
import psychlua.LuaImport;

import backend.DesignTokens;
import backend.MusicBeatState;
import backend.Paths;
import backend.CoolUtil;

import openfl.utils.Assets;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxTimer;

import states.PlayState;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

//
// MenuCommands —— 由 MenuScript.hx 的 new() 拆分而来（阶段 D）
// 与游玩脚本功能域模块（ScriptCommands 等）使用同一套 implement(宿主) 注册表模式。
// 注册名、注册顺序、回调体逐字保留；仅把宿主成员引用显式限定为 menu.*。
//
class MenuCommands
{
	public static function implement(menu:MenuScript)
	{
		var lua:State = menu.lua;
		menu.addLocalCallback('setText', function(objName:String, text:String) {
			var obj:Dynamic = menu.findObject(objName);
			if(obj == null) { FunkinLua.luaTrace('setText: Object "' + objName + '" not found!'); return false; }
			if(!Std.isOfType(obj, FlxText)) { FunkinLua.luaTrace('setText: Object "' + objName + '" is not a text object!'); return false; }
			obj.text = text;
			return true;
		});
		menu.addLocalCallback('getText', function(objName:String) {
			var obj:Dynamic = menu.findObject(objName);
			if(obj == null || !Std.isOfType(obj, FlxText)) return null;
			return obj.text;
		});
		menu.addLocalCallback('addText', function(name:String, text:String, x:Float, y:Float, ?size:Int = 22, ?color:Int = 0xFFFFFFFF, ?font:String = 'vcr.ttf') {
			if(menu.scriptObjects.exists(name)) { FunkinLua.luaTrace('addText: Object "' + name + '" already exists!'); return false; }
			var txt:FlxText = new FlxText(x, y, 0, text, size);
			txt.setFormat(Paths.font(font), size, color, LEFT, OUTLINE, FlxColor.BLACK);
			txt.borderSize = 2;
			txt.scrollFactor.set();
			menu.scriptObjects.set(name, txt);
			menu.state.add(txt);
			return true;
		});
		menu.addLocalCallback('removeObject', function(name:String) {
			if(menu.scriptObjects.exists(name))
			{
				var obj:FlxSprite = menu.scriptObjects.get(name);
				menu.scriptObjects.remove(name);
				menu.state.remove(obj);
				obj.destroy();
				return true;
			}
			FunkinLua.luaTrace('removeObject: Object "' + name + '" not found!');
			return false;
		});
		menu.addLocalCallback('objectExists', function(name:String) {
			return menu.findObject(name) != null;
		});

		// ---- 对象控制 API ----
		menu.addLocalCallback('setObjectVisible', function(name:String, visible:Bool) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectVisible: Object "' + name + '" not found!'); return false; }
			obj.visible = visible;
			return true;
		});
		menu.addLocalCallback('getObjectVisible', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('getObjectVisible: Object "' + name + '" not found!'); return null; }
			return obj.visible;
		});
		menu.addLocalCallback('setObjectAlpha', function(name:String, alpha:Float) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectAlpha: Object "' + name + '" not found!'); return false; }
			obj.alpha = alpha;
			return true;
		});
		menu.addLocalCallback('getObjectAlpha', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('getObjectAlpha: Object "' + name + '" not found!'); return null; }
			return obj.alpha;
		});
		menu.addLocalCallback('setObjectPosition', function(name:String, x:Float, y:Float) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectPosition: Object "' + name + '" not found!'); return false; }
			obj.x = x;
			obj.y = y;
			return true;
		});
		menu.addLocalCallback('getObjectPosition', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('getObjectPosition: Object "' + name + '" not found!'); return null; }
			return {x: obj.x, y: obj.y};
		});
		menu.addLocalCallback('setObjectScale', function(name:String, x:Float, y:Float) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectScale: Object "' + name + '" not found!'); return false; }
			obj.scale.set(x, y);
			if(Std.isOfType(obj, FlxSprite)) obj.updateHitbox();
			return true;
		});
		menu.addLocalCallback('getObjectScale', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('getObjectScale: Object "' + name + '" not found!'); return null; }
			return {x: obj.scale.x, y: obj.scale.y};
		});
		menu.addLocalCallback('setObjectColor', function(name:String, color:Int) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectColor: Object "' + name + '" not found!'); return false; }
			obj.color = color;
			return true;
		});
		menu.addLocalCallback('getObjectColor', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('getObjectColor: Object "' + name + '" not found!'); return null; }
			return obj.color;
		});
		menu.addLocalCallback('setObjectAngle', function(name:String, angle:Float) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectAngle: Object "' + name + '" not found!'); return false; }
			obj.angle = angle;
			return true;
		});
		menu.addLocalCallback('getObjectAngle', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('getObjectAngle: Object "' + name + '" not found!'); return null; }
			return obj.angle;
		});
		menu.addLocalCallback('setObjectFlip', function(name:String, flipX:Bool, ?flipY:Bool = false) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('setObjectFlip: Object "' + name + '" not found!'); return false; }
			obj.flipX = flipX;
			obj.flipY = flipY;
			return true;
		});
		menu.addLocalCallback('getObjectType', function(name:String) {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) return null;
			return Type.getClassName(Type.getClass(obj));
		});

		// ---- 创建对象 API ----
		menu.addLocalCallback('addSprite', function(name:String, image:String, x:Float, y:Float) {
			if(menu.scriptObjects.exists(name)) { FunkinLua.luaTrace('addSprite: Object "' + name + '" already exists!'); return false; }
			var spr:FlxSprite = new FlxSprite(x, y).loadGraphic(Paths.image(image));
			spr.antialiasing = ClientPrefs.data.antialiasing;
			menu.scriptObjects.set(name, spr);
			menu.state.add(spr);
			return true;
		});
		menu.addLocalCallback('addBox', function(name:String, x:Float, y:Float, w:Float, h:Float, ?color:Int = 0xCC161622, ?radius:Float = 20, ?borderColor:Int = 0x45FFFFFF) {
			if(menu.scriptObjects.exists(name)) { FunkinLua.luaTrace('addBox: Object "' + name + '" already exists!'); return false; }
			var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, color);
			if(borderColor != 0)
				FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: borderColor, thickness: 1.5});
			spr.scrollFactor.set();
			menu.scriptObjects.set(name, spr);
			menu.state.add(spr);
			return true;
		});

		// ---- 动画与计时器 API ----
		menu.addLocalCallback('tweenObject', function(name:String, tweenValue:Dynamic, duration:Float, ?ease:String = 'linear') {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('tweenObject: Object "' + name + '" not found!'); return false; }
			menu.cancelTweenInternal(name);
			var tween:FlxTween = FlxTween.tween(obj, tweenValue, duration, {
				ease: menu.getEaseFunction(ease),
				onComplete: function(twn:FlxTween) menu.scriptTweens.remove(name)
			});
			menu.scriptTweens.set(name, tween);
			return true;
		});
		menu.addLocalCallback('tweenObjectColor', function(name:String, toColor:Int, duration:Float, ?ease:String = 'linear') {
			var obj:Dynamic = menu.findObject(name);
			if(obj == null) { FunkinLua.luaTrace('tweenObjectColor: Object "' + name + '" not found!'); return false; }
			if(!Std.isOfType(obj, FlxSprite)) { FunkinLua.luaTrace('tweenObjectColor: Object "' + name + '" is not a sprite!'); return false; }
			menu.cancelTweenInternal(name);
			var tween:FlxTween = FlxTween.color(obj, duration, obj.color, toColor, {
				ease: menu.getEaseFunction(ease),
				onComplete: function(twn:FlxTween) menu.scriptTweens.remove(name)
			});
			menu.scriptTweens.set(name, tween);
			return true;
		});
		menu.addLocalCallback('cancelTween', function(name:String) {
			return menu.cancelTweenInternal(name);
		});
		menu.addLocalCallback('addTimer', function(tag:String, seconds:Float, callback:String) {
			if(menu.scriptTimers.exists(tag))
			{
				menu.scriptTimers.get(tag).cancel();
				menu.scriptTimers.remove(tag);
			}
			var timer:FlxTimer = new FlxTimer().start(seconds, function(tmr:FlxTimer) {
				menu.scriptTimers.remove(tag);
				menu.call(callback, [tag]);
			});
			menu.scriptTimers.set(tag, timer);
			return true;
		});
		menu.addLocalCallback('cancelTimer', function(tag:String) {
			if(menu.scriptTimers.exists(tag))
			{
				menu.scriptTimers.get(tag).cancel();
				menu.scriptTimers.remove(tag);
				return true;
			}
			return false;
		});

		// ---- 输入 API ----
		menu.addLocalCallback('keyJustPressed', function(key:String) return FlxG.keys.anyJustPressed([key]));
		menu.addLocalCallback('keyPressed', function(key:String) return FlxG.keys.anyPressed([key]));
		menu.addLocalCallback('keyJustReleased', function(key:String) return FlxG.keys.anyJustReleased([key]));
		menu.addLocalCallback('mouseJustPressed', function() return FlxG.mouse.justPressed);
		menu.addLocalCallback('mousePressed', function() return FlxG.mouse.pressed);
		menu.addLocalCallback('mouseJustReleased', function() return FlxG.mouse.justReleased);

		// ---- 音频 API ----
		menu.addLocalCallback('playSound', function(name:String, ?volume:Float = 1, ?tag:String = null) {
			var sound:FlxSound = FlxG.sound.play(Paths.sound(name), volume);
			if(tag != null && tag.length > 0) menu.scriptSounds.set(tag, sound);
			return sound != null;
		});
		menu.addLocalCallback('stopSound', function(?tag:String = null) {
			if(tag == null || tag.length < 1)
			{
				for(s in menu.scriptSounds) s.stop();
				menu.scriptSounds = [];
				return true;
			}
			if(menu.scriptSounds.exists(tag))
			{
				menu.scriptSounds.get(tag).stop();
				menu.scriptSounds.remove(tag);
				return true;
			}
			return false;
		});
		menu.addLocalCallback('playMusic', function(name:String, ?volume:Float = 1, ?loop:Bool = true) {
			FlxG.sound.playMusic(Paths.music(name), volume, loop);
			return true;
		});
		menu.addLocalCallback('stopMusic', function() {
			if(FlxG.sound.music != null) FlxG.sound.music.stop();
			return true;
		});

		// ---- 数据与系统 API ----
		menu.addLocalCallback('getDataFromSave', function(key:String, ?defaultValue:Dynamic = null) {
			if(FlxG.save.data != null && Reflect.hasField(FlxG.save.data, key)) return Reflect.field(FlxG.save.data, key);
			return defaultValue;
		});
		menu.addLocalCallback('setDataFromSave', function(key:String, value:Dynamic) {
			if(FlxG.save.data != null)
			{
				Reflect.setField(FlxG.save.data, key, value);
				FlxG.save.flush();
				return true;
			}
			return false;
		});
		menu.addLocalCallback('resetState', function() {
			FlxG.resetState();
			return true;
		});
		menu.addLocalCallback('switchState', function(stateName:String) {
			var newState:Class<Dynamic> = Type.resolveClass('states.' + stateName);
			if(newState == null) { FunkinLua.luaTrace('switchState: State "states.' + stateName + '" not found!'); return false; }
			MusicBeatState.switchState(Type.createInstance(newState, []));
			return true;
		});
		menu.addLocalCallback('openURL', function(url:String) {
			CoolUtil.browserLoad(url);
			return true;
		});

		// ---- 主题色（Meteoric 主题色功能）：界面脚本同样可用 ----
		// 语义与游玩脚本一致：默认临时覆盖，persist=true 才写存档。
		// 注意：界面脚本改色后，**已创建**的界面元素不会自动重绘（颜色在 create 时取值），
		// 需要立刻看到效果时由脚本自行重开界面，或等界面下次进入。
		menu.addLocalCallback('setThemeColor', function(index:Int = 0, ?persist:Bool = false) {
			DesignTokens.applyTheme(index, true, persist == true);
			return DesignTokens.themeIndex;
		});
		menu.addLocalCallback('getThemeColor', function() {
			return DesignTokens.themeIndex;
		});
		menu.addLocalCallback('getThemeColorName', function(?index:Int = -1) {
			return DesignTokens.themeName(index < 0 ? null : index);
		});
		menu.addLocalCallback('getThemeColorKey', function(?index:Int = -1) {
			return DesignTokens.themeKey(index < 0 ? null : index);
		});
		menu.addLocalCallback('getThemeColorCount', function() {
			return DesignTokens.THEME_COUNT;
		});
		menu.addLocalCallback('getThemeColors', function() {
			return DesignTokens.allThemeNames();
		});
		menu.addLocalCallback('getThemePrimary', function() {
			return DesignTokens.primary;
		});
		menu.addLocalCallback('getThemeSecondary', function() {
			return DesignTokens.secondary;
		});
		menu.addLocalCallback('getThemeTertiary', function() {
			return DesignTokens.tertiary;
		});
		// 脚本自绘面板想跟随主题色时显式取用；addBox 的默认值刻意保持中性深色，
		// 避免模组自绘 UI 随玩家主题设置漂移（默认值即契约）。
		menu.addLocalCallback('getThemePanelFill', function() {
			return DesignTokens.panelFill;
		});
		menu.addLocalCallback('getThemeRowHighlight', function() {
			return DesignTokens.rowHighlight;
		});

		// ---- 属性/方法反射 API ----
		menu.addLocalCallback('setStateProperty', function(objName:String, property:String, value:Dynamic) {
			var obj:Dynamic = menu.findObject(objName);
			if(obj == null) { FunkinLua.luaTrace('setStateProperty: Object "' + objName + '" not found!'); return false; }
			Reflect.setProperty(obj, property, value);
			return true;
		});
		menu.addLocalCallback('getStateProperty', function(objName:String, property:String) {
			var obj:Dynamic = menu.findObject(objName);
			if(obj == null) { FunkinLua.luaTrace('getStateProperty: Object "' + objName + '" not found!'); return null; }
			return Reflect.field(obj, property);
		});
		menu.addLocalCallback('setStateVar', function(varName:String, value:Dynamic) {
			Reflect.setProperty(menu.state, varName, value);
			return true;
		});
		menu.addLocalCallback('getStateVar', function(varName:String) {
			return Reflect.field(menu.state, varName);
		});
		menu.addLocalCallback('callStateFunction', function(funcName:String, ...args:Array<Dynamic>) {
			var fn:Dynamic = Reflect.field(menu.state, funcName);
			if(fn == null) { FunkinLua.luaTrace('callStateFunction: Function "' + funcName + '" not found!'); return false; }
			return Reflect.callMethod(menu.state, fn, args);
		});

		menu.addLocalCallback('luaTrace', function(text:String) {
			trace('[UI Script ' + menu.scriptName + '] ' + text);
			return text;
		});
		menu.addLocalCallback('getImportedScripts', function() {
			return menu.importedScripts;
		});

		// import 导入库系统：界面脚本同样支持导入其他 Lua 库
		Lua_helper.add_callback(menu.lua, 'import', function(luaFile:String) {
			// 游戏内 PlayState 脚本也会经过同一个全局回调分发；
			// 只有当前绑定界面就是活动状态（或不在游戏中）时才处理，避免误导入到错误状态
			var ps:PlayState = PlayState.instance;
			if(ps != null && ps.subState != menu.state)
			{
				trace('import: ignored (caller is not this UI script)');
				return false;
			}
			return LuaImport.importLibrary(menu.lua, luaFile, menu.scriptName, menu.importedScripts, menu.importingScripts,
				function(msg) FunkinLua.luaTrace(msg),
				function(msg) FunkinLua.luaTrace(msg));
		});
	}
}
