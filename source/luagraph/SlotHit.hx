package luagraph;

import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import backend.DesignTokens;
import backend.Paths;

/** 一个参数槽的命中矩形（坐标一律为**舞台绝对坐标**，便于鼠标命中）。 */
class SlotHit
{
	public var name:String;
	public var label:String;
	public var kind:GKind;
	public var ax:Float;
	public var ay:Float;
	public var aw:Float;
	public var ah:Float;

	public function new(name:String, label:String, kind:GKind, ax:Float, ay:Float, aw:Float, ah:Float)
	{
		this.name = name;
		this.label = label;
		this.kind = kind;
		this.ax = ax;
		this.ay = ay;
		this.aw = aw;
		this.ah = ah;
	}

	public function hit(mx:Float, my:Float):Bool
	{
		return mx >= ax && mx <= ax + aw && my >= ay && my <= ay + ah;
	}
}
