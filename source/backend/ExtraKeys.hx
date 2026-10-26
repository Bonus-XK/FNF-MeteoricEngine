package backend;

import flixel.FlxG;

/**
 * ExtraKeys —— 任意键数（1~12 轨）的**唯一事实来源**。
 *
 * 设计约束（用户拍板）：
 *  - 键数由**谱面声明**（song JSON 顶层 "keys" 字段，缺省 = 4）；引擎按谱面动态生成轨道。
 *  - 4K 谱面（keys==4 或缺省）行为必须与旧版**逐像素一致**：所有旧常量路径原样保留，
 *    泛化公式只在 keys != 4 时生效。
 *  - 轨道外观：循环复用 4 方向箭头贴图（lane % 4 → 紫/蓝/绿/红），
 *    颜色由 ClientPrefs.arrowRGB（12 条目）按 lane 自定义。
 *  - 输入绑定：lane 0-3 沿用 note_left/down/up/right；lane 4-11 用 note_4..note_11。
 *  - 列号协议（psych_v1 泛化）：绝对列号 col ∈ [0, 2*keys)，
 *      lane = col % keys；col < keys = 玩家侧，否则对手侧。
 *    keys==4 时与旧版「<4 玩家 / %4 lane」完全等价。
 */
class ExtraKeys
{
	/** 键数硬上限（改键界面 / 布局 / 绑定注册都按此预留） */
	public static inline var MAX_KEYS:Int = 12;
	public static inline var DEFAULT_KEYS:Int = 4;

	/** 4K 时代的轨道间距（Note.swagWidth 同源，布局计算用） */
	public static inline var SWAG_WIDTH:Float = 160 * 0.7;

	/** 当前谱面键数。进曲 / 进编辑器时由 setSongKeys 写入；默认 4 = 旧行为。 */
	public static var songKeys:Int = DEFAULT_KEYS;

	/** 每轨间距（keys>4 时自动压缩，keys<=4 恒 = SWAG_WIDTH） */
	public static var laneGap:Float = SWAG_WIDTH;
	/** 音符缩放（keys>4 时 = laneGap/SWAG_WIDTH，<=4 恒 1） */
	public static var laneScale:Float = 1.0;

	/** 从谱面字段解析键数（容错：null/非法 → 4；范围钳到 1..12） */
	public static function resolveKeys(v:Dynamic):Int
	{
		var n:Int = DEFAULT_KEYS;
		if (v != null)
		{
			if (v is Int) n = cast v;
			else if (v is Float) n = Std.int(cast v);
			else
			{
				var parsed:Null<Int> = Std.parseInt(Std.string(v));
				n = (parsed != null) ? parsed : DEFAULT_KEYS;
			}
		}
		if (n < 1) n = 1;
		if (n > MAX_KEYS) n = MAX_KEYS;
		return n;
	}

	/** 进曲 / 进编辑器时调用：写入 songKeys 并重算布局。 */
	public static function setSongKeys(k:Int):Void
	{
		songKeys = resolveKeys(k);
		computeLayout();
	}

	/** 布局：keys==4 恒等旧值；keys>4 时玩家组压缩进右半屏可用宽度。 */
	static function computeLayout():Void
	{
		if (songKeys <= 4)
		{
			laneGap = SWAG_WIDTH;
			laneScale = 1.0;
			return;
		}
		// 玩家组可用宽度 = 右半屏 - 两侧安全边距（1280 基线下 ≈ 540px）
		var avail:Float = FlxG.width / 2 - 100;
		var g:Float = avail / songKeys;
		if (g > SWAG_WIDTH) g = SWAG_WIDTH;
		if (g < 24) g = 24; // 12K 的兜底下限，防止缩成看不见
		laneGap = g;
		laneScale = g / SWAG_WIDTH;
	}

	/** 绝对列号 → lane（0..keys-1）。负列号防御性纠正（Haxe % 对负数返回负值）。 */
	public static inline function laneOf(col:Int):Int
	{
		var l:Int = col % songKeys;
		if (l < 0) l += songKeys;
		return l;
	}

	/** 绝对列号是否玩家侧（col < keys） */
	public static inline function isPlayerCol(col:Int):Bool
	{
		return col >= 0 && col < songKeys;
	}

