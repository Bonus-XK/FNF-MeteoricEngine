package states.editors;

import states.editors.ChartWidgets.EditorButton;
import states.editors.ChartWidgets.EditorDropdown;
import states.editors.ChartWidgets.EditorInput;
import states.editors.ChartWidgets.EditorStepper;
import states.editors.ChartWidgets.EditorToggle;


import backend.ClientPrefs;
import backend.Paths;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxTimer;

/**
 * 编谱设置面板（重写版）：
 * - 每标签页独立控件注册表（tabButtons/tabToggles/...），命中与点击只作用于当前标签页，
 *   根除跨标签页矩形重叠导致的“悬浮一个按钮其它按钮也亮”。
 * - 面板/标签页/Toast 全部自包含；ChartingState 只负责 add*UI 的功能回调接线。
 */
class ChartingPanel extends FlxSpriteGroup
{
	public static final PANEL_X:Float = 656;
	public static final PANEL_Y:Float = 20;
	public static final PANEL_W:Float = 472;
	public static final PANEL_H:Float = 600;
	public static final CONTENT_X:Float = PANEL_X + 16;
	public static final CONTENT_Y:Float = PANEL_Y + 100;
	public static final CONTENT_W:Float = PANEL_W - 32;
	public static final CONTENT_RW:Float = (PANEL_W - 48) / 2;

	public var tabGroups:Array<FlxSpriteGroup> = [];
	public var tabButtons:Array<Array<EditorButton>> = [];
	public var tabToggles:Array<Array<EditorToggle>> = [];
	public var tabInputs:Array<Array<EditorInput>> = [];
	public var tabSteppers:Array<Array<EditorStepper>> = [];
	public var tabDropdowns:Array<Array<EditorDropdown>> = [];
	public var dropdownLayer:FlxSpriteGroup;
	public var curTab:Int = 0;
	public var toastText:FlxText;
	public var toastTimer:FlxTimer;

	var tabBtns:Array<{bg:FlxSprite, txt:FlxText}> = [];
	var lastHoveredTab:Int = -2;
	static final TAB_LABELS:Array<String> = ['歌曲', '小节', '音符', '事件', '编曲', '数据'];

	public function new()
	{
		super();
	}

	public function build():Void
	{
		add(makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22));
		add(makeText(CONTENT_X, PANEL_Y + 14, CONTENT_W, '编谱设置', 22, 0xFFFFFFFF));

		for (i in 0...TAB_LABELS.length)
		{
			var btnBg:FlxSprite = new FlxSprite(PANEL_X + 12 + i * 76, PANEL_Y + 52).makeGraphic(74, 30, FlxColor.TRANSPARENT, true);
			btnBg.antialiasing = ClientPrefs.data.antialiasing;
			btnBg.scrollFactor.set();
			redrawBox(btnBg, 74, 30, 10, 0x1CFFFFFF, 0x45FFFFFF);
			add(btnBg);
			var btnTxt:FlxText = makeText(PANEL_X + 12 + i * 76, PANEL_Y + 58, 74, TAB_LABELS[i], 13, 0xFFB8B8C8, CENTER);
			add(btnTxt);
			tabBtns.push({bg: btnBg, txt: btnTxt});
		}

		for (i in 0...TAB_LABELS.length)
		{
			var grp:FlxSpriteGroup = new FlxSpriteGroup();
			grp.visible = false;
			grp.active = false;
			add(grp);
			tabGroups.push(grp);
			tabButtons.push([]);
			tabToggles.push([]);
			tabInputs.push([]);
			tabSteppers.push([]);
			tabDropdowns.push([]);
		}

		dropdownLayer = new FlxSpriteGroup();
		add(dropdownLayer);

		toastText = makeText(CONTENT_X, PANEL_Y + PANEL_H - 40, CONTENT_W, '', 13, 0xFFFFFFFF, CENTER);
		toastText.visible = false;
		add(toastText);

