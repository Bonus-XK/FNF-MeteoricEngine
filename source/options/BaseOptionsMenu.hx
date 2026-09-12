package options;
import backend.WheelScroll;

import objects.BackButton;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;
import states.PlayState;

class BaseOptionsMenu extends MusicBeatSubstate
{
	var wheelScroll:WheelScroll = new WheelScroll(); // 滚轮限速（Freeplay 同款）
	// ===== 布局常量 =====
	static final PANEL_L_X:Float = 40;
	static final PANEL_L_Y:Float = 70;
	static final PANEL_L_W:Float = 680;
	static final PANEL_L_H:Float = 570;

	static final PANEL_R_X:Float = 740;
	static final PANEL_R_Y:Float = 70;
	static final PANEL_R_W:Float = 460;
	static final PANEL_R_H:Float = 570;

	static final LIST_X:Float = 108;     // 选项名称 X
	static final LIST_Y:Float = 152;     // 第一行 Y
	static final ROW_GAP:Float = 56;     // 行距
	static final ROWS_VISIBLE:Int = 8;   // 可见行数

	static final CHECK_X:Float = 56;     // 复选框 X
	static final CHECK_SIZE:Float = 26;
	static final VALUE_X:Float = 420;    // 值文字 X
	static final VALUE_W:Float = 240;    // 值文字宽度（右对齐）

	private var optionsArray:Array<Option>;
	private var curSelected:Int = 0;
	var curOption:Option = null;

	var rows:Array<FlxText> = [];
	var checkBgs:Array<FlxSprite> = [];
	var checkFills:Array<FlxSprite> = [];
	var valueTexts:Array<FlxText> = [];
	var lastRowText:Array<String> = [];
	var lastValueText:Array<String> = [];
	var lastIsBool:Array<Bool> = [];

	var descText:FlxText;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var backBtn:BackButton;
	/** menuDesat 背景精灵（主题色切换时刷新 tint；暂停内嵌路径为纯黑遮罩，不参与主题化） */
	var bgSprite:FlxSprite = null;
	/** 主题色色块选择器（子类调 setupThemeSwatches() 启用；鼠标/触控直接点色块换色） */
	var themeSwatches:objects.ColorSwatchPicker = null;
	var swatchBar:FlxSprite = null;
	/** 色块区几何常量（**右面板**内，位于选项说明文字下方的空白区；见 meteoric-system） */
	static final SWATCH_BAR_H:Float = 34;    // 色块区底板高度
	static final SWATCH_BAR_PAD:Float = 14;  // 底板与右面板左右内边距
	static final SWATCH_BOTTOM_GAP:Float = 4; // 底板距右面板底边的留白
	/** 防止移动端"按下 + 抬起"两次触发色块（桌面 justPressed 只有一次按下帧，不受影响） */
	var _handleSwatchClick:Bool = true;
	/** 色块精灵是否已 add 进 group（构造期不能 add，见 ensureThemeSwatchesAdded 注释） */
	var _themeSwatchSpritesReady:Bool = false;
	/** 是否已尝试过挂载（挂载只在首个 update 帧做一次，避免每帧重复 add） */
	var _themeSwatchTried:Bool = false;
	/** 子类是否请求启用色块区（由 setupThemeSwatches 登记；真正的创建在构造之后） */
	var _themeSwatchesWanted:Bool = false;
	var diffLeftBtn:FlxSprite;  // 移动端 ◀ 调节按钮
	var diffRightBtn:FlxSprite; // 移动端 ▶ 调节按钮
	var menuPad:objects.MobileControls; // 移动端菜单 pad（右下角 A 确认键，等效 Enter）
	var lastPadBtnTap:Int = 0;  // 移动端 ◀▶ 按钮点击冷却（防一次按下触发两次）

	var scrollIndex:Int = 0;
	var mouseActive:Bool = true;   // 键盘操作后冻结，鼠标移动/滚轮/点击恢复
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var holdTime:Float = 0;
	var holdValue:Float = 0;
	// 移动端 ◀▶ 长按连续调节状态（与键盘按住逻辑同参数，触摸独立计时）
	static final PAD_HOLD_DELAY:Float = 0.5;   // 长按初始延迟（秒）
	static final PAD_STRING_STEP:Float = 0.2;  // 字符串档位长按步进间隔（约 5 档/秒）
	var padHoldDir:Int = 0;       // -1 左 / 1 右 / 0 无
	var padHoldTime:Float = 0;    // 长按已持续时长
	var padHoldValue:Float = 0;   // 数字类长按累计值（独立于键盘 holdValue）
	var padStepTimer:Float = 0;   // 字符串类长按步进计时
	var nextAccept:Int = 5;        // 进入界面先忽略确认键，防误触
	var timeForMoving:Float = 0.1; // 进入子状态先忽略输入，防控制器误触

