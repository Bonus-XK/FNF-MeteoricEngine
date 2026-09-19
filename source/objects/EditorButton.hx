package objects;

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
