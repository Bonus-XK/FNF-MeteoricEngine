package flixel.system.scaleModes;

import backend.ClientPrefs;
import flixel.FlxG;

/**
 * 【Meteoric 宽屏适配】按窗口比例自适应逻辑分辨率的缩放模式（宽窄两个方向都铺满）。
 *
 * 参考 Kathy Engine（Psych Mobile 分支）的 PlayStateScaleMode / MobileScaleMode 思路，
 * 并按 Meteoric 需求扩展到窄窗口：
 *   - 窗口比 16:9 更宽（宽屏手机 / 超宽屏）：高度锁 720，宽度 = 720 × 窗口比例，
 *     夹取 [1280, 1600]（即 16:9 ~ 20:9）→ 水平方向多显示内容；
 *   - 窗口比 16:9 更窄（MacBook 内屏 / 竖屏）：宽度锁 1280，高度 = 1280 ÷ 窗口比例，
 *     夹取 [720, 1440]（最高 2×720）→ 垂直方向多显示内容；
 *   - 比例在上述区间内 → 精确铺满、无黑边、不变形；
 *   - 超出夹取上限（比 20:9 更宽 / 比 1280:1440 更方的窗口）→ 回退等比缩放 + 居中黑边。
 *
 * 以 FlxG.width/height 为锚的 HUD/轨道/菜单布局自动展开；模组脚本读 FlxG.width/
 * FlxG.height 的事件/遮罩自动盖满全屏。
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
	/** 逻辑宽度下限 = 16:9 基准宽（窄窗方向锁这个宽向下延伸高度） */
	public static inline var MIN_WIDTH:Int = 1280;
	/** 逻辑宽度上限 = 20:9（覆盖主流全面屏手机；更宽的显示器回退等比黑边） */
	public static inline var MAX_WIDTH:Int = 1600;
	/** 逻辑高度基准 = 16:9 基准高（宽窗方向锁这个高向两侧扩展宽度） */
	public static inline var BASE_HEIGHT:Int = 720;
	/** 逻辑高度上限 = 2 × 720（窄窗方向；更方/竖屏的窗口回退等比黑边） */
	public static inline var MAX_HEIGHT:Int = 1440;

	override public function onMeasure(Width:Int, Height:Int):Void
	{
		if (Width <= 0) Width = MIN_WIDTH;
		if (Height <= 0) Height = BASE_HEIGHT;

		var aspect:Float = Width / Height;
		var baseRatio:Float = MIN_WIDTH / BASE_HEIGHT; // 16:9 分界

		var gameW:Float;
		var gameH:Float;
		if (aspect >= baseRatio)
		{
			// 宽窗：高度锁 720，宽度按窗口比例扩展，上限 20:9
			gameH = BASE_HEIGHT;
			gameW = BASE_HEIGHT * aspect;
			if (gameW < MIN_WIDTH) gameW = MIN_WIDTH;
			else if (gameW > MAX_WIDTH) gameW = MAX_WIDTH;
		}
		else
		{
			// 窄窗：宽度锁 1280，高度按窗口比例向下延伸，上限 2×720
			gameW = MIN_WIDTH;
			gameH = MIN_WIDTH / aspect;
			if (gameH < BASE_HEIGHT) gameH = BASE_HEIGHT;
			else if (gameH > MAX_HEIGHT) gameH = MAX_HEIGHT;
		}

		// ⚠ 不要调 super.onMeasure()：flixel 的 BaseScaleMode.onMeasure 会先把
		// FlxG.width/height 重置回 initialWidth/initialHeight（恒定值），动态尺寸即刻失效。
		// 这里按 Kathy PlayStateScaleMode 同款思路自行完成四步测量。
		FlxG.width = Math.round(gameW);
		FlxG.height = Math.round(gameH);

		updateGameSize(Width, Height);
		updateDeviceSize(Width, Height);
		updateScaleOffset();
		updateGamePosition();
	}

	/** 按【动态后的】游戏比例等比适配窗口（Kathy PlayStateScaleMode 同款）：
	 *  比例在夹取区间内时 gameRatio == windowRatio → gameSize == 窗口尺寸（精确铺满）；
	 *  超出区间（宽或高被夹取）→ 居中留黑边，画面始终不变形。 */
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
