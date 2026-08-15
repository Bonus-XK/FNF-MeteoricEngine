package states;

import backend.Multiplayer;
import backend.WeekData;
import backend.Difficulty;
import backend.Highscore;
import objects.BackButton;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flixel.addons.ui.FlxInputText;

class OnlineMenuState extends MusicBeatState
{
	static final PANEL_X:Float = 200;
	static final PANEL_Y:Float = 100;
	static final PANEL_W:Float = 880;
	static final PANEL_H:Float = 470;
	static final ROW_X:Float = 260;
	static final ROW_START_Y:Float = 180;
	static final ROW_GAP:Float = 70;

	var menuItems:Array<String> = ['创建房间', '加入房间'];
	var rowTexts:Array<FlxText> = [];
	var songRows:Array<FlxText> = [];
	var curSelected:Int = 0;
	var mode:String = 'menu'; // menu / host / join
	var statusText:FlxText;
	var roomInfoText:FlxText;
	var ipInput:FlxInputText;
	var ipLabel:FlxText;
	var backBtn:BackButton;
	var playerCountText:FlxText;
	var lastPlayerCount:Int = 0;
	var songs:Array<String> = [];
	var songCur:Int = 0;
	var selectedDiff:Int = 0;
	var receivedSong:String = '';
	var receivedDiff:String = '';
	var hostSelected:Bool = false;

	override function create()
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		add(bg);

