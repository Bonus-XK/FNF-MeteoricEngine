package backend;

import backend.Section;

/**
 * 测试替身：typedef 与仓库 `source/backend/Song.hx:14-38` 逐字段一致。
 * 保留同名空类 `Song`，因为没有顶层类的纯 typedef 文件不会成为模块
 * （仓库里正是 `class Song` + `typedef SwagSong` 同文件）。
 */
typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;

	@:optional var format:String;
}

class Song
{
	public function new() {}
}
