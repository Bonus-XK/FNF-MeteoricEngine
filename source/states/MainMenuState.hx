package states;

import backend.WheelScroll;
import backend.CrashHandler;

import objects.BackButton;
import objects.AchievementPopup;
import backend.Achievements;

import states.editors.MasterEditorMenu;
import options.OptionsState;

import flixel.addons.transition.FlxTransitionableState;
import flixel.effects.FlxFlicker;
import flixel.math.FlxPoint;
import openfl.Lib;

// 经典主界面 v2：
// - 左侧：TitleState 同款 FNF 标志（logoBumpin，随节拍跳动）
// - 右侧：Psych 0.7.3 精灵菜单（英文 Art），右对齐竖排
// - 滚动：重写为时间插值平滑滑动（Freeplay 同款 elapsed*SCROLL_LERP），无相机跟随、无跳帧
// - 保留：版本号 + 可点击「新版本」GitHub 链接、可点击「联机」入口、
//   meforever / crash 彩蛋、鼠标/触控完整交互、< 返回按钮（回标题界面）。
class MainMenuState extends MusicBeatState
{
	public static var curSelected:Int = 0;

	var wheelScroll:WheelScroll = new WheelScroll(); // 滚轮限速（Freeplay 同款）

	// ===== 右侧列表布局 =====
	static final ITEM_RIGHT:Float = 1220;   // 菜单项右边缘（右对齐）
	static final LIST_CENTER_Y:Float = 360; // 选中项中心 Y
	static final ROW_GAP:Float = 130;       // 相邻项间距（经典 Psych 行距，避免叠压）
	static final SCROLL_LERP:Float = 14;    // 时间插值系数（Freeplay 同款手感）

	var menuItems:FlxTypedGroup<FlxSprite>;

	var optionShit:Array<String> = [
		'story_mode',
		'freeplay',
		#if MODS_ALLOWED 'mods', #end
		#if ACHIEVEMENTS_ALLOWED 'awards', #end
		'credits',
		#if !switch 'donate', #end
		'options'
	];
	// 注：多版本容器入口只放在「设置 → 容器」，不占主菜单。
	// 主菜单项必须有 mainmenu/menu_<name>.png 素材，容器目前没有美术资源。

	var logoBl:FlxSprite;
	var magenta:FlxSprite;

	var backBtn:BackButton;
	var verText:FlxText;
	var updateLinkText:FlxText;
	var onlineLinkText:FlxText;

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
	var selectedSomethin:Bool = false;

