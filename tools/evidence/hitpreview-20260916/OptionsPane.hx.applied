package options;

import backend.WheelScroll;
import flixel.group.FlxGroup;
import objects.ColorSwatchPicker;

/**
 * 单界面设置的**内容区**：渲染当前分区（section）的选项行，并独占内容区的输入。
 *
 * 与存量 `BaseOptionsMenu` 的关系（重要）：
 *  - `BaseOptionsMenu` 仍是**暂停内嵌路径**（PauseSettingsSubstate → openCamSubState）的渲染器，本轮不动它；
 *  - 本类是新「单界面」路径的渲染器。两者共用 `Option`、`OptionValue`（显示/步进单点）与 `OptionsUi`（面板令牌），
 *    但**不共用布局常量**：BaseOptionsMenu 是「左 680 列表 + 右 460 说明」，本类只有一块 956 宽内容面板。
 *  - 分区的**选项定义与业务回调**来自 headless 的 `BaseOptionsMenu` 子类实例（见 BaseOptionsMenu.headless）：
 *    因此不存在"选项表被复制两份"的漂移风险。
 *
 * 契约（meteoric-system / meteoric-design）：
 *  - 绘制层级：面板 → 高亮条 → 行文字（`selectorBar` 必须在 rows 之前 add）；
 *  - 颜色一律走令牌；面板一次绘制，update() 零绘制；
 *  - 值文本 `wordWrap = false`（FlxText 默认 true，固定宽会折行压到相邻行 —— 实测事故）；
 *  - 色板**只在该行被选中时整块显示**（含底板），其余选项必须 `visible = false`，不能只降 alpha；
 *  - 复用的 tween 先 cancel；键盘/鼠标/触控三套输入都在本类内闭合。
 *
 * 几何（1280×720 基准，已核算）：
 *  内容面板 284,70,956,570（右缘 1240 ≤ 1240，底缘 640 ≤ 648）；
 *  标题 y 100；行首 y 152、行距 52、可见 8 行（末行文字底 ≈ 560）；
 *  复选框 x 314（26px，触控命中区另加 12px 内边距）；选项名 x 360；值列右对齐 914..1214；
 *  高亮条 928×44 圆角 12；底部信息条 y 578 高 54（说明行 / 主题色块区，二选一显示）。
 */
class OptionsPane extends FlxGroup
{
	// ===== 内容面板几何 =====
	public static final PANEL_X:Float = 284;
	public static final PANEL_Y:Float = 70;
	public static final PANEL_W:Float = 956;
	public static final PANEL_H:Float = 570;

	static final TITLE_X:Float = PANEL_X + 32;
	static final TITLE_Y:Float = PANEL_Y + 30;
	static final TITLE_W:Float = PANEL_W - 64;

	static final CHECK_X:Float = PANEL_X + 22;      // 开关列（96×32 胶囊，见 objects.ToggleSwitch）
	static final SWITCH_ROW_OFF:Float = 6;         // 开关在行内垂直偏移（行高 44 → 32 高居中偏上）
	static final NAME_X:Float = PANEL_X + 130;     // 选项名起点：开关右缘 306+96=402，再留 12 间距
	static final ROW_Y:Float = PANEL_Y + 82;          // 152
	static final ROW_GAP:Float = 52;
	static final ROWS_VISIBLE:Int = 8;
	/** 预览带（分区自带可视元素，如音符皮肤预览）的位置：6 行窗口（末行底 456）之下、说明条（578）之上 */
	static final PREVIEW_Y:Float = 464;
	static final PREVIEW_H:Float = 108;
	static final VALUE_W:Float = 300;
	static final VALUE_X:Float = PANEL_X + PANEL_W - 26 - VALUE_W;  // 914
	static final NAME_W:Float = VALUE_X - NAME_X - 14;              // 540

	static final BAR_X:Float = PANEL_X + 14;
	static final BAR_W:Float = PANEL_W - 28;
	static final BAR_H:Float = 44;

	static final STRIP_Y:Float = PANEL_Y + PANEL_H - 62;   // 578
	static final STRIP_H:Float = 54;
	static final DESC_X:Float = PANEL_X + 32;
	static final DESC_Y:Float = STRIP_Y + 16;
	static final DESC_W:Float = PANEL_W - 64;

	// ===== 输入节奏（与 BaseOptionsMenu / meteoric-mobile 同参数）=====
	static final PAD_HOLD_DELAY:Float = 0.5;   // 长按初始延迟（秒）
	static final PAD_STRING_STEP:Float = 0.2;  // 字符串档位长按步进间隔
	static final HOLD_DELAY:Float = 0.5;       // 键盘左右长按初始延迟

