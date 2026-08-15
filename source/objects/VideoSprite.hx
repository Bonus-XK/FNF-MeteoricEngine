package objects;

import flixel.FlxSprite;
import flixel.util.FlxColor;

/**
 * 极简 VideoSprite 兼容占位。
 * 让引用 VideoSprite 的 Psych 0.6.3 / 其他 Mod 在加载时不会因为类不存在而崩溃。
 * 目前不真正播放视频，只保证不报错；后续可接入真实视频播放。
 */
class VideoSprite extends FlxSprite
{
	public var videoSprite:Dynamic;
	public var cover:FlxSprite;
	public var bitmap:Dynamic;

	public function new(?source:Dynamic = null, ?loop:Bool = false)
	{
		super();
		makeGraphic(1, 1, FlxColor.TRANSPARENT);
		cover = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		videoSprite = new DummyVideoHandle();
		bitmap = videoSprite.bitmap;
	}

	public function playVideo(path:String):Void
	{
		// TODO: 接入真实视频播放
	}

	public function play():Void {}
	public function pause():Void {}
	public function resume():Void {}
}

class DummyVideoHandle
{
	public var bitmap:Dynamic;

	public function new()
	{
		bitmap = new DummyVideoBitmap();
	}
}

class DummyVideoBitmap
{
	public var rate:Float = 1;
	public var onEndReached:DummySignal;
	public var onFormatSetup:DummySignal;

	public function new()
	{
		onEndReached = new DummySignal();
		onFormatSetup = new DummySignal();
	}

	public function play():Void {}
	public function pause():Void {}
	public function resume():Void {}
}

class DummySignal
{
	public function new() {}

	public function add(cb:Dynamic):Void {}
	public function removeAll():Void {}
	public function remove(cb:Dynamic):Void {}
}