	/**
	 * lane 的最终 X（HUD 坐标）。
	 * @param rawBase 调用方传入的基准 X（普通 = PlayState.STRUM_X；中滚 = STRUM_X_MIDDLESCROLL），
	 *                函数内部统一 +50（与旧版 postAddedToGroup / Note 构造的 +50 同源）。
	 *                传入值可含 HUD 自定义偏移（旧版 generateStaticArrows 即如此）。
	 *
	 * keys==4 时逐项复现旧常量路径（含中滚对手 310 / lane>1 加 640+25 的手调值）。
	 */
	public static function laneX(rawBase:Float, player:Bool, lane:Int):Float
	{
		var middle:Bool = ClientPrefs.data.middleScroll;
		if (songKeys == 4)
		{
			var x:Float = rawBase + 50 + lane * SWAG_WIDTH;
			if (player) return x + FlxG.width / 2;
			if (middle) return x + 310 + ((lane > 1) ? FlxG.width / 2 + 25 : 0);
			return x;
		}
		var start:Float;
		if (player)
			start = middle ? (FlxG.width - songKeys * laneGap) / 2 : (rawBase + 50 + FlxG.width / 2);
		else
			start = middle ? 8 : (rawBase + 50);
		return start + lane * laneGap;
	}

	/**
	 * 音符出生的阵营/中滚偏移（叠加在「对手组基准 + lane*laneGap」之上）。
	 * 对手普通 = 0；玩家普通 = +FlxG.width/2（4K 与泛化同值）；
	 * 中滚按 keys 分支（4K 保旧手调值；其他键数玩家组居中 / 对手组贴左缘）。
	 */
	public static function sideShiftX(mustPress:Bool, lane:Int):Float
	{
		var middle:Bool = ClientPrefs.data.middleScroll;
		if (songKeys == 4)
		{
			if (mustPress) return FlxG.width / 2;
			if (middle) return 310 + ((lane > 1) ? FlxG.width / 2 + 25 : 0);
			return 0;
		}
		if (!middle) return mustPress ? FlxG.width / 2 : 0;
		// 中滚 + keys≠4：Note 构造基准 = STRUM_X_MIDDLESCROLL+50 = -228；
		// 玩家组目标起点 = FlxG.width/2 - N*gap/2 → 偏移 = 640 - N*gap/2 + 228；
		// 对手组贴左缘 8 → 偏移 = 8 + 228 = 236。
		if (mustPress) return FlxG.width / 2 - songKeys * laneGap / 2 + 228;
		return 236;
	}

	/** lane → 输入 action 名。lane 0-3 沿用旧名（note_left/down/up/right），4+ 用 note_N。 */
	public static function actionName(lane:Int):String
	{
		return switch (lane)
		{
			case 0: 'note_left';
			case 1: 'note_down';
			case 2: 'note_up';
			case 3: 'note_right';
			default: 'note_' + lane;
		}
	}

	/** 当前键数下的完整输入 action 表（PlayState.keysArray 用）。 */
	public static function actionNames():Array<String>
	{
		var out:Array<String> = [];
		for (i in 0...songKeys) out.push(actionName(i));
		return out;
	}

	/** 定长 false 数组（botBatch/replayHeld 等 per-lane 状态用） */
	public static function falseLanes():Array<Bool>
	{
		var out:Array<Bool> = [];
		for (i in 0...songKeys) out.push(false);
		return out;
	}

	/** 定长 0 数组（botLaneCounts 等） */
	public static function zeroLanes():Array<Int>
	{
		var out:Array<Int> = [];
		for (i in 0...songKeys) out.push(0);
		return out;
	}

	/** 定长 -99999 数组（lastSplashLane 节流用） */
	public static function farPastLanes():Array<Float>
	{
		var out:Array<Float> = [];
		for (i in 0...songKeys) out.push(-99999);
		return out;
	}

	/** lane → 轨道颜色表（带越界兜底，绝不返回 null）。 */
	public static function laneColors(lane:Int, pixel:Bool):Array<FlxColor>
	{
		var table:Array<Array<FlxColor>> = pixel ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB;
		if (table != null && lane >= 0 && lane < table.length && table[lane] != null && table[lane].length >= 3)
			return table[lane];
		var def:Array<Array<FlxColor>> = pixel ? ClientPrefs.defaultData.arrowRGBPixel : ClientPrefs.defaultData.arrowRGB;
		if (def != null && lane >= 0 && lane < def.length && def[lane] != null) return def[lane];
		return [0xFFFFFFFF, 0xFFFFFFFF, 0xFF000000];
	}
}
