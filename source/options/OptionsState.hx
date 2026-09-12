package options;
import backend.WheelScroll;

import objects.BackButton;
import states.MainMenuState;
import backend.StageData;
import openfl.Lib;
import flixel.util.FlxSpriteUtil;

class OptionsState extends MusicBeatState
{
	var wheelScroll:WheelScroll = new WheelScroll(); // 滚轮限速（Freeplay 同款）
	// ===== 布局常量 =====
	static final PANEL_X:Float = 220;
	static final PANEL_Y:Float = 110;
	static final PANEL_W:Float = 840;
	static final PANEL_H:Float = 500;

	static final LIST_Y:Float = 200;
	static final ROW_GAP:Float = #if mobile 50 #else 56 #end;
	static final ROWS_VISIBLE:Int = #if mobile 8 #else 7 #end;

	var options:Array<String> = [
		'音符', '箭头配色', '界面', '画面', '效果', '玩法', '判定', '性能', '按键设置', '调整延迟与Combo', '自定义界面'
		#if desktop
		, '容器'
		#end
		#if mobile
		, '移动触控'
		#end
	];
	private static var curSelected:Int = 0;
	/** 待恢复的选中项（按标签）：从容器界面返回时用，避免依赖 static 索引在列表变动后错位。 */
	public static var pendingSelectLabel:String = null;
	private var scrollOffset:Int = 0; // 可见行窗口顶部的分类索引
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
	#if mobile
	var menuPad:objects.MobileControls; // 右下角虚拟 A 确认键（拖动选中后按 A 打开分类子页）
	#end
	var nextAccept:Int = 5;        // 进入界面先忽略确认键，防开界面时按住的 A 误触发

	function openSelectedSubstate(label:String) {
		// 【性能】二级页打开期间父级停止绘制：子页背景（menuDesat，不透明整屏）100% 盖住父级，
		// 父级继续画是纯白绘（实测二级页帧耗 ~1090us vs 一级 ~730us，多出的 ~360us 正是父级
		// 被遮死仍在下层持续渲染的 GPU 成本）。关闭时由 closeSubState() 恢复绘制。
		persistentDraw = false;
		switch(label) {
			case '音符':
				openSubState(new options.NoteSettingsSubState());
			case '箭头配色':
				openSubState(new options.NotesSubState());
			case '界面':
				openSubState(new options.InterfaceSettingsSubState());
			case '画面':
				openSubState(new options.GraphicsSettingsSubState());
			case '效果':
				openSubState(new options.EffectsSubState());
			case '玩法':
				openSubState(new options.GameplaySettingsSubState());
			case '判定':
				openSubState(new options.JudgmentSettingsSubState());
			case '性能':
				openSubState(new options.PerformanceSubState());
			case '按键设置':
				openSubState(new options.ControlsSubState());
			case '自定义界面':
				MusicBeatState.switchState(new options.HUDCustomizeState());
			case '调整延迟与Combo':
				MusicBeatState.switchState(new options.NoteOffsetState());
			#if desktop
			case '容器':
				// 容器管理是独立全屏界面（列表 + 详情 + 操作条），直接切状态而不是 openSubState：
				// 会话启动后 Meteoric 会整机重启，子状态挂在父状态上的层级关系会带来无意义的恢复成本
				pendingSelectLabel = '容器';
				MusicBeatState.switchState(new states.ContainersMenuState());
			#end
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
		bg.color = DesignTokens.menuTint; // 主题色（原硬编码品红 0xFFea71fd，会导致选了色一级页不跟随）
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
			var row:FlxText = new FlxText(PANEL_X + 100, LIST_Y + (r * ROW_GAP), PANEL_W - 200, getOptionAt(r), 32);
			row.setFormat(Paths.font('future.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.scrollFactor.set();
			add(row);
			rows.push(row);
		}

		selectorBar = makePanel(PANEL_X + 60, LIST_Y - 5, PANEL_W - 120, 48, 14, DesignTokens.rowHighlight, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		#if mobile
		// 右下角虚拟 A 确认键（menuMode pad，不注册全局 instance）：拖动选中后按 A 打开分类子页
		menuPad = new objects.MobileControls(false, FlxG.camera, -1, true);
		add(menuPad);
		#end

		// ---- 底部提示 ----
		var hintText:String = '滚轮 / 方向键 选择 · Enter / 点击 打开 · 点击 < 返回';
		#if mobile
		hintText = '滑动选择 · A 确认打开 · < 返回';
		#end
		var hint:FlxText = new FlxText(120, 672, 1040, hintText, 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		// 从容器界面返回时按标签恢复选中（列表顺序若变动，光靠 static 索引会错位）
		if (pendingSelectLabel != null)
		{
			var idx:Int = options.indexOf(pendingSelectLabel);
			pendingSelectLabel = null;
			if (idx >= 0) curSelected = idx;
		}

		changeSelection(0, false);
		ClientPrefs.saveSettings();
		FlxG.mouse.visible = true;
		super.create();

		loadUIscripts('options');
	}

	override function closeSubState() {
		super.closeSubState();
		persistentDraw = true; // 恢复父级绘制（见 openSelectedSubstate 性能注释）
		FlxG.mouse.visible = true;
		#if mobile
		if (menuPad != null) menuPad.visible = true;
		#end
		ClientPrefs.saveSettings();
	}

	override function update(elapsed:Float) {
		#if METEORIC_PROFILE
		backend.MeteoricProfile.begin();
		#end
		super.update(elapsed);

		// 鼠标在本界面始终可见
		FlxG.mouse.visible = true;

		// 子界面（按键设置等）打开期间，本层不再响应输入，
		// 防止进入瞬间的点击/按键被父层再次消费（如重复打开子界面、误触发绑定）
		if (subState != null)
		{
			#if mobile
			// 隐藏本页 A 键：子界面（尤其移动触控布局编辑）拖动按钮时，
			// 右下角多余的 A 键会与"保存并退出"等按钮重叠、极易误触
			if (menuPad != null) menuPad.visible = false;
			#end
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('OptionsState.update');
			#end
			return;
		}

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

			// ---- 滚轮（全平台：桌面鼠标滚轮 / 手机触屏合成滚轮 45px/格，Freeplay 同款）----
			var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);

			if (wheelStep != 0)
			{
				mouseActive = true;
				changeSelection(wheelStep);
			}

			// 点击判定：桌面沿用 justPressed；触屏抬起且未滑动才算点击（拖动滚动列表时不误触）
			var clickPressed:Bool = FlxG.mouse.justPressed;
			var acceptPressed:Bool = controls.ACCEPT;
			#if mobile
			clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
			// 确认键：右下角虚拟 A（拖到目标行后按 A 打开子页）；与 BaseOptionsMenu 同款冷却防误触
			if (menuPad != null && menuPad.justPressed('accept'))
				acceptPressed = true;
			#end

			backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
			{
				mouseActive = true;
				goBack();
				return;
			}

			#if !mobile
			// 桌面：点击行 = 选中；点击已选中行 = 打开（Psych 原版交互）。
			// 手机：点击行无反应（取消点选），打开只由 A 键触发。
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
					else if (clickID == curSelected)
					{
						// 点击已选中分类：直接进入
						openSelectedSubstate(options[curSelected]);
					}
				}
			}
			#end

			#if mobile
			if (nextAccept > 0)
			{
				nextAccept--;
				acceptPressed = false;
			}
			#end

			if (acceptPressed) openSelectedSubstate(options[curSelected]);
			else if (controls.BACK) goBack();
		}

		#if METEORIC_PROFILE
		backend.MeteoricProfile.end('OptionsState.update');
		#end
	}

