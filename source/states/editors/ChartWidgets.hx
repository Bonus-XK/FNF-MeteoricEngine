package states.editors;

import backend.ClientPrefs;
import backend.Paths;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.addons.ui.FlxInputText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

class EditorButton extends FlxSpriteGroup
{
	public var onClick:Void->Void;
	public var enabled:Bool = true;
	public var hovered:Bool = false;
	public var bg:FlxSprite;
	public var label:FlxText;
	var accent:Bool;
	var w:Float;
	var h:Float;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, ?onClick:Void->Void, ?size:Int = 14, ?accent:Bool = false)
	{
		super(x, y);
		this.onClick = onClick;
		this.accent = accent;
		this.w = w;
		this.h = h;

		bg = new FlxSprite(0, 0).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		redraw();
		add(bg);

		label = new FlxText(0, 0, Std.int(w), text, size);
		label.setFormat(Paths.font('future.ttf'), size, accent ? 0xFFFFFFFF : 0xFFD7D7E0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.2;
		label.scrollFactor.set();
		label.antialiasing = ClientPrefs.data.antialiasing;
		label.y = (h - label.height) / 2;
		add(label);
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + w && my >= y && my <= y + h;
	}

	public function setHovered(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		redraw();
	}

	function redraw():Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		var fill:Int = hovered ? 0x36FFFFFF : (accent ? 0x2EFFFFFF : 0x1CFFFFFF);
		var border:Int = hovered ? 0x8CFFFFFF : (accent ? 0x66FFFFFF : 0x45FFFFFF);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, w, h, 10, 10, fill, {color: border, thickness: 1.5});
		bg.dirty = true;
	}
}

class EditorToggle extends FlxSpriteGroup
{
	public var checked:Bool;
	public var onChange:Bool->Void;
	public var label:FlxText;
	var box:FlxSprite;
	var checkTxt:FlxText;
	public var hovered:Bool = false;
	var hitW:Float = 220;

	public function new(x:Float, y:Float, text:String, initial:Bool, ?onChange:Bool->Void, ?labelW:Float = 200)
	{
		super(x, y);
		this.onChange = onChange;
		checked = initial;

		box = new FlxSprite(0, 0).makeGraphic(22, 22, FlxColor.TRANSPARENT, true);
		box.antialiasing = ClientPrefs.data.antialiasing;
		box.scrollFactor.set();
		add(box);

		checkTxt = new FlxText(1, -1, 22, '✓', 15);
		checkTxt.setFormat(Paths.font('future.ttf'), 15, 0xFFFFFFFF, CENTER);
		checkTxt.scrollFactor.set();
		checkTxt.visible = checked;
		add(checkTxt);

		label = new FlxText(30, 2, Std.int(labelW), text, 14);
		label.setFormat(Paths.font('future.ttf'), 14, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.2;
		label.scrollFactor.set();
		label.antialiasing = ClientPrefs.data.antialiasing;
		add(label);

		hitW = 30 + label.width;
		redraw();
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x - 4 && mx <= x + hitW && my >= y - 4 && my <= y + 30;
	}

	public function setHovered(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		redraw();
	}

	public function toggle():Void
	{
		checked = !checked;
		checkTxt.visible = checked;
		redraw();
		if (onChange != null) onChange(checked);
	}

	public function setChecked(v:Bool, fire:Bool = true):Void
	{
		if (checked == v) return;
		checked = v;
		checkTxt.visible = checked;
		redraw();
		if (fire && onChange != null) onChange(checked);
	}

	function redraw():Void
	{
		box.pixels.fillRect(box.pixels.rect, FlxColor.TRANSPARENT);
		var fill:Int = checked ? 0x406B7CFF : (hovered ? 0x26FFFFFF : 0x12FFFFFF);
		var border:Int = checked ? 0x8C9BB5FF : 0x45FFFFFF;
		FlxSpriteUtil.drawRoundRect(box, 0, 0, 22, 22, 6, 6, fill, {color: border, thickness: 1.5});
		box.dirty = true;
	}
}

class EditorInput extends FlxSpriteGroup
{
	public var field:FlxInputText;
	public var bg:FlxSprite;
	public var labelTxt:FlxText;
	public var userOnChange:String->Void;
	var h:Float = 30;

