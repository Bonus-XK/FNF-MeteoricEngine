package backend;

/** 测试替身：固定返回 Normal（对齐仓库默认难度语义）。 */
class Difficulty
{
	public static var name:String = 'Normal';
	public static function getString(?num:Null<Int> = null):String return name;
}
