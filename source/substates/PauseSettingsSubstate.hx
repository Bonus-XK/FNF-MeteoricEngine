package substates;

import backend.WheelScroll;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import objects.BackButton;
import backend.ClientPrefs;
import backend.MusicBeatState;
import backend.MusicBeatSubstate;
import backend.Paths;
import states.PlayState;

/**
 * 暂停菜单内的设置分类列表（嵌入式，不再跳转全屏 OptionsState）。
 * - 全部二级菜单入口：9 个分类子页（暗化覆盖式叠加，视觉为暂停界面内的一页）；
 *   自定义界面/调整延迟与Combo 走全屏（退出自动回到暂停菜单）
 * - 与外层暂停菜单同款：56px 行距 + 8 行窗口滚动 + 滚轮 + 选中条滑动（主菜单设置同款手感）
 * - 关闭本列表回到暂停菜单（保持暂停，不重载曲目）
 * - 设置即时生效；需重载才生效的项在下一次重开曲目时生效
 */
class PauseSettingsSubstate extends MusicBeatSubstate
{
	static final PANEL_X:Float = 220;
	static final PANEL_Y:Float = 120;
	static final PANEL_W:Float = 840;
	static final PANEL_H:Float = 570;
	static final LIST_X:Float = 262;
	static final LIST_Y:Float = 190;
	static final ROW_GAP:Float = 56;      // 与主菜单设置一致
	static final ROWS_VISIBLE:Int = 8;    // 可见行窗口

	var rowsDef:Array<String> = [
		'音符', '箭头配色', '界面', '画面', '效果', '玩法', '判定', '性能', '编程', '按键设置', '自定义界面', '调整延迟与Combo'
		#if mobile
		, '移动触控'
		#end
	];

	var rows:Array<FlxText> = [];
	var rowStartY:Float = LIST_Y - 2;
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var backBtn:BackButton;
	var curSelected:Int = 0;
	var scrollOffset:Int = 0;   // 可见行窗口顶部的分类索引
	var wheelScroll:WheelScroll = new WheelScroll();
	// 初始为 false：鼠标需真实移动超过死区、或发生点击，才被允许接管。
	// 本页不做"悬停即选中"——悬停只用于判定点击落在哪一行，选中项只能由点击/键盘/滚轮改变。
	var mouseActive:Bool = false;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	// 上一次点击落在的行（scrollOffset 空间的绝对行号）。用于"点一次选中、再点一次打开"，
	// 与鼠标是否悬停、选中项来自键盘还是鼠标都无关：-1 = 本次会话还没有过点击。
	var lastClickedRow:Int = -1;
	// 子页打开时隐藏本列表 UI（避免与子页双重显示）
	var listUI:Array<FlxBasic> = [];
	var listUIHidden:Bool = false;
	#if mobile
	var menuPad:objects.MobileControls; // 右下角虚拟 A 确认键（拖动选中后按 A 打开子页）
	#end
	var nextAccept:Int = 5;              // 进入界面先忽略确认键，防开界面时按住的 A 误触发

	public function new()
	{
		super();
		// 与暂停菜单共用顶层相机（camOther）：保证本列表及其下级子页绘制在暂停菜单之上
		// （相机渲染顺序优先于状态嵌套，默认相机在底层会被 camOther 盖住）
		var pauseCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [pauseCam];
	}

	function getRowAt(r:Int):String
	{
		var idx:Int = scrollOffset + r;
		if (idx < 0 || idx >= rowsDef.length) return '';
		return rowsDef[idx];
	}

	/** 点击落在列表某行：第一次点击只选中（**不打开**），第二次点击同一行才打开对应子页。
	 *  判定依据是"上一次点击的行"，不是"当前悬停"也不是"选中项"：
	 *  光标扫过列表、键盘刚移过选中项，都不会导致误开子页。 */
	function handleRowClick():Void
	{
		var hoveredRow:Int = getHoveredRow();
		if (hoveredRow < 0) return; // 点在列表外（面板空白处）：不改变选中项
		var idx:Int = scrollOffset + hoveredRow;
		if (idx != curSelected)
			changeSelection(idx - curSelected, true);
		if (idx != lastClickedRow)
		{
			lastClickedRow = idx;
			return; // 第一次点击：仅选中
		}
		lastClickedRow = -1; // 子页打开前复位，返回后需要重新"点两次"
		openSelectedSubstate();
	}

