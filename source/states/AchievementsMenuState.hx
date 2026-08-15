package states;

import objects.BackButton;
import backend.Achievements;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;

class AchievementsMenuState extends MusicBeatState
{
	#if ACHIEVEMENTS_ALLOWED
	// ===== 布局常量（与自由选歌/制作人员界面一致） =====
	static final PANEL_L_X:Float = 40;
	static final PANEL_L_Y:Float = 70;
	static final PANEL_L_W:Float = 680;
	static final PANEL_L_H:Float = 570;

	static final PANEL_R_X:Float = 740;
	static final PANEL_R_Y:Float = 70;
	static final PANEL_R_W:Float = 460;
	static final PANEL_R_H:Float = 570;

	static final LIST_X:Float = 92;      // 行图标 X
	static final LIST_Y:Float = 152;     // 第一行 Y
	static final ROW_GAP:Float = 56;     // 行距
	static final ROWS_VISIBLE:Int = 8;   // 可见行数
	static final NAME_X:Float = 152;     // 行名称 X
	static final ROW_ICON:Float = 44;    // 行图标尺寸

	static final ICON_X:Float = 890;     // 右侧大图标（居中）
	static final ICON_Y:Float = 140;
	static final ICON_SIZE:Float = 160;

	var achievementList:Array<Int> = [];  // achievementsStuff 索引（全部成就，含隐藏）
	var unlockedCount:Int = 0;

	var rows:Array<FlxText> = [];
	var rowIcons:Array<FlxSprite> = [];

	var bg:FlxSprite;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

	var bigIcon:FlxSprite;
	var nameText:FlxText;
	var statusText:FlxText;
	var descText:FlxText;
	var triggerLabel:FlxText;
	var triggerText:FlxText;
	var progressText:FlxText;
	var progressBg:FlxSprite;
	var progressFill:FlxSprite;

	var backBtn:BackButton;
	var mouseActive:Bool = true;  // 鼠标活跃：滚轮/点击可用；键盘操作后冻结
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var quitting:Bool = false;
	var holdTime:Float = 0;

	private static var curSelected:Int = 0;
	var scrollIndex:Int = 0;

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Achievements";

		#if desktop
		DiscordClient.changePresence("Achievements Menu", null);
		#end

