package options;

import backend.DesignTokens;
import backend.Paths;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;

/**
 * 单界面设置的**左侧分区栏**（侧边栏）。
 *
 * 用途：把原本「一级分类列表 → 打开二级整屏页」的两级结构，换成「一个界面 + 侧栏切分区」。
 *
 * 滚动（本轮的最终形态 = **页面滚动**，不是"一格一项"，也不是逐像素连续滚动）：
 *  - 滚轮一格 = **翻一整页**（`ROWS_VISIBLE` 项，桌面 9 项）——列表尾自然夹取，不越界、不回卷；
 *    这样"滚整个栏"最多两下就到底，符合"像电脑一样翻页"的直觉。
 *  - 翻页过程仍然**有滑动动画**：窗口位置用**时间插值**逐帧 `FlxMath.lerp(..., elapsed * SCROLL_LERP)`
 *    （与 Freeplay/MainMenu 同款手感，见 meteoric-design「滚动（时间插值）」），掉帧时手感一致、不跳变。
 *  - 键盘 ↑↓ / 长按重复仍是一行一行；点选仍是单击直达（两者的窗口跟随由同一套插值负责）。
 *  - 移动端：触屏拖动会合成滚轮事件，一拖就是几十个"格"，所以移动端**一格 = 一行**（浏览手感），
 *    翻页只留给桌面滚轮。
 *  - 行不越列表带（面板没有裁剪遮罩）：靠近上下边缘的行按位置淡出隐藏，避免文字压到标题。
 *
 * 契约（meteoric-system）：
 *  - 绘制层级：面板 → 选中高亮条 → 行文字（高亮条必须在行文字**之前** add）。
 *  - 颜色全部走 DesignTokens（panelFill/panelOutline/rowHighlight），禁止字面量。
 *  - 面板/圆角一次画好，update() 里零绘制（只更新位置/文本/透明度，不建对象）；不做 tween 队列。
 *  - 三套输入：键盘（宿主转发 ↑↓，含长按重复）、滚轮（本类的 addWheel）、鼠标/触控点选（hitIndex）。
 *    本组件**不做**输入读取，只暴露状态与入口 —— 输入策略属于宿主（焦点/音效/防误触）。
 *
 * 几何（1280×720 基准，已核算）：
 *  面板 40,70,230,570；标题 y 100；行距 50（移动端 56，满足触控红线）、可见 9 行（移动端 8）；
 *  列表带 166..616 仍在面板内（70..640）；文本左缘 72；高亮条 202×42 圆角 12。
 */
class SettingsRail extends FlxGroup
{
	public static final PANEL_X:Float = 40;
	public static final PANEL_Y:Float = 70;
	public static final PANEL_W:Float = 230;
	public static final PANEL_H:Float = 570;

	static final TITLE_X:Float = PANEL_X + 32;
	static final TITLE_Y:Float = PANEL_Y + 30;
	static final LIST_Y:Float = PANEL_Y + 96;
	// 行距/可见行：移动端必须 ≥56px 触控目标（meteoric-mobile 红线），桌面 50 更紧凑
	static final ROW_GAP:Float = #if mobile 56 #else 50 #end;
	static final ROWS_VISIBLE:Int = #if mobile 8 #else 9 #end;
	/** 多画 2 行承接滑动中的半行（按位置隐藏，不新增可见元素） */
	static final ROWS_RENDER:Int = ROWS_VISIBLE + 2;
	static final TEXT_X:Float = PANEL_X + 32;
	static final TEXT_W:Float = PANEL_W - 64;
	static final BAR_H:Float = 42;
	static final BAR_X:Float = PANEL_X + 14;
	static final BAR_W:Float = PANEL_W - 28;

	/** 滚动时间插值系数（Freeplay/MainMenu 同款 14） */
	static final SCROLL_LERP:Float = 14;
	/** 翻页间隔下限（毫秒）：连续快速滚动不会一帧翻好几页，翻页节奏可控 */
	static final PAGE_INTERVAL_MS:Float = 110;

