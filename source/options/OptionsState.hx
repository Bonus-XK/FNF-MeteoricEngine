package options;
import backend.WheelScroll;

import objects.BackButton;
import states.MainMenuState;
import backend.StageData;
import flixel.addons.transition.FlxTransitionableState; // 容器界面入口要用它跳过入场转场
import openfl.Lib;

/**
 * 【单界面设置】引擎设置界面（多界面融合 + 侧边栏切分区）。
 *
 * 改造前后（本文件是改造的唯一入口）：
 *   旧：一级分类列表（OptionsState，11–13 行）→ 按确认**打开二级整屏子页**（7 个 BaseOptionsMenu 派生页
 *       + 箭头配色 + 按键设置 + 4 个独立整屏页），每次都要"进/出"两层界面。
 *   新：**一个界面**。左侧 `SettingsRail` 分区栏（230 宽）切分区，右侧 `OptionsPane` 内容区就地渲染该分区
 *       的选项行 —— 不跳转、不叠子状态、不重建精灵。分区栏选中即切换（等同 MD3 navigation rail 的预览手感）。
 *
 * 分区来源（**选项定义只有一份**，不存在两套表漂移）：
 *   7 个选项分区由 headless 的 `BaseOptionsMenu` 子类实例提供（`BaseOptionsMenu.headless = true`）：
 *   子类照旧在构造里 `addOption(...)` 并挂 `onChange`，只是不建任何 UI；渲染交给 `OptionsPane`。
 *   暂停内嵌路径（`PauseSettingsSubstate`）仍开这些子类的**正常**实例，行为与改造前完全一致。
 *
 * 本轮边界（明确声明，避免误读）：
 *   - 「箭头配色」（NotesSubState）与「按键设置」（ControlsSubState）是自带绝对布局的整屏画布，
 *     重排进 956×570 内容区属下一增量；本轮它们在侧栏列出并作为**独立页出口**打开。
 *   - 「调整延迟与Combo」「自定义界面」「容器」「移动触控」同理为独立整屏页出口（用户已确认此边界）。
 *   - 音符皮肤预览 / 抗锯齿 BF 预览：headless 分区不创建预览精灵（内容区本轮没有预览承载位），
 *     选项与 onChange 行为不受影响；预览迁移同样属下一增量。
 *
 * 兼容契约（改动时勿破）：
 *   - `OptionsState.onPlayState`：暂停内进入设置后返回曲目要重载曲目（见 goBack）；
 *   - `OptionsState.pendingSelectLabel`：从容器界面返回时按标签恢复选中分区；
 *   - `enterContainersMenu()`：容器入口"不挂转场"的既有修复（黑屏回归风险点）。
 *
 * 绘制/交互契约（meteoric-system）：层级= 面板 → 高亮条 → 行文字；颜色走 DesignTokens；
 * 面板一次绘制、update() 零绘制；三套输入（键盘/鼠标/触控）与防误触（nextAccept / timeForMoving）保留。
 */
class OptionsState extends MusicBeatState
{
	// ===== 焦点 =====
	static final FOCUS_RAIL:Int = 0;
	static final FOCUS_CONTENT:Int = 1;

	static final TIME_FOR_MOVING:Float = 0.1; // 进入界面先忽略输入（防控制器/触屏误触）
	static final RAIL_HOLD_DELAY:Float = 0.5; // 分区栏上下长按重复

	/** 待恢复的选中分区（按标签）：从容器界面返回时用，避免依赖索引在列表变动后错位 */
	public static var pendingSelectLabel:String = null;
	public static var onPlayState:Bool = false;

	var roster:Array<SectionEntry> = [];
	var rail:SettingsRail;
	var pane:OptionsPane;
	var bg:FlxSprite;
	var backBtn:BackButton;

	var focus:Int = FOCUS_CONTENT;
	var timeForMoving:Float = 0;
	var railHold:Float = 0;
	var quitting:Bool = false;
	var nextAccept:Int = 5; // 移动端：忽略进入界面时的确认帧