		// ---- 背景 ----
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFF4A5C8C; // 成就主题色（蓝紫）
		add(bg);
		bg.screenCenter();

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 662, 1160, 48, 14));

		// ---- 面板标题 ----
		addTitle(PANEL_L_X + 48, 100, '成就列表');
		addTitle(PANEL_R_X + 32, 100, '成就详情');

		// ---- 成就数据 ----
		Achievements.loadAchievements();
		for (i in 0...Achievements.achievementsStuff.length)
		{
			achievementList.push(i);
			if (Achievements.isAchievementUnlocked(Achievements.achievementsStuff[i][2]))
				unlockedCount++;
		}

		// ---- 列表行（静态行：切换时只移动高亮条） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var icon:FlxSprite = new FlxSprite(LIST_X, LIST_Y + (r * ROW_GAP) + 2);
			icon.antialiasing = ClientPrefs.data.antialiasing;
			icon.scrollFactor.set();
			icon.visible = false;
			add(icon);
			rowIcons.push(icon);

			var row:FlxText = new FlxText(NAME_X, LIST_Y + (r * ROW_GAP), PANEL_L_W - 130, '', 26);
			row.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.scrollFactor.set();
			row.visible = false;
			add(row);
			rows.push(row);
		}

		// ---- 选中高亮条 ----
		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, 0x2EFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 右侧：大图标 ----
		bigIcon = new FlxSprite(ICON_X, ICON_Y);
		bigIcon.antialiasing = ClientPrefs.data.antialiasing;
		bigIcon.scrollFactor.set();
		add(bigIcon);

		// ---- 右侧：名称 / 状态 / 描述 ----
		nameText = new FlxText(PANEL_R_X + 30, 318, PANEL_R_W - 60, '', 30);
		nameText.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		nameText.borderSize = 2;
		nameText.scrollFactor.set();
		add(nameText);

		statusText = new FlxText(PANEL_R_X + 30, 358, PANEL_R_W - 60, '', 20);
		statusText.setFormat(Paths.font('future.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.borderSize = 2;
		statusText.scrollFactor.set();
		add(statusText);

		descText = new FlxText(PANEL_R_X + 30, 392, PANEL_R_W - 60, '', 20);
		descText.setFormat(Paths.font('future.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.borderSize = 2;
		descText.scrollFactor.set();
		add(descText);

		// ---- 右侧：触发方式 ----
		triggerLabel = new FlxText(PANEL_R_X + 30, 456, PANEL_R_W - 60, '触发方式', 16);
		triggerLabel.setFormat(Paths.font('future.ttf'), 16, 0xFF33E0FF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		triggerLabel.borderSize = 2;
		triggerLabel.scrollFactor.set();
		add(triggerLabel);

		triggerText = new FlxText(PANEL_R_X + 30, 478, PANEL_R_W - 60, '', 18);
		triggerText.setFormat(Paths.font('future.ttf'), 18, 0xFFD7D7E0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		triggerText.borderSize = 2;
		triggerText.scrollFactor.set();
		add(triggerText);

		// ---- 右侧：解锁进度条 ----
		progressText = new FlxText(PANEL_R_X + 30, 562, PANEL_R_W - 60, '', 16);
		progressText.setFormat(Paths.font('future.ttf'), 16, 0xFFD7D7E0, CENTER);
		progressText.scrollFactor.set();
		add(progressText);

		progressBg = new FlxSprite(PANEL_R_X + 50, 588).makeGraphic(360, 10, 0xFF1C2230);
		progressBg.scrollFactor.set();
		add(progressBg);

		progressFill = new FlxSprite(PANEL_R_X + 50, 588).makeGraphic(0, 10, 0xFF33E0FF);
		progressFill.scrollFactor.set();
		add(progressFill);

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(40, 672, 1160, '滚轮 / 方向键 选择 · ESC 返回', 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		// ---- 返回按钮（右上角） ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		if (curSelected >= achievementList.length) curSelected = 0;
		changeSelection();

		FlxG.mouse.visible = true;
		super.create();
	}

	function addTitle(x:Float, y:Float, text:String)
	{
		var t:FlxText = new FlxText(x, y, 0, text, 26);
		t.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.scrollFactor.set();
		t.antialiasing = ClientPrefs.data.antialiasing;
		add(t);
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		// unique：面板独立位图，避免与其他界面同尺寸面板共享位图而被重复绘制叠加变黑
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function getAchievementIdx(listIdx:Int):Int
	{
		return achievementList[listIdx];
	}

	function getTag(listIdx:Int):String
	{
		return Achievements.achievementsStuff[getAchievementIdx(listIdx)][2];
	}

	function isHidden(listIdx:Int):Bool
	{
		return Achievements.achievementsStuff[getAchievementIdx(listIdx)][3] == true;
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.7)
		{
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
		}

		if (!quitting)
		{
			var shiftMult:Int = 1;
			if (FlxG.keys.pressed.SHIFT) shiftMult = 3;

			if (controls.UI_UP_P)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.screenX;
				mouseLockY = FlxG.mouse.screenY;
				changeSelection(-shiftMult);
				holdTime = 0;
			}
			if (controls.UI_DOWN_P)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.screenX;
				mouseLockY = FlxG.mouse.screenY;
				changeSelection(shiftMult);
				holdTime = 0;
			}

			if (controls.UI_DOWN || controls.UI_UP)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.screenX;
				mouseLockY = FlxG.mouse.screenY;
				var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
				holdTime += elapsed;
				var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

				if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
				{
					changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
				}
			}

			if (!controls.controllerMode)
			{
				var clickPressed:Bool = FlxG.mouse.justPressed;
				#if mobile
				// 触屏：手指抬起且未滑动才算点击，拖动滚动列表时不误选
				clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
				#end

				// 键盘接管后，鼠标移动超过阈值才恢复鼠标操作
				if (!mouseActive)
				{
					var dx:Float = FlxG.mouse.screenX - mouseLockX;
					var dy:Float = FlxG.mouse.screenY - mouseLockY;
					if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
				}

				// 滚轮：每帧最多 1 格
				if (FlxG.mouse.wheel != 0)
				{
					mouseActive = true;
					changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
				}

				// 返回按钮：悬停发光，点击返回
				backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
				if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
				{
					mouseActive = true;
					quitting = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));
					MusicBeatState.switchState(new MainMenuState());
					return;
				}

				// 点击列表行：选中
				if (clickPressed)
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
					}
				}
			}

			if (controls.BACK)
			{
				quitting = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		super.update(elapsed);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}

	function getHoveredOptionID():Int
	{
		var hoveredID:Int = -1;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...rows.length)
		{
			var row:FlxText = rows[r];
			if (row.visible && mx >= row.x && mx <= row.x + row.width && my >= row.y && my <= row.y + row.height)
				hoveredID = scrollIndex + r;
		}
		return hoveredID;
	}

	function changeSelection(change:Int = 0)
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		curSelected += change;
		if (curSelected < 0)
			curSelected = achievementList.length - 1;
		if (curSelected >= achievementList.length)
			curSelected = 0;

		// 滚动窗口：只有越过可见区时才整页滚动
		if (curSelected < scrollIndex)
			scrollIndex = curSelected;
		else if (curSelected > scrollIndex + ROWS_VISIBLE - 1)
			scrollIndex = curSelected - ROWS_VISIBLE + 1;

		refreshRows();

		// ---- 右侧详情 ----
		var unlocked:Bool = Achievements.isAchievementUnlocked(getTag(curSelected));
		var hidden:Bool = isHidden(curSelected);

		var graphic = Paths.image('achievements/' + getTag(curSelected));
		if (graphic == null || !unlocked)
			graphic = Paths.image('achievements/lockedachievement');

		bigIcon.loadGraphic(graphic);
		bigIcon.setGraphicSize(Std.int(ICON_SIZE), Std.int(ICON_SIZE));
		bigIcon.updateHitbox();
		bigIcon.x = ICON_X;
		bigIcon.y = ICON_Y;

		nameText.text = (unlocked || !hidden) ? Achievements.achievementsStuff[getAchievementIdx(curSelected)][0] : '？？？';
		nameText.updateHitbox();

		if (unlocked)
		{
			statusText.text = '已解锁';
			statusText.color = 0xFF33E0FF;
		}
		else if (hidden)
		{
			statusText.text = '隐藏成就 · 未解锁';
			statusText.color = 0xFF8A93A5;
		}
		else
		{
			statusText.text = '未解锁';
			statusText.color = 0xFF8A93A5;
		}
		statusText.updateHitbox();

		descText.text = (unlocked || !hidden)
			? Achievements.achievementsStuff[getAchievementIdx(curSelected)][1]
			: '这是一个隐藏成就\n完成特定条件后解锁';
		descText.updateHitbox();

		triggerText.text = (unlocked || !hidden)
			? Achievements.achievementsStuff[getAchievementIdx(curSelected)][4]
			: '？？？';
		triggerText.updateHitbox();

		progressText.text = '已解锁 ' + unlockedCount + ' / ' + achievementList.length;
		progressText.updateHitbox();

		var ratio:Float = achievementList.length > 0 ? unlockedCount / achievementList.length : 0;
		progressFill.makeGraphic(Std.int(360 * ratio), 10, 0xFF33E0FF);
		progressFill.x = PANEL_R_X + 50;
		progressFill.y = 588;
		progressFill.scrollFactor.set();

		callUIScripts('onChangeSelection', [curSelected, getTag(curSelected)]);
	}

	function refreshRows()
	{
		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:FlxText = rows[r];
			var icon:FlxSprite = rowIcons[r];

			if (idx >= achievementList.length)
			{
				row.visible = false;
				icon.visible = false;
				continue;
			}

			var unlocked:Bool = Achievements.isAchievementUnlocked(getTag(idx));
			var hidden:Bool = isHidden(idx);
			var isSel:Bool = (idx == curSelected);

			row.visible = true;
			row.text = (unlocked || !hidden) ? Achievements.achievementsStuff[getAchievementIdx(idx)][0] : '？？？';
			row.alpha = isSel ? 1 : 0.55;
			row.color = unlocked ? (isSel ? FlxColor.WHITE : 0xFFD7D7E0) : 0xFF8A93A5;
			row.updateHitbox();

			var graphic = Paths.image('achievements/' + getTag(idx));
			if (graphic == null || !unlocked)
				graphic = Paths.image('achievements/lockedachievement');

			icon.loadGraphic(graphic);
			icon.setGraphicSize(Std.int(ROW_ICON), Std.int(ROW_ICON));
			icon.updateHitbox();
			icon.x = LIST_X;
			icon.y = LIST_Y + (r * ROW_GAP) + 2;
			icon.visible = true;
			icon.alpha = isSel ? 1 : 0.7;
		}

		var barY:Float = LIST_Y - 3 + ((curSelected - scrollIndex) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null)
		{
			selectorTween.cancel();
			selectorTween = null;
		}
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}
	#end
}
