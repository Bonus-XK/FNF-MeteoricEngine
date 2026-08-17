package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import flixel.group.FlxGroup;
import flixel.math.FlxPoint;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.animation.FlxAnimation;
import openfl.Lib;

import objects.MenuItem;
import objects.MenuCharacter;
import flixel.util.FlxSpriteUtil;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;

/**
 * StoryMenuState —— 故事模式选周界面（显示逻辑重写版）
 *
 * 保留备份版整体视觉（黄色标题条、每周背景、周目轮播、角色立绘、曲目轨条），
 * 重点重写“难度切换”的显示与输入：
 *   - 难度选择器（◀ 难度 ▶）固定坐标、固定可见（不再锚定周目缩略图、
 *     不再受锁定状态影响）、最后添加永远在最上层
 *   - 触控：点 ◀▶ 切难度、点周目选中、拖动滚周目（stage tap 队列，安卓必定可用）
 *   - 键盘/鼠标沿用备份版
 *   - 安卓系统返回键 → 回主菜单（不再退出游戏）
 */
class StoryMenuState extends MusicBeatState
{
	public static var weekCompleted:Map<String, Bool> = new Map<String, Bool>();

	// ===== 难度选择器固定位置（逻辑坐标，1280x720） =====
	// 位于黄色标题条中部偏右，避开周目轮播/角色/曲目轨条
	static final DIFF_X:Float = 830;   // 之前的位置（备份版箭头坐标，A 键上方）
	static final DIFF_Y:Float = 462;
	static final DIFF_GAP:Float = 376;

	var scoreText:FlxText;

	private static var lastDifficultyName:String = '';
	var curDifficulty:Int = 1;

	var txtWeekTitle:FlxText;
	var bgSprite:FlxSprite;

	private static var curWeek:Int = 0;

	var txtTracklist:FlxText;

	var grpWeekText:FlxTypedGroup<MenuItem>;
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;

	var grpLocks:FlxTypedGroup<FlxSprite>;

	var difficultySelectors:FlxGroup;
	var sprDifficulty:FlxSprite;
	var diffTxt:FlxText; // 难度图缺失时的文字兜底
	var leftArrow:FlxSprite;
	var rightArrow:FlxSprite;
	var diffLeftBtn:FlxSprite;  // 移动端自绘难度 ◀ 按钮（不依赖 MobileControls.instance）
	var diffRightBtn:FlxSprite; // 移动端自绘难度 ▶ 按钮

	var loadedWeeks:Array<WeekData> = [];

	var movedBack:Bool = false;
	var selectedWeek:Bool = false;
	var stopspamming:Bool = false;
	var tweenDifficulty:FlxTween;
	var backBtn:objects.BackButton;

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		Lib.application.window.title = "FNF':Meteoric Engine - Select Week:";

		PlayState.isStoryMode = true;
		WeekData.reloadWeekFiles(true);
		if (curWeek >= WeekData.weeksList.length) curWeek = 0;
		persistentUpdate = persistentDraw = true;

		super.create();

		scoreText = new FlxText(10, 10, 0, "SCORE: 49324858", 36);
		scoreText.setFormat(Paths.font("future.ttf"), 32);

		txtWeekTitle = new FlxText(FlxG.width * 0.7, 10, 0, "", 32);
		txtWeekTitle.setFormat(Paths.font("future.ttf"), 32, FlxColor.WHITE, RIGHT);
		txtWeekTitle.alpha = 0.7;

		var ui_tex = Paths.getSparrowAtlas('campaign_menu_UI_assets');
		var bgYellow:FlxSprite = new FlxSprite(0, 56).makeGraphic(FlxG.width, 386, 0xFFF9CF51);
		bgSprite = new FlxSprite(0, 56);

		grpWeekText = new FlxTypedGroup<MenuItem>();
		add(grpWeekText);

