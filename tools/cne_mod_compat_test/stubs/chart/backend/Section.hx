package backend;

/**
 * 测试替身：typedef 与仓库 `source/backend/Section.hx:3-13` 逐字段一致。
 * 保留同名空类 `Section`（仓库同文件里也有 class Section）。
 */
typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var typeOfSection:Int;
	var mustHitSection:Bool;
	var gfSection:Bool;
	var bpm:Float;
	var changeBPM:Bool;
	var altAnim:Bool;
}

class Section
{
	public function new() {}
}
