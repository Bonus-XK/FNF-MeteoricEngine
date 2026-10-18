package options;

import backend.ClientPrefs;
import backend.DesignTokens;
import backend.Lang;
import backend.MusicBeatState;
import backend.Paths;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

import openfl.display.FPS;

import objects.BackButton;
import objects.ToggleSwitch;

/**
 * FPS 显示项编辑器（整屏独立 State）：
 *   - 开关 FPS 计数器内的统计项（内存 / 峰值内存 / CPU / 版本信息）；
 *   - 调整显示顺序（↑↓ 按钮或 ←→ 键）；FPS 数字固定为主行（不可关、不可移）。
 *
 * 数据模型：ClientPrefs.data.fpsStatsList（CSV，仅启用项，顺序即显示顺序）。
 * FPS.hx 每 100ms tick 读存档重排 → 改动即时生效（左上角计数器可实时预览）；
 * 本界面只负责改清单 + 每次改动立即 ClientPrefs.saveSettings()。
 *
 * 几何与交互模板：substates.ScriptManagerSubstate（docs/UI-DESIGN.md 的面板基线）。
 * 返回路径：OptionsState.openCurrentExternal 进入前已预置 pendingSelectLabel，
 * saveAndExit 直接 switchState(OptionsState) 即自动落回「FPS 显示项」分区。
 */
class FPSStatsEditorState extends MusicBeatState
{
	// ===== 几何基线（ScriptManagerSubstate 同款） =====
	static final PANEL_X:Float = 160;
	static final PANEL_Y:Float = 96;
	static final PANEL_W:Float = 960;
	static final PANEL_H:Float = 560;
	static final ROW_X:Float = 204;
	static final ROW_START_Y:Float = 164;
	static final ROW_GAP:Float = 56;
	static final VALUE_RIGHT:Float = 1096;
	static final HINT_Y:Float = 668;
	static final ROW_TEXT_SIZE:Int = 24;

	// 右侧控件布局：开关 96 宽右缘贴 VALUE_RIGHT；↑↓ 两个 36 宽小按钮在其左侧
	static final SWITCH_W:Float = 96;
	static final SWITCH_H:Float = 32;
	static final ARROW_W:Float = 36;
	static final ARROW_GAP:Float = 8;
	static final ARROW_DOWN_X:Float = VALUE_RIGHT - SWITCH_W - ARROW_GAP - ARROW_W;
	static final ARROW_UP_X:Float = ARROW_DOWN_X - ARROW_GAP - ARROW_W;

	// 可编辑显示项（id 是存档 ASCII 令牌，绝不能改 —— 显示名走 fpsStatName.*）
	static final EDITABLE:Array<String> = ['Mem', 'Peak', 'CPU', 'Ver'];
	static final ROWS:Int = 5; // 行 0 = FPS 固定主行，行 1..4 = 清单行

	var selectorBar:FlxSprite;
	var selectorTween:FlxTween = null;
	var backBtn:BackButton;

	var grpLabels:Array<FlxText> = [];     // 行名（5）
	var grpRight:Array<FlxText> = [];      // 行 0 = 固定主行说明；行 1..4 = null 占位
	var switches:Array<ToggleSwitch> = []; // 行 0 = null 占位；行 1..4 = 开关
	var arrowsUp:Array<FlxText> = [];      // 行 0 = null 占位
	var arrowsDown:Array<FlxText> = [];

	var curSelected:Int = 0;
	var mouseActive:Bool = false;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var nextAccept:Int = 5; // 进入界面先忽略确认帧（防控制器/触屏误触，与 OptionsState 同规范）

	public function new()
	{
		super();
	}

	override public function create():Void
	{
		FlxG.mouse.visible = true;

		// 独立整屏界面：不透明深底（不经由暂停/游戏相机，无叠加需求）
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		bg.scrollFactor.set();
		add(bg);

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(0, 24, FlxG.width, Lang.tOr('options.title.fpsStats', 'FPS 显示项编辑'), 48);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		// ---- 磨砂面板 + 选中高亮条 ----
		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 20);
		add(panel);
		selectorBar = makePanel(PANEL_X + 16, ROW_START_Y - 4, PANEL_W - 32, 40, 12, DesignTokens.rowHighlight, null);
		add(selectorBar);

