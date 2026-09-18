package flixel.util;

/**
 * 测试替身：与 flixel 6.2.0 `flixel/util/FlxSort.hx` 的 `byValues` 逐行一致
 * （只实现本测试用到的常量与函数）。
 */
class FlxSort
{
	public static inline var ASCENDING:Int = -1;
	public static inline var DESCENDING:Int = 1;

	public static inline function byValues(Order:Int, Value1:Float, Value2:Float):Int
	{
		var result:Int = 0;

		if (Value1 < Value2)
		{
			result = Order;
		}
		else if (Value1 > Value2)
		{
			result = -Order;
		}

		return result;
	}
}
