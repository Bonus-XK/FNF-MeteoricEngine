package states.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;

import backend.DesignTokens;
import backend.Mods;
import backend.MusicBeatState;
import backend.Paths;

import objects.BackButton;
import objects.UIButton;
import objects.UIInputBox;

import states.editors.MasterEditorMenu;
import substates.Prompt;
import substates.TextInputPrompt;

import luagraph.GBlock;
import luagraph.GDoc;
import luagraph.GStack;
import luagraph.GVar;
import luagraph.LuaBlockDefs;
import luagraph.LuaBlockSprite;
import luagraph.LuaCodeGen;
import luagraph.LuaGraphIO;
import luagraph.LuaGraphTemplates;
import luagraph.SlotHit;
import luagraph.BlockDef;
import luagraph.BlockMetrics;
import luagraph.PDef;

/** 吸附插入点：把积木放进 containerPath 指向的序列的 index 位置。 */
private typedef LuaGraphGap =
{
	var containerPath:Array<Int>;
	var index:Int;
	var ax:Float;
	var ay:Float;
	var aw:Float;
	var ah:Float;
}

/**
 * Lua 图形化编程编辑器（积木块 → Lua）。
 *
 * 域归属：系统域（meteoric-system）—— 圆角磨砂面板 + MD3 令牌 + 三套输入 + 克制动效。
 * 交互：左「分类」、中「积木面板」、右「画布」；下「状态条 + 操作按钮」。
 * 画布为多栈结构：每条事件帽块 = 生成文件里的一个真实回调函数。
 */
class LuaGraphEditorState extends MusicBeatState
{
	// ===== 布局（1280×720 逻辑像素；右缘 ≤1240、底部 ≤648 的安全区）=====
	static inline var CAT_X:Float = 40;
	static inline var CAT_Y:Float = 70;
	static inline var CAT_W:Float = 156;
	static inline var CAT_H:Float = 570;

	static inline var BLK_X:Float = 208;
	static inline var BLK_Y:Float = 70;
	static inline var BLK_W:Float = 300;
	static inline var BLK_H:Float = 570;

	static inline var CAN_X:Float = 520;
	static inline var CAN_Y:Float = 70;
	static inline var CAN_W:Float = 720;
	static inline var CAN_H:Float = 570;

	/**
	 * 画布内容起始 y（第一条事件栈的顶部）= 画布顶部两行（标题行 + 「模组/脚本」行）之后。
	 * 2026-09-15：原先写死 `CAN_Y + CAN_PAD + 34`（=120），只够一行，状态行一折行就压在
	 * 第一条事件栈上（截图复核的叠字根因之一）。
	 */
	static inline var CAN_CONTENT_Y:Float = CAN_Y + 78;

	/** 状态行可用宽度：右缘 = CAN_X + CAN_W - 40 = 1216 ≤ meteoric-design「固定列布局右缘 1220」 */
	static inline var CAN_NAME_W:Float = CAN_W - 40;

	/** 底栏按钮标签字号：96×32 的窄按钮装不下历史默认 26px（"保存生成" 折行、"预览 Lua" 被截） */
	static inline var BAR_BTN_LABEL:Int = 18;

	/** 底栏按钮与状态条的安全间距（沿用原布局：5 个 96 宽按钮右对齐到面板右缘） */
	static inline var BAR_BTN_W:Float = 96;
	static inline var BAR_BTN_GAP:Float = 8;

	/** 拖拽插入指示（⑥） */
	static inline var DROP_LINE_COLOR:Int = 0x66D7D7E0;
	static inline var DROP_LINE_H:Float = 3;
	static inline var DROP_CURSOR_W:Float = 200;
	static inline var DROP_CURSOR_H:Float = 4;

	static inline var BAR_X:Float = 40;
	/**
	 * 底栏（状态行 + 两行快捷键提示 + 5 个按钮）。
	 * 2026-09-15：高 48 时只放得下"状态行 + 一行提示"，而完整键位文案实测约 1100px、
	 * 左侧可用宽度只有 636px（右侧 512px 被 5 个按钮占掉）→ 尾部永远看不到
	 * （用户截图：提示止于"Enter 编"）。故加高到 58（顶边 652 仍 ≥ 设计规范底部安全线 648）
	 * 并把提示**均衡拆成两行**；不采用缩写方案（会丢键位信息）。
	 */
	static inline var BAR_Y:Float = 652;
	static inline var BAR_W:Float = 1200;
	static inline var BAR_H:Float = 58;

	/** 底栏左侧文本区宽度（按钮从 BAR_X + BAR_W - 512 = 728 起） */
	static inline var BAR_TEXT_W:Float = 636;
	static inline var BAR_HINT_FONT:Int = 13;

	/**
	 * 两行快捷键提示。**每行必须 ≤ BAR_TEXT_W**：`create()` 会跑 `fitText()` 兜底截断，
	 * 自检会打印两行的实测宽度与是否被截断（`truncated=`）—— 改文案时请跟着看这一行日志。
	 */
	static inline var HINT_ROW1:String = '拖拽=放置/移动 · 点击参数=编辑 · [ ] 分类 · PgUp/PgDn 选块 · Insert 插入 · F1 说明';
	static inline var HINT_ROW2:String = '←/→ 选参数 · Enter 编辑 · Del 删除 · Ctrl+Z/Y 撤销重做 · Ctrl+S 保存 · Tab 预览';

	/**
	 * `F1` 操作说明：**完整键位表**（底栏两行只放高频项，放不全的键位在这里）。
	 * 复用通用弹层 ⇒ 自动获得：`raiseOverlay()`（永远在积木之上）、滚轮/↑↓ 翻页、Enter/点击确认、Esc 关闭。
	 * 每行必须 ≤ 556px（弹层正文宽度 pw-64 = 620-64）；自检会打印实测最大宽度 `help fit: max=…/556`。
	 */
	static var HELP_LINES:Array<String> = [
		'鼠标：拖积木到插入线/凹槽松手即接上 · 点参数槽就地编辑',
		'点事件帽块 = 选中整条事件栈（Del 删除，Ctrl+Z 撤销）',
		'滚轮：画布/积木列表滚动 · 点画布空白 = 取消选中',
		'[ ] 切换分类 · ,/. 或 PgUp/PgDn 上下选积木',
		'Insert：插入高亮积木（选中项之后；无选中则插到最后一条栈）',
		'←/→：切换参数并微调枚举/数字 · Enter：编辑选中参数',
		'Del/Backspace：删除选中积木；选中帽块时删整条事件栈',
		'Ctrl+Z / Ctrl+Y：撤销 / 重做 · Ctrl+C/X/V：复制/剪切/粘贴',
		'Ctrl+S 保存生成 · Ctrl+O 打开 · F2 重命名',
		'Tab：预览生成的 Lua · Esc：返回编辑器菜单 · F1：本说明'
	];

	/** 弹层正文可用宽度（renderPopup 的 pw - 64）与操作说明字号，供自检断言使用 */
	static inline var POPUP_TEXT_W:Float = 556;
	static inline var HELP_FONT:Int = 18;

	static inline var CAT_ROW_H:Float = 44;
	static inline var PAL_ROW_H:Float = 40;
	static inline var PAL_VISIBLE:Int = 12;
	static inline var CAN_PAD:Float = 16;
	static inline var MAX_UNDO:Int = 60;
	static inline var GAP_BAND:Float = 16;
	static inline var STACK_GAP:Float = 26;

	// 语义色例外（meteoric-design：success/error 属内容语义色，永不参与主题化）
	static inline var COLOR_ERROR:Int = 0xFFFF6B6B;
	static inline var COLOR_OK:Int = 0xFF7BFF9E;

	static inline var DRAG_NONE:Int = 0;
	static inline var DRAG_NEW:Int = 1;
	static inline var DRAG_MOVE:Int = 2;

	// ===== 文档与历史 =====
	var doc:GDoc;
	var dirty:Bool = false;
	var undoStack:Array<String> = [];
	var redoStack:Array<String> = [];
	var clipboard:GBlock = null;

	// ===== 视觉 =====
	var bg:FlxSprite;
	var catRows:Array<FlxText> = [];
	var catBar:FlxSprite;
	var palRows:Array<FlxText> = [];
	var palBar:FlxSprite;
	var palTitle:FlxText;
	var palDesc:FlxText;
	var canvasEmptyHint:FlxText;
	var statusText:FlxText;
	var hintText:FlxText;
	var hintText2:FlxText;
	var nameText:FlxText;
	var backBtn:BackButton;
	var buttons:Array<UIButton> = [];
	var btnNew:UIButton;
	var btnOpen:UIButton;
	var btnSave:UIButton;
	var btnRename:UIButton;
	var btnPreview:UIButton;

	// ===== 画布内容 =====
	var blockSprites:Array<LuaBlockSprite> = [];
	var canvasBits:Array<FlxSprite> = [];
	var gaps:Array<LuaGraphGap> = [];

	// ===== 交互状态 =====
	var catIndex:Int = 0;
	var palScroll:Int = 0;
	var palHighlight:Int = 0;
	var canvasScroll:Float = 0;
	var selPath:Array<Int> = null;
	var selParam:Int = 0;
	var dragKind:Int = DRAG_NONE;
	var dragBlock:GBlock = null;
	var dragSpr:LuaBlockSprite = null;
	var dragOffX:Float = 0;
	var dragOffY:Float = 0;
	var dragOriginContainer:Array<Int> = null;
	var dragOriginIndex:Int = 0;
	var mouseGuard:Int = 3;

	// 拖拽插入指示（⑥）：插入线 + 最近插入点高亮 —— 松手前就能看到"会接到哪"
	var dropHints:Array<FlxSprite> = [];
	var dropCursor:FlxSprite = null;

	// ===== 弹出层（清单/选项）=====
	var popupOpen:Bool = false;
	var popupPick:String->Void = null;
	var popupAll:Array<String> = [];
	var popupScroll:Int = 0;
	var popupHover:Int = 0;
	var popupSprites:Array<FlxSprite> = [];
	var popupTexts:Array<FlxText> = [];

	// ===== 预览层 =====
	var previewOpen:Bool = false;
	var previewAll:Array<String> = [];
	var previewScroll:Int = 0;
	var previewSprites:Array<FlxSprite> = [];
	var previewTexts:Array<FlxText> = [];

