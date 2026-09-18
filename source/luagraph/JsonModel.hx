package luagraph;

import haxe.Json;

/**
 * JSON 容错取值助手：图文件来自磁盘，任何字段都可能缺失/类型不符。
 * 一律不抛异常（除了结构性错误），把坏数据降级为默认值，避免"读一张坏图 = 崩编辑器"。
 */
class JsonModel
{
	public static function str(v:Dynamic, def:String = ''):String
	{
		if (v == null) return def;
		if (Std.isOfType(v, String)) return cast v;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int) || Std.isOfType(v, Bool)) return Std.string(v);
		return def;
	}

	public static function int(v:Dynamic, def:Int = 0):Int
	{
		if (v == null) return def;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Float)) return Std.int(cast(v, Float));
		var n:Null<Int> = Std.parseInt(str(v, ''));
		return (n == null) ? def : n;
	}

	public static function arr(v:Dynamic):Array<Dynamic>
	{
		if (v == null) return [];
		if (Std.isOfType(v, Array)) return cast v;
		return [];
	}
}
