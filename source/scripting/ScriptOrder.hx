package scripting;

/**
 * 脚本执行顺序约定（仅影响**同一脚本组内**的调用顺序，不改变加载内容）。
 *
 * ## 文件名前缀
 *
 * ```
 * 00_first.hx      → 优先级 0    （最先执行）
 * 50_middle.hx     → 优先级 50
 * z_last.hx        → 优先级 1000 （最后执行）
 * normal.hx        → 优先级 500  （默认，与加前缀前行为一致）
 * ```
 *
 * - 数字前缀：`^(\d{1,3})[_-]`，取值 0–999；
 * - `z_` / `z-`（不区分大小写）：固定 1000，等价于「最后」；
 * - 无前缀：{@link DEFAULT_PRIORITY}（500）。
 *
 * ## 排序键
 *
 * `(优先级, mod 启用顺序, 文件名小写)` 三段稳定排序。
 * 因此**所有脚本都不带前缀时，顺序与加本约定之前完全一致**（仍是 mod 顺序 + 文件名）。
 *
 * ## 为什么需要
 *
 * 大型 mod 里 `create()` 的先后会影响脚本之间的依赖（例如 UI 脚本要读机制脚本
 * 已建好的变量）。Dustin（CNE）用 `z_script_orderer.hx` 在运行期重排脚本数组；
 * 这里用更轻的「文件名前缀」在构建期一次排好，不需要额外的排序脚本。
 */
class ScriptOrder
{
	/** 无前缀脚本的默认优先级。 */
	public static inline var DEFAULT_PRIORITY:Int = 500;

	/** `z_` 前缀脚本的优先级（最后执行）。 */
	public static inline var LAST_PRIORITY:Int = 1000;

	/**
	 * 从文件名解析执行优先级。
	 *
	 * @param fileName 文件名（可带 `.hx` / `.hx.disabled` 后缀，只解析主名前缀）。
	 * @return 0–999 的数字前缀；`z_` = 1000；无前缀 = 500。
	 */
	public static function priorityOf(fileName:String):Int
	{
		if (fileName == null || fileName.length == 0) return DEFAULT_PRIORITY;

		// 数字前缀：00_ / 10- / 999_
		var m = ~/^([0-9]{1,3})[_-]/;
		if (m.match(fileName))
		{
			var n:Null<Int> = Std.parseInt(m.matched(1));
			if (n != null && n >= 0) return n;
		}

		// z_ / z-（不区分大小写）= 最后
		if (~/^[zZ][_-]/.match(fileName)) return LAST_PRIORITY;

		return DEFAULT_PRIORITY;
	}

	/**
	 * 把脚本条目按「优先级 → mod 顺序 → 文件名」排序（原地）。
	 *
	 * 排序是稳定的：相同键保持调用方传入的相对顺序。
	 */
	public static function sortEntries(entries:Array<ScriptOrderEntry>):Void
	{
		if (entries == null || entries.length < 2) return;
		entries.sort(function(a:ScriptOrderEntry, b:ScriptOrderEntry):Int
		{
			var c:Int = a.priority - b.priority;
			if (c != 0) return c;
			c = a.modIndex - b.modIndex;
			if (c != 0) return c;
			var an:String = a.file == null ? '' : a.file.toLowerCase();
			var bn:String = b.file == null ? '' : b.file.toLowerCase();
			return Reflect.compare(an, bn);
		});
	}
}

/** 排序用的脚本条目（构建期临时结构，不暴露给脚本）。 */
typedef ScriptOrderEntry =
{
	/** 脚本完整路径。 */
	var path:String;
	/** 文件名（用于排序与日志）。 */
	var file:String;
	/** 执行优先级（见 {@link ScriptOrder.priorityOf}）。 */
	var priority:Int;
	/** mod 启用顺序（枚举自 `Mods.parseList().enabled`）。 */
	var modIndex:Int;
}
