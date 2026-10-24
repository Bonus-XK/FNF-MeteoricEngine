package scripting;

import psychlua.HScript;
import sys.FileSystem;
import sys.io.File;

/**
 * 脚本组：把若干个 HScript 脚本当成一个整体来调用。
 *
 * 语义：
 *  - `addPath()` 逐个加载脚本；**单个文件解析失败不影响同组其它脚本**（失败的直接跳过）。
 *  - `importScript()` 加载的库脚本挂在 `libraries`：参与 call/callResult/bindVars 广播，
 *    随组销毁（主脚本先销毁、库按 import 倒序销毁）。
 *  - `call()` 向组内所有脚本广播；**脚本没定义该函数时静默跳过**
 *    （SScript 对缺失函数会返回 succeeded=false 并塞一条 "does not exist" 异常，
 *      直接 call 会在每帧刷错误日志 —— 全局脚本的 postUpdate 就是这种典型）。
 *  - 单个脚本抛异常**不会中断同组其它脚本**。
 *  - `destroy()` 先给每个脚本发 `destroy` 回调，再释放实例（顺序不能反：
 *    SScript.destroy() 会把 interp 清空，之后再 call 只会拿到 null）。
 */
class ScriptGroup
{
	/** 组内脚本实例（与 paths 一一对应）。 */
	public var scripts:Array<HScript> = [];

	/** 已加载脚本的路径（与 scripts 一一对应）。 */
	public var paths:Array<String> = [];

	/**
	 * 通过 `importScript` 加载的库脚本（不参与 paths / rebuild，随组一起销毁）。
	 * 参与 `call` / `callResult` / `bindVars` 广播 —— 与主脚本同生命周期。
	 */
	public var libraries:Array<HScript> = [];

	/**
	 * 宿主对象：状态脚本 = 所属 State / SubState；全局脚本 = null（`state` 变量每帧刷新为当前 State）。
	 */
	public var parent:Dynamic = null;

	public function new(?parent:Dynamic)
	{
		this.parent = parent;
	}

	/** 组内是否有脚本。 */
	public inline function hasScripts():Bool
		return scripts.length > 0;

	/**
	 * 加载一个脚本文件。
	 * @return true = 加载成功；false = 文件不存在 / 解析失败（已打日志）。
	 */
	public function addPath(path:String):Bool
	{
		if (path == null || path.length == 0) return false;
		if (paths.contains(path)) return false;
		if (!FileSystem.exists(path)) return false;

		var libMark:Int = libraries.length;
		var script:HScript = loadScript(path, this);
		if (script == null)
		{
			// 路径形态失败：回滚它执行期间已 import 的库，再走代码形态兜底重试。
			rollbackLibraries(libMark);
			// 兜底：Psych 0.7.3 风格的 `:Map<String, Dynamic> = [];` 初始化在 SScript 4.0.1
			// 的类型检查器里不通过，preprocessScript 会把它改写成 `new Map()`。
			// 只有「路径形态失败」才走这条兜底，正常脚本不会走到。
			script = loadScriptCode(path, this);
			if (script == null)
			{
				// 该脚本 execute 期间已 import 的库脚本一并回滚，避免半加载泄漏。
				rollbackLibraries(libMark);
				return false;
			}
		}

		scripts.push(script);
		paths.push(path);
		return true;
	}

	/**
	 * 加载一个库脚本并挂到本组（`HScript.importScript` 的落地实现）。
	 *
	 * 库脚本不写入 `paths`（rebuild 时由主脚本重新 import），但参与生命周期广播。
	 * @return 库脚本实例；加载失败返回 null。
	 */
	@:keep public function importLibrary(path:String):HScript
	{
		if (path == null || path.length == 0) return null;

		var libMark:Int = libraries.length;
		var lib:HScript = loadScript(path, this);
		if (lib == null)
		{
			rollbackLibraries(libMark);
			lib = loadScriptCode(path, this);
		}
		if (lib == null)
		{
			rollbackLibraries(libMark);
			return null;
		}

		bindOne(lib, parent);
		libraries.push(lib);
		return lib;
	}