	#if mobile
	/** 移动端系统返回键：返回主菜单（与右上角返回键一致） */
	override public function onAndroidBack():Bool
	{
		goBack();
		return true;
	}
	#end

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
			// 重进曲目必须携带谱面参数走 loadSongAndSwitchState：
			// loadAndSwitchState 不带 pendingChartJson，会沿用上一局运行时 SONG 静态对象，
			// 而其 sectionNotes 已被 buildChartNotes 释放置 null（大谱面内存大关）→ 重进生成空谱面（箭头全部消失）
			var songPath:String = backend.Paths.formatToSongPath(PlayState.SONG.song);
			if (!LoadingState.loadSongAndSwitchState(new PlayState(), songPath,
				backend.Highscore.formatSong(songPath, PlayState.storyDifficulty), songPath,
				true, PlayState.isStoryMode ? new states.StoryMenuState() : new states.FreeplayState()))
			{
				// 谱面文件异常缺失时的兜底：退回无参数路径（保持原行为，不阻断返回）
				LoadingState.loadAndSwitchState(new PlayState());
			}
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
				return scrollOffset + r;
		}
		return -1;
	}

	function getOptionAt(r:Int):String
	{
		var idx:Int = scrollOffset + r;
		if (idx < 0 || idx >= options.length) return '';
		return options[idx];
	}

	function changeSelection(change:Int = 0, playSound:Bool = true) {
		curSelected += change;
		if (curSelected < 0)
			curSelected = options.length - 1;
		if (curSelected >= options.length)
			curSelected = 0;

		if (playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		// 滚动窗口跟随选中项
		var newOffset:Int = scrollOffset;
		if (curSelected < newOffset) newOffset = curSelected;
		if (curSelected >= newOffset + ROWS_VISIBLE) newOffset = curSelected - ROWS_VISIBLE + 1;
		if (newOffset != scrollOffset)
		{
			scrollOffset = newOffset;
			for (r in 0...rows.length)
				rows[r].text = getOptionAt(r);
		}

		for (r in 0...rows.length)
		{
			var isSel:Bool = (scrollOffset + r == curSelected);
			rows[r].alpha = isSel ? 1 : 0.72;
			rows[r].color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
		}

		var barY:Float = LIST_Y - 5 + ((curSelected - scrollOffset) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是**编译期常量**，不能写 DesignTokens.panelFill（运行时求值会被 Haxe 拒绝），
		// 故默认传 null、在此解析 —— 同时保证取到的是「当前主题」的值，而不是类加载时的快照。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
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
