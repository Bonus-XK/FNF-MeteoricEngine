package substates;
import backend.WheelScroll;

import backend.Highscore;

import flixel.math.FlxPoint;
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

	// ===== 安全布局常量（1280×720 基准；底部安全线 648 = 720 - 72） =====
	static final TITLE_Y:Float = 22;
	static final PANEL_TOP:Float = 96;
	static final PANEL_X:Float = 40;
	static final PANEL_W:Float = 560;
	static final RIGHT_X:Float = 620;
	static final RIGHT_W:Float = 620;
	static final TEXT_PAD:Float = 20;

	// 左：曲目信息
	static final INFO_Y:Float = PANEL_TOP;
	static final INFO_H:Float = 172;
	static final INFO_Y_START:Float = INFO_Y + 34;
	static final INFO_LINE_GAP:Float = 34;

	// 左：判定统计
	static final JUDGE_Y:Float = INFO_Y + INFO_H + 14;
	static final JUDGE_H:Float = 168;
	static final JUDGE_TITLE_Y:Float = JUDGE_Y + 20;
	static final JUDGE_ROW_START:Float = JUDGE_Y + 62;
	static final JUDGE_ROW_GAP:Float = 32;
	static final JUDGE_COL0:Float = PANEL_X + TEXT_PAD;   // 60
	static final JUDGE_COL1:Float = PANEL_X + 320;        // 360
	static final JUDGE_VAL_GAP:Float = 175;               // 标签后数值 x 偏移（MARVELOUS 较长，需留宽）

	// 左：操作菜单
	static final MENU_Y:Float = JUDGE_Y + JUDGE_H + 14;
	static final MENU_LINE_GAP:Float = 34;

	// 右：本局数据
	static final STATS_X:Float = RIGHT_X;
	static final STATS_W:Float = RIGHT_W;
	static final STATS_Y:Float = PANEL_TOP;
	static final STATS_H:Float = 288;
	static final STATS_TITLE_Y:Float = STATS_Y + 24;
	static final STATS_ROW_START:Float = STATS_Y + 80;
	static final STATS_ROW_GAP:Float = 32;
	static final STATS_LABEL_X:Float = STATS_X + TEXT_PAD;
	static final STATS_VAL_X:Float = STATS_X + 300;

	// 右：命中判定散点图
	static final GRAPH_X:Float = RIGHT_X;
	static final GRAPH_W:Float = RIGHT_W;
	static final GRAPH_Y:Float = STATS_Y + STATS_H + 14;
	#if mobile
	static final GRAPH_H:Float = 150; // 收窄避开右下手柄键
	#else
	static final GRAPH_H:Float = 250;
	#end

	public var resultAction:String = 'continue';

	var grpMenuShit:FlxTypedGroup<MenuText>;
	var menuItems:Array<String> = ['重试', '继续'];
	var curSelected:Int = 0;

	var menuSelector:FlxSprite;
	var menuSelectorTween:FlxTween;
	var menuPanelY:Float = MENU_Y; // 实际菜单面板 Y（联机精简版与单机布局共用选中条定位）

	// 联机双栏结算：对方成绩栏显示对象（createSimplified 创建，update 每帧刷新）
	var onlineSimplified:Bool = false;
	var oppHeaderText:FlxText = null;
	var oppScoreText:FlxText = null;
	var oppComboText:FlxText = null;
	var oppAccText:FlxText = null;
	var oppJudgeText:FlxText = null;

	var mouseActive:Bool = true;  // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;

	#if mobile
	var pad:objects.MobileControls; // virtualpad：A 确认 + 上下箭头（自带按下动画）
	#end

	public function new(?hasReplay:Bool = false)
	{
		super();

		if (hasReplay) menuItems = ['重试', '回放本局', '继续'];

		// 固定渲染在专用相机上：zoom=1、scroll=(0,0)，不受游戏相机缩放影响
		var resultsCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [resultsCam];
		cameras[0].zoom = 1;
		cameras[0].scroll.set(0, 0);

		var st:PlayState = PlayState.instance;

		// 联机模式：渲染普通结算的精简版（本局数据 + 判定统计 + 继续），关闭后回联机大厅
		if (PlayState.isOnlineMode)
		{
			createSimplified(st);
			return;
		}

		var invalidResult:Bool = (st.usedAutoplay || st.usedGodMode);

		// ---- 背景 ----
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		FlxTween.tween(bg, {alpha: 0.6}, 0.25, {ease: FlxEase.quadOut});

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, '本局结算 Song Results', 54);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 54, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		titleText.alpha = 0;
		add(titleText);
		FlxTween.tween(titleText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.05});

		// ================= 左列 =================

		// ---- 曲目信息面板 ----
		var infoPanel:FlxSprite = makePanel(PANEL_X, INFO_Y, PANEL_W, INFO_H, 20);
		infoPanel.alpha = 0;
		add(infoPanel);
		FlxTween.tween(infoPanel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var infoTexts:Array<FlxText> = [];
		infoTexts.push(makeInfoText('曲目：' + PlayState.SONG.song, INFO_Y_START));
		infoTexts.push(makeInfoText('难度：' + translateDifficulty(Difficulty.getString()), INFO_Y_START + INFO_LINE_GAP));
		infoTexts.push(makeInfoText('评级：' + st.ratingName + fcText(st.ratingFC), INFO_Y_START + INFO_LINE_GAP * 2));
		var modeText:FlxText;
		if (invalidResult)
		{
			var why:Array<String> = [];
			if (st.usedAutoplay) why.push('自动游玩');
			if (st.usedGodMode) why.push('上帝模式');
			modeText = makeInfoText(why.join(' + ') + '（成绩无效）', INFO_Y_START + INFO_LINE_GAP * 3, 0xFFFF6B6B);
		}
		else
			modeText = makeInfoText('正常模式', INFO_Y_START + INFO_LINE_GAP * 3);
		infoTexts.push(modeText);
		for (i in 0...infoTexts.length)
		{
			var txt:FlxText = infoTexts[i];
			FlxTween.tween(txt, {alpha: 1, y: txt.y + 8}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});
		}

		// ---- 判定统计面板（Judgements，KE 同款两列） ----
		var judgePanel:FlxSprite = makePanel(PANEL_X, JUDGE_Y, PANEL_W, JUDGE_H, 20);
		judgePanel.alpha = 0;
		add(judgePanel);
		FlxTween.tween(judgePanel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var judgeTitle:FlxText = new FlxText(PANEL_X + TEXT_PAD, JUDGE_TITLE_Y, 0, '判定统计 Judgements', 26);
		judgeTitle.scrollFactor.set();
		judgeTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		judgeTitle.borderSize = 2;
		judgeTitle.antialiasing = ClientPrefs.data.antialiasing;
		judgeTitle.alpha = 0;
		add(judgeTitle);
		FlxTween.tween(judgeTitle, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

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
		judgeItems.push({name: 'MISS', count: st.songMisses, color: 0xFFFF6B6B});
		for (i in 0...judgeItems.length)
		{
			var item = judgeItems[i];
			var colX:Float = (i % 2 == 0) ? JUDGE_COL0 : JUDGE_COL1;
			var rowY:Float = JUDGE_ROW_START + Std.int(i / 2) * JUDGE_ROW_GAP;

			var label:FlxText = new FlxText(colX, rowY, 0, item.name, 24);
			label.scrollFactor.set();
			label.setFormat(Paths.font('future.ttf'), 24, item.color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			label.borderSize = 1.5;
			label.antialiasing = ClientPrefs.data.antialiasing;
			label.alpha = 0;
			add(label);
			FlxTween.tween(label, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

			var count:FlxText = new FlxText(colX + JUDGE_VAL_GAP, rowY, 0, Std.string(item.count), 24);
			count.scrollFactor.set();
			count.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			count.borderSize = 1.5;
			count.antialiasing = ClientPrefs.data.antialiasing;
			count.alpha = 0;
			add(count);
			FlxTween.tween(count, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});
		}

		// ================= 右列 =================

		// ---- 本局数据面板 ----
		var statPanel:FlxSprite = makePanel(STATS_X, STATS_Y, STATS_W, STATS_H, 20);
		statPanel.alpha = 0;
		add(statPanel);
		FlxTween.tween(statPanel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var statTitle:FlxText = new FlxText(STATS_LABEL_X, STATS_TITLE_Y, 0, '本局数据 Stats', 26);
		statTitle.scrollFactor.set();
		statTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statTitle.borderSize = 2;
		statTitle.antialiasing = ClientPrefs.data.antialiasing;
		statTitle.alpha = 0;
		add(statTitle);
		FlxTween.tween(statTitle, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var bestScore:Int = Highscore.getScore(PlayState.SONG.song, PlayState.storyDifficulty);
		if (!invalidResult && st.songScore >= bestScore && st.songScore > 0)
		{
			var newRecordText:FlxText = new FlxText(STATS_LABEL_X + 230, STATS_TITLE_Y + 4, 0, '新纪录！ New Record', 22);
			newRecordText.scrollFactor.set();
			newRecordText.setFormat(Paths.font('future.ttf'), 22, DesignTokens.secondary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			newRecordText.borderSize = 1.5;
			newRecordText.antialiasing = ClientPrefs.data.antialiasing;
			newRecordText.alpha = 0;
			add(newRecordText);
			FlxTween.tween(newRecordText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});
		}

		var statDefs:Array<String> = ['当前分数', '最佳分数', '最高连击', '失误数', '命中 / 总音符', '准确度'];
		var statVals:Array<String> = [
			FlxStringUtil.formatMoney(st.songScore),
			FlxStringUtil.formatMoney(bestScore),
			Std.string(st.maxCombo),
			Std.string(st.songMisses),
			Std.string(st.songHits) + ' / ' + Std.string(st.totalNotes),
			CoolUtil.floorDecimal(st.ratingPercent * 100, 2) + '%'
		];
		for (i in 0...statDefs.length)
		{
			var rowY:Float = STATS_ROW_START + (i * STATS_ROW_GAP);

			var lbl:FlxText = new FlxText(STATS_LABEL_X, rowY, 0, statDefs[i] + '：', 24);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), 24, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			lbl.alpha = 0;
			add(lbl);
			FlxTween.tween(lbl, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

			var val:FlxText = new FlxText(STATS_VAL_X, rowY, 0, statVals[i], 24);
			val.scrollFactor.set();
			val.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			val.alpha = 0;
			add(val);
			FlxTween.tween(val, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});
		}

		// ---- KE 命中判定散点图（大图版） ----
		var graphPanel:FlxSprite = makePanel(GRAPH_X, GRAPH_Y, GRAPH_W, Std.int(GRAPH_H), 20);
		graphPanel.alpha = 0;
		add(graphPanel);
		FlxTween.tween(graphPanel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.12});

		var entries:Array<NoteHitEntry> = st.judgementHistory;
		var innerX:Float = GRAPH_X + 14;
		var innerW:Int = Std.int(GRAPH_W - 28);

		var graphHead:FlxText = new FlxText(innerX, GRAPH_Y + 8, innerW, '命中分布 Hit Distribution（横轴=时间 · 纵轴=偏移：+早到 / −晚到 · 点色=判定）', 14);
		graphHead.scrollFactor.set();
		graphHead.setFormat(Paths.font('future.ttf'), 14, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		graphHead.borderSize = 1.2;
		graphHead.antialiasing = ClientPrefs.data.antialiasing;
		graphHead.alpha = 0;
		add(graphHead);
		FlxTween.tween(graphHead, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.12});

		if (entries != null && entries.length > 0)
		{
			var graph:FlxSprite = NoteHitGraph.build(innerW, Std.int(GRAPH_H - 62), entries, st.songLength);
			graph.x = innerX;
			graph.y = GRAPH_Y + 30;
			graph.scrollFactor.set();
			graph.alpha = 0;
			add(graph);
			FlxTween.tween(graph, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.12});

			// Mean 均值 + 判定窗口说明（KE 同款底行）
			var sum:Float = 0;
			var cnt:Int = 0;
			for (e in entries)
				if (e.r != 'miss') { sum += e.d; cnt++; }
			var meanStr:String = (cnt > 0) ? ('平均偏移 Mean ' + CoolUtil.floorDecimal(sum / cnt, 2) + ' ms') : '平均偏移 Mean -';
			var winStr:String = 'SICK ' + ClientPrefs.data.sickWindow + ' / GOOD ' + ClientPrefs.data.goodWindow
				+ ' / BAD ' + ClientPrefs.data.badWindow + ' / SHIT 166';
			var meanText:FlxText = new FlxText(innerX, GRAPH_Y + GRAPH_H - 22, innerW, meanStr + '　' + winStr, 13);
			meanText.scrollFactor.set();
			meanText.setFormat(Paths.font('future.ttf'), 13, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			meanText.borderSize = 1.2;
			meanText.antialiasing = ClientPrefs.data.antialiasing;
			meanText.alpha = 0;
			add(meanText);
			FlxTween.tween(meanText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.12});
		}
		else
		{
			var noDataText:FlxText = new FlxText(innerX, GRAPH_Y + 44, innerW, '（本局无判定数据）', 16);
			noDataText.scrollFactor.set();
			noDataText.setFormat(Paths.font('future.ttf'), 16, 0xFFCFCFDC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			noDataText.borderSize = 1.2;
			noDataText.antialiasing = ClientPrefs.data.antialiasing;
			noDataText.alpha = 0;
			add(noDataText);
			FlxTween.tween(noDataText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.12});
		}

		// ---- 底部菜单（面板 + 高亮条 + 菜单项） ----
		buildMenu(PANEL_X, MENU_Y, PANEL_W);

		FlxG.mouse.visible = true;
		Lib.application.window.title = "FNF':Meteoric Engine - 结算";

		loadUIscripts('results');
	}

	/**
	 * 底部菜单（面板 + 提示 + 选中高亮条 + 菜单项）。
	 * 单机标准布局与联机精简版共用，x/y/w 由调用方传入。
	 */
	function buildMenu(x:Float, y:Float, w:Float):Void
	{
		menuPanelY = y;

		var panelHeight:Float = 16 + (menuItems.length * MENU_LINE_GAP * 1.3);
		var menuPanel:FlxSprite = makePanel(x, y, w, Std.int(panelHeight), 20);
		menuPanel.alpha = 0;
		add(menuPanel);
		FlxTween.tween(menuPanel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var hintText:FlxText = new FlxText(x + TEXT_PAD, y + panelHeight + 12, 0, getHintText(), 18);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), 18, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);

		#if mobile
		// virtualpad：A 在右下，[上][下] 依次在 A 左侧（同一行，不遮挡面板）；按下有动画
		pad = new objects.MobileControls(false, cameras[0], -1, true);
		pad.addPadArrow('ui_up', 'up', FlxG.width - objects.MobileControls.BTN_W * 3 - 20 - 24, FlxG.height - objects.MobileControls.BTN_H - 20);
		pad.addPadArrow('ui_down', 'down', FlxG.width - objects.MobileControls.BTN_W * 2 - 20 - 12, FlxG.height - objects.MobileControls.BTN_H - 20);
		add(pad);
		#end

		menuSelector = makePanel(x + 16, y + 9, w - 32, 44, 12, DesignTokens.rowHighlight, null);
		menuSelector.alpha = 0;
		add(menuSelector);
		FlxTween.tween(menuSelector, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		grpMenuShit = new FlxTypedGroup<MenuText>();
		add(grpMenuShit);
		for (i in 0...menuItems.length)
		{
			var item:MenuText = new MenuText(x + TEXT_PAD, y + 12 + (i * MENU_LINE_GAP * 1.3), menuItems[i], true, 34);
			item.isMenuItem = false;
			item.ID = i;
			grpMenuShit.add(item);
		}
		curSelected = 0;
		changeSelection();
	}

	/**
	 * 联机双栏结算：左=我的成绩+判定统计；右=对方成绩+判定统计 +「继续」。
	 * 对方未 FINISH 时右侧显示等待，FINISH 到达后由 refreshOpponentBlock 实时刷新。
	 * 关闭后由 PlayState 的 closeCallback 保持连接返回房间大厅。
	 */
	function createSimplified(st:PlayState):Void
	{
		onlineSimplified = true;
		menuItems = ['继续'];

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		FlxTween.tween(bg, {alpha: 0.6}, 0.25, {ease: FlxEase.quadOut});

		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, '本局结算 Song Results', 54);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 54, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		titleText.alpha = 0;
		add(titleText);
		FlxTween.tween(titleText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.05});

		var scW:Float = 600;
		var scX:Float = FlxG.width / 2 - scW / 2;
		var scY:Float = 118;
		var scH:Float = 330;

		var scPanel:FlxSprite = makePanel(scX, scY, scW, scH, 20);
		scPanel.alpha = 0;
		add(scPanel);
		FlxTween.tween(scPanel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		// ================= 左：我的成绩 =================
		var myColX:Float = scX + 30;
		var myValX:Float = myColX + 110;

		var myHeader:FlxText = makeSimText(myColX, scY + 22, '我的成绩', 22, DesignTokens.primary);
		myHeader.alpha = 0;
		add(myHeader);
		FlxTween.tween(myHeader, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var myRows:Array<Array<String>> = [
			['分数', FlxStringUtil.formatMoney(st.songScore)],
			['最高连击', Std.string(st.maxCombo)],
			['准确率', CoolUtil.floorDecimal(st.ratingPercent * 100, 2) + '%']
		];
		var rowY:Float = scY + 58;
		for (i in 0...myRows.length)
		{
			makeSimRow(myColX, myValX, rowY, myRows[i][0], myRows[i][1], 0xFFD7D7E0, 0.08);
			rowY += 34;
		}

		var myJudgeLabel:FlxText = makeSimText(myColX, scY + 172, '判定统计', 18, 0xFFD7D7E0);
		myJudgeLabel.alpha = 0;
		add(myJudgeLabel);
		FlxTween.tween(myJudgeLabel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		var ownCsv:Array<String> = [];
		for (r in st.ratingsData)
			if (r.hits > 0) ownCsv.push(r.name + ':' + r.hits);
		ownCsv.push('miss:' + st.songMisses);
		var ownJudge:FlxText = makeSimText(myColX, scY + 202, formatJudgeLines(ownCsv.join(',')), 16, FlxColor.WHITE);
		ownJudge.alpha = 0;
		add(ownJudge);
		FlxTween.tween(ownJudge, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		// ================= 右：对方成绩 =================
		var oppColX:Float = scX + 330;

		oppHeaderText = makeSimText(oppColX, scY + 22, '对方成绩 · ' + PlayState.onlineOppNick, 22, 0xFFFFA0A0);
		oppHeaderText.alpha = 0;
		add(oppHeaderText);
		FlxTween.tween(oppHeaderText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		oppScoreText = makeSimText(oppColX, scY + 58, '', 20, 0xFFD7D7E0);
		oppComboText = makeSimText(oppColX, scY + 92, '', 20, 0xFFD7D7E0);
		oppAccText = makeSimText(oppColX, scY + 126, '', 20, 0xFFD7D7E0);
		var oppRows:Array<FlxText> = [oppScoreText, oppComboText, oppAccText];
		for (i in 0...oppRows.length)
		{
			var t:FlxText = oppRows[i];
			t.alpha = 0;
			add(t);
			FlxTween.tween(t, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});
		}

		var oppJudgeLabel:FlxText = makeSimText(oppColX, scY + 172, '判定统计', 18, 0xFFD7D7E0);
		oppJudgeLabel.alpha = 0;
		add(oppJudgeLabel);
		FlxTween.tween(oppJudgeLabel, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		oppJudgeText = makeSimText(oppColX, scY + 202, '', 16, FlxColor.WHITE);
		oppJudgeText.alpha = 0;
		add(oppJudgeText);
		FlxTween.tween(oppJudgeText, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: 0.08});

		refreshOpponentBlock();

		buildMenu(scX, scY + scH + 14, scW);

		FlxG.mouse.visible = true;
		Lib.application.window.title = "FNF':Meteoric Engine - 结算";

		loadUIscripts('results');
	}

	/** 联机结算小字（双栏共用：列宽 270，左对齐白描边） */
	function makeSimText(x:Float, y:Float, text:String, size:Int, color:FlxColor):FlxText
	{
		var t:FlxText = new FlxText(x, y, 270, text, size);
		t.scrollFactor.set();
		t.setFormat(Paths.font('future.ttf'), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.antialiasing = ClientPrefs.data.antialiasing;
		return t;
	}

	/** 我的成绩单行（标签 + 值） */
	function makeSimRow(labelX:Float, valX:Float, y:Float, label:String, val:String, labelColor:FlxColor, delay:Float):Void
	{
		var lbl:FlxText = makeSimText(labelX, y, label + '：', 20, labelColor);
		lbl.alpha = 0;
		add(lbl);
		FlxTween.tween(lbl, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: delay});

		var valT:FlxText = makeSimText(valX, y, val, 20, FlxColor.WHITE);
		valT.alpha = 0;
		add(valT);
		FlxTween.tween(valT, {alpha: 1}, 0.25, {ease: FlxEase.quadOut, startDelay: delay});
	}

	/** 把 "sick:12,good:3,miss:1" 折成最多 3 行小字统计（每行约 26 字符断行，防溢出面板） */
	function formatJudgeLines(csv:String):String
	{
		if (csv == null || csv == '') return '—';
		var parts:Array<String> = csv.split(',');
		var lines:Array<String> = [];
		var cur:String = '';
		for (p in parts)
		{
			var kv:Array<String> = p.split(':');
			if (kv.length != 2) continue;
			var item:String = kv[0].toUpperCase() + ' ' + kv[1];
			if (cur == '') cur = item;
			else if (cur.length + item.length + 2 <= 26) cur += '  ' + item;
			else { lines.push(cur); cur = item; }
		}
		if (cur != '') lines.push(cur);
		while (lines.length > 3) lines.pop();
		return lines.length == 0 ? '—' : lines.join('\n');
	}

	/** 对方 FINISH 后刷新右侧成绩栏（每帧调用；未完成显示等待） */
	function refreshOpponentBlock():Void
	{
		var ps:PlayState = PlayState.instance;
		if (ps == null || oppScoreText == null) return;
		if (ps.onlineOppFinished && ps.onlineOppStats != null)
		{
			var stats:Array<Dynamic> = ps.onlineOppStats;
			var acc:Float = Std.parseFloat(Std.string(stats[6]));
			if (Math.isNaN(acc)) acc = 0;
			oppScoreText.text = '分数：' + FlxStringUtil.formatMoney(Std.int(stats[0]));
			oppComboText.text = '最高连击：' + Std.int(stats[5]);
			oppAccText.text = '准确率：' + Math.round(acc * 1000) / 10 + '%';
			oppJudgeText.text = formatJudgeLines(Std.string(stats[7]));
		}
		else
		{
			oppScoreText.text = '对方成绩：等待对方完成...';
			oppComboText.text = '';
			oppAccText.text = '';
			oppJudgeText.text = '';
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
		// 联机：结算期间 PlayState.update 冻结，由本界面继续泵网络（对方 FINISH/QUIT/DISCONNECTED）
		if (PlayState.isOnlineMode && PlayState.instance != null)
			PlayState.instance.onlineResultsNetworkTick();

		// 对方 FINISH 到达后实时刷新右侧成绩栏
		if (onlineSimplified)
			refreshOpponentBlock();
		super.update(elapsed);

		var upP = controls.UI_UP_P;
		var downP = controls.UI_DOWN_P;
		var accepted = controls.ACCEPT;
		#if mobile
		// virtualpad 按键（走 stage tap 队列，安卓 FlxG.touches 为空也能触发）
		if (pad != null)
		{
			if (pad.justPressed('accept')) accepted = true;
			if (pad.justPressed('ui_up')) upP = true;
			if (pad.justPressed('ui_down')) downP = true;
		}
		#end

		if (upP)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.x;
			mouseLockY = FlxG.mouse.y;
			changeSelection(-1);
		}
		if (downP)
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

			for (item in grpMenuShit.members)
			{
				if (mousePos.x >= item.x && mousePos.x <= item.x + item.width
					&& mousePos.y >= item.y && mousePos.y <= item.y + item.height)
					hoveredID = item.ID;
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
			// ---- 触屏：拖动上下滚动（选择只靠拖动/箭头，A 确认；点按行不改变选中）----
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
			resultAction = (menuItems[curSelected] == '重试') ? 'retry'
				: ((menuItems[curSelected] == '回放本局') ? 'replay' : 'continue');
			close();
		}
	}

	function getHintText():String
	{
		if (PlayState.isOnlineMode) return '回车确认 · ESC 返回联机大厅';
		if (PlayState.isStoryMode)
		{
			if (PlayState.storyPlaylist.length > 1) return '回车确认 · ESC 继续（播放下一首）';
			return '回车确认 · ESC 继续（完成周目，返回剧情选关）';
		}
		return '回车确认 · ESC 继续（返回自由选歌）';
	}

	function fcText(fc:String):String
	{
		switch (fc)
		{
			case 'FC': return '（全连）';
			case 'SDCB': return '（单断）';
			case 'Clear': return '（通过）';
		}
		return (fc == null || fc == '') ? '' : fc;
	}

	function translateDifficulty(d:String):String
	{
		switch (d)
		{
			case 'Easy': return '简单';
			case 'Normal': return '普通';
			case 'Hard': return '困难';
		}
		return d;
	}

	function changeSelection(change:Int = 0):Void
	{
		curSelected += change;

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		if (curSelected < 0)
			curSelected = menuItems.length - 1;
		if (curSelected >= menuItems.length)
			curSelected = 0;

		for (item in grpMenuShit.members)
		{
			item.alpha = 0.6;
			item.color = 0xFFCFCFDC;

			if (item.ID == curSelected)
			{
				item.alpha = 1;
				item.color = FlxColor.WHITE;
			}
		}

		if (menuSelector != null)
		{
			if(menuSelectorTween != null) {
				menuSelectorTween.cancel();
				menuSelectorTween = null;
			}
			var barY:Float = menuPanelY + 9 + (curSelected * MENU_LINE_GAP * 1.3);
			if(menuSelector.y != barY)
				menuSelectorTween = FlxTween.tween(menuSelector, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
		}

		callUIScripts('onChangeSelection', [curSelected, menuItems[curSelected]]);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