	/** 侧栏标签（短名） */
	public var labels:Array<String> = [];
	/** 选中变化回调（宿主播 scrollMenu 音效、切内容区） */
	public var onMove:Void->Void = null;
	/** 确认回调（宿主切分区并转移焦点） */
	public var onConfirm:Int->Void = null;
	/** 键盘焦点是否在本组件（只影响高亮条亮度，不改变选中项） */
	public var focused(default, set):Bool = false;
	public var curSelected(default, set):Int = 0;

	var scrollOffset:Int = 0;   // 窗口顶部行索引（整数：决定渲染哪些标签）
	var scrollAnim:Float = 0;   // 窗口顶部的动画值（浮点：决定逐帧位移）
	var lastPageTime:Float = -9999; // 上次翻页时间（毫秒）
	var rows:Array<FlxText> = [];
	var lastText:Array<String> = [];
	var bar:FlxSprite;

	public function new()
	{
		super();

		add(OptionsUi.makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22));

		var title:FlxText = new FlxText(TITLE_X, TITLE_Y, TEXT_W, '设置', 30);
		title.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.scrollFactor.set();
		add(title);

		// ★ 高亮条必须先 add（画在文字下面）：见类注释的层级契约
		bar = OptionsUi.makePanel(BAR_X, LIST_Y - 4, BAR_W, BAR_H, 12, DesignTokens.rowHighlight, null);
		add(bar);