		changeTab(0);
	}

	/** 注册控件：加入所属标签页组 + 对应控件类型注册表（命中/点击只扫当前页） */
	public function register(tab:Int, w:Dynamic):Void
	{
		tabGroups[tab].add(cast w);
		if (Std.isOfType(w, EditorButton)) tabButtons[tab].push(cast w);
		else if (Std.isOfType(w, EditorToggle)) tabToggles[tab].push(cast w);
		else if (Std.isOfType(w, EditorInput)) tabInputs[tab].push(cast w);
		else if (Std.isOfType(w, EditorStepper)) tabSteppers[tab].push(cast w);
		else if (Std.isOfType(w, EditorDropdown)) tabDropdowns[tab].push(cast w);
	}

	public function changeTab(t:Int):Void
	{
		if (t < 0 || t >= tabGroups.length) return;
		curTab = t;
		for (i in 0...tabGroups.length)
		{
			tabGroups[i].visible = (i == t);
			tabGroups[i].active = (i == t);
		}
		blurAllInputs();
		for (d in tabDropdowns[curTab]) if (d.open) d.close();
		refreshTabButtons();
	}

	public function refreshTabButtons():Void
	{
		for (i in 0...tabBtns.length)
		{
			var active:Bool = (i == curTab);
			redrawBox(tabBtns[i].bg, 74, 30, 10, active ? 0x38FFFFFF : 0x1CFFFFFF, active ? 0x8CFFFFFF : 0x45FFFFFF);
			tabBtns[i].txt.color = active ? 0xFFFFFFFF : 0xFFB8B8C8;
		}
	}

	public function showToast(msg:String):Void
	{
		toastText.text = msg;
		toastText.visible = true;
		toastText.alpha = 1;
		if (toastTimer != null) toastTimer.cancel();
		toastTimer = new FlxTimer().start(2.2, function(_)
		{
			FlxTween.tween(toastText, {alpha: 0}, 0.4, {onComplete: function(_) toastText.visible = false});
		});
	}

	public function blurAllInputs():Void
	{
		for (i in tabInputs) for (inp in i) inp.field.hasFocus = false;
	}

	/** 每帧 UI 交互入口：标签页 hover/点击 + 当前页控件命中/点击（含下拉展开态） */
	public function updatePanel(mx:Float, my:Float):Void
	{
		var hoveredTab:Int = -1;
		for (i in 0...tabBtns.length)
		{
			var b = tabBtns[i];
			var hover:Bool = mx >= b.bg.x && mx <= b.bg.x + b.bg.width && my >= b.bg.y && my <= b.bg.y + b.bg.height;
			if (hover) hoveredTab = i;
		}
		if (hoveredTab != lastHoveredTab)
		{
			lastHoveredTab = hoveredTab;
			for (i in 0...tabBtns.length)
			{
				redrawBox(tabBtns[i].bg, 74, 30, 10, (i == curTab || i == hoveredTab) ? 0x30FFFFFF : 0x1CFFFFFF, (i == curTab || i == hoveredTab) ? 0x8CFFFFFF : 0x45FFFFFF);
				tabBtns[i].txt.color = (i == curTab) ? 0xFFFFFFFF : (i == hoveredTab ? 0xFFE0E0E8 : 0xFFB8B8C8);
			}
		}
		if (FlxG.mouse.justPressed && hoveredTab >= 0 && hoveredTab != curTab)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
			changeTab(hoveredTab);
		}

		var typing:Bool = false;
		for (inp in tabInputs[curTab]) if (inp.field.hasFocus) { typing = true; break; }

		var openDropdown:EditorDropdown = null;
		for (d in tabDropdowns[curTab]) if (d.open) { openDropdown = d; break; }

		if (openDropdown != null) openDropdown.updateOpen();
		else if (!typing) updateWidgets(mx, my);
	}

	function updateWidgets(mx:Float, my:Float):Void
	{
		var clicked:Bool = FlxG.mouse.justPressed;

		for (b in tabButtons[curTab])
		{
			b.setHovered(b.over(mx, my));
			if (clicked && b.over(mx, my) && b.onClick != null)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
				b.onClick();
			}
		}
		for (t in tabToggles[curTab])
		{
			t.setHovered(t.over(mx, my));
			if (clicked && t.over(mx, my)) t.toggle();
		}
		for (s in tabSteppers[curTab])
		{
			s.setHovered(s.overMinus(mx, my), s.overPlus(mx, my));
			if (clicked)
			{
				if (s.overMinus(mx, my)) s.stepBy(-1, FlxG.keys.pressed.SHIFT);
				else if (s.overPlus(mx, my)) s.stepBy(1, FlxG.keys.pressed.SHIFT);
			}
		}
		for (d in tabDropdowns[curTab])
		{
			d.setHovered(d.over(mx, my));
			if (clicked && d.over(mx, my))
			{
				for (other in tabDropdowns[curTab]) if (other != d && other.open) other.close();
				d.toggle();
			}
		}
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, ?color:Int = 0xFFD7D7E0, ?align:FlxTextAlign = LEFT, ?font:String = 'future.ttf'):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font(font), size, color, align, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		t.antialiasing = ClientPrefs.data.antialiasing;
		return t;
	}

	function redrawBox(spr:FlxSprite, w:Int, h:Int, radius:Float, fill:Int, border:Int):Void
	{
		spr.pixels.fillRect(spr.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != 0)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.dirty = true;
	}
}