	#if mobile
	var menuPad:objects.MobileControls;
	var diffLeftBtn:FlxSprite;
	var diffRightBtn:FlxSprite;
	var lastPadBtnTap:Float = 0;
	#end

	public function new()
	{
		super();
	}

	// ===== 分区表 =====

	function buildRoster():Array<SectionEntry>
	{
		var list:Array<SectionEntry> = [];

		var e:SectionEntry = new SectionEntry('音符', '音符');
		e.make = function() return new NoteSettingsSubState();
		list.push(e);

		e = new SectionEntry('箭头配色', '箭头配色');
		e.canvas = true;
		e.makeCanvas = function() {
			// 画布按内容区矩形构造：左右面板重排 + 色轮/渐变条换位（逻辑与整屏路径同一份代码，见 NotesPane）
			var c:NotesPane = new NotesPane(new flixel.math.FlxRect(
				OptionsPane.PANEL_X, OptionsPane.PANEL_Y, OptionsPane.PANEL_W, OptionsPane.PANEL_H));
			c.onExit = function() setFocus(FOCUS_RAIL);
			return c;
		};
		list.push(e);

		e = new SectionEntry('界面', '界面');
		e.make = function() return new InterfaceSettingsSubState();
		list.push(e);

		e = new SectionEntry('画面', '图像设置');
		e.make = function() return new GraphicsSettingsSubState();
		list.push(e);

		e = new SectionEntry('效果', '效果');
		e.make = function() return new EffectsSubState();
		list.push(e);

		e = new SectionEntry('玩法', '玩法');
		e.make = function() return new GameplaySettingsSubState();
		list.push(e);

		e = new SectionEntry('判定', '判定');
		e.make = function() return new JudgmentSettingsSubState();
		list.push(e);

		e = new SectionEntry('性能', '性能');
		e.make = function() return new PerformanceSubState();
		list.push(e);

		e = new SectionEntry('编程', '编程');
		e.make = function() return new ProgrammingSettingsSubState();
		list.push(e);

		e = new SectionEntry('按键设置', '按键设置');
		e.canvas = true;
		e.makeCanvas = function() {
			// 画布按内容区矩形构造：列表左缩进、键位列右贴（逻辑与整屏路径同一份代码，见 ControlsPane）
			var c:ControlsPane = new ControlsPane(new flixel.math.FlxRect(
				OptionsPane.PANEL_X, OptionsPane.PANEL_Y, OptionsPane.PANEL_W, OptionsPane.PANEL_H));
			c.onExit = function() setFocus(FOCUS_RAIL); // 画布内按 BACK/返回 = 焦点回分区栏（不直接退出设置）
			return c;
		};
		list.push(e);

		e = new SectionEntry('调整延迟', '调整延迟与Combo');
		e.external = true;
		e.hint = '节拍校准以"节拍"为被测对象（需要整屏播放节拍动画与偏移反馈），因此保持独立整屏界面。\n'
			+ '点左侧分区栏即直接打开（键盘选中后按 Enter 同样直达）；退出后自动回到暂停菜单（曲目内进入时）。';
		e.open = function() MusicBeatState.switchState(new options.NoteOffsetState());
		list.push(e);

		e = new SectionEntry('自定义界面', '自定义界面');
		e.external = true;
		e.hint = 'HUD 自定义是整屏拖拽编辑器（拖动血条/分数/时间条并保存位置），保持独立整屏界面。\n'
			+ '点左侧分区栏即直接打开（键盘选中后按 Enter 同样直达）。';
		e.open = function() MusicBeatState.switchState(new options.HUDCustomizeState());
		list.push(e);

		#if desktop
		e = new SectionEntry('容器', '容器');
		e.external = true;
		e.hint = '容器管理是独立整屏界面（列表 + 详情 + 操作条）：容器自带引擎界面，直接跳转过去用。\n'
			+ '点左侧分区栏即直接打开（键盘选中后按 Enter 同样直达）。'
			+ '注意：启动容器会让 Meteoric 整机重启，所以它不适合嵌进设置界面里当子页。';
		e.open = enterContainersMenu;
		list.push(e);
		#end

		#if mobile
		e = new SectionEntry('移动触控', '移动触控');
		e.external = true;
		e.hint = '移动触控布局是独立整屏编辑器（拖动按键并保存布局）。\n'
			+ '点左侧分区栏即直接打开（选中后按 A 同样直达）。';
		e.open = function() openSubState(new objects.MobileControlsSubState());
		list.push(e);
		#end

		return list;
	}

