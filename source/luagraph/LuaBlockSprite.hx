package luagraph;

import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import backend.DesignTokens;
import backend.Paths;

/**
 * 积木的可视化体（Scratch 风）。
 *
 * 绘制纪律（遵循 meteoric-design 系统域规范）：
 *  - 整个积木底图在构造时**一次画好**（makeGraphic + drawRoundRect ×N），update() 里零绘制；
 *  - 文本是独立的 FlxText（离开底图，避免每帧重建位图），随积木一起创建/销毁；
 *  - 配色全部来自 LuaBlockDefs（内部由 DesignTokens 派生），不写死十六进制。
 */
class LuaBlockSprite extends FlxSprite
{
	public static inline var HEADER_H:Float = 46;
	public static inline var HAT_H:Float = 14;
	public static inline var INDENT:Float = 26;
	public static inline var SLOT_H:Float = 26;
	public static inline var SLOT_GAP:Float = 8;
	public static inline var PAD:Float = 12;
	/**
	 * 空凹槽高度。2026-09-15 由 32 提到 44：
	 * 32 高 + 淡底（0x33）时，空凹槽被实测当成"另一块小积木压在帽块下面"（见截图复核），
	 * 加高 + 加深 + 槽内占位文案后，"这里能放积木"才是一眼可读的。
	 */
	public static inline var EMPTY_BODY_H:Float = 44;
	public static inline var ELSE_LABEL_H:Float = 26;
	public static inline var CHAIN_GAP:Float = 6;
	public static inline var MIN_W:Float = 220;
	public static inline var MAX_W:Float = 600;

	// ===== 凹槽（body / else 放置区）视觉 =====
	// 槽底属"面板内次级元素"，保留半透明深色（meteoric-design 硬性规则 3），不参与令牌化。
	static inline var WELL_FILL:Int = 0x59000000;
	static inline var WELL_BORDER:Int = 0x33FFFFFF;
	static inline var WELL_HINT_COLOR:Int = 0xFF9A9AA8;
	/** 辅助/提示字号（meteoric-design 字体表：辅助提示 16） */
	static inline var WELL_HINT_SIZE:Int = 16;
	static inline var WELL_HINT_LINE_H:Float = 18;
	static inline var WELL_HINT_BODY:String = '把积木拖进这个凹槽';
	static inline var WELL_HINT_ELSE:String = '把积木拖进「否则」凹槽';

	public var gblock:GBlock;
	public var def:BlockDef;
	public var blockPath:Array<Int>;
	public var metrics:BlockMetrics;
	public var slots:Array<SlotHit> = [];
	public var texts:Array<FlxText> = [];

	/** 两个容器的绝对矩形（用于空容器吸附与命中判断）。 */
	public var bodyWell:{x:Float, y:Float, w:Float, h:Float} = null;
	public var elseWell:{x:Float, y:Float, w:Float, h:Float} = null;

	/**
	 * @param bodyEmpty / elseEmpty 该凹槽在**界面上**是否为空。默认 null = 由 block 自身推断；
	 *   事件帽块必须由调用方传入：帽块的凹槽装的是**整条事件栈**（栈内积木与帽块在模型里同级），
	 *   所以 `block.body` 恒为空，只有 `stack.blocks.length == 0` 才能说明"槽是空的"。
	 *   不传就会在装了积木的帽块凹槽里也画出"把积木拖进这个凹槽"的占位文案。
	 */
	public function new(def:BlockDef, block:GBlock, blockPath:Array<Int>, x:Float, y:Float, m:BlockMetrics, selected:Bool,
			?bodyEmpty:Null<Bool> = null, ?elseEmpty:Null<Bool> = null)
	{
		super(x, y);
		this.def = def;
		this.gblock = block;
		this.blockPath = blockPath;
		this.metrics = m;

		var w:Float = Math.ceil(m.w);
		var h:Float = Math.ceil(m.h);
		makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);

		var fill:FlxColor = LuaBlockDefs.catFill(def.cat);
		var border:FlxColor = LuaBlockDefs.catBorder(def.cat);
		var headerTop:Float = def.hat ? HAT_H : 0;

		// 帽子（事件积木）：像 Scratch 一样在顶部凸出一条帽檐
		if (def.hat)
		{
			FlxSpriteUtil.drawRoundRect(this, 0, 0, w, HAT_H + 12, 7, 7, fill,
				{color: border, thickness: 1.5});
		}
		// 主体
		FlxSpriteUtil.drawRoundRect(this, 0, headerTop, w, HEADER_H, 10, 10, fill,
			{color: selected ? DesignTokens.primary : border, thickness: selected ? 2.5 : 1.5});

