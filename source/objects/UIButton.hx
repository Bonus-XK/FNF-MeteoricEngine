package objects;

import flixel.util.FlxSpriteUtil;
import flixel.tweens.FlxTween;

/**
 * 系统域按钮（MD3 语义：filled / tonal / text）—— 更新界面等系统域弹层复用。
 *
 * 设计依据 skills/meteoric-design：
 *  - 圆角 14（按钮档）；1.5px 描边；填充走令牌，主题色切换即时跟随（禁止 static final 缓存）。
 *  - 三态表达用**叠加层**而非实体色块：hover 叠 0x18 白、pressed 叠 0x30 白（skill 明列）。
 *  - 动效：hover/按下 ≤100ms quadOut，复用的 tween 先 cancel；按下缩放 0.97。
 *  - 触控目标 ≥56 逻辑 px：调用方传 h ≥ 56。
 *  - 三套输入：鼠标/触控（over + setHovered + 宿主 justPressed）、键盘（setFocused + 宿主 ACCEPT）。
 *
 * 注意：本类**不**自己监听输入（与 BackButton 一致），由宿主界面统一分发 ——
 * 否则多个按钮各自读全局输入会重复触发。
 *
 * 重绘约定（2026-09-12 修正）：
 *  graphic **只在构造时建一次**，且必须显式 `unique = true`；状态变化只在原地
 *  「清空 pixels → 重画 → dirty = true」。
 *
 * ⚠ 曾经的写法是状态变化时 `makeGraphic` "重建" —— 那是错的，而且是「悬浮两个都亮 / 移开不灭」的根因：
 *  flixel 的 `makeGraphic(width, height, color)` 对 (宽,高,色) 相同的调用会命中位图缓存
 *  （FlxG.bitmap），返回**同一张 BitmapData**。于是：
 *   ① 同尺寸的多个按钮共图 → 悬停 A 的状态层同时画到 B 上（「悬浮串亮」）；
 *   ② 尺寸没变时它**不清旧像素** → 移开鼠标后白层永远留在位图里，A 一直亮（「粘住不灭」）。
 *  本仓库同类坑此前已在 ChartingPanel / ChartWidgets 用 `makeGraphic(..., true)` 修过
 *  （CHANGELOG：makeGraphic unique=true 根除「悬浮串亮」）。
 *  参考实现：objects/UIInputBox.redraw、states/editors/ChartWidgets.redraw。
 */
class UIButton extends FlxSpriteGroup
{
	public static final VARIANT_FILLED:String = 'filled';
	public static final VARIANT_TONAL:String = 'tonal';
	public static final VARIANT_TEXT:String = 'text';

	public static final RADIUS:Float = 14;

	public var onClick:Void->Void;
	public var label:FlxText;

	var bg:FlxSprite;
	var overlay:FlxSprite;
	var variant:String;
	var btnW:Float;
	var btnH:Float;
	var enabled:Bool = true;
	var hovered:Bool = false;
	var pressed:Bool = false;
	var scaleTween:FlxTween;
	// 悬停唤醒：界面打开时鼠标恰好停在按钮上不应立即高亮（与 BackButton 同款语义）
	var awake:Bool = false;
	var lastX:Float = 0;
	var lastY:Float = 0;

	/**
	 * @param variant 语义：'filled' / 'tonal' / 'text'。
	 *   默认值必须是**编译期常量**，不能写 `VARIANT_TONAL`（static final 不是常量表达式，
	 *   Haxe 会报 "Parameter default value should be constant" —— 与 makePanel 的 panelFill 同类坑）。
	 *   调用点可以照常传 `UIButton.VARIANT_FILLED`，那是运行期实参，不受此限制。
	 * @param labelSize 标签字号，默认 26（历史值，宽按钮足够）。**窄按钮必须显式传小字号**：
	 *   本仓库 `FlxText.set_fieldWidth()` 在 `fieldWidth > 0` 时会强制 `wordWrap = true`
	 *   （source/flixel/text/FlxText.hx:521-540），26px 下 96px 宽只放得下 3 个汉字 →
	 *   "保存生成" 折成两行、"预览 Lua" 被截（Lua 图形化编辑器 2026-09-15 实测）。
	 */
	public function new(x:Float, y:Float, w:Float, h:Float, text:String, variant:String = 'tonal', ?cb:Void->Void, labelSize:Int = 26)
	{
		super(x, y);
		this.variant = variant;
		if (this.variant == null || this.variant.length < 1) this.variant = VARIANT_TONAL;
		onClick = cb;
		btnW = w;
		btnH = h;

		// ⚠ 这里的两处 makeGraphic 必须带 unique = true（见类注释）：不加就会两个按钮共用一张
		// 缓存位图 —— 悬停 A 时 A 和 B 同时亮，且移开鼠标后仍不灭。
		bg = new FlxSprite(0, 0);
		bg.antialiasing = true;
		bg.scrollFactor.set();
		bg.makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		add(bg);

		overlay = new FlxSprite(0, 0);
		overlay.antialiasing = true;
		overlay.alpha = 0;
		overlay.scrollFactor.set();
		overlay.makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		add(overlay);

		// 字号：< 10 视为误传，回退历史默认 26（避免出现 0 号字这种"按钮还在、字没了"的静默故障）
		var ls:Int = (labelSize < 10) ? 26 : labelSize;
		label = new FlxText(0, 0, Std.int(w), text, ls);
		label.setFormat(Paths.font('future.ttf'), ls, FlxColor.WHITE, CENTER);
		// 标签永远单行：宽度不够时宁可横向溢出（调用方按文案宽度定按钮宽），
		// 也不允许折行后第二行掉到按钮/界面安全区之外（见 labelSize 注释的实测缺陷）。
		label.wordWrap = false;
		label.textField.height = Std.int(h);
		label.y = Math.max(0, (h - label.textField.textHeight) / 2);
		label.scrollFactor.set();
		add(label);

		scrollFactor.set();
		lastX = FlxG.mouse.screenX;
		lastY = FlxG.mouse.screenY;
		refreshColors();
	}

