package substates;
import backend.Lang;
import backend.WheelScroll;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import flixel.FlxBasic;
import flixel.addons.transition.FlxTransitionableState;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import objects.BackButton;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxStringUtil;

import states.StoryMenuState;
import states.FreeplayState;
import options.OptionsState;
import openfl.Lib;
import openfl.events.KeyboardEvent;

class PauseSubState extends MusicBeatSubstate
{
	var wheelScroll:WheelScroll = new WheelScroll(); // 滚轮限速（Freeplay 同款）
	// ===== 安全布局常量 =====
	// 所有文本一律左侧排版，右缘不依赖缩放/窗口计算，彻底避开右侧截断问题
	static final SAFE_MARGIN:Float = 72;      // 面板内文本左边距
	static final SAFE_RIGHT:Float = 1100;     // 任何文本右缘不得超过此值（画布 1280 内留 180px 余量）
	static final INFO_Y_START:Float = 100;    // 信息文本起始 Y
	static final INFO_LINE_GAP:Float = 30;    // 信息文本行距（改版前 34：4 行只占到面板 60%，底部空一大块）
	static final MENU_X:Float = 72;           // 菜单 X
	/** 分隔线上方留白 / 下方留白（px）。 */
	static final SEP_PAD_TOP:Float = 8;
	static final SEP_PAD_BOTTOM:Float = 16;

	/** 卡片头部高度（信息区）—— 按**实际行数**算。
	 *
	 *  ⚠ 之前写成常量 `26 + INFO_LINE_GAP * 3` 是错的：漏算了 `INFO_Y_START`
	 *  相对面板顶部的 30px 上边距（INFO_Y_START=100、INFO_PANEL_Y=70），
	 *  也漏算了「上帝模式已激活」那行的条件出现 —— 结果头部比实际矮 30px，
	 *  菜单整体上移，**「游玩难度 / 死亡次数」被前两个菜单项压住**
	 *  （用户实机截图：游玩难度与「返回游戏」重叠）。
	 *
	 *  正确算法：`上边距 + 行数×行距 + 分隔线上方留白`。
	 */
	function calcHeadH(infoRows:Int):Float
	{
		return (INFO_Y_START - INFO_PANEL_Y) + infoRows * INFO_LINE_GAP + SEP_PAD_TOP;
	}

	/** 菜单项起始 Y = 面板顶部 + 头部高度 + 分隔线 + 下方留白。实例字段，随行数变化。 */
	var MENU_Y:Float = 0;
	/**
	 * 菜单行距（MenuText 内部再乘 1.3 → 约 43px）。
	 * 33 而非 36 的原因：36 时 10 项菜单会把卡片撑到 708px、溢出 720 画布。
	 * **实例字段**：菜单项异常多时会按可用高度自动压缩（见 new() 里的兜底），
	 * 所以每次 regenMenu 前要恢复默认值，否则上一次压缩后的窄行距会被继承。
	 */
	var MENU_LINE_GAP:Float = MENU_LINE_GAP_DEFAULT;

	static inline var MENU_LINE_GAP_DEFAULT:Float = 33;

	// 圆角磨砂面板
	static final PANEL_X:Float = 40;          // 面板 X
	static final PANEL_W:Float = 600;         // 面板宽度
	static final INFO_PANEL_Y:Float = 70;     // 信息面板 Y

	// 右侧统计面板
	static final STATS_X:Float = 680;         // 面板 X
	static final STATS_W:Float = 560;         // 面板宽度
	static final STATS_TEXT_X:Float = 716;    // 面板内文本左边距
	static final STATS_ROW_START:Float = 82;  // 数据行起始 Y（相对卡片顶部；标题在 +26）
	/** 数据行距的**兜底值**（仅 1 行时用）；正常按卡片高度自适应，见 new() 里的 statGap。 */
	static final STATS_ROW_GAP:Float = 58;

	var grpMenuShit:FlxTypedGroup<MenuText>;

	// ===== 菜单项内部 ID（多语言）=====
	// 关键设计：**内部一律用稳定英文 ID**，中文只在 displayLabel() 一处翻译。
	// 旧实现把中文串当 menuItemsOG 的值并直接当 switch 的 case 选择器 —— 那样一本地化
	// 分支就全断了；现在 ID 与语言解耦，显示与行为彻底分离。
	static final ID_RESUME:String = 'resume';
	static final ID_RESTART:String = 'restart';
	static final ID_SKIP:String = 'skipTime';
	static final ID_DIFFICULTY:String = 'changeDifficulty';
	static final ID_SCRIPTS:String = 'scriptManager';
	static final ID_GAMEPLAY:String = 'gameplaySettings';
	static final ID_OPTIONS:String = 'options';
	static final ID_EXIT:String = 'exitToMenu';
	static final ID_EXIT_CHARTING:String = 'exitCharting';
	static final ID_END_SONG:String = 'endSong';
	static final ID_BACK:String = 'back';

	var menuItems:Array<String> = [];
	var menuItemsOG:Array<String> = [ID_RESUME, ID_RESTART, ID_SKIP, ID_DIFFICULTY, ID_SCRIPTS, ID_GAMEPLAY, ID_OPTIONS, ID_EXIT];
	var difficultyChoices = [];
	var curSelected:Int = 0;

	var pauseMusic:FlxSound;
	var practiceText:FlxText;
	var skipTimeText:FlxText;
	var skipTimeTracker:MenuText;
	var curTime:Float = Math.max(0, Conductor.songPosition);

	var missingTextBG:FlxSprite;
	var missingText:FlxText;
	var menuSelector:FlxSprite;
	var menuSelectorTween:FlxTween;
	var backBtn:BackButton;
	// 子页（设置/脚本管理等）打开时整体隐藏的"菜单侧"UI（右侧本局数据面板保留）
	var menuUI:Array<FlxBasic> = [];
	var menuUIHidden:Bool = false;
	var statPanel:FlxSprite;
	var statLabels:Array<FlxText> = [];
	var statTexts:Array<FlxText> = [];
	var statLast:Array<String> = [];

