package psychlua;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
import openfl.utils.Assets;
import backend.ClientPrefs;
import backend.CoolUtil;
import backend.MusicBeatState;
import backend.Paths;
import backend.Mods;
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

/**
 * 界面脚本系统（自定义界面端口）：
 * 每个界面可加载 menus/<界面名>.lua，脚本可修改/新增界面文字、读写界面属性、调用界面方法，
 * 并通过 onCreate / onUpdate / onDestroy 等回调参与界面生命周期。
 * 与 FunkinLua（游玩脚本）互相独立，不依赖 PlayState 上下文。
 */
class MenuScript
{
	public var lua:State = null;
	public var scriptName:String = '';
	public var state:Dynamic = null;
	public var closed:Bool = false;
	public var importedScripts:Array<String> = []; // import 导入库系统：已导入库记录
	private var importingScripts:Array<String> = [];
	private var scriptObjects:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	private var scriptTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	private var scriptTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	private var scriptSounds:Map<String, FlxSound> = new Map<String, FlxSound>();

	public function new(state:Dynamic, scriptName:String)
	{
		this.state = state;
		this.scriptName = scriptName;

		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		// Lua class 系统（class + 继承）
		LuaClass.register(lua);

		// 基础环境变量
		set('scriptName', scriptName);
		set('stateName', Type.getClassName(Type.getClass(state)));
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);
		set('currentModDirectory', Mods.currentModDirectory);
		set('buildTarget', FunkinLua.getBuildTarget());
		set('version', Main.meVersion);
		set('luaDebugMode', false);

		// ---- 文字与对象定制 API ----
		addLocalCallback('setText', function(objName:String, text:String) {
			var obj:Dynamic = findObject(objName);
			if(obj == null) { luaTrace('setText: Object "' + objName + '" not found!'); return false; }
			if(!Std.isOfType(obj, FlxText)) { luaTrace('setText: Object "' + objName + '" is not a text object!'); return false; }
			obj.text = text;
			return true;
		});
		addLocalCallback('getText', function(objName:String) {
			var obj:Dynamic = findObject(objName);
			if(obj == null || !Std.isOfType(obj, FlxText)) return null;
			return obj.text;
		});
		addLocalCallback('addText', function(name:String, text:String, x:Float, y:Float, ?size:Int = 22, ?color:Int = 0xFFFFFFFF, ?font:String = 'vcr.ttf') {
			if(scriptObjects.exists(name)) { luaTrace('addText: Object "' + name + '" already exists!'); return false; }
			var txt:FlxText = new FlxText(x, y, 0, text, size);
			txt.setFormat(Paths.font(font), size, color, LEFT, OUTLINE, FlxColor.BLACK);
			txt.borderSize = 2;
			txt.scrollFactor.set();
			scriptObjects.set(name, txt);
			state.add(txt);
			return true;
		});
		addLocalCallback('removeObject', function(name:String) {
			if(scriptObjects.exists(name))
			{
				var obj:FlxSprite = scriptObjects.get(name);
				scriptObjects.remove(name);
				state.remove(obj);
				obj.destroy();
				return true;
			}
			luaTrace('removeObject: Object "' + name + '" not found!');
			return false;
		});
		addLocalCallback('objectExists', function(name:String) {
			return findObject(name) != null;
		});

