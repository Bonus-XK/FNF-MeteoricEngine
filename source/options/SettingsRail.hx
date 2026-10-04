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
	// ===== 跑马灯（超宽行文本横向滚动）=====
	// 为什么需要：侧栏行宽固定 TEXT_W=166px 且 wordWrap=false（禁止折行压下一行），
	// 多语言后英文分区名（如 "Customize HUD"、"Touch Controls"）会超出该宽度被硬裁掉。
	// 为什么只滚**选中行**：整栏一起滚视觉噪声大且违反"低频动效"纪律；
	// 未选中行只是静态截断（用户没聚焦它，看全名没有价值）。
	/** 每行文本实际宽度（px），-1 = 该行不需要滚动 */
	var rowTextW:Array<Float> = [];
	/** 当前 scrollX（px） */
	var rowScroll:Float = 0;
	/** 距离下一次推进的剩余秒数（用于「停留 → 滚动 → 停留」的循环） */
	var rowScrollWait:Float = 0;
	/** 上次滚动所对应的行索引；换行/换文案时重置 */
	var rowScrollIdx:Int = -1;
	/** 上一次看到的选中行文本，用于检测换文案并复位 */
	var rowScrollText:String = null;
	/** 上次写入 textField 的 scrollH（相同则跳过重复写入；-1 = 尚未写过） */
	var rowScrollDrawn:Int = -1;
	/** 距上次重绘累积的秒数（节流用） */
	var rowScrollAccum:Float = 0;

	/** 跑马灯参数（px/秒 与 停留秒数） */
	static final SCROLL_SPEED:Float = 26;
	static final SCROLL_HOLD_START:Float = 1.1; // 起手先停多久
	static final SCROLL_HOLD_END:Float = 1.6; // 滚到尾再停多久
	/** 判定「超宽」的余量（px）：抗字体渲染误差，避免刚好齐边就抖动 */
	static final OVERFLOW_EPS:Float = 1.0;
	/** 位图重绘节流间隔（秒）≈20fps：FlxText 是缓存位图，改 scrollH 必须重绘才可见 */
	static final SCROLL_REDRAW_INTERVAL:Float = 0.05;

	var bar:FlxSprite;
	/** 侧栏底板（主题色变更时要原地重绘，故留引用） */
	var panel:FlxSprite;

	public function new()
	{
		super();

		panel = OptionsUi.makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22);
		add(panel);

		var title:FlxText = new FlxText(TITLE_X, TITLE_Y, TEXT_W, backend.Lang.t('settings.title'), 30);
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
			row.wordWrap = false; // 固定 166px 宽：长名靠跑马灯（仅选中行）看全，禁止折行压到下一行
			row.scrollFactor.set();
			row.visible = false;
			add(row);
			rows.push(row);
			lastText.push('');
			rowTextW.push(-1);
		}
	}

	/**
	 * 主题色变更：原地重绘本组件里**令牌化**的两块（底板 + 选中高亮条），让侧栏立刻换色。
	 * 低频事件（仅在 applyTheme 的监听者派发里调用），禁止放进 update/逐帧路径。
	 */
	public function refreshTheme():Void
	{
		OptionsUi.rethemePanel(panel, PANEL_W, PANEL_H, 22);
		OptionsUi.rethemePanel(bar, BAR_W, BAR_H, 12, DesignTokens.rowHighlight, null);
	}

	public function setLabels(list:Array<String>):Void
	{
		labels = list;
		if (curSelected >= labels.length) curSelected = Std.int(Math.max(0, labels.length - 1));
		// 文案整体换了（首次构建 / 语言切换）→ 强制每行重测宽度并复位跑马灯，
		// 否则会沿用旧语言的缓存宽度判定（英文比中文宽，判定结果完全不同）。
		resetRowScroll();
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

		// 跑马灯步长：写进实例字段供 renderRows → applyRowScroll 读取
		// （切到后台/暂停时 elapsed 可能异常，钳到上限避免恢复瞬间跳一大截）
		tickDt = Math.min(elapsed, 0.1);

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
				// FlxText 每次 set_text 都会复位内部 TextField 的 scrollX：
				// 换文案必须重测宽度并把跑马灯状态清零，否则会带着旧偏移/旧宽度继续滚。
				rowTextW[r] = -1;
				row.textField.scrollH = 0;
			}
			row.y = LIST_Y + rel * ROW_GAP;

			var isSel:Bool = (idx == curSelected);
			row.alpha = isSel ? 1 : 0.78;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;

			// 跑马灯：只有选中行滚动；其余行一律停在起点（scrollH=0）
			if (isSel) applyRowScroll(row, r, idx, txt);
			else if (rowScrollDrawn != 0)
			{
				// 该行刚被取消选中、可能停在滚动中途 → 必须归零**并重绘**，
				// 只改 scrollH 不重绘的话位图仍是滚动后的画面（视觉残留）。
				rowScrollDrawn = 0;
				rowScrollAccum = 0;
				row.textField.scrollH = 0;
				row.forceRegen();
			}
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
		if (curSelected != v) resetRowScroll();
		curSelected = v;
		return curSelected;
	}

	/** 跑马灯状态复位（换行 / 换文案 / 语言切换后调用） */
	function resetRowScroll():Void
	{
		rowScroll = 0;
		rowScrollWait = 0;
		rowScrollIdx = -1;
		rowScrollText = null;
		rowScrollDrawn = -1;
		rowScrollAccum = 0;
		for (r in 0...rows.length)
		{
			rowTextW[r] = -1;
			if (rows[r] != null && rows[r].textField != null) rows[r].textField.scrollH = 0;
		}
	}

	/**
	 * 推进选中行的跑马灯（仅在文本超出 TEXT_W 时生效）。
	 *
	 * 循环：起手停留 → 匀速滚到末尾 → 末尾停留 → 瞬间归零 → 再停 → 再滚。
	 * 用 `textField.scrollH` 而不是移动 FlxText.x：后者需要额外裁剪遮罩，
	 * 会与「高亮条必须先 add」这条层级契约打架（遮罩要么裁掉高亮条、要么被行文字盖住）。
	 */
	function applyRowScroll(row:FlxText, r:Int, idx:Int, txt:String):Void
	{
		if (row == null || row.textField == null) return;

		// 换行或换文案 → 复位（否则带着上一行的偏移/宽度继续滚）
		if (idx != rowScrollIdx || txt != rowScrollText)
		{
			rowScrollIdx = idx;
			rowScrollText = txt;
			rowScroll = 0;
			rowScrollWait = SCROLL_HOLD_START;
			rowScrollDrawn = -1;
			rowScrollAccum = 0;
			row.textField.scrollH = 0;
			row.forceRegen();
		}

		// 量宽（懒测：只在成为选中行时测一次，缓存进 rowTextW）
		if (rowTextW[r] < 0) rowTextW[r] = row.textField.textWidth;

		var overflow:Float = rowTextW[r] - TEXT_W;
		if (overflow <= OVERFLOW_EPS)
		{
			if (rowScrollDrawn != 0)
			{
				rowScrollDrawn = 0;
				row.textField.scrollH = 0;
				row.forceRegen();
			}
			rowScroll = 0;
			return;
		}

		if (rowScrollWait > 0)
		{
			rowScrollWait -= tickDt;
			return;
		}

		rowScroll += SCROLL_SPEED * tickDt;
		if (rowScroll >= overflow)
		{
			rowScroll = 0;
			rowScrollWait = SCROLL_HOLD_END;
		}
		applyScrollH(row);
	}

	/**
	 * 写入 scrollH 并按节流重绘位图。
	 *
	 * FlxText 把文本画进缓存 BitmapData，所以改 scrollH 后必须 forceRegen 才可见。
	 * 但每帧重画一张 166×32 的位图属于"逐帧绘制"（违反 meteoric-system 绘制纪律），
	 * 故节流到 ~20fps：位移按真实 elapsed 累积，只在攒够 ~0.05s 才画一次，
	 * 视觉上是平滑滚动（26px/s × 0.05s ≈ 1.3px/步），开销可忽略。
	 */
	function applyScrollH(row:FlxText):Void
	{
		var v:Int = Std.int(rowScroll);
		if (v == rowScrollDrawn) return; // 位图已是这一位置，不必重画
		rowScrollDrawn = v;
		row.textField.scrollH = v; // scrollH 是 Int（openfl TextField 的类型）
		rowScrollAccum += tickDt;
		if (rowScrollAccum >= SCROLL_REDRAW_INTERVAL)
		{
			rowScrollAccum = 0;
			row.forceRegen();
		}
	}

	/** 本帧步长（秒）。由 update 写入，跑马灯在 renderRows 里读取，避免逐层传参。 */
	var tickDt:Float = 0;

	function set_focused(v:Bool):Bool
	{
		focused = v;
		if (bar != null) bar.alpha = v ? 1 : 0.7;
		return focused;
	}

	/** 兼容旧调用点：本组件不再用 tween，滑动全走时间插值 */
	public function killTweens():Void {}
}
