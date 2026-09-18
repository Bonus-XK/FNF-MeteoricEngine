package luagraph;

/**
 * 图 → Lua 代码生成器。
 *
 * 设计要点：
 *  1. 生成的文件分两区：顶部「受管区」（由本编辑器全量重写）与底部「自定义代码区」（永不覆盖）。
 *  2. 事件栈 → 真实 Psych 回调函数（函数名/参数逐条核对自 psychlua 注册原文）。
 *  3. 「等待 N 秒后继续」用 runTimer + 续接闭包实现，不阻塞主线程；为此会生成一个
 *     onTimerCompleted 调度器（仅当图中真的用了等待积木时才生成）。
 *  4. 生成前做静态校验（validate），错误级别会阻止保存，警告级别只提示。
 */
class LuaCodeGen
{
	public static inline var CUSTOM_BEGIN:String = '-- ===== 自定义代码区（重新生成不会覆盖，可在此手写）=====';
	public static inline var MANAGED_BEGIN:String = '-- ===== Meteoric LuaGraph 受管区（自动生成，手改会在下次保存时被覆盖）=====';

	static inline var INDENT:String = '\t';

	/** 生成上下文：收集自动声明的变量、告警与等待调度器需求。 */
	static function newCtx(doc:GDoc):Ctx
	{
		var c:Ctx = new Ctx();
		for (v in doc.vars)
			if (v.name != null && v.name.length > 0) c.declared.set(v.name, true);
		return c;
	}

	public static function generate(doc:GDoc):String
	{
		var ctx:Ctx = newCtx(doc);
		var body:Array<String> = [];

		// ---- 事件栈（每个栈 = 一个真实回调）----
		var hasWait:Bool = false;
		for (s in doc.stacks)
		{
			var def:BlockDef = LuaBlockDefs.byEvent(s.event);
			if (def == null || !def.hat)
			{
				ctx.warnings.push('未知的事件类型：' + s.event);
				continue;
			}
			// 帽块与普通积木共用同一套模板发射逻辑（$BODY$ / $ELSE$ 统一在此展开）
			emitTemplate(def.lua, new GBlock(s.event), def, 0, ctx, body, s.blocks);
			body.push('');
			if (containsWait(s.blocks)) hasWait = true;
		}

		// ---- 变量声明（含被引用但未声明的变量，自动补 0）----
		var varLines:Array<String> = [];
		for (v in doc.vars)
		{
			if (v.name == null || v.name.length == 0) continue;
			var n:String = sanitizeIdent(v.name, ctx);
			varLines.push('local ' + n + ' = ' + (v.value == null || v.value.length == 0 ? '0' : v.value));
		}

		var head:Array<String> = [];
		head.push('-- ============================================================');
		head.push('--  Meteoric Engine · Lua 图形化编程（积木块 → Lua）');
		head.push('--  脚本名称：' + (doc.name == null ? '' : doc.name));
		head.push('--  说明：本区块由编辑器全量重写；需要手写代码请用文件底部的自定义代码区。');
		head.push(MANAGED_BEGIN);
		head.push('-- ============================================================');
		head.push('');
		if (varLines.length > 0)
		{
			for (l in varLines) head.push(l);
			head.push('');
		}
		if (hasWait)
		{
			head.push('-- 「等待」积木的续接调度器（引擎在计时结束时回调 onTimerCompleted）');
			head.push('local me_waitCb = {}');
			head.push('function onTimerCompleted(tag, loops, loopsLeft)');
			head.push('\tlocal cb = me_waitCb[tag]');
			head.push('\tif cb ~= nil then');
			head.push('\t\tme_waitCb[tag] = nil');
			head.push('\t\tcb()');
			head.push('\tend');
			head.push('end');
			head.push('');
		}

		var out:Array<String> = [];
		for (l in head) out.push(l);
		for (l in body) out.push(l);
		out.push(CUSTOM_BEGIN);
		out.push(doc.custom == null ? '' : doc.custom.rtrim());
		out.push('');
		return out.join('\n');
	}

