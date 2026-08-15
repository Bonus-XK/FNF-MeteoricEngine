package states;

import objects.BackButton;
import objects.Alphabet;
import objects.AchievementPopup;
import backend.Achievements;

import states.editors.MasterEditorMenu;
import options.OptionsState;

import flixel.FlxObject;
import flixel.addons.transition.FlxTransitionableState;
import flixel.effects.FlxFlicker;

import openfl.Lib;

// 旧版本（1.0.4）经典主界面：Alphabet 字母菜单 + 相机跟随 + 品红闪烁
class OldMenuState extends MusicBeatState
{
	public static var curSelected:Int = 0;

	// Alphabet 只支持字母/数字/部分符号，这里用经典英文菜单名
	var optionShit:Array<String> = [
		'STORY MODE',
		'FREEPLAY',
		#if MODS_ALLOWED 'MODS', #end
		#if ACHIEVEMENTS_ALLOWED 'AWARDS', #end
		'CREDITS',
		#if !switch 'DONATE', #end
		'OPTIONS'
	];

	static final ROW_GAP:Float = 110;
	static final BASE_Y:Float = 150;
	static final FAN_X:Float = 60;

	var menuItems:FlxTypedGroup<Alphabet>;
	var magenta:FlxSprite;
	var camFollow:FlxObject;
	var backBtn:BackButton;
	var selectedSomethin:Bool = false;

	// ===== 鼠标/键盘输入分离 =====
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	static final MOUSE_REACTIVATE_DIST:Float = 10;

	var camGame:FlxCamera;
	var camAchievement:FlxCamera;

	override function create()
	{
		trace('OldMenuState: create');
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Classic Menu";

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

		var yScroll:Float = Math.max(0.25 - (0.05 * (optionShit.length - 4)), 0.1);
		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set(0, yScroll);
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);

		magenta = new FlxSprite(-80).loadGraphic(Paths.image('menuDesat'));
		magenta.antialiasing = ClientPrefs.data.antialiasing;
		magenta.scrollFactor.set(0, yScroll);
		magenta.setGraphicSize(Std.int(magenta.width * 1.175));
		magenta.updateHitbox();
		magenta.screenCenter();
		magenta.visible = false;
		magenta.color = 0xFFfd719b;
		add(magenta);

		// ---- Alphabet 菜单项（经典字母菜单） ----
		menuItems = new FlxTypedGroup<Alphabet>();
		add(menuItems);

		for (i in 0...optionShit.length)
		{
			var menuItem:Alphabet = new Alphabet(0, 0, optionShit[i], true);
			menuItem.isMenuItem = true;
			menuItem.ID = i;
			menuItem.screenCenter(X);
			menuItem.startPosition.x = menuItem.x;
			menuItem.startPosition.y = BASE_Y + (i * ROW_GAP);
			menuItem.distancePerItem.x = FAN_X;
			menuItem.distancePerItem.y = 0;
			menuItems.add(menuItem);
		}

		FlxG.camera.follow(camFollow, null, 0);

		// ---- 版本信息（固定屏幕） ----
		if (TitleState.mainUpdateCheck)
		{
			var verText:FlxText = new FlxText(12, 12, 0, 'Meteoric Engine v' + Main.meVersion + '（旧版本）', 16);
			verText.scrollFactor.set();
			verText.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			verText.borderSize = 2;
			add(verText);

			var updText:FlxText = new FlxText(12, 34, 0, '新版本：' + TitleState.updateVersion, 16);
			updText.scrollFactor.set();
			updText.setFormat(Paths.font("future.ttf"), 16, 0xFFFFD166, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			updText.borderSize = 2;
			add(updText);
		}
		else
		{
			var verText:FlxText = new FlxText(12, 12, 0, 'Meteoric Engine v' + Main.meVersion, 16);
			verText.scrollFactor.set();
			verText.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			verText.borderSize = 2;
			add(verText);
		}

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(0, 676, FlxG.width, '经典界面 · 触控/滚轮 选择 · A / Enter 确认 · Esc 返回', 16);
		hint.scrollFactor.set();
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hint.borderSize = 2;
		add(hint);

		// ---- 返回按钮（回新主界面） ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		backBtn.spr.scrollFactor.set();
		backBtn.label.scrollFactor.set();
		backBtn.glow.scrollFactor.set();
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		changeItem();

		#if ACHIEVEMENTS_ALLOWED
		Achievements.loadAchievements();
		var leDate = Date.now();
		if (leDate.getDay() == 5 && leDate.getHours() >= 18) {
			var achieveID:Int = Achievements.getAchievementIndex('friday_night_play');
			if(!Achievements.isAchievementUnlocked(Achievements.achievementsStuff[achieveID][2])) {
				Achievements.achievementsMap.set(Achievements.achievementsStuff[achieveID][2], true);
				giveAchievement();
				ClientPrefs.saveSettings();
			}
		}
		#end

		super.create();
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
		if (FlxG.sound.music.volume < 0.8)
		{
			FlxG.sound.music.volume += 0.5 * elapsed;
			if(FreeplayState.vocals != null) FreeplayState.vocals.volume += 0.5 * elapsed;
		}
		FlxG.camera.followLerp = FlxMath.bound(elapsed * 9 / (FlxG.updateFramerate / 60), 0, 1);

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
				MusicBeatState.switchState(new MainMenuState());
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
		}