	// ===== 生命周期 =====

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - 设置菜单";

		#if desktop
		DiscordClient.changePresence("设置菜单", null);
		#end

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = DesignTokens.menuTint;
		bg.screenCenter();
		add(bg);

		roster = buildRoster();

		rail = new SettingsRail();
		var labels:Array<String> = [];
		for (e in roster) labels.push(e.label);
		rail.setLabels(labels);
		rail.onMove = onRailMove;
		rail.onConfirm = function(_idx:Int) { switchSection(rail.curSelected, true); };
		add(rail);

		pane = new OptionsPane();
		pane.onValueChanged = onPaneValueChanged;
		pane.onOpenExternal = function() openCurrentExternal();
		pane.onContentClicked = function() setFocus(FOCUS_CONTENT);
		add(pane);


		// ---- 返回按钮（右上角，三套输入一致）----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 底部提示条 ----
		add(OptionsUi.makePanel(40, 662, 1200, 48, 14));
		var hintText:String = 'Tab 切换分区/选项 · ↑↓ 选择 · ←→ 调整 · Enter 切换 · R 重置 · 点击左侧分区切换 · Esc 返回';
		#if mobile
		hintText = '点左侧分区切换 · 拖动选择 · ◀▶ 调整 · A 切换 · 点 < 返回';
		#end
		var hint:FlxText = new FlxText(64, 674, 1152, hintText, 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		#if mobile
		// 左下 ◀ ▶：调节当前选项（长按连续，参数与 BaseOptionsMenu 一致）
		diffLeftBtn = objects.MobileControls.makePadSprite('left', 0xFFFFFFFF);
		diffLeftBtn.setGraphicSize(110, 106);
		diffLeftBtn.updateHitbox();
		diffLeftBtn.x = 20;
		diffLeftBtn.y = FlxG.height - diffLeftBtn.height - 12;
		add(diffLeftBtn);

		diffRightBtn = objects.MobileControls.makePadSprite('right', 0xFFFFFFFF);
		diffRightBtn.setGraphicSize(110, 106);
		diffRightBtn.updateHitbox();
		diffRightBtn.x = 20 + diffLeftBtn.width + 8;
		diffRightBtn.y = FlxG.height - diffRightBtn.height - 12;
		add(diffRightBtn);

		// 右下 A 确认键（menuMode pad，不注册全局 instance）
		menuPad = new objects.MobileControls(false, FlxG.camera, -1, true);
		add(menuPad);
		#end

		// 初始分区：容器界面返回 → 按标签恢复；否则第一个分区
		var startIndex:Int = 0;
		if (pendingSelectLabel != null)
		{
			for (i in 0...roster.length)
				if (roster[i].label == pendingSelectLabel) startIndex = i;
			pendingSelectLabel = null;
		}
		rail.setSelected(startIndex);
		rail.snapScroll(); // 初始定位不滑动（进入界面时不该看到列表在滑）
		switchSection(startIndex, false);
		setFocus(FOCUS_CONTENT);

		timeForMoving = TIME_FOR_MOVING;
		ClientPrefs.saveSettings();
		FlxG.mouse.visible = true;

		// headless 分区的弹窗（如 Score 栏格式输入框）路由到本状态
		BaseOptionsMenu.promptHost = this;

		super.create();

		loadUIscripts('options');
	}

	override function closeSubState()
	{
		super.closeSubState();
		persistentDraw = true; // 恢复父级绘制（见 openSubState 性能约定）
		FlxG.mouse.visible = true;
		#if mobile
		if (menuPad != null) menuPad.visible = true;
		#end
		// 子页可能改了存档值（如 Score 栏格式输入框）→ 内容区重绘
		if (pane != null) pane.refresh();
		ClientPrefs.saveSettings();
	}

