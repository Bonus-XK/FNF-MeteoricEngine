package cne;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
import backend.ClientPrefs;
import backend.Paths;
import psychlua.HScript;
import states.PlayState;
import tea.SScript;

/**
 * CNE 式脚本组（编程层）。
 *
 * 语义对齐 Codename Engine 的 `backend.scripting.ScriptPack`：
 *  - `addPath()` 逐条加载脚本；`call()` 向组内所有活动脚本广播；
 *  - `reload()` 重建组内全部脚本（原地热重载的底层原语）；
 *  - `destroy()` 先给脚本 `destroy` 回调、再释放 SScript 实例。
 *
 * 实现不复制 CNE 的 hscript 引擎：复用 Meteoric 的 `psychlua.HScript`
 * （SScript 4.0.1 + Meteoric 184 项 preset API），因此脚本能直接访问 Meteoric 引擎类。
 *
 * 与 CNE 的差异（必须知晓）：
 *  - CNE 把 state 设为 interp 的 `this`；SScript 不允许改写 `this`，
 *    因此这里注入 `state`（以及 PlayState 下的 `game`），脚本用 `state.xxx` 访问宿主。
 *  - `.pack` 合并脚本格式未移植；只支持 `.hx/.hscript/.hsc/.hxs` 独立文件。
 */
class ScriptPack
{
	public var scripts:Array<HScript> = [];
	public var paths:Array<String> = [];
	public var parent:Dynamic = null;

	public function new(?parent:Dynamic)
	{
		this.parent = parent;
	}

	/**
	 * 加载一个脚本文件。成功返回 true；文件不存在/解析出错/重复路径返回 false。
	 */
	public function addPath(path:String):Bool
	{
		if (path == null || path.length == 0 || paths.contains(path)) return false;
		if (!sys.FileSystem.exists(path)) return false;

		var script:HScript = null;
		try
		{
			// executeNow=false：先构造并注入 state，再显式 execute()。
			// 直接传路径而非代码串：SScript 的 doString 会对长字符串执行 FileSystem.exists，
			// 超长路径在 macOS 上可能抛错并静默吞掉整段脚本。
			//
			// classSupport 只在该文件确实定义 class 时才打开：
			// SScript 打开 classSupport 后会先按 EX 模式解析一次普通脚本，失败也会往
			// parsingExceptions 里塞一条 EX 异常；对普通脚本这是噪声，会误判成解析失败。
			var rawCode:String = sys.io.File.getContent(path);
			var wantsClasses:Bool = (ClientPrefs.data != null && ClientPrefs.data.cneScriptClasses)
				&& ~/\bclass[ \t]+[A-Za-z_][A-Za-z0-9_]*/.match(rawCode);

			var prevClassSupport:Null<Bool> = SScript.defaultClassSupport;
			SScript.defaultClassSupport = wantsClasses;
			script = new HScript(null, path, false);
			SScript.defaultClassSupport = prevClassSupport;

			script.origin = path;
			bindParent(script);
			script.execute();

			var parseErrors:Array<haxe.Exception> = @:privateAccess script.parsingExceptions;
			if (parseErrors != null && parseErrors.length > 0)
			{
				ProgrammingManager.log('script parse error: $path (' + Std.string(parseErrors[0]) + ')');
				script.destroy();
				return false;
			}
		}
		catch (e:Dynamic)
		{
			if (script != null) script.destroy();
			ProgrammingManager.log('script load error: $path - ' + Std.string(e));
			return false;
		}

		scripts.push(script);
		paths.push(path);
		return true;
	}

	/** 向组内所有活动脚本注入宿主引用（state；PlayState 下同时覆盖 game）与编程层入口 CNE。 */
	public function bindParent(script:HScript):Void
	{
		if (script == null) return;
		script.set('state', parent);
		script.set('CNE', ProgrammingManager);
		if (parent != null && Std.isOfType(parent, PlayState))
			script.set('game', parent);
	}

	/** 广播一个回调；脚本未定义该函数时静默跳过，单个脚本异常不会中断其余脚本。 */
	public function call(func:String, ?args:Array<Dynamic>):Void
	{
		if (args == null) args = [];
		for (script in scripts)
		{
			if (script == null || !script.active) continue;
			// 先探测函数是否存在：SScript 对缺失函数会返回 succeeded=false + "does not exist"，
			// 若直接 call 会在缺钩子的脚本上每帧刷错误日志（全局脚本的 postUpdate 就是典型）。
			var fn:Dynamic = script.get(func);
			if (fn == null || !Reflect.isFunction(fn)) continue;
			try
			{
				var result = script.call(func, args);
				if (result != null && !result.succeeded
					&& result.exceptions != null && result.exceptions.length > 0)
					ProgrammingManager.log('$func error in ' + script.origin + ': ' + Std.string(result.exceptions[0]));
			}
			catch (e:Dynamic)
			{
				ProgrammingManager.log('$func threw in ' + script.origin + ': ' + Std.string(e));
			}
		}
	}

	/** 重建组内全部脚本（保持路径与顺序）。 */
	public function reload():Void
	{
		var oldPaths:Array<String> = paths.copy();
		destroy();
		for (p in oldPaths) addPath(p);
	}

	/** 先给脚本 destroy 回调，再释放实例。 */
	public function destroy():Void
	{
		for (script in scripts)
		{
			if (script == null) continue;
			try { script.call('destroy', []); } catch (e:Dynamic) {}
			try { script.destroy(); } catch (e:Dynamic) {}
		}
		scripts = [];
		paths = [];
	}

	public function setParent(p:Dynamic):Void
	{
		parent = p;
		for (script in scripts) bindParent(script);
	}

	public function hasScripts():Bool
		return scripts.length > 0;
}
#end