	public var title:String;
	public var rpcTitle:String;

	public function new()
	{
		super();

		if (title == null) title = '设置';
		if (rpcTitle == null) rpcTitle = '设置菜单';

		#if desktop
		DiscordClient.changePresence(rpcTitle, null);
		#end

		var bg:FlxSprite;
		// 判定"暂停内嵌"：以游戏暂停状态为权威信号（无标志位/无相机时序依赖）。
		// 暂停菜单打开时 PlayState.instance.paused == true（设置列表/子页都在暂停堆栈内）；
		// 主菜单路径：PlayState.instance 为 null（对局已销毁）或在游玩中（paused==false）。
		// 相机检测作为附加信号保留（仅在两者同时为真时走暗化，绝不误伤主菜单）
		var isInPause:Bool = PlayState.instance != null && PlayState.instance.paused;
		var camIsPause:Bool = (PlayState.instance != null && PlayState.instance.camOther != null
			&& cameras != null && cameras.length > 0 && cameras[0] == PlayState.instance.camOther);
		if (isInPause || camIsPause)
		{
			// 暂停内嵌：暗化覆盖（不再整屏 menuDesat，避免"跳转到新界面"的视觉）
			bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
			bg.alpha = 0.6;
		}
		else
		{
			bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
			bg.color = DesignTokens.menuTint;
			bg.screenCenter();
			bg.antialiasing = ClientPrefs.data.antialiasing;
		}
		bgSprite = bg;
		add(bg);

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(120, 662, 1040, 48, 14));

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(LIST_X, 100, 0, title, 30);
		titleText.setFormat(Paths.font('future.ttf'), 30, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		titleText.scrollFactor.set();
		add(titleText);

		var rightTitle:FlxText = new FlxText(PANEL_R_X + 32, 100, 0, '选项说明', 26);
		rightTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rightTitle.borderSize = 2;
		rightTitle.scrollFactor.set();
		add(rightTitle);

		// ---- 列表行（静态行，选中高亮条移动） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = new FlxText(LIST_X, LIST_Y + (r * ROW_GAP), 0, '', 26);
			row.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.scrollFactor.set();
			row.visible = false;
			add(row);
			rows.push(row);

			var checkBg:FlxSprite = makePanel(CHECK_X, LIST_Y + 4 + (r * ROW_GAP), CHECK_SIZE, CHECK_SIZE, 7, 0x66161622, 0x8CFFFFFF);
			checkBg.visible = false;
			add(checkBg);
			checkBgs.push(checkBg);

			var checkFill:FlxSprite = makePanel(CHECK_X + 6, LIST_Y + 10 + (r * ROW_GAP), CHECK_SIZE - 12, CHECK_SIZE - 12, 4, 0xFFFFFFFF, null);
			checkFill.visible = false;
			add(checkFill);
			checkFills.push(checkFill);

			var valueText:FlxText = new FlxText(VALUE_X, LIST_Y + 2 + (r * ROW_GAP), VALUE_W, '', 24);
			valueText.setFormat(Paths.font('future.ttf'), 24, 0xFFD7D7E0, RIGHT);
			// FlxText 默认 wordWrap = true，固定宽度 240 下长值会折行压到相邻行（实测：Score 栏格式）。
			// 强制单行：过长部分被 fieldWidth 裁掉，配合 Option.valueHint 给「点击查看」入口。
			valueText.wordWrap = false;
			valueText.scrollFactor.set();
			valueText.visible = false;
			add(valueText);
			valueTexts.push(valueText);

			lastRowText.push('');
			lastValueText.push('');
			lastIsBool.push(false);
		}

