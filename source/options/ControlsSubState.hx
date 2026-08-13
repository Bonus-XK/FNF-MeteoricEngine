package options;

import objects.BackButton;
import backend.InputFormatter;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.FlxGridOverlay;
import flixel.util.FlxSpriteUtil;
import flixel.math.FlxRect;

import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.gamepad.FlxGamepadInputID;

class ControlsSubState extends MusicBeatSubstate
{
	// ===== 布局常量 =====
	static final PANEL_X:Float = 120;
	static final PANEL_Y:Float = 70;
	static final PANEL_W:Float = 1040;
	static final PANEL_H:Float = 580;

	static final LIST_X:Float = 160;     // 名称文字 X
	static final LIST_Y:Float = 170;     // 第一行 Y
	static final ROW_GAP:Float = 52;     // 行距
	static final ROWS_VISIBLE:Int = 9;   // 可见行数

	static final KEY_X:Float = 700;      // 主键位框 X
	static final KEY_GAP:Float = 250;    // 两个键位框间距
	static final KEY_W:Float = 210;
	static final KEY_H:Float = 42;

	//Show on gamepad - Display name - Save file key - Rebind display name
	var options:Array<Dynamic> = [
		[true, '音符键'],
		[true, '左', 'note_left', '音符 左'],
		[true, '下', 'note_down', '音符 下'],
		[true, '上', 'note_up', '音符 上'],
		[true, '右', 'note_right', '音符 右'],
		[true],
		[true, '界面'],
		[true, '左', 'ui_left', '界面 左'],
		[true, '下', 'ui_down', '界面 下'],
		[true, '上', 'ui_up', '界面 上'],
		[true, '右', 'ui_right', '界面 右'],
		[true],
		[true, '重置', 'reset', '重置'],
		[true, '确认', 'accept', '确认'],
		[true, '返回', 'back', '返回'],
		[true, '暂停', 'pause', '暂停'],
		[false],
		[false, '音量键'],
		[false, '静音', 'volume_mute', '音量 静音'],
		[false, '增大', 'volume_up', '音量 增大'],
		[false, '减小', 'volume_down', '音量 减小'],
		[false],
		[false, '调试键'],
		[false, '按键 1', 'debug_1', '调试按键 1'],
		[false, '按键 2', 'debug_2', '调试按键 2'],
		[true],
		[true],
		[true, '恢复默认按键']
	];
	var allRows:Array<Int> = [];         // 全列表：<0 标题/分隔（-i-1），>=0 可选项的 options 索引
	var curOptions:Array<Int> = [];      // 可选项的 options 索引
	var curOptionsValid:Array<Int> = []; // 可选项在全列表中的行号
	static var defaultKey:String = '恢复默认按键';

	var curSelected:Int = 0;
	var curAlt:Bool = false;
	var scrollIndex:Int = 0;
	var onKeyboardMode:Bool = true;

	var bg:FlxSprite;
	var colorTween:FlxTween;
	var keyboardColor:FlxColor = 0xff7192fd;
	var gamepadColor:FlxColor = 0xfffd7194;

	var rows:Array<FlxText> = [];          // 名称行
	var keyBoxes:Array<FlxSprite> = [];    // 键位磨砂框
	var keyTexts:Array<FlxText> = [];      // 键名文字
	var lastRowText:Array<String> = [];    // 缓存：避免未变化时重绘文字
	var lastRowTitle:Array<Bool> = [];
	var lastKeyText:Array<String> = [];
	var selectorBar:FlxSprite;             // 选中行高亮条
	var selectorTween:FlxTween;
	var keySelector:FlxSprite;             // 选中键位框高亮
	var keySelectorTween:FlxTween;

	var modeLinks:Array<FlxText> = [];     // 模式切换标签
	var modeRects:Array<FlxRect> = [];
	var modeOn:Array<Bool> = [false, false];
	var lastMX:Float = -9999;
	var lastMY:Float = -9999;
	var hoverWarm:Bool = false;

	var backBtn:BackButton;

	var binding:Bool = false;
	var holdingEsc:Float = 0;
	var bindingGroup:FlxSpriteGroup;

