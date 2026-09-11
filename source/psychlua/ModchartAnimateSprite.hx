package psychlua;

#if flxanimate
import flxanimate.PsychFlxAnimate;

class ModchartAnimateSprite extends flxanimate.PsychFlxAnimate
{
	public var animOffsets:Map<String, Array<Float>> = new Map<String, Array<Float>>();
	public function new(?x:Float = 0, ?y:Float = 0, ?path:String, ?settings:flxanimate.FlxAnimate.Settings)
	{
		super(x, y, path, settings);
		antialiasing = ClientPrefs.data.antialiasing;
	}

	// @:keep：playAnim/addOffset 只被 Lua/反射调用，release 的 -dce full 会把它裁掉，
	// 导致 Lua playAnim 回退到 FlxSprite.animation.play（flxanimate 精灵永不播放、卡首帧）
	@:keep
	public function playAnim(name:String, forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
	{
		anim.play(name, forced, reverse, startFrame);

		var daOffset = animOffsets.get(name);
		if (animOffsets.exists(name)) offset.set(daOffset[0], daOffset[1]);
	}

	@:keep
	public function addOffset(name:String, x:Float, y:Float)
	{
		animOffsets.set(name, [x, y]);
	}
}
#end
