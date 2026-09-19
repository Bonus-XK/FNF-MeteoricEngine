package states;

import backend.WheelScroll;
import backend.CrashHandler;

import objects.BackButton;
import objects.AchievementPopup;
import backend.Achievements;

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

	// ===== 右侧列表布局：滚动方案 + 帧高自适应间距（不再拥挤） =====
	// 历轮查实并保留的真修复（与滚动/静态无关，属几何正确性）：
	//   ① 右缘不再写死 1220（窄窗口会被裁），改为按窗口宽度留白；
	//   ② 建项时 addByPrefix('selected') 会把**白帧**设为当前帧，而白帧比 idle 帧大很多
	//      （story_mode: 796x181 vs 615x122），必须先复位 idle 再 updateHitbox，
	//      否则尺寸/offset 全按白帧算，整列错位；
	//   ③ 对齐一律按"当前帧"（frame.width/height 为可见内容，sourceSize 为含边距整帧）换算，
	//      不再混用 updateHitbox 的整帧 width/height。
	//   ④ 本轮新增：**间距与缩放按真实帧高自适应**。旧方案固定 ROW_GAP=150 且缩放 1.0，
	//      而 8 项的最高白帧 192px > 150px —— 选中项与相邻项间距只剩 46px，这正是"拥挤"的
	//      量化来源（8 项 × 150 = 1200px 需求 > 720px 屏高，列表永远满屏，只能靠滚动看全）。
	//      现在行距 = 最高可见帧高 × (1 + LIST_ROW_PADDING)，零叠压。
	static final LIST_RIGHT_MARGIN_RATIO:Float = 0.12; // 右边距 = 窗口宽 × 12%
	static final LIST_RIGHT_MARGIN_MIN:Float = 8;      // 右缘距窗口右边的绝对下限
	static final LIST_MARGIN_SIDE_MIN:Float = 6;       // 最宽项左缘距窗口左边的下限
	static final LIST_CENTER_Y:Float = 360; // 选中项中心 Y（恒定居中）
	static final LIST_SAFE_TOP:Float = 96;  // 列表可见内容上安全线（避开左上 FNF 标志）
	static final LIST_SAFE_BOTTOM:Float = 624; // 下安全线（避开左下版本信息 / 底部提示行）
	static final LIST_ROW_SCALE_BASE:Float = 0.85; // 8 项时的整列缩放（少项时向 1.0 放大）
	static final LIST_ROW_SCALE_MIN:Float = 0.78;  // 整列缩放硬下限（绝不缩到看不清）
	static final LIST_ROW_PADDING:Float = 0.10;    // 相邻项之间的额外留白比例（0.10 = 再留 10% 帧高）
	static final LIST_TARGET_VISIBLE_H:Float = 132; // 每项在 1280×720 上的舒适竖向占位（用于少项时自动放大）
	static final SCROLL_LERP:Float = 14;    // 时间插值系数（Freeplay 同款手感）
	static final INFO_ROW_Y:Float = 684;    // 底部信息行（左：操作提示 / 右：联机入口）
	/** 菜单项右缘 x（随窗口宽度计算，避免窄窗口/非 16:9 时贴边被裁）。 */
	var listRightX:Float = 1120;
	/** 整列缩放（按项数自适应：8 项 0.85，项数少时更大）。 */
	var rowScale:Float = LIST_ROW_SCALE_BASE;
	/** 相邻项中心间距（= 最高可见帧高 × (1 + LIST_ROW_PADDING) × rowScale，绝不叠压）。 */
	var rowPitch:Float = 180;

	var menuItems:FlxTypedGroup<FlxSprite>;

	var optionShit:Array<String> = [
		'story_mode',
		'freeplay',
		#if MODS_ALLOWED 'mods', #end
		#if ACHIEVEMENTS_ALLOWED 'awards', #end
		'online',   // 美术取自 Psych Online（assets/preload/images/mainmenu/menu_online.*）
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

		// ---- 精灵菜单项（右对齐竖排，选中项恒在 LIST_CENTER_Y，列表整体滚动） ----
		// 缩放 rowScale 在【建项前】设好：updateHitbox 的量算必须先带缩放，才能算出正确 offset。
		rowScale = computeRowScale(optionShit.length);
		menuItems = new FlxTypedGroup<FlxSprite>();
		add(menuItems);

		if (optionShit.length > 0)
		{
			for (i in 0...optionShit.length)
			{
				var menuItem:FlxSprite = new FlxSprite();
				menuItem.antialiasing = ClientPrefs.data.antialiasing;
				menuItem.frames = Paths.getSparrowAtlas('mainmenu/menu_' + optionShit[i]);
				menuItem.animation.addByPrefix('idle', optionShit[i] + " basic", 24);
				menuItem.animation.addByPrefix('selected', optionShit[i] + " white", 24);
				// 必须复位到 idle 再量：addByPrefix 会把最后添加的白帧设为当前帧，
				// 白帧比 idle 帧大得多，直接 updateHitbox 会把尺寸/offset 全按白帧算。
				menuItem.animation.play('idle', true);
				menuItem.scale.set(rowScale, rowScale);
				menuItem.updateHitbox();
				// 注意：千万不要再调 centerOffsets()（旧代码这里有一行）——
				// 它会把 offset 重写为居中值，而下方对齐换算依赖"XML 帧偏移"（frameX/frameY 取负）。
				menuItems.add(menuItem);
			}

			// ---- 先量原始帧（未缩放口径），排完版再统一乘 rowScale（padding 不能平方缩放）----
			var maxIdleH:Float = 0;
			var maxSelH:Float = 0;
			var maxSelW:Float = 0;
			var maxPadL:Float = 0;
			for (j in 0...menuItems.members.length)
			{
				var spr:FlxSprite = menuItems.members[j];
				var hIdle:Float = itemIdleVisHeight(spr);
				var hSel:Float = itemSelVisHeight(spr);
				var wSel:Float = itemSelVisWidth(spr);
				var padL:Float = itemFrameVisPadLeft(spr);
				if (hIdle > maxIdleH) maxIdleH = hIdle;
				if (hSel > maxSelH) maxSelH = hSel;
				if (wSel > maxSelW) maxSelW = wSel;
				if (padL > maxPadL) maxPadL = padL;
			}

			// ① 项数少时把缩放放大（视觉不变小），上限 1.0；项数多则保持基准
			if (optionShit.length < 8)
			{
				var fitScale:Float = 1.0;
				if (maxSelH > 0)
					fitScale = Math.min(1.0, LIST_TARGET_VISIBLE_H / maxSelH);
				if (fitScale > rowScale)
				{
					rowScale = fitScale;
					for (j in 0...menuItems.members.length)
						applyRowScale(menuItems.members[j]);
				}
			}

			// ② 行距 = 最高可见帧高（选中白帧优先）× (1 + 留白) × 缩放；零叠压
			var maxVisibleH:Float = Math.max(maxIdleH, maxSelH);
			if (maxVisibleH > 0)
				rowPitch = Math.max(1, Std.int(maxVisibleH * (1 + LIST_ROW_PADDING) * rowScale + 0.5));

			// ③ 右缘按窗口宽度算，并用最宽项（含帧内透明边距）反推，保证整列不进裁剪区
			var visWidest:Float = (maxSelW + maxPadL) * rowScale;
			var margin:Float = FlxG.width * LIST_RIGHT_MARGIN_RATIO;
			if (margin < LIST_RIGHT_MARGIN_MIN) margin = LIST_RIGHT_MARGIN_MIN;
			if (visWidest > 0 && FlxG.width - visWidest - margin < LIST_MARGIN_SIDE_MIN)
				margin = Math.max(LIST_RIGHT_MARGIN_MIN, FlxG.width - visWidest - LIST_MARGIN_SIDE_MIN);
			listRightX = FlxG.width - margin;
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

		// 联机入口已改为列表项（optionShit 中的 'online'，美术取自 Psych Online），
		// 原先右下角那个"临时文字链接"（等美术图用）随之下架，避免同一入口出现两处。

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

		// ---- 底部提示（左对齐；宽度收窄到 960，给右下角联机入口让位，不再横跨全屏） ----
		var hint:FlxText = new FlxText(40, INFO_ROW_Y, 960, '触控/滚轮 选择 · A / Enter 确认 · Esc 返回', 16);
		hint.setFormat(Paths.font('future.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
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

		// 节拍基准复位：清掉上一首歌残留的 Conductor.bpm / bpmChangeMap，
		// 否则打完 BPM 不同的歌回到本界面，整屏节拍跳动的频率会跟着那首歌变。
		resetMenuBeat();

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
			Conductor.syncToMusic();

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
				bridge.EditorBridge.openMasterEditor();
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
				var tx:Float = itemTargetX(spr);
				var ty:Float = itemTargetY(i) - itemVisHeight(spr) * 0.5 + spr.offset.y; // 可见内容中心→y 属性
				if (spr.width <= 0 || spr.height <= 0) { tx = spr.x; ty = spr.y; } // 素材缺失：原地不动，避免滑到屏幕外
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
		// 联机入口已是列表项 'online'（见 optionShit），点击走 selectItem() 的统一分支

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
			// 容差按行距自适应：行距越大给得越宽，但不会与相邻项重叠命中
			if (mx >= spr.x - 12 && mx <= spr.x + spr.width + 12
				&& my >= spr.y - hitTolY() && my <= spr.y + spr.height + hitTolY())
				return i;
		}
		return -1;
	}

	// ===== 对齐换算（统一按"当前帧"口径，绝不用 updateHitbox 的整帧 width/height 混算）=====
	// 帧模型：frame.width/height = 被裁剪段尺寸（= 可见内容）；sourceSize = 含边距整帧；
	//         精灵 offset = -0.5(scale*frameSize - frameSize)（与 XML 帧偏移无关，缩放后仍还原正确）；
	//         frame.offset = XML 的 frameX/frameY 取负（内容在整帧内的左上留白）。
	// 两条口径必须分清：
	//   带帧后缀的（itemFrameVis*）= **原始未缩放**像素，用于排版量算（行距/右缘），绝不参与定位；
	//   不带的（itemVis*）= **已乘 rowScale**，用于对齐与插值定位。
	function itemFrameVisPadLeft(spr:FlxSprite):Float
	{
		var f = spr.frame;
		return f == null ? 0 : (f.sourceSize.x - f.frame.width - f.offset.x);
	}

	function itemFrameVisWidth(spr:FlxSprite):Float
	{
		var f = spr.frame;
		return f == null ? 0 : f.frame.width;
	}

	function itemFrameVisHeight(spr:FlxSprite):Float
	{
		var f = spr.frame;
		return f == null ? 0 : f.frame.height;
	}

	function itemVisWidth(spr:FlxSprite):Float
	{
		return itemFrameVisWidth(spr) * rowScale;
	}

	function itemVisHeight(spr:FlxSprite):Float
	{
		return itemFrameVisHeight(spr) * rowScale;
	}

	function itemVisPadLeft(spr:FlxSprite):Float
	{
		return itemFrameVisPadLeft(spr) * rowScale;
	}

	/** 整列缩放：8 项及以上用基准（0.85），项数少时向 1.0 放大（避免无谓缩小）。 */
	function computeRowScale(count:Int):Float
	{
		if (count >= 8) return LIST_ROW_SCALE_BASE;
		var s:Float = LIST_ROW_SCALE_BASE + (LIST_ROW_SCALE_BASE * (8 - count) / 8) * 1.15;
		return Math.min(1.0, Math.max(LIST_ROW_SCALE_BASE, s));
	}

	/** 图集里某个动画的最大帧尺寸（**原始未缩放**像素）。
	 *  API 依据（本工程实际编译版本 flixel 6.x，两次编译验证）：
	 *   - FlxAnimationController **没有** `get()` / `getByName()`；
	 *   - FlxFramesCollection 有 `framesHash:Map<String, FlxFrame>`（帧名 → 帧），
	 *     帧名即 Sparrow 图集里的 `<SubTexture name="...">`（如 'story_mode basic0000'）；
	 *   - 动画名由 addByPrefix(AnimName, Prefix) 建立：idle ↔ '<id> basic'、selected ↔ '<id> white'。 */
	function maxAnimFrameSize(spr:FlxSprite, animName:String, wantWidth:Bool):Float
	{
		var current:Float = wantWidth ? itemFrameVisWidth(spr) : itemFrameVisHeight(spr);
		if (spr.frames == null || spr.frames.framesHash == null) return current;
		var wantSel:Bool = (animName == 'selected');
		var m:Float = 0;
		for (fname in spr.frames.framesHash.keys())
		{
			if (fname == null) continue;
			var iSel:Int = fname.indexOf(' white');
			var iIdle:Int = fname.indexOf(' basic');
			var isSel:Bool = (iSel >= 0 && (iIdle < 0 || iSel < iIdle));
			if (isSel != wantSel) continue;
			var fr = spr.frames.framesHash.get(fname);
			if (fr == null) continue;
			var v:Float = wantWidth ? fr.frame.width : fr.frame.height;
			if (v > m) m = v;
		}
		return m > 0 ? m : current;
	}

	/** 该图集里最大的 idle 帧高（原始尺寸）：行距要容得下所有未选中项。 */
	function itemIdleVisHeight(spr:FlxSprite):Float
	{
		return maxAnimFrameSize(spr, 'idle', false);
	}

	/** 该图集里最大的 selected 白帧高（原始尺寸）：行距的真正上限。 */
	function itemSelVisHeight(spr:FlxSprite):Float
	{
		return maxAnimFrameSize(spr, 'selected', false);
	}

	/** 该图集里最大的 selected 白帧宽（原始尺寸）：右缘/左缘越界判定用。 */
	function itemSelVisWidth(spr:FlxSprite):Float
	{
		return maxAnimFrameSize(spr, 'selected', true);
	}

	/** 按当前 rowScale 应用缩放并重算命中盒。缩放必须在 updateHitbox 之前设好。 */
	function applyRowScale(spr:FlxSprite):Void
	{
		spr.scale.set(rowScale, rowScale);
		spr.updateHitbox();
	}

	/** 悬浮命中框的竖向容差：取行距的 20%，上限 20px —— 行距变大也不会与相邻项重叠命中。 */
	function hitTolY():Float
	{
		return Math.min(20, rowPitch * 0.2);
	}

	/** 把该项的可见内容右缘对齐到 listRightX（changeItem 里在动画切换后重新纠偏，
	 *  因为 selected 白帧比 idle 帧大，尺寸/offset 会变）。 */
	function alignItemX(spr:FlxSprite):Void
	{
		spr.x = listRightX - itemVisPadLeft(spr) - itemVisWidth(spr) + spr.offset.x;
	}

	/** 把该项的可见内容中心对齐到目标 y。 */
	function alignItemY(spr:FlxSprite, targetCenterY:Float):Void
	{
		spr.y = targetCenterY - itemVisHeight(spr) * 0.5 + spr.offset.y;
	}

	// 目标位置计算（滚动方案：y 随选中项位移，选中项恒在 LIST_CENTER_Y）
	function itemTargetX(spr:FlxSprite):Float
	{
		return listRightX - itemVisPadLeft(spr) - itemVisWidth(spr) + spr.offset.x;
	}

	function itemTargetY(i:Int):Float
	{
		// 返回该项**可见内容中心 y**。
		// 选中项恒在 LIST_CENTER_Y（滚动方案的设计前提）；仅当"整列总高 + 上下安全边距"
		// 能完整放进屏幕时，才把整列纵向居中，避免少项时列表贴顶。
		var center:Float = LIST_CENTER_Y + (i - curSelected) * rowPitch;
		var totalH:Float = rowPitch * optionShit.length;
		var availH:Float = (LIST_SAFE_TOP + (FlxG.height - LIST_SAFE_BOTTOM));
		if (totalH <= availH)
			return center + (availH * 0.5 - totalH * 0.5 + LIST_SAFE_TOP) - LIST_CENTER_Y;
		return center;
	}

	// 进入界面时直接把菜单项吸附到目标位（避免从 0,0 滑入）
	function snapItems()
	{
		for (i in 0...menuItems.members.length)
		{
			var spr:FlxSprite = menuItems.members[i];
			if (spr == null) continue;
			alignItemX(spr);
			alignItemY(spr, itemTargetY(i));
			spr.alpha = (i == curSelected) ? 1 : 0.55;
		}
	}

	function changeItem(huh:Int = 0)
	{
		// 只做三件事：切动画、改 curSelected、更新 α。**Y 一律不在这里赋值** ——
		// 位置全部交给 update() 里的每帧 lerp 平滑滑动（选中项与其它项走同一条路径）。
		// 曾经这里对旧/新选中项调 alignItemY(...) 硬赋值：结果选中项瞬移到中心、
		// 其它项平滑滑动，观感割裂。X 仍在这里对齐：idle/selected 帧宽与 offset 不同，
		// 不重算就会横向错位（列表无水平滚动，故 X 对齐不会产生可见跳变）。
		if (menuItems.members[curSelected] != null)
		{
			var prev:FlxSprite = menuItems.members[curSelected];
			prev.animation.play('idle');
			prev.updateHitbox();
			alignItemX(prev); // 帧尺寸变化（idle/selected 不同）后重新对齐可见内容右缘
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
			alignItemX(sel);
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
				case 'online':
					MusicBeatState.switchState(new OnlineMenuState());
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
