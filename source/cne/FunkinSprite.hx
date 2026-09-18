package cne;

import flixel.FlxSprite;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;

/**
 * CNE `FunkinSprite` 最小兼容类。
 *
 * 为什么不能直接把 `FunkinSprite` 这个 HScript 变量 set 成 `flixel.FlxSprite`：
 * SMA 的 CNE 歌曲脚本有 `var fadeThing:FunkinSprite = new FunkinSprite().makeGraphic(...)`，
 * HScript/SScript 的类型检查会把链式 `makeGraphic` 的返回类型当成 `FlxSprite`，
 * 赋值给 `:FunkinSprite` 时报 “FlxSprite should be FunkinSprite for variable "fadeThing"”
 * （2026-09-18 实测）。所以这里提供一个真实子类，并把 `makeGraphic` 的返回类型协变成
 * `FunkinSprite`，让 CNE 脚本的链式写法通过类型检查。
 *
 * 其余方法（`frames`/`animation`/`scale`/`screenCenter`/`camera` 等）全部继承 `FlxSprite`。
 */
@:keep
class FunkinSprite extends FlxSprite
{
	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);
	}

	override public function makeGraphic(width:Int, height:Int, color:FlxColor = FlxColor.WHITE, unique:Bool = false, ?key:String):FunkinSprite
	{
		super.makeGraphic(width, height, color, unique, key);
		return this;
	}

	/**
	 * Flixel 的 `FlxObject.screenCenter` 是 `inline`，hxcpp 反射拿不到函数指针；
	 * CNE 脚本会 `pluh.screenCenter()`，所以这里用真实（非 inline）方法覆盖。
	 */
	@:keep
	override public function screenCenter(axes:FlxAxes = FlxAxes.XY):FunkinSprite
	{
		super.screenCenter(axes);
		return this;
	}
}