	// 【分配削减】updateStats 的轻量签名：暂停期间绝大多数帧这些底值不变，
	// 此时直接 return，不再每帧 formatTime/formatMoney/7 字符串数组分配
	//（暂停里每秒一次 GC 尖峰的喂食源就用这里切断）。初始值 = 必然不相等的哨兵。
	var _sigScore:Int = 0x7fffffff;
	var _sigMisses:Int = 0x7fffffff;
	var _sigCombo:Int = 0x7fffffff;
	var _sigRatingName:String = null;
	var _sigFC:String = null;
	var _sigPct:Int = 0x7fffffff;
	var _sigHits:Int = 0x7fffffff;
	var _sigTotal:Int = 0x7fffffff;
	var _sigSec:Int = 0x7fffffff;
	var _sigMLen:Int = 0x7fffffff;

	var mouseActive:Bool = true;  // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;      // 键盘接管时记录的鼠标位置
	var mouseLockY:Float = 0;

	// ===== 暂停键防双击（“按一下暂停键被判定为两下 → 暂停界面闪现回播放”）=====
	// 根因：'pause'(ENTER/ESC) 与 'accept'(SPACE/ENTER) 键位重叠；并且打开暂停子界面时
	// flixel 会重置输入状态（onStateSwitch），若暂停键仍被按住，OS 自动重复的 keydown
	// 会把 JUST_PRESSED 重新武装——同一物理按键被判定为两次：第一次打开暂停，
	// 第二次立刻被菜单当作“确认”关闭，表现为暂停界面一闪而过。
	// 修复：打开瞬间由 PlayState 捕获“暂停键是否仍按住”（此刻输入尚未重置），
	// 传入本界面 → 锁定 ACCEPT，直到该键被物理松开（stage 原始 KEY_UP 监听，
	// 不受 flixel 输入重置影响）。控制器不受影响（其保护由 cantUnpause 承担）。
	var lockPauseAccept:Bool = false;

	#if mobile
	var touchDownRow:Int = -1;    // 触屏点选：按下时所在的行
	var touchDownID:Int = -1;     // 触屏点选：触摸点 ID
	#end

	#if mobile
	var pausePad:objects.MobileControls;
	#end

	public static var songName:String = '';

