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
	/** 键数硬上限（改键界面 / 布局 / 绑定注册都按此预留）。
	 *  2026-10-31 移植 Leather：上限对齐 21（mania data 表写满 21 行）；
	 *  输入绑定/颜色 UI 目前只注册到 12，13-21 键可玩但键位沿用系统默认。 */
	public static inline var MAX_KEYS:Int = 21;
	public static inline var DEFAULT_KEYS:Int = 4;

	/** 4K 时代的轨道间距（Note.swagWidth 同源，布局计算用） */
	public static inline var SWAG_WIDTH:Float = 160 * 0.7;

	/** 当前谱面键数。进曲 / 进编辑器时由 setSongKeys 写入；默认 4 = 旧行为。 */
	public static var songKeys:Int = DEFAULT_KEYS;

	/** 每轨间距（keys>4 时自动压缩，keys<=4 恒 = SWAG_WIDTH） */
	public static var laneGap:Float = SWAG_WIDTH;
	/** 音符缩放（keys>4 时 = laneGap/SWAG_WIDTH，<=4 恒 1） */
	public static var laneScale:Float = 1.0;

	// Leather 布局参数（ui skins/<skin>/mania*.txt，每键数一行）：size=整体缩小系数、
	// gap=每轨步进扣减、offset=整组偏移。Leather 公式：步进 = 帧宽×(0.7−size) + 2 + gap。
	static var maniaSize:Array<Float> = null;
	static var maniaGap:Array<Float> = null;
	static var maniaOffset:Array<Float> = null;

	// Leather mania data 数据表（data/mania data/*.txt，每键数一行、空格分词）：
	// noteCountDirections=箭头 static 帧方向名、otherNoteAnim=音符帧前缀、
	// charAnim=角色 sing 动画名、defaultBinds=默认键位（KeyBoard 名）。
	static var noteCountDirections:Array<Array<String>> = null;
	static var otherNoteAnim:Array<Array<String>> = null;
	static var charAnimTable:Array<Array<String>> = null;

	static var maniaLoaded:Bool = false;

	/** 惰性加载 Leather 数据表（每行 = 一个键数，行号 = 键数-1；缺行回退 4 方向循环）。 */
	static function loadManiaData():Void
	{
		if (maniaLoaded) return;
		maniaLoaded = true;

		maniaSize = loadFloatRows('data/ui skins/default/maniasize');
		maniaGap = loadFloatRows('data/ui skins/default/maniagap');
		maniaOffset = loadFloatRows('data/ui skins/default/maniaoffset');
		noteCountDirections = loadStrRows('data/mania data/maniaDirections');
		otherNoteAnim = loadStrRows('data/mania data/maniaAnimationDirections');
		charAnimTable = loadStrRows('data/mania data/maniaCharacterAnimations');
	}

	/** 读整文件按行分 Float（含空行占位，行号即键数-1）。 */
	static function loadFloatRows(path:String):Array<Float>
	{
		var out:Array<Float> = [];
		var raw:String = Paths.getTextFromFile(path + '.txt');
		if (raw == null) return out;
		for (line in raw.split('\n'))
		{
			var s:String = StringTools.trim(line);
			out.push((s.length > 0 && !s.startsWith('//')) ? Std.parseFloat(s) : 0.0);
		}
		return out;
	}

	/** 读整文件按行分词（空行=空组占位）。 */
	static function loadStrRows(path:String):Array<Array<String>>
	{
		var out:Array<Array<String>> = [];
		var raw:String = Paths.getTextFromFile(path + '.txt');
		if (raw == null) return out;
		for (line in raw.split('\n'))
		{
			var s:String = StringTools.trim(line);
			if (s.startsWith('//')) continue;
			out.push((s.length > 0) ? s.split(' ') : []);
		}
		return out;
	}

	static function rowAt(table:Array<Array<String>>, keys:Int):Array<String>
	{
		if (table == null || keys - 1 >= table.length) return null;
		var r:Array<String> = table[keys - 1];
		return (r != null && r.length > 0) ? r : null;
	}

	static function floatAt(table:Array<Float>, keys:Int):Float
	{
		if (table == null || keys - 1 >= table.length) return 0.0;
		return table[keys - 1];
	}

	/** 是否走 Leather 风格（箭头皮肤 + 方向名帧）：keys > 4 时自动启用；4K 恒走 Psych 原路径。 */
	public static inline function usingLeatherSkin():Bool
	{
		return songKeys > 4;
	}

	/** lane 的箭头 static 帧方向名（小写，如 left/square/rup）。仅 Leather 风格下有意义。 */
	public static function arrowDirFrame(lane:Int):String
	{
		loadManiaData();
		var row:Array<String> = rowAt(noteCountDirections, songKeys);
		if (row == null || lane < 0 || lane >= row.length) return colNameOf(lane);
		return row[lane].toLowerCase();
	}

	/** lane 的音符帧前缀（如 purple/plus/rup）。Leather 帧 = 前缀+"0"/" hold0"/" hold end0"。 */
	public static function noteAnimPrefix(lane:Int):String
	{
		loadManiaData();
		var row:Array<String> = rowAt(otherNoteAnim, songKeys);
		if (row == null || lane < 0 || lane >= row.length) return colNameOf(lane);
		return row[lane].toLowerCase();
	}

	/** lane 的角色 sing 动画名（singLEFT 等）。 */
	public static function charSingAnim(lane:Int):String
	{
		loadManiaData();
		var row:Array<String> = rowAt(charAnimTable, songKeys);
		if (row == null || lane < 0 || lane >= row.length) return singNameOf(lane);
		return row[lane];
	}

	static function colNameOf(lane:Int):String
	{
		return ['purple', 'blue', 'green', 'red'][((lane % 4) + 4) % 4];
	}

	static function singNameOf(lane:Int):String
	{
		return ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'][((lane % 4) + 4) % 4];
	}

	/**
	 * lane → 音符/箭头贴图的颜色前缀名。
	 * keys>4（Leather 风格）= maniaAnimationDirections 表；4K = Psych 4 色循环。
	 */
	public static function noteColName(lane:Int):String
	{
		if (usingLeatherSkin()) return noteAnimPrefix(lane);
		return colNameOf(lane);
	}

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
		// ⚠ 非法值（0 / 负数）回退默认 4 —— 不能钳到 1：
		//   SwagSong.keys 是 @:optional，旧谱面（无 keys 字段）读到的是 null，
		//   null 传给 Int 形参在 hxcpp 下会变成 0（Null<Int> 的装箱陷阱），
		//   钳到 1 会让所有内置 4K 谱面变成「1 键」（实测事故）。
		if (n < 1) n = DEFAULT_KEYS;
		if (n > MAX_KEYS) n = MAX_KEYS;
		return n;
	}

	/**
	 * 进曲 / 进编辑器时调用：写入 songKeys 并重算布局。
	 * @param k 必须是 Dynamic/可空：谱面没有 keys 字段时传进来的是 null，
	 *          用 Int 形参会被静默装箱成 0 → 全部内置曲变 1 键。
	 */
	public static function setSongKeys(k:Dynamic):Void
	{
		songKeys = resolveKeys(k);
		computeLayout();
	}

	/** 布局：keys==4 恒等旧值；keys>4 用 Leather 公式（mania 布局参数表驱动）：
	 *  轨道宽 = 帧宽157 × (0.7 − size[kc])；步进 = 轨道宽 + 2 + gap[kc]；
	 *  offset[kc] 由 laneX 的组起点叠加。5K 起逐步缩小，11K 起整组右移居中。 */
	static function computeLayout():Void
	{
		if (songKeys <= 4)
		{
			laneGap = SWAG_WIDTH;
			laneScale = 1.0;
			return;
		}
		loadManiaData();
		var trackW:Float = 157 * (0.7 - floatAt(maniaSize, songKeys));
		if (trackW < 20) trackW = 20;
		laneGap = trackW + 2 + floatAt(maniaGap, songKeys);
		laneScale = trackW / (157 * 0.7);
		// 布局整体偏移在 laneX 的组起点里叠加（maniaOffset）
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
		loadManiaData();
		// keys>4：Leather 组起点公式 —— 100 − (kc−4)×16，10 键起 +30；整组偏移 maniaOffset
		var groupStart:Float = 100 - ((songKeys - 4) * 16) + (songKeys >= 10 ? 30 : 0)
			+ floatAt(maniaOffset, songKeys);
		if (middle)
		{
			// 中滚沿用 Meteoric 泛化：整组按键数居中（Leather 无中滚概念）
			var start:Float = (FlxG.width - songKeys * laneGap) / 2;
			return start + lane * laneGap;
		}
		var x:Float = rawBase + 50 + groupStart + lane * laneGap;
		if (player) return x + FlxG.width / 2;
		return x;
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
		loadManiaData();
		if (!middle)
		{
			// Leather 组起点（与 laneX 的 keys>4 分支同源），音符与轨道必须同基准
			var groupStart:Float = 100 - ((songKeys - 4) * 16) + (songKeys >= 10 ? 30 : 0)
				+ floatAt(maniaOffset, songKeys);
			return mustPress ? FlxG.width / 2 + groupStart : groupStart;
		}
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

	/** lane → 轨道颜色表（21 键超出 12 条目时循环复用，绝不返回 null）。 */
	public static function laneColors(lane:Int, pixel:Bool):Array<FlxColor>
	{
		var table:Array<Array<FlxColor>> = pixel ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB;
		if (table != null && table.length > 0 && lane >= 0)
		{
			var idx:Int = lane % table.length; // 13-21 键循环复用前 12 组颜色
			if (table[idx] != null && table[idx].length >= 3) return table[idx];
		}
		var def:Array<Array<FlxColor>> = pixel ? ClientPrefs.defaultData.arrowRGBPixel : ClientPrefs.defaultData.arrowRGB;
		if (def != null && def.length > 0)
		{
			var idx2:Int = lane % def.length;
			if (def[idx2] != null) return def[idx2];
		}
		return [0xFFFFFFFF, 0xFFFFFFFF, 0xFF000000];
	}
}
