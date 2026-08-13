package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

// Phigros 式判定线：发光横线 + 轨道标记点，随歌曲时间上下平滑浮动。
// 音符块到达判定线（strumTime）时命中，判定线与音符同步移动。
class PhigrosJudgeLine extends FlxSpriteGroup
{
	public var line:FlxSprite; // 主光线
	public var glow:FlxSprite; // 光晕
	public var flashLayer:FlxSprite; // 命中闪光层

	var baseY:Float;
	var flashTween:FlxTween;

	// 自定义界面：HUD 布局偏移（由游玩界面应用/调整）
	public var layoutOffsetY:Float = 0;

	public function new()
	{
		super();
		baseY = 50; // 与原版箭头判定线（upscroll）同一位置
		y = baseY;

		// 光晕（下层）
		glow = new FlxSprite(0, -18).makeGraphic(Std.int(FlxG.width), 36, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(glow, 0, 0, FlxG.width, 36, 18, 18, 0x2EFFFFFF);
		glow.alpha = 0.55;
		add(glow);

		// 主光线
		line = new FlxSprite(0, -2).makeGraphic(Std.int(FlxG.width), 5, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(line, 0, 0, FlxG.width, 5, 2.5, 2.5, 0xFFFFFFFF);
		add(line);

		// 命中闪光层（透明，命中时闪白后淡出）
		flashLayer = new FlxSprite(0, -16).makeGraphic(Std.int(FlxG.width), 32, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(flashLayer, 0, 0, FlxG.width, 32, 16, 16, 0x66FFFFFF);
		flashLayer.alpha = 0;
		add(flashLayer);

		scrollFactor.set();
	}

	// 判定线浮动：基于歌曲位置的正弦平滑移动（Phigros 判定线移动感）
	public function updateFloat(elapsed:Float):Void
	{
		if (PlayState.instance != null && PlayState.instance.paused) return;
		var t:Float = Conductor.songPosition / 1000;
		y = baseY + layoutOffsetY + Math.sin(t * 1.7) * 14;
	}

	// 命中闪光：判定线整体闪白一下
	public function flash():Void
	{
		flashLayer.alpha = 0.85;
		if (flashTween != null) flashTween.cancel();
		flashTween = FlxTween.tween(flashLayer, {alpha: 0}, 0.22, {ease: FlxEase.cubeOut});
	}
}
