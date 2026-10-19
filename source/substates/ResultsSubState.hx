package substates;
import backend.Lang;
import backend.WheelScroll;

import backend.Highscore;
import backend.PhigrosRating;
import backend.PhigrosRating.PhigrosResult;

import flixel.math.FlxPoint;
import flixel.util.FlxGradient;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxStringUtil;
import openfl.Lib;
import objects.NoteHitGraph;
import objects.NoteHitGraph.NoteHitEntry;

/**
 * 本局结算界面（Meteoric 风格重排版，信息结构对齐 KE 1.8：
 * 左侧 = 曲目信息 + 判定统计(Judgements) + 操作菜单；
 * 右侧 = 本局数据(分数/最高连击/准确度…) + KE 命中判定散点图（大图）。
 * 中英混合：标题/说明中文，SICK/GOOD/BAD/SHIT/MISS 保留判定缩写。
 */
class ResultsSubState extends MusicBeatSubstate
{
	var wheelScroll:WheelScroll = new WheelScroll(); // 滚轮限速（Freeplay 同款）

	// ===== 安全布局常量（1280×720 基准） =====
	// ⚠ 底部安全线 648：底部要放操作按钮行 + 操作提示，两行共占 ~90px，
	//   所以**任何卡片都不得越过 648**，否则按钮/提示会被挤出画面。
	//   （改版前 MENU_Y 是常量链 `PGR_Y + PGR_H + 14` = 650，菜单卡 650..754
	//     直接溢出 720 画布 34px、提示文字 766..788 完全不可见。）
	static final TITLE_Y:Float = 22;
	static final PANEL_TOP:Float = 96;
	static final SAFE_BOTTOM:Float = 648;
	static final PANEL_X:Float = 40;
	static final PANEL_W:Float = 560;
	static final RIGHT_X:Float = 620;
	static final RIGHT_W:Float = 620;
	static final TEXT_PAD:Float = 20;
	static final CARD_GAP:Float = 14;

	// ---- 底部：操作提示 + 按钮行（横排，每个选项一个独立按钮） ----
	static final HINT_Y:Float = 566;
	static final MENU_Y:Float = 600;
	/** 按钮行可用高度：648 - MENU_Y */
	static final MENU_ROW_H:Float = SAFE_BOTTOM - MENU_Y;
	/** 按钮之间的间距 */
	static final MENU_BTN_GAP:Float = 18;
	/** 按钮底板：文字四周的内边距（决定底板比文字大多少） */
	static final MENU_BTN_PAD_X:Float = 22;
	static final MENU_BTN_PAD_Y:Float = 9;
	static final MENU_BTN_RADIUS:Float = 14;

	// ---- 左：曲目信息 + 判定统计（同一张卡：信息当头部，判定在分隔线之下） ----
	// 改版前这是**两张**独立卡片（INFO_H 172 / JUDGE_H 168），加上 Phigros 面板
	// 和菜单卡片，左列一路排 4 块，屏幕上是 6 块面板/卡片 —— 实机反馈「拥挤」。
	// 现合并为 1 张：面板数 6 → 4，并腾出一整块垂直空间。
	static final CARD_A_TITLE_PAD:Float = 26;   // 内部首行相对卡片顶部的上边距
	static final INFO_LINE_GAP:Float = 30;      // 曲目/难度/评级/模式 四行行距
	static final INFO_LINE_GAP_MIN:Float = 24;  // 溢出兜底时的行距下限
	static final INFO_ROWS:Int = 4;
	static final SEP_PAD_TOP:Float = 12;        // 分隔线上方留白
	static final SEP_PAD_BOTTOM:Float = 10;     // 分隔线下方留白
	static final JUDGE_ROW_GAP:Float = 32;      // 判定统计行距（两列布局）
	static final JUDGE_ROW_GAP_MIN:Float = 24;  // 溢出兜底时的行距下限
	static final JUDGE_COL0:Float = PANEL_X + TEXT_PAD;   // 60
	static final JUDGE_COL1:Float = PANEL_X + 320;        // 360
	static final JUDGE_VAL_GAP:Float = 175;     // 标签后数值 x 偏移（MARVELOUS 较长，需留宽）
	static final CARD_BOTTOM_PAD:Float = 18;

	// ---- 左：Phigros 式评级卡（仅「Phigros 式评分」开启时创建） ----
	static final PGR_TITLE_PAD:Float = 18;
	static final PGR_ROW_GAP:Float = 28;
	static final PGR_BIG_FONT:Int = 64;
	static final PGR_BIG_BOX:Float = 88;   // 64px future.ttf 的文本框高（用于居中与定高）
	static final PGR_BIG_X:Float = PANEL_X + 26;   // 大评级符号
	static final PGR_ROW_X:Float = PANEL_X + 150;  // 准确率 / 连击率 / 判定计数 三行
	/** 说明行右对齐到卡片内边距，宽度固定（标题在左、说明在右同一行） */
	static final PGR_NOTE_W:Float = 280;

	// ---- 右：本局数据 ----
	static final STATS_X:Float = RIGHT_X;
	static final STATS_W:Float = RIGHT_W;
	static final STATS_Y:Float = PANEL_TOP;
	static final STATS_TITLE_Y:Float = STATS_Y + 24;
	static final STATS_ROW_START:Float = STATS_Y + 80;
	static final STATS_ROW_GAP:Float = 32;
	static final STATS_ROWS:Int = 7;
	static final STATS_LABEL_X:Float = STATS_X + TEXT_PAD;
	static final STATS_VAL_X:Float = STATS_X + 300;

	// ---- 右：命中判定散点图（高度 = 安全线剩余空间，不再写死） ----
	static final GRAPH_X:Float = RIGHT_X;
	static final GRAPH_W:Float = RIGHT_W;
	static final GRAPH_HEAD_H:Float = 30;   // 图内标题占位
	static final GRAPH_FOOT_H:Float = 22;   // 图内 Mean/判定窗口 底行占位
	#if mobile
	static final GRAPH_MAX_H:Float = 150;   // 收窄避开右下手柄键
	#else
	static final GRAPH_MAX_H:Float = 999;   // 桌面：由剩余空间决定
	#end