	var mouseActive:Bool = true;   // 键盘操作后冻结，鼠标移动/滚轮/点击恢复
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var holdTime:Float = 0;
	var timeForMoving:Float = 0.1; // 进入子状态先忽略输入，防控制器误触

	public function new()
	{
		super();

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = keyboardColor;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		var grid:FlxBackdrop = new FlxBackdrop(FlxGridOverlay.createGrid(80, 80, 160, 160, true, 0x33FFFFFF, 0x0));
		grid.velocity.set(40, 40);
		grid.alpha = 0;
		FlxTween.tween(grid, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
		add(grid);

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22));
		add(makePanel(120, 662, 1040, 48, 14));

		// ---- 标题 ----
		var title:FlxText = new FlxText(LIST_X, 100, 0, '按键设置', 30);
		title.setFormat(Paths.font('future.ttf'), 30, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.scrollFactor.set();
		add(title);

		// ---- 模式切换标签 ----
		addModeLink(820, 106, '> 键盘模式');
		addModeLink(1030, 106, '> 手柄模式');
		refreshModeLabels();

		// ---- 列表行 ----
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

			for (n in 0...2)
			{
				var box:FlxSprite = makePanel(KEY_X + n * KEY_GAP, LIST_Y - 6 + (r * ROW_GAP), KEY_W, KEY_H, 10, 0x66161622, 0x8CFFFFFF);
				box.visible = false;
				add(box);
				keyBoxes.push(box);

				var keyTxt:FlxText = new FlxText(KEY_X + n * KEY_GAP, LIST_Y + 2 + (r * ROW_GAP), KEY_W, '', 20);
				keyTxt.setFormat(Paths.font('future.ttf'), 20, 0xFFF0F0F8, CENTER);
				keyTxt.scrollFactor.set();
				keyTxt.visible = false;
				add(keyTxt);
				keyTexts.push(keyTxt);
			}
			lastRowText.push('');
			lastRowTitle.push(false);
			lastKeyText.push('');
			lastKeyText.push('');
		}

