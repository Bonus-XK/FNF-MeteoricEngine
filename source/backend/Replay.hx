package backend;

#if sys
import sys.io.File;
import sys.FileSystem;
import lime.system.System;
#end
import backend.Song;
import haxe.Json;

typedef ReplayEvent =
{
	s:Int,   // 谱面序号（Note.chartSeq），-1 = 空按（无对应音符）
	t:Float, // 时间（ms）：命中 = 音符 strumTime；空按 = 按键瞬间
	d:Int,   // 轨道 0-3
	r:String // sick/good/bad/shit/sus/hurt/mp
}

// 回放：录制一次手动游玩的所有按键命中（含长条子段与空按），按谱面序号精确重放
class Replay
{
	public var song:String = '';
	public var difficulty:String = '';
	public var fingerprint:String = '';
	public var score:Int = 0;
	public var misses:Int = 0;
	public var percent:Float = 0;
	public var events:Array<ReplayEvent> = [];

	public var filePath:String = ''; // 已保存文件的完整路径（列表/删除用）
	public var saveTime:Float = 0;   // 保存时间戳（ms）

	// ---- 回放派生数据（buildDerived 后使用） ----
	public var hitSeqs:Map<Int, String> = new Map();    // chartSeq -> sus/hurt/评分
	public var ratingSeqs:Map<Int, String> = new Map(); // chartSeq -> 评分（非长条/伤害）
	public var pressMisses:Array<ReplayEvent> = [];     // 空按（按时间升序）

	public function new(?songName:String = '', ?diff:String = '')
	{
		song = songName;
		difficulty = diff;
	}

	public function addEvent(seq:Int, t:Float, d:Int, r:String):Void
	{
		events.push({s: seq, t: t, d: d, r: r});
	}

	public function buildDerived():Void
	{
		hitSeqs = new Map();
		ratingSeqs = new Map();
		pressMisses = [];
		for (e in events)
		{
			if (e.s >= 0)
			{
				hitSeqs.set(e.s, e.r);
				if (e.r != 'sus' && e.r != 'hurt') ratingSeqs.set(e.s, e.r);
			}
			else
				pressMisses.push(e);
		}
		pressMisses.sort(function(a, b) return a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));
	}

	// 谱面指纹：同一张谱（同一难度文件）的录制才能套用，防止谱面被改后回放错位
	public static function chartFingerprint(song:SwagSong):String
	{
		var count:Int = 0;
		var sum:Float = 0;
		var last:Float = 0;
		if (song != null && song.notes != null)
		{
			for (section in song.notes)
			{
				if (section.sectionNotes == null) continue;
				for (n in section.sectionNotes)
				{
					var t:Float = n[0];
					count++;
					sum += t;
					if (t > last) last = t;
				}
			}
		}
		return song.song + '|' + song.bpm + '|' + count + '|' + Math.round(last) + '|' + Math.round(sum);
	}

	public function toJson():String
	{
		return Json.stringify({
			song: song,
			difficulty: difficulty,
			fingerprint: fingerprint,
			score: score,
			misses: misses,
			percent: percent,
			events: events
		});
	}

	public static function fromJson(data:String):Replay
	{
		var raw:Dynamic = Json.parse(data);
		if (raw == null) return null;
		var replay:Replay = new Replay(raw.song, raw.difficulty);
		if (raw.fingerprint != null) replay.fingerprint = raw.fingerprint;
		if (raw.score != null) replay.score = raw.score;
		if (raw.misses != null) replay.misses = raw.misses;
		if (raw.percent != null) replay.percent = raw.percent;
		if (raw.events != null)
			for (e in (raw.events:Array<Dynamic>))
				replay.addEvent(e.s, e.t, e.d, e.r);
		replay.buildDerived();
		return replay;
	}

	#if sys
	public static function getReplayDir():String
	{
		var dir:String = System.applicationStorageDirectory;
		if (dir.length > 0 && !dir.endsWith('/') && !dir.endsWith('\\')) dir += '/';
		return dir + 'replays/';
	}

	public function save():String
	{
		try
		{
			var dir:String = getReplayDir();
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			var epoch:Int = Std.int(Date.now().getTime() / 1000);
			var fileName:String = Paths.formatToSongPath(song) + '-' + difficulty + '-'
				+ epoch + '-' + Std.random(9000) + '.json';
			filePath = dir + fileName;
			saveTime = epoch * 1000;
			File.saveContent(filePath, toJson());
			return filePath;
		}
		catch (e:Dynamic)
		{
			trace('保存回放失败：' + e);
		}
		return '';
	}

	public static function loadFromFile(path:String):Replay
	{
		try
		{
			var replay:Replay = fromJson(File.getContent(path));
			if (replay != null) replay.filePath = path;
			return replay;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	public static function listFor(songName:String, diff:Int):Array<Replay>
	{
		var result:Array<Replay> = [];
		var dir:String = getReplayDir();
		if (!FileSystem.exists(dir)) return result;
		var prefix:String = Paths.formatToSongPath(songName) + '-' + Difficulty.getString(diff) + '-';
		for (file in FileSystem.readDirectory(dir))
		{
			if (!file.startsWith(prefix) || !file.endsWith('.json')) continue;
			var replay:Replay = loadFromFile(dir + file);
			if (replay != null)
			{
				var base:String = file.substr(prefix.length, file.length - prefix.length - 5);
				replay.saveTime = Std.parseFloat(base.split('-')[0]) * 1000;
				result.push(replay);
			}
		}
		result.sort(function(a, b) return a.saveTime < b.saveTime ? 1 : -1);
		return result;
	}

	public static function deleteFile(path:String):Void
	{
		try
		{
			if (path.length > 0 && FileSystem.exists(path)) FileSystem.deleteFile(path);
		}
		catch (e:Dynamic) {}
	}
	#end
}