	/** 静态校验：返回问题清单（"错误：…" 会阻止保存，"警告：…" 只提示）。 */
	public static function validate(doc:GDoc):Array<String>
	{
		var issues:Array<String> = [];
		var ctx:Ctx = newCtx(doc);
		if (doc.stacks.length == 0) issues.push('错误：没有任何事件栈（无法生成脚本）');
		if (doc.isEmpty()) issues.push('错误：画布上还没有任何积木，请至少放一块到事件栈里');

		var tweenTags:Map<String, Int> = new Map();
		var waitTags:Map<String, Int> = new Map();
		for (s in doc.stacks)
		{
			var hdef:BlockDef = LuaBlockDefs.byEvent(s.event);
			if (hdef == null) issues.push('错误：未知的事件栈类型 “' + s.event + '”（可用：onCreate/onCreatePost/onUpdatePost/onBeatHit/onStepHit/onKeyPress/goodNoteHit/onSongStart/onDestroy）');
			else if (!hdef.hat) issues.push('错误：事件栈的帽子块不是事件积木（' + s.event + '）');
			checkChain(s.blocks, ctx, issues, tweenTags, waitTags);
		}
		if (containsWaitAny(doc))
		{
			if (doc.custom != null && doc.custom.indexOf('function onTimerCompleted') >= 0)
				issues.push('警告：自定义代码区里也定义了 onTimerCompleted —— 会覆盖"等待"积木的调度器，等待将失效');
		}
		for (w in ctx.warnings) issues.push(w);
		return issues;
	}

	/** 生成结果的行数（给状态栏用）。 */
	public static function countLines(text:String):Int
	{
		if (text == null) return 0;
		var n:Int = 1;
		for (i in 0...text.length)
			if (text.charCodeAt(i) == 10) n++;
		return n;
	}

	// ================= internal =================

	static function containsWait(blocks:Array<GBlock>):Bool
	{
		for (b in blocks)
		{
			if (b.type == 'flow_wait') return true;
			if (containsWait(b.body)) return true;
			if (containsWait(b.elseBody)) return true;
		}
		return false;
	}

	static function containsWaitAny(doc:GDoc):Bool
	{
		for (s in doc.stacks)
			if (containsWait(s.blocks)) return true;
		return false;
	}

	static function checkChain(blocks:Array<GBlock>, ctx:Ctx, issues:Array<String>, tweenTags:Map<String, Int>, waitTags:Map<String, Int>):Void
	{
		for (b in blocks)
		{
			var def:BlockDef = LuaBlockDefs.get(b.type);
			if (def == null)
			{
				issues.push('错误：未知积木类型 ' + b.type + '（图文件可能来自更新版本的编辑器）');
				continue;
			}
			for (p in def.params)
			{
				var v:String = b.get(p.name, p.def);
				switch (p.kind)
				{
					case KNum:
						var t:String = StringTools.trim(v);
						if (t.length == 0) issues.push('错误：【' + def.label + '】的「' + p.label + '」不能为空');
						else if (!isNumericExpr(t)) issues.push('错误：【' + def.label + '】的「' + p.label + '」必须是数字，当前是 “' + t + '”');
					case KExpr:
						if (StringTools.trim(v).length == 0) issues.push('警告：【' + def.label + '】的「' + p.label + '」为空，可能会生成无效 Lua');
					case KVar:
						if (StringTools.trim(v).length == 0) issues.push('错误：【' + def.label + '】未选择变量');
						else if (!ctx.declared.exists(v))
						{
							ctx.declared.set(v, true);
							issues.push('警告：变量 “' + v + '” 未在左侧声明，已自动在文件顶部补 local ' + sanitizeIdent(v, ctx) + ' = 0');
						}
					case KTag:
						if (StringTools.trim(v).length == 0) issues.push('错误：【' + def.label + '】的「' + p.label + '」不能为空');
					case KText, KEnum(_):
				}
			}
			// 注意：tw_cancel 是「引用」已有补间标签，不参与重复计数
			if (b.type == 'flow_wait' || (StringTools.startsWith(b.type, 'tw_') && b.type != 'tw_cancel'))
			{
				var tag:String = StringTools.trim(b.get('tag', ''));
				if (tag.length > 0)
				{
					var bag:Map<String, Int> = (b.type == 'flow_wait') ? waitTags : tweenTags;
					var n:Int = bag.exists(tag) ? bag.get(tag) : 0;
					bag.set(tag, n + 1);
					if (n == 1) issues.push('警告：' + (b.type == 'flow_wait' ? '计时器' : '补间') + '标签 “' + tag + '” 被用了多次，后一个会覆盖前一个');
				}
			}
			if (b.type == 'adv_call')
			{
				var fn:String = StringTools.trim(b.get('fname', ''));
				if (fn.length == 0) issues.push('错误：【调用任意 Lua 函数】缺少函数名');
				else if (!isIdentifier(fn)) issues.push('错误：函数名 “' + fn + '” 不是合法 Lua 标识符');
			}
			if (def.body && b.body.length == 0) issues.push('警告：【' + def.label + '】的内部还是空的');
			if (def.alt && b.elseBody.length == 0) issues.push('警告：【' + def.label + '】的「否则」分支是空的');
			checkChain(b.body, ctx, issues, tweenTags, waitTags);
			checkChain(b.elseBody, ctx, issues, tweenTags, waitTags);
		}
	}