	public function new(x:Float, y:Float, w:Float, label:String, value:String, ?userOnChange:String->Void, ?numeric:Bool = false)
	{
		super(x, y);
		this.userOnChange = userOnChange;

		labelTxt = new FlxText(0, -20, Std.int(w), label, 12);
		labelTxt.setFormat(Paths.font('future.ttf'), 12, 0xFF8A8FA8, LEFT);
		labelTxt.scrollFactor.set();
		add(labelTxt);

		bg = new FlxSprite(0, 0).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		redraw(false);
		add(bg);

		field = new FlxInputText(8, 5, Std.int(w) - 16, value, 14, 0xFFE8E8F0, FlxColor.TRANSPARENT);
		field.setFormat(Paths.font('future.ttf'), 14, 0xFFE8E8F0, LEFT);
		field.scrollFactor.set();
		field.antialiasing = ClientPrefs.data.antialiasing;
		if (numeric) field.customFilterPattern = ~/[^0-9.\-]/g;
		field.callback = function(text:String, action:String)
		{
			if (action == FlxInputText.ENTER_ACTION) field.hasFocus = false;
			if (userOnChange != null) userOnChange(text);
		};
		field.focusGained = function() redraw(true);
		field.focusLost = function() redraw(false);
		add(field);
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + bg.width && my >= y && my <= y + h;
	}

	public function setText(v:String):Void
	{
		if (field.text != v) field.text = v;
	}

	function redraw(focused:Bool):Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, bg.width, h, 8, 8, focused ? 0x1EFFFFFF : 0x10FFFFFF, {color: focused ? 0x66FFFFFF : 0x30FFFFFF, thickness: 1.5});
		bg.dirty = true;
	}
}

class EditorStepper extends FlxSpriteGroup
{
	public var value:Float;
	public var min:Float;
	public var max:Float;
	public var step:Float;
	public var onChange:Float->Void;
	public var labelTxt:FlxText;
	var minusBtn:FlxSprite;
	var plusBtn:FlxSprite;
	var minusTxt:FlxText;
	var plusTxt:FlxText;
	var valueTxt:FlxText;
	var decimals:Int;
	var hoverMinus:Bool = false;
	var hoverPlus:Bool = false;
	var w:Float;
	var h:Float = 30;

	public function new(x:Float, y:Float, w:Float, label:String, value:Float, min:Float, max:Float, step:Float, ?decimals:Int = 2, ?onChange:Float->Void)
	{
		super(x, y);
		this.value = value;
		this.min = min;
		this.max = max;
		this.step = step;
		this.onChange = onChange;
		this.decimals = decimals;
		this.w = w;

		labelTxt = new FlxText(0, -20, Std.int(w), label, 12);
		labelTxt.setFormat(Paths.font('future.ttf'), 12, 0xFF8A8FA8, LEFT);
		labelTxt.scrollFactor.set();
		add(labelTxt);

		minusBtn = new FlxSprite(0, 0).makeGraphic(30, Std.int(h), FlxColor.TRANSPARENT, true);
		minusBtn.antialiasing = ClientPrefs.data.antialiasing;
		minusBtn.scrollFactor.set();
		add(minusBtn);

		plusBtn = new FlxSprite(w - 30, 0).makeGraphic(30, Std.int(h), FlxColor.TRANSPARENT, true);
		plusBtn.antialiasing = ClientPrefs.data.antialiasing;
		plusBtn.scrollFactor.set();
		add(plusBtn);

		minusTxt = new FlxText(0, 4, 30, '-', 16);
		minusTxt.setFormat(Paths.font('future.ttf'), 16, 0xFFD7D7E0, CENTER);
		minusTxt.scrollFactor.set();
		add(minusTxt);

		plusTxt = new FlxText(w - 30, 4, 30, '+', 16);
		plusTxt.setFormat(Paths.font('future.ttf'), 16, 0xFFD7D7E0, CENTER);
		plusTxt.scrollFactor.set();
		add(plusTxt);

		valueTxt = new FlxText(30, 6, Std.int(w - 60), '', 13);
		valueTxt.setFormat(Paths.font('future.ttf'), 13, 0xFFE8E8F0, CENTER);
		valueTxt.scrollFactor.set();
		add(valueTxt);

		redraw();
		updateValueText();
	}