		// ---- 对象控制 API ----
		addLocalCallback('setObjectVisible', function(name:String, visible:Bool) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectVisible: Object "' + name + '" not found!'); return false; }
			obj.visible = visible;
			return true;
		});
		addLocalCallback('getObjectVisible', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('getObjectVisible: Object "' + name + '" not found!'); return null; }
			return obj.visible;
		});
		addLocalCallback('setObjectAlpha', function(name:String, alpha:Float) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectAlpha: Object "' + name + '" not found!'); return false; }
			obj.alpha = alpha;
			return true;
		});
		addLocalCallback('getObjectAlpha', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('getObjectAlpha: Object "' + name + '" not found!'); return null; }
			return obj.alpha;
		});
		addLocalCallback('setObjectPosition', function(name:String, x:Float, y:Float) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectPosition: Object "' + name + '" not found!'); return false; }
			obj.x = x;
			obj.y = y;
			return true;
		});
		addLocalCallback('getObjectPosition', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('getObjectPosition: Object "' + name + '" not found!'); return null; }
			return {x: obj.x, y: obj.y};
		});
		addLocalCallback('setObjectScale', function(name:String, x:Float, y:Float) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectScale: Object "' + name + '" not found!'); return false; }
			obj.scale.set(x, y);
			if(Std.isOfType(obj, FlxSprite)) obj.updateHitbox();
			return true;
		});
		addLocalCallback('getObjectScale', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('getObjectScale: Object "' + name + '" not found!'); return null; }
			return {x: obj.scale.x, y: obj.scale.y};
		});
		addLocalCallback('setObjectColor', function(name:String, color:Int) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectColor: Object "' + name + '" not found!'); return false; }
			obj.color = color;
			return true;
		});
		addLocalCallback('getObjectColor', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('getObjectColor: Object "' + name + '" not found!'); return null; }
			return obj.color;
		});
		addLocalCallback('setObjectAngle', function(name:String, angle:Float) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectAngle: Object "' + name + '" not found!'); return false; }
			obj.angle = angle;
			return true;
		});
		addLocalCallback('getObjectAngle', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('getObjectAngle: Object "' + name + '" not found!'); return null; }
			return obj.angle;
		});
		addLocalCallback('setObjectFlip', function(name:String, flipX:Bool, ?flipY:Bool = false) {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('setObjectFlip: Object "' + name + '" not found!'); return false; }
			obj.flipX = flipX;
			obj.flipY = flipY;
			return true;
		});
		addLocalCallback('getObjectType', function(name:String) {
			var obj:Dynamic = findObject(name);
			if(obj == null) return null;
			return Type.getClassName(Type.getClass(obj));
		});

		// ---- 创建对象 API ----
		addLocalCallback('addSprite', function(name:String, image:String, x:Float, y:Float) {
			if(scriptObjects.exists(name)) { luaTrace('addSprite: Object "' + name + '" already exists!'); return false; }
			var spr:FlxSprite = new FlxSprite(x, y).loadGraphic(Paths.image(image));
			spr.antialiasing = ClientPrefs.data.antialiasing;
			scriptObjects.set(name, spr);
			state.add(spr);
			return true;
		});
		addLocalCallback('addBox', function(name:String, x:Float, y:Float, w:Float, h:Float, ?color:Int = 0xCC161622, ?radius:Float = 20, ?borderColor:Int = 0x45FFFFFF) {
			if(scriptObjects.exists(name)) { luaTrace('addBox: Object "' + name + '" already exists!'); return false; }
			var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, color);
			if(borderColor != 0)
				FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: borderColor, thickness: 1.5});
			spr.scrollFactor.set();
			scriptObjects.set(name, spr);
			state.add(spr);
			return true;
		});

		// ---- 动画与计时器 API ----
		addLocalCallback('tweenObject', function(name:String, tweenValue:Dynamic, duration:Float, ?ease:String = 'linear') {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('tweenObject: Object "' + name + '" not found!'); return false; }
			cancelTweenInternal(name);
			var tween:FlxTween = FlxTween.tween(obj, tweenValue, duration, {
				ease: getEaseFunction(ease),
				onComplete: function(twn:FlxTween) scriptTweens.remove(name)
			});
			scriptTweens.set(name, tween);
			return true;
		});
		addLocalCallback('tweenObjectColor', function(name:String, toColor:Int, duration:Float, ?ease:String = 'linear') {
			var obj:Dynamic = findObject(name);
			if(obj == null) { luaTrace('tweenObjectColor: Object "' + name + '" not found!'); return false; }
			if(!Std.isOfType(obj, FlxSprite)) { luaTrace('tweenObjectColor: Object "' + name + '" is not a sprite!'); return false; }
			cancelTweenInternal(name);
			var tween:FlxTween = FlxTween.color(obj, duration, obj.color, toColor, {
				ease: getEaseFunction(ease),
				onComplete: function(twn:FlxTween) scriptTweens.remove(name)
			});
			scriptTweens.set(name, tween);
			return true;
		});
		addLocalCallback('cancelTween', function(name:String) {
			return cancelTweenInternal(name);
		});
		addLocalCallback('addTimer', function(tag:String, seconds:Float, callback:String) {
			if(scriptTimers.exists(tag))
			{
				scriptTimers.get(tag).cancel();
				scriptTimers.remove(tag);
			}
			var timer:FlxTimer = new FlxTimer().start(seconds, function(tmr:FlxTimer) {
				scriptTimers.remove(tag);
				call(callback, [tag]);
			});
			scriptTimers.set(tag, timer);
			return true;
		});
		addLocalCallback('cancelTimer', function(tag:String) {
			if(scriptTimers.exists(tag))
			{
				scriptTimers.get(tag).cancel();
				scriptTimers.remove(tag);
				return true;
			}
			return false;
		});

		// ---- 输入 API ----
		addLocalCallback('keyJustPressed', function(key:String) return FlxG.keys.anyJustPressed([key]));
		addLocalCallback('keyPressed', function(key:String) return FlxG.keys.anyPressed([key]));
		addLocalCallback('keyJustReleased', function(key:String) return FlxG.keys.anyJustReleased([key]));
		addLocalCallback('mouseJustPressed', function() return FlxG.mouse.justPressed);
		addLocalCallback('mousePressed', function() return FlxG.mouse.pressed);
		addLocalCallback('mouseJustReleased', function() return FlxG.mouse.justReleased);

		// ---- 音频 API ----
		addLocalCallback('playSound', function(name:String, ?volume:Float = 1, ?tag:String = null) {
			var sound:FlxSound = FlxG.sound.play(Paths.sound(name), volume);
			if(tag != null && tag.length > 0) scriptSounds.set(tag, sound);
			return sound != null;
		});
		addLocalCallback('stopSound', function(?tag:String = null) {
			if(tag == null || tag.length < 1)
			{
				for(s in scriptSounds) s.stop();
				scriptSounds = [];
				return true;
			}
			if(scriptSounds.exists(tag))
			{
				scriptSounds.get(tag).stop();
				scriptSounds.remove(tag);
				return true;
			}
			return false;
		});
		addLocalCallback('playMusic', function(name:String, ?volume:Float = 1, ?loop:Bool = true) {
			FlxG.sound.playMusic(Paths.music(name), volume, loop);
			return true;
		});
		addLocalCallback('stopMusic', function() {
			if(FlxG.sound.music != null) FlxG.sound.music.stop();
			return true;
		});

		// ---- 数据与系统 API ----
		addLocalCallback('getDataFromSave', function(key:String, ?defaultValue:Dynamic = null) {
			if(FlxG.save.data != null && Reflect.hasField(FlxG.save.data, key)) return Reflect.field(FlxG.save.data, key);
			return defaultValue;
		});
		addLocalCallback('setDataFromSave', function(key:String, value:Dynamic) {
			if(FlxG.save.data != null)
			{
				Reflect.setField(FlxG.save.data, key, value);
				FlxG.save.flush();
				return true;
			}
			return false;
		});
		addLocalCallback('resetState', function() {
			FlxG.resetState();
			return true;
		});
		addLocalCallback('switchState', function(stateName:String) {
			var newState:Class<Dynamic> = Type.resolveClass('states.' + stateName);
			if(newState == null) { luaTrace('switchState: State "states.' + stateName + '" not found!'); return false; }
			MusicBeatState.switchState(Type.createInstance(newState, []));
			return true;
		});
		addLocalCallback('openURL', function(url:String) {
			CoolUtil.browserLoad(url);
			return true;
		});

		// ---- 属性/方法反射 API ----
		addLocalCallback('setStateProperty', function(objName:String, property:String, value:Dynamic) {
			var obj:Dynamic = findObject(objName);
			if(obj == null) { luaTrace('setStateProperty: Object "' + objName + '" not found!'); return false; }
			Reflect.setProperty(obj, property, value);
			return true;
		});
		addLocalCallback('getStateProperty', function(objName:String, property:String) {
			var obj:Dynamic = findObject(objName);
			if(obj == null) { luaTrace('getStateProperty: Object "' + objName + '" not found!'); return null; }
			return Reflect.field(obj, property);
		});
		addLocalCallback('setStateVar', function(varName:String, value:Dynamic) {
			Reflect.setProperty(state, varName, value);
			return true;
		});
		addLocalCallback('getStateVar', function(varName:String) {
			return Reflect.field(state, varName);
		});
		addLocalCallback('callStateFunction', function(funcName:String, ...args:Array<Dynamic>) {
			var fn:Dynamic = Reflect.field(state, funcName);
			if(fn == null) { luaTrace('callStateFunction: Function "' + funcName + '" not found!'); return false; }
			return Reflect.callMethod(state, fn, args);
		});

		addLocalCallback('luaTrace', function(text:String) {
			trace('[UI Script ' + scriptName + '] ' + text);
			return text;
		});
		addLocalCallback('getImportedScripts', function() {
			return importedScripts;
		});

		// import 导入库系统：界面脚本同样支持导入其他 Lua 库
		Lua_helper.add_callback(lua, 'import', function(luaFile:String) {
			// 游戏内 PlayState 脚本也会经过同一个全局回调分发；
			// 只有当前绑定界面就是活动状态（或不在游戏中）时才处理，避免误导入到错误状态
			var ps:PlayState = PlayState.instance;
			if(ps != null && ps.subState != state)
			{
				trace('import: ignored (caller is not this UI script)');
				return false;
			}
			return LuaImport.importLibrary(lua, luaFile, scriptName, importedScripts, importingScripts,
				function(msg) luaTrace(msg),
				function(msg) luaTrace(msg));
		});

		// 加载并执行脚本文件
		var content:String = getScriptContent(scriptName);
		if(content == null || content.length < 1)
		{
			luaTrace('Failed to load script: ' + scriptName);
			Lua.close(lua);
			lua = null;
			return;
		}

		var status:Int = LuaL.dostring(lua, content);
		if(status != Lua.LUA_OK)
		{
			luaTrace(getErrorMessage(status));
			Lua.close(lua);
			lua = null;
			return;
		}
		trace('UI script loaded successfully: ' + scriptName);

		call('onCreate', []);
	}

	public function call(func:String, args:Array<Dynamic>):Dynamic
	{
		if(closed) return FunkinLua.Function_Continue;

		try
		{
			if(lua == null) return FunkinLua.Function_Continue;

			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);
			if(type != Lua.LUA_TFUNCTION)
			{
				Lua.pop(lua, 1);
				return FunkinLua.Function_Continue;
			}

			if(args == null) args = [];
			for(arg in args) Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, args.length, 1, 0);

			if(status != Lua.LUA_OK)
			{
				luaTrace('ERROR (' + func + '): ' + getErrorMessage(status));
				return FunkinLua.Function_Continue;
			}

			var result:Dynamic = cast Convert.fromLua(lua, -1);
			Lua.pop(lua, 1);
			return result;
		}
		catch(e:Dynamic)
		{
			trace(e);
		}
		return FunkinLua.Function_Continue;
	}

	public function set(variable:String, data:Dynamic)
	{
		if(lua == null) return;
		Convert.toLua(lua, data);
		Lua.setglobal(lua, variable);
	}

	public function update(elapsed:Float)
	{
		// 每帧更新鼠标位置变量，脚本里可直接读 mouseX / mouseY
		set('mouseX', FlxG.mouse.x);
		set('mouseY', FlxG.mouse.y);
		call('onUpdate', [elapsed]);
	}

	public function destroy()
	{
		call('onDestroy', []);
		closed = true;
		if(lua != null)
		{
			Lua.close(lua);
			lua = null;
		}
		for(tween in scriptTweens) tween.cancel();
		scriptTweens = [];
		for(timer in scriptTimers) timer.cancel();
		scriptTimers = [];
		for(sound in scriptSounds) sound.stop();
		scriptSounds = [];
		for(obj in scriptObjects)
		{
			state.remove(obj);
			obj.destroy();
		}
		scriptObjects = [];
	}

	function getEaseFunction(ease:String):flixel.tweens.EaseFunction
	{
		var fn:Dynamic = Reflect.field(FlxEase, ease);
		if(fn == null)
		{
			luaTrace('Unknown ease "' + ease + '", using linear');
			fn = FlxEase.linear;
		}
		return cast fn;
	}

	function cancelTweenInternal(name:String):Bool
	{
		if(scriptTweens.exists(name))
		{
			scriptTweens.get(name).cancel();
			scriptTweens.remove(name);
			return true;
		}
		return false;
	}

	public function luaTrace(text:String)
	{
		trace('[UI Script ' + scriptName + '] ' + text);
	}

	// 注册界面脚本专属回调（名字与游玩脚本错开，避免全局回调冲突）
	public function addLocalCallback(name:String, myFunction:Dynamic)
	{
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, myFunction);
	}

	private var callbacks:Map<String, Dynamic> = new Map<String, Dynamic>();

	function findObject(objName:String):Dynamic
	{
		if(scriptObjects.exists(objName)) return scriptObjects.get(objName);
		return Reflect.field(state, objName);
	}

	function getScriptContent(path:String):String
	{
		#if MODS_ALLOWED
		if(FileSystem.exists(path)) return File.getContent(path);
		#else
		if(Assets.exists(path)) return Assets.getText(path);
		#end
		return null;
	}

	function getErrorMessage(status:Int):String
	{
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);
		if(v != null) v = v.trim();
		if(v == null || v == "")
		{
			switch(status)
			{
				case Lua.LUA_ERRRUN: return "Runtime Error";
				case Lua.LUA_ERRMEM: return "Memory Allocation Error";
				case Lua.LUA_ERRERR: return "Critical Error";
			}
			return "Unknown Error";
		}
		return v;
	}

	/**
	 * 查找界面脚本路径：menus/<name>.lua
	 * 依次查找当前 mod 目录、全局 mods、mods 根目录、preload 资源；也支持绝对路径。
	 */
	public static function findScriptPath(name:String):String
	{
		if(name == null || name.length < 1) return null;
		if(!name.endsWith('.lua')) name += '.lua';

		#if MODS_ALLOWED
		if(name.startsWith('/') && FileSystem.exists(name))
			return name;
		#end

		var file:String = 'menus/' + name;
		var preloadPath:String = Paths.getPreloadPath(file);
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(file);
		if(FileSystem.exists(path)) return path;
		if(FileSystem.exists(preloadPath)) return preloadPath;
		#else
		if(Assets.exists(preloadPath)) return preloadPath;
		#end
		return null;
	}
}
#end