	// ===== 自检（CI/维护用，ME_LUAGRAPH_SELFTEST=1 时启用；不设置则零行为影响）=====
	var selfTest:Bool = false;
	var selfTestT:Float = 0;
	var selfTestStep:Int = 0;
	/** 自检模拟拖拽时锁住鼠标分支：否则真实鼠标并未按下 → 下一帧就被 finishDrag 拆掉，无法截图取证 */
	var selfTestDragHold:Bool = false;

	// ===== 参数输入框 =====
	var inputBox:UIInputBox = null;
	var inputSlot:SlotHit = null;
	var inputPath:Array<Int> = null;
	var inputHadFocus:Bool = false;

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Lua 图形化编程";

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = DesignTokens.menuTint;
		add(bg);

		// 面板：分类 / 积木 / 画布 / 底部条（后 add 的盖住先 add 的）
		add(makePanel(CAT_X, CAT_Y, CAT_W, CAT_H, 22));
		add(makePanel(BLK_X, BLK_Y, BLK_W, BLK_H, 22));
		add(makePanel(CAN_X, CAN_Y, CAN_W, CAN_H, 22));
		add(makePanel(BAR_X, BAR_Y, BAR_W, BAR_H, 14));

		add(makeText(CAT_X + 18, CAT_Y + 16, 0, '分类', 24, DesignTokens.primary));
		palTitle = makeText(BLK_X + 18, BLK_Y + 16, 0, '积木', 24, DesignTokens.primary);
		add(palTitle);
		add(makeText(CAN_X + 16, CAN_Y + 16, 0, '画布（拖拽积木到这里）', 24, DesignTokens.primary));

		// 画布顶部固定两行：第 1 行 = 面板标题，第 2 行 = 「模组/脚本」（右对齐、单行、超长省略）。
		// 原先宽 280 + 默认 wordWrap（FlxText 在 fieldWidth>0 时强制换行）→ 长模组名折 3 行压进画布内容区。
		nameText = makeText(CAN_X + 16, CAN_Y + 44, CAN_NAME_W, '', 16, 0xFFCFCFDC);
		nameText.alignment = RIGHT;
		nameText.wordWrap = false;
		add(nameText);

		// 空画布提示：只在"没有任何可绘制事件栈"时出现（见 hasDrawableStack）。
		// 位置改到画布中部：旧位置 y = CAN_Y+90 正好落在第一条事件栈上 → 提示与帽块叠字。
		canvasEmptyHint = makeText(CAN_X + 40, CAN_Y + 150, CAN_W - 80, '画布是空的：从左侧「积木」面板拖一块事件积木（如“当每拍时”）到这里开始。', 18, 0xFFCFCFDC);
		canvasEmptyHint.wordWrap = true;
		add(canvasEmptyHint);

		// 积木面板底部：当前积木说明
		palDesc = makeText(BLK_X + 18, BLK_Y + BLK_H - 76, BLK_W - 36, '', 15, 0xFFCFCFDC);
		palDesc.wordWrap = true;
		add(palDesc);

		// 状态条（三行：状态 + 快捷键提示 ×2）
		statusText = makeText(BAR_X + 24, BAR_Y + 3, BAR_TEXT_W, '就绪', 17, FlxColor.WHITE);
		statusText.wordWrap = false;
		add(statusText);
		// 提示拆两行：一行装不下完整键位（实测 ~1100px vs 可用 636px）；fitText 兜底 + 自检打印实测宽度
		hintText = makeText(BAR_X + 24, BAR_Y + 22, BAR_TEXT_W, '', BAR_HINT_FONT, 0xFFCFCFDC);
		hintText.wordWrap = false;
		add(hintText);
		hintText.text = fitText(HINT_ROW1, BAR_HINT_FONT, BAR_TEXT_W);
		hintText2 = makeText(BAR_X + 24, BAR_Y + 38, BAR_TEXT_W, '', BAR_HINT_FONT, 0xFFCFCFDC);
		hintText2.wordWrap = false;
		add(hintText2);
		hintText2.text = fitText(HINT_ROW2, BAR_HINT_FONT, BAR_TEXT_W);

		// 操作按钮（标签字号 18：见 BAR_BTN_LABEL 注释，26px 会折行并被窗口底边切掉）
		var bx:Float = BAR_X + BAR_W - 5 * BAR_BTN_W - 4 * BAR_BTN_GAP;
		var by:Float = BAR_Y + 13;
		var bh:Float = 32;
		btnNew = new UIButton(bx, by, BAR_BTN_W, bh, '新建', UIButton.VARIANT_TONAL, newScript, BAR_BTN_LABEL);
		btnOpen = new UIButton(bx + 104, by, BAR_BTN_W, bh, '打开', UIButton.VARIANT_TONAL, openChooser, BAR_BTN_LABEL);
		btnSave = new UIButton(bx + 208, by, BAR_BTN_W, bh, '保存生成', UIButton.VARIANT_FILLED, saveScript, BAR_BTN_LABEL);
		btnRename = new UIButton(bx + 312, by, BAR_BTN_W, bh, '重命名', UIButton.VARIANT_TONAL, renameScript, BAR_BTN_LABEL);
		btnPreview = new UIButton(bx + 416, by, BAR_BTN_W, bh, '预览 Lua', UIButton.VARIANT_TONAL, openPreview, BAR_BTN_LABEL);
		buttons = [btnNew, btnOpen, btnSave, btnRename, btnPreview];
		for (b in buttons) add(b);

		// 返回按钮
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// 文档
		doc = LuaGraphTemplates.blank('graph_script');
		doc.mod = Mods.currentModDirectory == null ? '' : Mods.currentModDirectory;

		rebuildCategories();
		rebuildPalette();
		rebuildCanvas();
		refreshStatus();

		selfTest = selfTestRequested();
		if (selfTest) stLog('start: mod=' + Mods.currentModDirectory);