		// ---- 行控件（固定 5 行，无滚动） ----
		for (i in 0...ROWS)
		{
			var rowY:Float = ROW_START_Y + (i * ROW_GAP);

			var lbl:FlxText = new FlxText(ROW_X, rowY + 2, 0, '', ROW_TEXT_SIZE);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, 0xFF9A9AA8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.wordWrap = false; // 强制单行
			lbl.textField.x = 1;  // 1px 内边距，避免描边被裁（与基线一致）
			lbl.textField.y = 1;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			grpLabels.push(lbl);

			if (i == 0)
			{
				// FPS 固定主行：右侧说明文字（无开关）
				var pin:FlxText = new FlxText(VALUE_RIGHT - 220, rowY + 6, 220, '', 18);
				pin.scrollFactor.set();
				pin.setFormat(Paths.font('future.ttf'), 18, 0xFF666677, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				pin.borderSize = 1.5;
				pin.antialiasing = ClientPrefs.data.antialiasing;
				add(pin);
				grpRight.push(pin);
				switches.push(null);
			}
			else
			{
				var sw:ToggleSwitch = new ToggleSwitch(VALUE_RIGHT - SWITCH_W, rowY + 4, SWITCH_W, SWITCH_H);
				for (spr in sw.sprites) add(spr);
				switches.push(sw);
				grpRight.push(null);
			}

			if (i == 0)
			{
				arrowsUp.push(null);
				arrowsDown.push(null);
			}
			else
			{
				var up:FlxText = makeArrow(ARROW_UP_X, rowY + 4, '↑');
				add(up);
				arrowsUp.push(up);
				var down:FlxText = makeArrow(ARROW_DOWN_X, rowY + 4, '↓');
				add(down);
				arrowsDown.push(down);
			}
		}

		// ---- 右上返回按钮 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 底部操作提示 ----
		var hintTxt:FlxText = new FlxText(0, HINT_Y, FlxG.width,
			Lang.tOr('fpsEditor.hint', '上下选择，左右移动顺序，确认开关，Esc 返回；改动即时生效并自动保存'), 18);
		hintTxt.scrollFactor.set();
		hintTxt.setFormat(Paths.font('future.ttf'), 18, 0xFF9A9AA8, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintTxt.borderSize = 1.5;
		hintTxt.antialiasing = ClientPrefs.data.antialiasing;
		add(hintTxt);

		refreshList();
		super.create();
	}

	// ===== 数据视图 =====

	// 行序视图（单一来源，交互与刷新共用）：启用项按清单顺序在前，未启用项按默认顺序在后
	function rowLayout():Array<String>
	{
		var list:Array<String> = FPS.parseFpsStats();
		var rows:Array<String> = [];
		for (id in list) rows.push(id);
		for (id in EDITABLE)
			if (list.indexOf(id) < 0) rows.push(id);
		return rows;
	}

	// 显示项名（字面量 key，i18n 校验器可核对）
	function statName(id:String):String
	{
		return switch (id)
		{
			case 'Mem': Lang.tOr('fpsStatName.Mem', '内存');
			case 'Peak': Lang.tOr('fpsStatName.Peak', '峰值内存');
			case 'CPU': Lang.tOr('fpsStatName.CPU', 'CPU 占用');
			case 'Ver': Lang.tOr('fpsStatName.Ver', '版本信息');
			default: id;
		}
	}

	function refreshList():Void
	{
		var list:Array<String> = FPS.parseFpsStats();
		var layout:Array<String> = rowLayout();

		if (curSelected < 0) curSelected = 0;
		if (curSelected > ROWS - 1) curSelected = ROWS - 1;

		// 高亮条跟随（与 ScriptManagerSubstate 同款缓动）
		var barY:Float = ROW_START_Y - 4 + curSelected * ROW_GAP;
		if (selectorBar.y != barY)
		{
			if (selectorTween != null)
			{
				selectorTween.cancel();
				selectorTween = null;
			}
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
		}

		// 行 0：FPS 数字（固定主行）
		grpLabels[0].text = Lang.tOr('fpsStatName.FPS', 'FPS 数字');
		grpLabels[0].color = (curSelected == 0) ? FlxColor.WHITE : 0xFF9A9AA8;
		grpRight[0].text = Lang.tOr('fpsEditor.pinned', '固定主行');
		grpRight[0].color = 0xFF666677;

		for (i in 1...ROWS)
		{
			var id:String = layout[i - 1];
			var k:Int = list.indexOf(id);
			var enabled:Bool = (k >= 0);
			var sel:Bool = (curSelected == i);

			grpLabels[i].text = statName(id);
			grpLabels[i].color = sel ? FlxColor.WHITE : (enabled ? 0xFF9A9AA8 : 0xFF666677);

			// 行序随清单重排 → 开关状态直接吸附（不做滑动）
			switches[i].setOn(enabled, true);

			// 排序箭头：仅启用项可移动（边界处灰显）
			var canUp:Bool = enabled && (k > 0);
			var canDown:Bool = enabled && (k < list.length - 1);
			arrowsUp[i].color = canUp ? (sel ? FlxColor.WHITE : 0xFFB4B4C0) : 0xFF444450;
			arrowsDown[i].color = canDown ? (sel ? FlxColor.WHITE : 0xFFB4B4C0) : 0xFF444450;
		}
	}

	// ===== 操作 =====

	function changeSelection(change:Int):Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		curSelected += change;
		if (curSelected < 0) curSelected = ROWS - 1;
		if (curSelected >= ROWS) curSelected = 0;

		refreshList();
	}