	function openSelectedSubstate()
	{
		switch(rowsDef[curSelected])
		{
			case '音符':
				openCamSubState(new options.NoteSettingsSubState());
			case '箭头配色':
				openCamSubState(new options.NotesSubState());
			case '界面':
				openCamSubState(new options.InterfaceSettingsSubState());
			case '画面':
				openCamSubState(new options.GraphicsSettingsSubState());
			case '效果':
				openCamSubState(new options.EffectsSubState());
			case '玩法':
				openCamSubState(new options.GameplaySettingsSubState());
			case '判定':
				openCamSubState(new options.JudgmentSettingsSubState());
			case '性能':
				openCamSubState(new options.PerformanceSubState());
			case '编程':
				openCamSubState(new options.ProgrammingSettingsSubState());
			case '按键设置':
				openCamSubState(new options.ControlsSubState());
			case '自定义界面':
				// 全屏页：退出后经 OptionsState → goBack 重载曲目并自动回到暂停菜单（PlayState.autoOpenPause）
				options.OptionsState.onPlayState = true;
				PlayState.autoOpenPause = true;
				MusicBeatState.switchState(new options.HUDCustomizeState());
			case '调整延迟与Combo':
				options.OptionsState.onPlayState = true;
				PlayState.autoOpenPause = true;
				MusicBeatState.switchState(new options.NoteOffsetState());
			#if mobile
			case '移动触控':
				openCamSubState(new objects.MobileControlsSubState());
			#end
		}
	}

	// 打开分类子页：仅传递给子页相机（与暂停菜单同层）；内嵌样式判定由子页自身按相机判定，
	// 不再使用标志位（标志写入曾晚于 create，属时序竞态源——相机继承在 create 时可稳定命中）
	function openCamSubState(sub:FlxSubState):Void
	{
		if (cameras != null && cameras.length > 0)
			sub.cameras = [cameras[0]];
		openSubState(sub);
	}