	/** 值变化后回调（宿主刷新主题视觉：menuDesat tint / 行文本 / 色板） */
	public var onValueChanged:Void->Void = null;
	/** 当前分区是「独立整屏页出口」时，确认打开 */
	public var onOpenExternal:Void->Void = null;
	/** 内容区被点击（宿主据此把键盘焦点从分区栏切到内容区，符合"点哪管哪"） */
	public var onContentClicked:Void->Void = null;

	var panel:FlxSprite;
	var titleText:FlxText;
	var descText:FlxText;

	var rows:Array<FlxText> = [];
	/** 布尔行的开关（与「更新界面」同款，见 objects.ToggleSwitch） */
	var switchCols:Array<objects.ToggleSwitch> = [];
	var valueTexts:Array<FlxText> = [];
	var lastRowText:Array<String> = [];
	var lastValueText:Array<String> = [];
	/** 行文字/值文字的"被压暗"状态（预览态用）：非预览时恢复 */
	var rowGroupDim:Bool = false;

	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

	// 分区（headless 的 BaseOptionsMenu 实例）与其选项表
	var section:BaseOptionsMenu = null;
	var options:Array<Option> = [];
	var isExternal:Bool = false;
	/** 画布分区：内容区让位给自带绝对布局的编辑器（按键设置 / 箭头配色），输入由画布自己吃 */
	var canvasMode:Bool = false;
	var currentCanvas:flixel.group.FlxGroup = null;
	/** 实际使用的选项行数（默认 8；带预览带的分区只用 6 行，见 setSection 的 previewRowCount） */
	var rowsVisible:Int = ROWS_VISIBLE;
	/** 分区自带的预览元素容器（音符皮肤预览等），定位在预览带里 */
	var previewGroup:flixel.group.FlxGroup = null;
	/** 已经摆放到预览带的容器（同一容器只摆一次，避免重复平移累加偏移） */
	var placedPreview:flixel.group.FlxGroup = null;
	/** 预览带当前实际范围（随本分区行窗口变化）：[ROW_Y + rowsVisible * ROW_GAP, STRIP_Y - 6]；
	 *  行窗口 6 行时 = 464..572，与既有常量 PREVIEW_Y / PREVIEW_H 完全一致；
	 *  分区把窗口缩到 2 行时 = 256..572（316px）——打击特效预览按实战尺寸显示需要这个高度。 */
	var previewY:Float = PREVIEW_Y;
	var previewH:Float = PREVIEW_H;

	// 外部页卡片
	var extCard:FlxSprite;
	var extTitle:FlxText;
	var extHint:FlxText;

	// 主题色块区（宿主不再依赖 BaseOptionsMenu 的色板挂载，见 meteoric-system 的挂载契约）
	var swatchBar:FlxSprite = null;
	var swatches:ColorSwatchPicker = null;
	var _handleSwatchClick:Bool = true;

	public var curSelected:Int = 0;
	var scrollIndex:Int = 0;
	public var focused(default, set):Bool = false;

	// 鼠标/键盘输入分离（键盘接管后冻结鼠标跟随，移动 > 10px 恢复）
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;

	// 键盘左右长按
	var holdTime:Float = 0;
	var holdValue:Float = 0;
	// 键盘上下长按
	var upDownHold:Float = 0;

	// 触控 ◀▶ 长按（与键盘独立计时）
	var padHoldDir:Int = 0;
	var padHoldTime:Float = 0;
	var padHoldValue:Float = 0;
	var padStepTimer:Float = 0;

	var wheelScroll:WheelScroll = new WheelScroll();

	// FlxGroup 没有 controls 取值器（MusicBeatState/MusicBeatSubstate 才自带），这里按同一模式接上
	var controls(get, never):Controls;
	inline function get_controls():Controls
		return Controls.instance;

	public function new()
	{
		super();

		panel = OptionsUi.makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22);
		add(panel);

		titleText = new FlxText(TITLE_X, TITLE_Y, TITLE_W, '', 30);
		titleText.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		titleText.wordWrap = false;
		titleText.scrollFactor.set();
		add(titleText);

		// ★ 高亮条先 add（画在文字下面）—— 层级契约，禁止挪到 rows 循环之后
		selectorBar = OptionsUi.makePanel(BAR_X, ROW_Y - 4, BAR_W, BAR_H, 12, DesignTokens.rowHighlight, null);
		selectorBar.visible = false;
		add(selectorBar);

		// 一次性建满 ROWS_VISIBLE 行精灵；实际用几行由 rowsVisible 决定（带预览带的分区只用 6 行）
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = new FlxText(NAME_X, ROW_Y + (r * ROW_GAP), NAME_W, '', 26);
			row.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.wordWrap = false;
			row.scrollFactor.set();
			add(row);
			rows.push(row);

			var sw:objects.ToggleSwitch = new objects.ToggleSwitch(CHECK_X, ROW_Y + SWITCH_ROW_OFF + (r * ROW_GAP));
			for (spr in sw.sprites) add(spr);
			switchCols.push(sw);

