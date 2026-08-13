package options;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxRect;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

import objects.Character;
import objects.HealthBar;
import objects.HealthIcon;
import objects.Note;
import objects.PhigrosJudgeLine;
import objects.StrumNote;
import objects.TimeBar;

import states.stages.StageWeek1 as BackgroundStage;

/**
 * 自定义界面（HUD 布局）：
 * 在设置中打开，模拟游玩 HUD（音符、时间条、血量条、计分文字），
 * 玩家可拖动/微调这些元素的位置，保存到 ClientPrefs.data.hudLayout，进歌后自动套用。
 */
class HUDCustomizeState extends MusicBeatState
{
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;

	// 模拟 HUD 元素
	var strumLineNotes:Array<StrumNote> = []; // 0-3 对手，4-7 玩家
	var phigrosJudgeLine:PhigrosJudgeLine;
	var timeBar:TimeBar;
	var timeTxt:FlxText;
	var healthBar:HealthBar;
	var iconP1:HealthIcon;
	var iconP2:HealthIcon;
	var scoreTxt:FlxText;
	var songTxt:FlxText; // 左下角水印

	// 编辑 UI
	static final TITLE_Y:Float = 4;
	static final PANEL_X:Float = 160;
	static final PANEL_Y:Float = 604;
	static final PANEL_W:Float = 960;
	static final PANEL_H:Float = 80;

	var elements:Array<String> = ['timeBar', 'healthBar', 'score', 'watermark', 'note'];
	var elementNames:Map<String, String> = [
		'note' => '音符',
		'timeBar' => '时间条',
		'healthBar' => '血量条',
		'score' => '计分文字',
		'watermark' => '水印'
	];

	var borders:Array<Array<FlxSprite>> = [];
	var labels:Array<FlxText> = [];
	var curSelected:Int = 0;

	var dragging:Bool = false;
	var lastMouseX:Float = 0;
	var lastMouseY:Float = 0;

	var hintText:FlxText;
	var doneBtn:FlxSprite;
	var doneLabel:FlxText;

	override public function create()
	{
		// ---- 相机（与调整延迟界面一致） ----
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);

		FlxG.cameras.setDefaultDrawTarget(camGame, true);
		CustomFadeTransition.nextCamera = camOther;
		FlxG.camera.scroll.set(120, 130);

		persistentUpdate = true;
		FlxG.sound.pause();

		// ---- 模拟舞台与角色 ----
		Paths.setCurrentLevel('week1');
		new BackgroundStage();
		var gf:Character = new Character(400, 130, 'gf');
		gf.x += gf.positionArray[0];
		gf.y += gf.positionArray[1];
		gf.scrollFactor.set(0.95, 0.95);
		var boyfriend:Character = new Character(770, 100, 'bf', true);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
		add(gf);
		add(boyfriend);

		// ---- 模拟 HUD ----
		createSimulatedHUD();
		repositionHUD();

