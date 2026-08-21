package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import flixel.util.FlxSpriteUtil;

import openfl.Lib;

import objects.HealthIcon;
import objects.BackButton;
import flixel.util.FlxSpriteUtil;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import substates.ScriptManagerSubstate;
import substates.ReplaySubState;

class FreeplayState extends MusicBeatState
{
	// ===== 布局常量 =====
	// 所有文本一律左侧排版，右缘留足余量，不再做“靠右计算”，杜绝字符截断
	static final PANEL_L_X:Float = 40;
	static final PANEL_L_Y:Float = 70;
	static final PANEL_L_W:Float = 680;
	static final PANEL_L_H:Float = 570;

	static final PANEL_R_X:Float = 740;
	static final PANEL_R_Y:Float = 70;
	static final PANEL_R_W:Float = 460;
	static final PANEL_R_H:Float = 570;

	static final LIST_X:Float = 88;      // 歌曲名 X
	static final LIST_Y:Float = 152;     // 第一行 Y
	static final ROW_GAP:Float = 62;     // 行距
	static final ROWS_VISIBLE:Int = 7;   // 可见行数

	static final INFO_X:Float = 772;     // 右侧信息 X
	static final INFO_W:Float = 400;     // 右侧信息最大宽度

	var songs:Array<SongMetadata> = [];

	private static var curSelected:Int = 0;
	var curDifficulty:Int = -1;
	private static var lastDifficultyName:String = Difficulty.getDefault();

	var songTitleText:FlxText;
	var scoreText:FlxText;
	var ratingText:FlxText;
	var diffText:FlxText;
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	var songRows:Array<MenuText> = [];
	var songIcon:HealthIcon;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var scrollIndex:Int = 0;
	var mouseActive:Bool = true;  // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;      // 键盘接管时记录的鼠标位置
	var mouseLockY:Float = 0;

	var backBtn:BackButton;
	// 0.6.3 模组兼容：Freeplay 歌曲颜色表（旧版模组 Lua 通过
	// setPropertyFromClass('states.FreeplayState', 'songColors[i]', 颜色) 逐个设置）
	public static var songColors:Array<FlxColor> = [];

	var bg:FlxSprite;
	var intendedColor:Int;
	var colorTween:FlxTween;

