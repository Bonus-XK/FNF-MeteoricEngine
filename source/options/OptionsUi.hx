package options;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

/**
 * 「单界面设置」（OptionsState 宿主 + SettingsRail 分区栏 + OptionsPane 内容区）共用的绘制工具。
 *
 * 为什么单独抽一个类：
 *  仓库里 `makePanel` 有 20+ 份同名复制（历史遗留），**新代码不再复制第 22 份布局常量**；
 *  本类只服务新增的单界面设置，存量 BaseOptionsMenu / Pause / Results 的副本不动（它们各自已验证）。
 *
 * 硬性契约（meteoric-design「面板与高亮令牌」）：
 *  - 面板填充/描边一律走令牌，禁止写字面量 0xCC161622 / 0x45FFFFFF；
 *  - 参数默认值必须是**编译期常量**（Haxe 拒绝 `?fill:Int = DesignTokens.panelFill`），
 *    因此默认传 null、在函数体内解析 —— 顺带保证取到的是**当前主题**的值，而不是类加载时的静态快照。
 */
class OptionsUi
{
	/** 圆角磨砂玻璃面板：填充 + 1.5px 描边，一次绘制（禁止逐帧重建）。 */
	public static function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 22, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	/** 次级元素（嵌在面板内的深色小块）：保留半透明深色，透出父面板的玻璃层次。 */
	public static function makeInset(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 10, ?fill:Int = 0x66161622, ?border:Null<Int> = 0x8CFFFFFF):FlxSprite
	{
		return makePanel(x, y, w, h, radius, fill, border);
	}

	/** 主题派生令牌（运行时读取；禁止 static final 缓存，否则主题切换后冻结）。 */
	public static function highlight():FlxColor return DesignTokens.rowHighlight;
	public static function hover():FlxColor return DesignTokens.rowHover;
}