		selectorBar = makePanel(LIST_X - 24, LIST_Y - 3, VALUE_X + VALUE_W - (LIST_X - 24), 44, 12, DesignTokens.rowHighlight, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 右侧：描述 ----
		descText = new FlxText(PANEL_R_X + 30, 170, PANEL_R_W - 60, '', 24);
		descText.setFormat(Paths.font("future.ttf"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.borderSize = 2;
		descText.scrollFactor.set();
		add(descText);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(300, 672, 680, '滚轮 / 方向键 选择 · 左/右 调整数值 · Enter 切换 · R 重置 · 点击 < 返回', 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		#if mobile
		// ---- 移动端 ◀ ▶ 调节按钮（等效左右方向键，修改当前选项值）----
		diffLeftBtn = objects.MobileControls.makePadSprite('left', 0xFFFFFFFF);
		diffLeftBtn.setGraphicSize(110, 106);
		diffLeftBtn.updateHitbox();
		diffLeftBtn.x = 20;
		diffLeftBtn.y = FlxG.height - diffLeftBtn.height - 12;
		add(diffLeftBtn);

		diffRightBtn = objects.MobileControls.makePadSprite('right', 0xFFFFFFFF);
		diffRightBtn.setGraphicSize(110, 106);
		diffRightBtn.updateHitbox();
		diffRightBtn.x = 20 + diffLeftBtn.width + 8;
		diffRightBtn.y = FlxG.height - diffRightBtn.height - 12;
		add(diffRightBtn);

		// 右下角 A 确认键：复用暂停界面同一套逻辑（menuMode pad，不注册为全局 instance）
		menuPad = new objects.MobileControls(false, FlxG.camera, -1, true);
		add(menuPad);
		#end

		changeSelection();
		FlxG.mouse.visible = true;
	}

	public function addOption(option:Option) {
		if (optionsArray == null || optionsArray.length < 1) optionsArray = [];
		optionsArray.push(option);
	}

	// ===== 列表刷新 =====
	function refreshRows()
	{
		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:FlxText = rows[r];

			if (idx >= optionsArray.length)
			{
				row.visible = false;
				checkBgs[r].visible = false;
				checkFills[r].visible = false;
				valueTexts[r].visible = false;
				continue;
			}

			var option:Option = optionsArray[idx];
			var isBool:Bool = (option.type == 'bool');
			var isSel:Bool = (idx == curSelected);

			row.visible = true;
			if (lastRowText[r] != option.name)
			{
				lastRowText[r] = option.name;
				row.text = option.name;
				row.updateHitbox();
			}
			row.alpha = isSel ? 1 : 0.78;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;

			checkBgs[r].visible = isBool;
			checkBgs[r].alpha = isSel ? 1 : 0.85;
			checkFills[r].visible = isBool && (option.getValue() == true);

			valueTexts[r].visible = !isBool;
			if (!isBool)
			{
				var v:String = formatValue(option);
				if (lastValueText[r] != v)
				{
					lastValueText[r] = v;
					var valueText:FlxText = valueTexts[r];
					valueText.text = v;
					valueText.updateHitbox();
				}
				valueTexts[r].alpha = isSel ? 1 : 0.8;
				valueTexts[r].color = isSel ? FlxColor.WHITE : 0xFFD7D7E0;
			}
		}

		// 选中行高亮条
		var barY:Float = LIST_Y - 3 + ((curSelected - scrollIndex) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

	function formatValue(option:Option):String
	{
		var text:String = option.displayFormat;
		// 值过长时只显示固定提示（如「点击查看」），避免长串折行压到相邻行
		// （放在取值之前：提示显示不需要读存档，省一次反射）
		if (option != null && option.valueHint != null) return option.valueHint;

		var val:Dynamic = option.getValue();
		// 选项自带显示格式化器时优先使用（声明式：不靠选项名做字符串嗅探）
		if (option != null && option.displayFormatter != null)
		{
			return option.displayFormatter(val);
		}
		// string 类型带 displayOptions 时：按存储值索引显示名（如英文存储值 → 中文显示），不写回存储
		if (option.type == 'string' && option.displayOptions != null)
		{
			var idx:Int = (option.options != null) ? option.options.indexOf(Std.string(val)) : -1;
			if (idx >= 0 && idx < option.displayOptions.length)
				val = option.displayOptions[idx];
		}
		if (option.type == 'percent') val *= 100;
		var def:Dynamic = option.defaultValue;
		return text.replace('%v', Std.string(val)).replace('%d', Std.string(def));
	}

	function updateTextFrom(option:Option) {
		refreshRows();
	}

	/**
	 * 主题色切换后的即时刷新（Options 内实时预览）。
	 * 规则（meteoric-design / meteoric-system）：
	 *  - 只刷新**强调整块**（menuDesat 背景 tint）与值文字，不动面板/尺寸、不做全局重绘、不 tween；
	 *  - 其余界面在下次 create() 时读取新令牌，无需在此处遍历整个游戏。
	 * @param index 目标色板索引；**必须显式传入**，不要依赖 curOption
	 *              （curOption 是当前选中行，可能是任意选项，隐式取值会误套用别的选项的值）
	 */
	public function refreshThemeVisuals(?index:Null<Int>):Void
	{
		DesignTokens.applyTheme(index, false, true);

		if (bgSprite != null)
			bgSprite.color = DesignTokens.menuTint;

		refreshSwatches();
		refreshRows();
	}

	// ===== 主题色色块区（可选挂载）=====

	/**
	 * 启用「点色块换主题色」。
	 * 由子类在 super() **之后**调用（addOption 之后）；不调用则本菜单不出现色块区（默认关闭，零副作用）。
	 *
	 * ⚠⚠ 必须在 super() 之后：hxcpp 把实例字段初始化器放在**基类构造**里执行，
	 * super() 之前对实例字段的任何赋值（含本类的 _themeSwatchesWanted）都会被重置回初始值，
	 * 表现为「明明调用了却毫无效果」（2026-09-11 两次实测事故）。
	 * 组件本身不碰存档/Audio，点的语义完全复用选项行的 changeOptionValue(1) 路径 ——
	 * 保证键盘、鼠标、触控三套输入走**同一条**取值与音效链路，不会出现两套行为。
	 */
	public function setupThemeSwatches():Void
	{
		// ⚠ 这里**不能**创建 ColorSwatchPicker，也不能 add —— 见 ensureThemeSwatchesAdded 的说明：
		// hxcpp 把实例字段初始化器放在**基类构造**里执行，子类在 super() 之前的任何字段赋值
		// 都会被 super::__construct() 重跑初始化而**清成 null**（2026-09-11 实测事故）。
		// 因此本方法只登记意图；真正的创建 + 挂载都在构造完成之后（create()/首帧）。
		_themeSwatchesWanted = true;
	}
	/**
	 * 显式挂载入口：子类在 super() 之后立刻调用一次（构造已完成，group 的 members 就绪），
	 * 这是**确定可验证**的路径；create() 与首个 update 帧各有一道兜底。
	 */
	public function ensureThemeSwatchesAdded():Void
	{
		if (!_themeSwatchesWanted || _themeSwatchSpritesReady) return;
		if (findThemeColorOption() == null) return;

		// 创建与挂载都必须在**构造完成之后**（create()/super() 之后），
		// 否则字段会被基类构造里的初始化器清成 null。
		if (themeSwatches == null)
		{
			themeSwatches = new objects.ColorSwatchPicker(swatchRowStartX(), swatchBarY() + SWATCH_BAR_H / 2, DesignTokens.primaryPalette());
			themeSwatches.onClick = onSwatchClicked;
			themeSwatches.selectedIndex = DesignTokens.themeIndex;
		}
		themeSwatches.registerThemeListener(); // 脚本 setThemeColor 后选中环立即跟上

		// 底板：与 selectorBar 同款令牌（outline 风格），表示「这一排是可点的」
		swatchBar = makePanel(PANEL_R_X + SWATCH_BAR_PAD, swatchBarY(), PANEL_R_W - SWATCH_BAR_PAD * 2, SWATCH_BAR_H, 12, DesignTokens.rowHover, DesignTokens.panelOutline);
		add(swatchBar);

		for (spr in themeSwatches.sprites)
			add(spr);

		_themeSwatchSpritesReady = true;
		refreshSwatches();
	}

	override function create()
	{
		// openSubState() calls create() after construction, so the group members array is ready
		ensureThemeSwatchesAdded();
		super.create();
	}

	/**
	 * 色块区几何（右面板内一行 10 格）。
	 * ⚠ 必须减**整行宽度**（totalWidth = 直径 + (n-1)×步进），不能只减单个色块直径 ——
	 * 只减直径会让整行右移 (n-1)×步进/2，实测曾冲到右面板右侧之外。
	 * 右面板宽 460，可用宽 = 460 - 2×14 = 432；10 格一行占用 32 + 9×44 = 428 → 恰好放得下。
	 * 尺寸选择依据：32/44 是唯一同时满足「整行在面板内」与「触摸热区 ≥56」的组合。
	 */
	function swatchRowStartX():Float
	{
		var rowW:Float = objects.ColorSwatchPicker.SWATCH_DIAMETER
			+ (DesignTokens.THEME_COUNT - 1) * objects.ColorSwatchPicker.SWATCH_STEP;
		var barLeft:Float = PANEL_R_X + SWATCH_BAR_PAD;
		var barW:Float = PANEL_R_W - SWATCH_BAR_PAD * 2;
		return barLeft + (barW - rowW) / 2 + objects.ColorSwatchPicker.SWATCH_DIAMETER / 2;
	}

	/** 色块区底板 Y（贴右面板底部内侧） */
	function swatchBarY():Float
	{
		return PANEL_R_Y + PANEL_R_H - SWATCH_BAR_H - SWATCH_BOTTOM_GAP;
	}

	/** 定位"主题色"选项行（按选项名；配色/名称改动只影响这一处） */
	function findThemeColorOption():Option
	{
		if (optionsArray == null) return null;
		for (o in optionsArray)
		{
			if (o != null && Std.string(o.name).indexOf('主题色') == 0) return o;
		}
		return null;
	}

	/** 色块选中态与键盘焦点：主题色行被选中时点亮主题色环，其余时候保持"当前档位"白环 */
	function refreshSwatches():Void
	{
		if (themeSwatches == null) return;
		themeSwatches.selectedIndex = DesignTokens.themeIndex;
		var o:Option = findThemeColorOption();
		var isThemeRow:Bool = (o != null && curOption == o);
		themeSwatches.interactive = isThemeRow;
		themeSwatches.keyboardFocus = isThemeRow;
		// 只在这一行被选中时显示整块色板：之前只降到 alpha 0.45，切到别的选项后仍占着右面板下段，
		// 既与说明文字（descText 自 y=170 向下延伸、无裁剪）打架，也让人误以为还能点（实测反馈）。
		themeSwatches.setVisible(isThemeRow);
		if (swatchBar != null) swatchBar.visible = isThemeRow;
	}

	/** 色块点击 → 复用选项行的调节路径（含存档 + scrollMenu 音效 + onChange → 即时换色） */
	function onSwatchClicked(index:Int):Void
	{
		if (!_handleSwatchClick) return; // 移动端：点击语义在 tap 抬起（clickPressed）通道，避免"按下+抬起"双触发
		_handleSwatchClick = false;

		var o:Option = findThemeColorOption();
		if (o == null) return;

		if (curOption != o) changeSelection(optionsArray.indexOf(o) - curSelected);
		// ⚠ 必须**一次点到目标格**，不能走 changeOptionValue(±1)：
		// changeOptionValue 每次只挪一格，跨格点击（如从第 0 格点第 5 格）只会移动一步 → 点不到（实测 bug）。
		// getValue() 走 Reflect.getProperty → Dynamic，故这里显式取整。
		var cur:Int = Std.int(o.getValue());
		if (index == cur) return; // 点的是当前档位：不重复播放音效、不重复存档

		o.setValue(index);
		updateTextFrom(o);   // 刷新值文字（跨格也直接显示目标色板名）
		o.change();          // onChange → applyThemeSelection → 即时换色 + 存档
		FlxG.sound.play(Paths.sound('scrollMenu')); // 与键盘调节一致：一次点击一次反馈音
		refreshSwatches();   // 选中环跟随
	}
	function changeOptionValue(dir:Int = 1)
	{
		var add:Dynamic = null;
		if (curOption.type != 'string') {
			add = (dir < 0) ? -curOption.changeValue : curOption.changeValue;
		}

		switch (curOption.type)
		{
			case 'int' | 'float' | 'percent':
				holdValue = curOption.getValue() + add;
				if (holdValue < curOption.minValue) holdValue = curOption.minValue;
				else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;

				switch (curOption.type)
				{
					case 'int':
						holdValue = Math.round(holdValue);
						curOption.setValue(holdValue);

					case 'float' | 'percent':
						holdValue = FlxMath.roundDecimal(holdValue, curOption.decimals);
						curOption.setValue(holdValue);
				}

			case 'string':
				var num:Int = curOption.curOption;
				num += dir;

				if (num < 0) {
					num = curOption.options.length - 1;
				} else if (num >= curOption.options.length) {
					num = 0;
				}

				curOption.curOption = num;
				curOption.setValue(curOption.options[num]);
		}
		updateTextFrom(curOption);
		curOption.change();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	// ===== 主循环 =====
	override function update(elapsed:Float)
	{
		updatePadBtnVisuals();
		if (timeForMoving > 0)
		{
			timeForMoving = Math.max(0, timeForMoving - elapsed);
			super.update(elapsed);
			return;
		}

		if (controls.UI_UP_P)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			holdTime = 0; // 每次新按下都重新计时，避免连按时累积出"突然加速"
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			holdTime = 0;
			changeSelection(1);
		}
		if (controls.UI_UP_R || controls.UI_DOWN_R)
			holdTime = 0;

		if (controls.UI_DOWN || controls.UI_UP)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
			holdTime += elapsed;
			var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);
			if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
				changeSelection(Std.int(Math.min(checkNewHold - checkLastHold, 1)) * (controls.UI_UP ? -1 : 1)); // 单帧最多移动 1 行，防止卡顿帧跳变
		}

		// 色块挂载兜底：若 create() 未被触发（不同 flixel/引擎流程差异），在首个 update 帧补挂一次。
		// 用 _themeSwatchTried 保证只尝试一次，不构成每帧开销。
		if (!_themeSwatchTried)
		{
			_themeSwatchTried = true;
			ensureThemeSwatchesAdded();
		}

		// 鼠标
		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		// 触屏：手指抬起且未滑动才算点击，拖动滚动列表时不误选
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

		if (themeSwatches != null)
		{
			// 色块演出（悬停放大不改变选中 / 按压缩放 / clickPressed 通道触发点击）
			themeSwatches.update(FlxG.mouse.screenX, FlxG.mouse.screenY, clickPressed && _handleSwatchClick);
			_handleSwatchClick = true;
		}

		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
		}

		var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);

		if (wheelStep != 0)
		{
			mouseActive = true;
			changeSelection(wheelStep);
		}

		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			mouseActive = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			super.update(elapsed);
			return;
		}

