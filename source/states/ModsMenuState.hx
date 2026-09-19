package states;
import backend.WheelScroll;

import backend.WeekData;
import backend.Mods;
import backend.ModInstaller;

import openfl.display.BitmapData;
import openfl.Lib;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

import objects.AttachedSprite;
import objects.BackButton;
import flixel.util.FlxSpriteUtil;

class ModsMenuState extends MusicBeatState
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

	static final LIST_X:Float = 164;  // 选项名 X（原 88：胶囊开关 96 宽后必须右移让位）
	static final LIST_Y:Float = 152;
	static final ROW_GAP:Float = 56;
	static final ROWS_VISIBLE:Int = 8;

	static final CHECK_X:Float = 56;      // 开关 X（objects.ToggleSwitch，96×32 胶囊）
	static final SWITCH_ROW_OFF:Float = 6; // 开关在行内垂直偏移
	static final VALUE_X:Float = 540;
	static final VALUE_W:Float = 160;

	// ===== 左面板：选中项「大卡片」（与 CreditsState 同一套尺寸语义）=====
	static final ROW_H:Float = 56;        // 未选中行高
	static final CARD_H:Float = 104;      // 选中卡片高
	static final ROW_GAP_S:Float = 4;     // 行间留白
	static final CARD_X:Float = PANEL_L_X + 24;
	static final CARD_W:Float = PANEL_L_W - 48;
	static final CARD_RADIUS:Float = 14;
	static final CARD_PAD:Float = 16;
	static final CARD_ICON_SIZE:Float = 64;                    // 卡片内图标（等比）
	static final CARD_TEXT_X:Float = CARD_X + CARD_PAD + CARD_ICON_SIZE + 18; // 162
	static final CARD_TEXT_W:Float = (CARD_X + CARD_W - CARD_PAD) - CARD_TEXT_X; // 486
	static final LIST_BOTTOM:Float = PANEL_L_Y + PANEL_L_H - 12; // 628
	static final LIST_H:Float = LIST_BOTTOM - LIST_Y;            // 476

	static final INFO_X:Float = 772;
	static final INFO_W:Float = 400;

	var mods:Array<ModMetadata> = [];
	var modsList:Array<Dynamic> = [];
	static var needaReset = false;
	private static var curSelected:Int = 0;
	public static var defaultColor:FlxColor = 0xFF665AFF;

	var rows:Array<MenuText> = [];
	/** 行内开关（与更新界面同款胶囊，见 objects.ToggleSwitch）；行位动态，靠 setPosition 跟随 */
	var switchCols:Array<objects.ToggleSwitch> = [];
	var statusTexts:Array<FlxText> = [];
	var lastRowText:Array<String> = [];
	var lastStatus:Array<String> = [];
	var scrollIndex:Int = 0;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

	// 选中卡片（左面板）：图标 + Mod 名 + 启用状态
	var cardBg:FlxSprite;
	var cardIcon:FlxSprite;
	var cardLetter:FlxText;
	var cardName:FlxText;
	var cardStatus:FlxText;
	var cardTween:FlxTween;
	var cardShownFolder:String = '';
	/** 当前卡片是否已套用 Mod 图标（图标首次加载发生在 updateInfo 里，见该函数的懒同步） */
	var cardAvatarApplied:Bool = false;
	/** 卡片当前显示的启用状态（状态变化要重建文案） */
	var cardShownOn:Bool = false;
	/** 卡片是否已经出现过一次（只有首次做淡入，之后即时重建，避免每格都播动画） */
	var cardEverShown:Bool = false;

	var iconSpr:FlxSprite;
	var iconCache:Map<String, BitmapData> = [];
	var lastIconFolder:String = '';
	var nameText:FlxText;
	var folderText:FlxText;
	var descText:FlxText;
	var restartText:FlxText;
	var countText:FlxText;

	var toggleBtn:ModsButton;
	var upBtn:ModsButton;
	var downBtn:ModsButton;
	var allOnBtn:ModsButton;
	var allOffBtn:ModsButton;
	var deleteBtn:ModsButton;
	var buttons:Array<ModsButton> = [];
	var hasModsUI:Array<FlxSprite> = []; // 有 Mod 时才显示的元素

	/** 打开本界面时 ModInstaller.lastInstallTime 的快照：安装完成时间戳比它新 → 自动刷新列表 */
	var lastInstallSeen:Float = 0;

	var noModsTxt:FlxText;
	var noModsSine:Float = 0;

	var bg:FlxSprite;
	var intendedColor:Int;
	var colorTween:FlxTween;

	var backBtn:BackButton;

	// ===== 鼠标/键盘输入分离 =====
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	static final MOUSE_REACTIVATE_DIST:Float = 10;

	override function create()
	{
		trace('ModsMenuState: create');
		Lib.application.window.title = "FNF':Meteoric Engine - Mods List";

		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		WeekData.setDirectoryFromWeek();

		#if desktop
		DiscordClient.changePresence("In the Menus", null);
		#end

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 662, 1160, 48, 14));

		// ---- 标题 ----
		var leftTitle:FlxText = new FlxText(LIST_X, 100, 0, 'Mod 列表', 26);
		leftTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		leftTitle.borderSize = 2;
		leftTitle.scrollFactor.set();
		add(leftTitle);

		var rightTitle:FlxText = new FlxText(INFO_X, 100, 0, 'Mod 信息', 26);
		rightTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rightTitle.borderSize = 2;
		rightTitle.scrollFactor.set();
		add(rightTitle);

		// ---- 列表行（静态行，选中高亮条移动） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var row:MenuText = new MenuText(LIST_X, LIST_Y + (r * ROW_GAP), '', true, 26);
			row.isMenuItem = false;
			row.ID = r;
			row.visible = false;
			row.scrollFactor.set();
			add(row);
			rows.push(row);

			var sw:objects.ToggleSwitch = new objects.ToggleSwitch(CHECK_X, LIST_Y + SWITCH_ROW_OFF + (r * ROW_GAP));
			sw.setVisible(false);
			for (spr in sw.sprites) add(spr);
			switchCols.push(sw);

			var statusText:FlxText = new FlxText(VALUE_X, LIST_Y + 2 + (r * ROW_GAP), VALUE_W, '', 22);
			statusText.setFormat(Paths.font('future.ttf'), 22, 0xFFD7D7E0, RIGHT);
			statusText.textField.height = 40;
			statusText.scrollFactor.set();
			statusText.visible = false;
			add(statusText);
			statusTexts.push(statusText);

			lastRowText.push('');
			lastStatus.push('');
		}

		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, DesignTokens.rowHighlight, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 左面板：选中项「大卡片」（图标 + Mod 名 + 启用状态）----
		// 与 Credits 左面板同一套语言（见 CreditsState 的同名实现与注释）：
		// 选中行占 CARD_H，其余行占 ROW_H，行位逐行累加 → 卡片展开时下面的行整体让位。
		// 卡片必须**最先 add**（画在行文字下方），文字才不会压住描边。
		cardBg = makePanel(CARD_X, LIST_Y, CARD_W, CARD_H, CARD_RADIUS, DesignTokens.rowHighlight, DesignTokens.panelOutline);
		cardBg.visible = false;
		add(cardBg);

		cardIcon = new FlxSprite(0, 0);
		cardIcon.antialiasing = ClientPrefs.data.antialiasing;
		cardIcon.scrollFactor.set();
		cardIcon.visible = false;
		add(cardIcon);

		cardLetter = new FlxText(0, 0, CARD_ICON_SIZE, '', 30);
		cardLetter.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, CENTER);
		cardLetter.scrollFactor.set();
		cardLetter.visible = false;
		add(cardLetter);

		cardName = new FlxText(CARD_TEXT_X, LIST_Y, CARD_TEXT_W, '', 32);
		cardName.setFormat(Paths.font('future.ttf'), 32, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		cardName.borderSize = 2;
		cardName.wordWrap = false;
		cardName.scrollFactor.set();
		cardName.visible = false;
		add(cardName);

		cardStatus = new FlxText(CARD_TEXT_X, LIST_Y, CARD_TEXT_W, '', 18);
		cardStatus.setFormat(Paths.font('future.ttf'), 18, 0xFFD7D7E0, LEFT);
		cardStatus.wordWrap = false;
		cardStatus.scrollFactor.set();
		cardStatus.visible = false;
		add(cardStatus);

		// ---- 右侧信息 ----
		iconSpr = new FlxSprite(772, 190);
		iconSpr.antialiasing = ClientPrefs.data.antialiasing;
		iconSpr.visible = false;
		add(iconSpr);
		hasModsUI.push(iconSpr);

		nameText = new FlxText(INFO_X, 140, INFO_W, '', 28);
		nameText.setFormat(Paths.font('future.ttf'), 28, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		nameText.textField.height = 44;
		nameText.borderSize = 2;
		nameText.scrollFactor.set();
		nameText.visible = false;
		add(nameText);
		hasModsUI.push(nameText);

		folderText = new FlxText(INFO_X, 352, INFO_W, '', 16);
		folderText.setFormat(Paths.font('future.ttf'), 16, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		folderText.textField.height = 24;
		folderText.borderSize = 2;
		folderText.scrollFactor.set();
		folderText.visible = false;
		add(folderText);
		hasModsUI.push(folderText);

		countText = new FlxText(INFO_X, 382, INFO_W, '', 16);
		countText.setFormat(Paths.font('future.ttf'), 16, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		countText.textField.height = 24;
		countText.borderSize = 2;
		countText.scrollFactor.set();
		countText.visible = false;
		add(countText);
		hasModsUI.push(countText);

		descText = new FlxText(INFO_X, 420, INFO_W, '', 22);
		descText.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.textField.height = 110;
		descText.borderSize = 2;
		descText.scrollFactor.set();
		descText.visible = false;
		add(descText);
		hasModsUI.push(descText);

		restartText = new FlxText(INFO_X, 505, INFO_W, '注意：启用 / 停用此 Mod 需要重启游戏', 18);
		restartText.setFormat(Paths.font('future.ttf'), 18, 0xFFFF6B6B, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		restartText.textField.height = 24;
		restartText.borderSize = 2;
		restartText.scrollFactor.set();
		restartText.visible = false;
		add(restartText);
		hasModsUI.push(restartText);

		// ---- 操作按钮 ----
		toggleBtn = new ModsButton(772, 540, 170, 44, '启用', function() { toggleSelected(); });
		upBtn = new ModsButton(952, 540, 96, 44, '上移', function() { moveMod(-1); });
		downBtn = new ModsButton(1058, 540, 96, 44, '下移', function() { moveMod(1); });
		allOnBtn = new ModsButton(772, 590, 130, 44, '全部启用', function() { setAllMods(true); });
		allOffBtn = new ModsButton(912, 590, 130, 44, '全部禁用', function() { setAllMods(false); });
		deleteBtn = new ModsButton(1052, 590, 130, 44, '删除', function() { deleteSelected(); });
		deleteBtn.setLabelColor(0xFFFF6B6B); // 危险操作：红色

		buttons = [toggleBtn, upBtn, downBtn, allOnBtn, allOffBtn, deleteBtn];
		for (btn in buttons)
		{
			btn.visible = false;
			add(btn);
			hasModsUI.push(btn);
		}

		// ---- 无 Mod 提示 ----
		noModsTxt = new FlxText(60, 250, PANEL_L_W - 40, '没有安装任何 Mod\n\n把 Mod 文件夹放进 mods/ 目录后重新打开本界面\n\n按 Enter 打开 Mod 下载站', 28);
		noModsTxt.setFormat(Paths.font("future.ttf"), 26, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		noModsTxt.textField.height = 140;
		noModsTxt.borderSize = 2;
		noModsTxt.scrollFactor.set();
		add(noModsTxt);

		// ---- 加载 Mod 列表（可被安装检测复用） ----
		lastInstallSeen = ModInstaller.get().lastInstallTime;
		rebuildModsList();

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(40, 672, 1160, '滚轮 / 方向键 选择 · Enter / 左右 启用停用 · 点击 < 返回', 16);
		hint.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hint.textField.height = 24;
		hint.borderSize = 2;
		hint.scrollFactor.set();
		add(hint);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		changeSelection();
		updateRows();
		updateInfo();
		updateButtons();
		FlxG.mouse.visible = true;

		super.create();
	}

	override function update(elapsed:Float)
	{
		// 开关滑块逐帧插值（行位动态，滑块位置由组件的圆心模型自己跟着轨道走）
		for (sw in switchCols)
			if (sw != null && sw.track != null && sw.track.visible) sw.animate(elapsed);

		// 本界面打开期间拖入了新 mod 并安装完成 → 自动刷新列表
		var instTime:Float = ModInstaller.get().lastInstallTime;
		if (instTime > lastInstallSeen)
		{
			lastInstallSeen = instTime;
			rebuildModsList(true);
			changeSelection(0);
			updateRows();
			updateInfo();
			updateButtons();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}

		// 子状态（删除确认框 / 安装界面）打开时冻结本界面输入，
		// 避免 ESC / 鼠标点击被父界面同时消费（如按 ESC 取消确认框又退出 Mods 菜单）
		if (subState != null)
		{
			super.update(elapsed);
			return;
		}

		if(noModsTxt.visible)
		{
			noModsSine += 180 * elapsed;
			noModsTxt.alpha = 1 - Math.sin((Math.PI * noModsSine) / 180);
		}

		if (!controls.controllerMode)
		{
			FlxG.mouse.visible = true;
			updateMouseControl(elapsed);
		}

		if (controls.UI_UP_P)
		{
			takeKeyboardControl();
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeSelection(-1);
			updateRows();
			updateInfo();
			updateButtons();
		}
		if (controls.UI_DOWN_P)
		{
			takeKeyboardControl();
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeSelection(1);
			updateRows();
			updateInfo();
			updateButtons();
		}

		if (controls.ACCEPT)
		{
			takeKeyboardControl();
			if(mods.length < 1)
				CoolUtil.browserLoad('https://gamebanana.com/');
			else
				toggleSelected();
		}
		if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
		{
			takeKeyboardControl();
			if(mods.length > 0) toggleSelected();
		}

		if (controls.BACK)
		{
			exitMods();
			return;
		}

		super.update(elapsed);
	}

	// ===== 鼠标控制 =====
	function updateMouseControl(elapsed:Float)
	{
		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		// 触屏：手指抬起且未滑动才算点击，拖动滚动列表时不误选
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);

		if (wheelStep != 0)
		{
			mouseActive = true;
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeSelection(wheelStep);
			updateRows();
			updateInfo();
			updateButtons();
		}

		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			mouseActive = true;
			exitMods();
			return;
		}

		if (clickPressed)
		{
			// 操作按钮
			for (btn in buttons)
			{
				if (btn.visible && btn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
				{
					mouseActive = true;
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					btn.onClick();
					return;
				}
			}

			// 复选框/行点击：只负责选中，启用/停用由 A 键触发
			var checkID:Int = getHoveredCheckbox();
			if (checkID >= 0)
			{
				mouseActive = true;
				if (checkID != curSelected)
				{
					changeSelection(checkID - curSelected);
					updateRows();
					updateInfo();
					updateButtons();
				}
				return;
			}

			var rowID:Int = getHoveredRowID();
			if (rowID >= 0)
			{
				mouseActive = true;
				if (rowID != curSelected)
				{
					changeSelection(rowID - curSelected);
					updateRows();
					updateInfo();
					updateButtons();
				}
			}
		}

		for (btn in buttons)
			btn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
	}

	function takeKeyboardControl()
	{
		mouseActive = false;
		mouseLockX = FlxG.mouse.screenX;
		mouseLockY = FlxG.mouse.screenY;
	}

	function getHoveredRowID():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...ROWS_VISIBLE)
		{
			var row:MenuText = rows[r];
			if (!row.visible) continue;
			if (mx >= LIST_X - 12 && mx <= LIST_X + PANEL_L_W - 40 && my >= row.y - 8 && my <= row.y + 46)
				return scrollIndex + r;
		}
		return -1;
	}

	function getHoveredCheckbox():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...ROWS_VISIBLE)
		{
			var sw:objects.ToggleSwitch = switchCols[r];
			if (sw.track == null || !sw.track.visible) continue;
			if (sw.hits(mx, my, 12)) return scrollIndex + r; // 外扩 12 → 命中高 56（触控红线）
		}
		return -1;
	}

	// ===== 列表逻辑 =====

	/** 重建 Mod 列表（打开界面时 / 检测到新安装的 mod 时共用）。
	 *  keepSelection = true 时尽量恢复之前的选中项（按文件夹名匹配）。 */
	function rebuildModsList(?keepSelection:Bool = false)
	{
		var oldSelected:String = null;
		if (keepSelection && mods.length > 0)
			oldSelected = mods[curSelected].folder;

		mods = [];
		modsList = [];
		#if (MODS_ALLOWED && sys)
		bridge.CneBridge.clearCaches(); // mod 列表变化 → CNE songs/ 目录名缓存作废
		#end
		var list:ModsList = Mods.parseList();
		for (mod in list.all) modsList.push([mod, list.enabled.contains(mod)]);

		var i:Int = 0;
		while (i < modsList.length)
		{
			var values:Array<Dynamic> = modsList[i];
			if(!FileSystem.exists(Paths.mods(values[0])))
			{
				modsList.remove(modsList[i]);
				continue;
			}
			mods.push(new ModMetadata(values[0]));
			i++;
		}

		if (oldSelected != null)
		{
			var found:Int = -1;
			for (j in 0...mods.length)
			{
				if (mods[j].folder == oldSelected)
				{
					found = j;
					break;
				}
			}
			if (found >= 0) curSelected = found;
		}
		if(curSelected >= mods.length) curSelected = mods.length > 0 ? mods.length - 1 : 0;

		noModsTxt.visible = mods.length < 1;
		if(mods.length < 1)
			bg.color = defaultColor;
		else
			bg.color = mods[curSelected].color;
		intendedColor = bg.color;
	}

	function changeSelection(change:Int = 0)
	{
		var noMods:Bool = (mods.length < 1);
		noModsTxt.visible = noMods;

		if(noMods) return;

		curSelected += change;
		if(curSelected < 0)
			curSelected = mods.length - 1;
		else if(curSelected >= mods.length)
			curSelected = 0;

		// 滚动窗口：选中行占 CARD_H（104）而不是 ROW_H（56），容量必须按**真实可用高度**算，
		// 再把旧窗口位置**夹进合法区间**（优先保持原位、越界才最小移动）。与 CreditsState 同款：
		//   hi = cur - capacity + 1（选中项落在窗口最后一格）
		//   lo = hi - 1           （卡片最多落在**倒数第二格**，底边留一行余量，不会顶出左面板）
		var slotH:Float = CARD_H + ROW_GAP_S;
		var rowsCapacity:Int = 1 + Math.floor((LIST_H - slotH) / (ROW_H + ROW_GAP_S));
		if (rowsCapacity < 1) rowsCapacity = 1;
		if (rowsCapacity > ROWS_VISIBLE) rowsCapacity = ROWS_VISIBLE;

		var hi:Int = curSelected - rowsCapacity + 1;
		var lo:Int = curSelected - rowsCapacity + 2;
		if (lo > hi) lo = hi;
		if (lo < 0) lo = 0;
		scrollIndex = Std.int(Math.max(lo, Math.min(hi, scrollIndex)));

		var newColor:Int = mods[curSelected].color;
		if(newColor != intendedColor)
		{
			if(colorTween != null) { colorTween.cancel(); colorTween = null; }
			intendedColor = newColor;
			colorTween = FlxTween.color(bg, 0.4, bg.color, intendedColor, {ease: FlxEase.quadOut});
		}

		// 选中视觉已由「大卡片」承担（旧 selectorBar 会从卡片下缘露出一截，形成两个选中框）。
		selectorBar.visible = false;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }

		updateRows();     // 行位 / 卡片内容随选中项重排
		updateInfo();     // 右侧信息 + 卡片图标懒同步（见 updateInfo 里的说明）
	}

	function updateRows()
	{
		// 行位：选中行占 CARD_H、其余占 ROW_H，逐行累加 —— 卡片展开时下面的行整体让位。
		var ys:Array<Float> = [];
		var y:Float = LIST_Y;
		for (r in 0...ROWS_VISIBLE)
		{
			ys.push(y);
			var idx0:Int = scrollIndex + r;
			y += ((idx0 == curSelected) ? CARD_H : ROW_H) + ROW_GAP_S;
		}

		// 卡片内容：选中项变化或启用状态变化时重建（cardShownFolder + 状态双守卫）
		if (mods.length > 0 && curSelected >= 0 && curSelected < mods.length)
		{
			var sel:ModMetadata = mods[curSelected];
			var selOn:Bool = (modsList[curSelected][1] == true);
			if (cardShownFolder != sel.folder || cardShownOn != selOn)
			{
				cardShownFolder = sel.folder;
				cardShownOn = selOn;
				cardAvatarApplied = false;
				buildCard();
			}
		}

		var isCardVisible:Bool = false;

		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:MenuText = rows[r];
			var top:Float = ys[r];

			if (idx >= mods.length)
			{
				row.visible = false;
				switchCols[r].setVisible(false);
				statusTexts[r].visible = false;
				continue;
			}

			var mod:ModMetadata = mods[idx];
			var isSel:Bool = (idx == curSelected);

			// 越过面板底线的**普通行**隐藏；选中行（卡片）绝不能走这条裁剪，
			// 否则卡片会被整个隐藏（Credits 那边踩过一次，见 CreditsState 注释）。
			if (!isSel && top + ROW_H > LIST_BOTTOM)
			{
				row.visible = false;
				switchCols[r].setVisible(false);
				statusTexts[r].visible = false;
				continue;
			}

			if (isSel)
			{
				// 选中行：名称/状态/复选框都收进卡片，行本身隐藏（避免与卡片重复渲染）
				row.visible = false;
				switchCols[r].setVisible(false);
				statusTexts[r].visible = false;
				isCardVisible = true;
				continue;
			}

			var isOn:Bool = (modsList[idx][1] == true);

			row.visible = true;
			if (lastRowText[r] != mod.name)
			{
				lastRowText[r] = mod.name;
				clipText(row, mod.name, VALUE_X - LIST_X - 24);
			}
			row.alpha = 0.78;
			row.color = 0xFFCFCFDC;
			row.y = top + (ROW_H - row.height) * 0.5; // 行内垂直居中

			// 开关位置随行位走（原来写死 `LIST_Y + 4 + r * ROW_GAP`，卡片一展开就会错位）
			switchCols[r].setVisible(true);
			switchCols[r].setAlpha(0.85);
			switchCols[r].setPosition(CHECK_X, top + SWITCH_ROW_OFF);
			switchCols[r].setOn(isOn);      // 目标态；滑块由 update 的 animate 滑过去
			switchCols[r].refreshTheme();   // primary 是运行时令牌：主题切换后重绘

			statusTexts[r].visible = true;
			statusTexts[r].y = top + 2; // 始终与所在行对齐
			var status:String = isOn ? '已启用' : '已停用';
			if (lastStatus[r] != status)
			{
				lastStatus[r] = status;
				statusTexts[r].text = status;
				statusTexts[r].updateHitbox();
			}
			statusTexts[r].alpha = 0.75;
			statusTexts[r].color = isOn ? 0xFF7BFF9E : DesignTokens.primary;
		}

		// ---- 卡片定位 ----
		cardBg.visible = isCardVisible;
		cardIcon.visible = isCardVisible && cardIcon.graphic != null;
		cardLetter.visible = isCardVisible && !cardIcon.visible;
		cardName.visible = isCardVisible;
		cardStatus.visible = isCardVisible;

		if (isCardVisible)
		{
			var slot:Int = curSelected - scrollIndex;
			if (slot < 0) slot = 0;
			if (slot > ROWS_VISIBLE - 1) slot = ROWS_VISIBLE - 1;
			var cardY:Float = ys[slot];

			// 【硬约束】卡片底边绝不越过面板底线（越界就是"卡片顶出左面板"）。窗口容量只是"尽量"
			// 保证放得下；任何常量/字号改动都可能让估算失效，这里直接夹住兜底。
			var cardMaxY:Float = LIST_BOTTOM - CARD_H;
			if (cardY > cardMaxY) cardY = cardMaxY;
			if (cardY < LIST_Y) cardY = LIST_Y;

			var cy:Float = cardY + CARD_H * 0.5;

			cardBg.y = cardY;
			if (cardBg.alpha < 1) cardBg.alpha = 1;

			// 图标：等比缩放居中放进卡片左端
			var icCx:Float = CARD_X + CARD_PAD + CARD_ICON_SIZE * 0.5;
			if (cardIcon.graphic != null)
			{
				cardIcon.x = icCx - cardIcon.width * 0.5;
				cardIcon.y = cy - cardIcon.height * 0.5;
			}
			if (cardLetter.visible)
			{
				cardLetter.fieldWidth = CARD_ICON_SIZE;
				cardLetter.x = CARD_X + CARD_PAD;
				cardLetter.y = cy - 20;
			}

			// 名字 + 状态：两行整体在卡片内垂直居中
			cardName.x = CARD_TEXT_X;
			cardName.y = cy - 26;
			cardName.color = FlxColor.WHITE;

			cardStatus.x = CARD_TEXT_X;
			cardStatus.y = cy + 8;
			// 下标防护：curSelected 越界时不要读 modsList（cpp 上越界是崩，不是报错）
			if (curSelected >= 0 && curSelected < modsList.length)
				cardStatus.color = (modsList[curSelected][1] == true) ? 0xFF7BFF9E : DesignTokens.primary;

			// 卡片图标懒同步兜底：图标可能在这一帧之后才由 updateInfo 写入 iconCache
			if (curSelected >= 0 && curSelected < mods.length
				&& !cardAvatarApplied && iconCache.exists(mods[curSelected].folder))
				applyCardAvatar(iconCache.get(mods[curSelected].folder));
		}
	}

	/**
	 * 构建卡片文本：Mod 名 + 启用状态。**不碰图标** —— 图标统一由 applyCardAvatar() 负责，
	 * 因为 Mod 图标是懒加载进 iconCache 的（见 updateInfo），构建时机与图标就绪时机并不同步。
	 */
	function buildCard()
	{
		if (curSelected < 0 || curSelected >= mods.length) return;

		var mod:ModMetadata = mods[curSelected];
		cardName.text = fitToWidth(mod.name, CARD_TEXT_W, 32);
		cardName.updateHitbox();

		var isOn:Bool = (modsList[curSelected][1] == true);
		cardStatus.text = isOn ? '已启用' : '已停用（按 Enter 或点击启用）';
		#if (MODS_ALLOWED && sys)
		// CNE 格式 mod 标识（廉价探测；判定见 cne/CneModCompat.isCneMod）
		if (bridge.CneBridge.isCneMod(mod.folder))
			cardStatus.text += (bridge.CneBridge.isEnabled() ? '   ·   CNE 格式' : '   ·   CNE 格式（需在设置→编程开启「CNE 模组兼容」）');
		#end
		cardStatus.updateHitbox();

		// 首次出现做一次克制的淡入（skill：低频、150ms quadOut、可被打断）；之后即时重建
		if (cardTween != null)
		{
			cardTween.cancel();
			cardTween = null;
		}
		if (!cardEverShown)
		{
			cardEverShown = true;
			cardBg.alpha = 0.4;
			cardTween = FlxTween.tween(cardBg, {alpha: 1}, 0.15, {
				ease: FlxEase.quadOut,
				onComplete: function(_) cardTween = null
			});
		}
		else
			cardBg.alpha = 1;
	}

	/** 把 Mod 图标套到卡片图标上（短边贴齐后居中；缺图时退化为名称首字母）。 */
	function applyCardAvatar(icon:BitmapData):Void
	{
		if (icon == null || curSelected < 0 || curSelected >= mods.length) return;

		cardAvatarApplied = true;
		if (icon.width >= 150 && icon.height >= 150)
		{
			// pack.png 常见是 150×150 一帧的多帧图集：卡片上用第一帧
			cardIcon.loadGraphic(icon, true, 150, 150);
			cardIcon.animation.add('icon', [0], 10);
			cardIcon.animation.play('icon');
		}
		else
			cardIcon.loadGraphic(icon);

		var k:Float = CARD_ICON_SIZE / Math.min(cardIcon.frameWidth, cardIcon.frameHeight);
		cardIcon.setGraphicSize(Std.int(cardIcon.frameWidth * k), Std.int(cardIcon.frameHeight * k));
		cardIcon.updateHitbox();
		cardLetter.text = '';
	}

	/** 逐字截断到指定像素宽（超宽补省略号）。Card 上不用非公开的 TextField.numLines。 */
	static function fitToWidth(s:String, maxPx:Float, size:Int):String
	{
		if (s == null || s.length < 1) return '';
		var probe:FlxText = new FlxText(0, 0, 0, s, size);
		probe.setFormat(Paths.font('future.ttf'), size, FlxColor.WHITE, LEFT);
		var t:String = s;
		var n:Int = s.length;
		while (n > 1)
		{
			probe.text = t + '…';
			if (probe.textField.textWidth <= maxPx) break;
			n--;
			t = s.substring(0, n);
		}
		probe.destroy();
		return (n < s.length) ? (t + '…') : s;
	}

	function updateInfo()
	{
		if (mods.length < 1)
		{
			for (obj in hasModsUI) obj.visible = false;
			return;
		}
		for (obj in hasModsUI) obj.visible = true;

		var mod:ModMetadata = mods[curSelected];
		clipText(nameText, mod.name, INFO_W - 20);
		var folderLabel:String = '文件夹：' + mod.folder;
		#if (MODS_ALLOWED && sys)
		// 右侧信息：CNE 格式 mod 且兼容开关未开时给出可操作的提示（开关位置写在提示里）
		if (bridge.CneBridge.isCneMod(mod.folder) && !bridge.CneBridge.isEnabled())
			folderLabel += '   ·   CNE 格式，需开启「设置 → 编程 → CNE 模组兼容」';
		#end
		clipText(folderText, folderLabel, INFO_W - 20);

		var enabledCount:Int = 0;
		for (values in modsList) if (values[1] == true) enabledCount++;
		countText.text = '已启用 ' + enabledCount + ' / 共 ' + mods.length;
		countText.updateHitbox();

		descText.wordWrap = true;
		var desc:String = mod.description;
		if (desc.length > 60) desc = desc.substr(0, 59) + '…';
		descText.text = desc;
		descText.updateHitbox();

		restartText.visible = mod.restart;

		// 【卡片懒同步】卡片构建时该 Mod 的图标可能还没进 iconCache（首次进入界面时图标是在这里
		// 才加载并写入缓存的），所以卡片图标在这里补一次；图标就绪后置位 cardAvatarApplied，
		// 后续切回来不再重复套用。
		if (cardShownFolder == mod.folder && !cardAvatarApplied && iconCache.exists(mod.folder))
			applyCardAvatar(iconCache.get(mod.folder));

		// 图标（带帧动画的 pack.png / unknownMod）
		if (lastIconFolder != mod.folder)
		{
			lastIconFolder = mod.folder;
			var loadedIcon:BitmapData = iconCache.get(mod.folder);
			if (loadedIcon == null)
			{
				var iconToUse:String = Paths.mods(mod.folder + '/pack.png');
				if(FileSystem.exists(iconToUse))
				{
					loadedIcon = BitmapData.fromFile(iconToUse);
					iconCache.set(mod.folder, loadedIcon);
				}
			}

			if (loadedIcon != null)
			{
				var totalFrames:Int = Math.floor(loadedIcon.width / 150) * Math.floor(loadedIcon.height / 150);
				if (totalFrames > 1)
				{
					if (!cardAvatarApplied) applyCardAvatar(loadedIcon); // 卡片图标与右侧同源同缓存
					cardAvatarApplied = true;
					iconSpr.loadGraphic(loadedIcon, true, 150, 150);
					iconSpr.animation.add("icon", [for (i in 0...totalFrames) i], 10);
					iconSpr.animation.play("icon");
				}
				else
				{
					if (!cardAvatarApplied) applyCardAvatar(loadedIcon);
					cardAvatarApplied = true;
					iconSpr.loadGraphic(loadedIcon);
				}
			}
			else
				iconSpr.loadGraphic(Paths.image('unknownMod'));

			iconSpr.setGraphicSize(150, 150);
			iconSpr.updateHitbox();
		}
	}

	// 文本超出宽度时从尾部截断并加省略号，防止溢出到其他元素/屏幕外
	function clipText(t:FlxText, s:String, maxW:Float)
	{
		t.wordWrap = false;
		t.text = s;
		t.updateHitbox();
		var clipped:Bool = false;
		while (s.length > 1 && t.textField.textWidth > maxW)
		{
			clipped = true;
			s = s.substr(0, s.length - 1);
			t.text = s;
			t.updateHitbox();
		}
		if (clipped)
		{
			t.text = s + '…';
			t.updateHitbox();
		}
	}

	function updateButtons()
	{
		if (mods.length < 1)
		{
			for (btn in buttons) btn.visible = false;
			return;
		}
		for (btn in buttons) btn.visible = true;

		var isOn:Bool = (modsList[curSelected][1] == true);
		toggleBtn.setText(isOn ? '停用' : '启用');
		toggleBtn.setLabelColor(isOn ? 0xFF7BFF9E : DesignTokens.primary);
	}

	function toggleSelected()
	{
		if (mods.length < 1) return;
		mouseActive = true;
		if(mods[curSelected].restart) needaReset = true;
		modsList[curSelected][1] = !modsList[curSelected][1];
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		updateRows();
		updateInfo();
		updateButtons();
	}

	function moveMod(change:Int)
	{
		if(mods.length <= 1) return;
		mouseActive = true;

		var doRestart:Bool = (mods[0].restart);
		var newPos:Int = curSelected + change;
		if(newPos < 0)
		{
			modsList.push(modsList.shift());
			mods.push(mods.shift());
		}
		else if(newPos >= mods.length)
		{
			modsList.insert(0, modsList.pop());
			mods.insert(0, mods.pop());
		}
		else
		{
			var lastArray:Array<Dynamic> = modsList[curSelected];
			modsList[curSelected] = modsList[newPos];
			modsList[newPos] = lastArray;

			var lastMod:ModMetadata = mods[curSelected];
			mods[curSelected] = mods[newPos];
			mods[newPos] = lastMod;
		}

		if(!doRestart) doRestart = mods[curSelected].restart;
		if(doRestart) needaReset = true;

		changeSelection(change);
		updateRows();
		updateInfo();
		updateButtons();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	function setAllMods(on:Bool)
	{
		if (mods.length < 1) return;
		mouseActive = true;
		for (i in 0...modsList.length)
		{
			if(modsList[i][1] != on && mods[i].restart) needaReset = true;
			modsList[i][1] = on;
		}
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		updateRows();
		updateInfo();
		updateButtons();
	}

	// ===== 删除 Mod =====
	function deleteSelected()
	{
		if (mods.length < 1) return;
		mouseActive = true;
		var folder:String = mods[curSelected].folder;
		openSubState(new substates.ModsDeleteConfirmSubstate(mods[curSelected].name, function()
		{
			doDeleteMod(folder);
		}));
	}

	function doDeleteMod(folder:String)
	{
		// 1) 删除 mod 目录（不可恢复）
		try
		{
			deleteFolderRecursive(Paths.mods(folder));
		}
		catch (e:Dynamic)
		{
			trace('删除 Mod 目录失败：' + Std.string(e));
		}

		// 2) 从内存列表移除
		var idx:Int = -1;
		for (i in 0...mods.length)
		{
			if (mods[i].folder == folder)
			{
				idx = i;
				break;
			}
		}
		if (idx >= 0)
		{
			mods.remove(mods[idx]);
			modsList.remove(modsList[idx]);
			// 删除的是选中项（或选中项之前的项）→ 选中"上一个"：
			// 数组前移后 curSelected 若不回退，会指向"下一个" mod（用户期望上一个）
			if (idx <= curSelected && curSelected > 0)
				curSelected--;
		}
		if (curSelected >= mods.length) curSelected = mods.length > 0 ? mods.length - 1 : 0;

		// 3) 当前生效 mod 目录指向被删 mod 时清空
		if (Mods.currentModDirectory == folder) Mods.currentModDirectory = '';

		// 4) 写回 modsList.txt
		saveTxt();

		// 5) 刷新界面：changeSelection(0) 同步选中框(selectorBar)/滚动/背景色，
		//    再更新行内容与信息
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		changeSelection(0);
		updateRows();
		updateInfo();
		updateButtons();
		noModsTxt.visible = mods.length < 1;
		if (mods.length < 1) bg.color = defaultColor;
	}

	/** 递归删除目录/文件（只用于 mods/ 下的 mod 目录） */
	static function deleteFolderRecursive(path:String):Void
	{
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path))
		{
			for (entry in FileSystem.readDirectory(path))
				deleteFolderRecursive(path + '/' + entry);
			FileSystem.deleteDirectory(path);
		}
		else
			FileSystem.deleteFile(path);
	}

	function exitMods()
	{
		if(colorTween != null) colorTween.cancel();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		FlxG.mouse.visible = false;
		saveTxt();
		if(needaReset)
		{
			TitleState.initialized = false;
			TitleState.closedState = false;
			FlxG.sound.music.fadeOut(0.3);
			if(FreeplayState.vocals != null)
			{
				FreeplayState.vocals.fadeOut(0.3);
				FreeplayState.vocals = null;
			}
			FlxG.camera.fade(FlxColor.BLACK, 0.5, false, FlxG.resetGame, false);
		}
		else
		{
			MusicBeatState.switchState(new MainMenuState());
		}
	}

	function saveTxt()
	{
		var fileStr:String = '';
		for (values in modsList)
		{
			if(fileStr.length > 0) fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

		try {
			// 与 Mods.parseList 读取同一路径（安卓为外部存储 modsList.txt），
			// 否则保存到相对路径导致禁用/启用状态不生效
			File.saveContent(Mods.modsListPath(), fileStr);
		} catch(e:Dynamic) {
			trace('Could not save modsList.txt: $e');
		}
		Mods.pushGlobalMods();
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
		for (sw in switchCols)
			if (sw != null) sw.destroy();
		switchCols = [];

		FlxG.mouse.visible = false;
		super.destroy();
	}
}

