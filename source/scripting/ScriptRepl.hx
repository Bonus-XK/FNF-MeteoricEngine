package scripting;

import backend.DesignTokens;
import backend.Lang;
import backend.Paths;
import backend.WheelScroll;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.input.FlxInput.FlxInputState;
import flixel.input.keyboard.FlxKey;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import objects.UIInputBox;
// ScriptReplResult 是 ScriptReplSession 模块的次级类型（typedef），同包也要显式 import 才在作用域内
import scripting.ScriptReplSession;

/** REPL 输出行。 */
typedef ScriptReplLine =
{
	/** 行文本。 */
	var text:String;
	/** 行类型：0 = 输入回显，1 = 结果，2 = 错误。 */
	var kind:Int;
}

/**
 * 游戏内 HScript REPL（F2 打开 / 关闭）。
 *
 * ## 它是什么
 *
 * 一个盖在当前界面上面的**控制台覆盖层**：底部一块面板，上面是输出区（输入回显 + 返回值 + 报错），
 * 下面是一行输入框。回车执行当前输入，↑ ↓ 滚动输出，ESC / F2 关闭。
 *
 * ## 为什么是「覆盖层」而不是子状态
 *
 *  - 子状态会**停掉父界面的 update**（FlxSubState 默认行为）→ 打开 REPL 就没法边玩边改；
 *  - 覆盖层挂在当前 State 上，游戏照常跑，改一个变量立刻能看到效果 —— 这才是「随时随地改」的意义。
 *
 * ## 渲染：专用相机
 *
 * 覆盖层自带一台 `FlxCamera`（zoom = 1、scroll = 0），并把自己加进 `FlxG.cameras`：
 *  - 画面固定在屏幕上，不跟着游戏相机滚动 / 缩放；
 *  - 后加的相机在显示列表里更靠上 → 天然盖在游戏画面之上；
 *  - 状态切换时 `FlxG.cameras.reset()` 会把这台相机一起清掉，所以状态切换时必须先关 REPL。
 *
 * ## 输入冲突
 *
 * 输入框用的是 `objects.UIInputBox`（隐形原生 TextField，拿到系统焦点，IME 可用）。
 * 原生输入框拿焦点时，Flixel 仍然会收到键盘事件 → 游戏会把打字当成按键操作。
 * 所以 REPL 打开期间会置 `Controls.inputBlocked = true`，让所有游戏输入查询一律返回 false；
 * REPL 自己的键盘操作直接读 `FlxG.keys`，不受影响。
 */
class ScriptRepl extends FlxGroup
{
	// ===== 布局常量（1280×720 基线） =====
	static final PANEL_X:Float = 40;
	static final PANEL_Y:Float = 280;
	static final PANEL_W:Float = 1200;
	static final PANEL_H:Float = 400;
	static final PAD:Float = 16;
	static final TITLE_Y:Float = 292;
	static final TITLE_SIZE:Int = 20;
	static final OUT_Y:Float = 322;
	static final OUT_LINE_H:Float = 22;
	static final OUT_SIZE:Int = 18;
	/** 同屏行数验算：OUT_Y + MAX_LINES*OUT_LINE_H = 322 + 11*22 = 564 ≤ INPUT_Y(572) ✓ */
	static final MAX_LINES:Int = 11;
	static final INPUT_Y:Float = 572;
	static final INPUT_H:Float = 46;
	static final HINT_Y:Float = 628;
	static final HINT_SIZE:Int = 16;
	/** 裁剪兜底的迭代硬上界（UI-DESIGN §2.3）。 */
	static final FIT_MAX_STEPS:Int = 64;
	/** 历史保留条数。 */
	static final HISTORY_MAX:Int = 200;

	// ===== 行类型 =====
	static final KIND_INPUT:Int = 0;
	static final KIND_RESULT:Int = 1;
	static final KIND_ERROR:Int = 2;

	/** 解释器会话。 */
	public var session:ScriptReplSession;

	/** 本覆盖层专用的相机（屏幕固定，不跟游戏相机滚）。 */
	public var cam:FlxCamera;

	var panel:FlxSprite;
	var titleText:FlxText;
	var promptText:FlxText;
	var hintText:FlxText;
	var inputBox:UIInputBox;
	var outLabels:Array<FlxText> = [];

	var lines:Array<ScriptReplLine> = [];
	var scrollOffset:Int = 0;
	var wheelScroll:WheelScroll = new WheelScroll();
	var themeListener:Void->Void;
	var mouseWasVisible:Bool = true;

	public function new()
	{
		super();

		// ---- 专用相机（屏幕固定 + 盖在游戏画面之上） ----
		cam = new FlxCamera();
		cam.bgColor.alpha = 0;
		FlxG.cameras.add(cam, false);
		cameras = [cam];

		// ---- 面板 ----
		panel = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 20);
		add(panel);

