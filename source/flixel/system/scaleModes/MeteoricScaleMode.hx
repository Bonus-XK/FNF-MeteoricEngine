package flixel.system.scaleModes;

import backend.ClientPrefs;
import flixel.FlxG;

/**
 * 【Meteoric 宽屏适配】高度锁定 720、宽度随窗口比例自适应的缩放模式。
 *
 * 参考 Kathy Engine（Psych Mobile 分支）的 PlayStateScaleMode / MobileScaleMode 思路：
 *   - 高度恒为 720（游戏设计基准高度），不随窗口增减；
 *   - 宽度 = 720 × 窗口宽高比，夹取在 [MIN_WIDTH, MAX_WIDTH]（即 16:9 ~ 20:9）；
 *   - 窗口比例在区间内 → 精确铺满、无黑边、不变形，水平方向多显示游戏内容
 *     （HUD/轨道以 FlxG.width 为锚的布局自动展开，模组脚本读 FlxG.width 亦自动盖满）；
 *   - 窗口比 16:9 更窄（4:3 / 竖屏）→ 保持 1280 宽等比缩放，上下留黑边；
 *   - 窗口比 20:9 更宽（21:9 / 32:9 超宽屏）→ 保持 1600 宽等比缩放，左右留黑边。
 *
 * 由 ClientPrefs.data.wideScreen 控制（设置 → 图像 →「宽屏适配」，默认关闭）：
 * 默认关闭时引擎保持 flixel 默认 RatioScaleMode（等比 + 黑边）——零行为变化。
 * 开关切换/存档加载后经 apply() 安装或卸载本模式并立即重测量；
 * 已打开界面的布局按「新打开的界面生效」语义处理（不强制重排）。
 *
 * ⚠ 必须放在 flixel.system.scaleModes 包内：FlxG.width/height 是
 * `@:allow(flixel.system.scaleModes)` 的只读字段，包外无法在 onMeasure 里写动态宽度。
 */
class MeteoricScaleMode extends BaseScaleMode
{
	/** 逻辑宽度下限 = 16:9（游戏设计基准宽度；更窄的窗口不缩窄游戏内容） */
	public static inline var MIN_WIDTH:Int = 1280;
	/** 逻辑宽度上限 = 20:9（覆盖主流全面屏手机；更宽的显示器回退等比黑边） */
	public static inline var MAX_WIDTH:Int = 1600;
	/** 锁定的逻辑高度（游戏设计基准） */
	public static inline var LOCKED_HEIGHT:Int = 720;

	override public function onMeasure(Width:Int, Height:Int):Void
	{
		if (Width <= 0) Width = MIN_WIDTH;
		if (Height <= 0) Height = LOCKED_HEIGHT;

		// 逻辑尺寸：高度锁死，宽度按窗口比例推算后夹取
		var gameW:Float = LOCKED_HEIGHT * (Width / Height);
		if (gameW < MIN_WIDTH) gameW = MIN_WIDTH;
		else if (gameW > MAX_WIDTH) gameW = MAX_WIDTH;

		// ⚠ 不要调 super.onMeasure()：flixel 的 BaseScaleMode.onMeasure 会先把
		// FlxG.width/height 重置回 initialWidth/initialHeight（恒定值），动态宽度即刻失效。
		// 这里按 Kathy PlayStateScaleMode 同款自行完成四步测量。
		FlxG.width = Math.round(gameW);
		FlxG.height = LOCKED_HEIGHT;

		updateGameSize(Width, Height);
		updateDeviceSize(Width, Height);
		updateScaleOffset();
		updateGamePosition();
	}

	/** 按【动态后的】游戏比例等比适配窗口（Kathy PlayStateScaleMode 同款）：
	 *  比例在夹取区间内时 gameRatio == windowRatio → gameSize == 窗口尺寸（精确铺满）；
	 *  超出区间（宽度被夹取）→ 居中留黑边，画面始终不变形。 */
	override function updateGameSize(Width:Int, Height:Int):Void
	{
		var gameRatio:Float = FlxG.width / FlxG.height;
		var windowRatio:Float = Width / Height;

		if (windowRatio < gameRatio)
		{
			// 窗口相对更「窄高」→ 以宽度贴满，上下留黑边
			gameSize.x = Width;
			gameSize.y = Math.floor(Width / gameRatio);
		}
		else
		{
			// 窗口相对更「宽矮」→ 以高度贴满，左右留黑边
			gameSize.y = Height;
			gameSize.x = Math.floor(Height * gameRatio);
		}
	}

	/**
	 * 按当前设置（ClientPrefs.data.wideScreen）安装/卸载宽屏缩放模式。
	 * flixel 的 FlxG.scaleMode setter 内部会触发一次完整重测量（game.onResize）。
	 * @return FlxG.width 是否因本次切换而变化（变化了的已打开界面需要重建布局，
	 *         调用方据此决定是否 resetState —— 见 TitleState 的防循环单次重建）。
	 */
	public static function apply():Bool
	{
		if (FlxG.game == null) return false; // FlxG 尚未初始化，等 TitleState.loadPrefs 后再应用

		var before:Int = FlxG.width;
		if (ClientPrefs.data.wideScreen)
		{
			if (!(FlxG.scaleMode is MeteoricScaleMode))
				FlxG.scaleMode = new MeteoricScaleMode();
		}
		else
		{
			// 卸载 = 恢复 flixel 默认 RatioScaleMode（等比 + 黑边），与本功能落地前的行为一致
			if (FlxG.scaleMode is MeteoricScaleMode)
				FlxG.scaleMode = new RatioScaleMode();
		}
		return FlxG.width != before;
	}
}