	public function overMinus(mx:Float, my:Float):Bool { return mx >= x && mx <= x + 30 && my >= y && my <= y + h; }
	public function overPlus(mx:Float, my:Float):Bool { return mx >= x + w - 30 && mx <= x + w && my >= y && my <= y + h; }

	public function setHovered(vMinus:Bool, vPlus:Bool):Void
	{
		if (hoverMinus == vMinus && hoverPlus == vPlus) return;
		hoverMinus = vMinus;
		hoverPlus = vPlus;
		redraw();
	}

	public function stepBy(sign:Int, big:Bool):Void
	{
		var s:Float = step * (big ? 10 : 1);
		value = FlxMath.bound(value + sign * s, min, max);
		updateValueText();
		if (onChange != null) onChange(value);
	}

	public function setValue(v:Float):Void
	{
		value = FlxMath.bound(v, min, max);
		updateValueText();
	}

	function updateValueText():Void
	{
		valueTxt.text = Std.string(FlxMath.roundDecimal(value, decimals));
	}

	function redraw():Void
	{
		for (pair in [{spr: minusBtn, hover: hoverMinus}, {spr: plusBtn, hover: hoverPlus}])
		{
			pair.spr.pixels.fillRect(pair.spr.pixels.rect, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(pair.spr, 0, 0, pair.spr.width, pair.spr.height, 8, 8, pair.hover ? 0x30FFFFFF : 0x14FFFFFF, {color: pair.hover ? 0x66FFFFFF : 0x38FFFFFF, thickness: 1.5});
			pair.spr.dirty = true;
		}
	}
}

class EditorDropdown extends FlxSpriteGroup
{
	public var options:Array<String>;
	public var selectedIndex:Int = 0;
	public var onChange:Int->Void;
	public var open:Bool = false;
	public var labelTxt:FlxText;
	var bg:FlxSprite;
	var valueTxt:FlxText;
	var arrowTxt:FlxText;
	public var hovered:Bool = false;
	var w:Float;
	var h:Float = 30;
	var layer:FlxSpriteGroup;
	var panelBg:FlxSprite;
	var panelItems:Array<{bg:FlxSprite, txt:FlxText}> = [];
	var scroll:Int = 0;
	var hoveredItem:Int = -1;
	var lastHoveredItem:Int = -999;
	var lastSelectedForHover:Int = -999;
	var visibleRows:Int = 6;
	var rowH:Int = 30;

	public function new(x:Float, y:Float, w:Float, label:String, options:Array<String>, selectedIndex:Int, ?onChange:Int->Void, layer:FlxSpriteGroup)
	{
		super(x, y);
		this.options = options;
		this.selectedIndex = selectedIndex;
		this.onChange = onChange;
		this.layer = layer;
		this.w = w;

		labelTxt = new FlxText(0, -20, Std.int(w), label, 12);
		labelTxt.setFormat(Paths.font('future.ttf'), 12, 0xFF8A8FA8, LEFT);
		labelTxt.scrollFactor.set();
		add(labelTxt);

		bg = new FlxSprite(0, 0).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		add(bg);

		valueTxt = new FlxText(10, 6, Std.int(w - 42), '', 13);
		valueTxt.setFormat(Paths.font('future.ttf'), 13, 0xFFE8E8F0, LEFT);
		valueTxt.scrollFactor.set();
		add(valueTxt);

		arrowTxt = new FlxText(w - 26, 3, 20, '▾', 14);
		arrowTxt.setFormat(Paths.font('future.ttf'), 14, 0xFFB8B8C8, CENTER);
		arrowTxt.scrollFactor.set();
		add(arrowTxt);

		redraw();
		refreshLabel();
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + w && my >= y && my <= y + h;
	}

	public function setHovered(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		redraw();
	}

	public function selectIndex(i:Int):Void
	{
		selectedIndex = i;
		refreshLabel();
	}

	public function refreshLabel():Void
	{
		if (selectedIndex >= 0 && selectedIndex < options.length) valueTxt.text = options[selectedIndex];
		else valueTxt.text = '';
	}

	public function toggle():Void
	{
		if (open) close();
		else openPanel();
	}

