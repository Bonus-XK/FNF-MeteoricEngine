package backend;

/**
 * 测试替身：只保留 CneModCompat 读取的字段（默认值/语义与仓库 ClientPrefs 一致）。
 */
class SaveVariables
{
	public var cneModCompat:Bool = true;
	public var cneScriptLogs:Bool = false;

	public function new() {}
}

class ClientPrefs
{
	public static var data:SaveVariables = new SaveVariables();
}
