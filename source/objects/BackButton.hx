package objects;

import flixel.util.FlxSpriteUtil;
import flixel.tweens.FlxTween;

class BackButton
{
	public var spr:FlxSprite;
	public var label:FlxText;
	public var glow:FlxSprite; // 悬停发光层（放在 spr 下层）
	var hovered:Bool = false;
	var glowTween:FlxTween;
	var awake:Bool = false; // 鼠标移动唤醒：避免界面打开时鼠标恰好停在按钮上直接发光
	var lastX:Float = 0;
	var lastY:Float = 0;

	public static inline var SIZE:Float = 56;

	public function new(x:Float, y:Float)
	{
		// 光晕层：三层白色圆由外到内渐强，模拟发光
		glow = new FlxSprite(x - 10, y - 10).makeGraphic(76, 76, FlxColor.TRANSPARENT, true);
		glow.antialiasing = true;
		FlxSpriteUtil.drawCircle(glow, 38, 38, 35, 0x10FFFFFF);
		FlxSpriteUtil.drawCircle(glow, 38, 38, 31, 0x26FFFFFF);
		FlxSpriteUtil.drawCircle(glow, 38, 38, 28, 0x4AFFFFFF);
		glow.alpha = 0;
		glow.scrollFactor.set();

		// 透明玻璃主体：低透明度白底 + 白色细边框，保留可见度
		spr = new FlxSprite(x, y).makeGraphic(Std.int(SIZE), Std.int(SIZE), FlxColor.TRANSPARENT, true);
		spr.antialiasing = true;
		FlxSpriteUtil.drawCircle(spr, SIZE / 2, SIZE / 2, SIZE / 2 - 1, 0x22FFFFFF, {color: 0x8CFFFFFF, thickness: 1.5});
		spr.color = 0xFFD5D9DF; // 默认轻微柔和，悬停恢复全亮
		spr.scrollFactor.set();

		label = new FlxText(x, y, Std.int(SIZE), "<", 30);
		label.setFormat(Paths.font("future.ttf"), 30, FlxColor.WHITE, CENTER);
		label.textField.height = 56;
		label.y += Math.max(0, (SIZE - label.textField.textHeight) / 2);
		label.scrollFactor.set();
		lastX = FlxG.mouse.screenX;
		lastY = FlxG.mouse.screenY;
	}

	public function over(mx:Float, my:Float):Bool
	{
		var dx:Float = mx - (spr.x + SIZE / 2);
		var dy:Float = my - (spr.y + SIZE / 2);
		return dx * dx + dy * dy <= (SIZE / 2) * (SIZE / 2);
	}

	public function setHovered(mx:Float, my:Float)
	{
		if (!awake)
		{
			var dx:Float = mx - lastX;
			var dy:Float = my - lastY;
			if (dx * dx + dy * dy < 100) return; // 鼠标未明显移动，不响应悬停
			awake = true;
		}
		lastX = mx;
		lastY = my;

		var v:Bool = over(mx, my);
		if (hovered == v) return;
		hovered = v;
		if (v)
		{
			if (glowTween != null) glowTween.cancel();
			glowTween = FlxTween.tween(glow, {alpha: 1}, 0.12, {ease: FlxEase.quadOut});
			spr.color = 0xFFFFFFFF; // 按钮整体发亮
		}
		else
		{
			if (glowTween != null) glowTween.cancel();
			glow.alpha = 0;
			spr.color = 0xFFD5D9DF;
		}
	}
}
