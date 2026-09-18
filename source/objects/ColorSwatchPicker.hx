package objects;

import flixel.util.FlxSpriteUtil;
import flixel.tweens.FlxTween;

/**
 * 主题色色块选择器（可复用组件）
 *
 * 职责：把固定色板渲染成一行可点击色块，并向宿主菜单回报"哪一格被点了"。
 * 它**不碰** ClientPrefs、**不调** Option —— 取值/存档由宿主菜单负责（见 BaseOptionsMenu.themeSwatches）。
 *
 * 设计合规（meteoric-design / meteoric-system / meteoric-mobile）：
 *  - 静态绘制：所有色块在 new() 时一次画好，**禁止**逐帧 makeGraphic（移动端性能红线）；
 *    与 objects/BackButton 同款做法（FlxSpriteUtil.drawCircle）。
 *  - 状态不靠颜色单独表达：选中 = 白色圆环，悬停/按压 = 缩放（1.08 / 0.97），键盘焦点 = 主题色圆环。
 *  - 触摸目标 56 逻辑 px（视觉直径 44，热区外边距 6）——满足移动端 ≥56×56。
 *  - 动效 ≤100ms quadOut（hover/press 属中频反馈），且复用的 tween 先 cancel 再启动。
 *  - 悬停**不改变选中**，只放大预览。
 *
 * 三套输入：
 *  - 键盘/手柄：由宿主菜单的选项行负责（本组件只响应"选中态演出"），故有 setKeyboardFocus()。
 *  - 鼠标：桌面 justPressed → click；移动端由宿主传入的 clickPressed（tap 抬起且未拖动）→ click。
 *  - 触控：同移动端路径，按压有缩放即时反馈。
 */
class ColorSwatchPicker
{
	// ===== 布局常量（8 的倍数网格；10 格 44px + 58px 步进 = 总宽 566）=====
	public static final SWATCH_DIAMETER:Float = 32;
	public static final SWATCH_STEP:Float = 44;
	/** 热区每侧外扩：视觉 32 + 12×2 = 56 逻辑 px，满足移动端触摸目标红线 */
	public static final SWATCH_HIT_PAD:Float = 12;

	/** 色块数量与颜色（按色板顺序；由宿主用 DesignTokens 的表填充） */
	public var colors:Array<FlxColor> = [];
	/** 整行可见性（setVisible 的读回接口：宿主据此判断"是否该吃这一帧的点击"） */
	public var isVisible(default, null):Bool = false;

	/** 当前选中索引（高亮圆环 / 键盘焦点圆环的位置） */
	public var selectedIndex(default, set):Int = 0;

	/** 是否响应鼠标/触控（宿主可在非主题选项时关掉，避免误点） */
	public var interactive:Bool = true;

	/** 是否显示键盘焦点环（宿主在"当前选中行 = 主题色行"时打开） */
	public var keyboardFocus(default, set):Bool = false;

	/** 色块被点击：回调参数 = 色板索引。宿主负责取值/存档/音效 */
	public var onClick:Int->Void = null;

	/** 添加进宿主 display group 的精灵（按层级顺序：底光 → 色块 → 圆环） */
	public var sprites:Array<FlxSprite> = [];

	var x:Float = 0;
	var y:Float = 0;

	var hoveredIndex:Int = -1;
	var pressedIndex:Int = -1;
	var pressedVisual:Bool = false;

	var glows:Array<FlxSprite> = [];
	var circles:Array<FlxSprite> = [];
	var rings:Array<FlxSprite> = [];

	var tweens:Array<FlxTween> = [];
	/** 每格色块的缩放 tween（复用时先 cancel，避免叠加） */
	var scaleTweens:Map<Int, FlxTween> = new Map<Int, FlxTween>();
	var themeListener:Void->Void = null;
	var destroyed:Bool = false;