	override function create()
	{
		trace("DBG MainMenuState create");
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
		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		magenta = new FlxSprite(-80).loadGraphic(Paths.image('menuDesat'));
		magenta.antialiasing = ClientPrefs.data.antialiasing;
		magenta.setGraphicSize(Std.int(magenta.width * 1.175));
		magenta.updateHitbox();
		magenta.screenCenter();
		magenta.visible = false;
		magenta.color = 0xFFfd719b;
		add(magenta);

		// ---- FNF 标志（TitleState 同款 logoBumpin，0.6 倍放左上，随节拍跳动） ----
		logoBl = new FlxSprite(30, 70);
		logoBl.frames = Paths.getSparrowAtlas('logoBumpin');
		logoBl.antialiasing = ClientPrefs.data.antialiasing;
		logoBl.animation.addByPrefix('bump', 'logo bumpin', 24, false);
		logoBl.animation.play('bump');
		logoBl.scale.set(0.6, 0.6);
		logoBl.updateHitbox();
		add(logoBl);

		// ---- 精灵菜单项（右对齐竖排） ----
		menuItems = new FlxTypedGroup<FlxSprite>();
		add(menuItems);

		for (i in 0...optionShit.length)
		{
			var menuItem:FlxSprite = new FlxSprite();
			menuItem.antialiasing = ClientPrefs.data.antialiasing;
			menuItem.frames = Paths.getSparrowAtlas('mainmenu/menu_' + optionShit[i]);
			menuItem.animation.addByPrefix('idle', optionShit[i] + " basic", 24);
			menuItem.animation.addByPrefix('selected', optionShit[i] + " white", 24);
			menuItem.animation.play('idle');
			menuItem.updateHitbox();
			menuItems.add(menuItem);
		}

		changeItem();
		snapItems();

		// ---- 版本信息（左下角；完整保留新版显示：版本号 + 可点击 GitHub 新版本链接） ----
		if (TitleState.mainUpdateCheck)
		{
			verText = new FlxText(40, 560, 0, 'Meteoric Engine v' + Main.meVersion + '（旧版本）', 16);
			verText.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			verText.borderSize = 2;
			verText.scrollFactor.set();
			add(verText);

			updateLinkText = new FlxText(40, 582, 0, '新版本：' + TitleState.updateVersion + '（点击查看）', 16);
			updateLinkText.setFormat(Paths.font('future.ttf'), 16, 0xFFFFD166, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			updateLinkText.borderSize = 2;
			updateLinkText.scrollFactor.set();
			updateLinkText.updateHitbox();
			add(updateLinkText);
		}
		else
		{
			verText = new FlxText(40, 560, 0, 'Meteoric Engine v' + Main.meVersion, 16);
			verText.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			verText.borderSize = 2;
			verText.scrollFactor.set();
			add(verText);
		}

		// ---- 联机入口（可点击文字链接，位于版本区旁） ----
		onlineLinkText = new FlxText(40, (updateLinkText != null ? 604 : 582), 0, '联机：与好友实时对战（点击进入）', 16);
		onlineLinkText.setFormat(Paths.font('future.ttf'), 16, 0xFF8AD7FF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		onlineLinkText.borderSize = 2;
		onlineLinkText.scrollFactor.set();
		onlineLinkText.updateHitbox();
		add(onlineLinkText);

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

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(40, 672, 1160, '触控/滚轮 选择 · A / Enter 确认 · Esc 返回', 16);
		hint.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hint.borderSize = 2;
		hint.scrollFactor.set();
		add(hint);

		// ---- 返回按钮（< 返回标题界面） ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

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

	override function beatHit()
	{
		super.beatHit();
		if (ClientPrefs.data.menuBeatBump)
		{
			if (logoBl != null)
				logoBl.animation.play('bump', true);
			menuBeatBump();
		}
	}

	#if ACHIEVEMENTS_ALLOWED
	function giveAchievement() {
		add(new AchievementPopup('friday_night_play', camAchievement));
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		trace('Giving achievement "friday_night_play"');
	}
	#end

	override function update(elapsed:Float)
	{
		// 菜单音乐时间同步到 Conductor：节拍事件（beatHit）才能随背景音乐触发
		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		#if METEORIC_PROFILE
		backend.MeteoricProfile.begin();
		#end
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
				changeItem(-1);
			}

			if (controls.UI_DOWN_P)
			{
				takeKeyboardControl();
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeItem(1);
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
			if (controls.justPressed('debug_1'))
			{
				selectedSomethin = true;
				MusicBeatState.switchState(new MasterEditorMenu());
			}
			#end

			// ---- 彩蛋：键盘输入 meforever / crash ----
			var pressedKey:Int = FlxG.keys.firstJustPressed();
			if (pressedKey >= 65 && pressedKey <= 90)
			{
				keyBuffer += String.fromCharCode(pressedKey);
				if (keyBuffer.length > 9) keyBuffer = keyBuffer.substring(keyBuffer.length - 9);
				if (keyBuffer.toLowerCase() == 'crash')
				{
					// 彩蛋：输入 crash → 弹窗选择崩溃模式（Haxe 级报错 / 原生底层报错）
					keyBuffer = '';
					trace('[CRASH-TEST] 输入 crash，弹出崩溃模式选择');
					ClientPrefs.toggleVolumeKeys(false);
					openSubState(new CrashTestPrompt(function(choice:Int)
					{
						ClientPrefs.toggleVolumeKeys(true);
						switch (choice)
						{
							case 0:
								// Haxe 级报错：同步抛出未捕获异常（处于 update 链内 → uncaughtErrorEvents → 报错界面 + MeteoricEngine_*.txt）
								trace('[CRASH-TEST] 触发 Haxe 级报错');
								throw '手动 Haxe 崩溃测试（主菜单输入 crash 触发）';
							case 1:
								// 原生/底层报错：真实段错误（走信号处理器 → native_stack.txt）
								trace('[CRASH-TEST] 触发原生段错误');
								CrashHandler.triggerNativeCrash();
						}
					}));
				}
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

		// ---- 平滑滚动：菜单项时间插值滑向目标位（Freeplay 同款手感）----
		// 彩蛋激活时所有权交给彩蛋物理（字母乱飞），不再把精灵拉回列表
		if (!eggActive)
		{
			var lerp:Float = FlxMath.bound(elapsed * SCROLL_LERP, 0, 1);
			for (i in 0...menuItems.members.length)
			{
				var spr:FlxSprite = menuItems.members[i];
				if (spr == null || !spr.alive) continue;
				var tx:Float = ITEM_RIGHT - spr.width;
				var ty:Float = LIST_CENTER_Y + (i - curSelected) * ROW_GAP;
				var tAlpha:Float = (i == curSelected) ? 1 : 0.55;
				spr.x = FlxMath.lerp(spr.x, tx, lerp);
				spr.y = FlxMath.lerp(spr.y, ty, lerp);
				spr.alpha = FlxMath.lerp(spr.alpha, tAlpha, lerp);
			}
		}

		super.update(elapsed);

		#if METEORIC_PROFILE
		backend.MeteoricProfile.end('MainMenuState.update');
		#end
	}

	// ===== 鼠标控制（右侧列表用屏幕坐标命中；链接/返回按钮用屏幕坐标） =====
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
		var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
		if (wheelStep != 0)
		{
			mouseActive = true;
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeItem(wheelStep);
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

		// 联机文字：悬停高亮，点击进入联机界面
		if (onlineLinkText != null)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;
			var overLink:Bool = mx >= onlineLinkText.x && mx <= onlineLinkText.x + onlineLinkText.width
				&& my >= onlineLinkText.y && my <= onlineLinkText.y + onlineLinkText.height;
			onlineLinkText.color = overLink ? FlxColor.WHITE : 0xFF8AD7FF;
			if (clickPressed && overLink)
			{
				mouseActive = true;
				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('confirmMenu'));
				MusicBeatState.switchState(new OnlineMenuState());
			}
		}

		// 菜单行点击：点击不同项只选中，点击已选中项进入
		if (clickPressed)
		{
			var clickID:Int = getHoveredRowID();
			if (clickID >= 0)
			{
				mouseActive = true;
				if (clickID != curSelected)
				{
					changeItem(clickID - curSelected);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				else if (clickID == curSelected)
				{
					selectItem();
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
		// 用世界坐标命中（节拍跳动时相机 zoom 会变化，世界坐标映射不受影响）
		var wp:FlxPoint = FlxG.mouse.getWorldPosition(camGame);
		var mx:Float = wp.x;
		var my:Float = wp.y;
		wp.put();
		for (i in 0...menuItems.members.length)
		{
			var spr:FlxSprite = menuItems.members[i];
			if (spr == null || !spr.alive || spr.alpha <= 0.01) continue;
			if (mx >= spr.x - 25 && mx <= spr.x + spr.width + 25
				&& my >= spr.y - 30 && my <= spr.y + spr.height + 30)
				return i;
		}
		return -1;
	}

	// 目标位置计算
	function itemTargetX(spr:FlxSprite):Float
	{
		return ITEM_RIGHT - spr.width;
	}

	function itemTargetY(i:Int):Float
	{
		return LIST_CENTER_Y + (i - curSelected) * ROW_GAP;
	}

	// 进入界面时直接把菜单项吸附到目标位（避免从 0,0 滑入）
	function snapItems()
	{
		for (i in 0...menuItems.members.length)
		{
			var spr:FlxSprite = menuItems.members[i];
			if (spr == null) continue;
			spr.x = itemTargetX(spr);
			spr.y = itemTargetY(i);
			spr.alpha = (i == curSelected) ? 1 : 0.55;
		}
	}

	function changeItem(huh:Int = 0)
	{
		if (menuItems.members[curSelected] != null)
		{
			menuItems.members[curSelected].animation.play('idle');
			menuItems.members[curSelected].updateHitbox();
		}

		curSelected += huh;

		if (curSelected >= menuItems.length)
			curSelected = 0;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;

		var sel:FlxSprite = menuItems.members[curSelected];
		if (sel != null)
		{
			sel.animation.play('selected');
			sel.updateHitbox();
		}

		callUIScripts('onChangeSelection', [curSelected, optionShit[curSelected]]);
	}

	function selectItem()
	{
		var daChoice:String = optionShit[curSelected];
		callUIScripts('onConfirm', [daChoice]);

		if (daChoice == 'donate')
		{
			CoolUtil.browserLoad('https://ninja-muffin24.itch.io/funkin');
			return;
		}

		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('confirmMenu'));

		if (ClientPrefs.data.flashing)
			FlxFlicker.flicker(magenta, 1.1, 0.15, false);

		FlxFlicker.flicker(menuItems.members[curSelected], 0.4, 0.06, false, false, function(flick:FlxFlicker)
		{
			switch (daChoice)
			{
				case 'story_mode':
					MusicBeatState.switchState(new StoryMenuState());
				case 'freeplay':
					MusicBeatState.switchState(new FreeplayState());
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
			}
		});

		for (i in 0...menuItems.members.length)
		{
			if (i == curSelected)
				continue;
			var spr:FlxSprite = menuItems.members[i];
			FlxTween.tween(spr, {alpha: 0}, 0.4, {
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween)
				{
					spr.kill();
				}
			});
		}
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
