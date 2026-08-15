package substates;

import backend.Highscore;

import flixel.math.FlxPoint;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxStringUtil;
import openfl.Lib;

class ResultsSubState extends MusicBeatSubstate
{
	// ===== 安全布局常量（与暂停界面同一套风格） =====
	static final LAYOUT_Y:Float = 120;       // 整体下移，让内容垂直居中
	static final TITLE_Y:Float = 22 + LAYOUT_Y - 35;  // 标题比面板高一些
	static final SAFE_MARGIN:Float = 72;
	static final INFO_PANEL_Y:Float = 70 + LAYOUT_Y;
	static final INFO_PANEL_H:Float = 200;
	static final INFO_Y_START:Float = INFO_PANEL_Y + 30;
	static final INFO_LINE_GAP:Float = 34;
	static final MENU_X:Float = 72;
	static final MENU_PANEL_Y:Float = 290 + LAYOUT_Y;
	static final MENU_Y:Float = MENU_PANEL_Y + 12;
	static final MENU_LINE_GAP:Float = 34;

	static final PANEL_X:Float = 40;
	static final PANEL_W:Float = 600;

	static final STATS_X:Float = 680;
	static final STATS_W:Float = 560;
	static final STATS_Y:Float = 70 + LAYOUT_Y;
	static final STATS_TEXT_X:Float = 716;
	static final STATS_TITLE_Y:Float = STATS_Y + 26;
	static final STATS_ROW_START:Float = STATS_Y + 88;
	static final STATS_ROW_GAP:Float = 48;

	public var resultAction:String = 'continue';

	var grpMenuShit:FlxTypedGroup<MenuText>;
	var menuItems:Array<String> = ['重试', '继续'];
	var curSelected:Int = 0;

	var menuSelector:FlxSprite;
	var menuSelectorTween:FlxTween;

	var mouseActive:Bool = true;  // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;

	#if mobile
	var touchDownRow:Int = -1;   // 触屏点选：按下时所在的行
	var touchDownID:Int = -1;    // 触屏点选：触摸点 ID
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