	/**
	 * 生成一段积木序列。遇到「等待」时把剩余部分包进续接闭包（Scratch 语义：
	 * 等待期间本栈暂停，时间到后从下一块继续），其余情况顺序生成。
	 */
	static function emitChain(blocks:Array<GBlock>, depth:Int, ctx:Ctx, out:Array<String>):Void
	{
		var i:Int = 0;
		while (i < blocks.length)
		{
			var b:GBlock = blocks[i];
			var ind:String = tabs(depth);
			if (b.type == 'flow_wait')
			{
				var tag:String = cleanTag(b.get('tag', 'myWait'), ctx);
				var secs:String = num(b.get('secs', '1'));
				out.push(ind + '-- 等待 ' + secs + ' 秒后继续本栈（由 onTimerCompleted 调度）');
				out.push(ind + 'me_waitCb[\'' + tag + '\'] = function()');
				emitChain(blocks.slice(i + 1), depth + 1, ctx, out);
				out.push(ind + 'end');
				out.push(ind + 'runTimer(\'' + tag + '\', ' + secs + ', 1)');
				out.push(ind + 'return');
				return;
			}
			emitBlock(b, depth, ctx, out);
			i++;
		}
	}

	static function emitBlock(b:GBlock, depth:Int, ctx:Ctx, out:Array<String>):Void
	{
		var def:BlockDef = LuaBlockDefs.get(b.type);
		if (def == null) return;
		var ind:String = tabs(depth);

		// 特例：playSound 的标签可省略
		if (b.type == 'snd_playSound')
		{
			var sound:String = sq(b.get('sound', 'scrollMenu'));
			var vol:String = num(b.get('vol', '1'));
			var tag:String = StringTools.trim(b.get('tag', ''));
			if (tag.length == 0) out.push(ind + 'playSound(' + sound + ', ' + vol + ')');
			else out.push(ind + 'playSound(' + sound + ', ' + vol + ', ' + sq(tag) + ')');
			return;
		}

		emitTemplate(def.lua, b, def, depth, ctx, out, null);
	}

	/**
	 * 统一的模板发射：{p:参数} 替换 → 按行输出，$BODY$/$ELSE$ 处递归展开子序列。
	 * @param bodyOverride 事件帽块用：把整条事件栈当作它的 body 装进凹槽（模型里栈内积木与帽块同级）
	 */
	static function emitTemplate(tpl:String, b:GBlock, def:BlockDef, depth:Int, ctx:Ctx, out:Array<String>, ?bodyOverride:Array<GBlock>):Void
	{
		var text:String = subst(tpl, b, def, ctx);
		for (l in text.split('\n'))
		{
			if (l == '$$BODY$$')
			{
				var kids:Array<GBlock> = (bodyOverride != null) ? bodyOverride : b.body;
				if (kids.length == 0 && bodyOverride != null) out.push(tabs(depth + 1) + '-- （空栈：拖入积木以添加内容）');
				emitChain(kids, depth + 1, ctx, out);
			}
			else if (l == '$$ELSE$$')
			{
				emitChain(b.elseBody, depth + 1, ctx, out);
			}
			else if (l.length > 0)
			{
				out.push(tabs(depth) + l);
			}
		}
	}

