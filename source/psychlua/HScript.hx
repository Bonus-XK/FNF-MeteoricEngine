package psychlua;

import flixel.FlxBasic;
import objects.Character;
import psychlua.FunkinLua;
import psychlua.CustomSubstate;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.0")
import tea.SScript;
class HScript extends SScript
{
	public var parentLua:FunkinLua;
	
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
		// Psych 0.7.3 模组兼容：`var x:Map<String, Dynamic> = [];` → `var x = __newMap();`
		// （字符串级替换，保留 var 名前缀；SScript 4.0.1 类型检查器/运行时均不认这种 Map 初始化）
		var fixed:Int = 0;
		var out:String = code;
		for (m in [':Map<String, Dynamic> = [];', ':Map<String, FlxBackdrop> = [];'])
		{
			if (out.indexOf(m) >= 0)
			{
				var cnt:Int = out.split(m).length - 1;
				out = out.split(m).join(' = __newMap();');
				fixed += cnt;
			}
		}
		return out;
	}

	public var origin:String;
	override public function new(?parent:FunkinLua, ?file:String)
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
		try execute() catch (e:Dynamic) { trace('HScript execute failed: ' + Std.string(e)); }
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
		origin = null;
		parentLua = null;

		super.destroy();
	}
	#else
	public function destroy()
	{
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