	// ---- 错峰飞入动画 ----
	static final FLY_DUR:Float = 0.3;
	static final FLY_DIST:Float = 26;
	static final FLY_D:Float = 0.045;       // 逐项错峰步长

	public var resultAction:String = 'continue';

	var grpMenuShit:FlxTypedGroup<MenuText>;
	// 菜单项**内部 ID**（多语言）：显示走 actionLabel()，判定走 ID 比较。
	// 旧实现 menuItems 存中文文本、并用 `menuItems[curSelected] == '重试'` 判定动作 ——
	// 一本地化就再也匹配不上：英文界面点 Retry 会误判成 continue（静默走错分支）。
	var menuItems:Array<String> = [ACTION_RETRY, ACTION_CONTINUE];
	var curSelected:Int = 0;

	/** 按钮行 Y（横排：按钮与文字共用） */
	var menuRowY:Float = MENU_Y;
	/** 每个菜单项一个圆角底板，索引与 menuItems 对齐 */
	var menuButtons:Array<FlxSprite> = [];
	/** 每个按钮顶部的光泽层（斜向白渐变），悬浮时淡入 */
	var btnGloss:Array<FlxSprite> = [];
	/** 当前鼠标悬浮在哪个按钮上（-1 = 无）。仅影响光泽，不改选中态。 */
	var hoverID:Int = -1;

	/** 元素飞入：位移 + 淡入。dir 用 FLY_* 常量；delay 用来错峰。 */
	function flyIn(obj:FlxSprite, dir:Int, delay:Float, ?dur:Float):Void
	{
		if (obj == null) return;
		var tx:Float = obj.x;
		var ty:Float = obj.y;
		var ox:Float = (dir == FLY_LEFT) ? -FLY_DIST : FLY_DIST;
		var oy:Float = (dir == FLY_UP) ? FLY_DIST : -FLY_DIST;
		obj.alpha = 0;
		obj.x = tx + ox;
		obj.y = ty + oy;
		FlxTween.tween(obj, {alpha: 1, x: tx, y: ty}, (dur != null) ? dur : FLY_DUR, {ease: FlxEase.quadOut, startDelay: delay});
	}

	static inline final FLY_LEFT:Int = 0;
	static inline final FLY_RIGHT:Int = 1;
	static inline final FLY_UP:Int = 2;
	static inline final FLY_DOWN:Int = 3;

	/** 无位移纯淡入（用于图这类大体量元素：位移看起来像整块在抖） */
	function fadeIn(obj:FlxSprite, delay:Float, ?dur:Float):Void
	{
		if (obj == null) return;
		obj.alpha = 0;
		FlxTween.tween(obj, {alpha: 1}, (dur != null) ? dur : FLY_DUR, {ease: FlxEase.quadOut, startDelay: delay});
	}

	var mouseActive:Bool = true;  // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;

	#if mobile
	var pad:objects.MobileControls; // virtualpad：A 确认 + 上下箭头（自带按下动画）
	#end