	function openPanel():Void
	{
		open = true;
		scroll = 0;
		hoveredItem = -1;
		redraw();
		panelBg = new FlxSprite(x, y + h).makeGraphic(Std.int(w), visibleRows * rowH + 8, DesignTokens.panelFill, true);
		panelBg.antialiasing = true;
		panelBg.scrollFactor.set();
		FlxSpriteUtil.drawRoundRect(panelBg, 0, 0, w, visibleRows * rowH + 8, 10, 10, DesignTokens.panelFill, {color: 0x55FFFFFF, thickness: 1.5});
		layer.add(panelBg);
		rebuildItems();
	}

	public function close():Void
	{
		open = false;
		redraw();
		if (panelBg != null)
		{
			layer.remove(panelBg);
			panelBg.destroy();
			panelBg = null;
		}
		for (it in panelItems)
		{
			layer.remove(it.bg);
			layer.remove(it.txt);
			it.bg.destroy();
			it.txt.destroy();
		}
		panelItems = [];
	}

	public function updateOpen():Void
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;

		if (FlxG.mouse.wheel != 0)
		{
			scroll -= FlxG.mouse.wheel;
			scroll = Std.int(FlxMath.bound(scroll, 0, Math.max(0, options.length - visibleRows)));
			rebuildItems();
		}

		hoveredItem = -1;
		for (i in 0...panelItems.length)
		{
			var it = panelItems[i];
			if (mx >= it.bg.x && mx <= it.bg.x + it.bg.width && my >= it.bg.y && my <= it.bg.y + it.bg.height) hoveredItem = scroll + i;
		}
		rebuildHover();

		if (FlxG.mouse.justPressed)
		{
			if (over(mx, my))
			{
				close();
				return;
			}
			if (hoveredItem >= 0 && hoveredItem < options.length)
			{
				selectedIndex = hoveredItem;
				refreshLabel();
				var cb:Int->Void = onChange;
				close();
				if (cb != null) cb(selectedIndex);
			}
			else if (panelBg != null && !(mx >= panelBg.x && mx <= panelBg.x + panelBg.width && my >= panelBg.y && my <= panelBg.y + panelBg.height))
			{
				close();
			}
		}
	}

	function rebuildItems():Void
	{
		for (it in panelItems)
		{
			layer.remove(it.bg);
			layer.remove(it.txt);
			it.bg.destroy();
			it.txt.destroy();
		}
		panelItems = [];

		if (panelBg == null) return;
		for (i in 0...visibleRows)
		{
			var idx:Int = scroll + i;
			if (idx >= options.length) break;
			var y:Float = panelBg.y + 4 + i * rowH;

			var bg:FlxSprite = new FlxSprite(panelBg.x + 4, y).makeGraphic(Std.int(w - 8), rowH - 4, 0x00FFFFFF, true);
			bg.antialiasing = true;
			bg.scrollFactor.set();
			layer.add(bg);

			var txt:FlxText = new FlxText(panelBg.x + 14, y + 6, Std.int(w - 28), options[idx], 13);
			txt.setFormat(Paths.font('future.ttf'), 13, 0xFFE8E8F0, LEFT);
			txt.scrollFactor.set();
			layer.add(txt);

			panelItems.push({bg: bg, txt: txt});
		}
		lastHoveredItem = -999;
		lastSelectedForHover = -999;
		rebuildHover();
	}

	function rebuildHover():Void
	{
		if (lastHoveredItem == hoveredItem && lastSelectedForHover == selectedIndex) return;
		lastHoveredItem = hoveredItem;
		lastSelectedForHover = selectedIndex;
		for (i in 0...panelItems.length)
		{
			var idx:Int = scroll + i;
			var selected:Bool = idx == selectedIndex;
			var hover:Bool = idx == hoveredItem;
			var it = panelItems[i];
			it.bg.pixels.fillRect(it.bg.pixels.rect, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(it.bg, 0, 0, it.bg.width, it.bg.height, 6, 6, hover ? 0x30FFFFFF : (selected ? 0x1EFFFFFF : 0x00FFFFFF));
			it.bg.dirty = true;
			it.txt.color = (hover || selected) ? 0xFFFFFFFF : 0xFFE8E8F0;
		}
	}

	function redraw():Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, w, h, 8, 8, open ? 0x1EFFFFFF : (hovered ? 0x26FFFFFF : 0x10FFFFFF), {color: open ? 0x66FFFFFF : (hovered ? 0x55FFFFFF : 0x30FFFFFF), thickness: 1.5});
		bg.dirty = true;
	}
}

