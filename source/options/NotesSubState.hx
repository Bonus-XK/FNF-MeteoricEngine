package options;

import objects.MenuText;
import objects.BackButton;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.math.FlxPoint;
import flixel.util.FlxGradient;
import flixel.util.FlxSpriteUtil;
import lime.system.Clipboard;
import objects.StrumNote;
import objects.Note;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

class NotesSubState extends MusicBeatSubstate
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

	static final MODE_X:Float = 227;
	static final MODE_Y:Float = 165;
	static final MODE_GAP:Float = 110;
	static final MODE_SIZE:Float = 85;

	static final NOTE_X:Float = 177;
	static final NOTE_Y:Float = 305;
	static final NOTE_GAP:Float = 135;
	static final NOTE_SIZE:Float = 102;

	static final WHEEL_X:Float = 820;
	static final WHEEL_Y:Float = 170;
	static final WHEEL_SIZE:Float = 300;

	static final GRADIENT_X:Float = 758;
	static final GRADIENT_Y:Float = 170;
	static final GRADIENT_W:Float = 46;
	static final GRADIENT_H:Float = 300;

	static final PALETTE_X:Float = 776;
	static final PALETTE_Y:Float = 568;
	static final PALETTE_SCALE:Float = 18;

	var onModeColumn:Bool = true;
	var curSelectedMode:Int = 0;
	var curSelectedNote:Int = 0;
	var onPixel:Bool = false;
	var dataArray:Array<Array<FlxColor>>;

	var hexTypeLine:FlxSprite;
	var hexTypeNum:Int = -1;
	var hexTypeVisibleTimer:Float = 0;

	var copyButton:FlxSprite;
	var pasteButton:FlxSprite;

	var colorGradient:FlxSprite;
	var colorGradientSelector:FlxSprite;
	var colorPalette:FlxSprite;
	var colorWheel:FlxSprite;
	var colorWheelSelector:FlxSprite;

	var alphabetR:MenuText;
	var alphabetG:MenuText;
	var alphabetB:MenuText;
	var alphabetHex:MenuText;
	var lastR:String = '';
	var lastG:String = '';
	var lastB:String = '';
	var lastHex:String = '';
	var lastHexColor:FlxColor = FlxColor.WHITE;

	var modeSelector:FlxSprite;
	var noteSelector:FlxSprite;
	var selectorTween:FlxTween;

	var skinNote:FlxSprite;
	var modeNotes:FlxTypedGroup<FlxSprite>;
	var myNotes:FlxTypedGroup<StrumNote>;
	var bigNote:Note;

	var backBtn:BackButton;

	var mouseActive:Bool = true;   // 键盘操作后冻结，鼠标明显移动后恢复
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var timeForMoving:Float = 0.1; // 进入子状态先忽略输入，防控制器误触

	// controller support
	var controllerPointer:FlxSprite;
	var _lastControllerMode:Bool = false;

	var _storedColor:FlxColor;
	var holdingOnObj:FlxSprite;

	var allowedTypeKeys:Map<FlxKey, String> = [
		ZERO => '0', ONE => '1', TWO => '2', THREE => '3', FOUR => '4', FIVE => '5', SIX => '6', SEVEN => '7', EIGHT => '8', NINE => '9',
		NUMPADZERO => '0', NUMPADONE => '1', NUMPADTWO => '2', NUMPADTHREE => '3', NUMPADFOUR => '4', NUMPADFIVE => '5', NUMPADSIX => '6',
		NUMPADSEVEN => '7', NUMPADEIGHT => '8', NUMPADNINE => '9', A => 'A', B => 'B', C => 'C', D => 'D', E => 'E', F => 'F'];

	public function new()
	{
		super();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFFEA71FD;
		bg.screenCenter();
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);

		var grid:FlxBackdrop = new FlxBackdrop(FlxGridOverlay.createGrid(80, 80, 160, 160, true, 0x33FFFFFF, 0x0));
		grid.velocity.set(40, 40);
		grid.alpha = 0;
		FlxTween.tween(grid, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
		add(grid);

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(120, 662, 1040, 48, 14));

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(108, 96, 0, '箭头配色', 30);
		titleText.setFormat(Paths.font('future.ttf'), 30, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		titleText.scrollFactor.set();
		add(titleText);

		var rightTitle:FlxText = new FlxText(PANEL_R_X + 32, 96, 0, '颜色编辑', 26);
		rightTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rightTitle.borderSize = 2;
		rightTitle.scrollFactor.set();
		add(rightTitle);

		// ---- 选中高亮框（模式 / 音符） ----
		modeSelector = makePanel(MODE_X - 9, MODE_Y - 9, MODE_SIZE + 18, MODE_SIZE + 18, 18, 0x3AFFFFFF, null);
		modeSelector.visible = false;
		add(modeSelector);

		noteSelector = makePanel(NOTE_X - 8, NOTE_Y - 8, NOTE_SIZE + 16, NOTE_SIZE + 16, 20, 0x3AFFFFFF, null);
		noteSelector.visible = false;
		add(noteSelector);

		modeNotes = new FlxTypedGroup<FlxSprite>();
		add(modeNotes);

		myNotes = new FlxTypedGroup<StrumNote>();
		add(myNotes);

		// ---- 模式标签 R / G / B ----
		for (i in 0...3)
		{
			var lab:MenuText = new MenuText(MODE_X + MODE_GAP * i + MODE_SIZE / 2 - 30, 258, i == 0 ? 'R' : (i == 1 ? 'G' : 'B'), true);
			lab.fieldWidth = 60;
			lab.alignment = 'center';
			lab.setScale(0.4);
			lab.color = i == 0 ? 0xFFFF6B6B : (i == 1 ? 0xFF6BFF8F : 0xFF6BB5FF);
			add(lab);
		}

		// ---- 音符编号 ----
		for (i in 0...4)
		{
			var lab:MenuText = new MenuText(NOTE_X + NOTE_GAP * i + NOTE_SIZE / 2 - 20, 408, Std.string(i + 1), true);
			lab.fieldWidth = 40;
			lab.alignment = 'center';
			lab.setScale(0.35);
			add(lab);
		}

		// ---- 右侧：复制 / 粘贴 ----
		copyButton = new FlxSprite(1004, 92).loadGraphic(Paths.image('noteColorMenu/copy'));
		copyButton.alpha = 0.6;
		add(copyButton);

		pasteButton = new FlxSprite(1080, 92).loadGraphic(Paths.image('noteColorMenu/paste'));
		pasteButton.alpha = 0.6;
		add(pasteButton);

		// ---- 亮度渐变条 ----
		colorGradient = FlxGradient.createGradientFlxSprite(Std.int(GRADIENT_W), Std.int(GRADIENT_H), [FlxColor.WHITE, FlxColor.BLACK]);
		colorGradient.setPosition(GRADIENT_X, GRADIENT_Y);
		add(colorGradient);

		colorGradientSelector = new FlxSprite(GRADIENT_X - 10, GRADIENT_Y).makeGraphic(Std.int(GRADIENT_W + 20), 10, FlxColor.WHITE);
		colorGradientSelector.offset.y = 5;
		add(colorGradientSelector);

		// ---- 调色板 ----
		colorPalette = new FlxSprite(PALETTE_X, PALETTE_Y).loadGraphic(Paths.image('noteColorMenu/palette', false));
		colorPalette.scale.set(PALETTE_SCALE, PALETTE_SCALE);
		colorPalette.updateHitbox();
		colorPalette.antialiasing = false;
		add(colorPalette);

		// ---- 色轮 ----
		colorWheel = new FlxSprite(WHEEL_X, WHEEL_Y).loadGraphic(Paths.image('noteColorMenu/colorWheel'));
		colorWheel.setGraphicSize(Std.int(WHEEL_SIZE), Std.int(WHEEL_SIZE));
		colorWheel.updateHitbox();
		add(colorWheel);

		colorWheelSelector = new FlxShapeCircle(0, 0, 8, {thickness: 0}, FlxColor.WHITE);
		colorWheelSelector.offset.set(8, 8);
		colorWheelSelector.alpha = 0.6;
		add(colorWheelSelector);

		// ---- RGB 数值 ----
		alphabetR = makeColorAlphabet(792, 486);
		alphabetG = makeColorAlphabet(937, 486);
		alphabetB = makeColorAlphabet(1082, 486);

		var labR:MenuText = makeColorAlphabet(762, 487, 0.35);
		labR.text = 'R';
		labR.color = 0xFFFF6B6B;
		labR.updateHitbox();
		var labG:MenuText = makeColorAlphabet(907, 487, 0.35);
		labG.text = 'G';
		labG.color = 0xFF6BFF8F;
		labG.updateHitbox();
		var labB:MenuText = makeColorAlphabet(1052, 487, 0.35);
		labB.text = 'B';
		labB.color = 0xFF6BB5FF;
		labB.updateHitbox();

		// ---- HEX 输入 ----
		alphabetHex = makeColorAlphabet(812, 534, 0.5);
		var labHex:MenuText = makeColorAlphabet(762, 536, 0.35);
		labHex.text = 'HEX';
		labHex.color = 0xFFD7D7E0;
		labHex.updateHitbox();

		hexTypeLine = new FlxSprite(0, 556).makeGraphic(5, 40, FlxColor.WHITE);
		hexTypeLine.visible = false;
		add(hexTypeLine);

		// ---- 主体 ----
		spawnNotes();
		updateNotes(true);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(120, 674, 1040, '滚轮 / 左右 选择箭头 · R 重置当前 · SHIFT+R 重置全部 · CTRL 切换像素 · 点击 < 返回', 16);
		hint.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hint.borderSize = 2;
		hint.scrollFactor.set();
		add(hint);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 手柄虚拟光标 ----
		controllerPointer = new FlxShapeCircle(0, 0, 20, {thickness: 0}, FlxColor.WHITE);
		controllerPointer.offset.set(20, 20);
		controllerPointer.screenCenter();
		controllerPointer.alpha = 0.6;
		add(controllerPointer);

		FlxG.mouse.visible = !controls.controllerMode;
		controllerPointer.visible = controls.controllerMode;
		_lastControllerMode = controls.controllerMode;
	}

	override function update(elapsed:Float)
	{
		if (timeForMoving > 0)
		{
			timeForMoving = Math.max(0, timeForMoving - elapsed);
			super.update(elapsed);
			return;
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		super.update(elapsed);

		// Early controller checking
		if (FlxG.gamepads.anyJustPressed(ANY)) controls.controllerMode = true;
		else if (FlxG.mouse.justPressed || FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0) controls.controllerMode = false;

		var changedToController:Bool = false;
		if (controls.controllerMode != _lastControllerMode)
		{
			FlxG.mouse.visible = !controls.controllerMode;
			controllerPointer.visible = controls.controllerMode;
			if (controls.controllerMode)
			{
				controllerPointer.x = FlxG.mouse.x;
				controllerPointer.y = FlxG.mouse.y;
				changedToController = true;
			}
			_lastControllerMode = controls.controllerMode;
		}

		var analogX:Float = 0;
		var analogY:Float = 0;
		var analogMoved:Bool = false;
		if (controls.controllerMode && (changedToController || FlxG.gamepads.anyInput()))
		{
			for (gamepad in FlxG.gamepads.getActiveGamepads())
			{
				analogX = gamepad.getXAxis(LEFT_ANALOG_STICK);
				analogY = gamepad.getYAxis(LEFT_ANALOG_STICK);
				analogMoved = (analogX != 0 || analogY != 0);
				if (analogMoved) break;
			}
			controllerPointer.x = Math.max(0, Math.min(FlxG.width, controllerPointer.x + analogX * 1000 * elapsed));
			controllerPointer.y = Math.max(0, Math.min(FlxG.height, controllerPointer.y + analogY * 1000 * elapsed));
		}
		var controllerPressed:Bool = (controls.controllerMode && controls.ACCEPT);

		// 键盘操作后冻结鼠标，鼠标明显移动后恢复
		if (controls.UI_LEFT_P || controls.UI_RIGHT_P || controls.UI_UP_P || controls.UI_DOWN_P || controls.RESET || FlxG.keys.justPressed.CONTROL)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
		}
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > 100) mouseActive = true;
		}

		// 滚轮切换音符（触屏上手指拖动也会合成滚轮事件，拖动调色/滚动时不切换选中音符）
		if (FlxG.mouse.wheel != 0 && holdingOnObj == null)
		{
			#if mobile
			var wheelClick:Bool = !Main.touchWasDragging();
			#else
			var wheelClick:Bool = true;
			#end
			if (wheelClick)
			{
				mouseActive = true;
				hexTypeNum = -1;
				changeSelectionNote(FlxG.mouse.wheel > 0 ? -1 : 1);
			}
		}

		// 返回按钮
		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (FlxG.mouse.justPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		// CTRL 切换像素 / 非像素
		if (FlxG.keys.justPressed.CONTROL)
		{
			onPixel = !onPixel;
			spawnNotes();
			updateNotes(true);
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}

		// HEX 输入模式
		if (hexTypeNum > -1)
		{
			var keyPressed:FlxKey = cast (FlxG.keys.firstJustPressed(), FlxKey);
			hexTypeVisibleTimer += elapsed;
			var changed:Bool = false;
			if (changed = FlxG.keys.justPressed.LEFT)
				hexTypeNum--;
			else if (changed = FlxG.keys.justPressed.RIGHT)
				hexTypeNum++;
			else if (allowedTypeKeys.exists(keyPressed))
			{
				var curColor:String = alphabetHex.text;
				var newColor:String = curColor.substring(0, hexTypeNum) + allowedTypeKeys.get(keyPressed) + curColor.substring(hexTypeNum + 1);

				var colorHex:FlxColor = FlxColor.fromString('#' + newColor);
				setShaderColor(colorHex);
				_storedColor = getShaderColor();
				updateColors();

				hexTypeNum++;
				changed = true;
			}
			else if (FlxG.keys.justPressed.ENTER)
				hexTypeNum = -1;

			var end:Bool = false;
			if (changed)
			{
				if (hexTypeNum > 5) //Typed last letter
				{
					hexTypeNum = -1;
					end = true;
					hexTypeLine.visible = false;
				}
				else
				{
					if (hexTypeNum < 0) hexTypeNum = 0;
					else if (hexTypeNum > 5) hexTypeNum = 5;
					centerHexTypeLine();
					hexTypeLine.visible = true;
				}
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			}
			if (!end) hexTypeLine.visible = Math.floor(hexTypeVisibleTimer * 2) % 2 == 0;
		}
		else
		{
			var add:Int = 0;
			if (analogX == 0 && !changedToController)
			{
				if (controls.UI_LEFT_P) add = -1;
				else if (controls.UI_RIGHT_P) add = 1;
			}

			if (analogY == 0 && !changedToController && (controls.UI_UP_P || controls.UI_DOWN_P))
			{
				onModeColumn = !onModeColumn;
				updateNotes();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}

			if (add != 0)
			{
				if (onModeColumn) changeSelectionMode(add);
				else changeSelectionNote(add);
			}
			hexTypeLine.visible = false;
		}

		// Copy/Paste buttons
		var generalMoved:Bool = (FlxG.mouse.justMoved || analogMoved);
		var generalPressed:Bool = (FlxG.mouse.justPressed || controllerPressed);
		// 触屏：手指抬起且未滑动才算点击（拖动只操作颜色控件，不切换选中音符）
		var clickPressed:Bool = generalPressed;
		#if mobile
		if (!controls.controllerMode)
			clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end
		if (generalMoved)
		{
			copyButton.alpha = 0.6;
			pasteButton.alpha = 0.6;
		}

		if (pointerOverlaps(copyButton))
		{
			copyButton.alpha = 1;
			if (generalPressed)
			{
				Clipboard.text = getShaderColor().toHexString(false, false);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			}
			hexTypeNum = -1;
		}
		else if (pointerOverlaps(pasteButton))
		{
			pasteButton.alpha = 1;
			if (generalPressed)
			{
				var formattedText:String = Clipboard.text.trim().toUpperCase().replace('#', '').replace('0x', '');
				var newColor:Null<FlxColor> = FlxColor.fromString('#' + formattedText);
				if (newColor != null && formattedText.length == 6)
				{
					setShaderColor(newColor);
					_storedColor = getShaderColor();
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					updateColors();
				}
				else //errored
					FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			}
			hexTypeNum = -1;
		}

		// 点击：选择模式 / 音符
		if (clickPressed)
		{
			// 点按 HEX 输入框不算切换选择，不重置输入状态
			if (!(pointerY() >= 530 && pointerY() < 570 && pointerX() >= 800 && pointerX() <= 1120))
				hexTypeNum = -1;
			if (pointerOverlaps(modeNotes))
			{
				modeNotes.forEachAlive(function(note:FlxSprite) {
					if (curSelectedMode != note.ID && pointerOverlaps(note))
					{
						curSelectedMode = note.ID;
						onModeColumn = true;
						_storedColor = getShaderColor();
						updateNotes();
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					}
				});
			}
			else if (pointerOverlaps(myNotes))
			{
				myNotes.forEachAlive(function(note:StrumNote) {
					if (curSelectedNote != note.ID && pointerOverlaps(note))
					{
						curSelectedNote = note.ID;
						onModeColumn = false;
						bigNote.rgbShader.parent = Note.globalRgbShaders[note.ID];
						bigNote.shader = Note.globalRgbShaders[note.ID].shader;
						_storedColor = getShaderColor();
						updateNotes();
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					}
				});
			}
		}

		// 按下：开始操作颜色控件 / 其它按钮
		if (generalPressed)
		{
			hexTypeNum = -1;
			if (pointerOverlaps(colorWheel))
			{
				_storedColor = getShaderColor();
				holdingOnObj = colorWheel;
			}
			else if (pointerOverlaps(colorGradient))
			{
				_storedColor = getShaderColor();
				holdingOnObj = colorGradient;
			}
			else if (pointerOverlaps(colorPalette))
			{
				var palX:Int = Std.int(FlxMath.bound((pointerX() - colorPalette.x) / PALETTE_SCALE, 0, colorPalette.pixels.width - 1));
				var palY:Int = Std.int(FlxMath.bound((pointerY() - colorPalette.y) / PALETTE_SCALE, 0, colorPalette.pixels.height - 1));
				setShaderColor(colorPalette.pixels.getPixel32(palX, palY));
				_storedColor = getShaderColor();
				holdingOnObj = colorPalette;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				updateColors();
			}
			else if (pointerOverlaps(skinNote))
			{
				onPixel = !onPixel;
				spawnNotes();
				updateNotes(true);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			}
			else if (pointerY() >= 530 && pointerY() < 570 && pointerX() >= 800 && pointerX() <= 1120)
			{
				hexTypeNum = 0;
				var charWidth:Float = alphabetHex.width / alphabetHex.text.length;
				for (i in 0...alphabetHex.text.length)
				{
					if (alphabetHex.x + (i + 1) * charWidth <= pointerX()) hexTypeNum++;
					else break;
				}
				if (hexTypeNum > 5) hexTypeNum = 5;
				hexTypeLine.visible = true;
				centerHexTypeLine();
			}
			else holdingOnObj = null;
		}

		// holding
		if (holdingOnObj != null)
		{
			if (FlxG.mouse.justReleased || (controls.controllerMode && controls.justReleased('accept')))
			{
				holdingOnObj = null;
				_storedColor = getShaderColor();
				updateColors();
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			}
			else if (generalMoved || generalPressed)
			{
				if (holdingOnObj == colorGradient)
				{
					var newBrightness:Float = 1 - FlxMath.bound((pointerY() - colorGradient.y) / colorGradient.height, 0, 1);
					_storedColor.alpha = 1;
					if (_storedColor.brightness == 0) //prevent bug
						setShaderColor(FlxColor.fromRGBFloat(newBrightness, newBrightness, newBrightness));
					else
						setShaderColor(FlxColor.fromHSB(_storedColor.hue, _storedColor.saturation, newBrightness));
					updateColors(_storedColor);
				}
			else if (holdingOnObj == colorWheel)
			{
				var center:FlxPoint = new FlxPoint(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
				var mouse:FlxPoint = pointerFlxPoint();
				var hue:Float = FlxMath.wrap(FlxMath.wrap(Std.int(mouse.degreesTo(center)), 0, 360) - 90, 0, 360);
				var sat:Float = FlxMath.bound(mouse.dist(center) / colorWheel.width * 2, 0, 1);
				if (sat != 0) setShaderColor(FlxColor.fromHSB(hue, sat, _storedColor.brightness));
				else setShaderColor(FlxColor.fromRGBFloat(_storedColor.brightness, _storedColor.brightness, _storedColor.brightness));
				updateColors();
			}
			else if (holdingOnObj == colorPalette)
			{
				var palX:Int = Std.int(FlxMath.bound((pointerX() - colorPalette.x) / PALETTE_SCALE, 0, colorPalette.pixels.width - 1));
				var palY:Int = Std.int(FlxMath.bound((pointerY() - colorPalette.y) / PALETTE_SCALE, 0, colorPalette.pixels.height - 1));
				setShaderColor(colorPalette.pixels.getPixel32(palX, palY));
				_storedColor = getShaderColor();
				updateColors();
			}
		}
		}
		else if (controls.RESET && hexTypeNum < 0)
		{
			if (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyJustPressed(LEFT_SHOULDER))
			{
				for (i in 0...3)
				{
					var strumRGB:RGBShaderReference = myNotes.members[curSelectedNote].rgbShader;
					var color:FlxColor = !onPixel ? ClientPrefs.defaultData.arrowRGB[curSelectedNote][i] : ClientPrefs.defaultData.arrowRGBPixel[curSelectedNote][i];
					switch (i)
					{
						case 0:
							getShader().r = strumRGB.r = color;
						case 1:
							getShader().g = strumRGB.g = color;
						case 2:
							getShader().b = strumRGB.b = color;
					}
					dataArray[curSelectedNote][i] = color;
				}
			}
			setShaderColor(!onPixel ? ClientPrefs.defaultData.arrowRGB[curSelectedNote][curSelectedMode] : ClientPrefs.defaultData.arrowRGBPixel[curSelectedNote][curSelectedMode]);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			updateColors();
		}
	}

	function pointerOverlaps(obj:Dynamic)
	{
		if (!controls.controllerMode) return FlxG.mouse.overlaps(obj);
		return FlxG.overlap(controllerPointer, obj);
	}

	function pointerX():Float
	{
		if (!controls.controllerMode) return FlxG.mouse.x;
		return controllerPointer.x;
	}
	function pointerY():Float
	{
		if (!controls.controllerMode) return FlxG.mouse.y;
		return controllerPointer.y;
	}
	function pointerFlxPoint():FlxPoint
	{
		if (!controls.controllerMode) return FlxG.mouse.getScreenPosition();
		return controllerPointer.getScreenPosition();
	}

	function centerHexTypeLine()
	{
		var charWidth:Float = alphabetHex.width / alphabetHex.text.length;
		hexTypeLine.x = alphabetHex.x + hexTypeNum * charWidth + hexTypeLine.width;
		hexTypeVisibleTimer = 0;
	}

	function changeSelectionMode(change:Int = 0)
	{
		curSelectedMode += change;
		if (curSelectedMode < 0) curSelectedMode = 2;
		if (curSelectedMode >= 3) curSelectedMode = 0;

		onModeColumn = true;
		updateNotes();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function changeSelectionNote(change:Int = 0)
	{
		curSelectedNote += change;
		if (curSelectedNote < 0) curSelectedNote = dataArray.length - 1;
		if (curSelectedNote >= dataArray.length) curSelectedNote = 0;

		onModeColumn = false;
		bigNote.rgbShader.parent = Note.globalRgbShaders[curSelectedNote];
		bigNote.shader = Note.globalRgbShaders[curSelectedNote].shader;
		updateNotes();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	// alphabets
	function makeColorAlphabet(x:Float = 0, y:Float = 0, ?scale:Float = 0.5):MenuText
	{
		var text:MenuText = new MenuText(x, y, '', true);
		text.alignment = 'left';
		text.setScale(scale);
		add(text);
		return text;
	}

	// notes sprites functions
	public function spawnNotes()
	{
		dataArray = !onPixel ? ClientPrefs.data.arrowRGB : ClientPrefs.data.arrowRGBPixel;
		if (onPixel) PlayState.stageUI = 'pixel';

		// clear groups
		modeNotes.forEachAlive(function(note:FlxSprite) {
			note.kill();
			note.destroy();
		});
		myNotes.forEachAlive(function(note:StrumNote) {
			note.kill();
			note.destroy();
		});
		modeNotes.clear();
		myNotes.clear();

		if (skinNote != null)
		{
			remove(skinNote);
			skinNote.destroy();
		}
		if (bigNote != null)
		{
			remove(bigNote);
			bigNote.destroy();
		}

		// respawn stuff
		var res:Int = onPixel ? 160 : 17;
		skinNote = new FlxSprite(636, 88).loadGraphic(Paths.image('noteColorMenu/' + (onPixel ? 'note' : 'notePixel')), true, res, res);
		skinNote.antialiasing = ClientPrefs.data.antialiasing;
		skinNote.setGraphicSize(56);
		skinNote.updateHitbox();
		skinNote.animation.add('anim', [0], 24, true);
		skinNote.animation.play('anim', true);
		if (!onPixel) skinNote.antialiasing = false;
		add(skinNote);

		var res:Int = !onPixel ? 160 : 17;
		for (i in 0...3)
		{
			var newNote:FlxSprite = new FlxSprite(MODE_X + MODE_GAP * i, MODE_Y).loadGraphic(Paths.image('noteColorMenu/' + (!onPixel ? 'note' : 'notePixel')), true, res, res);
			newNote.antialiasing = ClientPrefs.data.antialiasing;
			newNote.setGraphicSize(Std.int(MODE_SIZE));
			newNote.updateHitbox();
			newNote.animation.add('anim', [i], 24, true);
			newNote.animation.play('anim', true);
			newNote.ID = i;
			if (onPixel) newNote.antialiasing = false;
			modeNotes.add(newNote);
		}

		Note.globalRgbShaders = [];
		for (i in 0...dataArray.length)
		{
			Note.initializeGlobalRGBShader(i);
			var newNote:StrumNote = new StrumNote(NOTE_X + NOTE_GAP * i, NOTE_Y, i, 0);
			newNote.useRGBShader = true;
			newNote.setGraphicSize(Std.int(NOTE_SIZE));
			newNote.updateHitbox();
			newNote.ID = i;
			myNotes.add(newNote);
		}

		bigNote = new Note(0, 0, false, true);
		bigNote.setPosition(280, 430);
		bigNote.setGraphicSize(200);
		bigNote.updateHitbox();
		bigNote.rgbShader.parent = Note.globalRgbShaders[curSelectedNote];
		bigNote.shader = Note.globalRgbShaders[curSelectedNote].shader;
		for (i in 0...Note.colArray.length)
		{
			if (!onPixel) bigNote.animation.addByPrefix('note$i', Note.colArray[i] + '0', 24, true);
			else bigNote.animation.add('note$i', [i + 4], 24, true);
		}
		insert(members.indexOf(myNotes) + 1, bigNote);
		_storedColor = getShaderColor();
		PlayState.stageUI = 'normal';
	}

	function updateNotes(?instant:Bool = false)
	{
		for (note in modeNotes)
			note.alpha = (curSelectedMode == note.ID) ? 1 : 0.55;

		for (note in myNotes)
		{
			var newAnim:String = curSelectedNote == note.ID ? 'confirm' : 'pressed';
			note.alpha = (curSelectedNote == note.ID) ? 1 : 0.55;
			if (note.animation.curAnim == null || note.animation.curAnim.name != newAnim) note.playAnim(newAnim, true);
			if (instant) note.animation.curAnim.finish();
		}
		bigNote.animation.play('note$curSelectedNote', true);

		moveSelector(modeSelector, MODE_X + MODE_GAP * curSelectedMode - 9, MODE_Y - 9, onModeColumn);
		moveSelector(noteSelector, NOTE_X + NOTE_GAP * curSelectedNote - 8, NOTE_Y - 8, !onModeColumn);
		updateColors();
	}

	function moveSelector(bar:FlxSprite, x:Float, y:Float, visible:Bool)
	{
		bar.visible = visible;
		if (bar.x == x && bar.y == y) return;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		selectorTween = FlxTween.tween(bar, {x: x, y: y}, 0.12, {ease: FlxEase.cubeOut});
	}

	function updateColors(specific:Null<FlxColor> = null)
	{
		var color:FlxColor = getShaderColor();
		var wheelColor:FlxColor = specific == null ? color : specific;

		var r:String = Std.string(color.red);
		var g:String = Std.string(color.green);
		var b:String = Std.string(color.blue);
		var hex:String = color.toHexString(false, false);
		if (lastR != r) { lastR = r; alphabetR.text = r; alphabetR.updateHitbox(); }
		if (lastG != g) { lastG = g; alphabetG.text = g; alphabetG.updateHitbox(); }
		if (lastB != b) { lastB = b; alphabetB.text = b; alphabetB.updateHitbox(); }
		if (lastHex != hex || lastHexColor != color) { lastHex = hex; lastHexColor = color; alphabetHex.text = hex; alphabetHex.color = color; alphabetHex.updateHitbox(); }

		colorWheel.color = FlxColor.fromHSB(0, 0, color.brightness);
		colorWheelSelector.setPosition(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
		if (wheelColor.brightness != 0)
		{
			var hueWrap:Float = wheelColor.hue * Math.PI / 180;
			colorWheelSelector.x += Math.sin(hueWrap) * colorWheel.width / 2 * wheelColor.saturation;
			colorWheelSelector.y -= Math.cos(hueWrap) * colorWheel.height / 2 * wheelColor.saturation;
		}
		colorGradientSelector.y = colorGradient.y + colorGradient.height * (1 - color.brightness);

		var strumRGB:RGBShaderReference = myNotes.members[curSelectedNote].rgbShader;
		switch (curSelectedMode)
		{
			case 0:
				getShader().r = strumRGB.r = color;
			case 1:
				getShader().g = strumRGB.g = color;
			case 2:
				getShader().b = strumRGB.b = color;
		}
	}

	function setShaderColor(value:FlxColor) dataArray[curSelectedNote][curSelectedMode] = value;
	function getShaderColor() return dataArray[curSelectedNote][curSelectedMode];
	function getShader() return Note.globalRgbShaders[curSelectedNote];

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
