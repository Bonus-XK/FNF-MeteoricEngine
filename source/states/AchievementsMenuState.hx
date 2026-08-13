package states;

import objects.BackButton;
import flixel.util.FlxSpriteUtil;
import backend.Achievements;
import objects.AttachedAchievement;
import openfl.Lib;

class AchievementsMenuState extends MusicBeatState
{
	#if ACHIEVEMENTS_ALLOWED
	var options:Array<String> = [];
	private var grpOptions:FlxTypedGroup<MenuText>;
	var backBtn:BackButton;
	var mouseActive:Bool = true;  // 默认鼠标活跃：悬停即可滚动，键盘操作后冻结
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	private static var curSelected:Int = 0;
	private var achievementArray:Array<AttachedAchievement> = [];
	private var achievementIndex:Array<Int> = [];
	private var descText:FlxText;

	override function create() {
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Awards Menu";
		
		#if desktop
		DiscordClient.changePresence("Achievements Menu", null);
		#end

		var menuBG:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuBGBlue'));
		menuBG.antialiasing = ClientPrefs.data.antialiasing;
		menuBG.setGraphicSize(Std.int(menuBG.width * 1.1));
		menuBG.updateHitbox();
		menuBG.screenCenter();
		add(menuBG);

		grpOptions = new FlxTypedGroup<MenuText>();
		add(grpOptions);

		Achievements.loadAchievements();
		for (i in 0...Achievements.achievementsStuff.length) {
			if(!Achievements.achievementsStuff[i][3] || Achievements.achievementsMap.exists(Achievements.achievementsStuff[i][2])) {
				options.push(Achievements.achievementsStuff[i]);
				achievementIndex.push(i);
			}
		}

		for (i in 0...options.length) {
			var achieveName:String = Achievements.achievementsStuff[achievementIndex[i]][2];
			var optionText:MenuText = new MenuText(280, 300, Achievements.isAchievementUnlocked(achieveName) ? Achievements.achievementsStuff[achievementIndex[i]][0] : '?', false);
			optionText.isMenuItem = true;
			optionText.targetY = i - curSelected;
			optionText.snapToPosition();
			optionText.ID = i;
			grpOptions.add(optionText);

			var icon:AttachedAchievement = new AttachedAchievement(optionText.x - 105, optionText.y, achieveName);
			icon.sprTracker = optionText;
			achievementArray.push(icon);
			add(icon);
		}

		// 悬停高亮条 + 返回按钮
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		descText = new FlxText(150, 600, 980, "", 32);
		descText.setFormat(Paths.font("future.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.scrollFactor.set();
		descText.borderSize = 2.4;
		add(descText);
		changeSelection();
		FlxG.mouse.visible = true;

		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (controls.UI_UP_P) {
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P) {
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			changeSelection(1);
		}

		if (!controls.controllerMode)
		{
			if (!mouseActive)
			{
				var dx:Float = FlxG.mouse.screenX - mouseLockX;
				var dy:Float = FlxG.mouse.screenY - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			if (FlxG.mouse.wheel != 0)
			{
				mouseActive = true;
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
			}

			backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (FlxG.mouse.justPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}

			if (FlxG.mouse.justPressed)
			{
				var clickID:Int = getHoveredOptionID();
				if (clickID >= 0 && clickID != curSelected)
				{
					mouseActive = true;
					changeSelection(clickID - curSelected);
				}
			}
		}

		if (controls.BACK) {
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}
	}

	function getHoveredOptionID():Int
	{
		var hoveredID:Int = -1;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (item in grpOptions.members)
		{
			if (mx >= item.x && mx <= item.x + item.width && my >= item.y && my <= item.y + item.height)
				hoveredID = item.ID;
		}
		return hoveredID;
	}

	function changeSelection(change:Int = 0) {
		curSelected += change;
		if (curSelected < 0)
			curSelected = options.length - 1;
		if (curSelected >= options.length)
			curSelected = 0;

		var bullShit:Int = 0;

		for (item in grpOptions.members) {
			item.targetY = bullShit - curSelected;
			bullShit++;

			item.alpha = 0.6;
			if (item.targetY == 0) {
				item.alpha = 1;
			}
		}

		for (i in 0...achievementArray.length) {
			achievementArray[i].alpha = 0.6;
			if(i == curSelected) {
				achievementArray[i].alpha = 1;
			}
		}
		descText.text = Achievements.achievementsStuff[achievementIndex[curSelected]][1];
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
	#end
}
