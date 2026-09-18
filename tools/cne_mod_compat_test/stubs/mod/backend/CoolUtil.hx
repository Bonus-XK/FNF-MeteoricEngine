package backend;

import sys.io.File;

/** 测试替身：与仓库 CoolUtil.coolTextFile 同语义（按行读、去掉行尾 \r）。 */
class CoolUtil
{
	public static function coolTextFile(path:String):Array<String>
	{
		var lines:Array<String> = [];
		if (!sys.FileSystem.exists(path)) return lines;
		for (line in File.getContent(path).split('\n')) lines.push(StringTools.replace(line, '\r', ''));
		return lines;
	}
}