		FlxG.mouse.visible = true;
		super.create();
	}

	/**
	 * 是否请求自检：读环境变量 ME_LUAGRAPH_SELFTEST（桌面端）。
	 * 用途 = 让 CI / 维护者无需鼠标与按键即可跑通"载入图 → 编辑 → 撤销重做 → 生成 → 保存"全链路。
	 * 不设置该变量时返回 false，本类行为与常规完全一致。
	 */
	public static function selfTestRequested():Bool
	{
		#if desktop
		var v:String = null;
		try v = Sys.getEnv('ME_LUAGRAPH_SELFTEST') catch (e:Dynamic) {}
		return (v != null && v.length > 0 && v != '0');
		#else
		return false;
		#end
	}

	inline function stLog(msg:String):Void
	{
		#if sys
		Sys.println('[SELFTEST] ' + msg);
		#end
	}

	/** 自检主流程：按时间片推进，保证每一步之后都有一帧真实渲染（可截图取证）。 */
	function runSelfTest(elapsed:Float):Void
	{
		selfTestT += elapsed;
		if (selfTestStep == 0 && selfTestT >= 0.6)
		{
			selfTestStep = 1;
			try
			{
				doc = LuaGraphIO.readGraph('demo');
				doc.name = 'demo';
				canvasScroll = 0;
				dirty = false;
				rebuildCanvas();
				refreshStatus();
				stLog('load graph ok: blocks=' + doc.blockCount() + ' stacks=' + doc.stacks.length + ' vars=' + doc.vars.length);
			}
			catch (e:Dynamic)
			{
				stLog('load graph FAILED: ' + Std.string(e));
			}
			// 底栏提示防回归断言：两行实测宽度必须 ≤ BAR_TEXT_W，且底栏不得越过窗口底部（720）安全线
			stLog('hint fit: row1=' + Std.int(LuaBlockSprite.textWidth(HINT_ROW1, BAR_HINT_FONT)) + '/' + Std.int(BAR_TEXT_W)
				+ ' row2=' + Std.int(LuaBlockSprite.textWidth(HINT_ROW2, BAR_HINT_FONT)) + '/' + Std.int(BAR_TEXT_W)
				+ ' truncated=' + (((hintText != null && hintText.text != HINT_ROW1)
					|| (hintText2 != null && hintText2.text != HINT_ROW2)) ? 'yes' : 'no')
				+ ' barBottom=' + Std.int(BAR_Y + BAR_H));
			// F1 操作说明的每行也必须落在弹层正文宽度内
			var helpMax:Int = 0;
			for (l in HELP_LINES)
			{
				var w:Int = Std.int(LuaBlockSprite.textWidth(l, HELP_FONT));
				if (w > helpMax) helpMax = w;
			}
			stLog('help fit: max=' + helpMax + '/' + Std.int(POPUP_TEXT_W) + ' rows=' + HELP_LINES.length);
			return;
		}
		if (selfTestStep == 1 && selfTestT >= 1.1)
		{
			selfTestStep = 2;
			// 模拟"从调色板拖入一块积木"：走与鼠标拖拽完全相同的插入路径
			var path:Array<Int> = [0];
			var arr:Array<GBlock> = GDoc.containerOf(doc, path);
			var b:GBlock = new GBlock('misc_print');
			b.params = LuaBlockDefs.get('misc_print').defaultParams();
			b.set('text', '自检插入的积木');
			pushUndo();
			arr.insert(0, b);
			selPath = [0, 0];
			dirty = true;
			rebuildCanvas();
			stLog('insert ok: blocks=' + doc.blockCount());
			return;
		}
		if (selfTestStep == 2 && selfTestT >= 1.6)
		{
			selfTestStep = 3;
			deleteSelected();
			var afterDelete:Int = doc.blockCount();
			undo();
			var afterUndo:Int = doc.blockCount();
			redo();
			var afterRedo:Int = doc.blockCount();
			stLog('edit ok: delete=' + afterDelete + ' undo=' + afterUndo + ' redo=' + afterRedo
				+ ' undoRedoMatch=' + (afterUndo == afterRedo + 1 ? 'yes' : 'no'));

			// 事件栈删除（本轮新增能力，此前全工程没有任何删除事件栈的代码）：
			// 选中帽块路径 → deleteSelected → 校验栈数减少 → 撤销回滚到原值。
			var stacksBefore:Int = doc.stacks.length;
			selPath = [stacksBefore - 1];
			deleteSelected();
			var stacksDeleted:Int = doc.stacks.length;
			undo();
			var stacksRestored:Int = doc.stacks.length;
			stLog('stack delete ok: before=' + stacksBefore + ' afterDelete=' + stacksDeleted
				+ ' afterUndo=' + stacksRestored + ' restored=' + ((stacksRestored == stacksBefore) ? 'yes' : 'no'));
			return;
		}
		if (selfTestStep == 3 && selfTestT >= 2.1)
		{
			selfTestStep = 4;
			var issues:Array<String> = LuaCodeGen.validate(doc);
			var gen:String = '';
			try gen = LuaCodeGen.generate(doc) catch (e:Dynamic) gen = 'GEN_FAILED: ' + Std.string(e);
			stLog('generate ok: lines=' + LuaCodeGen.countLines(gen) + ' issues=' + issues.length
				+ (issues.length > 0 ? ' first=' + issues[0] : ''));
			return;
		}
		if (selfTestStep == 4 && selfTestT >= 2.6)
		{
			selfTestStep = 5;
			saveScript();
			stLog('save status: ' + statusText.text);
			return;
		}
		if (selfTestStep == 5 && selfTestT >= 3.1)
		{
			selfTestStep = 6;
			openPreview();
			stLog('preview opened: lines=' + previewAll.length);
			return;
		}
		if (selfTestStep == 6 && selfTestT >= 4.6)
		{
			selfTestStep = 7;
			// 拖拽吸附指示（⑥）取证：走与鼠标拖拽**完全相同**的路径
			// （startDragNew → makeGhost → showDropHints → updateDropHints），
			// 使"插入线 + 最近插入点高亮"在没有鼠标的 CI 截图里也能被复核。
			// 先关掉弹层与预览层：弹层是模态的（真实用户此时不可能拖拽），留着会挡住取证画面。
			closePreview();
			closePopup();
			selfTestDragHold = true;
			var dragDef:BlockDef = LuaBlockDefs.get('misc_print');
			if (dragDef != null)
			{
				var dmx:Float = CAN_X + 150;
				var dmy:Float = CAN_CONTENT_Y + 40;
				startDragNew(dragDef, dmx, dmy);
				updateDropHints(dmx, dmy);
				stLog('drag hints: gaps=' + gaps.length + ' lines=' + dropHints.length
					+ ' cursor=' + (dropCursor != null && dropCursor.visible ? 'on' : 'off'));
			}
			return;
		}
		if (selfTestStep == 7 && selfTestT >= 6.2)
		{
			selfTestStep = 8;
			selfTestDragHold = false;
			clearGhost();
			// 演示用的拖拽不入图：清干净状态，避免自检结束后残留悬挂的 dragBlock
			dragKind = DRAG_NONE;
			dragBlock = null;
			rebuildCanvas();
			// 层级契约取证：**复现用户报的"神秘堆叠"场景** —— 弹层已打开，随后重建画布。
			// 没有 `raiseOverlay()` 时，重建把积木 add 到 members 末尾 → 积木压住弹层
			// （实测截图：弹层错误行被「当脚本创建时」拦腰盖住）。此步把修复后的层级留在画面上供截图。
			openPopup('自检 · 层级检查', ['弹层必须压在画布积木之上（raiseOverlay 生效）'], null);
			rebuildCanvas();
			stLog('overlay restack: popupOpen=' + popupOpen + ' blocks=' + doc.blockCount()
				+ ' popupIdx=' + (popupSprites.length > 0 ? members.indexOf(popupSprites[0]) : -1)
				+ ' lastBlockIdx=' + (canvasBits.length > 0 ? members.indexOf(canvasBits[canvasBits.length - 1]) : -1));
			return;
		}
		if (selfTestStep == 8 && selfTestT >= 7.4)
		{
			selfTestStep = 9;
			closePopup();
			rebuildCanvas();
			// 帽块选中取证：调用与鼠标处理**完全相同**的函数（updateMouse 命中帽块时就是走 startDragMove），
			// 让"已选中事件栈：X（Del 删除整条栈）"这条新提示留在画面上供截图复核。
			var hatSpr:LuaBlockSprite = null;
			for (s in blockSprites)
				if (s.blockPath.length == 1 && s.blockPath[0] == 0)
				{
					hatSpr = s;
					break;
				}
			if (hatSpr != null) startDragMove(hatSpr, hatSpr.x + 40, hatSpr.y + 30);
			stLog('hat select: selPath=' + Std.string(selPath) + ' status=' + statusText.text);
			return;
		}
		if (selfTestStep == 9 && selfTestT >= 8.6)
		{
			selfTestStep = 10;
			// Del 删除整条事件栈（键处理里调的就是这个函数）
			var before:Int = doc.stacks.length;
			deleteSelected();
			stLog('stack delete via Del: stacks ' + before + ' -> ' + doc.stacks.length + ' status=' + statusText.text);
			return;
		}
		if (selfTestStep == 10 && selfTestT >= 9.8)
		{
			selfTestStep = 11;
			undo();
			stLog('stack delete undo: stacks=' + doc.stacks.length + ' status=' + statusText.text);
			stLog('DONE');
			return;
		}
	}

	override function update(elapsed:Float)
	{
		if (selfTest) runSelfTest(elapsed);

		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.8)
			FlxG.sound.music.volume += 0.5 * elapsed;

		if (mouseGuard > 0) mouseGuard--;

		if (popupOpen)
		{
			updatePopup();
			super.update(elapsed);
			return;
		}
		if (previewOpen)
		{
			updatePreview(elapsed);
			super.update(elapsed);
			return;
		}

		updateMouse();
		updateKeys();
		pollInputBox();

		super.update(elapsed);
	}

	// ==================================================================
	//  界面构建
	// ==================================================================
	function rebuildCategories():Void
	{
		disposeAll(catRows);
		disposeSprite(catBar);
		// 层级契约（meteoric-system）：高亮条必须先于行文字 add，否则框会盖住文字
		catBar = makePanelPlain(CAT_X + 10, CAT_Y + 58, CAT_W - 20, CAT_ROW_H - 6, 12, DesignTokens.rowHighlight);
		add(catBar);
		for (i in 0...LuaBlockDefs.CATEGORIES.length)
		{
			var t:FlxText = makeText(CAT_X + 22, CAT_Y + 62 + i * CAT_ROW_H, 0, LuaBlockDefs.CATEGORIES[i][1], 20, 0xFFCFCFDC);
			add(t);
			catRows.push(t);
		}
		refreshCategoryVisual();
	}

	function refreshCategoryVisual():Void
	{
		if (catBar != null) catBar.y = CAT_Y + 58 + catIndex * CAT_ROW_H;
		for (i in 0...catRows.length)
		{
			catRows[i].alpha = (i == catIndex) ? 1 : 0.72;
			catRows[i].color = (i == catIndex) ? FlxColor.WHITE : 0xFFCFCFDC;
		}
	}

	function paletteDefs():Array<BlockDef>
	{
		return LuaBlockDefs.ofCat(LuaBlockDefs.CATEGORIES[catIndex][0]);
	}

	function rebuildPalette():Void
	{
		disposeAll(palRows);
		disposeSprite(palBar);
		var defs:Array<BlockDef> = paletteDefs();
		if (palHighlight >= defs.length) palHighlight = 0;
		var maxScroll:Int = Std.int(Math.max(0, defs.length - PAL_VISIBLE));
		if (palScroll > maxScroll) palScroll = maxScroll;

		// 同上：先 add 高亮条，再 add 行文字
		palBar = makePanelPlain(BLK_X + 12, BLK_Y + 58 + (palHighlight - palScroll) * PAL_ROW_H, BLK_W - 24, PAL_ROW_H - 6, 12, DesignTokens.rowHighlight);
		add(palBar);
		for (i in 0...PAL_VISIBLE)
		{
			var idx:Int = i + palScroll;
			var t:FlxText = makeText(BLK_X + 22, BLK_Y + 62 + i * PAL_ROW_H, BLK_W - 44, '', 18, FlxColor.WHITE);
			t.wordWrap = false;
			add(t);
			palRows.push(t);
			if (idx < defs.length) t.text = (defs[idx].hat ? '▸ ' : '▪ ') + defs[idx].label;
		}
		refreshPaletteHighlight();
		palTitle.text = '积木 · ' + LuaBlockDefs.catLabel(LuaBlockDefs.CATEGORIES[catIndex][0]);
	}

	function refreshPaletteHighlight():Void
	{
		var defs:Array<BlockDef> = paletteDefs();
		if (palBar != null) palBar.y = BLK_Y + 58 + (palHighlight - palScroll) * PAL_ROW_H;
		for (i in 0...palRows.length)
		{
			var idx:Int = i + palScroll;
			var sel:Bool = (idx == palHighlight);
			palRows[i].alpha = (idx < defs.length) ? (sel ? 1 : 0.75) : 0;
		}
		if (palDesc != null)
			palDesc.text = (palHighlight < defs.length) ? defs[palHighlight].desc : '';
	}

	/**
	 * 画布"空"的定义：没有任何**可绘制**的事件栈。
	 *
	 * ⚠ 不要用 `GDoc.isEmpty()` 控空提示：它的语义是"没有任何真实积木"（归 `LuaCodeGen.validate`
	 * 的保存前校验用），只拖了事件帽块、凹槽还空着时它仍返回 true → 提示常显并压住第一条事件栈
	 * （2026-09-15 截图复核的叠字根因）。两处语义必须分开。
	 */
	function hasDrawableStack():Bool
	{
		for (s in doc.stacks)
			if (LuaBlockDefs.byEvent(s.event) != null) return true;
		return false;
	}

	// ==================================================================
	//  资源释放（本轮修复 ①：remove 不销毁 ⇒ unique 位图只增不减）
	// ==================================================================

	/**
	 * 从显示列表摘除并**真正销毁**一个显示对象。
	 *
	 * 为什么必须有它：`FlxGroup.remove(o, true)` 只把对象从 `members` 摘掉，**不调用 destroy**
	 * （flixel 5.2.2 `FlxGroup.hx:396-420`）—— 旧代码以为它会销毁，于是每次重建画布 / 拖拽一次 /
	 * 弹层翻一页都留下新的 unique 位图（`makeGraphic(..., true)` 的结果仍留在 `FlxG.bitmap` 缓存里）。
	 *
	 * 位图释放规则（实测源码）：
	 *  - `FlxText.destroy()` 会自己释放（Meteoric 版 `FlxText.set_graphic` 调 `FlxG.bitmap.removeIfNoUse`，FlxText.hx:739）；
	 *  - 纯 `FlxSprite.destroy()` 只做 `graphic = null` + `useCount--`（haxelib FlxSprite.hx:1490-1502），
	 *    **不会**从缓存摘除 → 必须显式 `FlxG.bitmap.removeIfNoUse(g)`，否则 unique 位图常驻。
	 */
	function disposeSprite(o:FlxSprite):Void
	{
		if (o == null) return;
		remove(o, true);
		var g = Std.isOfType(o, FlxText) ? null : o.graphic;
		o.destroy();
		if (g != null) FlxG.bitmap.removeIfNoUse(g);
	}

	/** 整批释放（并把数组清空，避免悬挂引用被二次销毁）。 */
	function disposeAll<T:FlxSprite>(list:Array<T>):Void
	{
		for (o in list) disposeSprite(o);
		list.resize(0);
	}

	// ==================================================================
	//  画布布局（两遍法：先量后画）
	// ==================================================================
	function rebuildCanvas():Void
	{
		// ⚠ 顺序：`canvasBits` 里就是各 `LuaBlockSprite.texts + chips`（同一批对象）。
		// 先把全部成员摘除（remove 不销毁），再按 canvasBits 统一销毁文本/槽底，
		// 最后清空 sprite 上的引用再销毁底图 —— 顺序颠倒会对同一对象二次 destroy。
		for (s in blockSprites)
			if (s != null) remove(s, true);
		for (b in canvasBits)
			if (b != null) remove(b, true);
		disposeAll(canvasBits);
		for (s in blockSprites)
		{
			if (s == null) continue;
			s.texts.resize(0);
			s.chips.resize(0);
			disposeSprite(s);
		}
		blockSprites.resize(0);
		gaps = [];

		var y:Float = CAN_CONTENT_Y - canvasScroll;
		for (si in 0...doc.stacks.length)
		{
			var stack:GStack = doc.stacks[si];
			var hdef:BlockDef = LuaBlockDefs.byEvent(stack.event);
			if (hdef == null) continue;
			var hatBlock:GBlock = new GBlock(stack.event);
			hatBlock.params = hdef.defaultParams();
			var hm:BlockMetrics = LuaBlockSprite.measure(hdef, hatBlock, stack.blocks);
			var hx:Float = CAN_X + CAN_PAD;
			// 帽块凹槽装的是整条事件栈（模型里栈内积木与帽块同级）→ 空槽事实只能由 stack 给出
			addBlockSprite(hdef, hatBlock, [si], hx, y, hm, stack.blocks.length == 0);
			var childY:Float = y + hm.headerH + 6;
			buildChain(stack.blocks, [si], hx + LuaBlockSprite.INDENT + 10, childY);
			if (stack.blocks.length == 0)
				addGap([si], 0, hx + LuaBlockSprite.INDENT + 10, childY + 8);
			y += hm.h + STACK_GAP;
		}

		canvasEmptyHint.visible = !hasDrawableStack();
		raiseOverlay();
		refreshSelectionVisual();
	}

	/**
	 * 抬升弹层/预览层（层级契约的最后一环）。
	 *
	 * `rebuildCanvas()` 每次都把积木 `add()` 到 `members` 末尾 —— 只要弹层早已打开，
	 * 一次重建就会把积木画到**弹层之上**（2026-09-15 实测：保存被拒弹层上压着帽块与凹槽占位文案，
	 * 弹层错误行被"当脚本创建时"拦腰盖住）。所以每次重建后必须把打开中的浮层移回末尾。
	 *
	 * `FlxGroup.remove(o, true)` 只从 `members` 摘除、**不销毁对象**（flixel 5.2.2 FlxGroup.hx:396-420），
	 * 因此"摘掉再 add"就是安全的非破坏性抬层。
	 */
	function raiseOverlay():Void
	{
		if (popupOpen) moveToFront(popupSprites, popupTexts);
		if (previewOpen) moveToFront(previewSprites, previewTexts);
	}

	function moveToFront(sprites:Array<FlxSprite>, texts:Array<FlxText>):Void
	{
		for (s in sprites)
			if (s != null && members.indexOf(s) >= 0)
			{
				remove(s, true);
				add(s);
			}
		for (t in texts)
			if (t != null && members.indexOf(t) >= 0)
			{
				remove(t, true);
				add(t);
			}
	}

	function buildChain(arr:Array<GBlock>, containerPath:Array<Int>, x:Float, y:Float):Void
	{
		var curY:Float = y;
		for (i in 0...arr.length)
		{
			var b:GBlock = arr[i];
			var d:BlockDef = LuaBlockDefs.get(b.type);
			if (d == null) continue;
			var bp:Array<Int> = containerPath.concat([i]);
			addGap(containerPath, i, x, curY);
			var m:BlockMetrics = LuaBlockSprite.measure(d, b);
			addBlockSprite(d, b, bp, x, curY, m);

			if (d.body)
			{
				var cy:Float = curY + m.headerH + 6;
				var cx:Float = x + LuaBlockSprite.INDENT + 10;
				buildChain(b.body, bp.concat([0]), cx, cy);
				if (b.body.length == 0) addGap(bp.concat([0]), 0, cx, cy + 8);
			}
			if (d.alt)
			{
				var cy2:Float = curY + m.headerH + m.bodyH + LuaBlockSprite.ELSE_LABEL_H + 8;
				var cx2:Float = x + LuaBlockSprite.INDENT + 10;
				buildChain(b.elseBody, bp.concat([1]), cx2, cy2);
				if (b.elseBody.length == 0) addGap(bp.concat([1]), 0, cx2, cy2 + 8);
			}
			curY += m.h + LuaBlockSprite.CHAIN_GAP;
		}
	}

	function addBlockSprite(def:BlockDef, block:GBlock, path:Array<Int>, x:Float, y:Float, m:BlockMetrics,
			?bodyEmpty:Null<Bool> = null, ?elseEmpty:Null<Bool> = null):Void
	{
		var selected:Bool = (selPath != null && samePath(selPath, path));
		var spr:LuaBlockSprite = new LuaBlockSprite(def, block, path, x, y, m, selected, bodyEmpty, elseEmpty);
		blockSprites.push(spr);
		add(spr);
		for (t in spr.texts)
		{
			add(t);
			canvasBits.push(t);
			cullOne(t, t.y, 26);
		}
		for (c in spr.chips)
		{
			add(c);
			canvasBits.push(c);
			cullOne(c, c.y, c.height);
		}
		cullOne(spr, spr.y, m.h);
	}

	function cullOne(obj:FlxSprite, top:Float, h:Float):Void
	{
		// 上界跟着 CAN_CONTENT_Y 走：滚出画布顶部的内容在标题行/状态行之前就裁掉，
		// 否则帽块会画到「模组/脚本」状态行上面（画布没有真正的裁剪遮罩）。
		var visible:Bool = (top + h > CAN_CONTENT_Y - 24) && (top < CAN_Y + CAN_H - 6);
		obj.visible = visible;
	}

	function addGap(containerPath:Array<Int>, index:Int, x:Float, y:Float):Void
	{
		gaps.push({
			containerPath: containerPath.copy(),
			index: index,
			ax: x - 6,
			ay: y - GAP_BAND / 2,
			aw: 260,
			ah: GAP_BAND
		});
	}

	function refreshSelectionVisual():Void
	{
		for (s in blockSprites)
			s.alpha = (selPath != null && samePath(selPath, s.blockPath)) ? 1 : 0.97;
	}

	static function samePath(a:Array<Int>, b:Array<Int>):Bool
	{
		if (a == null || b == null || a.length != b.length) return false;
		for (i in 0...a.length)
			if (a[i] != b[i]) return false;
		return true;
	}

	// ==================================================================
	//  状态 / 提示
	// ==================================================================
	function refreshStatus():Void
	{
		var mod:String = Mods.currentModDirectory;
		var full:String = '模组：' + ((mod == null || mod.length == 0) ? '未选择' : mod) + '　脚本：' + doc.name + '.lua'
			+ (dirty ? '　●未保存' : '');
		// 单行 + 超长省略：模组名可以很长，但绝不允许换行压进画布内容区（④ 的根因）
		nameText.text = fitText(full, 16, CAN_NAME_W);
	}

	/** 单行文本按估宽截断加省略号（CJK≈字号、ASCII≈0.58 字号，与 LuaBlockSprite.textWidth 同源）。 */
	static function fitText(s:String, size:Int, maxW:Float):String
	{
		if (s == null) return '';
		if (maxW <= 0 || LuaBlockSprite.textWidth(s, size) <= maxW) return s;
		var out:String = '';
		var used:Float = 0;
		var ellipsisW:Float = size;
		for (i in 0...s.length)
		{
			var c:String = s.substr(i, 1);
			var cw:Float = LuaBlockSprite.textWidth(c, size);
			if (used + cw + ellipsisW > maxW) break;
			out += c;
			used += cw;
		}
		return out + '…';
	}

	function setStatus(msg:String, isError:Bool = false):Void
	{
		statusText.text = msg;
		statusText.color = isError ? COLOR_ERROR : FlxColor.WHITE;
	}

	// ==================================================================
	//  输入：鼠标
	// ==================================================================
	function updateMouse():Void
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		var pressed:Bool = FlxG.mouse.justPressed && mouseGuard <= 0;
		var down:Bool = FlxG.mouse.pressed;

		backBtn.setHovered(mx, my);
		if (backBtn.over(mx, my) && pressed)
		{
			tryLeave();
			return;
		}

		for (b in buttons)
		{
			b.setHovered(mx, my);
			if (b.over(mx, my) && pressed)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				b.click();
				return;
			}
		}

		// 正在拖拽
		if (dragKind != DRAG_NONE)
		{
			// 自检模拟拖拽期间锁住鼠标分支（真实鼠标未按下），保证插入指示能稳定留在画面上取证
			if (selfTestDragHold) return;
			if (dragSpr != null)
			{
				dragSpr.x = mx - dragOffX;
				dragSpr.y = my - dragOffY;
				dragSpr.visible = true;
			}
			updateDropHints(mx, my);
			if (!down) finishDrag(mx, my);
			return;
		}

		// 滚轮：画布滚动 / 积木列表滚动
		if (FlxG.mouse.wheel != 0)
		{
			if (mx >= CAN_X && mx <= CAN_X + CAN_W && my >= CAN_Y && my <= CAN_Y + CAN_H)
			{
				canvasScroll -= FlxG.mouse.wheel * 40;
				if (canvasScroll < 0) canvasScroll = 0;
				rebuildCanvas();
				return;
			}
			if (mx >= BLK_X && mx <= BLK_X + BLK_W && my >= BLK_Y && my <= BLK_Y + BLK_H)
			{
				var maxScroll:Int = Std.int(Math.max(0, paletteDefs().length - PAL_VISIBLE));
				palScroll -= FlxG.mouse.wheel;
				if (palScroll < 0) palScroll = 0;
				if (palScroll > maxScroll) palScroll = maxScroll;
				rebuildPalette();
				return;
			}
		}

		if (!pressed) return;

		// 分类面板
		if (mx >= CAT_X && mx <= CAT_X + CAT_W && my >= CAT_Y + 58 && my <= CAT_Y + 58 + LuaBlockDefs.CATEGORIES.length * CAT_ROW_H)
		{
			var idx:Int = Std.int((my - (CAT_Y + 58)) / CAT_ROW_H);
			if (idx >= 0 && idx < LuaBlockDefs.CATEGORIES.length && idx != catIndex)
			{
				catIndex = idx;
				palScroll = 0;
				palHighlight = 0;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				refreshCategoryVisual();
				rebuildPalette();
			}
			return;
		}

		// 积木面板：点击 = 高亮；按住拖出 = 新建积木
		if (mx >= BLK_X && mx <= BLK_X + BLK_W && my >= BLK_Y + 58 && my <= BLK_Y + 58 + PAL_VISIBLE * PAL_ROW_H)
		{
			var row:Int = Std.int((my - (BLK_Y + 58)) / PAL_ROW_H);
			var defs:Array<BlockDef> = paletteDefs();
			var idx:Int = row + palScroll;
			if (idx >= 0 && idx < defs.length)
			{
				if (idx != palHighlight)
				{
					palHighlight = idx;
					refreshPaletteHighlight();
				}
				startDragNew(defs[idx], mx, my);
			}
			return;
		}

		// 画布：命中槽位 → 编辑参数；命中积木 → 选中/拖动；空白 → 清除选中
		if (mx >= CAN_X && mx <= CAN_X + CAN_W && my >= CAN_Y && my <= CAN_Y + CAN_H)
		{
			for (s in blockSprites)
			{
				if (!s.visible) continue;
				for (slot in s.slots)
				{
					if (slot.hit(mx, my))
					{
						selPath = s.blockPath.copy();
						selParam = indexOfParam(s.def, slot.name);
						openParamEditor(s, slot);
						return;
					}
				}
			}
			for (s in blockSprites)
			{
				if (!s.visible) continue;
				if (mx >= s.x && mx <= s.x + s.metrics.w && my >= s.y && my <= s.y + s.metrics.h)
				{
					selPath = s.blockPath.copy();
					selParam = 0;
					startDragMove(s, mx, my);
					return;
				}
			}
			selPath = null;
			rebuildCanvas();
		}
	}

	function indexOfParam(def:BlockDef, name:String):Int
	{
		for (i in 0...def.params.length)
			if (def.params[i].name == name) return i;
		return 0;
	}

	function startDragNew(def:BlockDef, mx:Float, my:Float):Void
	{
		if (def.hat)
		{
			// 事件积木：直接新增一条事件栈（不能塞进普通序列里）
			pushUndo();
			doc.stacks.push(new GStack(LuaBlockDefs.eventName(def)));
			dirty = true;
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
			rebuildCanvas();
			refreshStatus();
			setStatus('已新增事件栈：' + def.label + '（拖积木到凹槽或插入线上松手即接入）');
			return;
		}
		var b:GBlock = new GBlock(def.id);
		b.params = def.defaultParams();
		dragKind = DRAG_NEW;
		dragBlock = b;
		dragOriginContainer = null;
		dragOriginIndex = 0;
		makeGhost(def, b, mx, my);
	}

	function startDragMove(s:LuaBlockSprite, mx:Float, my:Float):Void
	{
		// 只有点在"抓手区"（标题/空白处，非参数槽）才拖动
		for (slot in s.slots)
			if (slot.hit(mx, my)) return;

		var bp:Array<Int> = s.blockPath.copy();
		// 事件帽块（路径长度 1）= 一整条事件栈：在模型里不是任何序列的元素，不能拖动；
		// 点它 = 选中这条栈（随后 Del 删除整条栈，走 deleteSelected 的奇数路径分支）。
		if (bp.length % 2 == 1)
		{
			selPath = bp;
			var st:GStack = (bp[0] >= 0 && bp[0] < doc.stacks.length) ? doc.stacks[bp[0]] : null;
			var hd:BlockDef = (st == null) ? null : LuaBlockDefs.byEvent(st.event);
			refreshSelectionVisual();
			setStatus('已选中事件栈：' + ((hd != null) ? hd.label : (st == null ? '未知' : st.event)) + '（Del 删除整条栈）');
			return;
		}
		dragOriginIndex = bp[bp.length - 1];
		dragOriginContainer = bp.slice(0, bp.length - 1);
		pushUndo();
		var taken:GBlock = GDoc.detach(doc, bp);
		if (taken == null)
		{
			popUndoWithoutChange();
			return;
		}
		dragKind = DRAG_MOVE;
		dragBlock = taken;
		dirty = true;
		selPath = null;
		// 先重建画布、再建「幽灵块 + 插入指示」：反过来的话重建时新 add 的积木会盖在它们上面，
		// 拖拽中的积木与插入线都会被自己挡住（层级契约）。
		rebuildCanvas();
		makeGhost(s.def, taken, mx, my);
	}

	function makeGhost(def:BlockDef, b:GBlock, mx:Float, my:Float):Void
	{
		var m:BlockMetrics = LuaBlockSprite.measure(def, b);
		dragOffX = 40;
		dragOffY = 18;
		dragSpr = new LuaBlockSprite(def, b, [-1], mx - dragOffX, my - dragOffY, m, false);
		dragSpr.alpha = 0.85;
		add(dragSpr);
		for (t in dragSpr.texts) add(t);
		for (c in dragSpr.chips) add(c);
		showDropHints();
	}

	/**
	 * 把插入点画出来（⑥）：每个 gap 画一条插入线，最近的插入点用 primary 高亮。
	 *
	 * 为什么要画：`addGap()` 只往 gaps 数组里塞了一个 16px 高的**不可见**命中带，
	 * 用户看不到"第二块积木该接到哪"（2026-09-15 反馈：不知道怎么把第二块接到第一块上）。
	 * 绘制纪律：拖拽期间**不重建**（不逐帧 makeGraphic），只移动高亮条 → 每帧 O(1)。
	 */
	function showDropHints():Void
	{
		clearDropHints();
		for (g in gaps)
		{
			var lw:Float = Math.min(g.aw, CAN_X + CAN_W - 8 - g.ax);
			if (lw < 24) continue;
			var spr:FlxSprite = new FlxSprite(g.ax, g.ay + g.ah / 2 - DROP_LINE_H / 2)
				.makeGraphic(Std.int(lw), Std.int(DROP_LINE_H), FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRoundRect(spr, 0, 0, lw, DROP_LINE_H, DROP_LINE_H / 2, DROP_LINE_H / 2, DROP_LINE_COLOR);
			spr.scrollFactor.set();
			add(spr);
			dropHints.push(spr);
		}
		dropCursor = new FlxSprite(0, 0).makeGraphic(Std.int(DROP_CURSOR_W), Std.int(DROP_CURSOR_H), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(dropCursor, 0, 0, DROP_CURSOR_W, DROP_CURSOR_H, DROP_CURSOR_H / 2, DROP_CURSOR_H / 2,
			DesignTokens.primary);
		dropCursor.scrollFactor.set();
		dropCursor.visible = false;
		add(dropCursor);
	}

	/** 拖拽中每帧只夹一次"最近的插入点"；鼠标不在画布内 → 高亮条隐藏（松手会给失败反馈）。 */
	function updateDropHints(mx:Float, my:Float):Void
	{
		if (dropCursor == null) return;
		var g:LuaGraphGap = nearestGap(mx, my);
		if (g == null)
		{
			dropCursor.visible = false;
			return;
		}
		dropCursor.visible = true;
		dropCursor.x = Math.min(g.ax, CAN_X + CAN_W - 8 - DROP_CURSOR_W);
		dropCursor.y = g.ay + g.ah / 2 - DROP_CURSOR_H / 2;
	}

	function clearDropHints():Void
	{
		disposeAll(dropHints);
		disposeSprite(dropCursor);
		dropCursor = null;
	}

	function clearGhost():Void
	{
		clearDropHints();
		if (dragSpr == null) return;
		// 幽灵块的文本/槽底与底图都只销毁一次（remove 不销毁，必须走 disposeSprite）
		disposeAll(dragSpr.texts);
		disposeAll(dragSpr.chips);
		disposeSprite(dragSpr);
		dragSpr = null;
	}

	function nearestGap(mx:Float, my:Float):LuaGraphGap
	{
		if (mx < CAN_X || mx > CAN_X + CAN_W || my < CAN_Y || my > CAN_Y + CAN_H) return null;
		var best:LuaGraphGap = null;
		var bestD:Float = 1e9;
		for (g in gaps)
		{
			var dx:Float = mx - (g.ax + 40);
			var dy:Float = my - (g.ay + g.ah / 2);
			var d:Float = dx * dx + dy * dy;
			if (d < bestD)
			{
				bestD = d;
				best = g;
			}
		}
		return best;
	}

	function finishDrag(mx:Float, my:Float):Void
	{
		var block:GBlock = dragBlock;
		var wasNew:Bool = (dragKind == DRAG_NEW);
		clearGhost();
		dragKind = DRAG_NONE;
		dragBlock = null;

		if (block == null) return;
		var gap:LuaGraphGap = nearestGap(mx, my);
		if (gap == null)
		{
			// 没落在任何插入线上：**不再静默丢弃** —— 新积木凭空消失会让用户以为拖拽坏了，
			// 一律给状态条红色反馈 + 取消音，并说明正确落点（2026-09-15 反馈）。
			if (!wasNew)
			{
				// 原地放回
				var arr:Array<GBlock> = GDoc.containerOf(doc, dragOriginContainer);
				var at:Int = Std.int(Math.max(0, Math.min(dragOriginIndex, arr.length)));
				arr.insert(at, block);
				setStatus('放回原位：要接进事件栈，拖到插入线或凹槽上松手', true);
			}
			else
			{
				setStatus('没接上：拖到插入线或凹槽上再松手', true);
			}
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
			rebuildCanvas();
			refreshStatus();
			return;
		}
		var arr2:Array<GBlock> = GDoc.containerOf(doc, gap.containerPath);
		var idx:Int = Std.int(Math.max(0, Math.min(gap.index, arr2.length)));
		arr2.insert(idx, block);
		selPath = gap.containerPath.concat([idx]);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		rebuildCanvas();
		refreshStatus();
		setStatus('已放置积木（共 ' + doc.blockCount() + ' 块）');
	}

	// ==================================================================
	//  输入：键盘
	// ==================================================================
	function updateKeys():Void
	{
		var ctrl:Bool = FlxG.keys.pressed.CONTROL;

		if (inputBox != null && inputBox.hasFocus) return; // 文本输入中不抢按键

		if (FlxG.keys.justPressed.ESCAPE)
		{
			tryLeave();
			return;
		}
		if (FlxG.keys.justPressed.TAB)
		{
			openPreview();
			return;
		}
		if (FlxG.keys.justPressed.F1)
		{
			openHelp();
			return;
		}
		if (FlxG.keys.justPressed.LBRACKET)
		{
			catIndex = (catIndex - 1 + LuaBlockDefs.CATEGORIES.length) % LuaBlockDefs.CATEGORIES.length;
			palScroll = 0;
			palHighlight = 0;
			refreshCategoryVisual();
			rebuildPalette();
			return;
		}
		if (FlxG.keys.justPressed.RBRACKET)
		{
			catIndex = (catIndex + 1) % LuaBlockDefs.CATEGORIES.length;
			palScroll = 0;
			palHighlight = 0;
			refreshCategoryVisual();
			rebuildPalette();
			return;
		}
		if (FlxG.keys.justPressed.PAGEDOWN)
		{
			palScroll = Std.int(Math.min(Math.max(0, paletteDefs().length - PAL_VISIBLE), palScroll + 1));
			rebuildPalette();
			return;
		}
		if (FlxG.keys.justPressed.PAGEUP)
		{
			palScroll = Std.int(Math.max(0, palScroll - 1));
			rebuildPalette();
			return;
		}
		if (FlxG.keys.justPressed.COMMA || FlxG.keys.justPressed.PERIOD)
		{
			var defs:Array<BlockDef> = paletteDefs();
			if (defs.length > 0)
			{
				palHighlight += FlxG.keys.justPressed.COMMA ? -1 : 1;
				if (palHighlight < 0) palHighlight = 0;
				if (palHighlight > defs.length - 1) palHighlight = defs.length - 1;
				if (palHighlight < palScroll) palScroll = palHighlight;
				if (palHighlight >= palScroll + PAL_VISIBLE) palScroll = palHighlight - PAL_VISIBLE + 1;
				rebuildPalette();
			}
			return;
		}
		if (FlxG.keys.justPressed.INSERT)
		{
			insertPaletteBlock();
			return;
		}
		if (FlxG.keys.justPressed.S && ctrl)
		{
			saveScript();
			return;
		}
		if (FlxG.keys.justPressed.O && ctrl)
		{
			openChooser();
			return;
		}
		if (FlxG.keys.justPressed.Z && ctrl)
		{
			undo();
			return;
		}
		if (FlxG.keys.justPressed.Y && ctrl)
		{
			redo();
			return;
		}
		if (FlxG.keys.justPressed.C && ctrl)
		{
			copySelected(false);
			return;
		}
		if (FlxG.keys.justPressed.X && ctrl)
		{
			copySelected(true);
			return;
		}
		if (FlxG.keys.justPressed.V && ctrl)
		{
			pasteClipboard();
			return;
		}
		if (FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE)
		{
			deleteSelected();
			return;
		}
		if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
		{
			var dir:Int = FlxG.keys.justPressed.UP ? -1 : 1;
			if (ctrl) moveSelected(dir);
			else moveSelection(dir);
			return;
		}
		if (FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.RIGHT)
		{
			cycleParam(FlxG.keys.justPressed.LEFT ? -1 : 1);
			return;
		}
		if (FlxG.keys.justPressed.ENTER)
		{
			editSelectedParam();
			return;
		}
		if (FlxG.keys.justPressed.F2)
		{
			renameScript();
			return;
		}
	}

	function selectedBlock():GBlock
	{
		if (selPath == null) return null;
		return GDoc.blockAt(doc, selPath);
	}

	function moveSelection(dir:Int):Void
	{
		var flat:Array<Array<Int>> = doc.flattenPaths();
		if (flat.length == 0) return;
		var cur:Int = -1;
		if (selPath != null)
			for (i in 0...flat.length)
				if (samePath(flat[i], selPath)) cur = i;
		cur += dir;
		if (cur < 0) cur = 0;
		if (cur > flat.length - 1) cur = flat.length - 1;
		selPath = flat[cur].copy();
		selParam = 0;
		rebuildCanvas();
	}

	function moveSelected(dir:Int):Void
	{
		var b:GBlock = selectedBlock();
		if (b == null || selPath == null) return;
		var parent:Array<Int> = selPath.slice(0, selPath.length - 1);
		var idx:Int = selPath[selPath.length - 1];
		var arr:Array<GBlock> = GDoc.containerOf(doc, parent);
		var to:Int = idx + dir;
		if (to < 0 || to >= arr.length) return;
		pushUndo();
		var tmp:GBlock = arr[idx];
		arr[idx] = arr[to];
		arr[to] = tmp;
		selPath = parent.concat([to]);
		dirty = true;
		rebuildCanvas();
		refreshStatus();
	}

	function cycleParam(dir:Int):Void
	{
		var b:GBlock = selectedBlock();
		if (b == null) return;
		var d:BlockDef = LuaBlockDefs.get(b.type);
		if (d == null || d.params.length == 0) return;
		if (selParam < 0) selParam = 0;
		if (selParam > d.params.length - 1) selParam = d.params.length - 1;
		var p:PDef = d.params[selParam];
		var cur:String = b.get(p.name, p.def);
		switch (p.kind)
		{
			case KEnum(options):
				var at:Int = options.indexOf(cur);
				if (at < 0) at = 0;
				at = (at + dir + options.length) % options.length;
				pushUndo();
				b.set(p.name, options[at]);
				dirty = true;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.3);
				rebuildCanvas();
				refreshStatus();
			case KNum:
				var f:Float = Std.parseFloat(cur);
				if (Math.isNaN(f)) f = 0;
				f += dir * ((Math.abs(f) >= 10) ? 1 : 0.1);
				pushUndo();
				b.set(p.name, Std.string(Math.round(f * 1000) / 1000));
				dirty = true;
				rebuildCanvas();
				refreshStatus();
			default:
				setStatus('参数「' + p.label + '」需要按 Enter 输入');
		}
	}

	function editSelectedParam():Void
	{
		var b:GBlock = selectedBlock();
		if (b == null || selPath == null) return;
		var d:BlockDef = LuaBlockDefs.get(b.type);
		if (d == null || d.params.length == 0) return;
		if (selParam < 0) selParam = 0;
		if (selParam > d.params.length - 1) selParam = d.params.length - 1;
		var p:PDef = d.params[selParam];
		// 找到该积木的对应槽位（用于把输入框定位到槽上）
		for (s in blockSprites)
		{
			if (!samePath(s.blockPath, selPath)) continue;
			for (slot in s.slots)
				if (slot.name == p.name)
				{
					openParamEditor(s, slot);
					return;
				}
		}
	}

	function insertPaletteBlock():Void
	{
		var defs:Array<BlockDef> = paletteDefs();
		if (palHighlight < 0 || palHighlight >= defs.length) return;
		var def:BlockDef = defs[palHighlight];
		if (def.hat)
		{
			pushUndo();
			doc.stacks.push(new GStack(LuaBlockDefs.eventName(def)));
			dirty = true;
			rebuildCanvas();
			refreshStatus();
			setStatus('已新增事件栈：' + def.label + '（拖积木到凹槽或按 Insert 接入）');
			return;
		}
		var b:GBlock = new GBlock(def.id);
		b.params = def.defaultParams();
		// 插入位置：选中积木所在序列的其后，否则最后一条事件栈的末尾
		var containerPath:Array<Int> = null;
		var idx:Int = 0;
		if (selPath != null)
		{
			containerPath = selPath.slice(0, selPath.length - 1);
			idx = selPath[selPath.length - 1] + 1;
		}
		else
		{
			containerPath = [doc.stacks.length - 1];
			idx = doc.stacks[doc.stacks.length - 1].blocks.length;
		}
		pushUndo();
		var arr:Array<GBlock> = GDoc.containerOf(doc, containerPath);
		arr.insert(Std.int(Math.max(0, Math.min(idx, arr.length))), b);
		selPath = containerPath.concat([Std.int(Math.max(0, Math.min(idx, arr.length - 1)))]);
		dirty = true;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		rebuildCanvas();
		refreshStatus();
		setStatus('已插入：' + def.label);
	}

	function deleteSelected():Void
	{
		// 无选中时给反馈，不要静默（点一下画布空白就会清选中，用户会以为"删除坏了"）
		if (selPath == null)
		{
			setStatus('没选中东西：先点一下画布上的积木，或点事件帽块删整条事件栈', true);
			return;
		}

		// 事件帽块 = 一整条事件栈：路径长度为奇数（[栈下标]），模型里它不是任何序列的元素，
		// `GDoc.detach()` 对奇数路径直接返回 null（GDoc.hx:155）→ 旧代码在此静默 no-op，
		// 而点一下「事件」积木就会新增一条栈 ⇒ 用户"只能加、不能减"（2026-09-15 反馈）。
		if (selPath.length % 2 == 1)
		{
			var si:Int = selPath[0];
			if (si < 0 || si >= doc.stacks.length)
			{
				setStatus('删除失败：这条事件栈已经不存在了', true);
				selPath = null;
				return;
			}
			var st:GStack = doc.stacks[si];
			var hd:BlockDef = LuaBlockDefs.byEvent(st.event);
			var lbl:String = (hd != null) ? hd.label : st.event;
			var inner:Int = st.blocks.length;
			pushUndo();
			doc.stacks.splice(si, 1);
			selPath = null;
			dirty = true;
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
			rebuildCanvas();
			refreshStatus();
			setStatus('已删除事件栈：' + lbl + (inner > 0 ? '（含 ' + inner + ' 块积木）' : '') + '（Ctrl+Z 可撤销）');
			return;
		}

		pushUndo();
		var b:GBlock = GDoc.detach(doc, selPath);
		if (b == null)
		{
			popUndoWithoutChange();
			setStatus('删除失败：这块积木已经不在图里了', true);
			return;
		}
		selPath = null;
		dirty = true;
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
		rebuildCanvas();
		refreshStatus();
		setStatus('已删除积木（Ctrl+Z 可撤销）');
	}

	function copySelected(cut:Bool):Void
	{
		var b:GBlock = selectedBlock();
		if (b == null) return;
		clipboard = b.clone();
		if (cut) deleteSelected();
		else setStatus('已复制积木（Ctrl+V 粘贴）');
	}

	function pasteClipboard():Void
	{
		if (clipboard == null)
		{
			setStatus('剪贴板是空的', true);
			return;
		}
		var containerPath:Array<Int> = null;
		var idx:Int = 0;
		if (selPath != null)
		{
			containerPath = selPath.slice(0, selPath.length - 1);
			idx = selPath[selPath.length - 1] + 1;
		}
		else
		{
			containerPath = [doc.stacks.length - 1];
			idx = doc.stacks[doc.stacks.length - 1].blocks.length;
		}
		pushUndo();
		var arr:Array<GBlock> = GDoc.containerOf(doc, containerPath);
		arr.insert(Std.int(Math.max(0, Math.min(idx, arr.length))), clipboard.clone());
		selPath = containerPath.concat([Std.int(Math.max(0, Math.min(idx, arr.length - 1)))]);
		dirty = true;
		rebuildCanvas();
		refreshStatus();
		setStatus('已粘贴积木');
	}

	function pushUndo():Void
	{
		undoStack.push(doc.toJsonString());
		if (undoStack.length > MAX_UNDO) undoStack.shift();
		redoStack = [];
	}

	function popUndoWithoutChange():Void
	{
		if (undoStack.length > 0) undoStack.pop();
	}

	function undo():Void
	{
		if (undoStack.length == 0)
		{
			setStatus('没有可撤销的操作');
			return;
		}
		redoStack.push(doc.toJsonString());
		applySnapshot(undoStack.pop());
		setStatus('已撤销');
	}

	function redo():Void
	{
		if (redoStack.length == 0)
		{
			setStatus('没有可重做的操作');
			return;
		}
		undoStack.push(doc.toJsonString());
		applySnapshot(redoStack.pop());
		setStatus('已重做');
	}

	function applySnapshot(json:String):Void
	{
		var name:String = doc.name;
		try
		{
			doc = GDoc.parse(json);
		}
		catch (e:Dynamic)
		{
			setStatus('撤销失败：' + Std.string(e), true);
			return;
		}
		doc.name = name;
		selPath = null;
		dirty = true;
		rebuildCanvas();
		refreshStatus();
	}

	// ==================================================================
	//  参数编辑
	// ==================================================================
	function openParamEditor(spr:LuaBlockSprite, slot:SlotHit):Void
	{
		switch (slot.kind)
		{
			case KEnum(options):
				// 闭包只捕获**路径副本**：弹层打开期间画布可能重建（本轮起 destroy 是真销毁，
				// 不再是"只从 members 摘除"），捕获 sprite 本身会读到已销毁对象。
				var slotPath:Array<Int> = spr.blockPath.copy();
				var b:GBlock = GDoc.blockAt(doc, slotPath);
				var cur:String = b == null ? '' : b.get(slot.name, '');
				openPopup('选择「' + slot.label + '」的取值', options, function(pick)
				{
					var bb:GBlock = GDoc.blockAt(doc, slotPath);
					if (bb == null) return;
					pushUndo();
					bb.set(slot.name, pick);
					dirty = true;
					rebuildCanvas();
					refreshStatus();
				}, cur);
			default:
				closeInputBox();
				inputSlot = slot;
				inputPath = spr.blockPath.copy();
				var b2:GBlock = GDoc.blockAt(doc, inputPath);
				var val:String = b2 == null ? '' : b2.get(slot.name, '');
				inputBox = new UIInputBox(slot.ax, slot.ay - 6, Std.int(Math.max(160, slot.aw + 60)), Std.int(slot.ah + 12), val, 18, 120);
				inputBox.onEnter = commitInputBox;
				add(inputBox);
				inputBox.setNativeFocus(true);
				inputHadFocus = true;
				setStatus('编辑「' + slot.label + '」：输入后按 Enter 确认（Esc 取消）');
		}
	}

	function pollInputBox():Void
	{
		if (inputBox == null) return;
		if (inputHadFocus && !inputBox.hasFocus && !FlxG.mouse.pressed)
			commitInputBox();
		if (FlxG.keys.justPressed.ESCAPE) closeInputBox();
	}

	function commitInputBox():Void
	{
		if (inputBox == null || inputSlot == null || inputPath == null)
		{
			closeInputBox();
			return;
		}
		var b:GBlock = GDoc.blockAt(doc, inputPath);
		var slot:SlotHit = inputSlot;
		var raw:String = inputBox.text;
		closeInputBox();
		if (b == null || slot == null) return;
		var p:PDef = LuaBlockDefs.get(b.type) == null ? null : LuaBlockDefs.get(b.type).param(slot.name);
		if (p != null && p.kind == KNum)
		{
			if (Math.isNaN(Std.parseFloat(StringTools.trim(raw))))
			{
				setStatus('「' + slot.label + '」必须是数字，已保留原值', true);
				return;
			}
		}
		pushUndo();
		b.set(slot.name, raw);
		dirty = true;
		rebuildCanvas();
		refreshStatus();
		setStatus('已修改参数「' + slot.label + '」');
	}

	function closeInputBox():Void
	{
		if (inputBox != null)
		{
			inputBox.setNativeFocus(false);
			// ⚠ 必须 destroy：UIInputBox.destroy() 会把**原生输入框**从 stage 摘掉并解绑监听；
			// 只 remove 会留下一个僵尸原生 TextField（每次编辑参数泄漏一个）。
			remove(inputBox, true);
			inputBox.destroy();
			inputBox = null;
		}
		inputSlot = null;
		inputPath = null;
		inputHadFocus = false;
	}

	// ==================================================================
	//  弹出层（通用清单 / 选项）
	// ==================================================================
	var popupTitle:String = '';

	/** `F1` 操作说明：完整键位表（底栏两行只放高频项）。复用弹层 ⇒ 自动在积木之上、可滚动、Esc 关闭。 */
	function openHelp():Void
	{
		openPopup('操作说明（F1 / Esc 关闭 · ↑↓ 或滚轮 翻页）', HELP_LINES.copy(), null);
	}

	function openPopup(title:String, items:Array<String>, pick:String->Void, ?current:String):Void
	{
		closePopup();
		popupOpen = true;
		popupTitle = title;
		popupAll = items;
		popupPick = pick;
		popupScroll = 0;
		popupHover = (current != null) ? items.indexOf(current) : 0;
		if (popupHover < 0) popupHover = 0;
		popupHover = Std.int(Math.max(0, Math.min(popupHover, items.length - 1)));
		renderPopup();
		setStatus(title);
	}

	/** 只重建弹层的可视元素（hover/滚动改变时复用，不重建整个弹层）。 */
	function renderPopup():Void
	{
		disposeAll(popupSprites);
		disposeAll(popupTexts);

		var scrim:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0x99000000);
		scrim.scrollFactor.set();
		add(scrim);
		popupSprites.push(scrim);

		var pw:Float = 620;
		var ph:Float = 460;
		var px:Float = (FlxG.width - pw) / 2;
		var py:Float = (FlxG.height - ph) / 2 - 20;

		var panel:FlxSprite = makePanel(px, py, pw, ph, 22);
		add(panel);
		popupSprites.push(panel);

		var t:FlxText = makeText(px + 24, py + 18, pw - 48, popupTitle, 22, FlxColor.WHITE);
		add(t);
		popupTexts.push(t);

		var rows:Int = 10;
		var start:Int = Std.int(Math.max(0, Math.min(popupHover - 4, Math.max(0, popupAll.length - rows))));
		popupScroll = start;
		for (i in 0...rows)
		{
			var idx:Int = start + i;
			if (idx >= popupAll.length) break;
			var ry:Float = py + 62 + i * 34;
			var rowBg:FlxSprite = makePanelPlain(px + 18, ry - 4, pw - 36, 32, 10,
				(idx == popupHover) ? DesignTokens.rowHighlight : 0x00000000);
			add(rowBg);
			popupSprites.push(rowBg);
			var rt:FlxText = makeText(px + 32, ry, pw - 64, popupAll[idx], 18, FlxColor.WHITE);
			rt.alpha = (idx == popupHover) ? 1 : 0.82;
			add(rt);
			popupTexts.push(rt);
		}

		var hint:FlxText = makeText(px + 24, py + ph - 34, pw - 48, '滚轮/↑↓ 选择 · 点击或 Enter 确认 · Esc 取消', 14, 0xFFCFCFDC);
		add(hint);
		popupTexts.push(hint);
	}

	function closePopup():Void
	{
		disposeAll(popupSprites);
		disposeAll(popupTexts);
		popupOpen = false;
		popupPick = null;
		popupAll = [];
	}

	function updatePopup():Void
	{
		if (FlxG.keys.justPressed.ESCAPE)
		{
			closePopup();
			setStatus('已取消');
			return;
		}
		var moved:Int = 0;
		if (FlxG.keys.justPressed.UP) moved = -1;
		if (FlxG.keys.justPressed.DOWN) moved = 1;
		if (FlxG.mouse.wheel > 0) moved = -1;
		if (FlxG.mouse.wheel < 0) moved = 1;
		if (moved != 0 && popupAll.length > 0)
		{
			popupHover += moved;
			popupHover = Std.int(Math.max(0, Math.min(popupHover, popupAll.length - 1)));
			renderPopup();
			return;
		}
		if (FlxG.keys.justPressed.ENTER)
		{
			pickPopup(popupHover);
			return;
		}
		if (FlxG.mouse.justPressed)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;
			var pw:Float = 620;
			var ph:Float = 460;
			var px:Float = (FlxG.width - pw) / 2;
			var py:Float = (FlxG.height - ph) / 2 - 20;
			for (i in 0...10)
			{
				var ry:Float = py + 62 + i * 34;
				if (mx >= px + 18 && mx <= px + pw - 18 && my >= ry - 4 && my <= ry + 28)
				{
					pickPopup(popupScroll + i);
					return;
				}
			}
			if (mx < px || mx > px + pw || my < py || my > py + ph) closePopup();
		}
	}

	function pickPopup(idx:Int):Void
	{
		if (idx < 0 || idx >= popupAll.length)
		{
			closePopup();
			return;
		}
		var value:String = popupAll[idx];
		var cb:String->Void = popupPick;
		closePopup();
		if (cb != null) cb(value);
	}

	// ==================================================================
	//  预览层
	// ==================================================================
	function openPreview():Void
	{
		previewOpen = true;
		previewScroll = 0;
		rebuildPreview();
	}

	function rebuildPreview():Void
	{
		disposeAll(previewSprites);
		disposeAll(previewTexts);

		var pw:Float = 900;
		var ph:Float = 560;
		var px:Float = (FlxG.width - pw) / 2;
		var py:Float = (FlxG.height - ph) / 2 - 10;

		var scrim:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0x99000000);
		scrim.scrollFactor.set();
		add(scrim);
		previewSprites.push(scrim);

		var panel:FlxSprite = makePanel(px, py, pw, ph, 22);
		add(panel);
		previewSprites.push(panel);

		var gen:String = '';
		try gen = LuaCodeGen.generate(doc) catch (e:Dynamic) gen = '-- 生成失败：' + Std.string(e) + '\n';
		previewAll = gen.split('\n');

		var issues:Array<String> = LuaCodeGen.validate(doc);
		var head:String = '生成预览（只读，不会自动执行）　共 ' + previewAll.length + ' 行　积木 ' + doc.blockCount() + ' 块';
		add(makePreviewText(px + 24, py + 16, pw - 48, head, 20, FlxColor.WHITE));
		var issueLine:String = (issues.length == 0) ? '校验：通过（无错误与警告）' : ('校验：' + issues.length + ' 条提示 —— ' + issues[0]);
		add(makePreviewText(px + 24, py + 44, pw - 48, issueLine, 15,
			(issues.length == 0) ? COLOR_OK : COLOR_ERROR));

		// 代码正文（可视行）：按面板可用高度反算，禁止压到底部提示行
		// 起始 y = py+78、行高 21、底部预留 40 → visible = (ph - 78 - 40) / 21 = 21 → 取 20 留一行余量
		var visible:Int = Std.int(Math.max(4, Math.floor((ph - 78 - 40) / 21)));
		var start:Int = Std.int(Math.max(0, Math.min(previewScroll, Math.max(0, previewAll.length - visible))));
		previewScroll = start;
		for (i in 0...visible)
		{
			var idx:Int = start + i;
			if (idx >= previewAll.length) break;
			var line:String = previewAll[idx];
			if (line.length > 96) line = line.substr(0, 96) + '…';
			add(makePreviewText(px + 24, py + 78 + i * 21, pw - 48, (idx + 1) + '  ' + line, 15, 0xFFE6E6F0));
		}
		add(makePreviewText(px + 24, py + ph - 30, pw - 48, '滚轮/PgUp/PgDn 翻页 · Tab 或 Esc 关闭', 14, 0xFFCFCFDC));
	}

	function makePreviewText(x:Float, y:Float, w:Float, txt:String, size:Int, color:Int):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, txt, size);
		t.setFormat(Paths.font('future.ttf'), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1;
		t.scrollFactor.set();
		t.wordWrap = false;
		previewTexts.push(t);
		return t;
	}

	function updatePreview(elapsed:Float):Void
	{
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.TAB)
		{
			closePreview();
			return;
		}
		if (FlxG.keys.justPressed.PAGEDOWN || FlxG.keys.justPressed.DOWN) previewScroll += 4;
		if (FlxG.keys.justPressed.PAGEUP || FlxG.keys.justPressed.UP) previewScroll -= 4;
		if (FlxG.mouse.wheel != 0) previewScroll -= Std.int(FlxG.mouse.wheel) * 3;
		if (previewScroll < 0) previewScroll = 0;
		rebuildPreview();
	}

	function closePreview():Void
	{
		disposeAll(previewSprites);
		disposeAll(previewTexts);
		previewOpen = false;
	}

	// ==================================================================
	//  文件操作
	// ==================================================================
	function newScript():Void
	{
		openPopup('新建：选择模板', LuaGraphTemplates.NAMES, function(pick)
		{
			var idx:Int = LuaGraphTemplates.NAMES.indexOf(pick);
			if (idx < 0) idx = 0;
			doc = LuaGraphTemplates.make(idx, doc.name);
			undoStack = [];
			redoStack = [];
			selPath = null;
			canvasScroll = 0;
			dirty = true;
			rebuildCanvas();
			refreshStatus();
			setStatus('已套用模板：' + pick + '（保存后生成 .lua 与 .luagraph.json）');
		});
	}

	function openChooser():Void
	{
		#if sys
		if (!LuaGraphIO.hasTargetMod())
		{
			setStatus('未选择模组：请返回编辑器菜单，用 ←/→ 选择目标模组', true);
			return;
		}
		var list:Array<String> = LuaGraphIO.listGraphs();
		if (list.length == 0)
		{
			setStatus('该模组 scripts/ 下还没有图形化脚本（用「新建」开始）', true);
			return;
		}
		openPopup('打开图形化脚本（' + Mods.currentModDirectory + '/scripts/）', list, function(pick) loadGraph(pick));
		#end
	}

	function loadGraph(name:String):Void
	{
		#if sys
		try
		{
			doc = LuaGraphIO.readGraph(name);
			doc.name = name;
			undoStack = [];
			redoStack = [];
			selPath = null;
			canvasScroll = 0;
			dirty = false;
			rebuildCanvas();
			refreshStatus();
			setStatus('已打开：' + name + '（积木 ' + doc.blockCount() + ' 块）');
		}
		catch (e:Dynamic)
		{
			setStatus('打开失败：' + Std.string(e), true);
		}
		#end
	}

	function renameScript():Void
	{
		openSubState(new TextInputPrompt('脚本名称', '生成的 .lua 与 .luagraph.json 都用这个名字', doc.name, function(v:String)
		{
			var clean:String = LuaGraphIO.sanitizeFileName(v);
			if (clean != doc.name)
			{
				doc.name = clean;
				dirty = true;
				refreshStatus();
				setStatus('已改名：' + clean + '（保存时按新名字写盘）');
			}
		}));
	}

	function saveScript():Void
	{
		#if sys
		if (!LuaGraphIO.hasTargetMod())
		{
			setStatus('未选择模组：请返回编辑器菜单，用 ←/→ 选择目标模组后再保存', true);
			return;
		}
		var issues:Array<String> = LuaCodeGen.validate(doc);
		var errors:Array<String> = [];
		for (i in issues)
			if (StringTools.startsWith(i, '错误：')) errors.push(i);
		if (errors.length > 0)
		{
			var msg:String = errors[0];
			if (errors.length > 1) msg += '（另有 ' + (errors.length - 1) + ' 条错误）';
			setStatus('无法保存：' + msg, true);
			openPopup('无法保存：请先修正以下问题', errors, null);
			return;
		}

		var name:String = LuaGraphIO.sanitizeFileName(doc.name);
		doc.name = name;
		var existed:String = LuaGraphIO.readLua(name);
		if (existed != null)
		{
			var custom:String = LuaGraphIO.extractCustom(existed);
			if (custom != null)
			{
				// 之前就是本编辑器生成的：保留其自定义区
				doc.custom = custom;
				writeAll(name);
			}
			else
			{
				openSubState(new Prompt('脚本 ' + name + '.lua 已存在，且不是图形化编辑器生成的。\n继续会把现有内容整体搬进文件底部的「自定义代码区」（不会丢失），确定吗？',
					0, function()
				{
					doc.custom = existed;
					writeAll(name);
				}, null, false, '确定', '取消'));
			}
			return;
		}
		writeAll(name);
		#end
	}

	function writeAll(name:String):Void
	{
		#if sys
		try
		{
			var lua:String = LuaCodeGen.generate(doc);
			LuaGraphIO.saveAll(doc, lua);
			dirty = false;
			refreshStatus();
			if (previewOpen) rebuildPreview();
			setStatus('已生成并保存：mods/' + Mods.currentModDirectory + '/scripts/' + name + '.lua（' + LuaCodeGen.countLines(lua)
				+ ' 行）与 ' + name + LuaGraphIO.GRAPH_EXT);
		}
		catch (e:Dynamic)
		{
			setStatus('保存失败：' + Std.string(e), true);
		}
		#end
	}

	function tryLeave():Void
	{
		if (!dirty)
		{
			MusicBeatState.switchState(new MasterEditorMenu());
			return;
		}
		openSubState(new Prompt('当前图形化脚本有未保存的改动，确定要离开吗？', 1, function()
		{
			MusicBeatState.switchState(new MasterEditorMenu());
		}, null, false, '离开', '继续编辑'));
	}

	// ==================================================================
	//  样式辅助（与 MasterEditorMenu 同款令牌化写法）
	// ==================================================================
	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function makePanelPlain(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Int):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		if ((fill & 0xFF000000) != 0)
			FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		spr.scrollFactor.set();
		return spr;
	}

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, ?color:Int = 0xFFD7D7E0):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('future.ttf'), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		return t;
	}
}