	/**
	 * @param x      首个色块的圆心 X
	 * @param y      色块的圆心 Y
	 * @param colors 色板颜色（通常传 DesignTokens 的 PRIMARY 表）
	 */
	public function new(x:Float, y:Float, colors:Array<FlxColor>)
	{
		this.x = x;
		this.y = y;
		this.colors = (colors == null) ? [] : colors;

		var r:Float = SWATCH_DIAMETER / 2;

		for (i in 0...this.colors.length)
		{
			var cx:Float = cxOf(i);
			var cy:Float = this.y;

			// 悬停底光：比色块大一圈的柔光（三层递减，BackButton 同款手法）
			var glow:FlxSprite = new FlxSprite(cx - r - 9, cy - r - 9).makeGraphic(Std.int(SWATCH_DIAMETER + 18), Std.int(SWATCH_DIAMETER + 18), FlxColor.TRANSPARENT, true);
			glow.antialiasing = true;
			FlxSpriteUtil.drawCircle(glow, r + 9, r + 9, r + 8, 0x12FFFFFF);
			FlxSpriteUtil.drawCircle(glow, r + 9, r + 9, r + 5, 0x22FFFFFF);
			glow.alpha = 0;
			glow.scrollFactor.set();

			// 色块本体 + 深色描边（保证浅色色板在浅底上也可见）
			var circle:FlxSprite = new FlxSprite(cx - r, cy - r).makeGraphic(Std.int(SWATCH_DIAMETER), Std.int(SWATCH_DIAMETER), FlxColor.TRANSPARENT, true);
			circle.antialiasing = true;
			// 参数顺序：drawCircle(sprite, X, Y, Radius, FillColor, ?lineStyle, ?drawStyle)
			// —— 第 5 参是**填充色**、第 6 参才是描边样式。注意 Haxe 没有命名参数，必须按位置传。
			FlxSpriteUtil.drawCircle(circle, r, r, r - 1, this.colors[i], {color: 0x8C000000, thickness: 1.5});
			circle.scrollFactor.set();

			// 选中/焦点圆环（画在色块外圈，避免遮住颜色本身）
			var ring:FlxSprite = new FlxSprite(cx - r - 5, cy - r - 5).makeGraphic(Std.int(SWATCH_DIAMETER + 10), Std.int(SWATCH_DIAMETER + 10), FlxColor.TRANSPARENT, true);
			ring.antialiasing = true;
			FlxSpriteUtil.drawCircle(ring, r + 5, r + 5, r + 3, FlxColor.TRANSPARENT, {color: 0xFFFFFFFF, thickness: 2.5});
			ring.visible = false;
			ring.scrollFactor.set();

			glows.push(glow);
			circles.push(circle);
			rings.push(ring);
			sprites.push(glow);
			sprites.push(circle);
			sprites.push(ring);
		}

		setSelectedVisual(selectedIndex);
	}

	// ===== 几何 =====
	inline function cxOf(index:Int):Float
	{
		return x + index * SWATCH_STEP;
	}

	/** 整行总宽（首块左缘 → 末块右缘），供宿主居中或对齐用 */
	public function totalWidth():Float
	{
		if (colors.length < 1) return 0;
		return SWATCH_DIAMETER + (colors.length - 1) * SWATCH_STEP;
	}

	/**
	 * 整行显隐。隐藏时必须连**选中环与悬停态一起复位**：
	 * 否则重新显示时会出现「鼠标早已不在上面、环却亮着」的残留状态。
	 * 隐藏时也一并取消交互（防止不可见区域仍吃点击）。
	 */
	public function setVisible(v:Bool):Void
	{
		if (destroyed) return;
		isVisible = v;
		for (spr in sprites) spr.visible = v;
		if (!v)
		{
			hoveredIndex = -1;
			pressedVisual = false;
			for (c in circles) { c.scale.set(1, 1); }
		}
		else
		{
			setSelectedVisual(selectedIndex); // 重新显示时恢复选中环
		}
	}

	/** 屏幕坐标 → 色块索引（未命中返回 -1）。用圆形距离判定，与视觉一致 */
	public function hitTest(mx:Float, my:Float):Int
	{
		if (!interactive || destroyed) return -1;
		var r:Float = SWATCH_DIAMETER / 2 + SWATCH_HIT_PAD;
		for (i in 0...colors.length)
		{
			var dx:Float = mx - cxOf(i);
			var dy:Float = my - y;
			if (dx * dx + dy * dy <= r * r) return i;
		}
		return -1;
	}