	public function new(?hasReplay:Bool = false)
	{
		super();

		if (hasReplay) menuItems = [ACTION_RETRY, ACTION_REPLAY, ACTION_CONTINUE];

		// 固定渲染在专用相机上：zoom=1、scroll=(0,0)，不受游戏相机缩放影响
		var resultsCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [resultsCam];
		cameras[0].zoom = 1;
		cameras[0].scroll.set(0, 0);

		var st:PlayState = PlayState.instance;

			var invalidResult:Bool = (st.usedAutoplay || st.usedGodMode);

		// ---- 背景 ----
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		FlxTween.tween(bg, {alpha: 0.6}, 0.25, {ease: FlxEase.quadOut});

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, Lang.tOr('results.title', '本局结算'), 54);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 54, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		titleText.alpha = 0;
		add(titleText);
		FlxTween.tween(titleText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.05});

		// ================= 左列 =================
		// 改版前左列是 4 块独立卡片一路排下来（曲目信息 / 判定统计 / Phigros / 菜单），
		// 全屏 6 块面板 —— 实机反馈「拥挤」。现合并成 2 张卡 + 1 行横排按钮。

		// 判定条目先算出来：行数决定卡片高度，而高度要在建卡片**之前**就知道。
		var judgeItems:Array<{name:String, count:Int, color:Int}> = [];
		for (rating in st.ratingsData)
		{
			var c:Int = switch (rating.name)
			{
				case 'marvelous': 0xFFFFD700; // 金黄色
				case 'sick': 0xFF00FFFF;
				case 'good': 0xFF00FF00;
				case 'bad': 0xFFFF0000;
				case 'shit': 0xFF8B0000;
				default: 0xFFA9A9B8;
			}
			judgeItems.push({name: rating.name.toUpperCase(), count: rating.hits, color: c});
		}
		judgeItems.push({name: 'MISS', count: haxe.Int64.toInt(st.songMisses), color: 0xFFFF6B6B});
		if (ClientPrefs.data.botMode == 'destroy' && st.usedAutoplay)
			judgeItems.push({name: 'DESTROYED', count: st.destroyedNotes, color: 0xFFFFB347});
		var judgeRows:Int = Std.int(Math.ceil(judgeItems.length / 2));

		var pgr:PhigrosResult = ClientPrefs.data.phigrosRating ? PhigrosRating.fromPlayState(st) : null;

		// ---- 卡 B 内部各元素的纵向落点（相对卡片顶部，先算好给下面用） ----
		// 全部由内容推导而不是手填常数：说明行挪到标题行之后，底部只剩三行读数与
		// 大评级符号，卡片高度取两者下沿的最大值。
		var pgrTitleH:Float = 33;                // 26px 标题的文本框高
		var pgrRowH:Float = 25;                  // 20px 读数行的文本框高
		var pgrRowsTop:Float = PGR_TITLE_PAD + 32;
		var pgrRowsBottom:Float = pgrRowsTop + 2 * PGR_ROW_GAP + pgrRowH;
		var pgrContentTop:Float = PGR_TITLE_PAD + pgrTitleH;
		// 大评级符号在「标题下沿 ~ 读数末行下沿」之间**垂直居中**。
		// 原先终态在 +32（创建 +46 再上移 14），紧贴标题而下方留白偏多
		// （用户实机反馈「评级字符有点靠上，往下点」）。
		var pgrBigY:Float = (pgrContentTop + pgrRowsBottom) * 0.5 - PGR_BIG_BOX * 0.5;
		var cardBH:Float = (pgr != null) ? Math.max(pgrRowsBottom, pgrBigY + PGR_BIG_BOX) + CARD_BOTTOM_PAD : 0;

		// ---- 两卡的高度与纵向位置（先算，再建） ----
		// 左列可用带 = 面板顶部 .. 提示文字上方。卡片总高不足时**垂直居中**：
		// Phigros 关闭时只剩一张卡（~280px），顶对齐会在按钮行上方留 ~90px 空洞，
		// 居中后上下均匀，看起来是有意留白而不是漏了东西。
		var bandTop:Float = PANEL_TOP;
		var bandBottom:Float = HINT_Y - CARD_GAP;
		var bandAvail:Float = bandBottom - bandTop;

		var infoGap:Float = INFO_LINE_GAP;
		var judgeGap:Float = JUDGE_ROW_GAP;
		function headHeight(ig:Float):Float { return CARD_A_TITLE_PAD + INFO_ROWS * ig + SEP_PAD_TOP; }
		function stackHeight(ig:Float, jg:Float):Float
		{
			var a:Float = headHeight(ig) + SEP_PAD_BOTTOM + judgeRows * jg + CARD_BOTTOM_PAD;
			return a + ((pgr != null) ? CARD_GAP + cardBH : 0);
		}

		// 溢出兜底：judgeItems 来自 st.ratingsData（**public 可变字段**，脚本/模组能追加判定种类），
		// 行数一多固定行距就会把卡片顶到提示行上（判定 7 项 + Phigros 开时实测压掉 24px）。
		// 先压判定行距、再压信息行距，各有下限；压到下限仍不够就保留溢出，绝不裁掉内容。
		var stackH:Float = stackHeight(infoGap, judgeGap);
		if (stackH > bandAvail)
		{
			var need:Float = stackH - bandAvail;
			var jSegs:Float = Math.max(judgeRows - 1, 1);
			var jSave:Float = jSegs * (judgeGap - JUDGE_ROW_GAP_MIN);
			if (need <= jSave)
				judgeGap -= need / jSegs;
			else
			{
				need -= jSave;
				judgeGap = JUDGE_ROW_GAP_MIN;
				var iSegs:Float = Math.max(INFO_ROWS - 1, 1);
				infoGap -= Math.min(need, iSegs * (infoGap - INFO_LINE_GAP_MIN)) / iSegs;
			}
			stackH = stackHeight(infoGap, judgeGap);
		}

		var headH:Float = headHeight(infoGap);
		var cardAH:Float = headH + SEP_PAD_BOTTOM + judgeRows * judgeGap + CARD_BOTTOM_PAD;
		var stackY:Float = bandTop + Math.max(0, (bandAvail - stackH) * 0.5);

		// ---- 卡 A：曲目信息（头部）+ 分隔线 + 判定统计 ----
		var cardA:FlxSprite = makePanel(PANEL_X, stackY, PANEL_W, Std.int(cardAH), 20);
		add(cardA);
		flyIn(cardA, FLY_LEFT, 0.08);

		var infoYStart:Float = stackY + CARD_A_TITLE_PAD;
		var infoTexts:Array<FlxText> = [];
		infoTexts.push(makeInfoText(Lang.tOr('results.song', '曲目：') + PlayState.SONG.song, infoYStart));
		infoTexts.push(makeInfoText(Lang.tOr('results.difficultyLabel', '难度：') + translateDifficulty(Difficulty.getString()), infoYStart + infoGap));
		infoTexts.push(makeInfoText(Lang.tOr('results.rankLabel', '评级：') + st.ratingName + fcText(st.ratingFC), infoYStart + infoGap * 2));
		var modeText:FlxText;
		if (invalidResult)
		{
			var why:Array<String> = [];
			if (st.usedAutoplay) why.push(Lang.tOr('results.botplay', '自动游玩'));
			if (st.usedGodMode) why.push(Lang.tOr('results.godMode', '上帝模式'));
			if (ClientPrefs.data.botMode == 'destroy' && st.usedAutoplay) why.push(Lang.tOr('results.botDestroy', '销毁模式'));
			modeText = makeInfoText(why.join(' + ') + Lang.tOr('results.invalidScore', '（成绩无效）'), infoYStart + infoGap * 3, 0xFFFF6B6B);
		}
		else
			modeText = makeInfoText(Lang.tOr('results.normalMode', '正常模式'), infoYStart + infoGap * 3);
		infoTexts.push(modeText);
		for (i in 0...infoTexts.length)
		{
			var txt:FlxText = infoTexts[i];
			flyIn(txt, FLY_LEFT, 0.14 + FLY_D * i);
		}

		// 分隔线：区分「本局是什么」与「判定明细」
		var sep:FlxSprite = new FlxSprite(PANEL_X + TEXT_PAD - 12, stackY + headH);
		sep.makeGraphic(Std.int(PANEL_W - TEXT_PAD * 2 + 24), 2, DesignTokens.panelOutline);
		sep.scrollFactor.set();
		add(sep);
		flyIn(sep, FLY_LEFT, 0.14 + FLY_D * infoTexts.length);

		var judgeStartY:Float = stackY + headH + SEP_PAD_BOTTOM;
		for (i in 0...judgeItems.length)
		{
			var item = judgeItems[i];
			var colX:Float = (i % 2 == 0) ? JUDGE_COL0 : JUDGE_COL1;
			var rowY:Float = judgeStartY + Std.int(i / 2) * judgeGap;
			var jDelay:Float = 0.30 + FLY_D * Std.int(i / 2);

			var label:FlxText = new FlxText(colX, rowY, 0, item.name, 24);
			label.scrollFactor.set();
			label.setFormat(Paths.font('future.ttf'), 24, item.color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			label.borderSize = 1.5;
			label.antialiasing = ClientPrefs.data.antialiasing;
			add(label);
			flyIn(label, FLY_LEFT, jDelay);

			var count:FlxText = new FlxText(colX + JUDGE_VAL_GAP, rowY, 0, Std.string(item.count), 24);
			count.scrollFactor.set();
			count.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			count.borderSize = 1.5;
			count.antialiasing = ClientPrefs.data.antialiasing;
			add(count);
			flyIn(count, FLY_LEFT, jDelay);
		}

		// ---- 卡 B：Phigros 式评级（仅「Phigros 式评分」开启时出现） ----
		// 分开成独立卡片而不是把原「评级：」那行换掉：原评级（ratingName，如 PF/SHDC）是
		// 引擎既有的**判定分布**评级，与 Phigros 的**分数**评级是两套口径，混在一起会误导。
		if (pgr != null)
		{
			var cardBY:Float = stackY + cardAH + CARD_GAP;
			var pgrPanel:FlxSprite = makePanel(PANEL_X, cardBY, PANEL_W, Std.int(cardBH), 20);
			add(pgrPanel);
			flyIn(pgrPanel, FLY_LEFT, 0.24);

			var pgrTitle:FlxText = new FlxText(PANEL_X + TEXT_PAD, cardBY + PGR_TITLE_PAD, 0,
				Lang.tOr('results.phigrosRating', 'Phigros 式评级'), 26);
			pgrTitle.scrollFactor.set();
			pgrTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			pgrTitle.borderSize = 2;
			pgrTitle.antialiasing = ClientPrefs.data.antialiasing;
			add(pgrTitle);
			flyIn(pgrTitle, FLY_LEFT, 0.30);

			// φ / V 补一行说明（Phigros 里 V 是「全连」特殊评级，语义与分数无关）
			var noteStr:String = switch (pgr.rank)
			{
				case 'φ': Lang.tOr('results.pgrAllPerfect', '全部判定完美');
				case 'V': pgr.special ? Lang.tOr('results.pgrFullCombo', '全连（无失误）') : Lang.tOr('results.pgrHighScore', '高分（未全连）');
				default: pgr.cleared ? Lang.tOr('results.pgrCleared', '已通关') : Lang.tOr('results.pgrNotCleared', '未通关');
			}
			// 说明行挪到**标题那一行的右侧**（右对齐到卡片内边距）。
			// 原先放在三行读数之下、紧贴卡片底边 —— 实机截图里「未通关」几乎掉出卡片
			// （+126 起、16px 字，而卡片只有 152 高，底部只剩 6px 留白）。
			// 挪上去后底部不再有东西，卡片也能顺势收矮，给大评级字符腾出下移空间。
			var pgrNote:FlxText = new FlxText(PANEL_X + PANEL_W - TEXT_PAD - PGR_NOTE_W, cardBY + PGR_TITLE_PAD + 4, PGR_NOTE_W,
				noteStr, 16);
			pgrNote.scrollFactor.set();
			pgrNote.setFormat(Paths.font('future.ttf'), 16, 0xFFA9A9B8, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			pgrNote.borderSize = 1.2;
			pgrNote.antialiasing = ClientPrefs.data.antialiasing;
			add(pgrNote);
			flyIn(pgrNote, FLY_LEFT, 0.34);

			// 大评级符号（φ / V / S / A / B / C / F），字号 64 居左。
			// ⚠ 字体必须用 future.ttf：**vcr.ttf 没有希腊字母字形**，φ 会渲染成空白
			// （用户实机报告：评级面板左边一片空白，只有右边的三行数字）。
			// 已逐字体核对字形表：future/bahnschrift/loadText 都有 φ(U+03C6)，
			// vcr.ttf 与 pixel.otf 都没有。future.ttf 还能顺带显示面板里的中文说明。
			//
			// 落点 pgrBigY 由「标题下沿 ~ 读数末行下沿」居中算出（见上方变量声明处），
			// 弹入时从下方 +10 处回弹到位。
			var rankBig:FlxText = new FlxText(PGR_BIG_X, cardBY + pgrBigY - 10, 0, pgr.rank, PGR_BIG_FONT);
			rankBig.scrollFactor.set();
			rankBig.setFormat(Paths.font('future.ttf'), PGR_BIG_FONT, pgr.color, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			rankBig.borderSize = 3;
			rankBig.antialiasing = ClientPrefs.data.antialiasing;
			rankBig.alpha = 0;
			add(rankBig);
			// backOut 弹入：评级符号是这一屏的视觉主角，值得一个回弹
			FlxTween.tween(rankBig, {alpha: 1, y: cardBY + pgrBigY}, 0.42, {ease: FlxEase.backOut, startDelay: 0.38});

			// 准确率 / 连击率 / 判定计数 三行。**不显示 Phigros 分数** —— 分数仍是引擎原口径
			// （已在「本局数据」面板里），这里只解释评级是怎么来的。
			var pgrRows:Array<{label:String, value:String, color:Int}> = [
				{label: Lang.tOr('results.pgrAccuracy', '准确率'), value: CoolUtil.floorDecimal(pgr.accuracy * 100, 2) + '%', color: FlxColor.WHITE},
				{
					label: Lang.tOr('results.pgrComboRate', '连击率'),
					value: (pgr.totalNotes > 0 ? CoolUtil.floorDecimal(pgr.maxCombo / (pgr.totalNotes : Float) * 100, 2) : 0) + '%',
					color: FlxColor.WHITE
				},
				{
					// 原始计数：P/G/B/M 与「最大连击 / 总音符」。既对应 Phigros 结算页的信息量，
					// 也让「为什么评级这么低」可直接核对，不必猜公式。
					label: Lang.tOr('results.pgrCounts', '判定 / 总数'),
					value: pgr.perfect + ' / ' + pgr.good + ' / ' + pgr.bad + ' / ' + pgr.miss
						+ '   |   ' + pgr.maxCombo + ' / ' + pgr.totalNotes,
					color: 0xFFA9A9B8
				}
			];
			for (i in 0...pgrRows.length)
			{
				var rowY:Float = cardBY + pgrRowsTop + i * PGR_ROW_GAP;

				var lbl:FlxText = new FlxText(PGR_ROW_X, rowY, 0, pgrRows[i].label, 20);
				lbl.scrollFactor.set();
				lbl.setFormat(Paths.font('future.ttf'), 20, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				lbl.borderSize = 1.4;
				lbl.antialiasing = ClientPrefs.data.antialiasing;
				add(lbl);
				flyIn(lbl, FLY_LEFT, 0.34 + FLY_D * i);

				var val:FlxText = new FlxText(PGR_ROW_X + 130, rowY, 0, pgrRows[i].value, 20);
				val.scrollFactor.set();
				val.setFormat(Paths.font('future.ttf'), 20, pgrRows[i].color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				val.borderSize = 1.4;
				val.antialiasing = ClientPrefs.data.antialiasing;
				add(val);
				flyIn(val, FLY_LEFT, 0.34 + FLY_D * i);
			}
		}

		// ================= 右列 =================

		// ---- 本局数据卡片 ----
		// 高度按行数算（写死 318 时，底部会随行数增减留空/挤边）：
		// 标题 24 + 行起点 80 + (行数-1)×行距 + 行高 + 底部留白
		var statsH:Float = STATS_ROW_START - STATS_Y + (STATS_ROWS - 1) * STATS_ROW_GAP + 32 + CARD_BOTTOM_PAD;
		var statPanel:FlxSprite = makePanel(STATS_X, STATS_Y, STATS_W, Std.int(statsH), 20);
		add(statPanel);
		flyIn(statPanel, FLY_RIGHT, 0.10);

		var statTitle:FlxText = new FlxText(STATS_LABEL_X, STATS_TITLE_Y, 0, Lang.tOr('results.stats', '本局数据'), 26);
		statTitle.scrollFactor.set();
		statTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statTitle.borderSize = 2;
		statTitle.antialiasing = ClientPrefs.data.antialiasing;
		add(statTitle);
		flyIn(statTitle, FLY_RIGHT, 0.16);

		var bestScore:haxe.Int64 = Highscore.getScore(PlayState.SONG.song, PlayState.storyDifficulty);
		// 比较必须用同一口径（Phigros 模式下存档里是 100 万制）
		if (!invalidResult && st.songScore >= bestScore && st.songScore > 0)
		{
			var newRecordText:FlxText = new FlxText(STATS_LABEL_X + 230, STATS_TITLE_Y + 4, 0, Lang.tOr('results.newRecord', '新纪录！'), 22);
			newRecordText.scrollFactor.set();
			newRecordText.setFormat(Paths.font('future.ttf'), 22, DesignTokens.secondary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			newRecordText.borderSize = 1.5;
			newRecordText.antialiasing = ClientPrefs.data.antialiasing;
			add(newRecordText);
			flyIn(newRecordText, FLY_RIGHT, 0.16);
		}

		var statDefs:Array<String> = [Lang.tOr('results.currentScore', '当前分数'), Lang.tOr('results.bestScore', '最佳分数'), Lang.tOr('results.statMaxCombo', '最高连击'), Lang.tOr('results.statMisses', '失误数'), Lang.tOr('results.statHitTotal', '命中 / 总音符'), Lang.tOr('results.statMaxNps', '峰值NPS'), Lang.tOr('results.statAccuracy', '准确度')];
		// 「准确度」行：跟随 `phigrosAccuracy` 开关（独立于「Phigros 式评分」）
		var accDisplay:Float = st.ratingPercent;
		if (ClientPrefs.data.phigrosAccuracy)
		{
			var accRes:PhigrosResult = PhigrosRating.fromPlayState(st);
			if (accRes != null) accDisplay = accRes.accuracy;
		}
		var statVals:Array<String> = [
			FlxStringUtil.formatMoney(I64.toFloat(st.songScore)),
			FlxStringUtil.formatMoney(I64.toFloat(bestScore)),
			Std.string(st.maxCombo),
			Std.string(st.songMisses),
			Std.string(st.songHits) + ' / ' + Std.string(st.totalNotes),
			Std.string(st.maxNpsDisplay),
			CoolUtil.floorDecimal(accDisplay * 100, 2) + '%'
		];
		for (i in 0...statDefs.length)
		{
			var rowY:Float = STATS_ROW_START + (i * STATS_ROW_GAP);

			var lbl:FlxText = new FlxText(STATS_LABEL_X, rowY, 0, statDefs[i] + '：', 24);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), 24, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			flyIn(lbl, FLY_RIGHT, 0.22 + FLY_D * i);

			var val:FlxText = new FlxText(STATS_VAL_X, rowY, 0, statVals[i], 24);
			val.scrollFactor.set();
			val.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			add(val);
			flyIn(val, FLY_RIGHT, 0.22 + FLY_D * i);
		}

		// ---- 命中判定散点图（高度 = 卡片下方到安全线的剩余空间） ----
		// 改版前写死 GRAPH_Y=428 / GRAPH_H=250 → 卡片底 678，越过安全线 648 共 30px。
		// 现在由「数据卡片实际高度」推导，永远收在安全线内。
		var graphY:Float = STATS_Y + statsH + CARD_GAP;
		var graphH:Float = Math.min(SAFE_BOTTOM - graphY, GRAPH_MAX_H);
		// 图内还要放标题(GRAPH_HEAD_H) + Mean/判定窗口底行(GRAPH_FOOT_H)，至少得留得下这些
		graphH = Math.max(graphH, GRAPH_HEAD_H + GRAPH_FOOT_H + 40);

		var graphPanel:FlxSprite = makePanel(GRAPH_X, graphY, GRAPH_W, Std.int(graphH), 20);
		add(graphPanel);
		// 大体量元素只淡入不位移：整块 26px 横移看着像画面在抖
		fadeIn(graphPanel, 0.42);

		var entries:Array<NoteHitEntry> = st.judgementHistory;
		var innerX:Float = GRAPH_X + 14;
		var innerW:Int = Std.int(GRAPH_W - 28);

		var graphHead:FlxText = new FlxText(innerX, graphY + 8, innerW, Lang.tOr('results.hitDistribution', '命中分布（横轴=时间 · 纵轴=偏移：+早到 / −晚到 · 点色=判定）'), 14);
		graphHead.scrollFactor.set();
		graphHead.setFormat(Paths.font('future.ttf'), 14, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		graphHead.borderSize = 1.2;
		graphHead.antialiasing = ClientPrefs.data.antialiasing;
		add(graphHead);
		fadeIn(graphHead, 0.44);

		if (entries != null && entries.length > 0)
		{
			var graph:FlxSprite = NoteHitGraph.build(innerW, Std.int(graphH - GRAPH_HEAD_H - GRAPH_FOOT_H - 8), entries, st.songLength);
			graph.x = innerX;
			graph.y = graphY + GRAPH_HEAD_H;
			graph.scrollFactor.set();
			add(graph);
			fadeIn(graph, 0.46);

			// Mean 均值 + 判定窗口说明（KE 同款底行）
			var sum:Float = 0;
			var cnt:Int = 0;
			for (e in entries)
				if (e.r != 'miss') { sum += e.d; cnt++; }
			var meanStr:String = (cnt > 0) ? (Lang.tOr('results.meanOffset', '平均偏移 ') + CoolUtil.floorDecimal(sum / cnt, 2) + ' ms') : Lang.tOr('results.meanOffsetNone', '平均偏移 -');
			var winStr:String = 'SICK ' + ClientPrefs.data.sickWindow + ' / GOOD ' + ClientPrefs.data.goodWindow
				+ ' / BAD ' + ClientPrefs.data.badWindow + ' / SHIT 166';
			var meanText:FlxText = new FlxText(innerX, graphY + graphH - GRAPH_FOOT_H, innerW, meanStr + '　' + winStr, 13);
			meanText.scrollFactor.set();
			meanText.setFormat(Paths.font('future.ttf'), 13, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			meanText.borderSize = 1.2;
			meanText.antialiasing = ClientPrefs.data.antialiasing;
			add(meanText);
			fadeIn(meanText, 0.50);
		}
		else
		{
			var noDataText:FlxText = new FlxText(innerX, graphY + 44, innerW, Lang.tOr('results.noJudgementData', '（本局无判定数据）'), 16);
			noDataText.scrollFactor.set();
			noDataText.setFormat(Paths.font('future.ttf'), 16, 0xFFCFCFDC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			noDataText.borderSize = 1.2;
			noDataText.antialiasing = ClientPrefs.data.antialiasing;
			add(noDataText);
			fadeIn(noDataText, 0.46);
		}

		// ---- 底部：操作提示 + 横排按钮行 ----
		var hintText:FlxText = new FlxText(PANEL_X + TEXT_PAD, HINT_Y, PANEL_W - TEXT_PAD, getHintText(), 18);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), 18, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);
		flyIn(hintText, FLY_UP, 0.46);

		buildMenu(PANEL_X, MENU_Y, PANEL_W);

		FlxG.mouse.visible = true;
		Lib.application.window.title = Lang.tOr('results.windowTitle', "FNF':Meteoric Engine - 结算");

		loadUIscripts('results');
	}

	/**
	 * 底部操作按钮行（**横排**，每个选项一个独立圆角按钮，不用卡片）。
	 *
	 * 改版演进：
	 * 1) 最初是一张 560px 宽的卡片竖排 2~3 项 → 改版后这块地已是底部安全区（648），
	 *    卡片底部直接溢出 720 画布 34px、操作提示整行落在屏幕外；
	 * 2) 改成横排文字 + 一条移动高亮条 → 高亮条是「一条」，三个选项看起来仍像列表项，
	 *    不像按钮（用户实机反馈：「这三个选项直接做成三个按钮吧」）；
	 * 3) 现在每个选项自带圆角底板，选中项底板提亮并染主题色。
	 */
	function buildMenu(x:Float, y:Float, w:Float):Void
	{
		menuRowY = y;

		#if mobile
		// virtualpad：A 在右下，[上][下] 依次在 A 左侧（同一行，不遮挡面板）；按下有动画
		pad = new objects.MobileControls(false, cameras[0], -1, true);
		pad.addPadArrow('ui_left', 'left', FlxG.width - objects.MobileControls.BTN_W * 3 - 20 - 24, FlxG.height - objects.MobileControls.BTN_H - 20);
		pad.addPadArrow('ui_right', 'right', FlxG.width - objects.MobileControls.BTN_W * 2 - 20 - 12, FlxG.height - objects.MobileControls.BTN_H - 20);
		add(pad);
		#end

		// 1) 先把文字造出来（**不加入场景**）—— 要靠 text.width 才知道每个按钮多宽
		var items:Array<MenuText> = [];
		var cursorX:Float = x + TEXT_PAD;
		for (i in 0...menuItems.length)
		{
			var it:MenuText = new MenuText(cursorX, y + MENU_BTN_PAD_Y, actionLabel(menuItems[i]), true, 34);
			it.isMenuItem = false;
			it.ID = i;
			items.push(it);
			cursorX += it.width + MENU_BTN_PAD_X * 2 + MENU_BTN_GAP;
		}

		// 2) 底板 + 光泽层入场景（add 顺序 = 绘制顺序，底板在文字之下）
		menuButtons = [];
		btnGloss = [];
		for (it in items)
		{
			var bw:Float = it.width + MENU_BTN_PAD_X * 2;
			var bh:Float = it.height + MENU_BTN_PAD_Y * 2;

			var btn:FlxSprite = makeBtn(it.x - MENU_BTN_PAD_X, it.y - MENU_BTN_PAD_Y, bw, bh);
			add(btn);
			menuButtons.push(btn);

			// 光泽层：上缘最亮、往下渐隐（3 色 + rotation 90 → ratio 0/127/255，
			// 即 y=0 最亮、y=h/2 起全透明）。未悬浮时 alpha 0，完全不可见。
			var gloss:FlxSprite = FlxGradient.createGradientFlxSprite(Std.int(bw) - 4, Std.int(bh) - 4,
				[0xB4FFFFFF, 0x00FFFFFF, 0x00FFFFFF], 1, 90);
			gloss.x = it.x - MENU_BTN_PAD_X + 2;
			gloss.y = it.y - MENU_BTN_PAD_Y + 2;
			gloss.scrollFactor.set();
			gloss.alpha = 0;
			add(gloss);
			btnGloss.push(gloss);

			// 底板飞入时**直接补间到状态 alpha**，不经过 1 ——
			// 否则未选中按钮会先全亮再被压暗，闪一下。
			// 颜色要在这里就设好：makeBtn 出来默认是白染，若等动画结束的
			// changeSelection(0, true) 再染，选中按钮在飞入期间是白的（而且
			// 玩家若在 0.86s 内按键会直接跳色）。
			var isSel:Bool = (it.ID == 0);
			btn.color = (isSel) ? DesignTokens.primary : FlxColor.WHITE;
			btn.alpha = 0;
			btn.y += FLY_DIST;
			FlxTween.tween(btn, {alpha: (isSel ? 1 : 0.5), y: y + MENU_BTN_PAD_Y - MENU_BTN_PAD_Y},
				FLY_DUR, {ease: FlxEase.quadOut, startDelay: 0.56 + FLY_D * it.ID});

			// 光泽跟着底板一起飞入（保持相对位置），落定后停在 alpha 0
			gloss.y += FLY_DIST;
			FlxTween.tween(gloss, {y: it.y - MENU_BTN_PAD_Y + 2}, FLY_DUR,
				{ease: FlxEase.quadOut, startDelay: 0.56 + FLY_D * it.ID});
		}

		// 3) 文字后入场景，盖在底板之上
		grpMenuShit = new FlxTypedGroup<MenuText>();
		add(grpMenuShit);
		curSelected = 0;
		for (it in items)
		{
			grpMenuShit.add(it);
			flyIn(it, FLY_UP, 0.56 + FLY_D * it.ID);
		}

		// 4) 动画落定后纠正一次文字 alpha（flyIn 把它压到 0，未选中项常态应是 0.6）
		FlxTween.tween(grpMenuShit, {alpha: 1}, 0.01, {
			ease: FlxEase.quadOut,
			startDelay: 0.56 + FLY_D * menuItems.length + FLY_DUR,
			onComplete: function(_) changeSelection(0, true)
		});
	}

	/**
	 * 按钮底板。画成**纯白**填充 + 白描边，状态全靠 `color`（乘法染色）与 `alpha` 表达 ——
	 * 这样切换选中只需改两个属性、不必重绘图形（重绘会与原像素做 alpha 混合留下残影）。
	 */
	function makeBtn(x:Float, y:Float, w:Float, h:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, MENU_BTN_RADIUS, MENU_BTN_RADIUS, 0x40FFFFFF,
			{color: 0x99FFFFFF, thickness: 1.8});
		spr.scrollFactor.set();
		return spr;
	}

	/**
	 * 把按钮与文字刷成当前选中态。
	 * @param animate true 时补间过渡；false 时立即生效
	 */
	function applySelectionStyle(animate:Bool):Void
	{
		if (grpMenuShit == null || menuButtons == null) return;
		var d:Float = (animate) ? 0.12 : 0;
		for (item in grpMenuShit.members)
		{
			var selected:Bool = (item.ID == curSelected);
			var btn:FlxSprite = menuButtons[item.ID];
			if (btn != null)
			{
				var toC:FlxColor = (selected) ? DesignTokens.primary : FlxColor.WHITE;
				var toA:Float = (selected) ? 1 : 0.5;

				// ⚠⚠ 颜色**绝对不能**写进 FlxTween.tween 的属性表。
				//
				//   FlxTween.tween(obj, {…}) 走的是 VarTween，它把每个属性当**裸数字**
				//   做线性插值（VarTween.hx）：
				//       info.startValue = value;                    // FlxColor → Int
				//       info.range      = info.range - value;
				//       Reflect.setProperty(obj, field, start + range * scale);
				//   FlxColor 是 0xAARRGGBB 的**打包整数**，于是青 0xFF9CE8FF → 白 0xFFFFFFFF
				//   之间会扫过 0x640331、0x8C2349 这类任意字节组合 —— 中途整片泛红。
				//   （用户实机录屏：左右切按钮时「继续」闪成血红色、「回放本局」变橄榄绿。
				//     量到的峰值像素 (140,35,73) / (100,3,49) 正是扫过的中间值。）
				//
				//   也不能用 FlxTween.color()：它内部 `sprite.alpha = color.alphaFloat`
				//   （ColorTween.hx:59），会和我们要单独控制的 alpha 打架。
				//   所以这里自己用 FlxColor.interpolate 按 r/g/b 分量插值。
				var fromC:FlxColor = btn.color;
				var fromA:Float = btn.alpha;
				FlxTween.cancelTweensOf(btn);

				if (animate)
				{
					FlxTween.tween(btn, {alpha: toA}, d, {
						ease: FlxEase.quadOut,
						onUpdate: function(t) {
							var s:Float = t.scale;   // 已含 ease
							btn.color = FlxColor.interpolate(fromC, toC, s);
						}
					});
				}
				else
				{
					btn.alpha = toA;
					btn.color = toC;
				}
			}

			// 文字：飞入动画期间不改 alpha —— flyIn 刚把它压到 0，
			// 这里若无条件写 0.6/1 会当场盖掉补间，按钮变成闪现（暂停界面踩过同一个坑）。
			if (item.alpha < 1) continue;
			item.alpha = 0.6;
			item.color = 0xFFCFCFDC;
			if (selected)
			{
				item.alpha = 1;
				item.color = FlxColor.WHITE;
			}
		}
	}

	/**
	 * 悬浮光泽。只改光泽层的 alpha，**不动选中态** ——
	 * 键盘/手柄选中与鼠标悬浮是两件事；一旦悬浮就改选中，
	 * 鼠标划过会把高亮带着跑，之前 `mouseActive` 那套「用键盘时冻结鼠标」的逻辑也就失效了。
	 */
	function applyHoverGloss():Void
	{
		if (btnGloss == null) return;
		for (i in 0...btnGloss.length)
		{
			var g:FlxSprite = btnGloss[i];
			if (g == null) continue;
			FlxTween.cancelTweensOf(g);
			// y 正在被飞入补间占用时不碰 alpha，只在动画结束后才允许淡入
			FlxTween.tween(g, {alpha: (i == hoverID ? 1 : 0)}, 0.14, {ease: FlxEase.quadOut});
		}
	}

	function makeInfoText(content:String, yPos:Float, ?textColor:FlxColor = FlxColor.WHITE, ?size:Int = 26):FlxText
	{
		var txt:FlxText = new FlxText(PANEL_X + TEXT_PAD, yPos, 0, content, size);
		txt.scrollFactor.set();
		txt.setFormat(Paths.font('future.ttf'), size, textColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		txt.borderSize = 2;
		txt.antialiasing = ClientPrefs.data.antialiasing;
		txt.alpha = 0;
		txt.updateHitbox();
		add(txt);
		return txt;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是**编译期常量**，不能写 DesignTokens.panelFill（运行时求值会被 Haxe 拒绝），
		// 故默认传 null、在此解析 —— 同时保证取到的是「当前主题」的值，而不是类加载时的快照。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if(border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override function update(elapsed:Float)
	{
		if (cameras != null && cameras[0] != null)
		{
			cameras[0].zoom = 1;
			cameras[0].scroll.set(0, 0);
		}
		super.update(elapsed);

		// 横排按钮行 → 左右键切换（原先用上下，与「横排」不符：
		// 上下键会把视线带着横着扫一整屏，看着别扭）
		var leftP = controls.UI_LEFT_P;
		var rightP = controls.UI_RIGHT_P;
		var accepted = controls.ACCEPT;
		#if mobile
		// virtualpad 按键（走 stage tap 队列，安卓 FlxG.touches 为空也能触发）
		if (pad != null)
		{
			if (pad.justPressed('accept')) accepted = true;
			if (pad.justPressed('ui_left')) leftP = true;
			if (pad.justPressed('ui_right')) rightP = true;
		}
		#end

		if (leftP)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.x;
			mouseLockY = FlxG.mouse.y;
			changeSelection(-1);
		}
		if (rightP)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.x;
			mouseLockY = FlxG.mouse.y;
			changeSelection(1);
		}

		if (!controls.controllerMode)
		{
			var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());
			var hoveredID:Int = -1;

			// 悬浮判定用**按钮底板**的范围而不是文字范围：
			// 底板比文字大 MENU_BTN_PAD_X/Y（上下各 9px、左右各 22px），
			// 按文字判会出现「看着在按钮上、光泽却不亮」。
			for (item in grpMenuShit.members)
			{
				var b:FlxSprite = (menuButtons != null && item.ID < menuButtons.length) ? menuButtons[item.ID] : null;
				if (b == null) continue;
				if (mousePos.x >= b.x && mousePos.x <= b.x + b.width
					&& mousePos.y >= b.y && mousePos.y <= b.y + b.height)
					hoveredID = item.ID;
			}
			if (hoveredID != hoverID)
			{
				hoverID = hoveredID;
				applyHoverGloss();
			}

			if (!mouseActive)
			{
				var dx:Float = FlxG.mouse.x - mouseLockX;
				var dy:Float = FlxG.mouse.y - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			#if !mobile
			var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
			if (wheelStep != 0)
			{
				mouseActive = true;
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(wheelStep);
			}
			#end

			#if mobile
			// ---- 触屏：拖动滚动（选择只靠拖动/左右箭头，A 确认；点按行不改变选中）----
			var steps:Int = objects.MobileControls.consumeDragSteps();
			if (steps != 0)
			{
				mouseActive = true;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				changeSelection(steps);
			}
			#else
			if (hoveredID >= 0 && FlxG.mouse.justPressed)
			{
				mouseActive = true;
				if (hoveredID != curSelected) changeSelection(hoveredID - curSelected);
				accepted = true;
			}
			#end
			mousePos.put();
		}

		if (controls.BACK)
		{
			resultAction = 'continue';
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		if (accepted)
		{
			FlxG.sound.play(Paths.sound('confirmMenu'));
			// 判定用内部 ID（与语言无关）；不能拿显示文本比较
			resultAction = (menuItems[curSelected] == ACTION_RETRY) ? 'retry'
				: ((menuItems[curSelected] == ACTION_REPLAY) ? 'replay' : 'continue');
			close();
		}
	}

	/** 菜单项内部 ID（稳定、与语言无关） */
	static final ACTION_RETRY:String = 'retry';
	static final ACTION_REPLAY:String = 'replay';
	static final ACTION_CONTINUE:String = 'continue';

	/** 菜单项 ID → 显示文本（多语言唯一翻译点） */
	function actionLabel(id:String):String
	{
		switch (id)
		{
			case ACTION_RETRY: return Lang.tOr('results.retry', '重试');
			case ACTION_REPLAY: return Lang.tOr('results.playReplay', '回放本局');
			case ACTION_CONTINUE: return Lang.tOr('results.continue', '继续');
		}
		return id;
	}

	function getHintText():String
	{
		if (PlayState.isStoryMode)
		{
			if (PlayState.storyPlaylist.length > 1) return Lang.tOr('results.hint.nextSong', '回车确认 · ESC 继续（播放下一首）');
			return Lang.tOr('results.hint.weekComplete', '回车确认 · ESC 继续（完成周目，返回剧情选关）');
		}
		return Lang.tOr('results.hint.backToFreeplay', '回车确认 · ESC 继续（返回自由选歌）');
	}

	function fcText(fc:String):String
	{
		switch (fc)
		{
			case 'FC': return Lang.tOr('results.rank.fc', '（全连）');
			case 'SDCB': return Lang.tOr('results.rank.sdcb', '（单断）');
			case 'Clear': return Lang.tOr('results.rank.clear', '（通过）');
		}
		return (fc == null || fc == '') ? '' : fc;
	}

	function translateDifficulty(d:String):String
	{
		switch (d)
		{
			case 'Easy': return Lang.t('difficulty.easy');
			case 'Normal': return Lang.t('difficulty.normal');
			case 'Hard': return Lang.t('difficulty.hard');
		}
		return d;
	}

	/**
	 * 切换选中项。
	 * @param change 选中项位移（会被环绕）
	 * @param silent true 时不播滚动音 —— 初始化与动画收尾调用，避免刚进界面就「咔」一声
	 */
	function changeSelection(change:Int = 0, silent:Bool = false):Void
	{
		curSelected += change;

		if (!silent) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		if (curSelected < 0)
			curSelected = menuItems.length - 1;
		if (curSelected >= menuItems.length)
			curSelected = 0;

		applySelectionStyle(!silent);

		callUIScripts('onChangeSelection', [curSelected, menuItems[curSelected]]);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