		var blackBarThingie:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 56, FlxColor.BLACK);
		add(blackBarThingie);

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();

		grpLocks = new FlxTypedGroup<FlxSprite>();
		add(grpLocks);

		#if desktop
		DiscordClient.changePresence("In the Menus", null);
		#end

		var num:Int = 0;
		for (i in 0...WeekData.weeksList.length)
		{
			var weekFile:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var isLocked:Bool = weekIsLocked(WeekData.weeksList[i]);
			if (!isLocked || !weekFile.hiddenUntilUnlocked)
			{
				loadedWeeks.push(weekFile);
				WeekData.setDirectoryFromWeek(weekFile);
				var weekThing:MenuItem = new MenuItem(0, bgSprite.y + 396, WeekData.weeksList[i]);
				weekThing.y += ((weekThing.height + 20) * num);
				weekThing.targetY = num;
				weekThing.ID = num;
				grpWeekText.add(weekThing);

				weekThing.screenCenter(X);

				if (isLocked)
				{
					var lock:FlxSprite = new FlxSprite(weekThing.width + 10 + weekThing.x);
					lock.antialiasing = ClientPrefs.data.antialiasing;
					lock.frames = ui_tex;
					lock.animation.addByPrefix('lock', 'lock');
					lock.animation.play('lock');
					lock.ID = i;
					grpLocks.add(lock);
				}
				num++;
			}
		}

		WeekData.setDirectoryFromWeek(loadedWeeks[0]);
		var charArray:Array<String> = loadedWeeks[0].weekCharacters;
		for (char in 0...3)
		{
			var weekCharacterThing:MenuCharacter = new MenuCharacter((FlxG.width * 0.25) * (1 + char) - 150, charArray[char]);
			weekCharacterThing.y += 70;
			grpWeekCharacters.add(weekCharacterThing);
		}

		Difficulty.resetList();
		if (lastDifficultyName == '')
			lastDifficultyName = Difficulty.getDefault();
		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		// ===== 难度选择器：固定坐标、最后添加（永远最上层）、始终可见 =====
		difficultySelectors = new FlxGroup();

		// 箭头：优先使用原图集贴图（campaign_menu_UI_assets），图集帧不可用时自动自绘兜底
		leftArrow = makeArrow(-1, DIFF_X, DIFF_Y, ui_tex);
		if (leftArrow != null) difficultySelectors.add(leftArrow);

		sprDifficulty = new FlxSprite(0, DIFF_Y);
		sprDifficulty.antialiasing = ClientPrefs.data.antialiasing;
		difficultySelectors.add(sprDifficulty);

		// 难度图缺失时的文字兜底（避免 flixel 默认 Haxe 占位图）
		diffTxt = new FlxText(0, 0, 0, '', 40);
		diffTxt.setFormat(Paths.font('future.ttf'), 40, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		diffTxt.borderSize = 2;
		diffTxt.visible = false;
		difficultySelectors.add(diffTxt);

		rightArrow = makeArrow(1, DIFF_X + DIFF_GAP, DIFF_Y, ui_tex);
		if (rightArrow != null) difficultySelectors.add(rightArrow);
		// 注意：difficultySelectors 延后到 create 末尾再 add —— 必须盖在黄色条/背景/角色之上

		add(bgYellow);
		add(bgSprite);
		add(grpWeekCharacters);

		var tracksSprite:FlxSprite = new FlxSprite(FlxG.width * 0.07, bgSprite.y + 425).loadGraphic(Paths.image('Menu_Tracks'));
		tracksSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(tracksSprite);

		txtTracklist = new FlxText(FlxG.width * 0.05, tracksSprite.y + 60, 0, "", 32);
		txtTracklist.alignment = CENTER;
		txtTracklist.font = scoreText.font;
		txtTracklist.color = 0xFFe55777;
		add(txtTracklist);
		add(scoreText);
		add(txtWeekTitle);

		// 难度选择器最后添加：永远绘制在黄色标题条/每周背景/角色之上
		add(difficultySelectors);

		#if mobile
		// 移动端：隐藏自绘箭头（makeArrow 返回 null，此处必须判空）
		if (leftArrow != null) leftArrow.visible = false;
		if (rightArrow != null) rightArrow.visible = false;
		// 难度切换 ◀ ▶ 自绘按钮（不依赖 MobileControls.instance：冷启动直进 StoryMenu 时
		// instance 不存在，tap 通道由 MobileControls 静态监听常驻提供）
		diffLeftBtn = objects.MobileControls.makePadSprite('left', 0xFFFFFFFF);
		diffLeftBtn.x = 20;
		diffLeftBtn.y = FlxG.height - objects.MobileControls.BTN_H - 20;
		add(diffLeftBtn);
		diffRightBtn = objects.MobileControls.makePadSprite('right', 0xFFFFFFFF);
		diffRightBtn.x = 20 + objects.MobileControls.BTN_W + 8;
		diffRightBtn.y = FlxG.height - objects.MobileControls.BTN_H - 20;
		add(diffRightBtn);
		#end

		// 右上角返回键
		backBtn = new objects.BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		changeWeek();
		changeDifficulty();
		FlxG.mouse.visible = true;

		loadUIscripts('story_menu');
	}

	#if mobile
	/** 安卓返回键：回主菜单（不退出游戏） */
	override public function onAndroidBack():Bool
	{
		if (!movedBack && !selectedWeek)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			movedBack = true;
			MusicBeatState.switchState(new MainMenuState());
		}
		return true;
	}
	#end

	override function closeSubState()
	{
		FlxG.mouse.visible = true;
		persistentUpdate = true;
		changeWeek();
		super.closeSubState();
	}

	override function update(elapsed:Float)
	{
		lerpScore = Math.floor(FlxMath.lerp(lerpScore, intendedScore, FlxMath.bound(elapsed * 30, 0, 1)));
		if (Math.abs(intendedScore - lerpScore) < 10) lerpScore = intendedScore;
		scoreText.text = "本周分数：" + lerpScore;

		if (!movedBack && !selectedWeek)
		{
			var upP = controls.UI_UP_P;
			var downP = controls.UI_DOWN_P;

			// 返回键悬停发光（与 Freeplay 一致：鼠标/触摸靠近即点亮，点击有反馈）
			backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);

			#if mobile
			// ---- 触屏：FlxG.mouse 触摸→鼠标模拟（与主菜单/Freeplay 同一可靠通道）----
			// 拖动滚周目（stage 拖动跟踪可用时；往下拖=下一个，往上拖=上一个）
			var steps:Int = objects.MobileControls.consumeDragSteps();
			if (steps != 0)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				changeWeek(steps);
				changeDifficulty();
			}
			// 点按：手指抬起且未滑动才算点击（与 Freeplay 一致）
			var clickPressed:Bool = FlxG.mouse.justReleased && !Main.touchWasDragging();
			if (clickPressed)
			{
				var mx:Float = FlxG.mouse.screenX;
				var my:Float = FlxG.mouse.screenY;
				// 难度切换 ◀ ▶（自绘按钮区域）
				if (diffLeftBtn != null && mx >= diffLeftBtn.x && mx <= diffLeftBtn.x + diffLeftBtn.width
					&& my >= diffLeftBtn.y && my <= diffLeftBtn.y + diffLeftBtn.height)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					changeDifficulty(-1);
				}
				else if (diffRightBtn != null && mx >= diffRightBtn.x && mx <= diffRightBtn.x + diffRightBtn.width
					&& my >= diffRightBtn.y && my <= diffRightBtn.y + diffRightBtn.height)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					changeDifficulty(1);
				}
				else
				{
					// 点周目 = 选中（A 键才真正进入）
					var hitWeek:Bool = false;
					for (item in grpWeekText.members)
					{
						if (mx >= item.x && mx <= item.x + item.width && my >= item.y && my <= item.y + item.height)
						{
							var idx:Int = grpWeekText.members.indexOf(item);
							if (idx != curWeek)
							{
								changeWeek(idx - curWeek);
								changeDifficulty();
							}
							hitWeek = true;
							break;
						}
					}
					// 右上角返回键（圆形判定，与 Freeplay 一致；等同 ESC/系统返回键）
					if (!hitWeek && backBtn.over(mx, my))
					{
						FlxG.sound.play(Paths.sound('cancelMenu'));
						movedBack = true;
						MusicBeatState.switchState(new MainMenuState());
						return;
					}
				}
			}
			#end

			if (upP)
			{
				changeWeek(-1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}

			if (downP)
			{
				changeWeek(1);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}

			if (FlxG.mouse.wheel != 0)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				changeWeek(-FlxG.mouse.wheel);
				changeDifficulty();
			}

			// 移动端 makeArrow 返回 null（难度切换走左下角 virtualpad）——所有箭头引用必须判空
			if (rightArrow != null && rightArrow.animation.getByName('press') != null)
			{
				if (controls.UI_RIGHT)
					rightArrow.animation.play('press')
				else
					rightArrow.animation.play('idle');
			}
			else if (rightArrow != null)
				rightArrow.alpha = controls.UI_RIGHT ? 1 : 0.9;
			if (leftArrow != null && leftArrow.animation.getByName('press') != null)
			{
				if (controls.UI_LEFT)
					leftArrow.animation.play('press')
				else
					leftArrow.animation.play('idle');
			}
			else if (leftArrow != null)
				leftArrow.alpha = controls.UI_LEFT ? 1 : 0.9;

			if (controls.UI_RIGHT_P)
				changeDifficulty(1);
			else if (controls.UI_LEFT_P)
				changeDifficulty(-1);
			else if (upP || downP)
				changeDifficulty();

			#if !mobile
			// 桌面：鼠标点 ◀▶ 切难度 / 点返回键
			if (FlxG.mouse.justPressed)
			{
				if (FlxG.mouse.overlaps(leftArrow))
					changeDifficulty(-1);
				else if (FlxG.mouse.overlaps(rightArrow))
					changeDifficulty(1);
				else if (backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					movedBack = true;
					MusicBeatState.switchState(new MainMenuState());
				}
			}
			#end

			if (FlxG.keys.justPressed.CONTROL)
			{
				persistentUpdate = false;
				openSubState(new GameplayChangersSubstate());
			}
			else if (controls.RESET)
			{
				persistentUpdate = false;
				openSubState(new ResetScoreSubState('', curDifficulty, '', curWeek));
			}
			else if (controls.ACCEPT)
			{
				selectWeek();
			}
		}

		if (controls.BACK && !movedBack && !selectedWeek)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			movedBack = true;
			MusicBeatState.switchState(new MainMenuState());
		}

		super.update(elapsed);

		grpLocks.forEach(function(lock:FlxSprite)
		{
			lock.y = grpWeekText.members[lock.ID].y;
			lock.visible = (lock.y > FlxG.height / 2);
		});
	}

	function selectWeek()
	{
		if (!weekIsLocked(loadedWeeks[curWeek].fileName))
		{
			var songArray:Array<String> = [];
			var leWeek:Array<Dynamic> = loadedWeeks[curWeek].songs;
			for (i in 0...leWeek.length)
				songArray.push(leWeek[i][0]);

			var diffic:String = Difficulty.getFilePath(curDifficulty);
			if (diffic == null) diffic = '';
			var firstSong:String = Paths.formatToSongPath(songArray[0]);

			try
			{
				PlayState.storyPlaylist = songArray;
				PlayState.isStoryMode = true;
				selectedWeek = true;

				PlayState.storyDifficulty = curDifficulty;

				if (Song.resolveChartPath(firstSong + diffic, firstSong) == null)
				{
					trace('ERROR! Missing chart: ' + firstSong + diffic);
					return;
				}
				PlayState.campaignScore = 0;
				PlayState.campaignMisses = 0;
			}
			catch (e:Dynamic)
			{
				trace('ERROR! $e');
				return;
			}

			if (stopspamming == false)
			{
				FlxG.sound.play(Paths.sound('confirmMenu'));
				grpWeekText.members[curWeek].startFlashing();
				for (char in grpWeekCharacters.members)
				{
					if (char.character != '' && char.hasConfirmAnimation)
						char.animation.play('confirm');
				}
				stopspamming = true;
			}

			new FlxTimer().start(1, function(tmr:FlxTimer)
			{
				LoadingState.loadSongAndSwitchState(new PlayState(), firstSong, firstSong + diffic, firstSong, true, new StoryMenuState());
				FreeplayState.destroyFreeplayVocals();
			});

			#if MODS_ALLOWED
			#if desktop
			DiscordClient.loadModRPC();
			#end
			#end
		}
		else
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	function changeDifficulty(change:Int = 0):Void
	{
		curDifficulty += change;

		if (curDifficulty < 0)
			curDifficulty = Difficulty.list.length - 1;
		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = 0;

		WeekData.setDirectoryFromWeek(loadedWeeks[curWeek]);

		var diff:String = Difficulty.getString(curDifficulty);
		var newImage:FlxGraphic = Paths.image('menudifficulties/' + Paths.formatToSongPath(diff));

		if (newImage == null)
		{
			// 难度图缺失：改用文字显示（绝不让 loadGraphic(null) 渲染 Haxe 占位图）
			sprDifficulty.visible = false;
			diffTxt.visible = true;
			diffTxt.text = diff.toUpperCase();
			diffTxt.x = DIFF_X + 20;
			diffTxt.y = DIFF_Y + (90 - diffTxt.height) / 2;
		}
		else if (sprDifficulty.graphic != newImage)
		{
			diffTxt.visible = false;
			sprDifficulty.visible = true;
			sprDifficulty.loadGraphic(newImage);
			sprDifficulty.setGraphicSize(220, 0); // 统一缩放到箭头间距内
			sprDifficulty.updateHitbox();
			sprDifficulty.x = DIFF_X + 60;
			sprDifficulty.x += (DIFF_GAP - 60 - sprDifficulty.width) / 2;
			sprDifficulty.alpha = 0;
			sprDifficulty.y = DIFF_Y + (90 - sprDifficulty.height) / 2;

			if (tweenDifficulty != null) tweenDifficulty.cancel();
			tweenDifficulty = FlxTween.tween(sprDifficulty, {y: DIFF_Y + 15, alpha: 1}, 0.07, {onComplete: function(twn:FlxTween)
			{
				tweenDifficulty = null;
			}});
		}
		lastDifficultyName = diff;

		#if !switch
		intendedScore = Highscore.getWeekScore(loadedWeeks[curWeek].fileName, curDifficulty);
		#end
	}

	var lerpScore:Int = 0;
	var intendedScore:Int = 0;

	function changeWeek(change:Int = 0):Void
	{
		curWeek += change;

		if (curWeek >= loadedWeeks.length)
			curWeek = 0;
		if (curWeek < 0)
			curWeek = loadedWeeks.length - 1;

		var leWeek:WeekData = loadedWeeks[curWeek];
		WeekData.setDirectoryFromWeek(leWeek);

		var leName:String = leWeek.storyName;
		txtWeekTitle.text = leName.toUpperCase();
		txtWeekTitle.x = FlxG.width - (txtWeekTitle.width + 10);

		var bullShit:Int = 0;
		var unlocked:Bool = !weekIsLocked(leWeek.fileName);
		for (item in grpWeekText.members)
		{
			item.targetY = bullShit - curWeek;
			if (item.targetY == Std.int(0) && unlocked)
				item.alpha = 1;
			else
				item.alpha = 0.6;
			bullShit++;
		}

		bgSprite.visible = true;
		var assetName:String = leWeek.weekBackground;
		if (assetName == null || assetName.length < 1)
			bgSprite.visible = false;
		else
			bgSprite.loadGraphic(Paths.image('menubackgrounds/menu_' + assetName));
		PlayState.storyWeek = curWeek;

		Difficulty.loadFromWeek();
		// 只有一种难度时（如 mod 周的 dside）隐藏箭头——没得切，避免“点了没反应”的错觉
		// 注意：sprDifficulty/diffTxt 的可见性由 changeDifficulty() 决定（难度名在单难度周也要显示），不在此覆盖
		var hasChoice:Bool = Difficulty.list.length > 1;
		if (leftArrow != null) leftArrow.visible = hasChoice;
		if (rightArrow != null) rightArrow.visible = hasChoice;
		#if mobile
		if (diffLeftBtn != null) diffLeftBtn.visible = hasChoice;
		if (diffRightBtn != null) diffRightBtn.visible = hasChoice;
		#end
		difficultySelectors.visible = true;

		if (Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		var newPos:Int = Difficulty.list.indexOf(lastDifficultyName);
		if (newPos > -1)
			curDifficulty = newPos;

		updateText();

		callUIScripts('onChangeSelection', [curWeek, loadedWeeks[curWeek].storyName]);
	}

	/** 难度箭头：优先加载原图集贴图（campaign_menu_UI_assets 的 arrow left/right），
	 *  图集帧缺失/不可用时自动自绘三角形兜底（保证必定可见）。dir=-1 左，1 右 */
	function makeArrow(dir:Int, x:Float, y:Float, ui_tex:FlxAtlasFrames):FlxSprite
	{
		#if mobile
		// 安卓端：不创建任何箭头对象（难度切换已由左下角 virtualpad ◀ ▶ 承担），
		// 难度文字位置使用固定常量，不依赖箭头对象。
		return null;
		#end
		var spr:FlxSprite = new FlxSprite(x, y);
		spr.antialiasing = ClientPrefs.data.antialiasing;
		var useAtlas:Bool = (ui_tex != null);
		if (useAtlas)
		{
			spr.frames = ui_tex;
			spr.animation.addByPrefix('idle', dir < 0 ? "arrow left" : 'arrow right');
			var idle:FlxAnimation = spr.animation.getByName('idle');
			useAtlas = (idle != null && idle.frames.length > 0);
			if (useAtlas)
			{
				spr.animation.addByPrefix('press', dir < 0 ? "arrow push left" : "arrow push right");
				spr.animation.play('idle');
			}
		}
		if (!useAtlas)
		{
			// 兜底：自绘三角形箭头
			spr.frames = null;
			spr.makeGraphic(70, 90, FlxColor.TRANSPARENT, true);
			var pts:Array<FlxPoint> = [];
			if (dir < 0)
			{
				pts.push(FlxPoint.get(66, 45));
				pts.push(FlxPoint.get(8, 8));
				pts.push(FlxPoint.get(8, 82));
				FlxSpriteUtil.drawPolygon(spr, pts, 0xFFFFFFFF);
				var tail:Array<FlxPoint> = [FlxPoint.get(8, 20), FlxPoint.get(30, 45), FlxPoint.get(8, 70)];
				FlxSpriteUtil.drawPolygon(spr, tail, 0xFFFFFFFF);
			}
			else
			{
				pts.push(FlxPoint.get(4, 45));
				pts.push(FlxPoint.get(62, 8));
				pts.push(FlxPoint.get(62, 82));
				FlxSpriteUtil.drawPolygon(spr, pts, 0xFFFFFFFF);
				var tail:Array<FlxPoint> = [FlxPoint.get(62, 20), FlxPoint.get(40, 45), FlxPoint.get(62, 70)];
				FlxSpriteUtil.drawPolygon(spr, tail, 0xFFFFFFFF);
			}
			for (p in pts) p.put();
			spr.alpha = 0.9;
		}
		return spr;
	}

	function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked && leWeek.weekBefore.length > 0 && (!weekCompleted.exists(leWeek.weekBefore) || !weekCompleted.get(leWeek.weekBefore)));
	}

	function updateText()
	{
		var weekArray:Array<String> = loadedWeeks[curWeek].weekCharacters;
		for (i in 0...grpWeekCharacters.length)
			grpWeekCharacters.members[i].changeCharacter(weekArray[i]);

		var leWeek:WeekData = loadedWeeks[curWeek];
		var stringThing:Array<String> = [];
		for (i in 0...leWeek.songs.length)
			stringThing.push(leWeek.songs[i][0]);

		txtTracklist.text = '';
		for (i in 0...stringThing.length)
			txtTracklist.text += stringThing[i] + '\n';
		txtTracklist.text = txtTracklist.text.toUpperCase();

		txtTracklist.screenCenter(X);
		txtTracklist.x -= FlxG.width * 0.35;

		#if !switch
		intendedScore = Highscore.getWeekScore(loadedWeeks[curWeek].fileName, curDifficulty);
		#end
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