		// 容器凹槽（body / else）：槽底加深 + 空槽内画占位文案（见 EMPTY_BODY_H 注释）。
		// 占位文案**底部对齐**：拖拽时插入线画在槽的上沿（gap 中心），居中会被线划过。
		var yCursor:Float = headerTop + HEADER_H;
		if (def.body)
		{
			bodyWell = {x: x + INDENT, y: y + yCursor, w: w - INDENT - 8, h: m.bodyH};
			drawWell(INDENT, yCursor, w - INDENT - 8, m.bodyH);
			var bodyIsEmpty:Bool = (bodyEmpty != null) ? bodyEmpty : (block.body.length == 0);
			if (bodyIsEmpty)
				addWellHint(x + INDENT + 12, y + yCursor + m.bodyH - WELL_HINT_LINE_H - 6, WELL_HINT_BODY);
			yCursor += m.bodyH;
		}
		if (def.alt)
		{
			yCursor += 2;
			var elseLabelY:Float = yCursor;
			addText(x + INDENT + 6, y + elseLabelY + 2, '否则', 16, 0xFFCFCFDC);
			yCursor += ELSE_LABEL_H;
			elseWell = {x: x + INDENT, y: y + yCursor, w: w - INDENT - 8, h: m.elseH};
			drawWell(INDENT, yCursor, w - INDENT - 8, m.elseH);
			var elseIsEmpty:Bool = (elseEmpty != null) ? elseEmpty : (block.elseBody.length == 0);
			if (elseIsEmpty)
				addWellHint(x + INDENT + 12, y + yCursor + m.elseH - WELL_HINT_LINE_H - 6, WELL_HINT_ELSE);
		}

		// 标题 + 参数槽
		var tx:Float = PAD;
		if (def.hat) tx += 2;
		var labelTxt:FlxText = addText(x + tx, y + headerTop + 12, def.label, 18, FlxColor.WHITE);
		tx += textWidth(def.label, 18) + 10;

		for (p in def.params)
		{
			var value:String = block.get(p.name, p.def);
			var shown:String = value == null ? '' : value;
			var label:String = (shown.length > 0) ? shown : ('{' + p.label + '}');
			var vw:Float = Math.max(58, textWidth(label, 16) + 20);
			if (tx + vw > w - PAD) vw = Math.max(58, w - PAD - tx);
			var kindTxt:FlxText = addText(x + tx + 10, y + headerTop + 13, label, 16,
				(shown.length > 0) ? 0xFFFFF2C4 : 0xFF9A9AA8);
			kindTxt.width = vw - 16;
			kindTxt.wordWrap = false;

			var slotY:Float = y + headerTop + (HEADER_H - SLOT_H) / 2;
			var chipW:Float = vw;
			// 槽底：面板内的次级元素刻意保留半透明深色（见 meteoric-design 硬性规则 3）
			var chip:FlxSprite = new FlxSprite(x + tx + 2, slotY).makeGraphic(Std.int(chipW), Std.int(SLOT_H), FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRoundRect(chip, 0, 0, chipW, SLOT_H, 6, 6, 0x8C161622,
				{color: presentSlotBorder(p), thickness: 1});
			chip.scrollFactor.set();
			chips.push(chip);

			slots.push(new SlotHit(p.name, p.label, p.kind, x + tx + 2, slotY, chipW, SLOT_H));
			tx += chipW + SLOT_GAP;
		}

		scrollFactor.set();
		visible = true;
	}

	/** 槽底精灵（由状态层 add/destroy；与 texts 分开以免类型混淆）。 */
	public var chips:Array<FlxSprite> = [];

	function presentSlotBorder(p:PDef):FlxColor
	{
		return switch (p.kind)
		{
			case KEnum(_): 0x66FFFFFF;
			case KNum: 0x66FFFFFF;
			case KVar: 0x88FFD9A0;
			case KExpr: 0x889CE8FF;
			default: 0x66FFFFFF;
		}
	}

	/** 凹槽底（相对本积木的坐标画进自己的底图：一次画好，update() 零绘制）。 */
	function drawWell(rx:Float, ry:Float, rw:Float, rh:Float):Void
	{
		FlxSpriteUtil.drawRoundRect(this, rx, ry, rw, rh, 8, 8, WELL_FILL, {color: WELL_BORDER, thickness: 1});
	}