	/** 回滚到指定库数量（加载失败的脚本/库在 execute 期间已挂进来的库一并释放）。 */
	function rollbackLibraries(mark:Int):Void
	{
		while (libraries.length > mark)
		{
			var orphan:HScript = libraries.pop();
			try orphan.destroy() catch (e:Dynamic) {}
		}
	}

	/**
	 * 广播一个回调。脚本未定义该函数时静默跳过；单个脚本异常不影响其余脚本。
	 */
	public function call(func:String, ?args:Array<Dynamic>):Void
	{
		if (args == null) args = [];
		for (script in scripts) callOne(script, func, args);
		for (lib in libraries) callOne(lib, func, args);
	}

	/** 单个脚本的回调广播（主脚本与库脚本共用）。 */
	static function callOne(script:HScript, func:String, args:Array<Dynamic>):Void
	{
		if (script == null || !script.active) return;
		// 先探测函数是否存在：缺失时直接 call 会在每帧刷错误日志。
		var fn:Dynamic = script.get(func);
		if (fn == null || !Reflect.isFunction(fn)) return;
		try
		{
			var result = script.call(func, args);
			if (result != null && !result.succeeded && result.exceptions != null && result.exceptions.length > 0)
				Scripting.logError('$func 出错 @ ' + scriptPath(script) + '：\n' + fullDetails(result.exceptions[0]));
		}
		catch (e:Dynamic)
		{
			Scripting.logError('$func 抛出异常 @ ' + scriptPath(script) + '：' + Std.string(e));
		}
	}

	/**
	 * 广播一个回调并**收集返回值**：返回第一个非 null 的返回值（没有则 null）。
	 * 用于「脚本用返回值表达意图」的场景（如 preStateSwitch 返回目标界面名）。
	 */
	public function callResult(func:String, ?args:Array<Dynamic>):Dynamic
	{
		if (args == null) args = [];
		var result:Dynamic = null;
		for (script in scripts)
		{
			var v:Dynamic = callOneResult(script, func, args);
			if (result == null && v != null) result = v;
		}
		for (lib in libraries)
		{
			var v:Dynamic = callOneResult(lib, func, args);
			if (result == null && v != null) result = v;
		}
		return result;
	}

	/** 单个脚本的回调调用并取返回值（callResult 用；异常/缺失返回 null）。 */
	static function callOneResult(script:HScript, func:String, args:Array<Dynamic>):Dynamic
	{
		if (script == null || !script.active) return null;
		var fn:Dynamic = script.get(func);
		if (fn == null || !Reflect.isFunction(fn)) return null;
		try
		{
			var call = script.call(func, args);
			if (call != null && !call.succeeded && call.exceptions != null && call.exceptions.length > 0)
			{
				Scripting.logError('$func 出错 @ ' + scriptPath(script) + '：' + firstLine(call.exceptions[0]));
				return null;
			}
			return call != null ? call.returnValue : null;
		}
		catch (e:Dynamic)
		{
			Scripting.logError('$func 抛出异常 @ ' + scriptPath(script) + '：' + Std.string(e));
			return null;
		}
	}

	/**
	 * 重建组内全部脚本（保持路径与顺序）。
	 * 注意：这是**破坏性**重建 —— 旧脚本先收 destroy 回调再释放。
	 * 需要「失败保留旧组」的语义请走 Scripting 侧的构建-替换两段式。
	 */
	public function rebuild():Void
	{
		var oldPaths:Array<String> = paths.copy();
		destroy();
		for (p in oldPaths) addPath(p);
	}

	/** 刷新每个脚本的宿主变量（`state` / `game` / `scripting`，脚本界面另有 `data`）。 */
	public function bindVars():Void
	{
		for (script in scripts) bindOne(script, parent);
		for (lib in libraries) bindOne(lib, parent);
	}

