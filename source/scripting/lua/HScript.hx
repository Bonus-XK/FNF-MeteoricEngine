package scripting.lua;

import flixel.FlxBasic;
import objects.Character;
import scripting.lua.FunkinLua;
import scripting.lua.CustomSubstate;
import hscript.Interp;
import hscript.Parser;
import hscript.Expr;
import hscript.Expr.Error;
import scripting.ModClassLoader;
import ex.InterpEx;
#if sys
import sys.FileSystem;
#end

#if (HSCRIPT_ALLOWED)
typedef SCall = {
	var succeeded:Bool;
	var exceptions:Array<Dynamic>;
	var returnValue:Dynamic;
	var calledFunction:String;
}

class HScript
{
	public var interp:InterpEx;
	public var parser:Parser;
	public var expr:Expr;
	public var parentLua:FunkinLua;

	/** 所属脚本组（由 `ScriptGroup` 在 execute 前注入；`runHaxeCode` 等无组场景为 null）。 */
	public var group:Dynamic = null;

	/** 无组场景下通过 `importScript` 加载的库脚本（随本脚本一起销毁）。 */
	public var standaloneLibraries:Array<HScript> = [];

	public var origin:String;

	/** 全局脚本注册表：按文件路径缓存 HScript 实例（替代 SScript.global）。 */
	public static var globalScripts:Map<String, HScript> = new Map();

	/** 脚本是否处于激活状态。 */
	public var active:Bool = true;

	/** 最后一次执行的返回值。 */
	public var returnValue:Dynamic = null;