	public function new(x:Float, y:Float, ?pauseKeyHeld:Bool = false)
	{
		super();
		lockPauseAccept = pauseKeyHeld;

		// 监听暂停键的物理松开（stage 原始事件，绕开 flixel 输入重置后的状态失真）
		if (Lib.current.stage != null)
			Lib.current.stage.addEventListener(KeyboardEvent.KEY_UP, onPauseKeyUp);

		// 固定渲染在专用相机上：zoom=1、scroll=(0,0)，不受游戏相机缩放影响
		var pauseCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [pauseCam];
		cameras[0].zoom = 1;
		cameras[0].scroll.set(0, 0);

		if(Difficulty.list.length < 2) menuItemsOG.remove(ID_DIFFICULTY); //No need to change difficulty if there is only one!
		if(PlayState.instance.startingSong) menuItemsOG.remove(ID_SKIP); //歌曲还没开始时无需跳转

		if(PlayState.chartingMode)
		{
			menuItemsOG.insert(2, ID_EXIT_CHARTING);
			menuItemsOG.insert(3, ID_END_SONG);
		}
		menuItems = menuItemsOG;

		// 存**原始难度名**（Easy/Normal/Hard），不再预翻译成中文：
		// 预翻译会把「行为值」和「显示文案」绑死，切换语言后档位标签仍是旧语言。
		for (i in 0...Difficulty.list.length) difficultyChoices.push(Difficulty.getString(i));
		difficultyChoices.push(ID_BACK);

		pauseMusic = new FlxSound();
		// 暂停音乐资源缺失时绝不能阻止暂停界面打开（否则会出现“暂停界面显示不出来”但游戏已冻结）
		try
		{
			if(songName != null) {
				pauseMusic.loadEmbedded(Paths.music(songName), true, true);
			} else if (songName != Lang.tOr('pause.musicNone', '无')) {
				pauseMusic.loadEmbedded(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)), true, true);
			}
			trace('[PAUSE] PauseSubState new: pauseMusic=' + songName);
			pauseMusic.volume = 0;
			pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));
			FlxG.sound.list.add(pauseMusic);
		}
		catch (e:Dynamic)
		{
			trace('[PAUSE] 暂停音乐加载失败，跳过：' + e);
			pauseMusic = null;
		}

		// ---- 背景 ----
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		FlxTween.tween(bg, {alpha: 0.6}, 0.25, {ease: FlxEase.quadOut});

		// ---- 标题（水平居中，从上方飞入；它是界面第一眼，先落位） ----
		var titleText:FlxText = new FlxText(0, 22, FlxG.width, Lang.tOr('pause.paused', '已暂停'), 54);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 54, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);
		flyIn(titleText, FLY_DOWN, 0.04);

		// ---- 编铺模式徽章（左上角圆角磨砂小面板） ----
		var chartingPanel:FlxSprite = makePanel(40, 16, 130, 36, 12);
		chartingPanel.alpha = 0;
		chartingPanel.visible = PlayState.chartingMode;
		add(chartingPanel);

		var chartingText:FlxText = new FlxText(40, 20, 130, Lang.tOr('pause.chartingMode', '编铺模式'), 18);
		chartingText.scrollFactor.set();
		chartingText.setFormat(Paths.font('future.ttf'), 18, DesignTokens.secondary, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		chartingText.borderSize = 2;
		chartingText.antialiasing = ClientPrefs.data.antialiasing;
		chartingText.visible = PlayState.chartingMode;
		add(chartingText);
		if(PlayState.chartingMode)
		{
			flyIn(chartingPanel, FLY_DOWN, 0.12);
			flyIn(chartingText, FLY_DOWN, 0.12);
		}

		// ---- 左列：一张卡片 = 曲目信息（头部）+ 菜单项 ----
		// 改版前是**两张**独立卡片（信息面板 / 菜单面板）上下排，1280×720 画布里
		// 三块面板（+ 右侧数据面板）显得拥挤（用户实机报告「面板太多导致拥挤」）。
		// 现在合成一张：信息当卡片头部的三行，菜单接在下面，用一条分隔线区分，
		// 面板总数 3 → 2，垂直方向也腾出一整块空白。
		// 头部高度按实际行数算：常态 3 行，上帝模式时多一行「上帝模式已激活！」
		var infoRows:Int = PlayState.instance.practiceMode ? 4 : 3;
		var headerH:Float = calcHeadH(infoRows);
		MENU_Y = INFO_PANEL_Y + headerH + SEP_PAD_TOP + SEP_PAD_BOTTOM;
		var menuBlockH:Float = menuItems.length * MENU_LINE_GAP * 1.3;
		// 兜底：菜单项异常多时（如编谱模式额外插入「退出编铺 / 结束歌曲」等），
		// 固定行距会把卡片撑出画布底部。按可用高度压缩行距，而不是让它溢出屏幕。
		var maxPanelH:Float = 720 - 16 - INFO_PANEL_Y;   // 画布 720，留 16px 底边距
		var minGap:Float = 26;                            // 行距下限（×1.3 后约 34px，仍可读）
		var maxGap:Float = MENU_LINE_GAP;
		if (headerH + SEP_PAD_TOP + SEP_PAD_BOTTOM + 10 + menuBlockH > maxPanelH)
		{
			var usable:Float = maxPanelH - headerH - SEP_PAD_TOP - SEP_PAD_BOTTOM - 10;
			var gap:Float = (menuItems.length > 0) ? usable / (menuItems.length * 1.3) : maxGap;
			MENU_LINE_GAP = FlxMath.bound(gap, minGap, maxGap);
			menuBlockH = menuItems.length * MENU_LINE_GAP * 1.3;
		}
		var panelHeight:Float = headerH + SEP_PAD_TOP + SEP_PAD_BOTTOM + menuBlockH + 10;
		var menuPanel:FlxSprite = makePanel(PANEL_X, INFO_PANEL_Y, PANEL_W, Std.int(panelHeight), 20);
		add(menuPanel);
		flyIn(menuPanel, FLY_LEFT, 0.10);

		// ---- 信息文本（卡片头部，左对齐；右侧永不越界） ----
		var levelInfo:FlxText = makeInfoText(Lang.tOr('pause.songLabel', '游玩曲目：') + PlayState.SONG.song, INFO_Y_START);
		var levelDifficulty:FlxText = makeInfoText(Lang.tOr('pause.difficultyLabel', '游玩难度：') + translateDifficulty(Difficulty.getString()), INFO_Y_START + INFO_LINE_GAP);
		var blueballedTxt:FlxText = makeInfoText(Lang.tOr('pause.deathsLabel', '死亡次数：') + PlayState.deathCounter, INFO_Y_START + INFO_LINE_GAP * 2);

		practiceText = makeInfoText(Lang.tOr('pause.godModeActive', '上帝模式已激活！'), INFO_Y_START + INFO_LINE_GAP * 3, DesignTokens.secondary);
		practiceText.visible = PlayState.instance.practiceMode;
		flyInRows([levelInfo, levelDifficulty, blueballedTxt], FLY_LEFT, 0.16);
		if (PlayState.instance.practiceMode)
			flyIn(practiceText, FLY_LEFT, 0.16 + FLY_STAGGER * 3);

		// 头部分隔线：把「本局是什么」和「能点什么」在视觉上分开，
		// 省掉一整块面板边框，信息密度高但不糊。
		// ⚠ `makeGraphic` 第三参是 `FlxGraphicAsset`（贴图），**不是颜色** ——
		// 传颜色会编译失败。分隔线要纯色，用 `FlxSpriteUtil.drawRect` 画。
		var sepW:Float = PANEL_W - (SAFE_MARGIN - 32) * 2;
		var sep:FlxSprite = new FlxSprite(PANEL_X + SAFE_MARGIN - 32, INFO_PANEL_Y + headerH + SEP_PAD_TOP);
		sep.makeGraphic(Std.int(sepW), 1, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRect(sep, 0, 0, sepW, 1, FlxColor.TRANSPARENT, {color: DesignTokens.panelOutline, thickness: 1});
		sep.scrollFactor.set();
		sep.alpha = 0.6;
		add(sep);
		flyIn(sep, FLY_LEFT, 0.20);

		// ---- 右侧统计面板（第二张卡片，与左列等高） ----
		var statsPanelH:Float = panelHeight;
		statPanel = makePanel(STATS_X, INFO_PANEL_Y, STATS_W, Std.int(statsPanelH), 20);
		add(statPanel);
		flyIn(statPanel, FLY_RIGHT, 0.10);

		var statTitle:FlxText = new FlxText(STATS_TEXT_X, INFO_PANEL_Y + 26, 0, Lang.tOr('pause.sessionData', '本局数据'), 26);
		statTitle.scrollFactor.set();
		statTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statTitle.borderSize = 2;
		statTitle.antialiasing = ClientPrefs.data.antialiasing;
		add(statTitle);
		flyIn(statTitle, FLY_RIGHT, 0.16);

		var statDefs:Array<String> = [Lang.tOr('pause.score', '当前分数'), Lang.tOr('pause.misses', '失误数'), Lang.tOr('pause.combo', '当前连击'), Lang.tOr('pause.rating', '评分'), Lang.tOr('pause.accuracy', '准确度'), Lang.tOr('pause.hitsTotal', '命中 / 总音符'), Lang.tOr('pause.songProgress', '歌曲进度')];
		// 行距按卡片实际高度自适应：左卡片高度随菜单项数量与信息行数变化，
		// 行距若写死，菜单项一多右卡片底部就空一大块（原先固定 58px 时约 100px 空白）。
		// 这里把可用高度均分成 (行数-1) 段，并夹在可读区间内，避免过疏或过挤。
		var statRows:Int = statDefs.length;
		var statAvail:Float = panelHeight - STATS_ROW_START - 44;   // 44 = 底部留白
		var statGap:Float = (statRows > 1) ? statAvail / (statRows - 1) : STATS_ROW_GAP;
		statGap = FlxMath.bound(statGap, 46, 68);
		for (i in 0...statDefs.length)
		{
			var rowY:Float = INFO_PANEL_Y + STATS_ROW_START + (i * statGap);

			var lbl:FlxText = new FlxText(STATS_TEXT_X, rowY, 0, statDefs[i] + '：', 24);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), 24, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			statLabels.push(lbl);
			flyIn(lbl, FLY_RIGHT, 0.30 + FLY_STAGGER * i);

			var val:FlxText = new FlxText(STATS_TEXT_X + 210, rowY, 0, '', 24);
			val.scrollFactor.set();
			val.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			add(val);
			statTexts.push(val);
			statLast.push('');
			// 数值与标签同一行、同一延迟到达（标签先建但延迟相同，视觉上成对出现）
			flyIn(val, FLY_RIGHT, 0.30 + FLY_STAGGER * i);
		}
		updateStats();

		// ---- 选中高亮条（跟随当前菜单项） ----
		menuSelector = makePanel(PANEL_X + 16, MENU_Y - 3, PANEL_W - 32, 44, 12, DesignTokens.rowHighlight, null);
		menuSelector.alpha = 0;
		add(menuSelector);
		// 高亮条只淡入、不飞入：它的 y 会被 `changeSelection` 的 menuSelectorTween 接管
		//（补间 `{y: barY}`），这里若也补间 y 会和选中移动打架。
		// 延迟对齐菜单项（0.26 + 0.028*i），让高亮条和它框住的第一项几乎同时出现。
		FlxTween.tween(menuSelector, {alpha: 1}, 0.2, {ease: FlxEase.quadOut, startDelay: 0.27});

		grpMenuShit = new FlxTypedGroup<MenuText>();
		add(grpMenuShit);

		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("future.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		// 悬停高亮条（跟随鼠标，不改变选中）+ 返回按钮
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		#if mobile
		// 暂停界面补上 virtualpad A 键（不注册为全局 instance，避免干扰游玩触控板）
		pausePad = new objects.MobileControls(false, cameras[0], -1, true);
		add(pausePad);
		#end

		regenMenu(true); // 首次打开：菜单项逐项飞入
		FlxG.mouse.visible = true;
		Lib.application.window.title = Lang.tOr('pause.windowTitle', "FNF':Meteoric Engine - 暂停");

		trace('[PAUSE] 新暂停界面已加载 | 画布=' + FlxG.width + 'x' + FlxG.height + ' | 菜单项=' + menuItems.length);
		trace('[PAUSE] 信息文本最右缘=' + (blueballedTxt.x + blueballedTxt.width) + ' | 安全上限=' + SAFE_RIGHT);

		loadUIscripts('pause');

		// 收集"菜单侧"UI：子页打开时整体隐藏（右侧本局数据面板 statPanel/statLabels/statTexts 保留）
		menuUI = [bg, titleText, chartingPanel, chartingText, menuPanel, sep, levelInfo, levelDifficulty,
			blueballedTxt, practiceText, menuSelector, grpMenuShit,
			backBtn.glow, backBtn.spr, backBtn.label];
	}

	function setMenuUI(visible:Bool):Void
	{
		for (obj in menuUI)
			if (obj != null) obj.visible = visible;
		if (!visible && skipTimeText != null) skipTimeText.visible = false;
	}

	function makeInfoText(content:String, yPos:Float, ?textColor:FlxColor = FlxColor.WHITE, ?size:Int = 26):FlxText
	{
		var txt:FlxText = new FlxText(SAFE_MARGIN, yPos, 0, content, size);
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

	// ==================== 入场动画 ====================

	/** 飞入方向。 */
	static inline var FLY_UP:Int = 0;
	static inline var FLY_DOWN:Int = 1;
	static inline var FLY_LEFT:Int = 2;
	static inline var FLY_RIGHT:Int = 3;

	/** 单个元素的飞入位移（px）。够明显但不夸张。 */
	static inline var FLY_DIST:Float = 26;

	/** 飞入时长 / 同组内每行的错峰间隔（秒）。 */
	static inline var FLY_DUR:Float = 0.26;
	static inline var FLY_STAGGER:Float = 0.028;

	/**
	 * 元素飞入：位移 + 淡入，位移用 `quadOut`（起步快、收尾稳）。
	 *
	 * 改版前整个暂停界面所有元素都用**同一个** `startDelay: 0.08` 一起淡入 ——
	 * 视觉上像「整块一起亮起来」，没有主次；而且菜单项（`regenMenu` 里建的
	 * `MenuText`）**完全没有动画**，直接闪现，和周围的面板/文本脱节。
	 * 现在改成按组错峰飞入：标题 → 左列菜单 → 右列数据。
	 *
	 * @param obj   目标（会先记录当前 x/y 作为终点）
	 * @param dir   FLY_* 方向
	 * @param delay 该元素在组内的起始延迟
	 * @param targetAlpha 终态透明度。菜单项**必须**传对：非选中项常态是 0.6，
	 *        若一律补到 1，未选中项会比选中项还亮（且 `changeSelection` 只在
	 *        切换选中时才跑，不会来纠正）。
	 */
	function flyIn(obj:FlxSprite, dir:Int, delay:Float, ?targetAlpha:Float):Void
	{
		if (obj == null) return;
		var endAlpha:Float = (targetAlpha != null) ? targetAlpha : 1;
		var tx:Float = obj.x;
		var ty:Float = obj.y;
		var ox:Float = 0;
		var oy:Float = 0;
		switch (dir)
		{
			case FLY_UP: oy = FLY_DIST;
			case FLY_DOWN: oy = -FLY_DIST;
			case FLY_LEFT: ox = -FLY_DIST;
			default: ox = FLY_DIST;
		}
		obj.alpha = 0;
		obj.x = tx + ox;
		obj.y = ty + oy;
		FlxTween.tween(obj, {alpha: endAlpha, x: tx, y: ty}, FLY_DUR, {ease: FlxEase.quadOut, startDelay: delay});
	}

	/**
	 * 按行错峰飞入一组文本（每行 `i * stagger`）。
	 * 面板本体先落位、文本随后浮现，读起来是「卡片进来 → 内容展开」。
	 */
	function flyInRows(rows:Array<FlxSprite>, dir:Int, baseDelay:Float):Void
	{
		for (i in 0...rows.length)
			flyIn(rows[i], dir, baseDelay + FLY_STAGGER * i);
	}

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.1;

	#if mobile
	/** 暂停菜单里按返回键 / 左上角 X：继续游戏，不退出 */
	override public function onAndroidBack():Bool
	{
		close();
		return true;
	}
	#end

	override function update(elapsed:Float)
	{
		#if METEORIC_PROFILE
		backend.MeteoricProfile.begin();
		#end
		// 每帧固定暂停相机缩放/滚动，防止暂停期间任何运行期改动导致文本截断
		if (cameras != null && cameras[0] != null)
		{
			cameras[0].zoom = 1;
			cameras[0].scroll.set(0, 0);
		}
		FlxG.mouse.visible = true;
		// 子页（设置列表/脚本管理等）打开期间：暂停菜单冻结输入并隐藏菜单侧 UI，由子页独占
		// （相机层上子页与暂停同用 camOther，渲染顺序由嵌套保证在暂停菜单之上；隐藏菜单是双保险）
		if (subState != null)
		{
			if (!menuUIHidden) { setMenuUI(false); menuUIHidden = true; }
			cantUnpause -= elapsed;
			if (pauseMusic != null && pauseMusic.volume < 0.5)
				pauseMusic.volume += 0.01 * elapsed;
			super.update(elapsed);
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('PauseSubState.update');
			#end
			return;
		}
		if (menuUIHidden) { setMenuUI(true); menuUIHidden = false; }
		cantUnpause -= elapsed;
		if (pauseMusic != null && pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseBegin('pauseSuper');
		#end
		super.update(elapsed);
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseEnd('pauseSuper');
		#end
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseBegin('pauseStats');
		#end
		updateStats();
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseEnd('pauseStats');
		#end
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseBegin('pauseSkip');
		#end
		updateSkipTextStuff();
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseEnd('pauseSkip');
		#end

		var upP = controls.UI_UP_P;
		var downP = controls.UI_DOWN_P;
		var accepted = controls.ACCEPT;
		#if mobile
		if (pausePad != null && pausePad.justPressed('accept')) accepted = true;

		// ---- 触屏直接点选（不依赖鼠标模拟）：按下所在行即选中，抬起仍在同一行则确认 ----
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				var tp:FlxPoint = touch.getPositionInCameraView(cameras[0], FlxPoint.get());
				for (item in grpMenuShit.members)
				{
					if (tp.x >= item.x && tp.x <= item.x + item.width
						&& tp.y >= item.y && tp.y <= item.y + item.height)
					{
						touchDownRow = item.ID;
						touchDownID = touch.touchPointID;
						if (touchDownRow != curSelected) changeSelection(touchDownRow - curSelected);
						break;
					}
				}
				// 返回按钮：触屏直接点按关闭
				if (touchDownRow < 0 && backBtn.over(tp.x, tp.y))
				{
					mouseActive = true;
					close();
					Lib.application.window.title = Lang.tOr('win.playing', "FNF':Meteoric Engine - Playing: ") + PlayState.SONG.song;
					tp.put();
					return;
				}
				tp.put();
			}
			else if (touch.justReleased && touch.touchPointID == touchDownID)
			{
				var tp:FlxPoint = touch.getPositionInCameraView(cameras[0], FlxPoint.get());
				var onRow:Bool = false;
				for (item in grpMenuShit.members)
				{
					if (item.ID == touchDownRow && tp.x >= item.x && tp.x <= item.x + item.width
						&& tp.y >= item.y && tp.y <= item.y + item.height)
					{
						onRow = true;
						break;
					}
				}
				tp.put();
				if (onRow) accepted = true;
				touchDownRow = -1;
				touchDownID = -1;
			}
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
			var hoveredID:Int = -1;
			// 用暂停专用相机计算鼠标坐标（游戏相机在暂停时 scroll/zoom 均不为 0，直接用会偏移）
			var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());
			for (item in grpMenuShit.members)
			{
				if (mousePos.x >= item.x && mousePos.x <= item.x + item.width
					&& mousePos.y >= item.y && mousePos.y <= item.y + item.height)
					hoveredID = item.ID;
			}

			// 返回按钮：悬停高亮，点击返回游戏
			var clickPressed:Bool = FlxG.mouse.justPressed;
			#if mobile
			clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
			#end

			backBtn.setHovered(mousePos.x, mousePos.y);
			if (clickPressed && backBtn.over(mousePos.x, mousePos.y))
			{
				mouseActive = true;
				close();
				Lib.application.window.title = Lang.tOr('win.playing', "FNF':Meteoric Engine - Playing: ") + PlayState.SONG.song;
				return;
			}
			mousePos.put();

			// 鼠标离开键盘接管位置超过阈值 → 恢复鼠标跟随（防轻微抖动误触发）
			if (!mouseActive)
			{
				var dx:Float = FlxG.mouse.x - mouseLockX;
				var dy:Float = FlxG.mouse.y - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);

			if (wheelStep != 0)
			{
				mouseActive = true;
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(wheelStep);
			}

			if (hoveredID >= 0 && clickPressed)
			{
				mouseActive = true;
				if (hoveredID != curSelected) changeSelection(hoveredID - curSelected);
				accepted = true;
			}
		}

		var daSelected:String = menuItems[curSelected];
		switch (daSelected)
		{
			case ID_SKIP:
				if (controls.UI_LEFT_P)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime -= 1000;
					holdTime = 0;
				}
				if (controls.UI_RIGHT_P)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime += 1000;
					holdTime = 0;
				}

				if(controls.UI_LEFT || controls.UI_RIGHT)
				{
					holdTime += elapsed;
					if(holdTime > 0.5)
					{
						curTime += 45000 * elapsed * (controls.UI_LEFT ? -1 : 1);
					}

					if(curTime >= FlxG.sound.music.length) curTime -= FlxG.sound.music.length;
					else if(curTime < 0) curTime += FlxG.sound.music.length;
					updateSkipTimeText();
				}
		}

		// 防“暂停键判定两次”：打开暂停的同一物理按键（ENTER/ESC）在本帧残留或长按
		// 重复事件中会被再次判为“确认”，导致暂停菜单打开即关闭的闪现。
		// 锁定期间（暂停键未物理松开）忽略一切确认来源，松开后恢复正常。
		if (lockPauseAccept)
			accepted = false;

		// 确认前必须经过短暂冷却（对键盘同样生效）：同帧残留的保护网
		if (accepted && cantUnpause <= 0)
		{
			if (menuItems == difficultyChoices)
			{
				try{
					if(menuItems.length - 1 != curSelected && difficultyChoices.contains(daSelected)) {

						var name:String = PlayState.SONG.song;
						var poop = Highscore.formatSong(name, curSelected);
						PlayState.setSong(Song.loadFromJson(poop, name));
						// 登记新难度谱面身份：游玩期剥离 SONG.notes 后仍可恢复
						PlayState.registerChartSource(poop, name, name);
						PlayState.storyDifficulty = curSelected;
						// 更换难度后不再继续回放，退回普通游玩
						PlayState.queuedReplay = null;
						PlayState.carryReplay = null;
						MusicBeatState.resetState();
						FlxG.sound.music.volume = 0;
						PlayState.changedDifficulty = true;
						PlayState.chartingMode = false;
						return;
					}
				}catch(e:Dynamic){
					trace('错误！$e');

					var errorStr:String = e.toString();
					if(errorStr.startsWith('[file_contents,assets/data/')) errorStr = Lang.tOr('pause.missingFiles', '丢失的文件：') + errorStr.substring(27, errorStr.length-1); //Missing chart
					missingText.text = Lang.tOr('pause.loadChartFailedPrefix', '加载铺面文件时出错！\n') + errorStr;
					missingText.screenCenter(Y);
					missingText.visible = true;
					missingTextBG.visible = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));

					super.update(elapsed);
					return;
				}


				menuItems = menuItemsOG;
				regenMenu(); // 从子页返回：列表内容未变，不重播入场动画
			}

			switch (daSelected)
			{
				case ID_RESUME:
					close();
					Lib.application.window.title = Lang.tOr('win.playing', "FNF':Meteoric Engine - Playing: ") + PlayState.SONG.song;
					#if METEORIC_PROFILE
					trace('[TITLE] resume set lib="' + Lib.application.window.title + '" limeSame=' + (lime.app.Application.current.window == Lib.application.window));
					#end
				case ID_DIFFICULTY:
					menuItems = difficultyChoices;
					deleteSkipTimeText();
					regenMenu(true); // 难度列表换了内容 → 播一次飞入
				case ID_RESTART:
					restartSong();
				case ID_EXIT_CHARTING:
					restartSong();
					PlayState.chartingMode = false;
				case ID_SKIP:
					if(curTime < Conductor.songPosition)
					{
						PlayState.startOnTime = curTime;
						restartSong(true, false);
					}
					else
					{
						if (curTime != Conductor.songPosition)
						{
							// 回放中跳时间：把按键注入游标对齐到新时间点，避免旧按键一次性补触发
							if (PlayState.instance.replayMode)
								PlayState.instance.resetReplayToTime(curTime);
							PlayState.instance.clearNotesBefore(curTime);
							PlayState.instance.setSongTime(curTime);
						}
						close();
					}
				case ID_END_SONG:
					close();
					PlayState.instance.notes.clear();
					PlayState.instance.unspawnNotes = [];
					PlayState.instance.finishSong(true);
				case ID_GAMEPLAY:
					persistentUpdate = false;
					var gameplaySettingsSubState:GameplayChangersSubstate = new GameplayChangersSubstate();
					gameplaySettingsSubState.closeCallback = function() {
						persistentUpdate = true;
						if (practiceText != null)
							practiceText.visible = PlayState.instance.practiceMode;
					};
					openSubState(gameplaySettingsSubState);
				case ID_SCRIPTS:
					persistentUpdate = false;
					var scriptManagerSubState:ScriptManagerSubstate = new ScriptManagerSubstate();
					scriptManagerSubState.closeCallback = function() {
						persistentUpdate = true;
					};
					openSubState(scriptManagerSubState);
				case ID_OPTIONS:
					// 嵌入式设置：直接叠加分类列表子页，关闭后回到暂停菜单（保持暂停、不重载曲目）。
					// 设置改动即时生效；需重载的项（判定模式/音符皮肤等）在下次重开曲目时生效。
					openSubState(new PauseSettingsSubstate());
				case ID_EXIT:
					PlayState.deathCounter = 0;
					PlayState.seenCutscene = false;

					// 冻结本 State（与 endSong 结算路径一致）：0.6s 转场期间不再驱动
					// PlayState.update（Lua onUpdate / holdCover 同步等），避免在半撕裂窗口
					// 继续执行脚本；FlxState.tryUpdate 保证转场子状态照常更新。
					PlayState.instance.persistentUpdate = false;

					Mods.loadTopMod();
					if(PlayState.isStoryMode) {
						MusicBeatState.switchState(new StoryMenuState());
					} else {
						MusicBeatState.switchState(new FreeplayState());
					}
					PlayState.cancelMusicFadeTween();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					PlayState.changedDifficulty = false;
					PlayState.chartingMode = false;
					FlxG.camera.followLerp = 0;
			}
		}

		#if METEORIC_PROFILE
		backend.MeteoricProfile.end('PauseSubState.update');
		#end
	}

	function deleteSkipTimeText()
	{
		if(skipTimeText != null)
		{
			skipTimeText.kill();
			remove(skipTimeText);
			skipTimeText.destroy();
		}
		skipTimeText = null;
		skipTimeTracker = null;
	}

	public static function restartSong(noTrans:Bool = false, skipChartReload:Null<Bool> = null)
	{
		PlayState.instance.paused = true; // For lua
		FlxG.sound.music.volume = 0;
		PlayState.instance.vocals.volume = 0;
		// 重开时重置可能被 Mod 改掉的 hideHud，避免 HUD 消失
		ClientPrefs.resetHideHud();

		// 回放中重开：保留回放数据。
		// 快速重开走 restartSongWithoutReload（数据在实例内保留）；
		// 完整重开走 resetState → create，需要经 queuedReplay 重新喂给新实例。
		if (PlayState.instance.replayMode && PlayState.carryReplay != null)
			PlayState.queuedReplay = PlayState.carryReplay;
		else
			PlayState.queuedReplay = null;

		if(skipChartReload == null) skipChartReload = ClientPrefs.data.restartNoChartReload;
		if(skipChartReload)
		{
			// 快速重开：关闭暂停菜单并原地重开，不重新加载谱面
			PlayState.instance.closeSubState();
			PlayState.instance.resetSubState();
			PlayState.instance.restartSongWithoutReload();
			return;
		}

		if(noTrans)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		MusicBeatState.resetState();
	}

	override function destroy()
	{
		// 移除 stage 原始键盘监听，避免对象泄漏后仍被回调
		if (Lib.current.stage != null)
			Lib.current.stage.removeEventListener(KeyboardEvent.KEY_UP, onPauseKeyUp);
		FlxG.mouse.visible = false;
		if (pauseMusic != null) pauseMusic.destroy();

		super.destroy();
	}

	/** 当前暂停键的键盘绑定（用户自定义键位），缺失时回退默认 [ENTER, ESCAPE] */
	public static function getPauseKeys():Array<FlxKey>
	{
		if (ClientPrefs.keyBinds != null && ClientPrefs.keyBinds.get('pause') != null)
			return ClientPrefs.keyBinds.get('pause');
		return [FlxKey.ENTER, FlxKey.ESCAPE];
	}

	/** 暂停键被物理松开 → 解除确认锁定（原始事件，不受 flixel 输入重置影响） */
	private function onPauseKeyUp(event:KeyboardEvent):Void
	{
		for (key in getPauseKeys())
		{
			if ((key : Int) == event.keyCode)
			{
				lockPauseAccept = false;
				break;
			}
		}
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
			// 入场动画进行中：让 flyIn 独占 alpha，否则这里会把它刚设的 0 覆盖成 0.6/1
			//（用户实机报告「没看见动画」的确定原因之一 —— 菜单项一直是闪现的）。
			// 判定用 alpha < 1 而不是另开标志位：动画期间 alpha 必然 <1，
			// 动画一结束就交回本函数控制，不会残留状态。
			if (item.alpha < 1) continue;

			item.alpha = 0.6;
			item.color = 0xFFCFCFDC;

			if (item.ID == curSelected)
			{
				item.alpha = 1;
				item.color = FlxColor.WHITE;

				if(item == skipTimeTracker)
				{
					curTime = Math.max(0, Conductor.songPosition);
					updateSkipTimeText();
				}
			}
		}

		// 高亮条跟随当前选项
		if (menuSelector != null)
		{
			if(menuSelectorTween != null) {
				menuSelectorTween.cancel();
				menuSelectorTween = null;
			}
			var barY:Float = MENU_Y - 3 + (curSelected * MENU_LINE_GAP * 1.3);
			if(menuSelector.y != barY)
				menuSelectorTween = FlxTween.tween(menuSelector, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
		}

		missingText.visible = false;
		missingTextBG.visible = false;

		callUIScripts('onChangeSelection', [curSelected, menuItems[curSelected]]);
	}

	// ===== 本局数据（右侧面板，内容变化才重绘） =====
	function updateStats()
	{
		if (PlayState.instance == null || statTexts.length < 1) return;

		var st:PlayState = PlayState.instance;
		// 轻量签名先行（见字段注释）：秒数与百分比按**显示口径**取整比较，
		// 否则与文本节拍对不上导致永远"变化"。未变 → 零分配返回。
		var sigSec:Int = (Conductor.songPosition > 0) ? Std.int(Conductor.songPosition / 1000) : 0;
		var sigPct:Int = Std.int(CoolUtil.floorDecimal(st.ratingPercent * 100, 2));
		var sigMLen:Int = (FlxG.sound.music != null) ? Std.int(FlxG.sound.music.length) : -1;
		if (st.songScore == _sigScore && st.songMisses == _sigMisses && st.combo == _sigCombo
			&& st.ratingName == _sigRatingName && st.ratingFC == _sigFC && sigPct == _sigPct
			&& st.songHits == _sigHits && st.totalNotes == _sigTotal
			&& sigSec == _sigSec && sigMLen == _sigMLen)
			return;
		_sigScore = st.songScore; _sigMisses = st.songMisses; _sigCombo = st.combo;
		_sigRatingName = st.ratingName; _sigFC = st.ratingFC; _sigPct = sigPct;
		_sigHits = st.songHits; _sigTotal = st.totalNotes; _sigSec = sigSec; _sigMLen = sigMLen;

		var totalT:String = (FlxG.sound.music != null) ? FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false) : '--:--';
		var vals:Array<String> = [
			FlxStringUtil.formatMoney(st.songScore),
			Std.string(st.songMisses),
			Std.string(st.combo),
			st.ratingName + fcText(st.ratingFC),
			CoolUtil.floorDecimal(st.ratingPercent * 100, 2) + '%',
			Std.string(st.songHits) + ' / ' + Std.string(st.totalNotes),
			FlxStringUtil.formatTime(Math.max(0, Math.floor(Conductor.songPosition / 1000)), false) + ' / ' + totalT
		];

		for (i in 0...statTexts.length)
		{
			if (statLast[i] != vals[i])
			{
				statLast[i] = vals[i];
				statTexts[i].text = vals[i];
				statTexts[i].updateHitbox();
			}
		}
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

	/** 难度名 → 显示文本（'Easy'/'Normal'/'Hard' 走语言包，其余原样） */
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
	 * 菜单内部 ID → 显示文本。**多语言的唯一翻译点**（regenMenu 唯一消费方）。
	 * 难度档位不是 ID 而是原始难度名，故先试 ID 表、未命中再走难度翻译。
	 */
	function displayLabel(id:String):String
	{
		switch (id)
		{
			case ID_RESUME: return Lang.t('pause.resume');
			case ID_RESTART: return Lang.t('pause.restart');
			case ID_SKIP: return Lang.t('pause.skipTime');
			case ID_DIFFICULTY: return Lang.t('pause.changeDifficulty');
			case ID_SCRIPTS: return Lang.t('pause.scriptManager');
			case ID_GAMEPLAY: return Lang.t('pause.gameplaySettings');
			case ID_OPTIONS: return Lang.t('pause.options');
			case ID_EXIT: return Lang.t('pause.exitToMenu');
			case ID_EXIT_CHARTING: return Lang.t('pause.exitCharting');
			case ID_END_SONG: return Lang.t('pause.endSong');
			case ID_BACK: return Lang.t('common.back');
		}
		return translateDifficulty(id);
	}

	function regenMenu(?animate:Bool = false):Void {
		// 行距是实例字段（可能被 new() 的溢出兜底压缩过），重建列表前先恢复默认，
		// 否则从「11 项」切回「4 项」时会继承上一次压缩出来的窄行距。
		MENU_LINE_GAP = MENU_LINE_GAP_DEFAULT;

		for (i in 0...grpMenuShit.members.length) {
			var obj = grpMenuShit.members[0];
			obj.kill();
			grpMenuShit.remove(obj, true);
			obj.destroy();
		}

		for (i in 0...menuItems.length) {
			// 静态列表：选项固定在各自位置，切换时只改变高亮，不做整列滚动
			var item = new MenuText(MENU_X, MENU_Y + (i * MENU_LINE_GAP * 1.3), displayLabel(menuItems[i]), true, 34);
			item.isMenuItem = false;
			item.ID = i;
			grpMenuShit.add(item);

			// 菜单项此前**完全没有入场动画**（面板与文本都在淡入，它却直接闪现，
			// 视觉上像掉进界面里）。这里补上：与菜单面板同一方向、逐项错峰，
			// 且必须排在面板之后。只在首次打开（new()）与切换难度列表时播；
			// 从子页返回时列表内容没变，重播会显得啰嗦，所以那边不传 animate。
			//
			// 终态 alpha 必须按「是否选中」给（1 / 0.6），color 同理 ——
			// 否则动画结束后未选中项会比选中项还亮，而 `changeSelection` 只在
			// 下次切换选中时才跑，不会来纠正。
			if (animate)
			{
				var isSel:Bool = (i == curSelected);
				item.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
				flyIn(item, FLY_LEFT, 0.24 + FLY_STAGGER * i, isSel ? 1 : 0.6);
			}

			if(menuItems[i] == ID_SKIP)
			{
				skipTimeText = new FlxText(0, 0, 0, '', 44);
				skipTimeText.setFormat(Paths.font("future.ttf"), 44, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				skipTimeText.scrollFactor.set();
				skipTimeText.borderSize = 2;
				skipTimeTracker = item;
				add(skipTimeText);

				updateSkipTextStuff();
				updateSkipTimeText();
			}
		}
		curSelected = 0;
		changeSelection();
	}

	function updateSkipTextStuff()
	{
		if(skipTimeText == null || skipTimeTracker == null) return;

		skipTimeText.x = skipTimeTracker.x + skipTimeTracker.width + 40;
		skipTimeText.y = skipTimeTracker.y;
		skipTimeText.visible = (skipTimeTracker.alpha >= 1);

		// 双保险：即使菜单项变宽，也绝不超出安全右缘
		if(skipTimeText.x + skipTimeText.width > SAFE_RIGHT)
			skipTimeText.x = SAFE_RIGHT - skipTimeText.width;
	}

	function updateSkipTimeText()
	{
		skipTimeText.text = FlxStringUtil.formatTime(Math.max(0, Math.floor(curTime / 1000)), false) + ' / ' + FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
	}
}