		// ---- 选中行高亮条 ----
		selectorBar = makePanel(LIST_X - 24, LIST_Y - 3, (KEY_X + KEY_GAP + KEY_W) - (LIST_X - 24), 44, 12, 0x3AFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 选中键位框高亮 ----
		keySelector = makePanel(0, 0, KEY_W + 8, KEY_H + 8, 12, 0x1EFFFFFF, 0xFFFFFFFF);
		keySelector.visible = false;
		add(keySelector);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(120, 672, 1040, '滚轮 / 方向键 选择 · 左/右 切换主备键 · Enter / 点击 绑定 · Ctrl 切换模式 · 点击 < 返回', 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		buildList();
		refreshList();
		FlxG.mouse.visible = true;
	}

	// ===== 列表构建 =====
	function buildList()
	{
		allRows = [];
		curOptions = [];
		curOptionsValid = [];
		var myID:Int = 0;
		for (i in 0...options.length)
		{
			var option:Array<Dynamic> = options[i];
			if (option[0] || onKeyboardMode)
			{
				if (option.length >= 3)
				{
					allRows.push(i);
					curOptions.push(i);
					curOptionsValid.push(myID);
				}
				else allRows.push(-(i + 1)); // 标题/分隔行
				myID++;
			}
		}
	}

	function refreshList()
	{
		var num:Int = curOptionsValid[curSelected];

		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:FlxText = rows[r];

			if (idx >= allRows.length)
			{
				row.visible = false;
				keyBoxes[r * 2].visible = false;
				keyBoxes[r * 2 + 1].visible = false;
				keyTexts[r * 2].visible = false;
				keyTexts[r * 2 + 1].visible = false;
				continue;
			}

			var optIdx:Int = allRows[idx];
			row.visible = true;

			if (optIdx < 0)
			{
				// 标题/分隔行
				var titleOption:Array<Dynamic> = options[-(optIdx + 1)];
				var titleText:String = (titleOption.length > 1) ? titleOption[1] : '';
				if (lastRowText[r] != titleText || !lastRowTitle[r])
				{
					lastRowText[r] = titleText;
					lastRowTitle[r] = true;
					row.text = titleText;
					row.fieldWidth = PANEL_W - 48;
					row.x = PANEL_X + 24;
					row.alignment = CENTER;
					row.updateHitbox();
				}
				row.alpha = 1;
				row.color = 0xFFFFD9A0;

				keyBoxes[r * 2].visible = false;
				keyBoxes[r * 2 + 1].visible = false;
				keyTexts[r * 2].visible = false;
				keyTexts[r * 2 + 1].visible = false;
			}
			else
			{
				var option:Array<Dynamic> = options[optIdx];
				var isSel:Bool = (idx == num);

				if (lastRowText[r] != option[1] || lastRowTitle[r])
				{
					lastRowText[r] = option[1];
					lastRowTitle[r] = false;
					row.text = option[1];
					row.fieldWidth = 0;
					row.x = LIST_X;
					row.alignment = LEFT;
					row.updateHitbox();
				}
				row.alpha = isSel ? 1 : 0.78;
				row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;

				for (n in 0...2)
				{
					keyBoxes[r * 2 + n].visible = true;
					keyTexts[r * 2 + n].visible = true;

					var key:String = null;
					if (onKeyboardMode)
					{
						var savKey:Array<Null<FlxKey>> = ClientPrefs.keyBinds.get(option[2]);
						key = InputFormatter.getKeyName((savKey[n] != null) ? savKey[n] : NONE);
					}
					else
					{
						var savKey:Array<Null<FlxGamepadInputID>> = ClientPrefs.gamepadBinds.get(option[2]);
						key = InputFormatter.getGamepadName((savKey[n] != null) ? savKey[n] : NONE);
					}

					var keyTxt:FlxText = keyTexts[r * 2 + n];
					if (lastKeyText[r * 2 + n] != key)
					{
						lastKeyText[r * 2 + n] = key;
						keyTxt.text = key;
						keyTxt.updateHitbox();
						keyTxt.scale.set(1, 1);
						if (keyTxt.width > KEY_W - 16)
							keyTxt.scale.x = (KEY_W - 16) / keyTxt.width;
					}
				}
			}
		}

		// 选中行高亮条
		var barY:Float = LIST_Y - 3 + ((num - scrollIndex) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});