		// ---- 编辑边框与标签 ----
		for (i in 0...elements.length)
		{
			var bars:Array<FlxSprite> = [];
			for (j in 0...4)
			{
				var bar:FlxSprite = new FlxSprite().makeGraphic(3, 3, FlxColor.WHITE);
				bar.scrollFactor.set();
				bar.cameras = [camOther];
				add(bar);
				bars.push(bar);
			}
			borders.push(bars);

			var lbl:FlxText = new FlxText(0, 0, 0, elementNames[elements[i]], 20);
			lbl.scrollFactor.set();
			lbl.cameras = [camOther];
			lbl.setFormat(Paths.font('future.ttf'), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			labels.push(lbl);
		}

		// ---- 顶部说明条 ----
		var blackBox:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 44, FlxColor.BLACK);
		blackBox.scrollFactor.set();
		blackBox.alpha = 0.6;
		blackBox.cameras = [camOther];
		add(blackBox);

		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, '自定义界面 —— 拖动 HUD 元素调整位置（方向键微调 · Shift 加速 10px · R 重置全部 · ESC 完成）', 22);
		titleText.scrollFactor.set();
		titleText.cameras = [camOther];
		titleText.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 1.5;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		// ---- 底部信息面板 + 完成按钮 ----
		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 18);
		panel.cameras = [camOther];
		add(panel);

		hintText = new FlxText(PANEL_X + 28, PANEL_Y + 26, PANEL_W - 240, '', 22);
		hintText.scrollFactor.set();
		hintText.cameras = [camOther];
		hintText.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);

		doneBtn = makePanel(PANEL_X + PANEL_W - 176, PANEL_Y + 18, 140, 44, 12, 0x3AFFFFFF, 0x88FFFFFF);
		doneBtn.cameras = [camOther];
		add(doneBtn);

		doneLabel = new FlxText(doneBtn.x, doneBtn.y + 9, doneBtn.width, '完成', 24);
		doneLabel.scrollFactor.set();
		doneLabel.cameras = [camOther];
		doneLabel.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		doneLabel.borderSize = 1.5;
		doneLabel.antialiasing = ClientPrefs.data.antialiasing;
		add(doneLabel);

		refreshBorders();
		updateHint();

		Conductor.bpm = 128.0;
		FlxG.sound.playMusic(Paths.music('offsetSong'), 1, true);

		super.create();
		FlxG.mouse.visible = true;
	}

	function createSimulatedHUD():Void
	{
		var phigros:Bool = ClientPrefs.data.phigrosStyle;

		// 音符（对手 0-3，玩家 4-7）
		for (p in 0...2)
		{
			for (i in 0...4)
			{
				var strum:StrumNote = new StrumNote(0, 0, i, p);
				strum.downScroll = ClientPrefs.data.downScroll && !phigros;
				strum.playAnim('static');
				strum.cameras = [camHUD];
				if (phigros)
					strum.alpha = 0; // Phigros 下箭头隐藏，仅作锚点
				else if (p == 0)
					strum.alpha = ClientPrefs.data.opponentStrums ? (ClientPrefs.data.middleScroll ? 0.35 : 1) : 0;
				add(strum);
				strumLineNotes.push(strum);
			}
		}

		if (phigros)
		{
			phigrosJudgeLine = new PhigrosJudgeLine();
			phigrosJudgeLine.cameras = [camHUD];
			add(phigrosJudgeLine);
		}

		// 时间条 + 时间文字
		timeBar = new TimeBar(0, 0, function() return 0.5, 0, 1, ClientPrefs.data.newTimeBarStyle);
		timeBar.scrollFactor.set();
		timeBar.cameras = [camHUD];
		if (ClientPrefs.data.newTimeBarStyle)
			timeBar.leftBar.color = 0xFF00FFFF;
		else
			timeBar.leftBar.color = 0xFFFF0000;
		add(timeBar);

		timeTxt = new FlxText(0, 0, 400, '1:23', 25);
		timeTxt.setFormat(Paths.font('vcr.ttf'), 25, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.cameras = [camHUD];
		add(timeTxt);

		// 血量条 + 图标
		healthBar = new HealthBar(0, 0, 'healthBar', function() return 1.0, 0, 2, ClientPrefs.data.oldHealthBar);
		healthBar.scrollFactor.set();
		healthBar.leftToRight = false;
		healthBar.cameras = [camHUD];
		healthBar.setColors(0xFF66FF33, 0xFFFF0000);
		add(healthBar);

		iconP1 = new HealthIcon('bf', true);
		iconP1.cameras = [camHUD];
		add(iconP1);

		iconP2 = new HealthIcon('dad', false);
		iconP2.cameras = [camHUD];
		add(iconP2);

		// 计分文字
		scoreTxt = new FlxText(0, 0, FlxG.width, 'Score: 12345 | Misses: 0 | Rating: A', 20);
		scoreTxt.setFormat(Paths.font('vcr.ttf'), 15, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.cameras = [camHUD];
		add(scoreTxt);

		// 左下角水印
		songTxt = new FlxText(0, 0, 0, 'Test Song (Hard) | 流星引擎', 12);
		songTxt.setFormat(Paths.font('future.ttf'), 15, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		songTxt.scrollFactor.set();
		songTxt.cameras = [camHUD];
		add(songTxt);
	}

	function hudGetOffset(id:String):Array<Float>
	{
		if (ClientPrefs.data.hudLayout.exists(id)) return ClientPrefs.data.hudLayout.get(id);
		var arr:Array<Float> = [0, 0];
		ClientPrefs.data.hudLayout.set(id, arr);
		return arr;
	}

	// 按保存的偏移重算模拟 HUD 位置（与 PlayState 默认位置公式一致）
	function repositionHUD():Void
	{
		var phigros:Bool = ClientPrefs.data.phigrosStyle;

		var noteOff:Array<Float> = hudGetOffset('note');
		var strumLineX:Float = (phigros || ClientPrefs.data.middleScroll) ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X;
		var strumLineY:Float = phigros ? 50 : (ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50);
		for (i in 0...strumLineNotes.length)
		{
			var strum:StrumNote = strumLineNotes[i];
			var px:Float = strumLineX + (i * Note.swagWidth) + noteOff[0];
			if (i < 4 && (phigros || ClientPrefs.data.middleScroll))
			{
				px += 310;
				if (i > 1) px += FlxG.width / 2 + 25;
			}
			strum.x = px;
			strum.y = strumLineY + noteOff[1];
		}
		if (phigrosJudgeLine != null)
		{
			phigrosJudgeLine.layoutOffsetY = noteOff[1];
			phigrosJudgeLine.y = 50 + noteOff[1];
		}

		var timeOff:Array<Float> = hudGetOffset('timeBar');
		var tbY:Float = 19;
		if (ClientPrefs.data.downScroll && !phigros) tbY = FlxG.height - 44 - 25;
		timeBar.y = tbY + timeOff[1];
		timeBar.screenCenter(X);
		timeBar.x += timeOff[0];
		timeTxt.x = PlayState.STRUM_X + (FlxG.width / 2) - 248 + timeOff[0];
		timeTxt.y = timeBar.y + 25;
		if (ClientPrefs.data.downScroll && !phigros) timeTxt.y = FlxG.height - 44 + timeOff[1];

		var hpOff:Array<Float> = hudGetOffset('healthBar');
		var hbY:Float = FlxG.height * (!ClientPrefs.data.downScroll || phigros ? 0.89 : 0.11) + hpOff[1];
		healthBar.y = hbY;
		healthBar.screenCenter(X);
		healthBar.x += hpOff[0];

		// 图标强绑定血量条（y 跟随，x 由 update 按 barCenter 计算）
		iconP1.y = healthBar.y - 75;
		iconP2.y = healthBar.y - 75;

		// 计分文字/水印：以默认血量条位置为基准，与血量条当前偏移解耦
		var defaultHpY:Float = FlxG.height * (!ClientPrefs.data.downScroll || phigros ? 0.89 : 0.11);
		var scoreOff:Array<Float> = hudGetOffset('score');
		scoreTxt.x = scoreOff[0];
		scoreTxt.y = defaultHpY + 55 + scoreOff[1];

		var wmOff:Array<Float> = hudGetOffset('watermark');
		songTxt.x = 12 + wmOff[0];
		songTxt.y = defaultHpY + 55 + wmOff[1];
	}

	function getElementRect(id:String):FlxRect
	{
		switch (id)
		{
			case 'note':
				var minX:Float = 99999, minY:Float = 99999, maxX:Float = -99999, maxY:Float = -99999;
				for (s in strumLineNotes)
				{
					minX = Math.min(minX, s.x);
					minY = Math.min(minY, s.y);
					maxX = Math.max(maxX, s.x + s.width);
					maxY = Math.max(maxY, s.y + s.height);
				}
				if (phigrosJudgeLine != null)
				{
					minY = Math.min(minY, phigrosJudgeLine.y - 20);
					maxY = Math.max(maxY, phigrosJudgeLine.y + 20);
				}
				return inflateRect(new FlxRect(minX, minY, maxX - minX, maxY - minY), 14);
			case 'timeBar':
				var r:FlxRect = new FlxRect(timeBar.x, timeBar.y, timeBar.bg.width, timeBar.bg.height);
				return inflateRect(unionRect(r, new FlxRect(timeTxt.x, timeTxt.y, 400, timeTxt.height)), 14);
			case 'healthBar':
				var r:FlxRect = new FlxRect(healthBar.x, healthBar.y, healthBar.bg.width, healthBar.bg.height);
				r = unionRect(r, new FlxRect(iconP1.x, iconP1.y, iconP1.width, iconP1.height));
				r = unionRect(r, new FlxRect(iconP2.x, iconP2.y, iconP2.width, iconP2.height));
				return inflateRect(r, 14);
			case 'score':
				var w:Float = scoreTxt.textField.textWidth + 40;
				if (w < 200) w = 700;
				return new FlxRect(scoreTxt.x + (FlxG.width - w) / 2, scoreTxt.y - 8, w, scoreTxt.height + 16);
			case 'watermark':
				return inflateRect(new FlxRect(songTxt.x, songTxt.y, songTxt.textField.textWidth + 20, songTxt.height), 10);
		}
		return new FlxRect(0, 0, 100, 100);
	}

	function unionRect(a:FlxRect, b:FlxRect):FlxRect
	{
		var minX:Float = Math.min(a.x, b.x);
		var minY:Float = Math.min(a.y, b.y);
		var maxX:Float = Math.max(a.x + a.width, b.x + b.width);
		var maxY:Float = Math.max(a.y + a.height, b.y + b.height);
		return new FlxRect(minX, minY, maxX - minX, maxY - minY);
	}

	function inflateRect(r:FlxRect, p:Float):FlxRect
	{
		return new FlxRect(r.x - p, r.y - p, r.width + p * 2, r.height + p * 2);
	}

	function getHoveredID(mx:Float, my:Float):Int
	{
		for (i in 0...elements.length)
		{
			var r:FlxRect = getElementRect(elements[i]);
			if (mx >= r.x && mx <= r.x + r.width && my >= r.y && my <= r.y + r.height)
				return i;
		}
		return -1;
	}

	function refreshBorders():Void
	{
		for (i in 0...elements.length)
		{
			var r:FlxRect = getElementRect(elements[i]);
			var col:Int = (i == curSelected) ? 0xFF00E5FF : 0x55FFFFFF;
			var bars:Array<FlxSprite> = borders[i];
			bars[0].setPosition(r.x, r.y);
			bars[0].setGraphicSize(Std.int(r.width), 3);
			bars[1].setPosition(r.x, r.y + r.height - 3);
			bars[1].setGraphicSize(Std.int(r.width), 3);
			bars[2].setPosition(r.x, r.y);
			bars[2].setGraphicSize(3, Std.int(r.height));
			bars[3].setPosition(r.x + r.width - 3, r.y);
			bars[3].setGraphicSize(3, Std.int(r.height));
			for (b in bars) b.color = col;

			var lbl:FlxText = labels[i];
			lbl.setPosition(r.x, r.y - 26);
			lbl.color = (i == curSelected) ? 0xFF00E5FF : 0xFFFFFFFF;
		}
	}

	function updateHint():Void
	{
		var off:Array<Float> = hudGetOffset(elements[curSelected]);
		hintText.text = '当前：' + elementNames[elements[curSelected]]
			+ '  ·  偏移 X ' + Std.int(off[0]) + ' / Y ' + Std.int(off[1])
			+ '  ·  拖动或方向键调整  ·  R 重置全部  ·  ESC 完成';
	}

	function applyDrag(dx:Float, dy:Float):Void
	{
		var off:Array<Float> = hudGetOffset(elements[curSelected]);
		off[0] += dx;
		off[1] += dy;
		repositionHUD();
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override public function update(elapsed:Float)
	{
		super.update(elapsed);

		// 图标强绑定血量条：x 跟随 barCenter（随血量增减左右滑动），y 跟随血量条，拖动血量条时整体跟随
		var iconOffset:Int = 26;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;

		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;

		// 鼠标拖动
		if (FlxG.mouse.justPressed)
		{
			if (mx >= doneBtn.x && mx <= doneBtn.x + doneBtn.width && my >= doneBtn.y && my <= doneBtn.y + doneBtn.height)
			{
				saveAndExit();
				return;
			}
			var hovered:Int = getHoveredID(mx, my);
			if (hovered >= 0)
			{
				curSelected = hovered;
				dragging = true;
				lastMouseX = mx;
				lastMouseY = my;
				refreshBorders();
				updateHint();
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.3);
			}
		}
		else if (FlxG.mouse.pressed && dragging)
		{
			applyDrag(mx - lastMouseX, my - lastMouseY);
			lastMouseX = mx;
			lastMouseY = my;
			refreshBorders();
			updateHint();
		}
		if (FlxG.mouse.justReleased && dragging)
		{
			dragging = false;
			ClientPrefs.saveSettings();
		}

		// 键盘微调 / 重置 / 退出（拖动时禁用，避免误操作）
		if (!dragging)
		{
			var step:Float = FlxG.keys.pressed.SHIFT ? 10 : 1;
			if (FlxG.keys.justPressed.LEFT) { applyDrag(-step, 0); refreshBorders(); updateHint(); }
			if (FlxG.keys.justPressed.RIGHT) { applyDrag(step, 0); refreshBorders(); updateHint(); }
			if (FlxG.keys.justPressed.UP) { applyDrag(0, -step); refreshBorders(); updateHint(); }
			if (FlxG.keys.justPressed.DOWN) { applyDrag(0, step); refreshBorders(); updateHint(); }

			if (FlxG.keys.justPressed.R)
			{
				// 重置全部元素到游戏默认位置（偏移全部清零）
				for (e in elements)
					ClientPrefs.data.hudLayout.set(e, [0, 0]);
				repositionHUD();
				refreshBorders();
				updateHint();
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
			}

			if (FlxG.keys.justPressed.ESCAPE || controls.BACK)
			{
				saveAndExit();
				return;
			}
		}
	}

	function saveAndExit():Void
	{
		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		CustomFadeTransition.nextCamera = camOther;
		MusicBeatState.switchState(new options.OptionsState());
		if (OptionsState.onPlayState)
		{
			if (ClientPrefs.data.pauseMusic != '无')
				FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
			else
				FlxG.sound.music.volume = 0;
		}
		else
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
		FlxG.mouse.visible = false;
	}
}
