package backend;

/** 测试替身：只提供 CneModCompat 用到的两个入口。 */
class Mods
{
	public static var currentModDirectory:String = '';
	static var globalMods:Array<String> = [];
	public static function getGlobalMods():Array<String> return globalMods;
	public static function setGlobalMods(m:Array<String>):Void globalMods = m;
}