	// 与暂停菜单同款圆角磨砂面板（makePanel 同实现）
	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是**编译期常量**，不能写 DesignTokens.panelFill（运行时求值会被 Haxe 拒绝），
		// 故默认传 null、在此解析 —— 同时保证取到的是「当前主题」的值，而不是类加载时的快照。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if(border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override function create()
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.55;
		bg.scrollFactor.set();
		add(bg);

		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 20);
		panel.alpha = 0;
		panel.scrollFactor.set();
		add(panel);
		FlxTween.tween(panel, {alpha: 0.96}, 0.25, {ease: FlxEase.quartInOut});

		var title:FlxText = new FlxText(PANEL_X, PANEL_Y - 46, PANEL_W, '设置', 30);
		title.scrollFactor.set();
		title.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		add(title);

		// 静态 8 行窗口（滚动时只改文本，避免重建对象）
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = new FlxText(LIST_X, rowStartY + (r * ROW_GAP), 0, '', 26);
			row.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.scrollFactor.set();
			add(row);
			rows.push(row);
		}

		selectorBar = makePanel(PANEL_X + 18, LIST_Y - 9, PANEL_W - 36, 42, 12, DesignTokens.rowHighlight, null);
		add(selectorBar);

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		#if mobile
		// 右下角虚拟 A 确认键（menuMode pad，不注册全局 instance）：
		// 拖动选中后按 A 打开当前分类子页
		menuPad = new objects.MobileControls(false, cameras[0], -1, true);
		add(menuPad);
		#end

		listUI = [panel, title, selectorBar, backBtn.glow, backBtn.spr, backBtn.label];
		#if mobile
		listUI.push(menuPad);
		#end
		for (row in rows) listUI.push(row);

		changeSelection(0, false);
		FlxG.mouse.visible = true;
	}

	function changeSelection(change:Int = 0, playSound:Bool = true):Void
	{
		curSelected += change;
		if (curSelected < 0) curSelected = rowsDef.length - 1;
		if (curSelected >= rowsDef.length) curSelected = 0;

		if (playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		// 滚动窗口跟随选中项（与主菜单设置一致）
		var newOffset:Int = scrollOffset;
		if (curSelected < newOffset) newOffset = curSelected;
		if (curSelected >= newOffset + ROWS_VISIBLE) newOffset = curSelected - ROWS_VISIBLE + 1;
		if (newOffset != scrollOffset)
			scrollOffset = newOffset;
		// 行文本无条件刷新（初始调用时 scrollOffset 未变，若只在窗口变化时赋值会全空白）
		for (r in 0...rows.length)
			rows[r].text = getRowAt(r);

		for (r in 0...rows.length)
		{
			var isSel:Bool = (scrollOffset + r == curSelected);
			rows[r].alpha = isSel ? 1 : 0.72;
			rows[r].color = isSel ? FlxColor.WHITE : 0xFFCFCFDC;
		}

		var barY:Float = rowStartY - 7 + ((curSelected - scrollOffset) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null) { selectorTween.cancel(); selectorTween = null; }
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

	function takeBack():Void
	{
		FlxG.sound.play(Paths.sound('cancelMenu'));
		close();
	}

	#if mobile
	/** 移动端系统返回键：关闭本列表并回到暂停菜单（不退出游戏） */
	override public function onAndroidBack():Bool
	{
		close();
		return true;
	}
	#end

	/** 悬停/手指所在的行索引：用本页相机（camOther）换算鼠标坐标判定行矩形。
	 *  FlxG.mouse.overlaps 默认走 FlxG.camera（游戏相机），暂停时与 camOther 视图不一致会错位 */
	function getHoveredRow():Int
	{
		var mp:FlxPoint = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());
		var hovered:Int = -1;
		for (r in 0...rows.length)
		{
			var row:FlxText = rows[r];
			if (row == null) continue;
			if (mp.x >= LIST_X - 24 && mp.x <= LIST_X + 580
				&& mp.y >= row.y - 6 && mp.y <= row.y + ROW_GAP - 10)
			{
				hovered = r;
				break;
			}
		}
		mp.put();
		return hovered;
	}

	function setListUI(visible:Bool):Void
	{
		for (obj in listUI)
			if (obj != null) obj.visible = visible;
	}

	override function update(elapsed:Float)
	{
		#if METEORIC_PROFILE
		backend.MeteoricProfile.begin();
		#end
		if (cameras != null && cameras[0] != null)
		{
			cameras[0].zoom = 1;
			cameras[0].scroll.set(0, 0);
		}
		FlxG.mouse.visible = true;
		// 分类子页打开期间：本列表冻结输入并隐藏，由子页独占
		if (subState != null)
		{
			if (!listUIHidden) { setListUI(false); listUIHidden = true; }
			super.update(elapsed);
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('PauseSettingsSubstate.update');
			#end
			return;
		}
		if (listUIHidden) { setListUI(true); listUIHidden = false; }
		super.update(elapsed);

		var upP:Bool = controls.UI_UP_P;
		var downP:Bool = controls.UI_DOWN_P;
		var accepted:Bool = controls.ACCEPT;

		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		// 触屏：手指抬起且未滑动才算点击（拖动滚动列表时不误触）
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		// 确认键：右下角虚拟 A（拖到目标行后按 A 打开子页）；与 BaseOptionsMenu 同款冷却防误触
		if (menuPad != null && menuPad.justPressed('accept'))
			accepted = true;
		#end

		// ---- 键盘上下：与 PauseSubState / BaseOptionsMenu 一致 —— 键盘接管选中后**冻结鼠标跟随**，
		//      并把锚点坐标更新到**当前**光标位置。
		//      旧实现只在悬停分支里把 mouseActive 置 false、却不更新锚点，导致：
		//      ① 下一帧悬停分支立刻把选中项抢回光标所在行（键盘/鼠标抢选中项）；
		//      ② 锚点常为陈旧坐标，恒判定"已移动"，选中项被反复改写（卡选中）。----
		if (upP)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			lastClickedRow = -1; // 键盘改过选中：下一次点击重新计为"第一次"（只选中，不打开）
			changeSelection(-1);
		}
		if (downP)
		{
			mouseActive = false;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			lastClickedRow = -1;
			changeSelection(1);
		}

		// ---- 鼠标（桌面/手机同一套语义：**只有点击才改变选中项，悬停不选中**）----
		//      点击落在某行：该行不是上一次点击的行 → 仅选中；就是上一次点击的行 → 打开对应子页。
		//      由于判定依据是"上一次点击的行"而不是"选中项"，光标扫过列表、键盘刚移过选中项等
		//      情况都不会误开任何子页。
		#if !mobile
		// 冻结期间不抢输入；需鼠标真实移动超过 10px 死区才重新接受点击/滚轮（与 PauseSubState 同参）
		if (!mouseActive)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
		}
		#end

		if (clickPressed)
		{
			mouseActive = true;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			handleRowClick();
		}

		// ---- 滚轮（全平台：桌面鼠标滚轮 / 手机触屏合成滚轮 45px/格，Freeplay 同款）----
		var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
		if (wheelStep != 0)
		{
			mouseActive = true;
			mouseLockX = FlxG.mouse.screenX;
			mouseLockY = FlxG.mouse.screenY;
			lastClickedRow = -1; // 滚轮改过选中：下一次点击重新计为"第一次"
			changeSelection(wheelStep);
		}

		// ---- 右上角返回键：点击关闭（桌面/手机通用）----
		backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
		if (clickPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
		{
			takeBack();
			#if METEORIC_PROFILE
			backend.MeteoricProfile.end('PauseSettingsSubstate.update');
			#end
			return;
		}

		#if mobile
		if (nextAccept > 0)
		{
			nextAccept--;
			accepted = false;
		}
		#end

		if (accepted)
			openSelectedSubstate();

		if (controls.BACK)
			takeBack();

		#if METEORIC_PROFILE
		backend.MeteoricProfile.end('PauseSettingsSubstate.update');
		#end
	}
}