		for (r in 0...ROWS_RENDER)
		{
			var row:FlxText = new FlxText(TEXT_X, LIST_Y + (r * ROW_GAP), TEXT_W, '', 22);
			row.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.wordWrap = false; // 固定 166px 宽：长名靠截断，禁止折行压到下一行
			row.scrollFactor.set();
			row.visible = false;
			add(row);
			rows.push(row);
			lastText.push('');
		}
	}

	public function setLabels(list:Array<String>):Void
	{
		labels = list;
		if (curSelected >= labels.length) curSelected = Std.int(Math.max(0, labels.length - 1));
		snapScroll();
	}

	/** 设置选中项（不播报，由宿主决定是否发声） */
	public function setSelected(index:Int):Void
	{
		curSelected = index;
	}

	/** 键盘/点击的一行移动（可回卷；长按重复由宿主计时） */
	public function changeSelection(change:Int):Void
	{
		if (labels.length == 0) return;
		var before:Int = curSelected;
		curSelected += change;
		if (curSelected < 0) curSelected = labels.length - 1;
		if (curSelected >= labels.length) curSelected = 0;
		refresh();
		// 回卷/大跳直接吸附（别让"最后一项→第一项"滑过整栏）
		if (Std.int(Math.abs(curSelected - before)) > 2) snapScroll();
		if (onMove != null) onMove();
	}

	/**
	 * 滚轮输入：**页面滚动** —— 一格滚轮翻一整页（桌面）或一行（移动端，触屏合成的滚轮事件太密）。
	 * 与 `backend.WheelScroll` 同约定：`wheelDelta > 0`（多数平台的上滚）= 列表下移（选中项变小）。
	 * 限速 = 翻页间隔 ≥ `PAGE_INTERVAL_MS`，避免一次飞滚连翻好几页；滑动动画由 update 的时间插值负责。
	 */
	public function addWheel(wheelDelta:Float):Void
	{
		if (wheelDelta == 0 || labels.length == 0) return;
		var now:Float = haxe.Timer.stamp() * 1000;
		if (now < lastPageTime + PAGE_INTERVAL_MS) return;
		lastPageTime = now;

		var dir:Int = (wheelDelta > 0) ? -1 : 1;
		#if mobile
		changeSelection(dir); // 移动端：一格一行（触屏拖动会合成大量滚轮事件）
		#else
		pageStep(dir);
		#end
	}

	/** 翻一页：移动 `ROWS_VISIBLE` 项，两端自然夹取（不越界、不回卷） */
	public function pageStep(dir:Int):Void
	{
		if (labels.length == 0 || dir == 0) return;
		var target:Int = curSelected + dir * ROWS_VISIBLE;
		if (target < 0) target = 0;
		if (target > labels.length - 1) target = labels.length - 1;
		if (target == curSelected) return;
		curSelected = target;
		refresh();
		if (onMove != null) onMove();
	}

	/** 当前选中标签 */
	public function selectedLabel():String
	{
		if (labels.length == 0) return '';
		return labels[curSelected];
	}

	/** 鼠标/触控落在哪一行（未命中返回 -1）；命中带 = 整行高（移动端 56 = 触控目标红线） */
	public function hitIndex(mx:Float, my:Float):Int
	{
		if (mx < PANEL_X || mx > PANEL_X + PANEL_W) return -1;
		if (labels.length == 0) return -1;
		var bandTop:Float = LIST_Y - 6;
		var bandBottom:Float = LIST_Y + ROWS_VISIBLE * ROW_GAP;
		if (my < bandTop || my > bandBottom) return -1;
		// 反解：行 i 的顶部 = LIST_Y + (i - scrollAnim) × ROW_GAP
		var idx:Int = Std.int(Math.floor(scrollAnim + (my - LIST_Y) / ROW_GAP));
		if (idx < 0) idx = 0;
		if (idx >= labels.length) idx = labels.length - 1;
		return idx;
	}

	// ===== 每帧：窗口时间插值 → 逐行位移（唯一驱动，无 tween 队列）=====

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var target:Float = scrollOffset;
		if (Math.abs(scrollAnim - target) > 0.0005)
		{
			scrollAnim = FlxMath.lerp(scrollAnim, target, Math.min(1, elapsed * SCROLL_LERP));
			if (Math.abs(scrollAnim - target) < 0.002) scrollAnim = target;
		}

		renderRows();
	}

	/** 立即定位（无滑动）：初始化、回卷、外部设置选中项时用 */
	public function snapScroll():Void
	{
		scrollOffset = windowOffsetFor(curSelected);
		scrollAnim = scrollOffset;
		renderRows();
	}

	/** 重算窗口并立即重绘（选中变化时调用；滑动位移由 update 逐帧负责） */
	public function refresh():Void
	{
		scrollOffset = windowOffsetFor(curSelected);
		renderRows();
	}

	/** 让选中项落在窗口内的窗口顶部索引（尽量居中，边缘夹取） */
	function windowOffsetFor(index:Int):Int
	{
		var len:Int = labels.length;
		if (len <= ROWS_VISIBLE) return 0;
		var off:Int = index - Std.int((ROWS_VISIBLE - 1) / 2);
		if (off < 0) off = 0;
		if (off > len - ROWS_VISIBLE) off = len - ROWS_VISIBLE;
		return off;
	}

	function renderRows():Void
	{
		var base:Int = Std.int(Math.floor(scrollAnim));
		var frac:Float = scrollAnim - base;

		for (r in 0...rows.length)
		{
			var idx:Int = base + r;
			var row:FlxText = rows[r];
			var has:Bool = (idx >= 0 && idx < labels.length);

			// 列表带内才有位置（面板没有裁剪遮罩：越界的行必须隐藏，否则文字会压到标题/面板外）
			var rel:Float = r - frac;
			var inBand:Bool = rel > -0.55 && rel < ROWS_VISIBLE - 0.35;

			if (!has || !inBand)
			{
				row.visible = false;
				continue;
			}

			row.visible = true;
			var txt:String = labels[idx];
			if (lastText[r] != txt)
			{
				lastText[r] = txt;
				row.text = txt;
				row.updateHitbox();
			}
			row.y = LIST_Y + rel * ROW_GAP;

			var isSel:Bool = (idx == curSelected);
			row.alpha = isSel ? 1 : 0.78;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
		}

		// 高亮条：跟随选中项，按同一插值位移（滑动期间与文字同步，不会"框先到、字后到"）
		var relSel:Float = (curSelected - scrollAnim);
		var barVisible:Bool = relSel > -0.55 && relSel < ROWS_VISIBLE - 0.35;
		bar.visible = barVisible;
		if (barVisible)
		{
			bar.y = LIST_Y - 4 + relSel * ROW_GAP;
			bar.alpha = focused ? 1 : 0.7;
		}
	}

	function set_curSelected(v:Int):Int
	{
		curSelected = v;
		return curSelected;
	}

	function set_focused(v:Bool):Bool
	{
		focused = v;
		if (bar != null) bar.alpha = v ? 1 : 0.7;
		return focused;
	}

	/** 兼容旧调用点：本组件不再用 tween，滑动全走时间插值 */
	public function killTweens():Void {}
}
