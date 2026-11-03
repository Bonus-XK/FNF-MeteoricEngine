package backend;

/**
 * ms 加权准确率（ClientPrefs.data.msWeightedAccuracy）：
 * 把离散锚点权重（sick=1 / good=0.67 / bad=0.34 / shit=0）换成按实际毫秒偏差
 * 在判定档位边界之间连续插值的分段线性曲线。
 *
 * 曲线（d = 归一化 |偏差|，与现行判定器同源）：
 *   d ≤ sickW          → 1.0
 *   sickW < d ≤ goodW  → 1.0   → 0.67 线性
 *   goodW < d ≤ badW   → 0.67  → 0.34 线性
 *   badW  < d ≤ 外沿    → 0.34  → 0    线性
 *   d > 外沿 / miss    → 0
 * 每段右端点 = 旧锚点权重：段边界处新旧口径数值相等，仅档位内部「贴边 vs 正中」产生区分。
 *
 * 偏差域与窗口必须和判定器严格同源（由调用方保证 d 的口径一致）：
 *   PE 判定：d = |strum−pos+offset| / playbackRate（Conductor.judgeNote 的输入域），
 *            锚点窗口 = ClientPrefs 三窗口（原始 ms），外沿 = safeZoneOffset/playbackRate（shit 档概念值）。
 *   KE 判定：d = |strum−pos|（judgeRatingKE 的输入域，不含 offset），
 *            锚点窗口 = 45/90/135 × timeScale（timeScale = Conductor.safeZoneOffset/166），外沿 = safeZoneOffset。
 *
 * 开关关闭或无有效偏差（normDiff < 0，即旧回放文件无 ms 字段）→ 返回旧锚点 ratingMod，
 * 数值与改动前完全一致（旧回放文件由此精确复现原局准确率）。
 */
class AccuracyDomain
{
	// 插值锚点权重，与 Rating.loadDefault 里 good/bad 档的 ratingMod 同源。
	public static inline var GOOD_ANCHOR:Float = 0.67;
	public static inline var BAD_ANCHOR:Float = 0.34;

	/**
	 * 单次命中的 accuracy 权重。
	 * @param playbackRate 调用局的回放速率（PE 外沿换算用；主局 PlayState / 编辑器试玩各自传入）
	 * @param normDiff     归一化 |ms 偏差|；< 0（含 NaN）= 无有效偏差 → 回退旧锚点权重
	 * @param daRating     本次命中的判定档（开关关/无偏差时直接取其 ratingMod）
	 * @param keMode       是否 KE 判定域（调用方与判定分支同源传入；编辑器试玩恒 false）
	 */
	public static function hitWeight(playbackRate:Float, normDiff:Float, daRating:Rating, keMode:Bool):Float
	{
		if (!ClientPrefs.data.msWeightedAccuracy || !(normDiff >= 0))
			return daRating.ratingMod;

		var sickW:Float;
		var goodW:Float;
		var badW:Float;
		var outerW:Float;
		if (keMode)
		{
			// KE：judgeRatingKE 的固定边界 × timeScale；timeScale = safeZoneOffset/166
			var ts:Float = Conductor.safeZoneOffset / 166;
			sickW = 45 * ts;
			goodW = 90 * ts;
			badW = 135 * ts;
			outerW = Conductor.safeZoneOffset; // 166 × timeScale，与 shit 档概念外沿一致
		}
		else
		{
			// PE：Conductor.judgeNote 的窗口即 ClientPrefs 原始 ms（d 已除 playbackRate）
			sickW = ClientPrefs.data.sickWindow;
			goodW = ClientPrefs.data.goodWindow;
			badW = ClientPrefs.data.badWindow;
			outerW = Conductor.safeZoneOffset / playbackRate; // shit 档概念外沿（safeFrames=10 时 ≈166.67）
		}

		if (normDiff <= sickW) return 1.0;
		if (normDiff <= goodW) return seg(sickW, goodW, 1.0, GOOD_ANCHOR, normDiff);
		if (normDiff <= badW) return seg(goodW, badW, GOOD_ANCHOR, BAD_ANCHOR, normDiff);
		if (normDiff <= outerW) return seg(badW, outerW, BAD_ANCHOR, 0.0, normDiff);
		return 0.0;
	}

	/** [a,b] 段内 wa→wb 线性插值；段宽≤0（窗口被设相等/倒挂）直接取右锚点防除零。 */
	static function seg(a:Float, b:Float, wa:Float, wb:Float, d:Float):Float
	{
		var span:Float = b - a;
		if (!(span > 0)) return wb;
		return wa + (wb - wa) * ((d - a) / span);
	}
}
