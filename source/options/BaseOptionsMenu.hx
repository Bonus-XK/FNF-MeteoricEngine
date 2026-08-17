package options;

import objects.BackButton;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;

class BaseOptionsMenu extends MusicBeatSubstate
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

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFFea71fd;
		bg.screenCenter();
		bg.antialiasing = ClientPrefs.data.antialiasing;
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
			valueText.scrollFactor.set();
			valueText.visible = false;
			add(valueText);
			valueTexts.push(valueText);

			lastRowText.push('');
			lastValueText.push('');
			lastIsBool.push(false);
		}

		selectorBar = makePanel(LIST_X - 24, LIST_Y - 3, VALUE_X + VALUE_W - (LIST_X - 24), 44, 12, 0x3AFFFFFF, null);
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
		var val:Dynamic = option.getValue();
		if (option.type == 'percent') val *= 100;
		var def:Dynamic = option.defaultValue;
		return text.replace('%v', Std.string(val)).replace('%d', Std.string(def));
	}

	function updateTextFrom(option:Option) {
		refreshRows();
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

		// 鼠标
		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		// 触屏：手指抬起且未滑动才算点击，拖动滚动列表时不误选
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

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
			#if mobile
			// ◀ ▶ 按钮：FlxG.mouse 通道 + 300ms 冷却。instance 的触摸路径（dpad）触发时
			// 会在下方 nextAccept 块更新 lastPadBtnTap，本检测随即被冷却挡住，保证一次按下只触发一次。
			if (Lib.getTimer() - lastPadBtnTap > 300)
			{
				// ◀ 按钮：调节当前选项值（等效左方向键；bool 选项=切换，key 选项不可调）
				if (diffLeftBtn != null && FlxG.mouse.screenX >= diffLeftBtn.x && FlxG.mouse.screenX <= diffLeftBtn.x + diffLeftBtn.width
					&& FlxG.mouse.screenY >= diffLeftBtn.y && FlxG.mouse.screenY <= diffLeftBtn.y + diffLeftBtn.height)
				{
					lastPadBtnTap = Lib.getTimer();
					mouseActive = true;
					if (curOption != null && curOption.type == 'bool')
						toggleSelected();
					else if (curOption != null && curOption.type != 'key')
						changeOptionValue(-1);
				}
				else if (diffRightBtn != null && FlxG.mouse.screenX >= diffRightBtn.x && FlxG.mouse.screenX <= diffRightBtn.x + diffRightBtn.width
					&& FlxG.mouse.screenY >= diffRightBtn.y && FlxG.mouse.screenY <= diffRightBtn.y + diffRightBtn.height)
				{
					lastPadBtnTap = Lib.getTimer();
					mouseActive = true;
					if (curOption != null && curOption.type == 'bool')
						toggleSelected();
					else if (curOption != null && curOption.type != 'key')
						changeOptionValue(1);
				}
			}
			#end
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
		}

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
		FlxG.sound.play(Paths.sound('scrollMenu'));
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
