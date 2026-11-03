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
	var labelBaseY:Float = 0;   // 按压弹回的基准位（构造期定，press 时下沉后弹回）
	var pressTween:FlxTween;
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
		labelBaseY = label.y;
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
		var v:Bool = over(mx, my);
		// 按压检测（自动，调用点零改动）：悬停中按下即播反馈。
		// 必须放在 hovered==v 早退**之前**——鼠标已停在按钮上时 hovered 不再变化，
		// 早退会吞掉这一帧的 justPressed。
		// 触摸路径（clickPressed）不经过 FlxG.mouse.justPressed，移动端无按压反馈（可接受，功能不受影响）。
		if (v && awake && FlxG.mouse.justPressed) pressVisual();
		if (!awake)
		{
			var dx:Float = mx - lastX;
			var dy:Float = my - lastY;
			if (dx * dx + dy * dy < 100) return; // 鼠标未明显移动，不响应悬停
			awake = true;
		}
		lastX = mx;
		lastY = my;

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

	/** 按压反馈："<" 下沉 2px 弹回 + 边框白闪。纯视觉，不影响命中与点击判定。 */
	public function pressVisual():Void
	{
		if (pressTween != null) pressTween.cancel();
		label.y = labelBaseY + 2;
		pressTween = FlxTween.tween(label, {y: labelBaseY}, 0.14, {ease: FlxEase.quadOut});
		FlxTween.color(spr, 0.16, 0xFFFFFFFF, hovered ? 0xFFFFFFFF : 0xFFD5D9DF);
	}
}