		if (clickPressed)
		{
			// ---- 主题色色块优先于选项行判定：色块区在列表下方，但圆形热区与行区域无交集时也必须先判，
			//      否则将来布局调整一旦重叠，点色块会被行点击吞掉（先判即免疫）。----
			if (themeSwatches != null)
			{
				var swatchHit:Int = themeSwatches.hitTest(FlxG.mouse.screenX, FlxG.mouse.screenY);
				if (swatchHit >= 0)
				{
					mouseActive = true;
					onSwatchClicked(swatchHit);
					#if !mobile
					_handleSwatchClick = false; // 桌面：本帧已处理，压住 update 里的抬起通道，避免二次触发
					#end
					super.update(elapsed);
					return;
				}
			}

			// 移动端 ◀▶ 的按下/长按统一在下方 #if mobile 块处理（按下即生效 + 0.5s 后连续重复）；
			// 此处的 release 路径不再处理 ◀▶，避免长按松手后重复触发。
			#if !mobile
			// 桌面：点击复选框/选项行 = 选中/切换数值（与 Psych 原版一致）。
			// 手机不启用：触屏拖动手势的释放帧易被误判为点击，改为「拖动选中 + A/◀▶ 确认调整」。
			var checkboxHit:Int = getHoveredCheckbox();
			if (checkboxHit >= 0)
			{
				mouseActive = true;
				if (checkboxHit != curSelected) changeSelection(checkboxHit - curSelected);
				toggleSelected();
			}
			else
			{
				var hoveredID:Int = getHoveredOptionID();
				if (hoveredID >= 0)
				{
					mouseActive = true;
					if (hoveredID != curSelected)
					{
						changeSelection(hoveredID - curSelected);
						holdTime = 0;
					}
					else
					{
						if (curOption.type == 'bool')
							toggleSelected();
						else if (curOption.type != 'key')
							changeOptionValue(1);
					}
				}
			}
			#end
		}

