package backend;

import states.PlayState;

/** 一次结算/一帧的评分结果（模块级 typedef —— hxcpp 不接受 class 内 typedef）。 */
typedef PhigrosResult = {
	/** 准确率，0~1（显示时 ×100 加 %）。 */
	var accuracy:Float;
	/** 两段式分数，0~1000000。 */
	var score:Int;
	/** 评级符号：φ / V / S / A / B / C / F。 */
	var rank:String;
	/** 该评级对应的颜色（ARGB）。 */
	var color:Int;
	/** 是否为特殊评级（φ / V），覆盖分数评级。 */
	var special:Bool;
	/** 是否通关（C 及以上 = 通过；φ/V 必通过）。 */
	var cleared:Bool;
	/** 原始判定计数（Phigros 结算页同款展示；同时是排查口径问题的依据）。 */
	var perfect:Int;
	var good:Int;
	var bad:Int;
	var miss:Int;
	/** 最大连击 / 谱面音符总数（连击分的两个输入）。 */
	var maxCombo:Int;
	var totalNotes:Int;
}

/**
 * Phigros 式**评级**（**可选**，开关：设置 → 判定 → 「Phigros 式评级」，默认关）。
 *
 * ## 范围：只换评级，不换分数、不换判定
 *
 * 本模块**只产出评级符号**（φ / V / S / A / B / C / F）与配套读数。
 * 引擎的分数与判定机制**完全不动**：
 *  - `songScore` 仍按引擎原口径累加（`Rating.hx` 的 sick=350 / marvelous=500 /
 *    good=200 / bad=100 / shit=50，Miss 扣 10），HUD、高分榜、回放、暂停、结算、
 *    脚本 API 全部照旧读它；
 *  - 判定窗口、判定名、`ratingMod` 一律不变。
 *
 * 换掉的只有**评级这一层**：原来用 `ratingPercent`（命中权重和 ÷ 已判定数）套
 * `PlayState.ratingStuff` 的 PF/SHDC/F/E/D/C/B/A/A./A:/AA/AAA 档位；开启后改用
 * Phigros 的 ACC 与 φ/V/S/A/B/C/F 档位。
 *
 * ## 公式（多来源交叉核对：Phigros Wiki / NamuWiki / Baiduwiki / TapTap 攻略一致）
 *
 * ```
 * ACC  = (Perfect + Good × 0.65) / 总音符数 × 100%
 * 连击分 = (最大连击 / 总音符数) × 100000
 * 评级用分 = 900000 × ACC + 连击分          ← 仅用于定档，不显示、不存档
 * ```
 *
 * `ACC` 与已有的 `ratingPercent` 不是一回事：后者是 `totalNotesHit / totalPlayed`
 * （权重 `ratingMod`：sick=1 / good=0.67 / bad=0.34 / shit=0，分母是**已判定数**）；
 * Phigros 的 ACC 分母是**谱面音符总数**，且 Good 系数是 0.65 而非 0.67。
 *
 * 注意 ACC 也**不等于** `totalNotesHit`——后者是累计的浮点权重和，不是比例。
 *
 * ## 评级档位
 *
 * Phigros 的档位定义在**分数**上（`900000×ACC + 连击分`，满分 100 万）。
 * 本实现在**全连**假设下把阈值折算成 ACC 阈值：
 *
 * | 评级 | Phigros 分数 | 折算 ACC 阈值 |
 * |---|---|---|
 * | φ (Phi) | 1000000（满分） | ACC = 100% |
 * | 蓝 V | 全连（无 Bad/Miss） | 与分数无关 |
 * | 白 V | ≥ 960000 | ≥ 95.56% |
 * | S | ≥ 920000 | ≥ 91.11% |
 * | A | ≥ 880000 | ≥ 86.67% |
 * | B | ≥ 820000 | ≥ 80.00% |
 * | C | ≥ 700000 | ≥ 66.67% |
 * | F (False) | < 700000 | < 66.67% |
 *
 * V 是**特殊评级**，覆盖除 φ 以外的全部分数评级（Phigros 原意：FC 时的独立标记，
 * 与分数高低无关）。本实现照此语义 —— 故 `grade()` 里先判 φ、再判 FC 的蓝 V、
 * 最后才按分数档落。
 */
class PhigrosRating
{
	/** 满分固定 100 万（Phigros 规则）。 */
	public static inline var MAX_SCORE:Int = 1000000;

	/** 准确率权重：90 万。 */
	public static inline var ACC_WEIGHT:Float = 900000;

	/** 连击权重：10 万。 */
	public static inline var COMBO_WEIGHT:Float = 100000;

	/** `Good` 判定的准确率系数（Phigros 固定 0.65，与本引擎 `Rating.ratingMod` 无关）。 */
	public static inline var GOOD_FACTOR:Float = 0.65;