		updateKeySelector();
	}

	function updateKeySelector()
	{
		var num:Int = curOptionsValid[curSelected];
		var selX:Float = KEY_X + (curAlt ? KEY_GAP : 0) - 4;
		var selY:Float = LIST_Y - 8 + ((num - scrollIndex) * ROW_GAP);
		keySelector.visible = true;
		if (keySelectorTween != null) { keySelectorTween.cancel(); keySelectorTween = null; }
		if (keySelector.x != selX || keySelector.y != selY)
			keySelectorTween = FlxTween.tween(keySelector, {x: selX, y: selY}, 0.12, {ease: FlxEase.cubeOut});
	}

	// ===== 选中移动 =====
	function changeSelection(move:Int = 0)
	{
		curSelected += move;
		if (curSelected < 0) curSelected = curOptions.length - 1;
		else if (curSelected >= curOptions.length) curSelected = 0;

		var num:Int = curOptionsValid[curSelected];
		if (num < scrollIndex) scrollIndex = num;
		else if (num > scrollIndex + ROWS_VISIBLE - 1) scrollIndex = num - ROWS_VISIBLE + 1;

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		refreshList();
	}

	function selectRow(rowID:Int)
	{
		var optIdx:Int = allRows[rowID];
		if (optIdx < 0) return;
		var newSel:Int = curOptions.indexOf(optIdx);
		if (newSel < 0) return;
		curSelected = newSel;
		refreshList();
	}

	// ===== 主循环 =====
	override function update(elapsed:Float)
	{
		if (timeForMoving > 0)
		{
			timeForMoving = Math.max(0, timeForMoving - elapsed);
			super.update(elapsed);
			return;
		}

		if (binding)
		{
			updateBinding(elapsed);
			super.update(elapsed);
			return;
		}

		// 键盘 / 手柄导航
		if (controls.BACK)
		{
			exitState();
			super.update(elapsed);
			return;
		}
		if (FlxG.keys.justPressed.CONTROL || FlxG.gamepads.anyJustPressed(LEFT_SHOULDER) || FlxG.gamepads.anyJustPressed(RIGHT_SHOULDER))
			swapMode();

		if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
		{
			takeKeyboardControl();
			updateAlt(true);
		}

		if (controls.UI_UP_P)
		{
			takeKeyboardControl();
			changeSelection(-1);
			holdTime = 0;
		}
		else if (controls.UI_DOWN_P)
		{
			takeKeyboardControl();
			changeSelection(1);
			holdTime = 0;
		}

		if (controls.UI_DOWN || controls.UI_UP)
		{
			takeKeyboardControl();
			var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
			holdTime += elapsed;
			var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);
			if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
				changeSelection(Std.int(Math.min(checkNewHold - checkLastHold, 1)) * (controls.UI_UP ? -1 : 1)); // 单帧最多移动 1 行，防止卡顿帧跳变
		}

		if (controls.ACCEPT)
		{
			takeKeyboardControl();
			activateSelected();
		}

		// 鼠标
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
		}

		if (FlxG.mouse.wheel != 0)
		{
			mouseActive = true;
			changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
		}

		// 模式标签悬停（鼠标移动才判定）
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		if (mx != lastMX || my != lastMY)
		{
			lastMX = mx;
			lastMY = my;
			if (!hoverWarm)
			{
				hoverWarm = true;
				modeOn[0] = overModeLink(0);
				modeOn[1] = overModeLink(1);
			}
			else
			{
				for (i in 0...modeLinks.length)
				{
					var on:Bool = overModeLink(i);
					if (on && !modeOn[i]) setModeHovered(i, true);
					else if (!on && modeOn[i]) setModeHovered(i, false);
					modeOn[i] = on;
				}
			}
		}

		backBtn.setHovered(mx, my);
		if (FlxG.mouse.justPressed)
		{
			if (backBtn.over(mx, my))
			{
				mouseActive = true;
				exitState();
				super.update(elapsed);
				return;
			}

			if (overModeLink(0))
			{
				mouseActive = true;
				if (!onKeyboardMode) swapMode();
			}
			else if (overModeLink(1))
			{
				mouseActive = true;
				if (onKeyboardMode) swapMode();
			}

			// 点击键位框：直接绑定该位置
			var boxHit:Array<Int> = getHoveredKeyBox();
			if (boxHit != null)
			{
				mouseActive = true;
				selectRow(boxHit[0]);
				if (curAlt != (boxHit[1] == 1)) updateAlt(true);
				startBinding();
				super.update(elapsed);
				return;
			}

			// 点击行：选中；点击已选中的行则执行
			var rowID:Int = getHoveredRowID();
			if (rowID >= 0)
			{
				mouseActive = true;
				if (rowID != curOptionsValid[curSelected])
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					selectRow(rowID);
					holdTime = 0;
				}
				else
				{
					activateSelected();
				}
			}
		}

		super.update(elapsed);
	}

	function takeKeyboardControl()
	{
		mouseActive = false;
		mouseLockX = FlxG.mouse.screenX;
		mouseLockY = FlxG.mouse.screenY;
	}

	function activateSelected()
	{
		var option:Array<Dynamic> = options[curOptions[curSelected]];
		if (option[1] == defaultKey)
		{
			// 恢复默认
			ClientPrefs.resetKeys(!onKeyboardMode);
			ClientPrefs.reloadVolumeKeys();
			buildList();
			refreshList();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
		else
		{
			startBinding();
		}
	}

	// ===== 绑定流程 =====
	function startBinding()
	{
		var option:Array<Dynamic> = options[curOptions[curSelected]];
		if (option[1] == defaultKey) return;

		binding = true;
		holdingEsc = 0;
		ClientPrefs.toggleVolumeKeys(false);
		FlxG.sound.play(Paths.sound('scrollMenu'));

		bindingGroup = new FlxSpriteGroup();

		var black:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		black.alpha = 0.6;
		bindingGroup.add(black);

		var pw:Float = 640;
		var ph:Float = 280;
		var px:Float = (FlxG.width - pw) / 2;
		var py:Float = (FlxG.height - ph) / 2;
		bindingGroup.add(makePanel(px, py, pw, ph, 22));

		var title:FlxText = new FlxText(px, py + 60, pw, '正在绑定：' + option[3], 36);
		title.setFormat(Paths.font('future.ttf'), 36, 0xFFFFFFFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		bindingGroup.add(title);

		var tip:FlxText = new FlxText(px, py + 170, pw, '按任意键 绑定\n长按 ESC 取消 · 长按 BACKSPACE 删除\n点击 取消绑定', 22);
		tip.setFormat(Paths.font('future.ttf'), 22, 0xFF9CE8FF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		tip.borderSize = 2;
		bindingGroup.add(tip);

		add(bindingGroup);
	}

	function updateBinding(elapsed:Float)
	{
		var altNum:Int = curAlt ? 1 : 0;
		var curOption:Array<Dynamic> = options[curOptions[curSelected]];

		if (FlxG.mouse.justPressed)
		{
			// 点击取消绑定
			closeBinding();
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		if (FlxG.keys.pressed.ESCAPE || FlxG.gamepads.anyPressed(B))
		{
			holdingEsc += elapsed;
			if (holdingEsc > 0.5)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				closeBinding();
			}
		}
		else if (FlxG.keys.pressed.BACKSPACE || FlxG.gamepads.anyPressed(BACK))
		{
			holdingEsc += elapsed;
			if (holdingEsc > 0.5)
			{
				if (onKeyboardMode)
					ClientPrefs.keyBinds.get(curOption[2])[altNum] = NONE;
				else
					ClientPrefs.gamepadBinds.get(curOption[2])[altNum] = NONE;
				ClientPrefs.clearInvalidKeys(curOption[2]);
				refreshList();
				FlxG.sound.play(Paths.sound('cancelMenu'));
				closeBinding();
			}
		}
		else
		{
			holdingEsc = 0;
			var changed:Bool = false;

			if (onKeyboardMode)
			{
				if (FlxG.keys.justPressed.ANY || FlxG.keys.justReleased.ANY)
				{
					var keyPressed:Int = FlxG.keys.firstJustPressed();
					var keyReleased:Int = FlxG.keys.firstJustReleased();
					if (keyPressed > -1 && keyPressed != FlxKey.ESCAPE && keyPressed != FlxKey.BACKSPACE)
					{
						ClientPrefs.keyBinds.get(curOption[2])[altNum] = keyPressed;
						changed = true;
					}
					else if (keyReleased > -1 && (keyReleased == FlxKey.ESCAPE || keyReleased == FlxKey.BACKSPACE))
					{
						ClientPrefs.keyBinds.get(curOption[2])[altNum] = keyReleased;
						changed = true;
					}
				}
			}
			else if (FlxG.gamepads.anyJustPressed(ANY) || FlxG.gamepads.anyJustPressed(LEFT_TRIGGER) || FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER) || FlxG.gamepads.anyJustReleased(ANY))
			{
				var keyPressed:Null<FlxGamepadInputID> = NONE;
				var keyReleased:Null<FlxGamepadInputID> = NONE;
				if (FlxG.gamepads.anyJustPressed(LEFT_TRIGGER)) keyPressed = LEFT_TRIGGER;
				else if (FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER)) keyPressed = RIGHT_TRIGGER;
				else
				{
					for (i in 0...FlxG.gamepads.numActiveGamepads)
					{
						var gamepad:FlxGamepad = FlxG.gamepads.getByID(i);
						if (gamepad != null)
						{
							keyPressed = gamepad.firstJustPressedID();
							keyReleased = gamepad.firstJustReleasedID();

							if (keyPressed == null) keyPressed = NONE;
							if (keyReleased == null) keyReleased = NONE;
							if (keyPressed != NONE || keyReleased != NONE) break;
						}
					}
				}

				if (keyPressed != NONE && keyPressed != FlxGamepadInputID.BACK && keyPressed != FlxGamepadInputID.B)
				{
					ClientPrefs.gamepadBinds.get(curOption[2])[altNum] = keyPressed;
					changed = true;
				}
				else if (keyReleased != NONE && (keyReleased == FlxGamepadInputID.BACK || keyReleased == FlxGamepadInputID.B))
				{
					ClientPrefs.gamepadBinds.get(curOption[2])[altNum] = keyReleased;
					changed = true;
				}
			}

			if (changed)
			{
				if (onKeyboardMode)
				{
					var curKeys:Array<Null<FlxKey>> = ClientPrefs.keyBinds.get(curOption[2]);
					if (curKeys[altNum] == curKeys[1 - altNum])
						curKeys[1 - altNum] = FlxKey.NONE;
				}
				else
				{
					var curButtons:Array<Null<FlxGamepadInputID>> = ClientPrefs.gamepadBinds.get(curOption[2]);
					if (curButtons[altNum] == curButtons[1 - altNum])
						curButtons[1 - altNum] = FlxGamepadInputID.NONE;
				}

				ClientPrefs.clearInvalidKeys(curOption[2]);
				refreshList();
				FlxG.sound.play(Paths.sound('confirmMenu'));
				closeBinding();
			}
		}
	}

	function closeBinding()
	{
		binding = false;
		if (bindingGroup != null)
		{
			remove(bindingGroup);
			bindingGroup.destroy();
			bindingGroup = null;
		}
		ClientPrefs.reloadVolumeKeys();
	}

	// ===== 模式切换 =====
	function swapMode()
	{
		if (colorTween != null) colorTween.cancel();
		colorTween = FlxTween.color(bg, 0.5, bg.color, onKeyboardMode ? gamepadColor : keyboardColor, {ease: FlxEase.linear});

		onKeyboardMode = !onKeyboardMode;
		curSelected = 0;
		curAlt = false;
		scrollIndex = 0;
		hoverWarm = false;
		modeOn[0] = false;
		modeOn[1] = false;
		buildList();
		refreshList();
		refreshModeLabels();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function refreshModeLabels()
	{
		modeLinks[0].color = onKeyboardMode ? FlxColor.WHITE : 0xFF9CE8FF;
		modeLinks[1].color = onKeyboardMode ? 0xFFFFD9A0 : FlxColor.WHITE;
	}

	function setModeHovered(idx:Int, hovered:Bool)
	{
		if (hovered) modeLinks[idx].color = FlxColor.WHITE;
		else refreshModeLabels();
	}

	function updateAlt(?doSwap:Bool = false)
	{
		if (doSwap)
		{
			curAlt = !curAlt;
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		updateKeySelector();
	}

	// ===== 鼠标命中 =====
	function getHoveredRowID():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = rows[r];
			if (!row.visible) continue;
			var idx:Int = scrollIndex + r;
			if (allRows[idx] < 0) continue;
			if (mx >= LIST_X - 24 && mx <= KEY_X - 20 && my >= row.y - 8 && my <= row.y + 40)
				return idx;
		}
		return -1;
	}

	function getHoveredKeyBox():Array<Int>
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			if (idx >= allRows.length || allRows[idx] < 0) continue;
			for (n in 0...2)
			{
				var box:FlxSprite = keyBoxes[r * 2 + n];
				if (!box.visible) continue;
				if (mx >= box.x && mx <= box.x + box.width && my >= box.y && my <= box.y + box.height)
					return [idx, n];
			}
		}
		return null;
	}

	function overModeLink(idx:Int):Bool
	{
		var r:FlxRect = modeRects[idx];
		return FlxG.mouse.screenX >= r.x && FlxG.mouse.screenX <= r.x + r.width
			&& FlxG.mouse.screenY >= r.y && FlxG.mouse.screenY <= r.y + r.height;
	}

	function addModeLink(x:Float, y:Float, text:String)
	{
		var t:FlxText = new FlxText(x, y, 0, text, 26);
		t.setFormat(Paths.font('future.ttf'), 26, 0xFF9CE8FF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 2;
		t.antialiasing = true;
		add(t);
		modeLinks.push(t);
		modeRects.push(new FlxRect(x, y, t.width, t.height));
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

	function exitState()
	{
		if (binding) closeBinding();
		FlxG.mouse.visible = false;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		close();
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