		#if mobile
		// ---- 移动端 ◀ ▶ 长按连续调节（按下即生效；按住 0.5s 后按键盘同参数自动重复）----
		var padHitLeft:Bool = padBtnHit(diffLeftBtn);
		var padHitRight:Bool = padBtnHit(diffRightBtn);
		if (FlxG.mouse.justPressed && padHoldDir == 0 && Lib.getTimer() - lastPadBtnTap > 300)
		{
			var dir:Int = padHitLeft ? -1 : (padHitRight ? 1 : 0);
			if (dir != 0)
			{
				lastPadBtnTap = Lib.getTimer();
				mouseActive = true;
				padHoldDir = dir;
				padHoldTime = 0;
				padStepTimer = 0;
				if (curOption == null || curOption.type == 'key')
					padHoldDir = 0; // key 类不可调
				else
				{
					if (curOption.type == 'bool')
						toggleSelected();       // 开关：仅点按切换，不参与长按重复
					else
						changeOptionValue(dir); // 数字/字符串：按下立即生效（与键盘 key-down 一致）
					if (curOption.type != 'string')
						padHoldValue = curOption.getValue();
				}
			}
		}

		if (padHoldDir != 0)
		{
			var hit:Bool = (padHoldDir < 0) ? padHitLeft : padHitRight;
			if (FlxG.mouse.pressed && hit)
			{
				padHoldTime += elapsed;
				if (padHoldTime > PAD_HOLD_DELAY && curOption != null)
				{
					switch (curOption.type)
					{
						case 'int' | 'float' | 'percent':
							padHoldValue += curOption.scrollSpeed * elapsed * padHoldDir;
							if (padHoldValue < curOption.minValue) padHoldValue = curOption.minValue;
							else if (padHoldValue > curOption.maxValue) padHoldValue = curOption.maxValue;
							switch (curOption.type)
							{
								case 'int':
									curOption.setValue(Math.round(padHoldValue));
								case 'float' | 'percent':
									curOption.setValue(FlxMath.roundDecimal(padHoldValue, curOption.decimals));
							}
							updateTextFrom(curOption);
							curOption.change();
							// 与键盘按住路径一致：数字连续滚动不逐帧播 scrollMenu

						case 'string':
							padStepTimer += elapsed;
							while (padStepTimer >= PAD_STRING_STEP)
							{
								padStepTimer -= PAD_STRING_STEP;
								changeOptionValue(padHoldDir); // 每 0.2s 切一档（含 scrollMenu 反馈）
							}

						default: // bool / key：不重复
					}
				}
			}
			else
				clearPadHold();
		}
		else if (FlxG.mouse.justReleased)
			clearPadHold();
		#end