	/** 按语义 + 当前主题色重建底/叠加层/文字色。主题变化时宿主可再调一次。 */
	public function refreshColors():Void
	{
		var primary:Int = DesignTokens.primary;
		var fill:Int = FlxColor.TRANSPARENT;
		var border:Int = FlxColor.TRANSPARENT;
		var textColor:Int = FlxColor.WHITE;

		switch (variant)
		{
			case VARIANT_FILLED:
				// 主题色填充 + **白字**（用户指定）。
				// 注意：浅色主题（青/金/绿…）下 primary 很亮，白字对比会不足，
				// 所以填充用主题色**压暗**后的版本（保持是当前主题色，同时让白字站得住）。
				fill = FlxColor.interpolate(FlxColor.BLACK, primary, 0.55);
				border = primary;
				textColor = FlxColor.WHITE;
			case VARIANT_TEXT:
				textColor = DesignTokens.secondary;
			default: // tonal
				fill = DesignTokens.panelFill;
				border = DesignTokens.panelOutline;
				textColor = primary;
		}

		// 原地重绘（先清后画）。**不要**再用 makeGraphic "重建"：尺寸不变时它返回位图缓存里的
		// 同一张 BitmapData —— 既清不掉旧像素（悬停层永久残留 → 移开鼠标还亮），
		// 又会让同尺寸按钮共图（悬停 A 时 B 也亮）。
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		if (fill != FlxColor.TRANSPARENT)
			FlxSpriteUtil.drawRoundRect(bg, 0, 0, btnW, btnH, RADIUS, RADIUS, fill);
		if (border != FlxColor.TRANSPARENT)
			FlxSpriteUtil.drawRoundRect(bg, 1, 1, btnW - 2, btnH - 2, RADIUS, RADIUS, FlxColor.TRANSPARENT,
				{color: border, thickness: 1.5});
		bg.dirty = true;

		overlay.pixels.fillRect(overlay.pixels.rect, FlxColor.TRANSPARENT);
		var stateLayer:Int = pressed ? 0x30FFFFFF : (hovered ? 0x18FFFFFF : FlxColor.TRANSPARENT);
		if (stateLayer != FlxColor.TRANSPARENT)
			FlxSpriteUtil.drawRoundRect(overlay, 0, 0, btnW, btnH, RADIUS, RADIUS, stateLayer);
		overlay.alpha = (stateLayer == FlxColor.TRANSPARENT) ? 0 : 1;
		overlay.dirty = true;

		label.color = textColor;
	}

	public function setEnabled(v:Bool):Void
	{
		enabled = v;
		alpha = v ? 1 : 0.45;
	}

	/** 命中判定（逻辑坐标）。 */
	public function over(mx:Float, my:Float):Bool
	{
		if (!visible || !enabled) return false;
		return mx >= x && mx <= x + btnW && my >= y && my <= y + btnH;
	}

	/** 悬停：要求鼠标先明显移动过，避免界面一打开就"亮着"。 */
	public function setHovered(mx:Float, my:Float):Void
	{
		if (!awake)
		{
			var dx:Float = mx - lastX;
			var dy:Float = my - lastY;
			if (dx * dx + dy * dy < 100) return;
			awake = true;
			lastX = mx;
			lastY = my;
		}
		setFocused(over(mx, my));
	}

	/** 高亮态（鼠标悬停与键盘焦点共用同一套视觉）。 */
	public function setFocused(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		refreshColors();
	}

	/** 按下：叠 0x30 白 + 缩放 0.97 / 100ms quadOut（复用的 tween 先 cancel）。 */
	public function setPressed(v:Bool):Void
	{
		if (pressed == v) return;
		pressed = v;
		refreshColors();
		if (scaleTween != null)
		{
			scaleTween.cancel();
			scaleTween = null;
		}
		var s:Float = v ? 0.97 : 1;
		scaleTween = FlxTween.tween(this, {'scale.x': s, 'scale.y': s}, 0.1, {
			ease: FlxEase.quadOut,
			onComplete: function(_) scaleTween = null
		});
	}

	public function click():Void
	{
		if (!enabled) return;
		if (onClick != null) onClick();
	}
}
