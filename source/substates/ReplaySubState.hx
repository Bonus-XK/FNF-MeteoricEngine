package substates;

import backend.Highscore;
import backend.Replay;

import flixel.math.FlxPoint;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;

import objects.BackButton;
import states.FreeplayState;

class ReplaySubState extends MusicBeatSubstate
{
	// ===== 布局常量（与自由选歌左侧面板一致） =====
	static final PANEL_X:Float = 40;
	static final PANEL_Y:Float = 70;
	static final PANEL_W:Float = 680;
	static final PANEL_H:Float = 570;
	static final TITLE_X:Float = 88;
	static final TITLE_Y:Float = 100;
	static final LIST_X:Float = 88;
	static final LIST_Y:Float = 152;
	static final ROW_GAP:Float = 56;
	static final ROWS_VISIBLE:Int = 8;

	var songName:String;
	var difficulty:Int;
	var replays:Array<Replay> = [];
	var curSelected:Int = 0;
	var scrollIndex:Int = 0;
	var rows:Array<MenuText> = [];
	var selectorBar:FlxSprite;
	var emptyText:FlxText;
	var hintText:FlxText;
	var backBtn:BackButton;
	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	public function new(song:String, diff:Int)
	{
		super();
		songName = song;
		difficulty = diff;

		var replayCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [replayCam];
		cameras[0].zoom = 1;
		cameras[0].scroll.set(0, 0);

		// ---- 背景 ----
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);
		FlxTween.tween(bg, {alpha: 0.6}, 0.4, {ease: FlxEase.quartInOut});