		// ---- 背景 ----
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		FlxTween.tween(bg, {alpha: 0.6}, 0.4, {ease: FlxEase.quartInOut});

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, '本局结算', 54);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 54, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		titleText.alpha = 0;
		add(titleText);
		FlxTween.tween(titleText, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.1});

		// ---- 左侧信息面板 ----
		var infoPanel:FlxSprite = makePanel(PANEL_X, INFO_PANEL_Y, PANEL_W, INFO_PANEL_H, 20);
		infoPanel.alpha = 0;
		add(infoPanel);
		FlxTween.tween(infoPanel, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.15});

		var songNameText:FlxText = makeInfoText('曲目：' + PlayState.SONG.song, INFO_Y_START);
		var diffText:FlxText = makeInfoText('难度：' + translateDifficulty(Difficulty.getString()), INFO_Y_START + INFO_LINE_GAP);
		var ratingText:FlxText = makeInfoText('评级：' + st.ratingName + fcText(st.ratingFC), INFO_Y_START + INFO_LINE_GAP * 2);
		var modeText:FlxText;
		var invalidResult:Bool = (st.usedAutoplay || st.usedGodMode);
		if (invalidResult)
		{
			var why:Array<String> = [];
			if (st.usedAutoplay) why.push('自动游玩');
			if (st.usedGodMode) why.push('上帝模式');
			modeText = makeInfoText(why.join(' + ') + '（成绩无效）', INFO_Y_START + INFO_LINE_GAP * 3, 0xFFFF6B6B);
		}
		else
			modeText = makeInfoText('正常模式', INFO_Y_START + INFO_LINE_GAP * 3);

		var infoTexts:Array<FlxText> = [songNameText, diffText, ratingText, modeText];
		for (i in 0...infoTexts.length)
		{
			var txt:FlxText = infoTexts[i];
			FlxTween.tween(txt, {alpha: 1, y: txt.y + 4}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.3 + i * 0.12});
		}

		// ---- 菜单面板（重试 / 继续） ----
		var panelHeight:Float = 16 + (menuItems.length * MENU_LINE_GAP * 1.3);
		var menuPanel:FlxSprite = makePanel(PANEL_X, MENU_PANEL_Y, PANEL_W, Std.int(panelHeight), 20);
		menuPanel.alpha = 0;
		add(menuPanel);
		FlxTween.tween(menuPanel, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.2});

		var hintText:FlxText = new FlxText(SAFE_MARGIN, MENU_PANEL_Y + panelHeight + 12, 0, getHintText(), 18);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), 18, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);

		// ---- 右侧统计面板（底部与菜单面板对齐） ----
		var statsPanelH:Float = (MENU_PANEL_Y + panelHeight) - STATS_Y;
		var statPanel:FlxSprite = makePanel(STATS_X, STATS_Y, STATS_W, Std.int(statsPanelH), 20);
		statPanel.alpha = 0;
		add(statPanel);
		FlxTween.tween(statPanel, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.25});

		var statTitle:FlxText = new FlxText(STATS_TEXT_X, STATS_TITLE_Y, 0, '本局数据', 26);
		statTitle.scrollFactor.set();
		statTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statTitle.borderSize = 2;
		statTitle.antialiasing = ClientPrefs.data.antialiasing;
		statTitle.alpha = 0;
		add(statTitle);
		FlxTween.tween(statTitle, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.35});

		var bestScore:Int = Highscore.getScore(PlayState.SONG.song, PlayState.storyDifficulty);
		if (!invalidResult && st.songScore >= bestScore && st.songScore > 0)
		{
			var newRecordText:FlxText = new FlxText(STATS_TEXT_X + 170, STATS_TITLE_Y + 4, 0, '新纪录！', 22);
			newRecordText.scrollFactor.set();
			newRecordText.setFormat(Paths.font('future.ttf'), 22, 0xFFFFD966, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			newRecordText.borderSize = 1.5;
			newRecordText.antialiasing = ClientPrefs.data.antialiasing;
			newRecordText.alpha = 0;
			add(newRecordText);
			FlxTween.tween(newRecordText, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.45});
		}

		var statDefs:Array<String> = ['当前分数', '最佳分数', '失误数', '命中 / 总音符', '准确度'];
		var statVals:Array<String> = [
			FlxStringUtil.formatMoney(st.songScore),
			FlxStringUtil.formatMoney(bestScore),
			Std.string(st.songMisses),
			Std.string(st.songHits) + ' / ' + Std.string(st.totalNotes),
			CoolUtil.floorDecimal(st.ratingPercent * 100, 2) + '%'
		];
		for (i in 0...statDefs.length)
		{
			var rowY:Float = STATS_ROW_START + (i * STATS_ROW_GAP);

			var lbl:FlxText = new FlxText(STATS_TEXT_X, rowY, 0, statDefs[i] + '：', 24);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), 24, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			lbl.alpha = 0;
			add(lbl);
			FlxTween.tween(lbl, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.4 + i * 0.06});

			var val:FlxText = new FlxText(STATS_TEXT_X + 210, rowY, 0, statVals[i], 24);
			val.scrollFactor.set();
			val.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			val.alpha = 0;
			add(val);
			FlxTween.tween(val, {alpha: 1}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.4 + i * 0.06});
		}

		// ---- 选中高亮条 ----
		menuSelector = makePanel(PANEL_X + 16, MENU_Y - 3, PANEL_W - 32, 44, 12, 0x2EFFFFFF, null);
		add(menuSelector);

		grpMenuShit = new FlxTypedGroup<MenuText>();
		add(grpMenuShit);
		for (i in 0...menuItems.length)
		{
			var item:MenuText = new MenuText(MENU_X, MENU_Y + (i * MENU_LINE_GAP * 1.3), menuItems[i], true, 34);
			item.isMenuItem = false;
			item.ID = i;
			grpMenuShit.add(item);
		}
		curSelected = 0;
		changeSelection();

		FlxG.mouse.visible = true;
		Lib.application.window.title = "FNF':Meteoric Engine - 结算";

		loadUIscripts('results');
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

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
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
		super.update(elapsed);

		var upP = controls.UI_UP_P;
		var downP = controls.UI_DOWN_P;
		var accepted = controls.ACCEPT;

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

			#if mobile
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

			if (FlxG.mouse.wheel != 0)
			{
				mouseActive = true;
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
			}

			if (hoveredID >= 0 && FlxG.mouse.justPressed)
			{
				mouseActive = true;
				if (hoveredID != curSelected) changeSelection(hoveredID - curSelected);
				accepted = true;
			}
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
			item.color = 0xFF9A9AA8;

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
			var barY:Float = MENU_Y - 3 + (curSelected * MENU_LINE_GAP * 1.3);
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
