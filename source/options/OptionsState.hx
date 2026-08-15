package options;

import objects.BackButton;
import states.MainMenuState;
import backend.StageData;
import openfl.Lib;
import flixel.util.FlxSpriteUtil;

class OptionsState extends MusicBeatState
{
	// ===== 布局常量 =====
	static final PANEL_X:Float = 220;
	static final PANEL_Y:Float = 110;
	static final PANEL_W:Float = 840;
	static final PANEL_H:Float = 500;

	static final LIST_Y:Float = 200;
	static final ROW_GAP:Float = #if mobile 50 #else 56 #end;
	static final ROWS_VISIBLE:Int = #if mobile 8 #else 7 #end;

	var options:Array<String> = [
		'箭头配色', '按键设置', '调整延迟与Combo', '图像设置', '视觉与界面', '游戏设置', '自定义界面'
		#if mobile
		, '移动触控'
		#end
	];
	private static var curSelected:Int = 0;
	public static var onPlayState:Bool = false;

	var bg:FlxSprite;
	var rows:Array<FlxText> = [];
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var backBtn:BackButton;

	var mouseActive:Bool = true;   // 键盘操作后冻结，鼠标移动/滚轮/点击恢复
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var holdTime:Float = 0;
	var quitting:Bool = false;

	function openSelectedSubstate(label:String) {
		switch(label) {
			case '箭头配色':
				openSubState(new options.NotesSubState());
			case '按键设置':
				openSubState(new options.ControlsSubState());
			case '图像设置':
				openSubState(new options.GraphicsSettingsSubState());
			case '视觉与界面':
				openSubState(new options.VisualsUISubState());
			case '游戏设置':
				openSubState(new options.GameplaySettingsSubState());
			case '自定义界面':
				MusicBeatState.switchState(new options.HUDCustomizeState());
			case '调整延迟与Combo':
				MusicBeatState.switchState(new options.NoteOffsetState());
			#if mobile
			case '移动触控':
				openSubState(new objects.MobileControlsSubState());
			#end
		}
	}

	override function create() {
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - 设置菜单";

		#if desktop
		DiscordClient.changePresence("设置菜单", null);
		#end

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFFea71fd;
		bg.screenCenter();
		add(bg);

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22));
		add(makePanel(120, 662, 1040, 48, 14));

		// ---- 标题 ----
		var title:FlxText = new FlxText(PANEL_X, PANEL_Y + 40, PANEL_W, '设置', 30);
		title.setFormat(Paths.font('future.ttf'), 30, 0xFFFFFFFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.scrollFactor.set();
		add(title);

		// ---- 选项行（静态行，选中高亮条移动） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = new FlxText(PANEL_X + 100, LIST_Y + (r * ROW_GAP), PANEL_W - 200, options[r], 32);
			row.setFormat(Paths.font('future.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.scrollFactor.set();
			add(row);
			rows.push(row);
		}

		selectorBar = makePanel(PANEL_X + 60, LIST_Y - 5, PANEL_W - 120, 48, 14, 0x3AFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(120, 672, 1040, '滚轮 / 方向键 选择 · Enter / 点击 打开 · 点击 < 返回', 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		changeSelection(0, false);
		ClientPrefs.saveSettings();
		FlxG.mouse.visible = true;
		super.create();

		loadUIscripts('options');
	}

	override function closeSubState() {
		super.closeSubState();
		FlxG.mouse.visible = true;
		ClientPrefs.saveSettings();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		// 鼠标在本界面始终可见
		FlxG.mouse.visible = true;

		if (!quitting)
		{
			if (controls.UI_UP_P) {
				takeKeyboardControl();
				changeSelection(-1);
				holdTime = 0;
			}
			if (controls.UI_DOWN_P) {
				takeKeyboardControl();
				changeSelection(1);
				holdTime = 0;
			}

			if (controls.UI_DOWN || controls.UI_UP) {
				takeKeyboardControl();
				var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
				holdTime += elapsed;
				var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);
				if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
					changeSelection(Std.int(Math.min(checkNewHold - checkLastHold, 1)) * (controls.UI_UP ? -1 : 1)); // 单帧最多移动 1 行，防止卡顿帧跳变
			}

			// 鼠标
			if (!mouseActive)
			{
				var dx:Float = FlxG.mouse.screenX - mouseLockX;
				var dy:Float = FlxG.mouse.screenY - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			if (FlxG.mouse.wheel != 0)
			{
				mouseActive = true;
				changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
			}

			backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (FlxG.mouse.justPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
			{
				mouseActive = true;
				goBack();
				return;
			}

			if (FlxG.mouse.justPressed)
			{
				var clickID:Int = getHoveredOptionID();
				if (clickID >= 0)
				{
					mouseActive = true;
					if (clickID != curSelected)
					{
						changeSelection(clickID - curSelected);
						holdTime = 0;
					}
				}
			}

			if (controls.ACCEPT) openSelectedSubstate(options[curSelected]);
			else if (controls.BACK) goBack();
		}
	}

	function takeKeyboardControl()
	{
		mouseActive = false;
		mouseLockX = FlxG.mouse.screenX;
		mouseLockY = FlxG.mouse.screenY;
	}

	function goBack()
	{
		if (quitting) return;
		quitting = true;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		if (onPlayState)
		{
			StageData.loadDirectory(PlayState.SONG);
			LoadingState.loadAndSwitchState(new PlayState());
			FlxG.sound.music.volume = 0;
		}
		else MusicBeatState.switchState(new MainMenuState());
	}

	function getHoveredOptionID():Int
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...rows.length)
		{
			var row:FlxText = rows[r];
			if (mx >= PANEL_X + 60 && mx <= PANEL_X + PANEL_W - 60 && my >= row.y - 10 && my <= row.y + 48)
				return r;
		}
		return -1;
	}

	function changeSelection(change:Int = 0, playSound:Bool = true) {
		curSelected += change;
		if (curSelected < 0)
			curSelected = options.length - 1;
		if (curSelected >= options.length)
			curSelected = 0;

		if (playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		for (r in 0...rows.length)
		{
			var row:FlxText = rows[r];
			var isSel:Bool = (r == curSelected);
			row.alpha = isSel ? 1 : 0.72;
			row.color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
		}

		var barY:Float = LIST_Y - 5 + (curSelected * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

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
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}