	// ===== 每帧演出（仅视觉；点击语义由宿主决定）=====
	/**
	 * @param mx            鼠标/触控 X（屏幕坐标）
	 * @param my            鼠标/触控 Y（屏幕坐标）
	 * @param clickPressed  宿主判定好的"本帧点了"（桌面 justPressed / 移动端 tap 抬起且未拖动）
	 */
	public function update(mx:Float, my:Float, clickPressed:Bool):Void
	{
		if (destroyed) return;

		// 悬停：只放大预览，**不改变选中**
		var h:Int = hitTest(mx, my);
		if (h != hoveredIndex)
		{
			hoveredIndex = h;
			applySwatchScale(h);
		}

		// 按压即时反馈（≤100ms）；真实按下即缩，松开复位（拖走取消也复位）
		var isDown:Bool = interactive && FlxG.mouse.pressed && hoveredIndex >= 0;
		if (isDown != pressedVisual)
		{
			pressedVisual = isDown;
			applySwatchScale(hoveredIndex);
		}

		if (clickPressed && hoveredIndex >= 0)
		{
			var idx:Int = hoveredIndex;
			if (onClick != null) onClick(idx);
		}
	}

	// ===== 状态 =====
	function set_selectedIndex(v:Int):Int
	{
		if (v < 0 || v >= colors.length) v = 0;
		selectedIndex = v;
		setSelectedVisual(v);
		return v;
	}

	function set_keyboardFocus(v:Bool):Bool
	{
		keyboardFocus = v;
		setSelectedVisual(selectedIndex);
		return v;
	}

	/**
	 * 选中环 + 焦点环的统一刷新。
	 * 环是**唯一**的"当前是哪一档"指示：始终可见（即使焦点不在色块上），
	 * 键盘焦点时用主题色环、非焦点时用白环 —— 状态不靠颜色单独表达（skill 要求）。
	 */
	function setSelectedVisual(index:Int):Void
	{
		// ⚠ 整行隐藏时**不得点亮任何环**：本方法会被 `keyboardFocus`（宿主切焦点）与
		// DesignTokens 主题监听（脚本/设置改主题色）回调触发，那些时机与"整行是否显示"无关，
		// 若不看 isVisible，就会在别的分区/别的选项行上留下一个孤零零的白圈（2026-09-16 用户实测截图）。
		var rowVisible:Bool = isVisible;
		for (i in 0...rings.length)
		{
			var ring:FlxSprite = rings[i];
			var on:Bool = rowVisible && (i == index);
			ring.visible = on;
			if (on) ring.color = keyboardFocus ? DesignTokens.primary : FlxColor.WHITE;
		}
	}

	function applySwatchScale(index:Int):Void
	{
		if (index < 0 || index >= circles.length) return;
		var target:Float = 1.0;
		if (index == hoveredIndex) target = pressedVisual ? 0.94 : 1.08; // 按压缩 / 悬停放大

		// 只缩放色块本体：圆环表示"选中"，不该跟着鼠标缩放而漂移
		var tw:FlxTween = scaleTweens.get(index);
		if (tw != null) tw.cancel(); // 复用的 tween 先 cancel（selectorTween 同款模式），避免动画叠加
		tw = FlxTween.tween(circles[index], {scale: {x: target, y: target}}, 0.1, {ease: FlxEase.quadOut});
		scaleTweens.set(index, tw);
	}

	// ===== 主题变更同步（脚本 setThemeColor 后选中态立即跟上）=====
	/**
	 * 注册主题变更监听：脚本临时改色（不写存档）时，色块选中环也要指向真正生效的那一档，
	 * 否则设置页会"显示得不对"。
	 * 宿主**必须**在 destroy 时调用 unregisterThemeListener()。
	 */
	public function registerThemeListener():Void
	{
		if (themeListener != null) return;
		themeListener = function() {
			if (destroyed) return;
			selectedIndex = DesignTokens.themeIndex;
			setSelectedVisual(selectedIndex);
		};
		DesignTokens.addThemeListener(themeListener);
	}

	public function unregisterThemeListener():Void
	{
		if (themeListener == null) return;
		DesignTokens.removeThemeListener(themeListener);
		themeListener = null;
	}

	public function destroy():Void
	{
		if (destroyed) return;
		destroyed = true;
		unregisterThemeListener();
		for (tw in tweens)
		{
			if (tw != null) tw.cancel();
		}
		tweens = [];
		glows = [];
		circles = [];
		rings = [];
		sprites = [];
		onClick = null;
	}
}