	public static function initHaxeModule(parent:FunkinLua)
	{
		if(parent.hscript == null)
		{
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent);
		}
	}

	public static function initHaxeModuleCode(parent:FunkinLua, code:String)
	{
		var hs:HScript = try parent.hscript catch (e) null;
		var cleaned:String = preprocessScript(code);
		if(hs == null)
		{
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent, cleaned);
		}
		else
		{
			hs.executeCodeString(cleaned);
		}
	}

	/**
	 * Psych 0.7.3 模组兼容：把 `var x:Map<String, Dynamic> = [];` 改写为 `new Map()`。
	 * hscript 的类型检查器对空数组初始化 Map 也有类似限制，保留此预处理。
	 */
	public static function preprocessScript(code:String):String
	{
		if (code == null || code.length == 0) return code;
		var out:String = code;
		out = ~/:[ \t]*Map[ \t]*<[^>]*>[ \t]*=[ \t]*\[\][ \t]*;/g.replace(out, ' = new Map();');
		return out;
	}

	public function new(?parent:FunkinLua, ?file:String, ?executeNow:Bool = true)
	{
		if (file == null) file = '';
		parentLua = parent;
		if (parent != null) origin = parent.scriptName;
		if (file != null && file.length > 0) origin = file;

		interp = new InterpEx(null, false);
		parser = new Parser();
		parser.allowJSON = parser.allowMetadata = parser.allowTypes = true;

		// Meteoric: 导入/using/包回调，将导入信息注册到 Interp，供 resolve() 查找
		parser.onImport = function(path:Array<String>, star:Bool, name:Null<String>) {
			interp.registerImport(path, star, name);
		};
		parser.onUsing = function(path:Array<String>) {
			interp.registerUsing(path);
		};
		parser.onPackage = function(path:Array<String>) {
			interp.registerPackage(path);
		};
		// Meteoric: 顶层 class 声明注册到全局脚本类表，供 new 实例化
		parser.onClass = function(c:Dynamic) {
			var decl = {
				imports: new Map<String, Array<String>>(),
				pkg: null,
				name: c.name,
				params: c.params,
				meta: c.meta,
				isPrivate: c.isPrivate,
				isExtern: c.isExtern,
				extend: c.extend,
				implement: c.implement,
				fields: c.fields
			};
			InterpEx.registerScriptClass(decl);
		};

		preset();

		if (executeNow && file != null && file.length > 0)
		{
			try executeFromFile(file) catch (e:Dynamic) { trace('HScript execute failed: ' + Std.string(e)); }
		}
	}

	private function executeFromFile(path:String):Void
	{
		#if sys
		var code:String = null;
		try code = sys.io.File.getContent(path) catch(e) { trace('Error reading $path: ${Std.string(e)}'); return; }
		executeCodeString(code, path);
		#end
	}

	/** 从字符串执行 HScript 代码（解析 + 运行）。 */
	public function executeCodeString(code:String, ?origin:String = null):Void
	{
		if (origin != null) this.origin = origin;
		try {
			var e:Expr = parser.parseString(code, this.origin);
			interp.execute(e);
		} catch(err:Dynamic) {
			trace('HScript execute failed: ' + Std.string(err));
		}
	}

	/** 执行先前解析的 expr（兼容旧 API）。 */
	public function execute():Void
	{
		if (expr != null) {
			try { interp.execute(expr); } catch(err:Dynamic) { trace('HScript execute failed: ' + Std.string(err)); }
		}
	}

	public function set(name:String, value:Dynamic):Void
	{
		interp.variables.set(name, value);
	}

	public function get(name:String):Dynamic
	{
		return interp.variables.get(name);
	}

	public function exists(name:String):Bool
	{
		return interp.variables.exists(name) && Reflect.isFunction(interp.variables.get(name));
	}

	public function call(func:String, ?args:Array<Dynamic>):SCall
	{
		var result:SCall = { succeeded: false, exceptions: [], returnValue: null, calledFunction: func };
		if (args == null) args = [];

		var f:Dynamic = interp.variables.get(func);
		if (f == null || !Reflect.isFunction(f)) {
			result.exceptions.push('No function named: ' + func);
			return result;
		}

		try {
			result.returnValue = Reflect.callMethod(null, f, args);
			result.succeeded = true;
		} catch(err:Dynamic) {
			result.exceptions.push(err);
		}
		return result;
	}

	public function destroy():Void
	{
		for (lib in standaloneLibraries) {
			if (lib == null) continue;
			try lib.destroy() catch(e:Dynamic) {}
		}
		standaloneLibraries = [];
		origin = null;
		parentLua = null;
		group = null;
		active = false;
	}

	@:keep public function importScript(path:String):Dynamic
	{
		var resolved:String = resolveImportPath(path);
		if (resolved == null) {
			trace('[HScript] importScript 找不到脚本库：' + path + '（来源：' + origin + '）');
			return null;
		}

		var lib:HScript = null;
		if (group != null) {
			try {
				lib = cast group.importLibrary(resolved);
			} catch(e:Dynamic) {
				trace('[HScript] importScript 挂组失败：' + resolved + ' —— ' + Std.string(e));
				lib = null;
			}
		} else {
			lib = loadStandaloneLibrary(resolved);
		}
		if (lib == null) return null;

		mergeLibraryScope(lib);
		return lib;
	}

	@:keep public function invoke(func:String, ?args:Array<Dynamic>):Dynamic
	{
		if (func == null) return null;
		var r:Dynamic = call(func, args);
		if (r == null) return null;
		if (!r.succeeded && r.exceptions != null && r.exceptions.length > 0) {
			trace('[HScript] ' + func + ' 调用失败 @ ' + origin + '：' + Std.string(r.exceptions[0]));
			return null;
		}
		return r.returnValue;
	}

	public function resolveImportPath(path:String):String
	{
		#if sys
		if (path == null) return null;
		var p:String = StringTools.replace(path.trim(), '\\', '/');
		if (p.length == 0) return null;

		var exts:Array<String> = ~/\.(hx|hscript|hsc|hxs)$/i.match(p) ? [''] : ['.hx', '.hscript', '.hsc', '.hxs'];
		var candidates:Array<String> = [];

		if (isAbsolutePath(p) || p.startsWith('mods/')) {
			var base:String = p.startsWith('mods/') ? Paths.mods(p.substr(5)) : p;
			for (ext in exts) candidates.push(base + ext);
		}
		else if (p.startsWith('./') || p.startsWith('../')) {
			var dir:String = scriptDirectory();
			if (dir != null)
				for (ext in exts) candidates.push(haxe.io.Path.normalize(dir + '/' + p + ext));
		}
		else {
			var modRoot:String = modRootOf(origin);
			if (modRoot != null)
				for (ext in exts) candidates.push(modRoot + '/scripting/libs/' + p + ext);
			var dir:String = scriptDirectory();
			if (dir != null)
				for (ext in exts) candidates.push(haxe.io.Path.normalize(dir + '/' + p + ext));
		}

		for (c in candidates) {
			try {
				if (FileSystem.exists(c) && !FileSystem.isDirectory(c)) return c;
			} catch(e:Dynamic) {}
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
		try {
			lib = new HScript(null, path, false);
			lib.origin = path;
			var code:String = sys.io.File.getContent(path);
			lib.executeCodeString(code, path);
			// hscript Parser 解析失败会抛异常，能走到这里说明解析已通过
		} catch(e:Dynamic) {
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

	/** 生命周期回调名：由 `ScriptGroup` 广播给库脚本**自身**，不再并入主脚本作用域。 */
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
		var target:Map<String, Dynamic> = interp.variables;
		var source:Map<String, Dynamic> = lib.interp.variables;
		if (target == null || source == null) return;
		for (key in source.keys()) {
			if (key == null || key == 'state' || key == 'game' || key == 'scripting' || key == 'this') continue;
			if (LIFECYCLE_NAMES.contains(key)) continue;
			if (!target.exists(key)) target.set(key, source.get(key));
		}
	}

	public function executeCode(?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):SCall
	{
		if (funcToRun == null) return null;
		if(!exists(funcToRun)) {
			FunkinLua.luaTrace(origin + ' - No HScript function named: $funcToRun', false, false, FlxColor.RED);
			return null;
		}
		return call(funcToRun, funcArgs);
	}

	public function executeFunction(funcToRun:String = null, funcArgs:Array<Dynamic>):SCall
	{
		if (funcToRun == null) return null;
		return call(funcToRun, funcArgs);
	}

	public static function implement(funk:FunkinLua)
	{
		#if LUA_ALLOWED
		funk.addLocalCallback("runHaxeCode", function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
			var retVal:SCall = null;
			if (codeToRun != null && codeToRun.indexOf('FlxBackdrop') >= 0)
				trace('[RHX] FlxBackdrop code len=' + codeToRun.length + ' head=' + codeToRun.substr(0, 60).replace('\n', ' '));
			// ⚠ macOS 平台保护：sprite 级 shader 赋值会让渲染层原生崩溃。
			// 2026-10-31 实测：macOS + flixel 6.2 + 当前 openfl 下，只要执行
			// `spr.shader = <任意 shader 或 null>`（包括极简 `void main(){gl_FragColor=vec4(1,0,0,1);}`）
			// 就在渲染时 SIGSEGV，与 shader 内容无关；应用层无法 try/catch（驱动直接 abort）。
			// FlxSprite.shader 是无 setter 的普通字段，子类也无法遮蔽拦截，
			// 因此只能在「执行 HScript 代码」这一层做过滤 —— 让模组无需改写，
			// 只是这些 sprite shader 特效不显示（相机 filter 路径不受影响，仍可用）。
			#if mac
			if (codeToRun != null && codeToRun.indexOf('.shader') >= 0)
			{
				trace('[runHaxeCode] macOS 跳过含 sprite.shader 的代码（渲染层会崩）| '
					+ funk.scriptName);
				return null;
			}
			#end
			// 定位 SEGV：runHaxeCode 执行前后写日志，崩溃时日志最后一条即肇事代码
			#if sys
			try {
				var _f = sys.io.File.append('/tmp/meteoric_rhx.log', false);
				_f.writeString('[RHX-before] ' + funk.scriptName + ' | '
					+ StringTools.replace(codeToRun == null ? 'null' : codeToRun.substr(0, 90), '\n', ' ') + '\n');
				_f.close();
			} catch (e:Dynamic) {}
			#end
			initHaxeModuleCode(funk, codeToRun);
			if(varsToBring != null) {
				for (key in Reflect.fields(varsToBring)) {
					funk.hscript.set(key, Reflect.field(varsToBring, key));
				}
			}
			retVal = funk.hscript.executeCode(funcToRun, funcArgs);
			#if sys
			try {
				var _f2 = sys.io.File.append('/tmp/meteoric_rhx.log', false);
				_f2.writeString('[RHX-after ] ' + funk.scriptName + '\n');
				_f2.close();
			} catch (e:Dynamic) {}
			#end
			if (retVal != null) {
				if(retVal.succeeded)
					return (retVal.returnValue == null || LuaUtils.isOfTypes(retVal.returnValue, [Bool, Int, Float, String, Array])) ? retVal.returnValue : null;
				var e = retVal.exceptions[0];
				if (e != null)
					FunkinLua.luaTrace(funk.hscript.origin + ":" + funk.lastCalledFunction + " - " + e, false, false, FlxColor.RED);
				return null;
			}
			else if (funk.hscript.returnValue != null)
				return funk.hscript.returnValue;
			return null;
		});

		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			var callValue = funk.hscript.executeFunction(funcToRun, funcArgs);
			if (!callValue.succeeded) {
				var e = callValue.exceptions[0];
				if (e != null)
					FunkinLua.luaTrace('ERROR (${funk.hscript.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), false, false, FlxColor.RED);
				return null;
			}
			else return callValue.returnValue;
		});

		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			var str:String = '';
			if(libPackage.length > 0) str = libPackage + '.';
			else if(libName == null) libName = '';
			var c = Type.resolveClass(str + libName);
			if (funk.hscript != null) {
				try {
					if (c != null) funk.hscript.set(libName, c);
				} catch(e:Dynamic) {
					FunkinLua.luaTrace(funk.hscript.origin + ":" + funk.lastCalledFunction + " - " + e, false, false, FlxColor.RED);
				}
			}
		});
		#end
	}

	/**
	 * 脚本可见的编程层 API 注入。
	 *
	 * 所有 `set('名', 值)` 落到 `interp.variables`，脚本里可直接用 `FlxG`、`Paths`、`FlxSprite` 等。
	 * release 构建开 `--dce full` 时，只被脚本反射调用的方法会被裁掉，
	 * 所以引擎类本身作为值注入（`set('FlxG', flixel.FlxG)`），不依赖 `@:keep`。
	 */
	public function preset():Void
	{
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

		// ── SeiunEngine 融合变量 ──
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
		set('hscriptVersion', 'hscript 2.7.0');
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);
		// Meteoric HScript 增强：正则与状态切换
		// `var reg = Reg('[A-Z0-9._%-]+', 'i');` —— 替代 SScript 不支持的 `~/.../i` 语法级正则。
		set('Reg', function(pattern:String, ?flags:String) return new EReg(pattern, flags));
		// `switchState(new FreeplayState())` —— 直接切换游戏状态，等价于 `MusicBeatState.switchState`。
		set('switchState', function(state:Dynamic) backend.MusicBeatState.switchState(state));

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
		set('createGlobalCallback', function(name:String, func:Dynamic)
		{
			#if LUA_ALLOWED
			for (script in PlayState.instance.luaArray)
			{
				if(script == null || script.lua == null || script.closed) continue;
				var _gt:Int = 0;
				try { _gt = Lua.gettop(script.lua); } catch (e:Dynamic) { continue; }
				if (_gt < 0) continue;
				Lua_helper.add_callback(script.lua, name, func);
			}
			#end
			FunkinLua.customFunctions.set(name, func);
		});

		set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null) {
			if(funk == null) funk = parentLua;

			if(parentLua != null) funk.addLocalCallback(name, func);
			else FunkinLua.luaTrace('createCallback ($name): 3rd argument is null', false, false, FlxColor.RED);
		});

		set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			try {
				var str:String = '';
				if(libPackage.length > 0) str = libPackage + '.';

				set(libName, Type.resolveClass(str + libName));
			}
			catch (e:Dynamic) {
				var msg:String = e.message.substr(0, e.message.indexOf('\n'));
				if(parentLua != null) {
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
		set('Function_StopLua', FunkinLua.Function_StopLua);
		set('Function_StopHScript', FunkinLua.Function_StopHScript);
		set('Function_StopAll', FunkinLua.Function_StopAll);

		set('add', function(obj:FlxBasic) PlayState.instance.add(obj));
		set('addBehindGF', function(obj:FlxBasic) PlayState.instance.addBehindGF(obj));
		set('addBehindDad', function(obj:FlxBasic) PlayState.instance.addBehindDad(obj));
		set('addBehindBF', function(obj:FlxBasic) PlayState.instance.addBehindBF(obj));
		set('insert', function(pos:Int, obj:FlxBasic) PlayState.instance.insert(pos, obj));
		set('remove', function(obj:FlxBasic, splice:Bool = false) PlayState.instance.remove(obj, splice));

		// 脚本库复用：importScript('util') 加载同 mod 的 scripting/libs/util.hx
		set('importScript', function(path:String):Dynamic {
			return importScript(path);
		});
	}
}
#end

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