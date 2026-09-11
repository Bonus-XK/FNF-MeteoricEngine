package states.editors;

import backend.WeekData;

#if MODS_ALLOWED
import sys.FileSystem;
#end

import objects.Character;
import objects.BackButton;
import objects.MenuText;

import states.MainMenuState;
import states.FreeplayState;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flixel.group.FlxSpriteGroup;

import openfl.Lib;

class MasterEditorMenu extends MusicBeatState
{
	// ===== 布局常量（与主菜单一致） =====
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

	static final INFO_X:Float = 772;
	static final INFO_W:Float = 400;

	// 菜单项：ID / 名称 / 英文名 / 描述 / 背景色
	var optionShit:Array<Array<Dynamic>> = [
		['chart', '编谱器', 'Chart Editor', '创建并编辑谱面：音符、长条、事件、变速与角色设置。', 0xFF66DDFF],
		['character', '角色编辑器', 'Character Editor', '编辑角色的贴图、动画帧、镜头跟随与各类属性。', 0xFFDD88FF],
		['week', '周目编辑器', 'Week Editor', '编辑自由游玩中的周目结构与歌曲顺序。', 0xFF88E58A],
		['menuChar', '菜单角色编辑器', 'Menu Character Editor', '编辑主菜单与自由游玩界面展示的角色。', 0xFFFFD166],
		['dialogue', '对话编辑器', 'Dialogue Editor', '编辑游戏内对话脚本、演出与表情切换。', 0xFFFF8A8A],
		['dialogueChar', '对话立绘编辑器', 'Dialogue Portrait Editor', '编辑对话角色的立绘资源与动画。', 0xFFFF9E5E],
		['noteSplash', '音符溅射调试', 'Note Splash Debug', '调试音符打击特效的贴图与帧动画。', 0xFFB0B6FF]
	];

	var rows:Array<MenuText> = [];
	var itemNameText:FlxText;
	var descText:FlxText;
	var actionText:FlxText;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var lastItemName:String = '';
	var lastDesc:String = '';
	var lastAction:String = '';

	var bg:FlxSprite;
	var colorTween:FlxTween;
	var backBtn:BackButton;
	var selectedSomethin:Bool = false;

	var curSelected:Int = 0;
	var curDirectory:Int = 0;
	var directories:Array<String> = [null];
	var directoryTxt:FlxText;

	// ===== 鼠标/键盘输入分离 =====
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	static final MOUSE_REACTIVATE_DIST:Float = 10;

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Editors Menu";

		#if desktop
		DiscordClient.changePresence("Editors Main Menu", null);
		#end