		// ---- 标题 ----
		titleText = new FlxText(PANEL_X + PAD, TITLE_Y, 0, '', TITLE_SIZE);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), TITLE_SIZE, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 1.5;
		titleText.wordWrap = false;
		titleText.textField.x = 1;
		titleText.textField.y = 1;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		// ---- 输出区（预创建可见行，随滚动复用） ----
		for (i in 0...MAX_LINES)
		{
			var lbl:FlxText = new FlxText(PANEL_X + PAD, OUT_Y + i * OUT_LINE_H, 0, '', OUT_SIZE);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), OUT_SIZE, 0xFF9A9AA8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.wordWrap = false;
			lbl.textField.x = 1;
			lbl.textField.y = 1;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			outLabels.push(lbl);
		}

		// ---- 输入提示符 + 输入框 ----
		promptText = new FlxText(PANEL_X + PAD, INPUT_Y + 10, 0, '>', 22);
		promptText.scrollFactor.set();
		promptText.setFormat(Paths.font('future.ttf'), 22, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		promptText.borderSize = 1.5;
		promptText.wordWrap = false;
		promptText.textField.x = 1;
		promptText.textField.y = 1;
		promptText.antialiasing = ClientPrefs.data.antialiasing;
		add(promptText);

		inputBox = new UIInputBox(PANEL_X + PAD + 18, INPUT_Y, Std.int(PANEL_W - PAD * 2 - 18), Std.int(INPUT_H), '', 20, 512);
		inputBox.onEnter = submit;
		add(inputBox);

		// ---- 底部提示 ----
		hintText = new FlxText(PANEL_X + PAD, HINT_Y, 0, '', HINT_SIZE);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), HINT_SIZE, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.wordWrap = false;
		hintText.textField.x = 1;
		hintText.textField.y = 1;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);

		// ---- 主题监听（面板是位图，主题变了要重绘） ----
		themeListener = function() refreshTheme();
		DesignTokens.addThemeListener(themeListener);

		session = new ScriptReplSession();

		mouseWasVisible = FlxG.mouse.visible;
		FlxG.mouse.visible = true;

		pushLine(KIND_INPUT, Lang.tOr('repl.welcome', 'REPL 已就绪 —— 输入 HScript 代码，回车执行；↑ ↓ 滚动输出；ESC 关闭。'));
		refreshOutput();
		updateTexts();

		// 打开即聚焦：原生输入框拿系统焦点 → 直接能打字（IME 也可用）
		inputBox.setNativeFocus(true);
	}

	// ==================== 执行 ====================

	function submit():Void
	{
		if (session == null) return;
		var code:String = inputBox.text;
		if (code == null) return;
		code = code.trim();
		if (code.length == 0) return;

		inputBox.text = '';
		pushLine(KIND_INPUT, '> ' + code);

		var res:ScriptReplResult = session.evaluate(code);
		if (res.ok)
		{
			if (res.value != null) pushLine(KIND_RESULT, formatValue(res.value));
		}
		else
		{
			pushLine(KIND_ERROR, Lang.tOr('repl.error', '错误') + '：' + res.error);
		}
		scrollToBottom();
	}

	/** 返回值的可读化。 */
	static function formatValue(v:Dynamic):String
	{
		if (v == null) return 'null';
		if (v is String) return '"' + Std.string(v) + '"';
		if (v is Bool || v is Int || v is Float) return Std.string(v);
		try
		{
			var cn:String = Type.getClassName(Type.getClass(v));
			if (cn != null) return cn;
		}
		catch (e:Dynamic) {}
		return Std.string(v);
	}

	function pushLine(kind:Int, text:String):Void
	{
		if (text == null) return;
		lines.push({text: text, kind: kind});
		while (lines.length > HISTORY_MAX) lines.shift();
		// 同步进脚本系统的日志缓冲（脚本管理器里能看到 REPL 的输出）
		Scripting.pushLog(text, kind == KIND_ERROR);
		refreshOutput();
	}

	function scrollToBottom():Void
	{
		scrollOffset = Std.int(Math.max(0, lines.length - MAX_LINES));
		refreshOutput();
	}

	// ==================== 显示 ====================

	function refreshOutput():Void
	{
		var total:Int = lines.length;
		var maxOffset:Int = Std.int(Math.max(0, total - MAX_LINES));
		if (scrollOffset > maxOffset) scrollOffset = maxOffset;
		if (scrollOffset < 0) scrollOffset = 0;

		for (i in 0...MAX_LINES)
		{
			var idx:Int = scrollOffset + i;
			var lbl:FlxText = outLabels[i];
			if (idx >= total)
			{
				lbl.visible = false;
				continue;
			}
			lbl.visible = true;
			var ln:ScriptReplLine = lines[idx];
			fitLine(lbl, ln.text, PANEL_W - PAD * 2);
			lbl.color = switch (ln.kind)
			{
				case KIND_INPUT: 0xFFD7D7E0;
				case KIND_RESULT: 0xFF9A9AA8;
				default: 0xFFFF8A8A;
			}
		}
	}

	/**
	 * 长文本裁剪（UI-DESIGN §2.3）：
	 * 先赋值再量宽度；省略号只在入口加一次；循环体内**只截不加**（长度严格递减）+ 迭代硬上界。
	 */
	function fitLine(lbl:FlxText, text:String, maxW:Float):Void
	{
		lbl.text = text;
		var fullW:Float = lbl.width;
		if (fullW <= maxW || text.length <= 5) return;

		var keep:Int = Math.floor(text.length * (maxW / fullW) * 0.92) - 1;
		if (keep < 4) keep = 4;
		if (keep > text.length - 1) keep = text.length - 1;
		var t:String = '…' + text.substr(text.length - keep);
		lbl.text = t;

		var step:Int = 0;
		while (lbl.width > maxW && step < FIT_MAX_STEPS && t.length > 4)
		{
			t = t.substr(1);
			lbl.text = t;
			step++;
		}
	}

	function updateTexts():Void
	{
		var stateName:String = Lang.tOr('repl.noState', '（无）');
		if (FlxG.state != null)
		{
			var cn:String = Type.getClassName(Type.getClass(FlxG.state));
			if (cn != null)
			{
				var dot:Int = cn.lastIndexOf('.');
				stateName = (dot >= 0) ? cn.substring(dot + 1) : cn;
			}
		}
		titleText.text = Lang.tOr('repl.title', '脚本 REPL') + '  ·  ' + Lang.tOr('repl.currentState', '当前界面') + '：' + stateName;
		hintText.text = Lang.tOr('repl.hint', '回车 执行 · ↑ ↓ 滚动输出 · ESC 关闭 · F2 开关');
	}

	function refreshTheme():Void
	{
		if (panel != null && panel.alive)
		{
			panel.pixels.fillRect(panel.pixels.rect, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(panel, 0, 0, PANEL_W, PANEL_H, 20, 20, DesignTokens.panelFill);
			FlxSpriteUtil.drawRoundRect(panel, 1, 1, PANEL_W - 2, PANEL_H - 2, 20, 20, FlxColor.TRANSPARENT,
				{color: DesignTokens.panelOutline, thickness: 1.5});
			panel.dirty = true;
		}
		if (titleText != null) titleText.color = DesignTokens.primary;
		if (promptText != null) promptText.color = DesignTokens.primary;
	}

	/** 磨砂圆角面板（主题色在函数体内解析，默认参数必须是编译期常量）。 */
	function makePanel(x:Float, y:Float, w:Float, h:Float, radius:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, DesignTokens.panelFill);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT,
			{color: DesignTokens.panelOutline, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	// ==================== 每帧 ====================

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// ESC 关闭（直接读 FlxG.keys：Controls 被 inputBlocked 挡住了）
		if (FlxG.keys != null && FlxG.keys.checkStatus(FlxKey.ESCAPE, FlxInputState.JUST_PRESSED))
		{
			Scripting.closeRepl();
			return;
		}

		// ↑ ↓ 滚动输出（游戏输入被挡住，这两个键归 REPL 用）
		if (FlxG.keys != null)
		{
			if (FlxG.keys.checkStatus(FlxKey.UP, FlxInputState.JUST_PRESSED))
			{
				scrollOffset++;
				refreshOutput();
			}
			if (FlxG.keys.checkStatus(FlxKey.DOWN, FlxInputState.JUST_PRESSED))
			{
				scrollOffset--;
				refreshOutput();
			}
		}

		// 滚轮滚动（WheelScroll 内部做 70ms / 2 格限速）
		var step:Int = wheelScroll.process(FlxG.mouse.wheel);
		if (step != 0)
		{
			scrollOffset -= step; // 滚轮向上（step<0）→ 看更早的行
			refreshOutput();
		}
	}

	// ==================== 收尾 ====================

	override function destroy():Void
	{
		if (themeListener != null)
		{
			DesignTokens.removeThemeListener(themeListener);
			themeListener = null;
		}

		// 副作用成对：关掉输入阻断、还原鼠标、摘掉相机
		Controls.inputBlocked = false;
		FlxG.mouse.visible = mouseWasVisible;

		if (cam != null)
		{
			if (FlxG.cameras != null && FlxG.cameras.list.contains(cam)) FlxG.cameras.remove(cam, true);
			cam = null;
		}

		if (session != null)
		{
			session.destroy();
			session = null;
		}

		if (Scripting.repl == this) Scripting.repl = null;

		super.destroy();
	}
}