	/** 单个脚本的宿主变量绑定（主脚本与库脚本共用）。 */
	static function bindOne(script:HScript, parent:Dynamic):Void
	{
		if (script == null || !script.active) return;
		script.set('state', parent != null ? parent : FlxG.state);
		script.set('game', PlayState.instance);
		script.set('scripting', Scripting.api);
		// 脚本界面：把打开时传入的数据也注入脚本（脚本里可直接用 `data`）
		if (parent != null && Std.isOfType(parent, IScriptScreen))
		{
			script.set('data', Reflect.field(parent, 'data'));
		}
	}

	/** 先给脚本发 destroy 回调，再释放实例。主脚本先于库脚本（库函数在 destroy 里仍可调用）。 */
	public function destroy():Void
	{
		for (script in scripts) destroyOne(script);
		// 倒序释放库：父库（后 import）先于它 import 的子库，父库 destroy 里仍可调子库。
		var i:Int = libraries.length - 1;
		while (i >= 0)
		{
			destroyOne(libraries[i]);
			i--;
		}
		scripts = [];
		paths = [];
		libraries = [];
	}

	/** 单个脚本的销毁（先回调，再释放 —— 顺序不能反，SScript.destroy 会清空 interp）。 */
	static function destroyOne(script:HScript):Void
	{
		if (script == null) return;
		try
		{
			var fn:Dynamic = script.get('destroy');
			if (fn != null && Reflect.isFunction(fn)) script.call('destroy', []);
		}
		catch (e:Dynamic) {}
		try
		{
			script.destroy();
		}
		catch (e:Dynamic) {}
	}

	// ===== 内部 =====

	/**
	 * 路径形态加载：hscript Parser 解析失败直接抛异常，由外层 try/catch 捕获。
	 * 不再需要 parsingExceptions / script 字段检查。
	 */
	static function loadScript(path:String, ?owner:ScriptGroup):HScript
	{
		var script:HScript = null;
		try
		{
			var code:String = File.getContent(path);
			// executeNow=false：构造期只做 preset（注入引擎类），宿主变量随后注入。
			script = new HScript(null, path, false);
			script.origin = path;
			script.group = owner; // 必须在 execute 前：顶层 importScript 要挂到同组
			script.executeCodeString(code, path);
		}
		catch (e:Dynamic)
		{
			Scripting.logError('加载失败 @ ' + path + '：' + Std.string(e));
			if (script != null) script.destroy();
			return null;
		}
		return script;
	}

	/**
	 * 代码形态加载：读文件 → preprocessScript（Map 初始化兼容）→ executeCodeString 执行。
	 * 只在路径形态失败时兜底使用。
	 */
	static function loadScriptCode(path:String, ?owner:ScriptGroup):HScript
	{
		var script:HScript = null;
		try
		{
			var code:String = HScript.preprocessScript(File.getContent(path));
			script = new HScript(null, code, false);
			script.origin = path;
			script.group = owner; // 必须在 execute 前：顶层 importScript 要挂到同组
			script.executeCodeString(code, path);
		}
		catch (e:Dynamic)
		{
			Scripting.logError('加载失败 @ ' + path + '：' + Std.string(e));
			if (script != null) script.destroy();
			return null;
		}
		return script;
	}

	static inline function scriptPath(script:HScript):String
		return script.origin != null ? script.origin : '(未知)';

	/** 异常只取首行，避免整段堆栈刷屏。 */
	public static inline function firstLine(e:haxe.Exception):String
	{
		if (e == null) return '(未知错误)';
		var msg:String = e.message != null ? e.message : Std.string(e);
		var idx:Int = msg.indexOf('\n');
		return idx > 0 ? msg.substr(0, idx) : msg;
	}

	/** 异常的完整信息（首行 + 堆栈）—— 排查脚本问题要用它，首行往往不够。 */
	public static function fullDetails(e:haxe.Exception):String
	{
		if (e == null) return '(未知错误)';
		try
		{
			var d:String = e.details();
			if (d != null && d.length > 0) return d;
		}
		catch (ex:Dynamic) {}
		return firstLine(e);
	}
}