		// ---- 面板 ----
		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22);
		add(panel);

		var title:FlxText = new FlxText(TITLE_X, TITLE_Y, 0, '回放列表 - ' + song + ' (' + Difficulty.getString(diff) + ')', 26);
		title.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set();
		title.antialiasing = ClientPrefs.data.antialiasing;
		add(title);

		selectorBar = makePanel(PANEL_X + 24, LIST_Y - 3, PANEL_W - 48, 46, 14, 0x2EFFFFFF, null);
		add(selectorBar);

		emptyText = new FlxText(TITLE_X, 300, PANEL_W - 100, '该歌曲/难度还没有回放\n完成一次手动游玩后会自动保存', 24);
		emptyText.setFormat(Paths.font('future.ttf'), 24, 0xFFA9A9B8, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyText.scrollFactor.set();
		emptyText.visible = false;
		add(emptyText);

		hintText = new FlxText(TITLE_X, 600, 0, '', 16);
		hintText.setFormat(Paths.font('future.ttf'), 16, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.scrollFactor.set();
		add(hintText);

		for (r in 0...ROWS_VISIBLE)
		{
			var row:MenuText = new MenuText(LIST_X, LIST_Y + (r * ROW_GAP), '', true, 24);
			row.isMenuItem = false;
			row.ID = r;
			row.visible = false;
			add(row);
			rows.push(row);
		}

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("future.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		FlxG.mouse.visible = true;
		Lib.application.window.title = "FNF':Meteoric Engine - 回放列表";

		reloadList();
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		// unique：面板需要独立位图，避免与选歌界面同尺寸面板共享位图而被重复绘制（半透明叠加变黑）
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if(border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function rowText(replay:Replay):String
	{
		var d:Date = Date.fromTime(replay.saveTime);
		var mm:String = (d.getMonth() + 1) < 10 ? '0' + (d.getMonth() + 1) : Std.string(d.getMonth() + 1);
		var dd:String = d.getDate() < 10 ? '0' + d.getDate() : Std.string(d.getDate());
		var hh:String = d.getHours() < 10 ? '0' + d.getHours() : Std.string(d.getHours());
		var mi:String = d.getMinutes() < 10 ? '0' + d.getMinutes() : Std.string(d.getMinutes());
		var p:Float = Math.floor((replay.percent * 10000)) / 100;
		return mm + '-' + dd + ' ' + hh + ':' + mi + '   ·   ' + replay.score + ' 分   ·   ' + p + '%   ·   ' + replay.misses + ' Miss';
	}

	function reloadList():Void
	{
		replays = Replay.listFor(songName, difficulty);
		curSelected = 0;
		scrollIndex = 0;
		if (replays.length > 0) changeSelection(0);
		else
		{
			selectorBar.visible = false;
			for (row in rows) row.visible = false;
			emptyText.visible = true;
		}
		hintText.text = replays.length > 0 ? '回车 播放 · 退格 删除 · ESC 返回' : 'ESC 返回';
	}

	function changeSelection(change:Int = 0):Void
	{
		if (replays.length < 1) return;
		curSelected = Std.int(FlxMath.bound(curSelected + change, 0, replays.length - 1));
		if (curSelected < scrollIndex) scrollIndex = curSelected;
		if (curSelected >= scrollIndex + ROWS_VISIBLE) scrollIndex = curSelected - ROWS_VISIBLE + 1;

		for (i in 0...ROWS_VISIBLE)
		{
			var row:MenuText = rows[i];
			var idx:Int = scrollIndex + i;
			if (idx < replays.length)
			{
				row.visible = true;
				row.text = rowText(replays[idx]);
				row.color = (idx == curSelected) ? 0xFF54C8FF : FlxColor.WHITE;
			}
			else row.visible = false;
		}
		selectorBar.visible = true;
		emptyText.visible = false;
	}

	function startReplay():Void
	{
		var chosen:Replay = replays[curSelected];
		if (chosen == null) return;
		var songLowercase:String = Paths.formatToSongPath(songName);
		var poop:String = Highscore.formatSong(songLowercase, difficulty);
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = difficulty;
		PlayState.queuedReplay = chosen;
		if (!LoadingState.loadSongAndSwitchState(new PlayState(), songLowercase, poop, songLowercase, true, new FreeplayState()))
		{
			PlayState.queuedReplay = null;
			missingText.text = '在加载铺面文件时出错：\n缺失的文件：data/' + songLowercase + '/' + poop;
			missingText.screenCenter(Y);
			missingText.visible = true;
			missingTextBG.visible = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}
		close();
	}

	function deleteSelected():Void
	{
		var chosen:Replay = replays[curSelected];
		if (chosen == null) return;
		Replay.deleteFile(chosen.filePath);
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
		reloadList();
	}

	override function update(elapsed:Float)
	{
		if (cameras != null && cameras[0] != null)
		{
			cameras[0].zoom = 1;
			cameras[0].scroll.set(0, 0);
		}
		FlxG.mouse.visible = true;
		super.update(elapsed);

		var accepted:Bool = controls.ACCEPT;
		var upP:Bool = controls.UI_UP_P;
		var downP:Bool = controls.UI_DOWN_P;

		if (replays.length > 0)
		{
			if (upP)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				changeSelection(-1);
			}
			if (downP)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				changeSelection(1);
			}
		}

		if (!controls.controllerMode)
		{
			var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());
			backBtn.setHovered(mousePos.x, mousePos.y);
			if (FlxG.mouse.justPressed && backBtn.over(mousePos.x, mousePos.y))
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				close();
				mousePos.put();
				return;
			}

			if (replays.length > 0)
			{
				var hoveredID:Int = -1;
				for (row in rows)
				{
					if (row.visible && mousePos.x >= row.x && mousePos.x <= row.x + row.width
						&& mousePos.y >= row.y && mousePos.y <= row.y + row.height)
						hoveredID = scrollIndex + row.ID;
				}
				if (hoveredID >= 0 && hoveredID != curSelected)
					changeSelection(hoveredID - curSelected);
				if (hoveredID >= 0 && FlxG.mouse.justPressed)
				{
					changeSelection(hoveredID - curSelected);
					accepted = true;
				}
			}
			mousePos.put();
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		if (accepted && replays.length > 0)
		{
			FlxG.sound.play(Paths.sound('confirmMenu'));
			startReplay();
			return;
		}

		if (FlxG.keys.justPressed.BACKSPACE && replays.length > 0)
			deleteSelected();
	}
}
