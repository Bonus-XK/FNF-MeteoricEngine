package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import flixel.util.FlxSpriteUtil;
import flixel.system.ui.FlxSoundTray;
import flixel.math.FlxPoint;

import openfl.Lib;

import objects.HealthIcon;
import objects.BackButton;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import substates.ScriptManagerSubstate;
import substates.ReplaySubState;

// Psych 0.7.3 版 Freeplay（Alphabet 歌曲列表 + HealthIcon 跟随 + 右上成绩区），
// 保留 Meteoric 特性：圆角磨砂框、返回按钮（左上）、完整鼠标/触控逻辑、试听灵动岛、
// 节拍跳动、CTRL/R/L/P 子状态、0.6.3 songColors 兼容、中文界面。
class FreeplayState extends MusicBeatState
{
	// ===== 布局常量 =====
	// 歌曲列表：无卡片、直接铺在背景上（Psych 0.7.3 式无限制显示）
	static final LIST_X:Float = 88;
	static final LIST_CENTER_Y:Float = 320; // Alphabet 列表中心（Psych 0.7.3 默认）
	static final ROW_STEP:Float = 120;      // Alphabet 行距（实际步进 = 1.3 * ROW_STEP ≈ 156）
	static final DRAW_DISTANCE:Int = 4;     // 可见窗口 ±4 行（Psych 0.7.3 默认，无卡片裁剪）

	// 右上磨砂条：歌名 / 历史最高分 / 准确率 / 难度
	static final PANEL_R_X:Float = 740;
	static final PANEL_R_Y:Float = 14;
	static final PANEL_R_W:Float = 500;
	static final PANEL_R_H:Float = 132;

	// 底部磨砂条：提示
	static final PANEL_B_X:Float = 40;
	static final PANEL_B_Y:Float = 662;
	static final PANEL_B_W:Float = 1160;
	static final PANEL_B_H:Float = 48;

	// 右上信息 X
	static final INFO_X:Float = 772;
	static final INFO_W:Float = 440;

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

	var grpSongs:FlxTypedGroup<Alphabet>;
	var iconArray:Array<HealthIcon> = [];
	var lerpSelected:Float = 0;
	var _lastVisibles:Array<Int> = [];

	var bg:FlxSprite;
	var intendedColor:Int;
	var colorTween:FlxTween;

	var missingTextBG:FlxSprite;
	var missingText:FlxText;
	var justClosedSubState:Float = -9999;

	// 鼠标/键盘输入分离
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var wheelThrottleUntil:Int = 0;
	var wheelNextStepTime:Int = 0;

	var backBtn:BackButton;
	var bottomPanel:FlxSprite;   // 底部磨砂条（置顶绘制）
	var bottomHint:FlxText;      // 底部提示文字（置顶绘制）
	// 0.6.3 模组兼容：Freeplay 歌曲颜色表
	public static var songColors:Array<FlxColor> = [];

	// ===== 试听播放器（灵动岛）状态 =====
	var previewActive:Bool = false;
	var previewTray:FlxSoundTray = null;
	var previewRestartPending:Bool = false;
	var lastSelectionTime:Int = 0;
	var instPlaying:Int = -1;
	public static var vocals:FlxSound = null;
	var holdTime:Float = 0;

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