// 磨砂玻璃小按钮
class ModsButton extends FlxSpriteGroup
{
	public var onClick:Void->Void;
	public var spr:FlxSprite;
	var label:FlxText;
	public var btnW:Float;
	public var btnH:Float;
	var hovered:Bool = false;
	var awake:Bool = false;
	var lastX:Float = 0;
	var lastY:Float = 0;
	var alphaTween:FlxTween;
	public function getLabelX():Float return label.x;
	public function getLabelY():Float return label.y;
	public function getLabelH():Float return label.height;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, ?cb:Void->Void)
	{
		super(x, y);
		onClick = cb;
		btnW = w;
		btnH = h;

		spr = new FlxSprite().makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, 14, 14, 0x66161622);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, 14, 14, FlxColor.TRANSPARENT, {color: 0x8CFFFFFF, thickness: 1.5});
		spr.alpha = 0.85;
		spr.scrollFactor.set();
		add(spr);

		label = new FlxText(0, 0, Std.int(w), text, 18);
		label.setFormat(Paths.font('future.ttf'), 18, 0xFFCFCFDC, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.5;
		label.textField.height = 44;
		label.scrollFactor.set();
		label.y = 12; // 按钮高 44，18px 文字垂直居中（固定值，不依赖字体度量）
		add(label);
		trace('[BTN] "' + text + '" lx=' + label.x + ' ly=' + label.y + ' lh=' + label.height + ' gx=' + x + ' gy=' + y);

		scrollFactor.set();
		lastX = FlxG.mouse.screenX;
		lastY = FlxG.mouse.screenY;
	}

	public function over(mx:Float, my:Float):Bool
	{
		if (!visible) return false;
		return mx >= x && mx <= x + btnW && my >= y && my <= y + btnH;
	}

	public function setHovered(mx:Float, my:Float)
	{
		if (!awake)
		{
			var dx:Float = mx - lastX;
			var dy:Float = my - lastY;
			if (dx * dx + dy * dy < 100) return;
			awake = true;
		}
		lastX = mx;
		lastY = my;

		var v:Bool = over(mx, my);
		if (hovered == v) return;
		hovered = v;
		if (alphaTween != null) { alphaTween.cancel(); alphaTween = null; }
		if (v)
			alphaTween = FlxTween.tween(spr, {alpha: 1}, 0.1, {ease: FlxEase.quadOut});
		else
			alphaTween = FlxTween.tween(spr, {alpha: 0.85}, 0.1, {ease: FlxEase.quadOut});
	}

	public function setText(t:String)
	{
		label.text = t;
		label.updateHitbox();
	}

	public function setLabelColor(c:FlxColor)
	{
		label.color = c;
	}
}

class ModMetadata
{
	public var folder:String;
	public var name:String;
	public var description:String;
	public var color:FlxColor;
	public var restart:Bool;
	public var alphabet:MenuText;
	public var icon:AttachedSprite;

	public function new(folder:String)
	{
		this.folder = folder;
		this.name = folder;
		this.description = "No description provided.";
		this.color = ModsMenuState.defaultColor;
		this.restart = false;

		//Try loading json
		var pack:Dynamic = Mods.getPack(folder);
		if(pack != null) {
			if(pack.name != null && pack.name.length > 0)
			{
				if(pack.name != 'Name')
					this.name = pack.name;
				else
					this.name = pack.folder;
			}

			if(pack.description != null && pack.description.length > 0)
			{
				if(pack.description != 'Description')
					this.description = pack.description;
				else
					this.description = "No description provided.";
			}

			if(pack.color != null)
				this.color = FlxColor.fromRGB(pack.color[0] != null ? pack.color[0] : 170,
											pack.color[1] != null ? pack.color[1] : 0,
											pack.color[2] != null ? pack.color[2] : 255);
			this.restart = pack.restart;
		}
	}
}