	// 开关该行显示项（写入清单 + 立即落盘；FPS.hx 下个 tick 自动重排）
	function toggleItem(row:Int):Void
	{
		var list:Array<String> = FPS.parseFpsStats();
		var id:String = rowLayout()[row - 1];

		if (list.indexOf(id) >= 0)
		{
			list.remove(id);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		}
		else
		{
			list.push(id); // 重新启用 → 追加到队尾
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		}

		ClientPrefs.data.fpsStatsList = list.join(',');
		ClientPrefs.saveSettings();
		refreshList();
	}

	// 移动该行显示项（dir = -1 上移 / +1 下移；仅启用项，越界播取消音）
	function moveItem(row:Int, dir:Int):Void
	{
		if (row < 1)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
			return;
		}
		var list:Array<String> = FPS.parseFpsStats();
		var id:String = rowLayout()[row - 1];
		var k:Int = list.indexOf(id);
		if (k < 0)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4); // 未启用项不可移动
			return;
		}
		var nk:Int = k + dir;
		if (nk < 0 || nk >= list.length)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4); // 已在边界
			return;
		}
		list[k] = list[nk];
		list[nk] = id;

		ClientPrefs.data.fpsStatsList = list.join(',');
		ClientPrefs.saveSettings();
		curSelected = row + dir; // 选中跟随被移动的项（行序 = 清单序）
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refreshList();
	}

	function saveAndExit():Void
	{
		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		MusicBeatState.switchState(new OptionsState());
		// 返回分区由 OptionsState.pendingSelectLabel 恢复（openCurrentExternal 进入本界面前已预置）
		if (OptionsState.onPlayState)
		{
			if (ClientPrefs.data.pauseMusic != Lang.tOr('common.none', '无'))
				FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
			else
				FlxG.sound.music.volume = 0;
		}
		else
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
		FlxG.mouse.visible = false;
	}

	// ===== 命中区域（固定矩形，不依赖文本宽度） =====

	function getRowSlot(mx:Float, my:Float):Int
	{
		for (i in 0...ROWS)
		{
			var rowY:Float = ROW_START_Y + i * ROW_GAP;
			if (mx >= ROW_X && mx <= VALUE_RIGHT && my >= rowY - 8 && my < rowY + ROW_GAP - 8)
				return i;
		}
		return -1;
	}

	function arrowHit(mx:Float, my:Float, row:Int, dir:Int):Bool
	{
		if (row < 1) return false;
		var rowY:Float = ROW_START_Y + row * ROW_GAP;
		var x:Float = (dir < 0) ? ARROW_UP_X : ARROW_DOWN_X;
		return mx >= x - 4 && mx <= x + ARROW_W + 4 && my >= rowY - 6 && my <= rowY + 46;
	}

	// ===== 主循环 =====

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// 开关滑块动画推进
		for (i in 1...ROWS)
			if (switches[i] != null) switches[i].animate(elapsed);

		var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(FlxG.camera, FlxPoint.get());

		if (controls.UI_UP_P)
		{
			mouseActive = false;
			mouseLockX = mousePos.x;
			mouseLockY = mousePos.y;
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			mouseActive = false;
			mouseLockX = mousePos.x;
			mouseLockY = mousePos.y;
			changeSelection(1);
		}
		if (controls.UI_LEFT_P)
		{
			mouseActive = false;
			mouseLockX = mousePos.x;
			mouseLockY = mousePos.y;
			moveItem(curSelected, -1);
		}
		if (controls.UI_RIGHT_P)
		{
			mouseActive = false;
			mouseLockX = mousePos.x;
			mouseLockY = mousePos.y;
			moveItem(curSelected, 1);
		}

		if (!controls.controllerMode)
		{
			var slot:Int = getRowSlot(mousePos.x, mousePos.y);

			// 悬停高亮（选中行之外重算基色/悬停色，含未启用行灰显）
			var layout:Array<String> = rowLayout();
			var list:Array<String> = FPS.parseFpsStats();
			for (i in 0...ROWS)
			{
				if (i == curSelected) continue;
				var enabled:Bool = (i == 0) || (list.indexOf(layout[i - 1]) >= 0);
				grpLabels[i].color = (slot == i) ? 0xFFD7D7E0 : (enabled ? 0xFF9A9AA8 : 0xFF666677);
			}

			if (!mouseActive)
			{
				var dx:Float = mousePos.x - mouseLockX;
				var dy:Float = mousePos.y - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			backBtn.setHovered(mousePos.x, mousePos.y);
			if (FlxG.mouse.justPressed && backBtn.over(mousePos.x, mousePos.y))
			{
				mousePos.put();
				saveAndExit();
				return;
			}

			if (FlxG.mouse.justPressed && slot >= 0)
			{
				mouseActive = true;
				if (arrowHit(mousePos.x, mousePos.y, slot, -1))
					moveItem(slot, -1);
				else if (arrowHit(mousePos.x, mousePos.y, slot, 1))
					moveItem(slot, 1);
				else if (slot == 0)
				{
					// 固定主行：点击只选中，不可开关
					if (curSelected != 0)
					{
						curSelected = 0;
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
						refreshList();
					}
					else
						FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
				}
				else
				{
					curSelected = slot;
					toggleItem(slot);
				}
			}
		}
		mousePos.put();

		if (controls.BACK)
		{
			saveAndExit();
			return;
		}

		if (nextAccept <= 0 && controls.ACCEPT)
		{
			if (curSelected == 0)
				FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
			else
				toggleItem(curSelected);
		}
		if (nextAccept > 0) nextAccept -= 1;
	}

	// ===== 局部工具 =====

	function makeArrow(x:Float, y:Float, glyph:String):FlxText
	{
		var a:FlxText = new FlxText(x, y, ARROW_W, glyph, 24);
		a.scrollFactor.set();
		a.setFormat(Paths.font('future.ttf'), 24, 0xFFB4B4C0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		a.borderSize = 1.5;
		a.antialiasing = ClientPrefs.data.antialiasing;
		return a;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是编译期常量（Haxe 限制），故默认 null、在此解析当前主题值
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	#if mobile
	/** 返回键 = 保存并回到设置 */
	override public function onAndroidBack():Bool
	{
		saveAndExit();
		return true;
	}
	#end
}
