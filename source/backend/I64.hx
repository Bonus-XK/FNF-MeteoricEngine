package backend;

/**
 * haxe.Int64 边界转换工具（本项目专用）。
 *
 * 背景（实测 haxe 4.2.5 std）：
 *  - `haxe.Int64` 抽象没有 `toFloat`（只有 `fromFloat`）；
 *  - `haxe.Int64.toInt(x)` 在 x 超出 Int32 范围时会 `throw "Overflow"`；
 *  - hxcpp 底层是原生 cpp::Int64Struct，运算走 C 层，无性能问题。
 *
 * 仅用于展示 / 存档 / Lua 脚本暴露的边界转换；判定、评分等游戏内路径不要加转换。
 */
class I64
{
	/**
	 * Int64 → Int，超出 Int32 范围时钳制到 Int32 极值（不抛异常）。
	 * 32 位可表示 ⇔ high == low >> 31（符号扩展一致，即 Int64.make/ofInt 的规范形式）。
	 */
	public static inline function toIntSafe(x:haxe.Int64):Int
	{
		return (x.high == (x.low >> 31)) ? x.low : (x.high > 0 ? 0x7fffffff : -2147483647 - 1);
	}

	/**
	 * Int64 → Float，手工 high * 2^32 + 无符号 low。
	 * Double 可精确表示到 2^53 = 9007199254740992，
	 * 本项目分数越界上限 ~1.8e12（36 亿谱面 × 500/音符），远在内。
	 */
	public static inline function toFloat(x:haxe.Int64):Float
	{
		var lo:Float = x.low; // Int32 有符号
		if (lo < 0)
			lo += 4294967296.0; // 还原成无符号 32 位
		return x.high * 4294967296.0 + lo;
	}
}