		// ---- 圆角磨砂框（右上成绩条 + 底部提示条；歌曲列表无框，铺在背景上） ----
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 18));
		bottomPanel = makePanel(PANEL_B_X, PANEL_B_Y, PANEL_B_W, PANEL_B_H, 14);
		add(bottomPanel);

		// ---- 返回按钮（左上） ----
		backBtn = new BackButton(44, 16);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- Psych 0.7.3 歌曲列表：Alphabet + HealthIcon 跟随 ----
		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);

		for (i in 0...songs.length)
		{
			var songText:Alphabet = new Alphabet(LIST_X, LIST_CENTER_Y, songs[i].songName, true);
			songText.targetY = i;
			songText.distancePerItem.y = ROW_STEP;
			songText.scaleX = Math.min(1, (PANEL_R_X - LIST_X - 100) / songText.width);
			songText.snapToPosition();
			grpSongs.add(songText);

			Mods.currentModDirectory = songs[i].folder;
			var icon:HealthIcon = new HealthIcon(songs[i].songCharacter);
			icon.sprTracker = songText;

			songText.visible = songText.active = songText.isMenuItem = false;
			icon.visible = icon.active = false;

			iconArray.push(icon);
			add(icon);
		}
		WeekData.setDirectoryFromWeek();

		// ---- 右上信息（磨砂条内，左对齐防截断） ----
		songTitleText = new FlxText(INFO_X, 26, INFO_W, '', 26);
		songTitleText.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		songTitleText.borderSize = 2;
		songTitleText.scrollFactor.set();
		add(songTitleText);

		scoreText = new FlxText(INFO_X, 64, INFO_W, '', 22);
		scoreText.setFormat(Paths.font('future.ttf'), 22, 0xFFFFD166, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreText.borderSize = 2;
		scoreText.scrollFactor.set();
		add(scoreText);

		ratingText = new FlxText(INFO_X, 92, INFO_W, '', 20);
		ratingText.setFormat(Paths.font('future.ttf'), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		ratingText.borderSize = 2;
		ratingText.scrollFactor.set();
		add(ratingText);

		diffText = new FlxText(INFO_X, 114, INFO_W, '', 20);
		diffText.setFormat(Paths.font('future.ttf'), 20, 0xFF8AD7FF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		diffText.borderSize = 2;
		diffText.scrollFactor.set();
		add(diffText);

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
		lerpSelected = curSelected;

		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		changeSelection();

		// ---- 底部提示（中文） ----
		#if PRELOAD_ALL
		var leText:String = "Enter / A / 点击 进入歌曲 · 空格 试听 · CTRL 游玩设置 · L 脚本管理 · R 重置分数 · P 回放 · Esc 返回";
		var size:Int = 16;
		#else
		var leText:String = "<!>未完全加载文件！CTRL 游玩设置 · L 脚本管理 · R 重置分数 · P 回放";
		var size:Int = 16;
		#end
		bottomHint = new FlxText(PANEL_B_X, PANEL_B_Y + 10, PANEL_B_W, leText, size);
		bottomHint.setFormat(Paths.font("future.ttf"), size, FlxColor.WHITE, CENTER);
		bottomHint.scrollFactor.set();
		add(bottomHint);

		#if FLX_SOUND_TRAY
		#if mobile
		// 移动端 flixel 不建 soundTray（"No need for overlays on mobile"），
		// 试听灵动岛是本引擎功能：手动创建同款托盘并挂到 FlxG.game（update 由本状态驱动）。
		if (previewTray == null)
		{
			previewTray = new FlxSoundTray();
			FlxG.game.addChild(previewTray);
		}
		#else
		previewTray = FlxG.game.soundTray;
		#end
		#end

		// ---- 曲目列表与 Alphabet 图标置底：绘制顺序最底层，所有 UI 自然盖在其上 ----
		// 注意：必须用 FlxGroup.remove(…, true) + insert()（内部维护 length），
		// 不能裸操作 members（draw/update 按 length 迭代，会跳过尾部元素）
		var bottomLayer:Array<flixel.FlxBasic> = [grpSongs];
		for (icon in iconArray) bottomLayer.push(icon);
		var insertAt:Int = 1; // index 0 = bg
		for (b in bottomLayer)
		{
			remove(b, true);
			insert(insertAt, b);
			insertAt++;
		}

		// ---- 置顶：返回按钮与底部提示（含磨砂条）绘制在歌名列表上方 ----
		remove(backBtn.glow);  add(backBtn.glow);
		remove(backBtn.spr);   add(backBtn.spr);
		remove(backBtn.label); add(backBtn.label);
		remove(bottomPanel);   add(bottomPanel);
		remove(bottomHint);    add(bottomHint);

		FlxG.mouse.visible = true;
		super.create();

		#if mobile
		// 用 virtualpad 的 T / C / L / P 键替代原来的按钮：T=试听，C=游玩设置，L=脚本管理，P=回放
		if (objects.MobileControls.instance != null)
		{
			var pad:objects.MobileControls = objects.MobileControls.instance;
			pad.addMenuButton('replay', 'P', FlxG.width - objects.MobileControls.BTN_W * 2 - 20 - 12, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
			pad.addMenuButton('script', 'L', FlxG.width - objects.MobileControls.BTN_W * 3 - 20 - 24, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
			pad.addMenuButton('gameplay', 'C', FlxG.width - objects.MobileControls.BTN_W * 4 - 20 - 36, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
			pad.addMenuButton('preview', 'T', FlxG.width - objects.MobileControls.BTN_W * 5 - 20 - 48, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFAAAAAA);
		}
		#end

		loadUIscripts('freeplay');

		// 0.6.3 模组兼容：Lua onCreate 设置 songColors 后应用到歌曲列表
		applySongColors();
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

	/** 0.6.3 模组兼容：把 songColors 应用到歌曲列表颜色。 */
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

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		// unique：面板独立位图，避免与其他界面同尺寸面板共享位图而被重复绘制叠加变黑
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if(border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
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
		// 临时调试：解锁全部周目
		return false;
	}

	override function beatHit()
	{
		super.beatHit();
		// 试听中停止整屏节拍跳动（灵动岛播放时不再随节拍缩放）
		if (!previewActive)
			menuBeatBump();
	}

	override function update(elapsed:Float)
	{
		// 菜单音乐时间同步到 Conductor：节拍事件（beatHit）才能随背景音乐触发（试听/菜单曲均可）
		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		#if mobile
		#if FLX_SOUND_TRAY
		// 移动端托盘由本状态驱动（FlxGame 无引用不会 update）
		if (previewTray != null && previewTray.active)
			previewTray.update(FlxG.elapsed * 1000);
		#end
		#end

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

		scoreText.text = '历史最高分：' + lerpScore;
		ratingText.text = '准确率：' + ratingSplit.join('.') + '%';

		updateTexts(elapsed);

		var shiftMult:Int = 1;
		if(FlxG.keys.pressed.SHIFT) shiftMult = 3;

		// 进入曲目只绑定 Enter（SPACE 已交给试听/暂停，引擎默认 accept=[SPACE, ENTER] 会误触发进入）；
		// 手柄玩家保留 ACCEPT（A/START），鼠标/触屏点击歌曲行仍可进入
		var accepted:Bool = FlxG.keys.justPressed.ENTER
			|| (controls.controllerMode && controls.ACCEPT);

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
				var wheelDelta:Int = Std.int(FlxG.mouse.wheel);
				var steps:Int = Std.int(Math.abs(wheelDelta));
				if (steps < 1) steps = 1;
				if (steps > 2) steps = 2; // 单次最多跳 2 格：快速滚动（delta 3~5）不会飞
				var dir:Int = wheelDelta > 0 ? -1 : 1;
				var now:Int = Lib.getTimer();
				// 滚动间隔节流：< 70ms 内的连续 wheel 事件不再跳格
				if (now >= wheelNextStepTime)
				{
					if (now < wheelThrottleUntil)
					{
						// 快速连续滚动：静默跳格（跳过颜色渐变——渐变会被下一格立即 cancel，纯浪费）
						changeSelection(shiftMult * dir * steps, false, true);
					}
					else
					{
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
						changeSelection(shiftMult * dir * steps, false);
					}
					wheelNextStepTime = now + 70;
				}
				wheelThrottleUntil = now + 150;
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

				// 灵动岛展开时鼠标在岛范围内 → 屏蔽对下层歌曲行的点击（岛内交互由托盘自身处理）
				var overIsland:Bool = (previewTray != null && previewTray.previewActive && previewTray.isOverPanel());

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

				if (hoveredID >= 0 && clickPressed && !overIsland)
				{
					mouseActive = true;
					if (hoveredID != curSelected)
					{
						changeSelection(hoveredID - curSelected);
						holdTime = 0;
					}
					// 鼠标/触屏点击歌曲行：选中并直接进入该曲目
					accepted = true;
				}
				if (FlxG.mouse.overlaps(diffText) && clickPressed && !overIsland)
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
			// 试听中按 ESC（BACK 键之一）：只停止试听并收起灵动岛，不退出界面；
			// BACKSPACE/手柄 BACK 仍直接退出。
			#if PRELOAD_ALL
			var escStopsPreview:Bool = previewActive && FlxG.keys.justPressed.ESCAPE;
			#else
			var escStopsPreview:Bool = false;
			#end
			if (escStopsPreview)
			{
				stopPreview();
			}
			else
			{
				persistentUpdate = false;
				#if PRELOAD_ALL
				if (previewActive) stopPreview(); // 恢复菜单音乐 freakyMenu
				#end
				if(colorTween != null) {
					colorTween.cancel();
				}
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
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
			// T 键：试听当前选中曲目（与桌面 SPACE 同行为；同曲再按 = 播放/暂停切换）
			if (objects.MobileControls.instance.justPressed('preview'))
			{
				#if PRELOAD_ALL
				if (previewActive && instPlaying == curSelected)
					togglePreviewPlayPause();
				else
					startPreview();
				#end
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
			#if PRELOAD_ALL
			if (previewActive && instPlaying == curSelected)
			{
				// 同一首歌再按空格：播放/暂停切换（灵动岛图标同步）
				togglePreviewPlayPause();
			}
			else
			{
				startPreview();
			}
			#end
		}

		// 切歌后 180ms 无新的切歌 → 自动重启试听（滚轮连滚情形下去抖，避免每格重载音频）
		// 独立 if 判断，解除与下方 accepted/RESET 的 else-if 耦合
		if (previewRestartPending && (Lib.getTimer() - lastSelectionTime) >= 180)
		{
			previewRestartPending = false;
			if (previewActive) startPreview();
		}

		if (accepted)
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

			#if PRELOAD_ALL
			if (previewActive) stopPreview(false); // 不恢复菜单音乐：PlayState 将加载自己的音乐
			#end
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
		// 兜底：离开状态时若仍在试听，停止并收平灵动岛（回调/音频不悬挂到下一状态）
		#if PRELOAD_ALL
		if (previewActive) stopPreview(false); else clearPreviewTray();
		#end
		#if mobile
		#if FLX_SOUND_TRAY
		// 移走本状态自建的灵动岛托盘（FlxSoundTray 是 openfl Sprite，无 destroy）
		if (previewTray != null)
		{
			FlxG.game.removeChild(previewTray);
			previewTray = null;
		}
		#end
		#end
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

	// ===== 试听播放器（灵动岛）= 空格试听功能与 -/+ 音量条融合 =====
	#if PRELOAD_ALL
	/** 开始试听当前选中曲目，并把音量托盘展开为播放器岛 */
	function startPreview():Void
	{
		previewRestartPending = false;
		if (previewActive && instPlaying == curSelected) return;

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
		previewActive = true;
		Lib.application.window.title = "FNF':Meteoric Engine - Select Song: " + curSelected;

		// 灵动岛：展开为播放器并注入交互回调
		if (previewTray != null)
		{
			previewTray.onSeek = seekPreview;
			previewTray.onTogglePlay = togglePreviewPlayPause;
			previewTray.onStopPreview = function() stopPreview();
			previewTray.openPreview(songs[curSelected].songName);
		}
	}

	/** 播放/暂停切换（空格或岛内按钮触发，inst 与 vocals 同步） */
	function togglePreviewPlayPause():Void
	{
		if (!previewActive) return;
		var m:FlxSound = FlxG.sound.music;
		if (m == null) return;
		if (m.playing)
		{
			m.pause();
			if (vocals != null) vocals.pause();
		}
		else
		{
			m.resume();
			if (vocals != null) vocals.resume();
		}
	}

	/** 进度条跳转：inst 与 vocals 同步 seek（毫秒） */
	function seekPreview(t:Float):Void
	{
		var m:FlxSound = FlxG.sound.music;
		if (m == null || m.length <= 0) return;
		t = Math.min(Math.max(t, 0), m.length);
		m.time = t;
		if (vocals != null && vocals.length > 0)
			vocals.time = Math.min(t, vocals.length);
	}

	/**
	 * 停止试听并收起灵动岛。
	 * @param restoreMenu true = 恢复菜单音乐 freakyMenu（返回主菜单时）；
	 *                    false = 直接静音（进入歌曲时，由 PlayState 加载自己的音乐）
	 */
	function stopPreview(restoreMenu:Bool = true):Void
	{
		if (!previewActive) return;
		previewActive = false;
		previewRestartPending = false;
		instPlaying = -1;
		destroyFreeplayVocals();
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		if (restoreMenu)
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.7);
		clearPreviewTray();
	}

	/** 清除托盘回调并收起为小音量条 */
	function clearPreviewTray():Void
	{
		if (previewTray != null)
		{
			previewTray.onSeek = null;
			previewTray.onTogglePlay = null;
			previewTray.onStopPreview = null;
			previewTray.closePreview();
		}
	}
	#end

	// ===== Psych 0.7.3 列表定位：lerpSelected 平滑 + 可见窗口 ±2 行 =====
	public function updateTexts(elapsed:Float = 0.0)
	{
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		for (i in _lastVisibles)
		{
			grpSongs.members[i].visible = grpSongs.members[i].active = false;
			iconArray[i].visible = iconArray[i].active = false;
		}
		_lastVisibles = [];

		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - DRAW_DISTANCE)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + DRAW_DISTANCE)));
		for (i in min...max)
		{
			var item:Alphabet = grpSongs.members[i];
			item.visible = item.active = true;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;

			var icon:HealthIcon = iconArray[i];
			icon.visible = icon.active = true;
			_lastVisibles.push(i);
		}
	}

	function getHoveredSongID():Int
	{
		var wp:FlxPoint = FlxG.mouse.getWorldPosition();
		var mx:Float = wp.x;
		var my:Float = wp.y;
		wp.put();
		for (i in 0...grpSongs.members.length)
		{
			var item:Alphabet = grpSongs.members[i];
			if (item == null || !item.visible || item.alpha <= 0.01) continue;
			// 无卡片：歌曲区位于右上磨砂条左侧（x < PANEL_R_X），整行高度带均命中
			if (mx >= LIST_X - 30 && mx <= PANEL_R_X - 20
				&& my >= item.y - 60 && my <= item.y + 60)
				return i;
		}
		return -1;
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

	function changeSelection(change:Int = 0, playSound:Bool = true, instant:Bool = false)
	{
		_updateSongLastDifficulty();
		if(playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var lastList:Array<String> = Difficulty.list;
		curSelected += change;

		if (curSelected < 0)
			curSelected = songs.length - 1;
		if (curSelected >= songs.length)
			curSelected = 0;

		var newColor:Int = songs[curSelected].color;
		if(newColor != intendedColor) {
			if(instant) {
				// 快速滚动（滚轮连续）：直接设色，跳过 1 秒渐变——渐变会被下一格 cancel，纯开销
				if(colorTween != null) { colorTween.cancel(); colorTween = null; }
				bg.color = newColor;
				intendedColor = newColor;
			}
			else {
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
		}

		// Psych 0.7.3 式高亮：选中项/图标不透明，其余半透明
		for (i in 0...iconArray.length)
		{
			iconArray[i].alpha = 0.6;
		}
		iconArray[curSelected].alpha = 1;

		for (item in grpSongs.members)
		{
			item.alpha = 0.6;
			if (item.targetY == curSelected)
				item.alpha = 1;
		}

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

		songTitleText.text = songs[curSelected].songName;
		songTitleText.updateHitbox();

		// 试听中切歌：延迟 180ms 自动切换到新曲试听（滚轮连滚下去抖，避免每格重载音频）
		if (previewActive && instPlaying != curSelected)
		{
			previewRestartPending = true;
			lastSelectionTime = Lib.getTimer();
		}

		callUIScripts('onChangeSelection', [curSelected, songs[curSelected].songName]);
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