		var title:FlxText = new FlxText(0, 40, FlxG.width, '联机模式', 48);
		title.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(title);

		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H);
		add(panel);

		for (i in 0...menuItems.length)
		{
			var txt:FlxText = new FlxText(ROW_X, ROW_START_Y + i * ROW_GAP, 0, menuItems[i], 32);
			txt.setFormat(Paths.font('future.ttf'), 32, (i == curSelected ? FlxColor.WHITE : 0xFFA9A9B8), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			add(txt);
			rowTexts.push(txt);
		}

		for (i in 0...7)
		{
			var txt:FlxText = new FlxText(ROW_X, ROW_START_Y + i * 40, 0, '', 24);
			txt.setFormat(Paths.font('future.ttf'), 24, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.visible = false;
			add(txt);
			songRows.push(txt);
		}

		roomInfoText = new FlxText(ROW_X, 120, PANEL_W - 80, '', 22);
		roomInfoText.setFormat(Paths.font('future.ttf'), 22, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		roomInfoText.visible = false;
		add(roomInfoText);

		statusText = new FlxText(ROW_X, PANEL_Y + PANEL_H - 80, PANEL_W - 80, '', 22);
		statusText.setFormat(Paths.font('future.ttf'), 22, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(statusText);

		playerCountText = new FlxText(ROW_X, PANEL_Y + PANEL_H - 45, PANEL_W - 80, '', 20);
		playerCountText.setFormat(Paths.font('future.ttf'), 20, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(playerCountText);

		ipLabel = new FlxText(ROW_X, 300, 0, '输入房主 IP：', 26);
		ipLabel.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		ipLabel.visible = false;
		add(ipLabel);

		ipInput = new FlxInputText(ROW_X + 180, 300, 300, '192.168.1.100', 24);
		ipInput.visible = false;
		add(ipInput);

		loadSongs();

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		FlxG.mouse.visible = true;
	}

	override function update(elapsed:Float)
	{
		Multiplayer.update();
		processMessages();

		if (mode == 'menu')
		{
			for (r in songRows) r.visible = false;
			roomInfoText.visible = false;

			if (controls.UI_UP_P)
			{
				changeSelection(-1);
			}
			if (controls.UI_DOWN_P)
			{
				changeSelection(1);
			}
			if (controls.ACCEPT)
			{
				if (curSelected == 0)
				{
					var err = Multiplayer.startHost();
					if (err == 'OK')
					{
						mode = 'lobby';
						statusText.text = '房间已创建\nIP: ' + Multiplayer.localIP + ':' + Multiplayer.port + '\n房间码: ' + Multiplayer.roomCode;
					}
					else
					{
						statusText.text = '创建失败：' + err;
					}
				}
				else
				{
					mode = 'join';
					ipLabel.visible = true;
					ipInput.visible = true;
					ipInput.hasFocus = true;
					statusText.text = '输入房主 IP 后按 A 连接';
				}
			}
			if (controls.BACK)
			{
				Multiplayer.stop();
				MusicBeatState.switchState(new MainMenuState());
			}
		}
		else if (mode == 'join')
		{
			for (r in songRows) r.visible = false;
			roomInfoText.visible = false;

			if (controls.ACCEPT)
			{
				var err = Multiplayer.connect(ipInput.text);
				if (err == 'OK')
				{
					mode = 'lobby';
					ipLabel.visible = false;
					ipInput.visible = false;
					statusText.text = '已连接到 ' + ipInput.text + ':' + Multiplayer.port;
				}
				else
				{
					statusText.text = '连接失败：' + err;
				}
			}
			// 输入框聚焦时 Backspace 用于删字，不当作返回键
			if (!ipInput.hasFocus && controls.BACK)
			{
				mode = 'menu';
				ipLabel.visible = false;
				ipInput.visible = false;
				statusText.text = '';
			}
		}
		else if (mode == 'lobby')
		{
			for (t in rowTexts) t.visible = false;
			roomInfoText.visible = true;

			if (Multiplayer.isHost)
				roomInfoText.text = 'IP: ' + Multiplayer.localIP + ':' + Multiplayer.port + '    房间码: ' + Multiplayer.roomCode;
			else
				roomInfoText.text = '已连接到房主';

			if (songs.length > 0)
			{
				var diffName:String = Difficulty.getString(selectedDiff);
				statusText.text = '当前选择: ' + songs[songCur] + ' [' + diffName + ']\n'
					+ (Multiplayer.isHost ? 'A=发送选曲，再按A=开始' : '等待房主选曲...');

				if (controls.UI_UP_P) songCur = (songCur - 1 + songs.length) % songs.length;
				if (controls.UI_DOWN_P) songCur = (songCur + 1) % songs.length;
				if (controls.UI_LEFT_P) selectedDiff = (selectedDiff - 1 + Difficulty.list.length) % Difficulty.list.length;
				if (controls.UI_RIGHT_P) selectedDiff = (selectedDiff + 1) % Difficulty.list.length;

				var start:Int = Math.floor(songCur / 7) * 7;
				if (songCur < start) start = songCur;
				if (songCur >= start + 7) start = songCur - 6;
				for (i in 0...songRows.length)
				{
					var idx:Int = start + i;
					if (idx < songs.length)
					{
						songRows[i].visible = true;
						songRows[i].text = (idx == songCur ? '> ' : '  ') + songs[idx];
						songRows[i].color = (idx == songCur ? FlxColor.WHITE : 0xFFA9A9B8);
					}
					else
					{
						songRows[i].visible = false;
					}
				}

				if (Multiplayer.isHost)
				{
					if (controls.ACCEPT)
					{
						if (!hostSelected)
						{
							hostSelected = true;
							Multiplayer.send('SONG|' + songs[songCur] + '|' + Difficulty.getString(selectedDiff));
							statusText.text = '已发送选曲: ' + songs[songCur] + ' [' + Difficulty.getString(selectedDiff) + ']\n再按 A 开始游戏';
						}
						else
						{
							Multiplayer.send('START|' + songs[songCur] + '|' + Difficulty.getString(selectedDiff));
							startMultiplayerGame(songs[songCur], Difficulty.getString(selectedDiff));
						}
					}
				}
			}
			else
			{
				for (r in songRows) r.visible = false;
				statusText.text = '没有可用歌曲';
			}

			if (controls.BACK)
			{
				Multiplayer.stop();
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		// 返回按钮点击
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		backBtn.setHovered(mx, my);
		if (FlxG.mouse.justPressed && backBtn.over(mx, my))
		{
			Multiplayer.stop();
			MusicBeatState.switchState(new MainMenuState());
		}

		super.update(elapsed);
	}

	function changeSelection(change:Int):Void
	{
		curSelected = (curSelected + change + menuItems.length) % menuItems.length;
		for (i in 0...rowTexts.length)
		{
			rowTexts[i].color = (i == curSelected) ? FlxColor.WHITE : 0xFFA9A9B8;
		}
	}

	function processMessages():Void
	{
		var msgs = Multiplayer.pollMessages();
		for (m in msgs)
		{
			if (m == 'PLAYER_JOINED')
			{
				lastPlayerCount++;
				playerCountText.text = '当前玩家：' + (lastPlayerCount + 1);
			}
			else if (m == 'PLAYER_LEFT')
			{
				lastPlayerCount--;
				if (lastPlayerCount < 0) lastPlayerCount = 0;
				playerCountText.text = '当前玩家：' + (lastPlayerCount + 1);
			}
			else if (m.indexOf('SONG|') == 0)
			{
				var parts = m.split('|');
				if (parts.length >= 3)
				{
					receivedSong = parts[1];
					receivedDiff = parts[2];
					statusText.text = '房主选曲：' + receivedSong + ' [' + receivedDiff + ']';
				}
			}
			else if (m.indexOf('START|') == 0)
			{
				var parts = m.split('|');
				if (parts.length >= 3)
				{
					startMultiplayerGame(parts[1], parts[2]);
				}
			}
			else
			{
				statusText.text = '收到消息：' + m;
			}
		}
	}

	function loadSongs():Void
	{
		WeekData.reloadWeekFiles(false);
		for (i in 0...WeekData.weeksList.length)
		{
			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			if (leWeek == null) continue;
			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				songs.push(song[0]);
			}
		}
		Mods.loadTopMod();
		if (songs.length > 0) songCur = 0;
	}

	function startMultiplayerGame(songName:String, diffName:String):Void
	{
		var diffInt:Int = Difficulty.list.indexOf(diffName);
		if (diffInt < 0) diffInt = 0;
		var songLowercase:String = Paths.formatToSongPath(songName);
		var poop:String = Highscore.formatSong(songLowercase, diffInt);
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = diffInt;
		if (!LoadingState.loadSongAndSwitchState(new PlayState(), songLowercase, poop, songLowercase, true, new OnlineMenuState()))
		{
			statusText.text = '加载失败：' + songLowercase;
		}
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, 20, 20, 0xCC161622);
		spr.scrollFactor.set();
		return spr;
	}

	override function destroy()
	{
		Multiplayer.stop();
		super.destroy();
	}
}
