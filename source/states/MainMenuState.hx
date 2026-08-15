package states;

import objects.BackButton;
import objects.AchievementPopup;
import backend.Achievements;

import states.editors.MasterEditorMenu;
import options.OptionsState;

import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;

class MainMenuState extends MusicBeatState
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

	static final LIST_X:Float = 88;
	static final LIST_Y:Float = 152;
	static final ROW_GAP:Float = 56;
	static final ROWS_VISIBLE:Int = 8;

	static final INFO_X:Float = 772;
	static final INFO_W:Float = 400;

	// 菜单项：ID / 名称 / 描述 / 背景色
	var optionShit:Array<Array<Dynamic>> = [
		['story_mode', '故事模式', '按章节顺序挑战官方曲目，一路打到周日晚上的对决。', 0xFFDD88FF],
		['freeplay', '自由游玩', '从全部已解锁曲目中任选一首挑战，还能查看最佳成绩与准确率。', 0xFF66DDFF],
		['online', '联机', '创建或加入房间，房主直连进行联机。', 0xFF66FF88],
		#if MODS_ALLOWED
		['mods', 'MOD', '管理已安装的模组：启用、停用或浏览模组内容。', 0xFF88E58A],
		#end
		#if ACHIEVEMENTS_ALLOWED
		['awards', '成就', '查看已解锁的成就与游戏内的挑战进度。', 0xFFFFD166],
		#end
		['credits', '制作人员', '查看 Meteoric Engine 与 Friday Night Funkin 的制作人员名单。', 0xFFFF8A8A],
		#if !switch
		['donate', '赞助', '打开赞助页面，支持游戏的开发与后续更新。', 0xFFFF9E5E],
		#end
		['options', '设置', '调整图像、视觉、游戏玩法与按键绑定等全部设置。', 0xFFB0B6FF],
		['old_menu', '旧版界面', '切换到 1.0.4 的经典主界面，重温 Alphabet 字母菜单。', 0xFF9E8AFF],
		['crash_test', '崩溃测试', '故意触发一个异常，用来测试游戏内报错系统。测试完按 Enter 即可返回主菜单。', 0xFF555555]
	];

	public static var curSelected:Int = 0;

	var rows:Array<MenuText> = [];
	var titleText:FlxText;    // 左侧主标题（界面脚本可 setText）
	var subtitleText:FlxText; // 右侧副标题（界面脚本可 setText）
	var itemNameText:FlxText;
	var descText:FlxText;
	var actionText:FlxText;
	var updateLinkText:FlxText;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var scrollOffset:Int = 0;
	var lastItemName:String = '';
	var lastDesc:String = '';
	var lastAction:String = '';

	var bg:FlxSprite;
	var colorTween:FlxTween;

	var backBtn:BackButton;
	var selectedSomethin:Bool = false;

	// ===== 彩蛋：输入 meforever =====
	var keyBuffer:String = '';
	var eggActive:Bool = false;
	var eggLetters:Array<FlxText> = [];
	var eggItems:Array<FlxSprite> = [];
	var eggVX:Array<Float> = [];
	var eggVY:Array<Float> = [];
	var eggVR:Array<Float> = [];
	var eggHue:Array<Float> = [];
	var baseWindowTitle:String = '';
	var titleScrollTimer:Float = 0;
	var windowVX:Float = 0;
	var windowVY:Float = 0;

	// ===== 鼠标/键盘输入分离 =====
	var mouseActive:Bool = true;  // 键盘操作后冻结，鼠标明显移动/滚轮/点击恢复
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	static final MOUSE_REACTIVATE_DIST:Float = 10;

	var camGame:FlxCamera;
	var camAchievement:FlxCamera;

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		baseWindowTitle = "FNF':Meteoric Engine - Main Menu";
		Lib.application.window.title = baseWindowTitle;

		if (curSelected >= optionShit.length) curSelected = 0;

		#if MODS_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		#if desktop
		DiscordClient.changePresence("In the Menus", null);
		#end

		camGame = new FlxCamera();
		camAchievement = new FlxCamera();
		camAchievement.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camAchievement, false);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);
		FlxG.mouse.visible = true;

		transIn = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;

		persistentUpdate = persistentDraw = true;

		// ---- 背景 ----
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);
		bg.color = optionShit[curSelected][3];

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 662, 1160, 48, 14));

		// ---- 标题 ----
		titleText = new FlxText(LIST_X, 100, 0, '主菜单', 26);
		titleText.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		titleText.scrollFactor.set();
		add(titleText);

		subtitleText = new FlxText(INFO_X, 100, 0, '选项说明', 26);
		subtitleText.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		subtitleText.borderSize = 2;
		subtitleText.scrollFactor.set();
		add(subtitleText);

		// ---- 版本信息 ----
		if (TitleState.mainUpdateCheck)
		{
			var verText:FlxText = new FlxText(40, 18, 0, 'Meteoric Engine v' + Main.meVersion + '（旧版本）', 16);
			verText.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			verText.borderSize = 2;
			verText.scrollFactor.set();
			add(verText);

			updateLinkText = new FlxText(40, 40, 0, '新版本：' + TitleState.updateVersion + '（点击查看）', 16);
			updateLinkText.setFormat(Paths.font('future.ttf'), 16, 0xFFFFD166, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			updateLinkText.borderSize = 2;
			updateLinkText.scrollFactor.set();
			updateLinkText.updateHitbox();
			add(updateLinkText);
		}
		else
		{
			var verText:FlxText = new FlxText(40, 18, 0, 'Meteoric Engine v' + Main.meVersion, 16);
			verText.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			verText.borderSize = 2;
			verText.scrollFactor.set();
			add(verText);
		}

		// ---- 彩蛋字母（输入 meforever 触发，逐字母乱飞变色） ----
		var eggStr:String = 'Meteoric Forever!';
		for (i in 0...eggStr.length)
		{
			var ltr:FlxText = new FlxText(0, 0, 0, eggStr.charAt(i), 40);
			ltr.setFormat(Paths.font('future.ttf'), 40, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			ltr.borderSize = 3;
			ltr.scrollFactor.set();
			ltr.visible = false;
			add(ltr);
			eggLetters.push(ltr);
		}

		// ---- 菜单行（静态行：切换时只移动高亮条） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var row:MenuText = new MenuText(LIST_X, LIST_Y + (r * ROW_GAP), '', true, 30);
			row.isMenuItem = false;
			row.ID = r;
			row.visible = false;
			row.scrollFactor.set();
			add(row);
			rows.push(row);
		}

		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, 0x2EFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 右侧信息 ----
		itemNameText = new FlxText(INFO_X, 165, INFO_W, '', 40);
		itemNameText.setFormat(Paths.font('future.ttf'), 40, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		itemNameText.borderSize = 2;
		itemNameText.scrollFactor.set();
		add(itemNameText);

		descText = new FlxText(INFO_X, 240, INFO_W, '', 24);
		descText.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.borderSize = 2;
		descText.scrollFactor.set();
		add(descText);

		actionText = new FlxText(INFO_X, 555, INFO_W, '', 20);
		actionText.setFormat(Paths.font('future.ttf'), 20, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		actionText.borderSize = 2;
		actionText.scrollFactor.set();
		add(actionText);

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(40, 672, 1160, '触控/滚轮 选择 · A / Enter 确认 · Esc 返回', 16);
		hint.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hint.borderSize = 2;
		hint.scrollFactor.set();
		add(hint);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		changeSelection();

		#if ACHIEVEMENTS_ALLOWED
		Achievements.loadAchievements();
		var leDate = Date.now();
		if (leDate.getDay() == 5 && leDate.getHours() >= 18) {
			var achieveID:Int = Achievements.getAchievementIndex('friday_night_play');
			if(!Achievements.isAchievementUnlocked(Achievements.achievementsStuff[achieveID][2])) { //It's a friday night. WEEEEEEEEEEEEEEEEEE
				Achievements.achievementsMap.set(Achievements.achievementsStuff[achieveID][2], true);
				giveAchievement();
				ClientPrefs.saveSettings();
			}
		}
		#end

		super.create();

		loadUIscripts('main_menu');
	}

	#if ACHIEVEMENTS_ALLOWED
	// Unlocks "Freaky on a Friday Night" achievement
	function giveAchievement() {
		add(new AchievementPopup('friday_night_play', camAchievement));
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		trace('Giving achievement "friday_night_play"');
	}
	#end

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.8)
		{
			FlxG.sound.music.volume += 0.5 * elapsed;
			if(FreeplayState.vocals != null) FreeplayState.vocals.volume += 0.5 * elapsed;
		}

		if (!selectedSomethin)
		{
			FlxG.mouse.visible = true;
			updateMouseControl();

			if (controls.UI_UP_P)
			{
				takeKeyboardControl();
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(-1);
			}

			if (controls.UI_DOWN_P)
			{
				takeKeyboardControl();
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(1);
			}

			if (controls.BACK)
			{
				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new TitleState());
			}

			if (controls.ACCEPT)
			{
				selectItem();
			}
			#if desktop
			else if (controls.justPressed('debug_1'))
			{
				selectedSomethin = true;
				MusicBeatState.switchState(new MasterEditorMenu());
			}
			#end

			// ---- 彩蛋：键盘输入 meforever ----
			var pressedKey:Int = FlxG.keys.firstJustPressed();
			if (pressedKey >= 65 && pressedKey <= 90)
			{
				keyBuffer += String.fromCharCode(pressedKey);
				if (keyBuffer.length > 9) keyBuffer = keyBuffer.substring(keyBuffer.length - 9);
				if (keyBuffer.toLowerCase() == 'meforever')
				{
					keyBuffer = '';
					eggActive = true;
					eggItems = [];
					eggVX = [];
					eggVY = [];
					eggVR = [];
					eggHue = [];
					titleScrollTimer = 0;
					for (m in members)
					{
						if (Std.isOfType(m, FlxSprite))
						{
							var spr:FlxSprite = cast m;
							eggItems.push(spr);
							var li:Int = -1;
							for (j in 0...eggLetters.length)
								if (eggLetters[j] == spr) { li = j; break; }
							if (li >= 0)
							{
								spr.visible = true;
								spr.alpha = 1;
								spr.x = FlxG.width * 0.5 - 90 + li * 12 + FlxG.random.float(-40, 40);
								spr.y = FlxG.height * 0.78 + FlxG.random.float(-30, 30);
								eggVX.push(FlxG.random.float(-300, 300));
								eggVY.push(FlxG.random.float(-720, -260));
								eggVR.push(FlxG.random.float(-360, 360));
							}
							else
							{
								eggVX.push(FlxG.random.float(-260, 260));
								eggVY.push(FlxG.random.float(-260, 260));
								eggVR.push(FlxG.random.float(-240, 240));
							}
							eggHue.push(FlxG.random.float(0, 360));
						}
					}
					FlxG.sound.play(Paths.sound('confirmMenu'));
					#if desktop
					windowVX = FlxG.random.float(-520, 520);
					windowVY = FlxG.random.float(-320, 320);
					if (windowVX > -250 && windowVX < 250) windowVX = 320 * (FlxG.random.bool(50) ? 1 : -1);
					if (windowVY > -40 && windowVY < 40) windowVY = 200;
					#end
				}
			}
			if (eggActive)
			{
				for (i in 0...eggItems.length)
				{
					var spr:FlxSprite = eggItems[i];
					eggVX[i] += FlxG.random.float(-160, 160) * elapsed;
					eggVY[i] += FlxG.random.float(-160, 160) * elapsed;
					eggVR[i] += FlxG.random.float(-120, 120) * elapsed;
					spr.x += eggVX[i] * elapsed;
					spr.y += eggVY[i] * elapsed;
					var halfDiag:Float = Math.sqrt(spr.width * spr.width + spr.height * spr.height) * 0.5;
					if (spr.x < halfDiag) { spr.x = halfDiag; eggVX[i] = Math.abs(eggVX[i]); }
					if (spr.x > FlxG.width - halfDiag) { spr.x = FlxG.width - halfDiag; eggVX[i] = -Math.abs(eggVX[i]); }
					if (spr.y < halfDiag) { spr.y = halfDiag; eggVY[i] = Math.abs(eggVY[i]); }
					if (spr.y > FlxG.height - halfDiag) { spr.y = FlxG.height - halfDiag; eggVY[i] = -Math.abs(eggVY[i]); }
					spr.angle += eggVR[i] * elapsed;
					eggHue[i] = (eggHue[i] + 600 * elapsed) % 360;
					spr.color = FlxColor.fromHSB(eggHue[i], 0.85, 1);
				}
				titleScrollTimer += elapsed;
				if (titleScrollTimer >= 0.03)
				{
					titleScrollTimer -= 0.03;
					baseWindowTitle = baseWindowTitle.charAt(baseWindowTitle.length - 1)
						+ baseWindowTitle.substring(0, baseWindowTitle.length - 1);
					Lib.application.window.title = baseWindowTitle;
				}
				#if desktop
				windowVX += FlxG.random.float(-40, 40) * elapsed;
				windowVY += FlxG.random.float(-40, 40) * elapsed;
				var win = Lib.application.window;
				win.x = Std.int(win.x + windowVX * elapsed);
				win.y = Std.int(win.y + windowVY * elapsed);
				var db = win.display.bounds;
				if (win.x < db.x) { win.x = Std.int(db.x); windowVX = Math.abs(windowVX); }
				if (win.x + win.width > db.x + db.width) { win.x = Std.int(db.x + db.width - win.width); windowVX = -Math.abs(windowVX); }
				if (win.y < db.y) { win.y = Std.int(db.y); windowVY = Math.abs(windowVY); }
				if (win.y + win.height > db.y + db.height) { win.y = Std.int(db.y + db.height - win.height); windowVY = -Math.abs(windowVY); }
				#end
			}
		}

		super.update(elapsed);
	}

	// ===== 鼠标控制（全部基于屏幕坐标） =====
	function updateMouseControl()
	{
		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		// 触屏：手指抬起且未滑动才算点击，拖动滚动菜单时不误选
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

		// 键盘接管后：鼠标必须物理移动超过阈值才恢复跟随
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		// 滚轮控制：上滚上一个、下滚下一个
		if (FlxG.mouse.wheel != 0)
		{
			mouseActive = true;
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
		}

		// 返回按钮：悬停高亮，点击返回标题界面
		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			mouseActive = true;
			selectedSomethin = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new TitleState());
		}

		// 新版本文字：悬停高亮，点击打开 GitHub Releases 页
		if (updateLinkText != null)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;
			var overLink:Bool = mx >= updateLinkText.x && mx <= updateLinkText.x + updateLinkText.width
				&& my >= updateLinkText.y && my <= updateLinkText.y + updateLinkText.height;
			updateLinkText.color = overLink ? FlxColor.WHITE : 0xFFFFD166;
			if (clickPressed && overLink)
			{
				mouseActive = true;
				CoolUtil.browserLoad('https://github.com/Bonus-XK/FNF-MeteoricEngine/releases');
			}
		}

		// 触控/点击只负责选中，真正进入由 A 键（virtualpad A / Enter / 手柄 A）触发
		if (clickPressed)
		{
			var clickID:Int = getHoveredRowID();
			if (clickID >= 0)
			{
				mouseActive = true;
				if (clickID != curSelected)
				{
					changeSelection(clickID - curSelected);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
			}
		}
	}

	function takeKeyboardControl()
	{
		mouseActive = false;
		mouseLockX = FlxG.mouse.screenX;
		mouseLockY = FlxG.mouse.screenY;
	}

	function getHoveredRowID():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...rows.length)
		{
			var row:MenuText = rows[r];
			if (!row.visible) continue;
			if (mx >= LIST_X - 12 && mx <= LIST_X + PANEL_L_W - 40 && my >= row.y - 8 && my <= row.y + 46)
				return r + scrollOffset;
		}
		return -1;
	}

	function changeSelection(huh:Int = 0)
	{
		curSelected += huh;

		if (curSelected >= optionShit.length)
			curSelected = 0;
		if (curSelected < 0)
			curSelected = optionShit.length - 1;

		var leItem:Array<Dynamic> = optionShit[curSelected];
		var nameStr:String = leItem[1];
		var descStr:String = leItem[2];
		var actionStr:String = leItem[0] == 'donate' ? '按 A 打开赞助页面' : '按 A / Enter 进入';

		// 列表滚动：超出可视行数时整体上移
		scrollOffset = (curSelected >= ROWS_VISIBLE) ? curSelected - ROWS_VISIBLE + 1 : 0;

		// 防文字跳舞：内容未变化时不重绘
		if (lastItemName != nameStr) { lastItemName = nameStr; itemNameText.text = nameStr; itemNameText.updateHitbox(); }
		if (lastDesc != descStr) { lastDesc = descStr; descText.text = descStr; descText.updateHitbox(); }
		if (lastAction != actionStr) { lastAction = actionStr; actionText.text = actionStr; actionText.updateHitbox(); }

		// 行状态
		for (r in 0...rows.length)
		{
			var row:MenuText = rows[r];
			var idx:Int = r + scrollOffset;
			if (idx >= optionShit.length)
			{
				row.visible = false;
				continue;
			}
			row.visible = true;
			row.text = optionShit[idx][1];
			row.updateHitbox();
			var isSel:Bool = (idx == curSelected);
			row.alpha = isSel ? 1 : 0.78;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
		}

		// 高亮条移动
		var barY:Float = LIST_Y - 3 + ((curSelected - scrollOffset) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});

		// 背景色过渡
		var newColor:Int = leItem[3];
		if (bg.color != newColor)
		{
			if (colorTween != null) { colorTween.cancel(); colorTween = null; }
			colorTween = FlxTween.color(bg, 0.4, bg.color, newColor, {ease: FlxEase.quadOut});
		}

		callUIScripts('onChangeSelection', [curSelected, leItem[0]]);
	}

	function selectItem()
	{
		var daChoice:String = optionShit[curSelected][0];
		callUIScripts('onConfirm', [daChoice]);

		if (daChoice == 'donate')
		{
			CoolUtil.browserLoad('https://ninja-muffin24.itch.io/funkin');
			return;
		}

		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('confirmMenu'));

		switch (daChoice)
		{
			case 'story_mode':
				MusicBeatState.switchState(new StoryMenuState());
			case 'freeplay':
				MusicBeatState.switchState(new FreeplayState());
			case 'online':
				MusicBeatState.switchState(new OnlineMenuState());
			#if MODS_ALLOWED
			case 'mods':
				MusicBeatState.switchState(new ModsMenuState());
			#end
			#if ACHIEVEMENTS_ALLOWED
			case 'awards':
				MusicBeatState.switchState(new AchievementsMenuState());
			#end
			case 'credits':
				MusicBeatState.switchState(new CreditsState());
			case 'options':
				LoadingState.loadAndSwitchState(new OptionsState());
				OptionsState.onPlayState = false;
				if (PlayState.SONG != null)
				{
					PlayState.SONG.arrowSkin = null;
					PlayState.SONG.splashSkin = null;
				}
			case 'old_menu':
				MusicBeatState.switchState(new OldMenuState());
			case 'crash_test':
				throw '崩溃测试：这是故意触发的异常，用来验证游戏内报错系统。';
		}
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