	/** 空槽占位文案：让"这里能放积木"可读（随 texts 一起被状态层 add / 销毁）。 */
	function addWellHint(x:Float, y:Float, txt:String):Void
	{
		var t:FlxText = addText(x, y, txt, WELL_HINT_SIZE, WELL_HINT_COLOR);
		t.wordWrap = false;
	}

	function addText(x:Float, y:Float, txt:String, size:Int, color:Int):FlxText
	{
		var t:FlxText = new FlxText(x, y, 0, txt, size);
		t.setFormat(Paths.font('future.ttf'), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		texts.push(t);
		return t;
	}

	/**
	 * 释放职责说明（2026-09-15 移除旧 `disposeAll()`）：文本/槽底的销毁必须与"从显示列表摘除"配套，
	 * 而本类拿不到宿主的 `FlxGroup`，自己销毁只会漏掉摘除（`FlxGroup.remove` 与 `destroy` 是两件事）。
	 * 统一由 `LuaGraphEditorState.disposeSprite()` / `disposeAll()` 负责：摘除 + destroy + 按需摘位图缓存；
	 * 顺序为先销毁 `texts/chips`（宿主用 `canvasBits` 统一持有），再把本类两个数组清空后销毁底图。
	 */

	/** 近似字宽：CJK/全角 ≈ 字号，ASCII ≈ 0.58 字号。用于布局测量，避免额外贴图开销。 */
	public static function textWidth(s:String, size:Int):Float
	{
		if (s == null) return 0;
		var sum:Float = 0;
		for (i in 0...s.length)
		{
			var c:Int = s.charCodeAt(i);
			sum += (c > 0x2E80 || c == 0xFF08 || c == 0xFF09) ? size : size * 0.58;
		}
		return sum;
	}

	/** 两遍法的"量"：给出宽度/高度/两个容器高度（递归子块）。 */
	public static function measure(def:BlockDef, b:GBlock, ?bodyOverride:Array<GBlock>):BlockMetrics
	{
		var headerW:Float = PAD + textWidth(def.label, 18) + 10 + PAD;
		for (p in def.params)
		{
			var value:String = b.get(p.name, p.def);
			var label:String = (value != null && value.length > 0) ? value : ('{' + p.label + '}');
			headerW += Math.max(58, textWidth(label, 16) + 20) + SLOT_GAP;
		}

		// bodyOverride：事件帽块的凹槽在界面上要装下整条事件栈（模型里栈内积木与帽块同级）
		var bodyChildren:Array<GBlock> = (bodyOverride != null) ? bodyOverride : b.body;
		var bodyChildH:Float = 0;
		var bodyChildW:Float = 0;
		for (c in bodyChildren)
		{
			var d2:BlockDef = LuaBlockDefs.get(c.type);
			if (d2 == null) continue;
			var m2:BlockMetrics = measure(d2, c);
			bodyChildH += m2.h + CHAIN_GAP;
			if (m2.w > bodyChildW) bodyChildW = m2.w;
		}
		var elseChildH:Float = 0;
		var elseChildW:Float = 0;
		for (c in b.elseBody)
		{
			var d2:BlockDef = LuaBlockDefs.get(c.type);
			if (d2 == null) continue;
			var m2:BlockMetrics = measure(d2, c);
			elseChildH += m2.h + CHAIN_GAP;
			if (m2.w > elseChildW) elseChildW = m2.w;
		}

		var bodyWellH:Float = def.body ? Math.max(EMPTY_BODY_H, bodyChildH + 12) : 0;
		var elseWellH:Float = def.alt ? Math.max(EMPTY_BODY_H, elseChildH + 12) : 0;

		var headerH:Float = (def.hat ? HAT_H : 0) + HEADER_H;
		var h:Float = headerH;
		if (def.body) h += bodyWellH;
		if (def.alt) h += ELSE_LABEL_H + elseWellH + 2;

		var w:Float = Math.max(MIN_W, headerW);
		if (def.body) w = Math.max(w, INDENT + 16 + bodyChildW + 12);
		if (def.alt) w = Math.max(w, INDENT + 16 + elseChildW + 12);
		if (w > MAX_W) w = MAX_W;

		return {w: w, h: h, bodyH: bodyWellH, elseH: elseWellH, headerH: headerH};
	}
}

