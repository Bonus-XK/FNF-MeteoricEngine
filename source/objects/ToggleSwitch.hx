package objects;

import backend.DesignTokens;
import backend.Paths;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxSpriteUtil;

/**
 * MD3 风格**开关（toggle switch）**：胶囊轨道 + 圆形滑块。
 *
 * 视觉规格**照抄**自「更新界面」（`states.OutdatedState` 的 updateNotify 开关），由本组件承载，
 * 让设置界面与更新界面看起来是同一个控件（更新界面本轮未动 —— 它那个"圆点飞出"修复已验证，
 * 后续收敛成两边共用本组件即可，届时删掉那边的私有实现）：
 *  - 轨道 96×32 胶囊（圆角 = 高的一半）；开 = `DesignTokens.primary` 填充 + primary 描边，
 *    关 = `0x66161622` 填充 + `DesignTokens.panelOutline` 描边（1.5px）；
 *  - 滑块直径 22，纯白圆；圆心在轨道内的活动区间 [16, 80]（= [h/2, w − h/2]）；
 *  - 切换动画：**圆心空间**插值 `FlxMath.lerp(..., elapsed * 18)`；首次落位**直接吸附**
 *    （否则会从错误初值滑进来）。
 *
 * ⚠ 两条踩过的坑（照抄自更新界面的修复）：
 *  1. 轨道**原地重绘**：不能靠 `makeGraphic` "重建"——尺寸不变时命中的是缓存里同一张 BitmapData，
 *     旧像素不会被清 → 「开」态的 primary 填充会残留在「关」态上（同尺寸精灵还会互相串图）。
 *     所以这里 `makeGraphic(..., unique: true)` + 每次 `pixels.fillRect` 清底再画。
 *  2. 夹取的是**圆心**、不是精灵左边框，且精灵 x 由圆心换算（`x = track.x + center − R`）。
 *
 * 用法（宿主自己负责命中与音效，组件不碰 ClientPrefs / Option）：
 *   var sw = new ToggleSwitch(x, y);
 *   for (spr in sw.sprites) add(spr);     // 两个精灵都是独立成员，宿主按需 add
 *   sw.setOn(value == true);
 *   // 每帧：sw.animate(elapsed)（或宿主 update 里统一推进）
 *   // 点击命中：sw.hits(mx, my)
 */
class ToggleSwitch
{
	public var track:FlxSprite;
	public var knob:FlxSprite;
	public var sprites:Array<FlxSprite> = [];

	public var on(default, null):Bool = false;
	public var width:Float;
	public var height:Float;

	var knobD:Float;
	var knobR:Float;
	var centerMin:Float;
	var centerMax:Float;
	var knobCenter:Float = 0;      // 当前圆心（轨道内坐标）
	var knobTarget:Float = 0;      // 目标圆心
	var placed:Bool = false;       // 是否已落位（首次直接吸附）

	public function new(x:Float, y:Float, ?w:Float = 96, ?h:Float = 32)
	{
		width = w;
		height = h;
		knobD = h - 10;
		knobR = knobD * 0.5;
		centerMin = h * 0.5;
		centerMax = w - h * 0.5;

		track = new FlxSprite(x, y);
		track.scrollFactor.set();
		sprites.push(track);

		knob = new FlxSprite(0, 0).makeGraphic(Std.int(knobD), Std.int(knobD), flixel.util.FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawCircle(knob, knobD * 0.5, knobD * 0.5, knobR, 0xFFFFFFFF);
		knob.updateHitbox();
		knob.y = y + (h - knob.height) * 0.5;
		knob.scrollFactor.set();
		sprites.push(knob);

		setOn(false, true);
	}

	/** 设定开关状态；instant = 不做滑动（首次落位 / 分区切换后立刻对齐用） */
	public function setOn(v:Bool, instant:Bool = false):Void
	{
		on = v;
		redrawTrack();
		knobTarget = on ? centerMax : centerMin;
		if (instant || !placed)
		{
			knobCenter = knobTarget;
			placed = true;
			placeKnob();
		}
	}

	/** 主题色变化后重绘（primary 是运行时令牌，切换主题要跟着变） */
	public function refreshTheme():Void
	{
		redrawTrack();
	}

	/** 逐帧推进滑块（宿主在 update 里调用；掉帧时靠 elapsed 保证手感一致） */
	public function animate(elapsed:Float):Void
	{
		if (Math.abs(knobCenter - knobTarget) < 0.05)
		{
			knobCenter = knobTarget;
		}
		else
		{
			knobCenter = FlxMath.lerp(knobCenter, knobTarget, Math.min(1, elapsed * 18));
		}
		placeKnob();
	}

	/** 移动整组开关（行位动态的列表用：模组列表的复选框位置随行位走） */
	public function setPosition(x:Float, y:Float):Void
	{
		track.x = x;
		track.y = y;
		knob.y = y + (height - knob.height) * 0.5;
		placeKnob();
	}

	/** 命中判定：轨道外扩 pad（默认 12 → 高 32+24 = 56 满足触控目标红线） */
	public function hits(mx:Float, my:Float, pad:Float = 12):Bool
	{
		return mx >= track.x - pad && mx <= track.x + width + pad
			&& my >= track.y - pad && my <= track.y + height + pad;
	}

	public function setVisible(v:Bool):Void
	{
		for (spr in sprites) spr.visible = v;
	}

	public function setAlpha(a:Float):Void
	{
		for (spr in sprites) spr.alpha = a;
	}

	public function destroy():Void
	{
		for (spr in sprites)
		{
			if (spr == null) continue;
			if (spr.graphic != null) FlxG.bitmap.removeIfNoUse(spr.graphic);
			spr.destroy();
		}
		sprites = [];
		track = null;
		knob = null;
	}

	function redrawTrack():Void
	{
		if (track.graphic == null)
			track.makeGraphic(Std.int(width), Std.int(height), flixel.util.FlxColor.TRANSPARENT, true);
		else
			track.pixels.fillRect(track.pixels.rect, flixel.util.FlxColor.TRANSPARENT);

		var radius:Float = height * 0.5;
		FlxSpriteUtil.drawRoundRect(track, 0, 0, width, height, radius, radius,
			on ? DesignTokens.primary : 0x66161622);
		FlxSpriteUtil.drawRoundRect(track, 1, 1, width - 2, height - 2, radius, radius,
			flixel.util.FlxColor.TRANSPARENT, {color: on ? DesignTokens.primary : DesignTokens.panelOutline, thickness: 1.5});
		track.dirty = true;
	}

	inline function placeKnob():Void
	{
		knob.x = track.x + knobCenter - knobR;
	}
}