		if (controls.BACK) {
			close();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}

		if (nextAccept <= 0)
		{
			var usesCheckbox:Bool = (curOption.type == 'bool');

			if (usesCheckbox)
			{
				var acceptNow:Bool = controls.ACCEPT;
				#if mobile
				// A 确认键映射为 Enter：FlxG.mouse 通道命中右下角 A 键 zone（300ms 冷却防双触发）。
				// instance 的触摸路径（controls.ACCEPT）触发时也会在下方更新 lastPadBtnTap，互斥生效。
				if (!acceptNow && Lib.getTimer() - lastPadBtnTap > 300)
				{
					var aZone:FlxSprite = (menuPad != null && menuPad.padButtons.exists('accept') && menuPad.padButtons.get('accept').length > 0)
						? menuPad.padButtons.get('accept')[0] : null;
					if (aZone != null && FlxG.mouse.justReleased && !Main.touchWasDragging()
						&& FlxG.mouse.screenX >= aZone.x && FlxG.mouse.screenX <= aZone.x + aZone.width
						&& FlxG.mouse.screenY >= aZone.y && FlxG.mouse.screenY <= aZone.y + aZone.height)
					{
						acceptNow = true;
					}
				}
				#end
				if (acceptNow)
				{
					#if mobile
					// 无论键盘 Enter / instance 触摸 / FlxG.mouse 兜底，触发后都计入冷却，防止按下+松开双触发
					lastPadBtnTap = Lib.getTimer();
					#end
					toggleSelected();
				}
			}
			else
			{
				// 非 bool 选项：string 类型且带 onChange（如自定义 Score 栏格式）按确认键也触发弹窗/回调
				if (controls.ACCEPT && curOption.type == 'string' && curOption.onChange != null)
				{
					curOption.change();
				}
				if (controls.UI_LEFT || controls.UI_RIGHT) {
					var pressed:Bool = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
					#if mobile
					if (pressed) lastPadBtnTap = Lib.getTimer(); // instance 路径（dpad）触发也计入冷却，防双触发
					#end
					if (pressed) holdTime = 0; // 左右键调数值也独立计时，不与上下键互相污染
					if (holdTime > 0.5 || pressed) {
						if (pressed) {
							changeOptionValue(controls.UI_LEFT ? -1 : 1);
						} else if (curOption.type != 'string') {
							holdValue += curOption.scrollSpeed * elapsed * (controls.UI_LEFT ? -1 : 1);
							if (holdValue < curOption.minValue) holdValue = curOption.minValue;
							else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;

							switch (curOption.type)
							{
								case 'int':
									curOption.setValue(Math.round(holdValue));

								case 'float' | 'percent':
									curOption.setValue(FlxMath.roundDecimal(holdValue, curOption.decimals));
							}
							updateTextFrom(curOption);
							curOption.change();
							refreshSwatches(); // 键盘长按连续调节：色块选中环同步跟手
						}
					}

					if (curOption.type != 'string') {
						holdTime += elapsed;
					}
				} else if (controls.UI_LEFT_R || controls.UI_RIGHT_R) {
					clearHold();
				}
			}

			if (controls.RESET)
			{
				var leOption:Option = optionsArray[curSelected];
				leOption.setValue(leOption.defaultValue);
				if (leOption.type != 'bool')
				{
					if (leOption.type == 'string') leOption.curOption = leOption.options.indexOf(leOption.getValue());
					updateTextFrom(leOption);
				}
				leOption.change();
				FlxG.sound.play(Paths.sound('cancelMenu'));
				refreshSwatches(); // R 重置：色块选中环回到默认档
				refreshRows();
			}
		}
		else nextAccept--;