	/**
	 * 由判定计数算出 Phigros 式结果。
	 *
	 * @param perfect `Sick` + `Marvelous` 命中数（Phigros 只有 Perfect 一档，Marvelous 更严，
	 *                归入 Perfect）。
	 * @param good    `Good` 命中数。
	 * @param bad     `Bad` 命中数（Phigros 里 Bad 得 0 分准确率）。
	 * @param miss    未命中数（Miss）。
	 * @param maxCombo 本局最大连击（Phigros 的「最高连击」，不是当前连击）。
	 * @param totalNotes 谱面音符总数（0 表示未知/异常 → 返回 null）。
	 */
	public static function compute(perfect:Int, good:Int, bad:Int, miss:Int, maxCombo:Int, totalNotes:Int):PhigrosResult
	{
		if (totalNotes <= 0) return null;

		// ACC：(P + G×0.65) / 总数。Bad/Miss 得 0 —— 与 Phigros 一致。
		// 用 Float 累加以免大谱面整数截断累积误差。
		var acc:Float = (perfect + good * GOOD_FACTOR) / totalNotes;
		if (acc > 1) acc = 1;
		if (acc < 0) acc = 0;

		// 连击分：(最大连击 / 总数) × 10 万。
		// ⚠ **必须先把分母转Float**：Haxe 的 `Int / Int` 是**整数除法**，`450/500` 得 0 而非 0.9。
		// 踩过这个坑：非全连玩家会白丢整段连击分（10 万 = 整整一个 S 档的差距）。
		var comboRatio:Float = maxCombo / (totalNotes : Float);
		if (maxCombo > totalNotes) comboRatio = 1;
		if (comboRatio < 0) comboRatio = 0;

		// 就近取整（Phigros 的 Score 与 ACC 都四舍五入）。
		var score:Int = Math.round(acc * ACC_WEIGHT + comboRatio * COMBO_WEIGHT);

		var res:PhigrosResult = {
			accuracy: acc,
			score: score,
			rank: 'F',
			color: 0xFFFF6B6B,
			special: false,
			cleared: false,
			perfect: perfect,
			good: good,
			bad: bad,
			miss: miss,
			maxCombo: maxCombo,
			totalNotes: totalNotes
		};

		// φ：满分数（等价 ACC 100% + 全连）。
		if (score >= MAX_SCORE)
		{
			res.rank = 'φ';
			res.color = 0xFFFFD700; // 金
			res.special = true;
			res.cleared = true;
			return res;
		}

		// V：全连（无 Bad/Miss）。V 覆盖分数评级，但吃 φ。
		var combo:Int = perfect + good;
		if (bad == 0 && miss == 0 && combo >= totalNotes)
		{
			res.rank = 'V';
			res.color = 0xFF3FA9FF; // 蓝（Phigros 的 FC 是蓝 V）
			res.special = true;
			res.cleared = true;
			return res;
		}

		if (score >= 960000)
		{
			res.rank = 'V';
			res.color = 0xFFFFFFFF; // 白 V（非全连但分数很高）
		}
		else if (score >= 920000)
		{
			res.rank = 'S';
			res.color = 0xFFFFD700;
		}
		else if (score >= 880000)
		{
			res.rank = 'A';
			res.color = 0xFF66FF33;
		}
		else if (score >= 820000)
		{
			res.rank = 'B';
			res.color = 0xFF00FFFF;
		}
		else if (score >= 700000)
		{
			res.rank = 'C';
			res.color = 0xFFFF8800;
			res.cleared = true;
		}
		else
		{
			res.rank = 'F';
			res.color = 0xFFFF6B6B;
		}
		return res;
	}

	/**
	 * 从 PlayState 取判定计数并算结果。
	 *
	 * 数据源（`PlayState` 的既有字段，不新增任何统计口径）：
	 *  - `ratingsData[i].name / .hits`：各判定命中数（Marvelous 与 Sick 归入 Perfect）
	 *  - `songMisses`：Miss 数
	 *  - `maxCombo`：最大连击
	 *  - `totalNotes`：谱面音符总数（`generateChartNotes` 里由 `preGenTotalNotes` 赋值）
	 *
	 * `totalNotes` 为 0（谱面解析异常/尚未生成）时返回 null，调用方保留原显示。
	 */
	public static function fromPlayState(ps:PlayState):PhigrosResult
	{
		if (ps == null) return null;

		var perfect:Int = 0;
		var good:Int = 0;
		var bad:Int = 0;
		if (ps.ratingsData != null)
		{
			for (r in ps.ratingsData)
			{
				if (r == null) continue;
				switch (r.name)
				{
					case 'marvelous', 'sick': perfect += r.hits;
					case 'good': good += r.hits;
					case 'bad': bad += r.hits;
					default:
				}
			}
		}
		return compute(perfect, good, bad, I64.toIntSafe(ps.songMisses), I64.toIntSafe(ps.maxCombo), ps.totalNotes);
	}
}