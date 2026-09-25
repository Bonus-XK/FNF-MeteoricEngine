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
		// ⚠ unique = true：`makeGraphic(..., unique:false)` 会命中"同尺寸 + 同色"缓存里的**同一张**
		// BitmapData，主题变更时的原地重绘（rethemePanel）会把别的精灵像素一起改掉
		// （同一踩坑记录见 objects/ToggleSwitch 类注释第 1 条）。本 UI 的面板数量个位数，代价可忽略。
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	/**
	 * 用**当前令牌**原地重绘一块由 makePanel 画出来的面板 —— 主题色变更时让**已经创建**的元素立刻换色。
	 *
	 * 纪律（meteoric-system）：主题色是**低频事件**，只在变更时重画一次；禁止放进 update/逐帧路径。
	 * 安全性：销毁后的精灵（alive=false）或没有 pixels 的精灵直接跳过 —— 静态监听表若因宿主漏摘留下
	 * 僵尸回调，这里也不会踩空（meteoric-system 的监听者契约仍要求宿主 destroy 时摘除）。
	 *
	 * @param fill/border 传 null = 跟随令牌（与 makePanel 的默认值同语义：面板底 + 白 27% 描边）
	 */
	public static function rethemePanel(spr:FlxSprite, w:Float, h:Float, ?radius:Float = 22, ?fill:Null<Int> = null, ?border:Null<Int> = null):Void
	{
		if (spr == null || !spr.alive || spr.pixels == null) return;
		// 注意：静态平台上 `Null<Int>` 不能经三元表达式收窄成 Int（Haxe 会报
		// "null can't be used as basic type Int"），必须与 makePanel 同款用 if 赋值收窄。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		spr.pixels.fillRect(spr.pixels.rect, FlxColor.TRANSPARENT); // 清底：不 clean 会把旧主题残留叠在里面
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
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
