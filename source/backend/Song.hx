package backend;

import tjson.TJSON;
import lime.utils.Assets;
import openfl.utils.AssetType;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

import backend.Section;

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

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;
	
	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';

	// 谱面解析缓存：按实际文件路径 + 修改时间校验，命中时直接返回深拷贝，
	// 避免重复读盘与重复 JSON 解析（Freeplay 预览/确认、暂停换歌、故事模式等）。
	static var chartCache:Map<String, SwagSong> = [];
	static var chartCacheOrder:Array<String> = [];
	inline static var CHART_CACHE_MAX:Int = 8;

	public static function clearChartCache()
	{
		chartCache = [];
		chartCacheOrder = [];
	}

	static function getCachedChart(key:String):SwagSong
	{
		if (!chartCache.exists(key)) return null;
		if (chartCacheOrder.remove(key)) chartCacheOrder.push(key);
		return chartCache.get(key);
	}

	static function cacheChart(key:String, song:SwagSong)
	{
		if (chartCacheOrder.remove(key)) {}
		chartCacheOrder.push(key);
		chartCache.set(key, song);
		while (chartCacheOrder.length > CHART_CACHE_MAX)
		{
			var oldKey:String = chartCacheOrder.shift();
			chartCache.remove(oldKey);
		}
	}

	// 只判断谱面是否已缓存（不深拷贝、不改 LRU 顺序），供选歌时决定是否提前开解析线程
	public static function isChartCached(jsonInput:String, ?folder:String):Bool
	{
		var filePath:String = resolveChartPath(jsonInput, folder);
		if (filePath == null) return false;
		return chartCache.exists(chartCacheKey(filePath));
	}

	// 深拷贝谱面，防止调用方修改（如 Chart Editor、PlayState 的 stage/gfVersion 修正）污染缓存
	public static function copySong(song:SwagSong):SwagSong
	{
		var copy:SwagSong =
		{
			song: song.song,
			notes: [],
			events: [],
			bpm: song.bpm,
			needsVoices: song.needsVoices,
			speed: song.speed,
			player1: song.player1,
			player2: song.player2,
			gfVersion: song.gfVersion,
			stage: song.stage,
			gameOverChar: song.gameOverChar,
			gameOverSound: song.gameOverSound,
			gameOverLoop: song.gameOverLoop,
			gameOverEnd: song.gameOverEnd,
			disableNoteRGB: song.disableNoteRGB,
			arrowSkin: song.arrowSkin,
			splashSkin: song.splashSkin
		};

		if (song.notes != null)
			for (sec in song.notes)
				copy.notes.push(copySection(sec));

		if (song.events != null)
			for (event in song.events)
				copy.events.push(copyEvent(event));

		return copy;
	}

	static function copySection(sec:SwagSection):SwagSection
	{
		return
		{
			sectionNotes: sec.sectionNotes != null ? [for (note in sec.sectionNotes) note.copy()] : [],
			sectionBeats: sec.sectionBeats,
			typeOfSection: sec.typeOfSection,
			mustHitSection: sec.mustHitSection,
			gfSection: sec.gfSection,
			bpm: sec.bpm,
			changeBPM: sec.changeBPM,
			altAnim: sec.altAnim
		};
	}

	static function copyEvent(event:Array<Dynamic>):Array<Dynamic>
	{
		var params:Array<Dynamic> = [];
		if (event[1] != null)
			for (p in (event[1]:Array<Dynamic>))
				params.push(p != null && Std.isOfType(p, Array) ? p.copy() : p);
		return [event[0], params];
	}

	private static function onLoadJson(songJson:Dynamic) // Convert old charts to newest format
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			songJson.player3 = null;
		}

		if(songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];

				var i:Int = 0;
				var notes:Array<Dynamic> = sec.sectionNotes;
				var len:Int = notes.length;
				while(i < len)
				{
					var note:Array<Dynamic> = notes[i];
					if(note[1] < 0)
					{
						songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						notes.remove(note);
						len = notes.length;
					}
					else i++;
				}
			}
		}
	}

	public function new(song, notes, bpm)
	{
		this.song = song;
		this.notes = notes;
		this.bpm = bpm;
	}

	// 解析出谱面实际文件路径（mod 优先），不存在返回 null
	public static function resolveChartPath(jsonInput:String, ?folder:String):String
	{
		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);

		#if MODS_ALLOWED
		var moddyFile:String = Paths.modsJson(formattedFolder + '/' + formattedSong);
		if(FileSystem.exists(moddyFile)) return moddyFile;
		#end

		var baseFile:String = Paths.json(formattedFolder + '/' + formattedSong);
		#if (sys && !android)
		if(FileSystem.exists(baseFile)) return baseFile;
		#end
		// 安卓：Paths.json 可能返回外部存储的绝对路径（/sdcard/meteoric/assets/...），
		// 必须用 FileSystem 检查，否则外部谱面永远判为缺失
		if(FileSystem.exists(baseFile)) return baseFile;
		if(Assets.exists(baseFile, TEXT)) return baseFile;
		return null;
	}

	static function chartCacheKey(filePath:String):String
	{
		#if (sys && !android)
		// 用文件路径 + 修改时间做缓存键：外部改文件或保存新谱面后会自动失效
		return filePath + '|' + FileSystem.stat(filePath).mtime.getTime();
		#else
		return filePath;
		#end
	}

	// 仅查缓存：命中返回独立深拷贝（并处理舞台目录），未命中返回 null。不读盘、不解析。
	public static function tryLoadFromCache(jsonInput:String, ?folder:String):SwagSong
	{
		var filePath:String = resolveChartPath(jsonInput, folder);
		if(filePath == null) return null;

		var cached:SwagSong = getCachedChart(chartCacheKey(filePath));
		if(cached == null) return null;

		if(jsonInput != 'events') StageData.loadDirectory(cached);
		return copySong(cached);
	}

	// 纯读盘 + 解析（不碰缓存、不碰舞台目录），供后台线程调用
	public static function loadFromFile(filePath:String, isEvents:Bool):SwagSong
	{
		var rawJson = null;
		#if (sys && !android)
		rawJson = File.getContent(filePath).trim();
		#else
		#if sys
		// 安卓：外置存储上的谱面是绝对路径，lime 资源表不认，直接读磁盘
		if (FileSystem.exists(filePath))
			rawJson = File.getContent(filePath).trim();
		else
		#end
		rawJson = Assets.getText(filePath).trim();
		#end

		while (!rawJson.endsWith("}"))
		{
			rawJson = rawJson.substr(0, rawJson.length - 1);
			// LOL GOING THROUGH THE BULLSHIT TO CLEAN IDK WHATS STRANGE
		}

		var songJson:Dynamic = parseJSONshit(rawJson);
		onLoadJson(songJson);

		// 后台线程解析完成后也写入缓存（纯数据深拷贝），下次再选同一首谱面直接命中、不再解析
		cacheChart(chartCacheKey(filePath), copySong(songJson));
		return songJson;
	}

	// 检查歌曲的人声文件是否存在（mod 目录优先）
	public static function voicesFileExists(songName:String):Bool
	{
		var songPath:String = Paths.formatToSongPath(songName);
		#if MODS_ALLOWED
		if(FileSystem.exists(Paths.modsSounds('songs', songPath + '/Voices'))) return true;
		#end
		#if (sys && !android)
		return FileSystem.exists('assets/songs/' + songPath + '/Voices.' + Paths.SOUND_EXT);
		#else
		return Assets.exists('assets/songs/' + songPath + '/Voices.' + Paths.SOUND_EXT, SOUND);
		#end
	}

	// 检查歌曲音频（伴奏/人声）是否已在缓存中：刚试听过的歌会命中，可跳过加载界面
	public static function songAudioCached(songName:String):Bool
	{
		var songPath:String = Paths.formatToSongPath(songName);
		#if MODS_ALLOWED
		var modInstKey:String = Paths.modsSounds('songs', songPath + '/Inst');
		if (Paths.currentTrackedSounds.exists(modInstKey))
			return !voicesFileExists(songName) || Paths.currentTrackedSounds.exists(Paths.modsSounds('songs', songPath + '/Voices'));
		#end

		var instKey:String = Paths.getPath('songs/' + songPath + '/Inst.' + Paths.SOUND_EXT, SOUND);
		instKey = instKey.substring(instKey.indexOf(':') + 1);
		if (!Paths.currentTrackedSounds.exists(instKey)) return false;

		if (!voicesFileExists(songName)) return true;
		var voicesKey:String = Paths.getPath('songs/' + songPath + '/Voices.' + Paths.SOUND_EXT, SOUND);
		voicesKey = voicesKey.substring(voicesKey.indexOf(':') + 1);
		return Paths.currentTrackedSounds.exists(voicesKey);
	}

	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong
	{
		var filePath:String = resolveChartPath(jsonInput, folder);
		if(filePath == null)
			throw 'Missing chart file: data/' + jsonInput;

		var cached:SwagSong = tryLoadFromCache(jsonInput, folder);
		if(cached != null) return cached;

		var songJson:SwagSong = loadFromFile(filePath, jsonInput == 'events');
		if(jsonInput != 'events') StageData.loadDirectory(songJson);
		return songJson;
	}

	public static function parseJSONshit(rawJson:String):SwagSong
	{
		var songJson:Dynamic = null;
		try
		{
			songJson = Reflect.field(haxe.Json.parse(rawJson), 'song');
		}
		catch(e:Dynamic)
		{
			// 极少数旧谱面带注释/非标准 JSON：回退到 tjson 兼容解析
			songJson = Reflect.field(TJSON.parse(rawJson), 'song');
		}
		return cast songJson;
	}
}