	/** 模板替换：{p:name} → 参数值（按类型转义）。 */
	static function subst(tpl:String, b:GBlock, def:BlockDef, ctx:Ctx):String
	{
		var s:String = tpl;
		for (p in def.params)
		{
			var raw:String = b.get(p.name, p.def);
			var rep:String = raw;
			switch (p.kind)
			{
				// 模板里已经写成 '{p:x}'（单引号由模板负责），这里只转义字符串体，
				// 否则会出现 debugPrint('"TEXT"') 这种双重引号（资源名会被引号污染 → 查不到贴图）
				case KText:
					rep = esc(raw);
				case KTag:
					rep = esc(cleanTag(raw, ctx));
				case KNum:
					rep = num(raw);
				case KExpr, KVar:
					rep = StringTools.trim(raw);
				case KEnum(_):
					rep = raw;
			}
			s = StringTools.replace(s, '{p:' + p.name + '}', rep);
		}
		return s;
	}

	static function tabs(n:Int):String
	{
		var s:String = '';
		for (i in 0...n) s += INDENT;
		return s;
	}

	/** 数字参数：非法时先清洗成合法数字（校验阶段已经报过错）。 */
	static function num(v:String):String
	{
		var t:String = StringTools.trim(v);
		if (isNumericExpr(t)) return t;
		var f:Float = Std.parseFloat(t);
		if (Math.isNaN(f)) return '0';
		return Std.string(f);
	}

	static function isNumericExpr(s:String):Bool
	{
		if (s.length == 0) return false;
		var f:Float = Std.parseFloat(s);
		return !Math.isNaN(f);
	}

	static function isIdentifier(s:String):Bool
	{
		if (s.length == 0) return false;
		if (!isIdentStart(s.charCodeAt(0))) return false;
		for (i in 1...s.length)
			if (!isIdentChar(s.charCodeAt(i))) return false;
		return true;
	}

	static function isIdentStart(c:Int):Bool
	{
		return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
	}

	static function isIdentChar(c:Int):Bool
	{
		return isIdentStart(c) || (c >= 48 && c <= 57);
	}

	/** 标签清洗：Lua 标识符安全，并把替换过的位置记成告警。 */
	public static function sanitizeIdent(sIn:String, ?ctx:Ctx):String
	{
		var s:String = StringTools.trim(sIn);
		if (s.length == 0) return 'me_unnamed';
		var out:String = '';
		for (i in 0...s.length)
		{
			var c:Int = s.charCodeAt(i);
			if (isIdentChar(c)) out += s.charAt(i);
			else out += '_';
		}
		if (!isIdentStart(out.charCodeAt(0))) out = 'me_' + out;
		if (ctx != null && out != s) ctx.warnings.push('警告：名称 “' + s + '” 含非法字符，已改为 “' + out + '”');
		return out;
	}

	static function cleanTag(s:String, ctx:Ctx):String
	{
		return sanitizeIdent(s, ctx);
	}

	/** Lua 单引号字符串体转义（不含外层引号）。 */
	static function esc(sIn:String):String
	{
		var s:String = sIn == null ? '' : sIn;
		var out:String = '';
		for (i in 0...s.length)
		{
			var ch:String = s.charAt(i);
			switch (ch)
			{
				case '\\': out += '\\\\';
				case '\'': out += '\\\'';
				case '\n': out += '\\n';
				case '\r': out += '\\r';
				case '\t': out += '\\t';
				default: out += ch;
			}
		}
		return out;
	}

	/** 完整 Lua 单引号字符串字面量（供代码生成内部直接拼接使用）。 */
	static function sq(s:String):String
	{
		return "'" + esc(s) + "'";
	}
}

/** 生成/校验过程中的共享状态。 */
class Ctx
{
	public var declared:Map<String, Bool> = new Map();
	public var warnings:Array<String> = [];

	public function new() {}
}
