package psychlua;

import flixel.FlxBasic;
import objects.Character;
import psychlua.FunkinLua;
import psychlua.CustomSubstate;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.0")
import tea.SScript;
#if sys
import sys.FileSystem;
#end
class HScript extends SScript
{
	public var parentLua:FunkinLua;

	/**
	 * 所属脚本组（由 `ScriptGroup` 在 execute 前注入；`runHaxeCode` 等无组场景为 null）。
	 * 类型用 Dynamic 避免 psychlua → scripting 的模块环。
	 */
	public var group:Dynamic = null;

	/** 无组场景下通过 `importScript` 加载的库脚本（随本脚本一起销毁）。 */
	public var standaloneLibraries:Array<HScript> = [];
	
	public static function initHaxeModule(parent:FunkinLua)
	{
		#if (SScript >= "3.0.0")
		if(parent.hscript == null)
		{
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent);
		}
		#end
	}

	public static function initHaxeModuleCode(parent:FunkinLua, code:String)
	{
		#if (SScript >= "3.0.0")
		var hs:HScript = try parent.hscript catch (e) null;
		var cleaned:String = preprocessScript(code);
		if(hs == null)
		{
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent, cleaned);
		}
		else
		{
			// Psych 0.7.3 兼容：后续 runHaxeCode 每次都要执行代码（SScript 4.0.1 的 doString 内部有 try/catch，解析失败不抛）
			hs.doString(cleaned);
		}
		#end
	}

	/**
	 * Psych 0.7.3 模组兼容：SScript 4.0.1 的类型检查器不接受
	 * `var x:Map<String, Dynamic> = [];`（报 Array should be Map），
	 * 官方 PE 0.7.3 能跑这类写法。此处把「Map 类型变量用空数组初始化」改写为 `new Map()`。
	 */
	public static function preprocessScript(code:String):String
	{
		if (code == null || code.length == 0) return code;
		// （字符串级替换，保留 var 名前缀；SScript 4.0.1 类型检查器/运行时均不认这种 Map 初始化）
		// 泛型通配：`:Map<String, Dynamic> = [];` / `:Map<String, FlxBackdrop> = [];` 等
		// 统一改写为「保留类型注解 + new Map()」——注意**不能**改成 `= __newMap();` 后丢掉注解，
		// 那会让 `var x = __newMap();` 里的 __newMap 变成未知标识符（旧的 __newMap 方案即因此必然报错）。
		var out:String = code;
		out = ~/:[ \t]*Map[ \t]*<[^>]*>[ \t]*=[ \t]*\[\][ \t]*;/g.replace(out, ' = new Map();');
		return out;
	}

	public var origin:String;
	override public function new(?parent:FunkinLua, ?file:String, ?executeNow:Bool = true)
	{
		if (file == null)
			file = '';
	
		super(file, false, false);
		parentLua = parent;
		if (parent != null)
			origin = parent.scriptName;
		if (scriptFile != null && scriptFile.length > 0)
			origin = scriptFile;
		preset();
		// SScript 4.0.1 的 execute() 解析失败会抛异常（runHaxeCode 首段代码语法错时避免 lua panic）
		// executeNow=false：先构造并注入 state 变量，再由调用方 execute()（见 HostDomain.initHScript）。
		if (executeNow)
		{
			try execute() catch (e:Dynamic) { trace('HScript execute failed: ' + Std.string(e)); }
		}
	}

	override function preset()
	{
		#if (SScript >= "3.0.0")
		super.preset();

		// Some very commonly used classes
		set('FlxG', flixel.FlxG);
		set('FlxSprite', flixel.FlxSprite);
		set('FlxCamera', flixel.FlxCamera);
		set('FlxTimer', flixel.util.FlxTimer);
		set('FlxTween', flixel.tweens.FlxTween);
		set('FlxEase', flixel.tweens.FlxEase);
		set('FlxColor', CustomFlxColor);
		set('PlayState', PlayState);
		set('Paths', Paths);
		set('Conductor', Conductor);
		set('ClientPrefs', ClientPrefs);
		set('Character', Character);
		set('Note', objects.Note);
		set('CustomSubstate', CustomSubstate);
		set('Countdown', backend.BaseStage.Countdown);
		#if (!flash && sys)
		set('FlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
		#end
		set('ShaderFilter', openfl.filters.ShaderFilter);
		set('StringTools', StringTools);

		// ── SeiunEngine 融合变量（来自 SeiunEngine getDefaultVariables，剔除 MeteoricEngine 缺失的类） ──
		// Haxe std（Math 用代理对象：Math.PI 等 inline 常量反射不到，方法以值引用生成非内联拷贝）
		set('Math', {
			PI: Math.PI,
			NaN: Math.NaN,
			POSITIVE_INFINITY: Math.POSITIVE_INFINITY,
			NEGATIVE_INFINITY: Math.NEGATIVE_INFINITY,
			abs: Math.abs,
			ceil: Math.ceil,
			floor: Math.floor,
			round: Math.round,
			min: Math.min,
			max: Math.max,
			pow: Math.pow,
			sqrt: Math.sqrt,
			sin: Math.sin,
			cos: Math.cos,
			tan: Math.tan,
			atan: Math.atan,
			atan2: Math.atan2,
			asin: Math.asin,
			acos: Math.acos,
			random: Math.random,
			log: Math.log,
			exp: Math.exp,
			isFinite: Math.isFinite,
			isNaN: Math.isNaN,
			ffloor: Math.ffloor,
			fceil: Math.fceil,
			fround: Math.fround
		});
		set('Std', Std);
		set('Type', Type);
		set('Reflect', Reflect);
		set('Date', Date);
		set('DateTools', DateTools);
		set('Lambda', Lambda);
		set('String', String);
		set('Array', Array);
		set('Json', {
			parse: function(text:String):Dynamic return haxe.format.JsonParser.parse(text),
			stringify: function(value:Dynamic, ?replacer:Dynamic = null, ?space:String = null):String
				return haxe.format.JsonPrinter.print(value, replacer, space)
		});
		// Flixel（FlxMath 用代理对象：fastCos/fastSin 等 inline 方法以值引用生成非内联拷贝，hscript 反射可用）
		set('FlxMath', {
			fastCos: flixel.math.FlxMath.fastCos,
			fastSin: flixel.math.FlxMath.fastSin,
			bound: flixel.math.FlxMath.bound,
			lerp: flixel.math.FlxMath.lerp,
			inBounds: flixel.math.FlxMath.inBounds,
			isOdd: flixel.math.FlxMath.isOdd,
			isEven: flixel.math.FlxMath.isEven,
			roundDecimal: flixel.math.FlxMath.roundDecimal,
			dotProduct: flixel.math.FlxMath.dotProduct,
			vectorLength: flixel.math.FlxMath.vectorLength,
			distanceBetween: flixel.math.FlxMath.distanceBetween,
			distanceToPoint: flixel.math.FlxMath.distanceToPoint,
			distanceToMouse: flixel.math.FlxMath.distanceToMouse,
			distanceToTouch: flixel.math.FlxMath.distanceToTouch,
			isDistanceWithin: flixel.math.FlxMath.isDistanceWithin,
			isDistanceToPointWithin: flixel.math.FlxMath.isDistanceToPointWithin,
			isDistanceToMouseWithin: flixel.math.FlxMath.isDistanceToMouseWithin
		});
		set('FlxText', flixel.text.FlxText);
		set('FlxSound', flixel.sound.FlxSound);
		set('FlxGroup', flixel.group.FlxGroup);
		set('FlxTypedGroup', flixel.group.FlxGroup.FlxTypedGroup);
		set('FlxSpriteGroup', flixel.group.FlxSpriteGroup);
		set('FlxStringUtil', flixel.util.FlxStringUtil);
		set('FlxSpriteUtil', flixel.util.FlxSpriteUtil);
		set('FlxAtlasFrames', flixel.graphics.frames.FlxAtlasFrames);
		set('FlxObject', flixel.FlxObject);
		set('FlxBasic', flixel.FlxBasic);
		set('FlxButton', flixel.ui.FlxButton);
		set('FlxBar', flixel.ui.FlxBar);
		set('FlxRect', flixel.math.FlxRect);
		set('FlxRandom', flixel.math.FlxRandom);
		set('FlxTextBorderStyle', flixel.text.FlxText.FlxTextBorderStyle);
		// Engine 类
		#if ACHIEVEMENTS_ALLOWED
		set('Achievements', backend.Achievements);
		#end
		#if flxanimate
		set('FlxAnimate', flxanimate.FlxAnimate);
		#end
		set('BGSprite', objects.BGSprite);
		set('AttachedSprite', objects.AttachedSprite);
		set('Alphabet', objects.Alphabet);
		// 脚本写界面用：引擎同款字体/描边的文本控件（MenuText 自带 future.ttf 与描边样式）
		set('MenuText', objects.MenuText);
		set('FlxGradient', flixel.util.FlxGradient);
		set('Mods', backend.Mods);
		set('MusicBeatState', backend.MusicBeatState);
		set('MusicBeatSubstate', backend.MusicBeatSubstate);
		set('FreeplayState', states.FreeplayState);
		set('StoryMenuState', states.StoryMenuState);
		set('TitleState', states.TitleState);
		set('CreditsState', states.CreditsState);
		set('MainMenuState', states.MainMenuState);
		set('HScript', HScript);
		set('CoolUtil', backend.CoolUtil);
		// 多语言（Meteoric 多语言功能）：Lang.t 取译文 / Lang.tOr 带原文兜底；Lang.current 读当前语言码
		set('Lang', backend.Lang);
		set('tr', function(key:String, ?args:Array<Dynamic>) {
			return backend.Lang.t(key, args);
		});
		set('trOr', function(key:String, fallback:String) {
			return backend.Lang.tOr(key, fallback);
		});
		set('getLanguage', function() {
			return backend.Lang.current;
		});
		// 主题色令牌中心（Meteoric 主题色功能）：HScript 可直接读 DesignTokens.primary/secondary/tertiary
		set('DesignTokens', backend.DesignTokens);
		// 主题色脚本 API：默认临时覆盖（不写存档），persist=true 才持久化
		set('setThemeColor', function(index:Int = 0, ?persist:Bool = false) {
			backend.DesignTokens.applyTheme(index, true, persist == true);
			return backend.DesignTokens.themeIndex;
		});
		set('getThemeColor', function() {
			return backend.DesignTokens.themeIndex;
		});
		set('getThemeColorName', function(?index:Int = -1) {
			return backend.DesignTokens.themeName(index < 0 ? null : index);
		});
		set('getThemeColorKey', function(?index:Int = -1) {
			return backend.DesignTokens.themeKey(index < 0 ? null : index);
		});
		set('getThemeColorCount', function() {
			return backend.DesignTokens.THEME_COUNT;
		});
		set('getThemeColors', function() {
			return backend.DesignTokens.allThemeNames();
		});
		set('getThemePanelFill', function() {
			return backend.DesignTokens.panelFill;
		});
		set('getThemeRowHighlight', function() {
			return backend.DesignTokens.rowHighlight;
		});
		set('WeekData', backend.WeekData);
		set('Highscore', backend.Highscore);
		set('LoadingState', states.LoadingState);
		set('Application', lime.app.Application);
		set('Assets', openfl.utils.Assets);
		set('ColorMatrixFilter', openfl.filters.ColorMatrixFilter);
		set('Event', openfl.events.Event);
		// 常量
		set('X', flixel.util.FlxAxes.X);
		set('Y', flixel.util.FlxAxes.Y);
		set('XY', flixel.util.FlxAxes.XY);
		set('LEFT', flixel.text.FlxText.FlxTextAlign.LEFT);
		set('CENTER', flixel.text.FlxText.FlxTextAlign.CENTER);
		set('RIGHT', flixel.text.FlxText.FlxTextAlign.RIGHT);
		set('OUTLINE', flixel.text.FlxText.FlxTextBorderStyle.OUTLINE);
		set('OUTLINE_FAST', flixel.text.FlxText.FlxTextBorderStyle.OUTLINE_FAST);
		set('SHADOW', flixel.text.FlxText.FlxTextBorderStyle.SHADOW);
		set('NONE', flixel.text.FlxText.FlxTextBorderStyle.NONE);
		// haxe.ds
		set('IntMap', haxe.ds.IntMap);
		set('StringMap', haxe.ds.StringMap);
		set('ObjectMap', haxe.ds.ObjectMap);
		set('EnumValueMap', haxe.ds.EnumValueMap);
		set('HaxeList', haxe.ds.List);
		set('GenericStack', haxe.ds.GenericStack);
		set('SortedList', haxe.ds.List);
		// haxe.io / crypto
		set('Bytes', haxe.io.Bytes);
		set('Input', haxe.io.Input);
		set('Output', haxe.io.Output);
		set('HaxePath', haxe.io.Path);
		set('Eof', haxe.io.Eof);
		set('Base64', haxe.crypto.Base64);
		set('Md5', haxe.crypto.Md5);
		set('Sha1', haxe.crypto.Sha1);
		set('Sha256', haxe.crypto.Sha256);
		set('Adler32', haxe.crypto.Adler32);
		set('CrC32', haxe.crypto.Crc32);
		#if sys
		set('Sys', Sys);
		set('File', sys.io.File);
		set('FileSystem', sys.FileSystem);
		set('FileInput', sys.io.FileInput);
		set('FileOutput', sys.io.FileOutput);
		set('Process', sys.io.Process);
		#end
		// openfl.geom
		set('Matrix', openfl.geom.Matrix);
		set('Point', openfl.geom.Point);
		set('Rectangle', openfl.geom.Rectangle);
		set('ColorTransform', openfl.geom.ColorTransform);
		set('Transform', openfl.geom.Transform);
		// openfl.display
		set('DisplayObject', openfl.display.DisplayObject);
		set('DisplayObjectContainer', openfl.display.DisplayObjectContainer);
		set('Sprite', openfl.display.Sprite);
		set('Stage', openfl.display.Stage);
		set('Bitmap', openfl.display.Bitmap);
		set('BitmapData', openfl.display.BitmapData);
		set('Graphics', openfl.display.Graphics);
		set('MovieClip', openfl.display.MovieClip);
		set('Shader', openfl.display.Shader);
		set('ShaderParameter', openfl.display.ShaderParameter);
		set('ShaderInput', openfl.display.ShaderInput);
		set('FPS', openfl.display.FPS);
		set('fpsVar', Main.fpsVar);
		// openfl.events
		set('MouseEvent', openfl.events.MouseEvent);
		set('KeyboardEvent', openfl.events.KeyboardEvent);
		set('TouchEvent', openfl.events.TouchEvent);
		set('FocusEvent', openfl.events.FocusEvent);
		set('IOErrorEvent', openfl.events.IOErrorEvent);
		set('SecurityErrorEvent', openfl.events.SecurityErrorEvent);
		set('ProgressEvent', openfl.events.ProgressEvent);
		set('HTTPStatusEvent', openfl.events.HTTPStatusEvent);
		// DataEvent / SampleDataEvent 因 OpenFL 9.2.1 C++ 生成 bug 无法引用，已剔除
		// 工具函数（移植自 SeiunEngine）
		set('loadModTextFile', function(path:String):String {
			#if sys
			var paths:Array<String> = [];
			#if MODS_ALLOWED
			if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
				paths.push(Paths.mods(Mods.currentModDirectory + '/' + path));
			for (mod in Mods.getGlobalMods())
				paths.push(Paths.mods(mod + '/' + path));
			#end
			paths.push(Paths.getPreloadPath(path));
			for (p in paths) {
				if (sys.FileSystem.exists(p))
					return sys.io.File.getContent(p);
			}
			#end
			return '';
		});
		set('parseTextConfig', function(content:String, ?prefix:String = null):Dynamic {
			var result = {};
			if (content == null || content.length == 0) return result;
			var lines = content.split("\n");
			for (line in lines) {
				line = StringTools.trim(line);
				if (line.length == 0 || line.startsWith("#")) continue;
				var eqIdx = line.indexOf("=");
				if (eqIdx < 0) continue;
				var key = StringTools.trim(line.substr(0, eqIdx));
				var val = StringTools.trim(line.substr(eqIdx + 1));
				if (prefix != null) {
					if (!key.startsWith(prefix)) continue;
					key = key.substr(prefix.length);
				}
				Reflect.setField(result, key, val);
			}
			return result;
		});
		set('version', '0.2.8');
		set('hscriptVersion', 'SScript 4.0.1');
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);

		// ── Psych 0.7.3 融合变量 ──
		set('moveCamera', function(isDad:Bool) return PlayState.instance.moveCamera(isDad));

		set('getModSetting', function(saveTag:String, ?modName:String = null) {
			if(modName == null)
			{
				modName = Mods.currentModDirectory;
				if(modName == null || modName.length < 1)
				{
					PlayState.instance.addTextToDebug('getModSetting: Argument #2 is null and script is not inside a packed Mod folder!', FlxColor.RED);
					return null;
				}
			}
			return LuaUtils.getModSetting(saveTag, modName);
		});

		// Keyboard & Gamepads
		set('keyboardJustPressed', function(name:String) return Reflect.getProperty(FlxG.keys.justPressed, name));
		set('keyboardPressed', function(name:String) return Reflect.getProperty(FlxG.keys.pressed, name));
		set('keyboardReleased', function(name:String) return Reflect.getProperty(FlxG.keys.justReleased, name));

		set('anyGamepadJustPressed', function(name:String) {
			var id = flixel.input.gamepad.FlxGamepadInputID.fromStringMap.get(name);
			if (id == null) return false;
			return FlxG.gamepads.anyJustPressed(id);
		});
		set('anyGamepadPressed', function(name:String) {
			var id = flixel.input.gamepad.FlxGamepadInputID.fromStringMap.get(name);
			if (id == null) return false;
			return FlxG.gamepads.anyPressed(id);
		});
		set('anyGamepadReleased', function(name:String) {
			var id = flixel.input.gamepad.FlxGamepadInputID.fromStringMap.get(name);
			if (id == null) return false;
			return FlxG.gamepads.anyJustReleased(id);
		});

		set('gamepadAnalogX', function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;

			return controller.getXAxis(leftStick ? flixel.input.gamepad.FlxGamepadInputID.LEFT_ANALOG_STICK : flixel.input.gamepad.FlxGamepadInputID.RIGHT_ANALOG_STICK);
		});
		set('gamepadAnalogY', function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;

			return controller.getYAxis(leftStick ? flixel.input.gamepad.FlxGamepadInputID.LEFT_ANALOG_STICK : flixel.input.gamepad.FlxGamepadInputID.RIGHT_ANALOG_STICK);
		});
		set('gamepadJustPressed', function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		set('gamepadPressed', function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.pressed, name) == true;
		});
		set('gamepadReleased', function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.justReleased, name) == true;
		});

		set('keyJustPressed', function(name:String = '') {
			name = name.toLowerCase();
			switch(name) {
				case 'left': return Controls.instance.NOTE_LEFT_P;
				case 'down': return Controls.instance.NOTE_DOWN_P;
				case 'up': return Controls.instance.NOTE_UP_P;
				case 'right': return Controls.instance.NOTE_RIGHT_P;
				default: return Controls.instance.justPressed(name);
			}
			return false;
		});
		set('keyPressed', function(name:String = '') {
			name = name.toLowerCase();
			switch(name) {
				case 'left': return Controls.instance.NOTE_LEFT;
				case 'down': return Controls.instance.NOTE_DOWN;
				case 'up': return Controls.instance.NOTE_UP;
				case 'right': return Controls.instance.NOTE_RIGHT;
				default: return Controls.instance.pressed(name);
			}
			return false;
		});
		set('keyReleased', function(name:String = '') {
			name = name.toLowerCase();
			switch(name) {
				case 'left': return Controls.instance.NOTE_LEFT_R;
				case 'down': return Controls.instance.NOTE_DOWN_R;
				case 'up': return Controls.instance.NOTE_UP_R;
				case 'right': return Controls.instance.NOTE_RIGHT_R;
				default: return Controls.instance.justReleased(name);
			}
			return false;
		});

		// Functions & Variables
		set('setVar', function(name:String, value:Dynamic)
		{
			PlayState.instance.variables.set(name, value);
		});
		// 兜底：旧的预处理产物会引用 __newMap()，注册成真实函数，避免「Unknown variable: __newMap」
		set('__newMap', function() return new Map<String, Dynamic>());
		set('getVar', function(name:String)
		{
			var result:Dynamic = null;
			if(PlayState.instance.variables.exists(name)) result = PlayState.instance.variables.get(name);
			return result;
		});
		set('removeVar', function(name:String)
		{
			if(PlayState.instance.variables.exists(name))
			{
				PlayState.instance.variables.remove(name);
				return true;
			}
			return false;
		});
		set('debugPrint', function(text:String, ?color:FlxColor = null) {
			if(color == null) color = FlxColor.WHITE;
			PlayState.instance.addTextToDebug(text, color);
		});

		// For adding your own callbacks

		// not very tested but should work
		set('createGlobalCallback', function(name:String, func:Dynamic)
		{
			#if LUA_ALLOWED
			for (script in PlayState.instance.luaArray)
			{
				if(script == null || script.lua == null || script.closed) continue;
				// 防护：被污染的 lua 状态（栈下溢 gettop<0）会导致 lua_pushcclosure 原生崩溃，跳过之
				var _gt:Int = 0;
				try { _gt = Lua.gettop(script.lua); } catch (e:Dynamic) { continue; }
				if (_gt < 0) continue; // 被污染的 lua 状态（栈下溢）跳过，防止 lua_pushcclosure 原生崩溃
				Lua_helper.add_callback(script.lua, name, func);
			}
			#end
			FunkinLua.customFunctions.set(name, func);
		});

		// tested
		set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null)
		{
			if(funk == null) funk = parentLua;
			
			if(parentLua != null) funk.addLocalCallback(name, func);
			else FunkinLua.luaTrace('createCallback ($name): 3rd argument is null', false, false, FlxColor.RED);
		});

		set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			try {
				var str:String = '';
				if(libPackage.length > 0)
					str = libPackage + '.';

				set(libName, Type.resolveClass(str + libName));
			}
			catch (e:Dynamic) {
				var msg:String = e.message.substr(0, e.message.indexOf('\n'));
				if(parentLua != null)
				{
					FunkinLua.lastCalledScript = parentLua;
					msg = origin + ":" + parentLua.lastCalledFunction + " - " + msg;
				}
				else msg = '$origin - $msg';
				FunkinLua.luaTrace(msg, parentLua == null, false, FlxColor.RED);
			}
		});
		set('parentLua', parentLua);
		set('this', this);
		set('game', PlayState.instance);
		set('buildTarget', FunkinLua.getBuildTarget());
		set('customSubstate', CustomSubstate.instance);
		set('customSubstateName', CustomSubstate.name);

		set('Function_Stop', FunkinLua.Function_Stop);
		set('Function_Continue', FunkinLua.Function_Continue);
		set('Function_StopLua', FunkinLua.Function_StopLua); //doesnt do much cuz HScript has a lower priority than Lua
		set('Function_StopHScript', FunkinLua.Function_StopHScript);
		set('Function_StopAll', FunkinLua.Function_StopAll);
		
		set('add', function(obj:FlxBasic) PlayState.instance.add(obj));
		set('addBehindGF', function(obj:FlxBasic) PlayState.instance.addBehindGF(obj));
		set('addBehindDad', function(obj:FlxBasic) PlayState.instance.addBehindDad(obj));
		set('addBehindBF', function(obj:FlxBasic) PlayState.instance.addBehindBF(obj));
		set('insert', function(pos:Int, obj:FlxBasic) PlayState.instance.insert(pos, obj));
		set('remove', function(obj:FlxBasic, splice:Bool = false) PlayState.instance.remove(obj, splice));
		#end

		// 脚本库复用：importScript('util') 加载同 mod 的 scripting/libs/util.hx，
		// 库的顶层函数/变量并入当前脚本作用域，生命周期回调由所属脚本组广播。
		set('importScript', function(path:String):Dynamic {
			return importScript(path);
		});
	}

	/**
	 * 加载一个脚本库并返回其实例（脚本内 `importScript(path)` 的落地实现）。
	 *
	 * 路径解析（见 {@link resolveImportPath}）：
	 *  1. `mods/...` 开头 → 按仓库根解析（Android 走 `Paths.mods`）；
	 *  2. `./` / `../` 开头 → 相对当前脚本所在目录；
	 *  3. 其它 → 同 mod 的 `scripting/libs/<path>.hx` 优先，其次相对当前脚本目录。
	 *
	 * 语义：
	 *  - 库脚本加入**当前脚本组**，`create/update/...` 生命周期回调自动广播；
	 *  - 库的顶层函数/变量并入当前脚本作用域（**不覆盖**当前脚本已有名字）；
	 *  - 返回库的 HScript 实例：`lib.active = false` 停用、`lib.invoke('fn', [args])`
	 *    取原始返回值、`lib.get/set` 读写变量；
	 *  - 无脚本组（如 Lua `runHaxeCode`）时独立加载，随本脚本销毁。
	 *
	 * @return 库脚本实例；找不到/加载失败返回 null（已打日志）。
	 */
	@:keep public function importScript(path:String):Dynamic
	{
		var resolved:String = resolveImportPath(path);
		if (resolved == null)
		{
			trace('[HScript] importScript 找不到脚本库：' + path + '（来源：' + origin + '）');
			return null;
		}

		var lib:HScript = null;
		if (group != null)
		{
			// ScriptGroup.importLibrary 负责挂组、绑定宿主变量；Dynamic 调用避免模块环。
			try
			{
				lib = cast group.importLibrary(resolved);
			}
			catch (e:Dynamic)
			{
				trace('[HScript] importScript 挂组失败：' + resolved + ' —— ' + Std.string(e));
				lib = null;
			}
		}
		else
		{
			lib = loadStandaloneLibrary(resolved);
		}
		if (lib == null) return null;

		mergeLibraryScope(lib);
		return lib;
	}

	/**
	 * 调用库脚本里的函数并返回**原始返回值**（失败返回 null 并打日志）。
	 * 等价于 `call(...).returnValue`，但少一层 SCall 解包。
	 */
	@:keep public function invoke(func:String, ?args:Array<Dynamic>):Dynamic
	{
		if (func == null) return null;
		var r:Dynamic = call(func, args);
		if (r == null) return null;
		if (!r.succeeded && r.exceptions != null && r.exceptions.length > 0)
		{
			trace('[HScript] ' + func + ' 调用失败 @ ' + origin + '：' + Std.string(r.exceptions[0]));
			return null;
		}
		return r.returnValue;
	}

	/**
	 * 解析 `importScript` 的路径，返回实际存在的文件路径；找不到返回 null。
	 * 只读探盘，不加载。
	 */
	public function resolveImportPath(path:String):String
	{
		#if sys
		if (path == null) return null;
		var p:String = StringTools.replace(path.trim(), '\\', '/');
		if (p.length == 0) return null;

		var exts:Array<String> = ~/\.(hx|hscript|hsc|hxs)$/i.match(p)
			? ['']
			: ['.hx', '.hscript', '.hsc', '.hxs'];
		var candidates:Array<String> = [];

		if (isAbsolutePath(p) || p.startsWith('mods/'))
		{
			var base:String = p.startsWith('mods/') ? Paths.mods(p.substr(5)) : p;
			for (ext in exts) candidates.push(base + ext);
		}
		else if (p.startsWith('./') || p.startsWith('../'))
		{
			var dir:String = scriptDirectory();
			if (dir != null)
				for (ext in exts) candidates.push(haxe.io.Path.normalize(dir + '/' + p + ext));
		}
		else
		{
			var modRoot:String = modRootOf(origin);
			if (modRoot != null)
				for (ext in exts) candidates.push(modRoot + '/scripting/libs/' + p + ext);
			var dir:String = scriptDirectory();
			if (dir != null)
				for (ext in exts) candidates.push(haxe.io.Path.normalize(dir + '/' + p + ext));
		}

		for (c in candidates)
		{
			try
			{
				if (FileSystem.exists(c) && !FileSystem.isDirectory(c)) return c;
			}
			catch (e:Dynamic) {}
		}
		#end
		return null;
	}

	/** 当前脚本所在目录；无 origin 或 origin 不是路径时返回 null。 */
	function scriptDirectory():String
	{
		if (origin == null || origin.length == 0) return null;
		var p:String = StringTools.replace(origin, '\\', '/');
		var i:Int = p.lastIndexOf('/');
		return i > 0 ? p.substr(0, i) : null;
	}

	/** 从脚本路径推出 mod 根目录（`mods/<mod>`）。 */
	static function modRootOf(from:String):String
	{
		if (from == null) return null;
		var p:String = StringTools.replace(from, '\\', '/');
		var i:Int = p.indexOf('/scripting/');
		if (i >= 0) return p.substr(0, i);
		var m:Int = p.indexOf('mods/');
		if (m >= 0)
		{
			var rest:String = p.substr(m + 5);
			var slash:Int = rest.indexOf('/');
			return slash > 0 ? p.substr(0, m + 5 + slash) : p;
		}
		return null;
	}

	static inline function isAbsolutePath(p:String):Bool
	{
		return p.length > 0 && (p.charAt(0) == '/' || (p.length > 2 && p.charAt(1) == ':' && p.charAt(2) == '/'));
	}

	/** 无脚本组时的独立加载：执行、绑宿主变量、记入 standaloneLibraries。 */
	function loadStandaloneLibrary(path:String):HScript
	{
		var lib:HScript = null;
		try
		{
			lib = new HScript(null, path, false);
			lib.origin = path;
			try lib.execute() catch (e:Dynamic)
			{
				trace('[HScript] 脚本库执行失败 ' + path + '：' + Std.string(e));
				lib.destroy();
				return null;
			}
			var errs:Array<haxe.Exception> = @:privateAccess lib.parsingExceptions;
			if (errs != null && errs.length > 0)
			{
				trace('[HScript] 脚本库解析失败 ' + path + '：' + Std.string(errs[0]));
				lib.destroy();
				return null;
			}
		}
		catch (e:Dynamic)
		{
			trace('[HScript] 脚本库加载失败 ' + path + '：' + Std.string(e));
			if (lib != null) lib.destroy();
			return null;
		}

		// 与调用方共享宿主变量（runHaxeCode 场景没有 ScriptGroup.bindVars，这里手动补齐）
		var hostState:Dynamic = get('state');
		var hostGame:Dynamic = get('game');
		var hostApi:Dynamic = get('scripting');
		lib.set('state', hostState != null ? hostState : flixel.FlxG.state);
		lib.set('game', hostGame != null ? hostGame : PlayState.instance);
		if (hostApi != null) lib.set('scripting', hostApi);
		standaloneLibraries.push(lib);
		return lib;
	}

	/**
	 * 生命周期回调名：由 `ScriptGroup` 广播给库脚本**自身**，不再并入主脚本作用域，
	 * 否则主脚本没定义时会把库的 `update` 当自己的、与库广播叠加成双重调用。
	 */
	static final LIFECYCLE_NAMES:Array<String> = [
		'create', 'destroy', 'update', 'postUpdate', 'preUpdate',
		'stepHit', 'beatHit', 'sectionHit',
		'preStateSwitch', 'postStateSwitch',
		'postDraw', 'preDraw', 'postGameStart', 'preGameStart',
		'focusGained', 'focusLost', 'gameResized',
		'onCreate', 'onDestroy'
	];

	/** 把库的顶层函数/变量并入当前脚本作用域（已有名字不覆盖，宿主变量/生命周期回调不并）。 */
	function mergeLibraryScope(lib:HScript):Void
	{
		if (lib == null) return;
		var target:Map<String, Dynamic> = @:privateAccess interp.variables;
		var source:Map<String, Dynamic> = @:privateAccess lib.interp.variables;
		if (target == null || source == null) return;
		for (key in source.keys())
		{
			if (key == null || key == 'state' || key == 'game' || key == 'scripting' || key == 'this') continue;
			if (LIFECYCLE_NAMES.contains(key)) continue;
			if (!target.exists(key)) target.set(key, source.get(key));
		}
	}

	public function executeCode(?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):SCall
	{
		if (funcToRun == null) return null;

		if(!exists(funcToRun))
		{
			FunkinLua.luaTrace(origin + ' - No HScript function named: $funcToRun', false, false, FlxColor.RED);
			return null;
		}

		var callValue = call(funcToRun, funcArgs);
		if (!callValue.succeeded)
		{
			var e = callValue.exceptions[0];
			if (e != null)
			{
				var msg:String = e.toString();
				if(parentLua != null) msg = origin + ":" + parentLua.lastCalledFunction + " - " + msg;
				else msg = '$origin - $msg';
				FunkinLua.luaTrace(msg, parentLua == null, false, FlxColor.RED);
			}
			return null;
		}
		return callValue;
	}

	public function executeFunction(funcToRun:String = null, funcArgs:Array<Dynamic>):SCall
	{
		if (funcToRun == null)
			return null;

		return call(funcToRun, funcArgs);
	}

	public static function implement(funk:FunkinLua)
	{
		#if LUA_ALLOWED
		funk.addLocalCallback("runHaxeCode", function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
			var retVal:SCall = null;
			// TEMP-DIAG: FlxBackdrop 执行证据（验证后删）
			if (codeToRun != null && codeToRun.indexOf('FlxBackdrop') >= 0)
				trace('[RHX] FlxBackdrop code len=' + codeToRun.length + ' head=' + codeToRun.substr(0, 60).replace('
', ' '));
			#if (SScript >= "3.0.0")
			initHaxeModuleCode(funk, codeToRun);
			if(varsToBring != null)
			{
				for (key in Reflect.fields(varsToBring))
				{
					//trace('Key $key: ' + Reflect.field(varsToBring, key));
					funk.hscript.set(key, Reflect.field(varsToBring, key));
				}
			}
			retVal = funk.hscript.executeCode(funcToRun, funcArgs);
			if (retVal != null)
			{
				if(retVal.succeeded)
					return (retVal.returnValue == null || LuaUtils.isOfTypes(retVal.returnValue, [Bool, Int, Float, String, Array])) ? retVal.returnValue : null;

				var e = retVal.exceptions[0];
				if (e != null)
					FunkinLua.luaTrace(funk.hscript.origin + ":" + funk.lastCalledFunction + " - " + e, false, false, FlxColor.RED);
				return null;
			}
			else if (funk.hscript.returnValue != null)
				return funk.hscript.returnValue;
			#else
			FunkinLua.luaTrace("runHaxeCode: HScript isn't supported on this platform!", false, false, FlxColor.RED);
			#end
			return null;
		});
		
		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			#if (SScript >= "3.0.0")
			var callValue = funk.hscript.executeFunction(funcToRun, funcArgs);
			if (!callValue.succeeded)
			{
				var e = callValue.exceptions[0];
				if (e != null)
					FunkinLua.luaTrace('ERROR (${funk.hscript.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), false, false, FlxColor.RED);
				return null;
			}
			else
				return callValue.returnValue;
			#else
			FunkinLua.luaTrace("runHaxeFunction: HScript isn't supported on this platform!", false, false, FlxColor.RED);
			#end
		});
		// This function is unnecessary because import already exists in SScript as a native feature
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			var str:String = '';
			if(libPackage.length > 0)
				str = libPackage + '.';
			else if(libName == null)
				libName = '';

			var c = Type.resolveClass(str + libName);

			#if (SScript >= "3.0.3")
			if (c != null)
				SScript.globalVariables[libName] = c;
			#end

			#if (SScript >= "3.0.0")
			if (funk.hscript != null)
			{
				try {
					if (c != null)
						funk.hscript.set(libName, c);
				}
				catch (e:Dynamic) {
					FunkinLua.luaTrace(funk.hscript.origin + ":" + funk.lastCalledFunction + " - " + e, false, false, FlxColor.RED);
				}
			}
			#else
			FunkinLua.luaTrace("addHaxeLibrary: HScript isn't supported on this platform!", false, false, FlxColor.RED);
			#end
		});
		#end
	}

	#if (SScript >= "3.0.3")
	override public function destroy()
	{
		for (lib in standaloneLibraries)
		{
			if (lib == null) continue;
			try lib.destroy() catch (e:Dynamic) {}
		}
		standaloneLibraries = [];

		origin = null;
		parentLua = null;
		group = null;

		super.destroy();
	}
	#else
	public function destroy()
	{
		for (lib in standaloneLibraries)
		{
			if (lib == null) continue;
			try lib.destroy() catch (e:Dynamic) {}
		}
		standaloneLibraries = [];

		group = null;
		active = false;
	}
	#end
}

