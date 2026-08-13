package states;

import backend.WeekData;
import backend.Mods;

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
	// ===== 布局常量 =====
	static final PANEL_L_X:Float = 40;
	static final PANEL_L_Y:Float = 70;
	static final PANEL_L_W:Float = 680;
	static final PANEL_L_H:Float = 570;

	static final PANEL_R_X:Float = 740;
	static final PANEL_R_Y:Float = 70;
	static final PANEL_R_W:Float = 460;
	static final PANEL_R_H:Float = 570;

	static final LIST_X:Float = 88;
	static final LIST_Y:Float = 152;
	static final ROW_GAP:Float = 56;
	static final ROWS_VISIBLE:Int = 8;

	static final CHECK_X:Float = 56;
	static final CHECK_SIZE:Float = 26;
	static final VALUE_X:Float = 540;
	static final VALUE_W:Float = 160;

	static final INFO_X:Float = 772;
	static final INFO_W:Float = 400;

	var mods:Array<ModMetadata> = [];
	var modsList:Array<Dynamic> = [];
	static var needaReset = false;
	private static var curSelected:Int = 0;
	public static var defaultColor:FlxColor = 0xFF665AFF;

	var rows:Array<MenuText> = [];
	var checkBgs:Array<FlxSprite> = [];
	var checkFills:Array<FlxSprite> = [];
	var statusTexts:Array<FlxText> = [];
	var lastRowText:Array<String> = [];
	var lastStatus:Array<String> = [];
	var scrollIndex:Int = 0;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

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
	var buttons:Array<ModsButton> = [];
	var hasModsUI:Array<FlxSprite> = []; // 有 Mod 时才显示的元素

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

			var checkBg:FlxSprite = makePanel(CHECK_X, LIST_Y + 4 + (r * ROW_GAP), CHECK_SIZE, CHECK_SIZE, 7, 0x66161622, 0x8CFFFFFF);
			checkBg.visible = false;
			add(checkBg);
			checkBgs.push(checkBg);

			var checkFill:FlxSprite = makePanel(CHECK_X + 6, LIST_Y + 10 + (r * ROW_GAP), CHECK_SIZE - 12, CHECK_SIZE - 12, 4, 0xFFFFFFFF, null);
			checkFill.visible = false;
			add(checkFill);
			checkFills.push(checkFill);

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

		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, 0x2EFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

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
		allOnBtn = new ModsButton(772, 590, 190, 44, '全部启用', function() { setAllMods(true); });
		allOffBtn = new ModsButton(972, 590, 190, 44, '全部禁用', function() { setAllMods(false); });

		buttons = [toggleBtn, upBtn, downBtn, allOnBtn, allOffBtn];
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

		// ---- 加载 Mod 列表 ----
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

		if(curSelected >= mods.length) curSelected = 0;

		if(mods.length < 1)
			bg.color = defaultColor;
		else
			bg.color = mods[curSelected].color;
		intendedColor = bg.color;

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
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		if (FlxG.mouse.wheel != 0)
		{
			mouseActive = true;
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
			updateRows();
			updateInfo();
			updateButtons();
		}

		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (FlxG.mouse.justPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			mouseActive = true;
			exitMods();
			return;
		}

		if (FlxG.mouse.justPressed)
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

			// 复选框
			var checkID:Int = getHoveredCheckbox();
			if (checkID >= 0)
			{
				mouseActive = true;
				if (checkID != curSelected)
				{
					changeSelection(checkID - curSelected);
					updateRows();
				}
				toggleSelected();
				return;
			}

			// 行点击：未选中则选中，已选中则启用/停用
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
				else
					toggleSelected();
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
			var bgSpr:FlxSprite = checkBgs[r];
			if (!bgSpr.visible) continue;
			if (mx >= bgSpr.x - 6 && mx <= bgSpr.x + bgSpr.width + 6 && my >= bgSpr.y - 6 && my <= bgSpr.y + bgSpr.height + 6)
				return scrollIndex + r;
		}
		return -1;
	}

	// ===== 列表逻辑 =====
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

		if (curSelected < scrollIndex)
			scrollIndex = curSelected;
		else if (curSelected > scrollIndex + ROWS_VISIBLE - 1)
			scrollIndex = curSelected - ROWS_VISIBLE + 1;

		var newColor:Int = mods[curSelected].color;
		if(newColor != intendedColor)
		{
			if(colorTween != null) { colorTween.cancel(); colorTween = null; }
			intendedColor = newColor;
			colorTween = FlxTween.color(bg, 0.4, bg.color, intendedColor, {ease: FlxEase.quadOut});
		}

		var barY:Float = LIST_Y - 3 + ((curSelected - scrollIndex) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

	function updateRows()
	{
		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:MenuText = rows[r];
			if (idx >= mods.length)
			{
				row.visible = false;
				checkBgs[r].visible = false;
				checkFills[r].visible = false;
				statusTexts[r].visible = false;
				continue;
			}

			var mod:ModMetadata = mods[idx];
			var isSel:Bool = (idx == curSelected);
			var isOn:Bool = (modsList[idx][1] == true);

			row.visible = true;
			if (lastRowText[r] != mod.name)
			{
				lastRowText[r] = mod.name;
				clipText(row, mod.name, VALUE_X - LIST_X - 24);
			}
			row.alpha = isSel ? 1 : 0.78;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;

			checkBgs[r].visible = true;
			checkBgs[r].alpha = isSel ? 1 : 0.85;
			checkFills[r].visible = isOn;

			statusTexts[r].visible = true;
			statusTexts[r].y = rows[r].y + 2; // 始终与所在行对齐
			trace('[STATUS] r=' + r + ' y=' + statusTexts[r].y + ' h=' + statusTexts[r].height + ' th=' + statusTexts[r].textField.textHeight);
			var status:String = isOn ? '已启用' : '已停用';
			if (lastStatus[r] != status)
			{
				lastStatus[r] = status;
				statusTexts[r].text = status;
				statusTexts[r].updateHitbox();
			}
			statusTexts[r].alpha = isSel ? 1 : 0.75;
			statusTexts[r].color = isOn ? 0xFF7BFF9E : 0xFF9A9AA8;
		}
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
		clipText(folderText, '文件夹：' + mod.folder, INFO_W - 20);

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
					iconSpr.loadGraphic(loadedIcon, true, 150, 150);
					iconSpr.animation.add("icon", [for (i in 0...totalFrames) i], 10);
					iconSpr.animation.play("icon");
				}
				else
					iconSpr.loadGraphic(loadedIcon);
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
		toggleBtn.setLabelColor(isOn ? 0xFF7BFF9E : 0xFFFF8F8F);
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
			File.saveContent('modsList.txt', fileStr);
		} catch(e:Dynamic) {
			trace('Could not save modsList.txt: $e');
		}
		Mods.pushGlobalMods();
	}

	// ===== 工具 =====
	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
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