		super.update(elapsed);
	}

	// ===== 鼠标控制（世界坐标，不受相机移动影响） =====
	function updateMouseControl()
	{
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		if (FlxG.mouse.wheel != 0)
		{
			mouseActive = true;
			FlxG.sound.play(Paths.sound('scrollMenu'));
			changeItem(FlxG.mouse.wheel > 0 ? -1 : 1);
		}

		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (FlxG.mouse.justPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			mouseActive = true;
			selectedSomethin = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}

		if (FlxG.mouse.justPressed)
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
		var world = FlxG.mouse.getWorldPosition(camGame);
		for (i in 0...optionShit.length)
		{
			var rowY:Float = BASE_Y + (i * ROW_GAP);
			if (world.x >= 280 && world.x <= 1000 && world.y >= rowY - 35 && world.y <= rowY + 45)
				return i;
		}
		return -1;
	}

	function changeItem(huh:Int = 0)
	{
		curSelected += huh;

		if (curSelected >= menuItems.length)
			curSelected = 0;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;

		menuItems.forEach(function(spr:Alphabet)
		{
			spr.targetY = spr.ID - curSelected;
			spr.alpha = (spr.ID == curSelected) ? 1 : 0.6;
		});

		camFollow.setPosition(FlxG.width / 2, BASE_Y + (curSelected * ROW_GAP));
	}

	function selectItem()
	{
		if (optionShit[curSelected] == 'DONATE')
		{
			CoolUtil.browserLoad('https://ninja-muffin24.itch.io/funkin');
			return;
		}

		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('confirmMenu'));

		if(ClientPrefs.data.flashing) FlxFlicker.flicker(magenta, 1.1, 0.15, false);

		var daChoice:String = optionShit[curSelected];
		var selectedSpr:Alphabet = menuItems.members[curSelected];

		menuItems.forEach(function(spr:Alphabet)
		{
			if (curSelected != spr.ID)
			{
				FlxTween.tween(spr, {alpha: 0}, 0.4, {
					ease: FlxEase.quadOut,
					onComplete: function(twn:FlxTween)
					{
						spr.kill();
					}
				});
			}
		});

		if (selectedSpr != null)
			FlxFlicker.flicker(selectedSpr, 1, 0.06, false, false, function(flick:FlxFlicker)
			{
				doSwitch(daChoice);
			});
		else
			doSwitch(daChoice);
	}

	function doSwitch(daChoice:String)
	{
		switch (daChoice)
		{
			case 'STORY MODE':
				MusicBeatState.switchState(new StoryMenuState());
			case 'FREEPLAY':
				MusicBeatState.switchState(new FreeplayState());
			#if MODS_ALLOWED
			case 'MODS':
				MusicBeatState.switchState(new ModsMenuState());
			#end
			case 'AWARDS':
				MusicBeatState.switchState(new AchievementsMenuState());
			case 'CREDITS':
				MusicBeatState.switchState(new CreditsState());
			case 'OPTIONS':
				LoadingState.loadAndSwitchState(new OptionsState());
				OptionsState.onPlayState = false;
				if (PlayState.SONG != null)
				{
					PlayState.SONG.arrowSkin = null;
					PlayState.SONG.splashSkin = null;
				}
		}
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