		super.update(elapsed);
	}

	function toggleSelected()
	{
		FlxG.sound.play(Paths.sound('scrollMenu'));
		curOption.setValue((curOption.getValue() == true) ? false : true);
		curOption.change();
		refreshRows();
	}

	/** 移动端 ◀ ▶ A 按钮按下动画：贴图第 3 帧为按下态（与游玩 pad 一致），
	 *  按住且指针在按钮内时切到按下帧，否则恢复普通帧 */
	function updatePadBtnVisuals():Void
	{
		#if mobile
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		var held:Bool = FlxG.mouse.pressed;

		if (diffLeftBtn != null)
		{
			var hit:Bool = held && mx >= diffLeftBtn.x && mx <= diffLeftBtn.x + diffLeftBtn.width
				&& my >= diffLeftBtn.y && my <= diffLeftBtn.y + diffLeftBtn.height;
			if (diffLeftBtn.frames != null && diffLeftBtn.frames.frames.length >= 3)
				diffLeftBtn.animation.frameIndex = hit ? 2 : 0;
			else
				diffLeftBtn.alpha = hit ? 1 : 0.75;
		}
		if (diffRightBtn != null)
		{
			var hit:Bool = held && mx >= diffRightBtn.x && mx <= diffRightBtn.x + diffRightBtn.width
				&& my >= diffRightBtn.y && my <= diffRightBtn.y + diffRightBtn.height;
			if (diffRightBtn.frames != null && diffRightBtn.frames.frames.length >= 3)
				diffRightBtn.animation.frameIndex = hit ? 2 : 0;
			else
				diffRightBtn.alpha = hit ? 1 : 0.75;
		}
		if (menuPad != null && menuPad.padButtons.exists('accept') && menuPad.padButtons.get('accept').length > 0)
		{
			var aZone:FlxSprite = menuPad.padButtons.get('accept')[0];
			var hit:Bool = held && mx >= aZone.x && mx <= aZone.x + aZone.width
				&& my >= aZone.y && my <= aZone.y + aZone.height;
			if (aZone.frames != null && aZone.frames.frames.length >= 3)
				aZone.animation.frameIndex = hit ? 2 : 0;
			else
				aZone.alpha = hit ? 1 : 0.75;
		}
		#end
	}

	#if mobile
	/** 移动端 ◀▶ 触摸命中判定（屏幕坐标，与 updatePadBtnVisuals 同一套） */
	function padBtnHit(btn:FlxSprite):Bool
	{
		if (btn == null) return false;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		return mx >= btn.x && mx <= btn.x + btn.width && my >= btn.y && my <= btn.y + btn.height;
	}

	/** 结束移动端 ◀▶ 长按状态（松手或滑出按钮） */
	function clearPadHold():Void
	{
		padHoldDir = 0;
		padHoldTime = 0;
		padStepTimer = 0;
		padHoldValue = 0;
	}
	#end

	function clearHold()
	{
		if (holdTime > 0.5) {
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		holdTime = 0;
	}

	// ===== 鼠标命中 =====
	function getHoveredOptionID():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = rows[r];
			if (!row.visible) continue;
			var idx:Int = scrollIndex + r;
			if (mx >= CHECK_X - 10 && mx <= VALUE_X + VALUE_W + 8 && my >= row.y - 8 && my <= row.y + 44)
				return idx;
		}
		return -1;
	}

	function getHoveredCheckbox():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...ROWS_VISIBLE)
		{
			var bg:FlxSprite = checkBgs[r];
			if (!bg.visible) continue;
			if (mx >= bg.x - 6 && mx <= bg.x + bg.width + 6 && my >= bg.y - 6 && my <= bg.y + bg.height + 6)
				return scrollIndex + r;
		}
		return -1;
	}

	// ===== 选中变化 =====
	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0)
			curSelected = optionsArray.length - 1;
		if (curSelected >= optionsArray.length)
			curSelected = 0;

		if (curSelected < scrollIndex)
			scrollIndex = curSelected;
		else if (curSelected > scrollIndex + ROWS_VISIBLE - 1)
			scrollIndex = curSelected - ROWS_VISIBLE + 1;

		if (curSelected >= 0 && curSelected < optionsArray.length)
		{
			descText.text = optionsArray[curSelected].description;
			descText.updateHitbox();
			curOption = optionsArray[curSelected];
		}

		refreshRows();
		refreshSwatches(); // 选中行变化 → 色块键盘焦点环/交互态跟着切
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	// ===== 工具 =====
	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是**编译期常量**，不能写 DesignTokens.panelFill（运行时求值会被 Haxe 拒绝），
		// 故默认传 null、在此解析 —— 同时保证取到的是「当前主题」的值，而不是类加载时的快照。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		// 摘掉静态监听：DesignTokens.themeListeners 是静态表，不摘除会留下对已销毁精灵的僵尸回调
		if (themeSwatches != null)
		{
			themeSwatches.destroy();
			themeSwatches = null;
		}
		super.destroy();
	}
}