			var valueText:FlxText = new FlxText(VALUE_X, ROW_Y + 4 + (r * ROW_GAP), VALUE_W, '', 22);
			valueText.setFormat(Paths.font('future.ttf'), 22, 0xFFD7D7E0, RIGHT);
			// FlxText 默认 wordWrap = true：固定 300 宽下长值（Score 栏格式那一串）会折行压到相邻行
			valueText.wordWrap = false;
			valueText.scrollFactor.set();
			add(valueText);
			valueTexts.push(valueText);

			lastRowText.push('');
			lastValueText.push('');
		}

		// 底部信息条：说明行（默认）与主题色块区（选中主题色行时）二选一显示
		descText = new FlxText(DESC_X, DESC_Y, DESC_W, '', 20);
		descText.setFormat(Paths.font('future.ttf'), 20, 0xFFCFCFDC, LEFT);
		descText.wordWrap = false;
		descText.scrollFactor.set();
		add(descText);

		// 外部页卡片（独立整屏页出口的分区在内容区显示它）
		extCard = OptionsUi.makePanel(PANEL_X + 24, PANEL_Y + 120, PANEL_W - 48, 200, 14, DesignTokens.rowHover, DesignTokens.panelOutline);
		extCard.visible = false;
		add(extCard);

		extTitle = new FlxText(PANEL_X + 56, PANEL_Y + 150, PANEL_W - 112, '', 26);
		extTitle.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT);
		extTitle.wordWrap = false;
		extTitle.scrollFactor.set();
		extTitle.visible = false;
		add(extTitle);

		extHint = new FlxText(PANEL_X + 56, PANEL_Y + 200, PANEL_W - 112, '', 22);
		extHint.setFormat(Paths.font('future.ttf'), 22, 0xFFD7D7E0, LEFT);
		extHint.scrollFactor.set();
		extHint.visible = false;
		add(extHint);

		setRowsVisible(false);
	}

	// ===== 分区装载 =====

	/**
	 * 切到「选项分区」：section 为 headless 构造出来的 BaseOptionsMenu 子类实例。
	 * 只改文本/可见性，**不重建精灵**（分区切换是高频操作，禁止分配新对象）。
	 * @param preview         分区自带预览元素容器（如音符皮肤预览）；null = 本分区没有预览
	 * @param previewRowCount 本分区用几行选项（默认 8；预览带分区用 6，省下的空间给预览）
	 */
	public function setSection(sec:BaseOptionsMenu, sectionTitle:String, ?preview:flixel.group.FlxGroup = null, previewRowCount:Int = 0):Void
	{
		canvasMode = false;
		if (currentCanvas != null) currentCanvas.visible = false;
		section = sec;
		if (sec != null) sec.paneHosted = true; // 常驻标志：分区据此走"预览带摆位、只切显隐"的分支
		options = (sec == null) ? [] : sec.getOptions();
		isExternal = false;
		titleText.text = sectionTitle;
		curSelected = 0;
		scrollIndex = 0;
		extCard.visible = false;
		extTitle.visible = false;
		extHint.visible = false;
		// 行窗口：0 = 默认满窗口；其余夹在 [2, ROWS_VISIBLE]，避免分区乱传数把布局压穿
		rowsVisible = (previewRowCount <= 0) ? ROWS_VISIBLE : previewRowCount;
		if (rowsVisible < 2) rowsVisible = 2;
		if (rowsVisible > ROWS_VISIBLE) rowsVisible = ROWS_VISIBLE;
		// 预览带跟着行窗口走：行窗口让出的高度全部给预览带（见 previewY/previewH 声明处的推导）
		previewY = ROW_Y + rowsVisible * ROW_GAP;
		previewH = Math.max(0, (STRIP_Y - 6) - previewY);
		setPreview(preview);
		setRowsVisible(true);
		refreshRows();
		refreshSwatches();
		notifySectionSelection();
	}

	/**
	 * 装载/隐藏分区预览：把预览整体摆进「预览带」并居中。
	 * ⚠ 预览容器是**普通 FlxGroup**（没有 x/y），而且分区往往把精灵再套一层自己的 FlxTypedGroup，
	 * 所以这里**递归收集叶子精灵**算包围盒，再逐个平移 —— 只对叶子生效，且同一容器只摆一次
	 * （重复摆放会累加偏移，见 placedPreview）。
	 */
	function setPreview(preview:flixel.group.FlxGroup):Void
	{
		if (previewGroup != null && previewGroup != preview) previewGroup.visible = false;
		previewGroup = preview;
		if (preview == null) return;

		if (members.indexOf(preview) < 0) add(preview);
		preview.visible = true;
		if (placedPreview == preview) return; // 已摆过：位置仍然有效，重复平移会累加

		var leaves:Array<FlxSprite> = [];
		collectSprites(preview, leaves);
		if (leaves.length == 0) return;

		var minX:Float = 1e9, maxX:Float = -1e9, minY:Float = 1e9, maxY:Float = -1e9;
		for (spr in leaves)
		{
			minX = Math.min(minX, spr.x);
			maxX = Math.max(maxX, spr.x + spr.width);
			minY = Math.min(minY, spr.y);
			maxY = Math.max(maxY, spr.y + spr.height);
		}
		var dx:Float = PANEL_X + (PANEL_W - (maxX - minX)) / 2 - minX;
		var dy:Float = previewY + (previewH - (maxY - minY)) / 2 - minY;
		for (spr in leaves)
		{
			spr.x += dx;
			spr.y += dy;
		}
		placedPreview = preview;
	}

	/** 递归收集容器里的叶子精灵（FlxGroup 可以多层嵌套：分区常自带一层 FlxTypedGroup） */
	function collectSprites(group:flixel.group.FlxGroup, out:Array<FlxSprite>, depth:Int = 0):Void
	{
		if (group == null || depth > 4) return;
		for (b in group.members)
		{
			if (b == null) continue;
			var sub:flixel.group.FlxGroup = Std.isOfType(b, flixel.group.FlxGroup) ? cast b : null;
			if (sub != null) collectSprites(sub, out, depth + 1);
			else if (Std.isOfType(b, FlxSprite)) out.push(cast b);
		}
	}

	function hidePreview():Void
	{
		if (previewGroup != null) previewGroup.visible = false;
		previewGroup = null;
		rowsVisible = ROWS_VISIBLE;
	}

	/** 切到「独立整屏页出口」分区：内容区显示一张可点卡片，确认即打开 */
	public function setExternal(sectionTitle:String, hint:String):Void
	{
		canvasMode = false;
		if (currentCanvas != null) currentCanvas.visible = false;
		section = null;
		options = [];
		isExternal = true;
		titleText.text = sectionTitle;
		curSelected = 0;
		scrollIndex = 0;
		setRowsVisible(false);
		if (swatchBar != null) swatchBar.visible = false;
		if (swatches != null) swatches.setVisible(false);
		selectorBar.visible = false;
		descText.visible = false;

		extTitle.text = sectionTitle;
		extTitle.visible = true;
		extHint.text = hint;
		extHint.visible = true;
		extCard.visible = true;
		hidePreview();
	}

	/**
	 * 切到「画布分区」：内容区让位给自带绝对布局的编辑器（按键设置 / 箭头配色）。
	 * 画布按内容区矩形构造（`new XXXPane(rect)`），本方法只负责显隐与层级；
	 * 画布自己的输入（鼠标/键盘/滚轮）由画布内部处理，本类不再接管内容区输入。
	 */
	public function setCanvas(canvasRef:flixel.group.FlxGroup, sectionTitle:String):Void
	{
		if (currentCanvas != null && currentCanvas != canvasRef) currentCanvas.visible = false;
		section = null;
		options = [];
		isExternal = false;
		canvasMode = true;
		titleText.text = sectionTitle;
		setRowsVisible(false);
		hidePreview();
		if (swatchBar != null) swatchBar.visible = false;
		if (swatches != null) swatches.setVisible(false);
		selectorBar.visible = false;
		descText.visible = false;
		extCard.visible = false;
		extTitle.visible = false;
		extHint.visible = false;

		currentCanvas = canvasRef;
		if (members.indexOf(canvasRef) < 0) add(canvasRef);
		canvasRef.visible = true;
	}

	/** 当前分区是否为画布（宿主据此决定 BACK/确认键是否交给画布自己处理） */
	public function isCanvasActive():Bool
	{
		return canvasMode;
	}

	public function currentOption():Option
	{
		if (curSelected < 0 || curSelected >= options.length) return null;
		return options[curSelected];
	}

	public function currentSection():BaseOptionsMenu
	{
		return section;
	}

	public function optionCount():Int
	{
		return options.length;
	}

	// ===== 渲染 =====

	function setRowsVisible(v:Bool):Void
	{
		for (r in 0...rows.length)
		{
			rows[r].visible = v;
			switchCols[r].setVisible(v);
			valueTexts[r].visible = v;
		}
		descText.visible = v;
	}

	function refreshRows():Void
	{
		if (isExternal) return;

		for (r in 0...rowsVisible)
		{
			var idx:Int = scrollIndex + r;
			if (idx >= options.length)
			{
				rows[r].visible = false;
				switchCols[r].setVisible(false);
				valueTexts[r].visible = false;
				continue;
			}

			var option:Option = options[idx];
			var isBool:Bool = (option.type == 'bool');
			var isSel:Bool = (idx == curSelected && focused);

			rows[r].visible = true;
			if (lastRowText[r] != option.name)
			{
				lastRowText[r] = option.name;
				rows[r].text = option.name;
				rows[r].updateHitbox();
			}
			rows[r].alpha = idx == curSelected ? (rowGroupDim ? 0.45 : 1) : (rowGroupDim ? 0.3 : 0.78);
			rows[r].color = idx == curSelected ? FlxColor.WHITE : 0xFFCFCFDC;

			switchCols[r].setVisible(isBool);
			switchCols[r].setAlpha(idx == curSelected ? 1 : 0.85);
			if (isBool)
			{
				switchCols[r].setOn(option.getValue() == true); // 目标态（滑块由 update 的 animate 滑过去）
				switchCols[r].refreshTheme();                   // primary 是运行时令牌：主题切换后重绘
			}

			valueTexts[r].visible = !isBool;
			if (!isBool)
			{
				var v:String = OptionValue.display(option);
				if (lastValueText[r] != v)
				{
					lastValueText[r] = v;
					valueTexts[r].text = v;
					valueTexts[r].updateHitbox();
				}
				valueTexts[r].alpha = idx == curSelected ? 1 : 0.8;
				valueTexts[r].color = idx == curSelected ? FlxColor.WHITE : 0xFFD7D7E0;
			}
			// 高亮条只在键盘/内容区有焦点时按"选中态"绘制，未聚焦时用同一几何降亮度
			if (isSel) selectorBar.alpha = 1;
		}

		// ★ 尾部未使用的行（带预览带的分区只用 6 行）必须**显式隐藏**：
		//   setRowsVisible(true) 会把全部 8 行的行文字/开关/值文字都显示出来，而上面只遍历 rowsVisible 行；
		//   不补这一段，预览带上就会留下"两个没有文字的空开关"（2026-09-16 用户实测截图定位到的问题）。
		for (r in rowsVisible...rows.length)
		{
			rows[r].visible = false;
			switchCols[r].setVisible(false);
			valueTexts[r].visible = false;
			lastRowText[r] = '';      // 复位缓存：下次真用到这一行时会重新填文本
			lastValueText[r] = '';
		}

		var barY:Float = ROW_Y - 4 + ((curSelected - scrollIndex) * ROW_GAP);
		selectorBar.visible = true;
		selectorBar.alpha = focused ? 1 : 0.7;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});

		var o:Option = currentOption();
		descText.text = (o == null) ? '' : Std.string(o.description).split('\n')[0];
	}

	/** 全部重绘（分区切换 / 主题切换 / 值变化后调用） */
	public function refresh():Void
	{
		if (canvasMode) return; // 画布分区自管绘制
		if (isExternal)
		{
			descText.visible = false;
			return;
		}
		refreshRows();
		refreshSwatches();
	}

	// ===== 主题色块区 =====

	function ensureSwatches():Void
	{
		if (swatches != null) return;
		var total:Float = ColorSwatchPicker.SWATCH_DIAMETER + (DesignTokens.THEME_COUNT - 1) * ColorSwatchPicker.SWATCH_STEP;
		var startX:Float = PANEL_X + (PANEL_W - total) / 2 + ColorSwatchPicker.SWATCH_DIAMETER / 2;
		var cy:Float = STRIP_Y + STRIP_H / 2;

		// 底板：表示"这一排是可点的"
		swatchBar = OptionsUi.makePanel(PANEL_X + 14, STRIP_Y, BAR_W, STRIP_H, 14, DesignTokens.rowHover, DesignTokens.panelOutline);
		swatchBar.visible = false;
		add(swatchBar);

		swatches = new ColorSwatchPicker(startX, cy, DesignTokens.primaryPalette());
		swatches.onClick = onSwatchClicked;
		swatches.selectedIndex = DesignTokens.themeIndex;
		swatches.setVisible(false);
		for (spr in swatches.sprites)
			add(spr);
		swatches.registerThemeListener();
	}

	/** 定位当前分区里的「主题色」选项（按选项名前缀；与 BaseOptionsMenu 同一约定） */
	function findThemeOption():Option
	{
		for (o in options)
			if (o != null && Std.string(o.name).indexOf('主题色') == 0) return o;
		return null;
	}

	function refreshSwatches():Void
	{
		var themeOpt:Option = findThemeOption();
		if (themeOpt == null)
		{
			if (swatchBar != null) swatchBar.visible = false;
			if (swatches != null) swatches.setVisible(false);
			descText.visible = !isExternal;
			return;
		}

		ensureSwatches();
		var isThemeRow:Bool = (currentOption() == themeOpt);
		swatches.selectedIndex = DesignTokens.themeIndex;
		swatches.interactive = isThemeRow;
		swatches.keyboardFocus = isThemeRow && focused;
		swatches.setVisible(isThemeRow);
		swatchBar.visible = isThemeRow;
		// 色板与说明行互斥：色板可见时说明行必须让位（避免文字压色块，实测反馈）
		descText.visible = !isThemeRow && !isExternal;
	}

	/** 色块点击 → 走与选项行**同一条**取值链路（setValue + change + 音效），不会出现两套行为 */
	function onSwatchClicked(index:Int):Void
	{
		if (!_handleSwatchClick) return;
		_handleSwatchClick = false;
		var o:Option = findThemeOption();
		if (o == null) return;
		if (currentOption() != o)
		{
			var idx:Int = options.indexOf(o);
			if (idx >= 0) changeSelection(idx - curSelected);
		}
		var cur:Int = Std.int(Std.parseFloat(Std.string(o.getValue())));
		if (index == cur) return;
		o.setValue(index);
		refreshRows();
		o.change();                       // onChange → 主题即时生效 + 存档
		FlxG.sound.play(Paths.sound('scrollMenu'));
		refreshSwatches();
		if (onValueChanged != null) onValueChanged();
	}

	// ===== 选中与取值 =====

	public function changeSelection(change:Int, playSound:Bool = true):Void
	{
		if (isExternal || options.length == 0) return;
		curSelected += change;
		if (curSelected < 0) curSelected = options.length - 1;
		if (curSelected >= options.length) curSelected = 0;

		if (curSelected < scrollIndex) scrollIndex = curSelected;
		else if (curSelected > scrollIndex + rowsVisible - 1) scrollIndex = curSelected - rowsVisible + 1;

		if (playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		refreshRows();
		refreshSwatches();
		notifySectionSelection();
	}

	/** 分区自身的选中联动钩子（如音符皮肤预览）：headless 分区里通常为空实现 */
	function notifySectionSelection():Void
	{
		if (section != null) section.onPaneSelectionChange(curSelected);
	}

	/** 单选一步取值（键盘 ←/→ 点按、鼠标点击、触控 ◀▶ 点按） */
	public function changeOptionValue(dir:Int):Void
	{
		var o:Option = currentOption();
		if (o == null || o.type == 'key') return;
		OptionValue.step(o, dir);
		var val:Dynamic = o.getValue();
		holdValue = Std.parseFloat(Std.string(val));
		o.change();
		refreshRows();
		refreshSwatches();
		FlxG.sound.play(Paths.sound('scrollMenu'));
		if (onValueChanged != null) onValueChanged();
	}

	public function toggleSelected():Void
	{
		var o:Option = currentOption();
		if (o == null || o.type != 'bool') return;
		FlxG.sound.play(Paths.sound('scrollMenu'));
		o.setValue((o.getValue() == true) ? false : true);
		o.change();
		refreshRows();
		if (onValueChanged != null) onValueChanged();
	}

	public function resetSelected():Void
	{
		var o:Option = currentOption();
		if (o == null) return;
		o.setValue(o.defaultValue);
		if (o.type == 'string') o.curOption = OptionValue.optionIndex(o);
		o.change();
		refreshRows();
		refreshSwatches();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		if (onValueChanged != null) onValueChanged();
	}

	/** 内容区确认键（Enter / A / 卡片点击） */
	public function confirm():Void
	{
		if (isExternal)
		{
			if (onOpenExternal != null) onOpenExternal();
			return;
		}
		var o:Option = currentOption();
		if (o == null) return;
		if (o.type == 'bool') toggleSelected();
		else if (o.type == 'string' && o.onChange != null) o.change();
	}

	// ===== 输入（内容区）=====

	public function takeKeyboardControl():Void
	{
		mouseActive = false;
		mouseLockX = FlxG.mouse.screenX;
		mouseLockY = FlxG.mouse.screenY;
	}

	public function isMouseActive():Bool
	{
		return mouseActive;
	}

	/**
	 * 内容区每帧输入。
	 * @param elapsed       帧时长
	 * @param allowKeyboard 键盘是否归内容区（焦点在内容区时才为 true）
	 * @param allowWheel    滚轮是否归内容区（焦点在分区栏时由宿主处理滚轮，避免双消费）
	 */
	public function updatePaneInput(elapsed:Float, allowKeyboard:Bool = true, allowWheel:Bool = true):Void
	{
		if (canvasMode) return; // 画布分区：输入由画布自己处理（它有自己的命中与滚轮逻辑）
		var wheelStep:Int = allowWheel ? wheelScroll.process(FlxG.mouse.wheel) : 0;

		if (allowKeyboard)
		{
			if (controls.UI_UP_P) { takeKeyboardControl(); upDownHold = 0; changeSelection(-1); }
			if (controls.UI_DOWN_P) { takeKeyboardControl(); upDownHold = 0; changeSelection(1); }
			if (controls.UI_UP || controls.UI_DOWN)
			{
				takeKeyboardControl();
				var before:Int = Math.floor((upDownHold - HOLD_DELAY) * 10);
				upDownHold += elapsed;
				var after:Int = Math.floor((upDownHold - HOLD_DELAY) * 10);
				if (upDownHold > HOLD_DELAY && after - before > 0)
					changeSelection(Std.int(Math.min(after - before, 1)) * (controls.UI_UP ? -1 : 1));
			}
			if (controls.UI_UP_R || controls.UI_DOWN_R) upDownHold = 0;

			// 左右调值：点按立即一步，按住 0.5s 后按 scrollSpeed 连续
			if (controls.UI_LEFT || controls.UI_RIGHT)
			{
				takeKeyboardControl();
				var dir:Int = controls.UI_LEFT ? -1 : 1;
				var o:Option = currentOption();
				if (o != null && o.type != 'key')
				{
					if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
					{
						holdTime = 0;
						changeOptionValue(dir);
					}
					else
					{
						holdTime += elapsed;
						if (holdTime > HOLD_DELAY)
						{
							if (o.type != 'string')
							{
								holdValue += o.scrollSpeed * elapsed * dir;
								if (holdValue < o.minValue) holdValue = o.minValue;
								else if (holdValue > o.maxValue) holdValue = o.maxValue;
								if (o.type == 'int') o.setValue(Math.round(holdValue));
								else o.setValue(FlxMath.roundDecimal(holdValue, o.decimals));
								o.change();
								refreshRows();
								refreshSwatches();
								if (onValueChanged != null) onValueChanged();
							}
							else if (holdTime > HOLD_DELAY)
							{
								// string：按住期间按 0.2s 步进切档
								var steps:Int = Std.int((holdTime - HOLD_DELAY) / PAD_STRING_STEP);
								if (steps > 0)
								{
									for (i in 0...steps) changeOptionValue(dir);
									holdTime = HOLD_DELAY;
								}
							}
						}
					}
				}
			}
			else holdTime = 0;
			if (controls.UI_LEFT_R || controls.UI_RIGHT_R) holdTime = 0;
		}

		// 鼠标：键盘接管后冻结跟随，真实移动 > 10px 恢复
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
		}

		if (wheelStep != 0)
		{
			mouseActive = true;
			changeSelection(wheelStep);
		}

		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		// 触屏：手指抬起且未拖动才算点击（拖动滚动列表时不误触）
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

		if (swatches != null)
		{
			swatches.update(FlxG.mouse.screenX, FlxG.mouse.screenY, clickPressed && _handleSwatchClick);
			_handleSwatchClick = true;
		}

		if (!clickPressed) return;

		// 1) 色板优先（将来布局若与行区域重叠，先判即免疫）
		if (swatches != null && swatches.isVisible)
		{
			var hit:Int = swatches.hitTest(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (hit >= 0)
			{
				mouseActive = true;
				if (onContentClicked != null) onContentClicked();
				onSwatchClicked(hit);
				#if !mobile
				_handleSwatchClick = false;
				#end
				return;
			}
		}

		// 2) 外部页卡片：整卡可点（触控目标远大于 56）
		if (isExternal)
		{
			if (overRect(extCard, FlxG.mouse.screenX, FlxG.mouse.screenY, 0))
			{
				mouseActive = true;
				if (onContentClicked != null) onContentClicked();
				confirm();
			}
			return;
		}

		// 3) 复选框：选中 + 切换
		var checkboxHit:Int = getHoveredCheckbox();
		if (checkboxHit >= 0)
		{
			mouseActive = true;
			if (onContentClicked != null) onContentClicked();
			if (checkboxHit != curSelected) changeSelection(checkboxHit - curSelected);
			toggleSelected();
			return;
		}

		// 4) 选项行：点未选中行 = 只选中（桌面/触控一致）；
		//    点已选中行 = 切换/调值 —— 仅桌面（触屏拖动易被误判为点击，与 BaseOptionsMenu 既有取舍一致）
		var hoveredID:Int = getHoveredOptionID();
		if (hoveredID >= 0)
		{
			mouseActive = true;
			if (onContentClicked != null) onContentClicked();
			if (hoveredID != curSelected)
			{
				changeSelection(hoveredID - curSelected);
				upDownHold = 0;
			}
			#if !mobile
			else
			{
				var o:Option = currentOption();
				if (o != null)
				{
					if (o.type == 'bool') toggleSelected();
					else if (o.type != 'key') changeOptionValue(1);
				}
			}
			#end
		}
	}

	/**
	 * 触控 ◀▶ 按钮（宿主持有按钮 Sprite 与按下状态，逐帧转发）：
	 * @param dir    -1 左 / 1 右 / 0 无
	 * @param held   本帧是否按住（且指针仍在按钮内）
	 * @param pressed 本帧是否刚按下（点按立即生效）
	 */
	public function updatePadAdjust(dir:Int, pressed:Bool, held:Bool, elapsed:Float):Void
	{
		if (isExternal) return;
		var o:Option = currentOption();
		if (o == null || o.type == 'key') return;

		if (pressed && dir != 0)
		{
			padHoldDir = dir;
			padHoldTime = 0;
			padStepTimer = 0;
			if (o.type == 'bool') toggleSelected();
			else changeOptionValue(dir);
			if (o.type != 'string') padHoldValue = Std.parseFloat(Std.string(o.getValue()));
			return;
		}

		if (!held || dir == 0 || dir != padHoldDir)
		{
			if (!held) { padHoldDir = 0; padHoldTime = 0; padStepTimer = 0; padHoldValue = 0; }
			return;
		}

		padHoldTime += elapsed;
		if (padHoldTime <= PAD_HOLD_DELAY) return;

		switch (o.type)
		{
			case 'int' | 'float' | 'percent':
				padHoldValue += o.scrollSpeed * elapsed * padHoldDir;
				if (padHoldValue < o.minValue) padHoldValue = o.minValue;
				else if (padHoldValue > o.maxValue) padHoldValue = o.maxValue;
				if (o.type == 'int') o.setValue(Math.round(padHoldValue));
				else o.setValue(FlxMath.roundDecimal(padHoldValue, o.decimals));
				o.change();
				refreshRows();
				refreshSwatches();
				if (onValueChanged != null) onValueChanged();
			case 'string':
				padStepTimer += elapsed;
				while (padStepTimer >= PAD_STRING_STEP)
				{
					padStepTimer -= PAD_STRING_STEP;
					changeOptionValue(padHoldDir);
				}
			default:
		}
	}

	// ===== 命中判定 =====

	function overRect(spr:FlxSprite, mx:Float, my:Float, pad:Float):Bool
	{
		if (spr == null) return false;
		return mx >= spr.x - pad && mx <= spr.x + spr.width + pad
			&& my >= spr.y - pad && my <= spr.y + spr.height + pad;
	}

	/** 选项行命中（返回全局选项下标；未命中 -1） */
	public function getHoveredOptionID():Int
	{
		if (isExternal) return -1;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		if (mx < PANEL_X + 14 || mx > PANEL_X + PANEL_W - 14) return -1;
		for (r in 0...rowsVisible)
		{
			if (!rows[r].visible) continue;
			var rowY:Float = ROW_Y + (r * ROW_GAP);
			if (my >= rowY - 8 && my <= rowY + 44)
			{
				var idx:Int = scrollIndex + r;
				if (idx < options.length) return idx;
			}
		}
		return -1;
	}

	/** 复选框命中（含 12px 内边距 → 50×50 触控目标；视觉尺寸保持 26） */
	function getHoveredCheckbox():Int
	{
		if (isExternal) return -1;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...rowsVisible)
		{
			var sw:objects.ToggleSwitch = switchCols[r];
			if (sw.track == null || !sw.track.visible) continue;
			if (sw.hits(mx, my, 12)) return scrollIndex + r; // 轨迹外扩 12 → 命中高 56（触控红线）
		}
		return -1;
	}

	// ===== 焦点 =====

	function set_focused(v:Bool):Bool
	{
		focused = v;
		if (selectorBar != null) selectorBar.alpha = v ? 1 : 0.7;
		if (swatches != null)
		{
			// 只在"色板确实显示着"时才动 keyboardFocus：该 setter 会刷新选中环，
			// 对隐藏中的色板调用它会在别的分区留下孤零零的白圈（见 ColorSwatchPicker.setSelectedVisual 的守卫）
			var themeOpt:Option = findThemeOption();
			var show:Bool = (swatches.isVisible && themeOpt != null && themeOpt == currentOption());
			swatches.keyboardFocus = v && show;
		}
		return focused;
	}

	/** 宿主在「预览态」下压暗选项行（当前无预览分区使用；保留给后续预览迁移） */
	public function setRowsDimmed(v:Bool):Void
	{
		if (rowGroupDim == v) return;
		rowGroupDim = v;
		refreshRows();
	}

	public function killTweens():Void
	{
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		// 开关滑块逐帧插值（圆心空间，elapsed*18），只在可见时推进
		for (sw in switchCols)
			if (sw != null && sw.track != null && sw.track.visible) sw.animate(elapsed);
	}

	override function destroy()
	{
		killTweens();
		for (sw in switchCols)
			if (sw != null) sw.destroy();
		switchCols = [];
		// 静态监听表：不摘除会留下对已销毁精灵的僵尸回调（meteoric-system 硬性契约）
		if (swatches != null)
		{
			swatches.unregisterThemeListener();
			swatches.destroy();
			swatches = null;
		}
		super.destroy();
	}
}
