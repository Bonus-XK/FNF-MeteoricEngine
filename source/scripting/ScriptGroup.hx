package scripting;

import psychlua.HScript;
import sys.FileSystem;
import sys.io.File;

/**
 * 脚本组：把若干个 HScript 脚本当成一个整体来调用。
 *
 * 语义：
 *  - `addPath()` 逐个加载脚本；**单个文件解析失败不影响同组其它脚本**（失败的直接跳过）。
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

		var script:HScript = loadScript(path);
		if (script == null)
		{
			// 兜底：Psych 0.7.3 风格的 `:Map<String, Dynamic> = [];` 初始化在 SScript 4.0.1
			// 的类型检查器里不通过，preprocessScript 会把它改写成 `new Map()`。
			// 只有「路径形态失败」才走这条兜底，正常脚本不会走到。
			script = loadScriptCode(path);
			if (script == null) return false;
		}

		scripts.push(script);
		paths.push(path);
		return true;
	}

	/**
	 * 广播一个回调。脚本未定义该函数时静默跳过；单个脚本异常不影响其余脚本。
	 */
	public function call(func:String, ?args:Array<Dynamic>):Void
	{
		if (args == null) args = [];
		for (script in scripts)
		{
			if (script == null || !script.active) continue;
			// 先探测函数是否存在：缺失时直接 call 会在每帧刷错误日志。
			var fn:Dynamic = script.get(func);
			if (fn == null || !Reflect.isFunction(fn)) continue;
			try
			{
				var result = script.call(func, args);
				if (result != null && !result.succeeded && result.exceptions != null && result.exceptions.length > 0)
					Scripting.logError('$func 出错 @ ' + scriptPath(script) + '：' + firstLine(result.exceptions[0]));
			}
			catch (e:Dynamic)
			{
				Scripting.logError('$func 抛出异常 @ ' + scriptPath(script) + '：' + Std.string(e));
			}
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
			if (script == null || !script.active) continue;
			var fn:Dynamic = script.get(func);
			if (fn == null || !Reflect.isFunction(fn)) continue;
			try
			{
				var call = script.call(func, args);
				if (call != null && !call.succeeded && call.exceptions != null && call.exceptions.length > 0)
					Scripting.logError('$func 出错 @ ' + scriptPath(script) + '：' + firstLine(call.exceptions[0]));
				else if (call != null && call.returnValue != null && result == null)
					result = call.returnValue;
			}
			catch (e:Dynamic)
			{
				Scripting.logError('$func 抛出异常 @ ' + scriptPath(script) + '：' + Std.string(e));
			}
		}
		return result;
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

	/** 刷新每个脚本的宿主变量（`state` / `game` / `scripting`）。 */
	public function bindVars():Void
	{
		for (script in scripts)
		{
			if (script == null || !script.active) continue;
			script.set('state', parent != null ? parent : FlxG.state);
			script.set('game', PlayState.instance);
			script.set('scripting', Scripting);
		}
	}

	/** 先给脚本发 destroy 回调，再释放实例。 */
	public function destroy():Void
	{
		for (script in scripts)
		{
			if (script == null) continue;
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
		scripts = [];
		paths = [];
	}

	// ===== 内部 =====

	/**
	 * 路径形态加载：SScript 自己读文件（`global` 注册表按路径做 key，不留大字符串）。
	 */
	static function loadScript(path:String):HScript
	{
		var script:HScript = null;
		try
		{
			// executeNow=false：构造期只做 preset（注入引擎类），宿主变量随后注入再 execute。
			script = new HScript(null, path, false);
			script.origin = path;
			try script.execute() catch (e:Dynamic)
			{
				Scripting.logError('执行失败 @ ' + path + '：' + Std.string(e));
				script.destroy();
				return null;
			}
			var errs:Array<haxe.Exception> = @:privateAccess script.parsingExceptions;
			if (errs != null && errs.length > 0)
			{
				Scripting.logError('解析失败 @ ' + path + '：' + firstLine(errs[0]));
				script.destroy();
				return null;
			}
			// 文件读不到 / 内容为空时 SScript 会静默吞掉异常（script 为空串）→ 当作加载失败。
			if (script.script == null || script.script.length == 0)
			{
				Scripting.logError('脚本内容为空 @ ' + path);
				script.destroy();
				return null;
			}
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
	 * 代码形态加载：读文件 → preprocessScript（Map 初始化兼容）→ 交给 SScript 当代码串。
	 * 只在路径形态失败时兜底使用。
	 */
	static function loadScriptCode(path:String):HScript
	{
		var script:HScript = null;
		try
		{
			var code:String = HScript.preprocessScript(File.getContent(path));
			script = new HScript(null, code, false);
			script.origin = path;
			try script.execute() catch (e:Dynamic)
			{
				Scripting.logError('执行失败 @ ' + path + '：' + Std.string(e));
				script.destroy();
				return null;
			}
			var errs:Array<haxe.Exception> = @:privateAccess script.parsingExceptions;
			if (errs != null && errs.length > 0)
			{
				Scripting.logError('解析失败 @ ' + path + '：' + firstLine(errs[0]));
				script.destroy();
				return null;
			}
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
}