	var missingTextBG:FlxSprite;
	var missingText:FlxText;
	var justClosedSubState:Float = -9999;

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Select Song";
		PlayState.queuedReplay = null; // 清除可能残留的回放请求

		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		for (i in 0...WeekData.weeksList.length) {
			if(weekIsLocked(WeekData.weeksList[i])) continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length)
			{
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if(colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]));
			}
		}
		Mods.loadTopMod();

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 662, 1160, 48, 14));

		// ---- 面板标题 ----
		var leftTitle:FlxText = new FlxText(LIST_X, 100, 0, '选择歌曲', 26);
		leftTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		leftTitle.scrollFactor.set();
		leftTitle.antialiasing = ClientPrefs.data.antialiasing;
		add(leftTitle);

		var rightTitle:FlxText = new FlxText(INFO_X, 100, 0, '歌曲信息', 26);
		rightTitle.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rightTitle.scrollFactor.set();
		rightTitle.antialiasing = ClientPrefs.data.antialiasing;
		add(rightTitle);

		// ---- 歌曲行（静态行：切换时只移动高亮条，行本身不整列滑动） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var row:MenuText = new MenuText(LIST_X, LIST_Y + (r * ROW_GAP), '', true, 30);
			row.isMenuItem = false;
			row.ID = r;
			row.visible = false;
			add(row);
			songRows.push(row);
		}

		// 悬停高亮条（只做视觉，不切换选中/滚动）+ 返回按钮
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 当前选中歌曲的大图标（显示在右侧曲目信息面板空白处） ----
		songIcon = new HealthIcon('face');
		songIcon.x = PANEL_R_X + (PANEL_R_W / 2) - 75;
		songIcon.y = 425;
		songIcon.visible = false;
		add(songIcon);

		// ---- 选中高亮条 ----
		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, 0x2EFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 右侧信息（固定位置，左对齐） ----
		songTitleText = makeInfoText('', 140, 40);
		scoreText = makeInfoText('最佳成绩：', 240, 28);
		ratingText = makeInfoText('准确率：', 296, 28);
		diffText = makeInfoText('', 360, 28);

		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("future.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		if(curSelected >= songs.length) curSelected = 0;
		bg.color = songs[curSelected].color;
		intendedColor = bg.color;

		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		WeekData.setDirectoryFromWeek();
		changeSelection();

		#if PRELOAD_ALL
		var leText:String = "空格 试听 · CTRL 游玩设置 · L 脚本管理 · R 重置分数 · P 回放";
		var size:Int = 16;
		#else
		var leText:String = "<!>未完全加载文件！CTRL 游玩设置 · L 脚本管理 · R 重置分数 · P 回放";
		var size:Int = 16;
		#end
		var text:FlxText = new FlxText(40, 672, 1160, leText, size);
		text.setFormat(Paths.font("future.ttf"), size, FlxColor.WHITE, CENTER);
		text.scrollFactor.set();
		add(text);

		FlxG.mouse.visible = true;
		super.create();

		#if mobile
		// 用 virtualpad 的 C / L / P 键替代原来的按钮：C=游玩设置，L=脚本管理，P=回放
		if (objects.MobileControls.instance != null)
		{
			var pad:objects.MobileControls = objects.MobileControls.instance;
			pad.addMenuButton('replay', 'P', FlxG.width - objects.MobileControls.BTN_W * 2 - 20 - 12, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
			pad.addMenuButton('script', 'L', FlxG.width - objects.MobileControls.BTN_W * 3 - 20 - 24, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
			pad.addMenuButton('gameplay', 'C', FlxG.width - objects.MobileControls.BTN_W * 4 - 20 - 36, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
		}
		#end

		loadUIscripts('freeplay');

		// 0.6.3 模组兼容：Lua onCreate 设置 songColors 后应用到歌曲列表
		applySongColors();
	}

	/** 0.6.3 模组兼容：把 songColors 应用到歌曲列表颜色。
	 *  支持 setPropertyFromClass('states.FreeplayState', 'songColors[i]', 颜色) 逐个设置；
	 *  整体赋值为 Lua 表（非 Haxe Array）时安全忽略 */
	function applySongColors():Void
	{
		if (songColors == null || !Std.isOfType(songColors, Array) || songColors.length == 0) return;
		for (i in 0...songs.length)
		{
			if (i >= songColors.length) break;
			var c:Dynamic = songColors[i];
			if (c == null || Std.isOfType(c, Array)) continue; // Lua 表元素/空值跳过
			songs[i].color = c;
		}
		if (songs.length > 0)
		{
			bg.color = songs[curSelected].color;
			intendedColor = bg.color;
		}
	}

	function makeInfoText(content:String, yPos:Float, ?size:Int = 28, ?textColor:FlxColor = FlxColor.WHITE):FlxText
	{
		var txt:FlxText = new FlxText(INFO_X, yPos, INFO_W, content, size);
		txt.setFormat(Paths.font('future.ttf'), size, textColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		txt.borderSize = 2;
		txt.scrollFactor.set();
		txt.antialiasing = ClientPrefs.data.antialiasing;
		add(txt);
		return txt;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		// unique：面板独立位图，避免与其他界面同尺寸面板（如回放列表）共享位图而被重复绘制叠加变黑
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if(border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override function openSubState(SubState:flixel.FlxSubState) {
		// 打开二级界面时隐藏父级返回键，避免半透明背景透出两个返回键
		if (backBtn != null)
		{
			backBtn.glow.visible = false;
			backBtn.spr.visible = false;
			backBtn.label.visible = false;
		}
		super.openSubState(SubState);
	}

	override function closeSubState() {
		FlxG.mouse.visible = true;
		changeSelection(0, false);
		persistentUpdate = true;
		justClosedSubState = Lib.getTimer(); // 关闭后短时间内忽略父界面点击，防止松手穿透
		if (backBtn != null)
		{
			backBtn.glow.visible = true;
			backBtn.spr.visible = true;
			backBtn.label.visible = true;
		}
		super.closeSubState();
	}

	function openScriptManager()
	{
		persistentUpdate = false;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		openSubState(new ScriptManagerSubstate(Paths.formatToSongPath(songs[curSelected].songName)));
	}

	function openReplayList()
	{
		persistentUpdate = false;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		openSubState(new ReplaySubState(songs[curSelected].songName, curDifficulty));
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int)
	{
		songs.push(new SongMetadata(songName, weekNum, songCharacter, color));
	}

	function weekIsLocked(name:String):Bool {
		// 临时调试：解锁全部周目（复现 Senpai 箭头颜色）
		return false;
	}

	var instPlaying:Int = -1;
	public static var vocals:FlxSound = null;
	var holdTime:Float = 0;
	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.7)
		{
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
		}
		lerpScore = Math.floor(FlxMath.lerp(lerpScore, intendedScore, FlxMath.bound(elapsed * 24, 0, 1)));
		lerpRating = FlxMath.lerp(lerpRating, intendedRating, FlxMath.bound(elapsed * 12, 0, 1));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
		if(ratingSplit.length < 2) { //No decimals, add an empty space
			ratingSplit.push('');
		}

		while(ratingSplit[1].length < 2) { //Less than 2 decimals in it, add decimals then
			ratingSplit[1] += '0';
		}

		scoreText.text = '最佳成绩：' + lerpScore;
		ratingText.text = '准确率：' + ratingSplit.join('.') + '%';

		var shiftMult:Int = 1;
		if(FlxG.keys.pressed.SHIFT) shiftMult = 3;

		var accepted:Bool = controls.ACCEPT;

		if(songs.length > 1)
		{
			if(FlxG.keys.justPressed.HOME)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.x;
				mouseLockY = FlxG.mouse.y;
				curSelected = 0;
				changeSelection();
				holdTime = 0;
			}
			else if(FlxG.keys.justPressed.END)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.x;
				mouseLockY = FlxG.mouse.y;
				curSelected = songs.length - 1;
				changeSelection();
				holdTime = 0;
			}
			if (controls.UI_UP_P)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.x;
				mouseLockY = FlxG.mouse.y;
				changeSelection(-shiftMult);
				holdTime = 0;
			}
			if (controls.UI_DOWN_P)
			{
				mouseActive = false;
				mouseLockX = FlxG.mouse.x;
				mouseLockY = FlxG.mouse.y;
				changeSelection(shiftMult);
				holdTime = 0;
			}

			if(controls.UI_DOWN || controls.UI_UP)
			{
				mouseActive = false; // 按住方向键期间键盘优先
				mouseLockX = FlxG.mouse.x;
				mouseLockY = FlxG.mouse.y;
				var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
				holdTime += elapsed;
				var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

				if(holdTime > 0.5 && checkNewHold - checkLastHold > 0)
					changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
			}

			if(FlxG.mouse.wheel != 0)
			{
				mouseActive = true;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
				changeSelection(shiftMult * (FlxG.mouse.wheel > 0 ? -1 : 1), false);
			}

			if (!controls.controllerMode)
			{
				var clickPressed:Bool = FlxG.mouse.justPressed;
				#if mobile
				// 触屏：手指抬起且未滑动才算点击，拖动滚动列表时不误选歌曲
				clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
				#end
				if (Lib.getTimer() - justClosedSubState < 300)
				{
					clickPressed = false;
				}

				var hoveredID:Int = getHoveredSongID();

				// 鼠标离开键盘接管位置超过阈值 → 恢复鼠标跟随（防轻微抖动误触发）
				if (!mouseActive)
				{
					var dx:Float = FlxG.mouse.x - mouseLockX;
					var dy:Float = FlxG.mouse.y - mouseLockY;
					if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
				}

				// 返回按钮：悬停高亮，点击返回主菜单
				backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
				if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
				{
					mouseActive = true;
					persistentUpdate = false;
					if (colorTween != null) colorTween.cancel();
					FlxG.sound.play(Paths.sound('cancelMenu'));
					MusicBeatState.switchState(new MainMenuState());
				}

				if (hoveredID >= 0 && clickPressed)
				{
					mouseActive = true;
					if (hoveredID != curSelected)
					{
						changeSelection(hoveredID - curSelected);
						holdTime = 0;
					}
					// 鼠标/触屏点击歌曲行：选中并直接进入该曲目
					// （原实现点击已选中的行无任何反应，也没有"点击进入游戏"的路径）
					accepted = true;
				}
				if (FlxG.mouse.overlaps(diffText) && clickPressed)
				{
					mouseActive = true;
					if (FlxG.mouse.x < diffText.x + (diffText.width / 2))
						changeDiff(-1);
					else
						changeDiff(1);
					_updateSongLastDifficulty();
				}
			}
		}

		if (controls.UI_LEFT_P)
		{
			changeDiff(-1);
			_updateSongLastDifficulty();
		}
		else if (controls.UI_RIGHT_P)
		{
			changeDiff(1);
			_updateSongLastDifficulty();
		}

		if (controls.BACK)
		{
			persistentUpdate = false;
			if(colorTween != null) {
				colorTween.cancel();
			}
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}

		// 脚本管理/回放/游玩设置改为 virtualpad 的 L / P / C 键触发
		#if mobile
		if (objects.MobileControls.instance != null)
		{
			if (objects.MobileControls.instance.justPressed('script')) openScriptManager();
			if (objects.MobileControls.instance.justPressed('replay')) openReplayList();
			if (objects.MobileControls.instance.justPressed('gameplay'))
			{
				persistentUpdate = false;
				openSubState(new GameplayChangersSubstate());
			}
		}
		#end

		if (FlxG.keys.justPressed.P)
			openReplayList();

		if(FlxG.keys.justPressed.CONTROL)
		{
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
		}
		else if(FlxG.keys.justPressed.L)
		{
			openScriptManager();
		}
		else if(FlxG.keys.justPressed.SPACE)
		{
			if(instPlaying != curSelected)
			{
				Lib.application.window.title = "FNF':Meteoric Engine - Select Song: " + curSelected;
				#if PRELOAD_ALL
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				Mods.currentModDirectory = songs[curSelected].folder;
				var previewSong:String = Paths.formatToSongPath(songs[curSelected].songName);
				// 试听不解析谱面（避免大谱面卡顿），直接用歌名播放音频
				if (Song.voicesFileExists(previewSong))
					vocals = new FlxSound().loadEmbedded(Paths.voices(previewSong));
				else
					vocals = new FlxSound();

				FlxG.sound.list.add(vocals);
				FlxG.sound.playMusic(Paths.inst(previewSong), 0.7);
				vocals.play();
				vocals.persist = true;
				vocals.looped = true;
				vocals.volume = 0.7;
				instPlaying = curSelected;
				#end
			}
		}

		else if (accepted)
		{
			persistentUpdate = false;
			var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = curDifficulty;

			if(!LoadingState.loadSongAndSwitchState(new PlayState(), songLowercase, poop, songLowercase, true, new FreeplayState()))
			{
				missingText.text = '在加载铺面文件时出错：\n缺失的文件：data/' + songLowercase + '/' + poop;
				missingText.screenCenter(Y);
				missingText.visible = true;
				missingTextBG.visible = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));

				super.update(elapsed);
				return;
			}

			if(colorTween != null) {
				colorTween.cancel();
			}

			FlxG.sound.music.volume = 0;

			destroyFreeplayVocals();
			#if MODS_ALLOWED
			#if desktop
			DiscordClient.loadModRPC();
			#end
			#end
		}
		else if(controls.RESET)
		{
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		super.update(elapsed);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}

	public static function destroyFreeplayVocals() {
		if(vocals != null) {
			vocals.stop();
			vocals.destroy();
		}
		vocals = null;
	}

	function getHoveredSongID():Int
	{
		var hoveredID:Int = -1;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (row in songRows)
		{
			if (row.visible && mx >= row.x && mx <= row.x + row.width && my >= row.y && my <= row.y + row.height)
				hoveredID = scrollIndex + row.ID;
		}
		return hoveredID;
	}

	function changeDiff(change:Int = 0)
	{
		curDifficulty += change;

		if (curDifficulty < 0)
			curDifficulty = Difficulty.list.length-1;
		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = 0;

		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].songName, curDifficulty);
		intendedRating = Highscore.getRating(songs[curSelected].songName, curDifficulty);
		#end

		lastDifficultyName = Difficulty.getString(curDifficulty);
		if (Difficulty.list.length > 1)
			diffText.text = '选择难度：< ' + lastDifficultyName.toUpperCase() + ' >';
		else
			diffText.text = '难度：' + lastDifficultyName.toUpperCase();

		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function changeSelection(change:Int = 0, playSound:Bool = true)
	{
		_updateSongLastDifficulty();
		if(playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var lastList:Array<String> = Difficulty.list;
		curSelected += change;

		if (curSelected < 0)
			curSelected = songs.length - 1;
		if (curSelected >= songs.length)
			curSelected = 0;

		// 滚动窗口：只有越过可见区时才整页滚动，平时只移动高亮条
		if (curSelected < scrollIndex)
			scrollIndex = curSelected;
		else if (curSelected > scrollIndex + ROWS_VISIBLE - 1)
			scrollIndex = curSelected - ROWS_VISIBLE + 1;

		var newColor:Int = songs[curSelected].color;
		if(newColor != intendedColor) {
			if(colorTween != null) {
				colorTween.cancel();
			}
			intendedColor = newColor;
			colorTween = FlxTween.color(bg, 1, bg.color, intendedColor, {
				onComplete: function(twn:FlxTween) {
					colorTween = null;
				}
			});
		}

		refreshRows();

		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		Difficulty.loadFromWeek();

		var savedDiff:String = songs[curSelected].lastDifficulty;
		var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
		if(savedDiff != null && !lastList.contains(savedDiff) && Difficulty.list.contains(savedDiff))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(savedDiff)));
		else if(lastDiff > -1)
			curDifficulty = lastDiff;
		else if(Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		changeDiff();
		_updateSongLastDifficulty();

		callUIScripts('onChangeSelection', [curSelected, songs[curSelected].songName]);
	}

	function refreshRows()
	{
		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:MenuText = songRows[r];

			if (idx >= songs.length)
			{
				row.visible = false;
				continue;
			}

			var meta:SongMetadata = songs[idx];
			var isSel:Bool = (idx == curSelected);

			row.visible = true;
			row.text = meta.songName;
			row.updateHitbox();
			row.alpha = isSel ? 1 : 0.55;
			row.color = isSel ? FlxColor.WHITE : 0xFFB8B8C8;
		}

		// ---- 大图标跟随选中曲目 ----
		if (songs.length > 0)
		{
			Mods.currentModDirectory = songs[curSelected].folder;
			songIcon.scale.set(1, 1);
			songIcon.changeIcon(songs[curSelected].songCharacter);
			songIcon.offset.set(0, 0);
			songIcon.visible = true;
		}

		songTitleText.text = songs[curSelected].songName;
		songTitleText.updateHitbox();

		var barY:Float = LIST_Y - 3 + ((curSelected - scrollIndex) * ROW_GAP);
		selectorBar.visible = (songs.length > 0);
		if(selectorTween != null) {
			selectorTween.cancel();
			selectorTween = null;
		}
		if(selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

	inline private function _updateSongLastDifficulty()
	{
		songs[curSelected].lastDifficulty = Difficulty.getString(curDifficulty);
	}
}

class SongMetadata
{
	public var songName:String = "";
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var color:Int = -7179779;
	public var folder:String = "";
	public var lastDifficulty:String = null;

	public function new(song:String, week:Int, songCharacter:String, color:Int)
	{
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = Mods.currentModDirectory;
		if(this.folder == null) this.folder = '';
	}
}