	// ===== 分区切换 =====

	/** 分区栏选中变化（键盘/滚轮）：立即切换内容区（等同 navigation rail 预览手感） */
	function onRailMove():Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		switchSection(rail.curSelected, false);
	}

	function switchSection(index:Int, moveFocusToContent:Bool):Void
	{
		if (index < 0 || index >= roster.length) return;
		rail.setSelected(index);
		rail.refresh();

		var e:SectionEntry = roster[index];
		if (e.canvas)
		{
			pane.setCanvas(canvasInstance(e), e.title);
		}
		else if (e.external)
		{
			pane.setExternal(e.title, e.hint);
		}
		else
		{
			var sec:BaseOptionsMenu = sectionInstance(e);
			if (sec == null) pane.setExternal(e.title, '（该分区不可用）');
			else if (sec.previewRows > 0) pane.setSection(sec, e.title, e.previewHost, sec.previewRows);
			else pane.setSection(sec, e.title);
		}

		if (moveFocusToContent) setFocus(FOCUS_CONTENT);
		else syncCanvasInput(); // 新建画布默认吃输入：切分区后必须按当前焦点同步
	}

	/** 懒加载 + headless 构造：选项定义来自子类自身（唯一来源），UI 由 OptionsPane 渲染 */
	function sectionInstance(e:SectionEntry):BaseOptionsMenu
	{
		if (e.instance == null && e.make != null)
		{
			// 分区自带的预览元素容器：子类在**构造期**就调 addVisual()，那时实例还没回到宿主手里，
			// 所以容器必须经静态口（headlessVisualHost）交进去，构造完再取回挂到条目上。
			var host:flixel.group.FlxGroup = new flixel.group.FlxGroup();
			var prev:Bool = BaseOptionsMenu.headless;
			var prevHost:flixel.group.FlxGroup = BaseOptionsMenu.headlessVisualHost;
			BaseOptionsMenu.headless = true;
			BaseOptionsMenu.headlessVisualHost = host;
			e.instance = e.make();
			BaseOptionsMenu.headless = prev;
			BaseOptionsMenu.headlessVisualHost = prevHost;
			if (e.instance != null) e.instance.visualHost = host;
			e.previewHost = host;
		}
		return e.instance;
	}

	/** 懒加载画布分区（按键设置 / 箭头配色…）：构造一次，之后只切显隐 */
	function canvasInstance(e:SectionEntry):SettingsCanvas
	{
		if (e.canvasRef == null && e.makeCanvas != null) e.canvasRef = e.makeCanvas();
		return e.canvasRef;
	}

	function openCurrentExternal():Void
	{
		var e:SectionEntry = roster[rail.curSelected];
		if (e == null || e.open == null) return;
		// 返回时按标签恢复选中分区：改造前靠 `private static var curSelected` 记住选中项，
		// 融合后选中项是实例字段（每次 switchState 都会新建本状态）——不记标签就会掉回第一个分区。
		// 复用 pendingSelectLabel（容器返回本来就走这条路），四个整屏页出口共用同一机制。
		pendingSelectLabel = e.label;
		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		e.open();
	}

	/** 当前选中的分区是否是「独立整屏页出口」（调整延迟 / 自定义界面 / 容器 / 移动触控） */
	function currentIsExternal():Bool
	{
		if (roster == null || rail == null) return false;
		var idx:Int = rail.curSelected;
		if (idx < 0 || idx >= roster.length) return false;
		var e:SectionEntry = roster[idx];
		return e != null && e.external;
	}

	function setFocus(v:Int):Void
	{
		focus = v;
		if (rail != null) rail.focused = (v == FOCUS_RAIL);
		if (pane != null) pane.focused = (v == FOCUS_CONTENT);
		syncCanvasInput();
	}

	/**
	 * 画布分区的输入权：只有焦点在内容区时画布才吃输入。
	 * 否则 ↑↓/Esc 会被"画布内部列表"与"分区栏"同时消费（两处一起动）。
	 * 注意：切分区时新建的画布默认 inputEnabled=true，因此切分区后也必须同步一次。
	 */
	function syncCanvasInput():Void
	{
		if (roster == null || rail == null) return;
		var idx:Int = rail.curSelected;
		if (idx < 0 || idx >= roster.length) return;
		var e:SectionEntry = roster[idx];
		if (e != null && e.canvasRef != null) e.canvasRef.inputEnabled = (focus == FOCUS_CONTENT);
	}

	/** 内容区值变化后的即时刷新：只刷主题色视觉与行文本，不重绘面板、不 tween（meteoric-system 契约） */
	function onPaneValueChanged():Void
	{
		if (bg != null) bg.color = DesignTokens.menuTint;
		if (pane != null) pane.refresh();
	}

	// ===== 输入 =====

	override function update(elapsed:Float)
	{
		#if METEORIC_PROFILE
		backend.MeteoricProfile.begin();
		#end
		super.update(elapsed);

		FlxG.mouse.visible = true;

		// 子界面（箭头配色/按键设置/移动触控/输入框）打开期间：本层冻结输入并隐藏移动端 A 键
		if (subState != null)
		{
			#if mobile
			if (menuPad != null) menuPad.visible = false;
			#end
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('OptionsState.update');
			#end
			return;
		}

		if (timeForMoving > 0)
		{
			timeForMoving = Math.max(0, timeForMoving - elapsed);
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('OptionsState.update');
			#end
			return;
		}

		if (quitting) return;

		// ---- 焦点切换（Tab）：键盘唯一的焦点迁移手势 ----
		if (FlxG.keys.justPressed.TAB)
			setFocus((focus == FOCUS_RAIL) ? FOCUS_CONTENT : FOCUS_RAIL);

		// ---- 分区栏输入 ----
		if (focus == FOCUS_RAIL)
		{
			if (controls.UI_UP_P) { railHold = 0; rail.changeSelection(-1); }
			if (controls.UI_DOWN_P) { railHold = 0; rail.changeSelection(1); }
			if (controls.UI_UP || controls.UI_DOWN)
			{
				var before:Int = Math.floor((railHold - RAIL_HOLD_DELAY) * 10);
				railHold += elapsed;
				var after:Int = Math.floor((railHold - RAIL_HOLD_DELAY) * 10);
				if (railHold > RAIL_HOLD_DELAY && after - before > 0)
					rail.changeSelection(Std.int(Math.min(after - before, 1)) * (controls.UI_UP ? -1 : 1));
			}
			if (controls.UI_UP_R || controls.UI_DOWN_R) railHold = 0;

			// 滚轮 = 页面滚动：一格 = 翻一整页（桌面 9 项；移动端一行，见 SettingsRail.addWheel）。
			// 旧实现走 WheelScroll（一格一项）—— 那是"逐项"，用户要的是"整栏翻页"，故改由分区栏自己处理。
			rail.addWheel(FlxG.mouse.wheel);

			// 独立整屏页出口（调整延迟 / 自定义界面 / 容器 / 移动触控）：**一步直达** ——
			// 分区栏上确认即打开整屏页，不再要求"先切分区、再在内容区确认"的第二下
			if (controls.ACCEPT || controls.UI_RIGHT_P)
			{
				if (currentIsExternal()) openCurrentExternal();
				else setFocus(FOCUS_CONTENT);
			}
		}

		// ---- 内容区输入（键盘仅在内容区有焦点时启用；鼠标/触控点击在任何焦点下都生效）----
		pane.updatePaneInput(elapsed, focus == FOCUS_CONTENT, focus == FOCUS_CONTENT);

		// 画布分区（按键设置/箭头配色）：内容区输入归画布自己（它有绑定流程与自己的退出语义），
		// 因此确认/重置/返回都不在这里重复处理，只保留"焦点在分区栏时的 Esc 退出设置"
		var canvasHasFocus:Bool = pane.isCanvasActive() && focus == FOCUS_CONTENT;

		if (focus == FOCUS_CONTENT && !canvasHasFocus)
		{
			var acceptPressed:Bool = controls.ACCEPT;
			#if mobile
			if (menuPad != null && menuPad.justPressed('accept')) acceptPressed = true;
			if (nextAccept > 0) { nextAccept--; acceptPressed = false; }
			#end
			if (acceptPressed) pane.confirm();
			if (controls.RESET) pane.resetSelected();
		}

		// ---- 移动端 ◀▶ 调节（点按立即生效 + 0.5s 后连续）----
		#if mobile
		updatePadAdjust(elapsed);
		#end

		// ---- 鼠标：点击分区栏 = 切分区并进入内容区 ----
		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			goBack();
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('OptionsState.update');
			#end
			return;
		}

		if (clickPressed)
		{
			var railHit:Int = rail.hitIndex(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (railHit >= 0)
			{
				if (railHit != rail.curSelected)
				{
					rail.setSelected(railHit);
					rail.refresh();
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					switchSection(railHit, true);
				}
				// **点分区栏 = 直达**：整屏页出口单击即打开（容器/调整延迟/自定义界面/移动触控）；
				// 就地分区只是把键盘焦点交给内容区（不跳转）
				if (currentIsExternal()) openCurrentExternal();
				else setFocus(FOCUS_CONTENT);
			}
		}

		if (controls.BACK && !canvasHasFocus) goBack();

		#if METEORIC_PROFILE
		backend.MeteoricProfile.end('OptionsState.update');
		#end
	}

	#if mobile
	function updatePadAdjust(elapsed:Float):Void
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		var leftHit:Bool = padBtnHit(diffLeftBtn, mx, my);
		var rightHit:Bool = padBtnHit(diffRightBtn, mx, my);
		var dir:Int = leftHit ? -1 : (rightHit ? 1 : 0);
		var pressed:Bool = FlxG.mouse.justPressed && dir != 0 && Lib.getTimer() - lastPadBtnTap > 300;
		if (pressed) lastPadBtnTap = Lib.getTimer();
		pane.updatePadAdjust(dir, pressed, FlxG.mouse.pressed && dir != 0, elapsed);

		// 按下态视觉反馈（贴图第 3 帧；无多帧贴图则降亮度）
		updatePadVisual(diffLeftBtn, leftHit && FlxG.mouse.pressed);
		updatePadVisual(diffRightBtn, rightHit && FlxG.mouse.pressed);
		if (menuPad != null && menuPad.padButtons.exists('accept') && menuPad.padButtons.get('accept').length > 0)
		{
			var aZone:FlxSprite = menuPad.padButtons.get('accept')[0];
			updatePadVisual(aZone, aZone != null && mx >= aZone.x && mx <= aZone.x + aZone.width
				&& my >= aZone.y && my <= aZone.y + aZone.height && FlxG.mouse.pressed);
		}
	}

	function updatePadVisual(btn:FlxSprite, held:Bool):Void
	{
		if (btn == null) return;
		if (btn.frames != null && btn.frames.frames.length >= 3)
			btn.animation.frameIndex = held ? 2 : 0;
		else btn.alpha = held ? 1 : 0.75;
	}

	function padBtnHit(btn:FlxSprite, mx:Float, my:Float):Bool
	{
		if (btn == null) return false;
		return mx >= btn.x && mx <= btn.x + btn.width && my >= btn.y && my <= btn.y + btn.height;
	}

	/** 移动端系统返回键：返回上一级（曲目内 → 曲目；主菜单 → 主菜单），禁止直接退出游戏 */
	override public function onAndroidBack():Bool
	{
		goBack();
		return true;
	}
	#end

	// ===== 退出 =====

	function goBack()
	{
		if (quitting) return;
		quitting = true;
		// 单界面没有"关子页"这一步（旧路径靠 OptionsState.closeSubState 落盘），
		// 因此离开界面必须显式落盘，否则 destroy() 里的 loadPrefs() 会把本次改动读没（本类 destroy 有注释）
		ClientPrefs.saveSettings();
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

	// ===== 容器入口（唯一入口，勿改转场语义：见下方注释）=====

	#if desktop
	/**
	 * 【容器界面入口 · 唯一入口】从设置进入「容器」管理页。
	 *
	 * 为什么单独抽成入口函数、而不是就地 `MusicBeatState.switchState(...)`：
	 *   `MusicBeatState.switchState()` 会先挂 `CustomFadeTransition(0.6,false)` 出场转场，
	 *   而转场层在**新状态 create() 完成之前**屏上是空的（`FlxGame.switchState()`：
	 *   cameras.reset() → bitmap.clearCache() → 旧状态 destroy() → 新状态 create()），
	 *   玩家看到的就是「先黑一下，容器界面再跳出来」。容器页自带整屏不透明背景（menuDesat），
	 *   并不需要出场转场遮丑；进曲那条路（`LoadingState.loadAndSwitchState`）同理。
	 *
	 * 做法：用 `FlxG.switchState()` 直接换状态，**不再挂出场转场** ⇒ 不存在"转场层空窗"。
	 * ⚠ 若以后要恢复转场：不要只把这一行换回 `MusicBeatState.switchState`，那正是本次要修的症状。
	 */
	function enterContainersMenu():Void
	{
		// 返回时按标签恢复选中（列表顺序若变动，光靠索引会错位）
		pendingSelectLabel = '容器';
		// ① 明确要求"这次不要入场转场"：`MusicBeatState.create()` 里是
		//    `if(!skip) openSubState(new CustomFadeTransition(0.7, true))`，
		//    而 `skip` 取自 `FlxTransitionableState.skipNextTransOut`（引擎自带开关）。
		FlxTransitionableState.skipNextTransOut = true;
		// ② 直接换状态：不进 `MusicBeatState.startTransition`（那会挂出场转场 → 空窗黑屏）
		FlxG.switchState(new states.ContainersMenuState());
	}
	#end

	// ===== 释放 =====

	override function destroy()
	{
		FlxG.mouse.visible = false;
		// 落盘 → 再 loadPrefs：本类旧实现的 destroy 只有 loadPrefs（"应用存档值"），
		// 分页时代靠各子页关闭时的 saveSettings 落盘；单界面没有那一步，必须在这里补（否则最后一次改动丢失）
		ClientPrefs.saveSettings();
		// headless 分区实例的"离开界面"业务收尾（如效果页恢复主菜单音乐）；
		// 这些实例不在状态树里，禁止调它们的 destroy()
		if (roster != null)
		{
			for (e in roster)
			{
				if (e.instance != null)
				{
					e.instance.onHostDisposed();
					e.instance = null;
				}
			}
		}
		BaseOptionsMenu.promptHost = null;
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}

/**
 * 侧栏分区条目。
 * - 选项分区：`make` 提供 headless 的 BaseOptionsMenu 子类实例（选项定义唯一来源），内容区就地渲染；
 * - 独立页出口：`external = true`，内容区显示一张可点卡片（`hint` 说明为什么它仍是独立页），
 *   确认/点击即 `open()`。
 */
class SectionEntry
{
	public var label:String;   // 侧栏显示名（短名，≤166px）
	public var title:String;   // 内容区标题（全名）
	public var external:Bool = false;
	public var hint:String = '';
	public var make:Void->BaseOptionsMenu = null;
	public var open:Void->Void = null;
	public var instance:BaseOptionsMenu = null;
	/** 画布分区：内容区让位给自带绝对布局的编辑器（按键设置 / 箭头配色…） */
	public var canvas:Bool = false;
	public var makeCanvas:Void->SettingsCanvas = null;
	public var canvasRef:SettingsCanvas = null;
	/** 本分区自带预览元素的容器（如音符皮肤预览）；无预览的分区为 null */
	public var previewHost:flixel.group.FlxGroup = null;

	public function new(label:String, title:String)
	{
		this.label = label;
		this.title = title;
	}
}
