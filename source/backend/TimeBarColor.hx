package backend;

import flixel.util.FlxColor;
import objects.Character;

/**
 * 时间条填充色的**唯一取色点**。
 *
 * 背景（为什么要有这个类）：
 * 时间条有两种样式（`newTimeBarStyle` 贴图/新版圆角），历史上两条分支各写了一套取色逻辑，
 * 结果新样式**硬编码跟随对手图标颜色**、并且设置项的说明文字把这件事写成了特性
 * （「新时间条样式不受此开关影响」），导致「新版样式不跟随对方」根本无法设置（2026-09-11 实测 bug）。
 *
 * 统一语义（两种样式一致）：
 *  - `timeBarOpponentColors` 开启 且对手存在 → 对手血量条颜色；过暗/过亮时按样式兜底
 *  - 否则 → **主题色** `DesignTokens.primary`（落实「主题色覆盖全部 UI」：默认不再写死青色）
 */
class TimeBarColor
{
	/** 对手颜色过暗阈值（RGB 分量之和）：低于此值看不清，改用兜底色 */
	public static inline var TOO_DARK:Int = 120;

	/** 对手颜色过亮阈值：仅贴图样式使用（新版圆角样式用深色对比，亮色反而不刺眼） */
	public static inline var TOO_BRIGHT:Int = 660;

	/**
	 * 解析时间条填充色。
	 * @param opponent       对方角色（可为 null；为 null 时视为未开启跟随）
	 * @param modernStyle    true = 新版黑色圆角样式；false = 贴图样式
	 * @param useOpponent    是否开启「时间条颜色跟随对方」
	 */
	public static function resolveFill(?opponent:Character, modernStyle:Bool = false, useOpponent:Bool = false):FlxColor
	{
		if (useOpponent && opponent != null)
		{
			var color:FlxColor = FlxColor.fromRGB(
				opponent.healthColorArray[0],
				opponent.healthColorArray[1],
				opponent.healthColorArray[2]);
			var sum:Int = color.red + color.green + color.blue;

			// 过暗：两种样式都兜底（贴图样式历史行为；新版样式原也如此）
			if (sum < TOO_DARK) return fallback(modernStyle);
			// 过亮：仅贴图样式兜底（保持历史行为，不改变已有观感）
			if (!modernStyle && sum > TOO_BRIGHT) return fallback(modernStyle);
			return color;
		}

		// 未跟随：使用主题色（默认主题 = 青，与历史字面量 0xFF00FFFF 同色系）
		return DesignTokens.primary;
	}

	/** 兜底色：新版样式用主题色；贴图样式保留历史上的青色（0.6.3 兼容观感） */
	static function fallback(modernStyle:Bool):FlxColor
	{
		return modernStyle ? DesignTokens.primary : 0xFF00FFFF;
	}
}