		// ---- 背景 ----
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		add(bg);
		bg.color = optionShit[curSelected][4];

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 662, 1160, 48, 14));

		// ---- 标题 ----
		var leftTitle:FlxText = makeText(LIST_X, 100, 0, '编辑器菜单', 26);
		add(leftTitle);

		var rightTitle:FlxText = makeText(INFO_X, 100, 0, '选项说明', 26);
		add(rightTitle);

		// ---- 菜单行（静态行：切换时只移动高亮条） ----
		for (r in 0...optionShit.length)
		{
			var row:MenuText = new MenuText(LIST_X, LIST_Y + (r * ROW_GAP), '', true, 30);
			row.isMenuItem = false;
			row.ID = r;
			row.scrollFactor.set();
			add(row);
			rows.push(row);
		}

		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, 0x2EFFFFFF, null);
		add(selectorBar);

		// ---- 右侧信息 ----
		itemNameText = makeText(INFO_X, 165, INFO_W, '', 40, 0xFFFFFFFF);
		add(itemNameText);

		descText = makeText(INFO_X, 240, INFO_W, '', 24, 0xFFFFFFFF);
		add(descText);

		actionText = makeText(INFO_X, 555, INFO_W, '', 20, 0xFFD7D7E0);
		add(actionText);

		#if MODS_ALLOWED
		directoryTxt = makeText(INFO_X, 585, INFO_W, '', 15, 0xFFFFD166);
		add(directoryTxt);

		for (folder in Mods.getModDirectories())
		{
			directories.push(folder);
		}
		var found:Int = directories.indexOf(Mods.currentModDirectory);
		if (found > -1) curDirectory = found;
		changeDirectory();
		#end

		// ---- 底部提示 ----
		var hint:FlxText = makeText(40, 672, 1160, '触控/滚轮 选择 · A / Enter 确认 · ←/→ 切换模组 · Esc 返回主菜单', 16, 0xFFFFFFFF);
		hint.alignment = CENTER;
		add(hint);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		mouseLockX = FlxG.mouse.screenX;
		mouseLockY = FlxG.mouse.screenY;

		changeSelection();

		FlxG.mouse.visible = true;
		super.create();
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.8)
		{
			FlxG.sound.music.volume += 0.5 * elapsed;
			if (FreeplayState.vocals != null) FreeplayState.vocals.volume += 0.5 * elapsed;
		}

		if (!selectedSomethin)
		{
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
			#if MODS_ALLOWED
			if (controls.UI_LEFT_P)
			{
				takeKeyboardControl();
				changeDirectory(-1);
			}
			if (controls.UI_RIGHT_P)
			{
				takeKeyboardControl();
				changeDirectory(1);
			}
			#end

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
		}

		super.update(elapsed);
	}

	// ===== 鼠标控制 =====
	function updateMouseControl()
	{
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;

		backBtn.setHovered(mx, my);
		if (backBtn.over(mx, my) && FlxG.mouse.justPressed)
		{
			selectedSomethin = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
			return;
		}

		if (!mouseActive) return;

		var hoverID:Int = getHoveredRowID();
		if (hoverID >= 0 && hoverID != curSelected)
		{
			curSelected = hoverID;
			changeSelection(0);
		}

		// 点击只选中，进入由 A 键触发（上方 hover 已处理选中）
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
			if (mx >= LIST_X - 12 && mx <= LIST_X + PANEL_L_W - 40 && my >= row.y - 8 && my <= row.y + 46)
				return r;
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
		var descStr:String = leItem[2] + '\n\n' + leItem[3];
		var actionStr:String = '按 A / Enter 进入';

		// 防文字跳舞：内容未变化时不重绘
		if (lastItemName != nameStr) { lastItemName = nameStr; itemNameText.text = nameStr; itemNameText.updateHitbox(); }
		if (lastDesc != descStr) { lastDesc = descStr; descText.text = descStr; descText.updateHitbox(); }
		if (lastAction != actionStr) { lastAction = actionStr; actionText.text = actionStr; actionText.updateHitbox(); }

		// 行状态
		for (r in 0...rows.length)
		{
			var row:MenuText = rows[r];
			row.text = optionShit[r][1];
			row.updateHitbox();
			var isSel:Bool = (r == curSelected);
			row.alpha = isSel ? 1 : 0.78;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
		}

		// 高亮条移动
		var barY:Float = LIST_Y - 3 + (curSelected * ROW_GAP);
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});

		// 背景色过渡
		var newColor:Int = leItem[4];
		if (bg.color != newColor)
		{
			if (colorTween != null) { colorTween.cancel(); colorTween = null; }
			colorTween = FlxTween.color(bg, 0.4, bg.color, newColor, {ease: FlxEase.quadOut});
		}
	}

	#if MODS_ALLOWED
	function changeDirectory(change:Int = 0)
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		curDirectory += change;

		if (curDirectory < 0)
			curDirectory = directories.length - 1;
		if (curDirectory >= directories.length)
			curDirectory = 0;

		WeekData.setDirectoryFromWeek();
		if (directories[curDirectory] == null || directories[curDirectory].length < 1)
			directoryTxt.text = '模组：未选择（使用原版资源）';
		else
		{
			Mods.currentModDirectory = directories[curDirectory];
			directoryTxt.text = '模组：' + Mods.currentModDirectory;
		}
	}
	#end

	function selectItem()
	{
		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('confirmMenu'));

		switch (optionShit[curSelected][0])
		{
			case 'chart':
				LoadingState.loadAndSwitchState(new ChartingState(), false);
			case 'character':
				LoadingState.loadAndSwitchState(new CharacterEditorState(Character.DEFAULT_CHARACTER, false));
			case 'week':
				MusicBeatState.switchState(new WeekEditorState());
			case 'menuChar':
				MusicBeatState.switchState(new MenuCharacterEditorState());
			case 'dialogue':
				LoadingState.loadAndSwitchState(new DialogueEditorState(), false);
			case 'dialogueChar':
				LoadingState.loadAndSwitchState(new DialogueCharacterEditorState(), false);
			case 'noteSplash':
				LoadingState.loadAndSwitchState(new NoteSplashDebugState());
		}

		FlxG.sound.music.volume = 0;
		#if PRELOAD_ALL
		FreeplayState.destroyFreeplayVocals();
		#end
	}

	// ===== 样式辅助 =====
	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, ?color:Int = 0xFFD7D7E0):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('future.ttf'), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 2;
		t.scrollFactor.set();
		return t;
	}
}