class CustomFlxColor
{
	public static var TRANSPARENT(default, null):Int = FlxColor.TRANSPARENT;
	public static var BLACK(default, null):Int = FlxColor.BLACK;
	public static var WHITE(default, null):Int = FlxColor.WHITE;
	public static var GRAY(default, null):Int = FlxColor.GRAY;

	public static var GREEN(default, null):Int = FlxColor.GREEN;
	public static var LIME(default, null):Int = FlxColor.LIME;
	public static var YELLOW(default, null):Int = FlxColor.YELLOW;
	public static var ORANGE(default, null):Int = FlxColor.ORANGE;
	public static var RED(default, null):Int = FlxColor.RED;
	public static var PURPLE(default, null):Int = FlxColor.PURPLE;
	public static var BLUE(default, null):Int = FlxColor.BLUE;
	public static var BROWN(default, null):Int = FlxColor.BROWN;
	public static var PINK(default, null):Int = FlxColor.PINK;
	public static var MAGENTA(default, null):Int = FlxColor.MAGENTA;
	public static var CYAN(default, null):Int = FlxColor.CYAN;

	public static function fromRGB(Red:Int, Green:Int, Blue:Int, Alpha:Int = 255):Int
	{
		return cast FlxColor.fromRGB(Red, Green, Blue, Alpha);
	}
	public static function fromRGBFloat(Red:Float, Green:Float, Blue:Float, Alpha:Float = 1):Int
	{	
		return cast FlxColor.fromRGBFloat(Red, Green, Blue, Alpha);
	}

	public static function fromHSB(Hue:Float, Sat:Float, Brt:Float, Alpha:Float = 1):Int
	{	
		return cast FlxColor.fromHSB(Hue, Sat, Brt, Alpha);
	}
	public static function fromHSL(Hue:Float, Sat:Float, Light:Float, Alpha:Float = 1):Int
	{	
		return cast FlxColor.fromHSL(Hue, Sat, Light, Alpha);
	}
	public static function fromString(str:String):Int
	{
		return cast FlxColor.fromString(str);
	}
}
#end