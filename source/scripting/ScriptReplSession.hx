package scripting;

import backend.Lang;
import hscript.Expr;
import hscript.Tools;
import hscript.Expr.ErrorDef;
import scripting.lua.HScript;

/** REPL 一次执行的结果。 */
typedef ScriptReplResult =
{
	/** true = 执行成功（value 可能是 null）。 */
	var ok:Bool;
	/** 成功时的返回值（最后一条语句的值）。 */
	var value:Dynamic;
	/** 失败时的错误描述（成功时为 null）。 */
	var error:String;
}

/**
 * REPL 会话：一个**长期存活**的 HScript 解释器实例。
 *
 * ## 为什么不能直接用 Interp.execute()
 *
 * hscript.Interp.execute() 每次调用开头都会 `locals = new Map()`（重置局部变量表），
 * 而且 EBlock 分支结束时会 `restore()` 撤销本块声明的 `var`。
 * 结果就是「上一行定义的变量」在下一行就消失了 —— 直接用它做 REPL 只能当一次性沙盒。
 *
 * 这里改走 `Interp.expr()` 并**逐条执行顶层语句**：
 *  - 不重置 locals → 上一行的 `var` 变量下一行仍能读到（`resolve()` 先查 locals 再查 variables）；
 *  - 不进 EBlock 分支 → 语句块结束时不会 `restore()` 撤销变量；
 *  - `interp.variables`（preset 注入的引擎类、`set()` 设进去的值）本来就跨调用保留。
 *
 * 代价：`Interp.declared` 只增不减（每个 `var` 留一条记录），长会话下是一点内存增长；
 * 会话本身是短生命周期的（关掉 REPL 即销毁），可以接受。
 *
 * ## 上下文
 *
 * 每次执行前重新绑定 `state` / `game` / `scripting`（界面可能已经换过），
 * 其余 preset（FlxG / PlayState / Paths / FlxSprite / Reflect / Type …）由 `scripting.lua.HScript.preset()` 注入。
 */
class ScriptReplSession
{
	/** 解释器实例（preset 已注入引擎类）。 */
	public var script:HScript;

	public function new()
	{
		// executeNow=false：构造期只做 preset，execute 由 REPL 自己逐行驱动。
		script = new HScript(null, '', false);
	}

	/** 绑定宿主变量（每次执行前刷新）。 */
	function bindHost():Void
	{
		if (script == null) return;
		script.set('state', FlxG.state);
		script.set('game', PlayState.instance);
		script.set('scripting', Scripting.api);
	}

	/**
	 * 执行一行代码。
	 *
	 * @param code 用户输入（可含多条语句，用 `;` 或换行分隔）。
	 * @return 成功时 value 是最后一条语句的值；失败时 error 是可读的错误描述。
	 */
	public function evaluate(code:String):ScriptReplResult
	{
		if (script == null) return {ok: false, value: null, error: Lang.tOr('repl.err.sessionClosed', '会话已关闭')};
		if (code == null) return {ok: false, value: null, error: Lang.tOr('repl.err.emptyInput', '空输入')};

		bindHost();
		try
		{
			var expr:Expr = script.parser.parseString(code, 'repl');
			var last:Dynamic = null;
			switch (Tools.expr(expr))
			{
				case EBlock(list):
					// 多条语句：逐条执行（不进 EBlock 分支 → 变量不会被 restore 撤销）
					for (stmt in list) last = runStatement(stmt);
				default:
					last = runStatement(expr);
			}
			return {ok: true, value: last, error: null};
		}
		catch (e:Dynamic)
		{
			return {ok: false, value: null, error: describeError(e)};
		}
	}

	/** 执行单条语句。Interp.expr() 评估单个表达式并返回值，不重置 locals。 */
	function runStatement(e:Expr):Dynamic
	{
		return script.interp.expr(e);
	}

	/** 销毁解释器。 */
	public function destroy():Void
	{
		if (script != null)
		{
			try script.destroy() catch (e:Dynamic) {}
			script = null;
		}
	}

	/**
	 * 把 hscript 抛出的错误转成人能看懂的文字。
	 *
	 * 本项目编译时定义了 `hscriptPos`（Project.xml 的 `<haxedef name="hscriptPos" />`），
	 * 所以 hscript 的 `Expr` 是带位置信息的结构体、`Error` 才是枚举，错误对象是 `Error` 类
	 * （`Std.string` 会输出 "repl:1: Unknown variable: x" 这种带行列的原文）。
	 * 这里按错误类型翻成中文，翻译不了就退回 hscript 原文。
	 */
	static function describeError(e:Dynamic):String
	{
		if (e == null) return Lang.tOr('repl.err.unknown', '（未知错误）');

		if (Std.isOfType(e, ErrorDef))
		{
			var err:ErrorDef = cast e;
			switch (err)
			{
				case EUnknownVariable(v): return Lang.tOr('repl.err.unknownVariable', '未知变量：') + v;
				case EInvalidAccess(f): return Lang.tOr('repl.err.missingField', '不存在的字段：') + f;
				case EInvalidOp(op): return Lang.tOr('repl.err.invalidOp', '非法运算符：') + op;
				case ECustom(msg): return msg;
				default:
			}
		}
		// 解析阶段错误（Parser 抛出的 Error 也可能是 hscript.Expr.Error 的子类型或其他）
		return Std.string(e);
	}
}
