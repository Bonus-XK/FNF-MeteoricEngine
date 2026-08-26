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
	@:optional var format:String;
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
	// 内存大关（Meteoric Fix 续）：LRU 上限从 8 收紧到 2 —— 大谱面（42MB/226 万音符级）
	// 每份缓存都是完整 DOM 深拷贝，8 份常驻可吃掉数 GB；2 份足够覆盖"当前曲 + 上一曲/events"，
	// 换曲/重开走重新解析是低频路径，代价可接受。
	static var chartCache:Map<String, SwagSong> = [];
	static var chartCacheOrder:Array<String> = [];
	inline static var CHART_CACHE_MAX:Int = 2;

	public static function clearChartCache()
	{
		chartCache = [];
		chartCacheOrder = [];
	}

	// ===== 游玩期谱面 DOM 释放（Meteoric Fix 续）=====
	// PlayState 生成完音符序列后调用：把每个 section 的逐音符数组（大谱面数百 MB 级 DOM）
	// 替换为空数组，只保留 section 元数据（sectionBeats/mustHitSection/bpm 等运行时需要）。
	// 原始数据仍在 chartCache（LRU 2）内，重开/回溯/开编谱前由 PlayState.reloadChartSourceIfNeeded()
	// 从缓存恢复完整 SONG，不影响任何流程正确性。
	public static function stripSectionNotes(song:SwagSong):Void
	{
		if (song == null || song.notes == null) return;
		for (sec in song.notes)
			if (sec != null && sec.sectionNotes != null && sec.sectionNotes.length > 0)
				sec.sectionNotes = []; // 每 section 独立空数组：不共享常量，杜绝编辑器 push 污染
	}

	// ===== 游玩期谱面缓存副本释放（Meteoric Fix 续：Flocc 级 1GB → 400MB）=====
	// 大谱面（JSON > CHART_DOM_KEEP_MAX）进曲生成完成后，把 chartCache 里那份完整 DOM 深拷贝
	// 也淘汰掉 —— 游玩稳态只剩 CastNote/元数据，不再有任何整份谱面 DOM 常驻。
	// 重开/回溯/换难度/开编谱走快速字节扫描重新解析（42MB 约 1~2s，用户已确认可接受），
	// 且 loadFromFile 不再把重解析结果重新塞进缓存（见 loadFromFile 底部注释）。
	inline static var CHART_DOM_KEEP_MAX:Int = 4000000; // 4MB：普通谱面保留缓存（瞬时重开），大谱面淘汰

	public static function evictChartFromCache(jsonInput:String, ?folder:String):Void
	{
		var filePath:String = resolveChartPath(jsonInput, folder);
		if (filePath == null) return;
		var key:String = chartCacheKey(filePath);
		if (chartCache.exists(key))
		{
			chartCache.remove(key);
			chartCacheOrder.remove(key);
		}
	}

	// 仅当谱面文件足够大（内存收益显著）才淘汰；小谱面保留缓存换瞬时重开
	public static function evictLargeChartFromCache(jsonInput:String, ?folder:String):Void
	{
		var filePath:String = resolveChartPath(jsonInput, folder);
		if (filePath == null) return;
		#if (sys && !android)
		try
		{
			if (FileSystem.stat(filePath).size < CHART_DOM_KEEP_MAX) return;
		}
		catch (e:Dynamic) return;
		#end
		evictChartFromCache(jsonInput, folder);
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
			splashSkin: song.splashSkin,
			format: song.format
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

	// Psych 1.0.4 谱面格式转换：把旧版（0.6/0.7 系，轨道列号 + mustHitSection 翻转语义）谱面
	// 转换成 psych_v1 格式（绝对列号：<4 玩家、>=4 对手），列号直接决定方向。
	// format 字段标记为 'psych_v1'/'psych_v1_convert' 的谱面（1.0.4 保存/转换产物）不再重复转换。
	static var legacyNoteTypes:Array<String> = ['', 'Alt Animation', 'Hey!', 'Hurt Note', 'GF Sing', 'No Animation'];
	public static function convertToPsychV1(songJson:Dynamic)
	{
		if(songJson.events == null) onLoadJson(songJson);

		var sectionsData:Array<SwagSection> = songJson.notes;
		if(sectionsData == null) return;

		for (section in sectionsData)
		{
			// sectionBeats 缺失/NaN 时补默认（1.0.4 兼容：旧谱面常用 lengthInSteps 代替）
			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if(Reflect.hasField(section, 'lengthInSteps')) Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				var gottaHitNote:Bool = (note[1] < 4) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % 4) + (gottaHitNote ? 0 : 4);

				// Week7 / 0.1-0.3 老谱面：noteType 是数字索引
				if(!Std.isOfType(note[3], String))
					note[3] = legacyNoteTypes[note[3]];
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
		// 谱面已解析且缓存未失效（mtime 不变）：数据是纯读的，从缓存深拷贝一份即可，
		// 避免重复读盘 + JSON 解析（42MB / 226 万音符级谱面，重复解析还会让后台线程长时间
		// 活过 LoadingState 生命周期，是"退出重进同曲闪退"的间接诱因）；语义与 loadFromJson 缓存命中一致
		var cachedHit:SwagSong = getCachedChart(chartCacheKey(filePath));
		if (cachedHit != null) return copySong(cachedHit);
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

		// Psych 1.0.4 谱面格式：format 为 psych_v1 的谱面列号已是绝对方向（<4 玩家 / >=4 对手），
		// 直接使用；旧版谱面（0.6/0.7 系轨道列号 + mustHitSection 翻转）转换后再用，
		// 否则 generateSong 的列号判定会把方向搞反（GF 段落/对手音符错乱、自定义 note 变普通）。
		var chartFmt:String = songJson.format != null ? Std.string(songJson.format) : '';
		if(chartFmt.length < 1 || !chartFmt.startsWith('psych_v1'))
		{
			songJson.format = 'psych_v1_convert';
			convertToPsychV1(songJson);
		}

		// 后台线程解析完成后也写入缓存（纯数据深拷贝），下次再选同一首谱面直接命中、不再解析
		// 内存大关：大谱面（≥CHART_DOM_KEEP_MAX）绝不入缓存 —— 否则"淘汰→重开→重解析→再入缓存"
		// 会让完整 DOM 反复常驻，1GB 目标失效。大谱面重开直接走本函数快速重解析（约 1~2s）。
		var isLargeChart:Bool = false;
		#if (sys && !android)
		try { isLargeChart = FileSystem.stat(filePath).size >= CHART_DOM_KEEP_MAX; } catch (e:Dynamic) {}
		#end
		if (!isLargeChart)
			cacheChart(chartCacheKey(filePath), copySong(songJson));
		return songJson;
	}

	// 检查歌曲的人声文件是否存在（mod 目录优先）
	public static function voicesFileExists(songName:String, ?postfix:String = null):Bool
	{
		var songPath:String = Paths.formatToSongPath(songName);
		var vocalName:String = 'Voices' + (postfix != null && postfix.length > 0 ? '-' + postfix : '');
		#if MODS_ALLOWED
		if(FileSystem.exists(Paths.modsSounds('songs', songPath + '/' + vocalName))) return true;
		#end
		#if (sys && !android)
		return FileSystem.exists('assets/songs/' + songPath + '/' + vocalName + '.' + Paths.SOUND_EXT);
		#elseif android
		// 安卓：与 returnSound 完全同源的判定。
		// ① 外部 .meteoric 覆盖优先（AndroidStorage.root() 绝对路径，用户可替换音频）；
		// ② 'songs:' 库（APK 内置资产，returnSound 经 getLibraryPath/tryResolveAsset 实际命中）。
		// 不可用无前缀 Assets.exists/相对 FileSystem：「songs」音频注册在独立库，且运行时 cwd 不指向外部资产
		// → 恒 false → 所有歌的人声永不加载（整首无人声、且无 MISSING 日志的根因）。
		var relPath:String = 'assets/songs/' + songPath + '/' + vocalName + '.' + Paths.SOUND_EXT;
		if (FileSystem.exists(backend.AndroidStorage.root() + '/' + relPath)) return true;
		return lime.utils.Assets.exists('songs:' + relPath, SOUND) || lime.utils.Assets.exists(relPath, SOUND);
		#else
		return Assets.exists('assets/songs/' + songPath + '/' + vocalName + '.' + Paths.SOUND_EXT, SOUND);
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

	// ===== 大谱面快速解析（零 DOM）：直接字节扫描 sectionNotes 数字矩阵 =====
	// 用于 42MB / 2.26M 音符级谱面：haxe.Json/TJSON 会把每颗音符做成对象树（1.5-2GB 峰值），
	// 本路径只产出引擎需要的扁平结构，解析耗时/内存下降 1-2 个数量级。失败返回 null 走通用解析。
	#if sys
	static function fastNumAt(text:String, pos:Int):Float
	{
		var start:Int = pos;
		while (pos < text.length)
		{
			var c:Int = text.charCodeAt(pos);
			if ((c >= 48 && c <= 57) || c == 45 || c == 46 || c == 43 || c == 101 || c == 69) pos++;
			else break;
		}
		if (pos <= start) return 0;
		return Std.parseFloat(text.substr(start, pos - start));
	}

	static function fastStrAt(text:String, pos:Int):String
	{
		if (pos >= text.length || text.charAt(pos) != '"') return null;
		pos++;
		var start:Int = pos;
		while (pos < text.length)
		{
			var c:String = text.charAt(pos);
			if (c == '\\') { pos++; continue; }
			if (c == '"') break;
			pos++;
		}
		return text.substr(start, pos - start);
	}

	// 字符串读取结束位置（越过闭合引号）
	static function fastStrAtEnd(text:String, pos:Int):Int
	{
		if (pos >= text.length || text.charAt(pos) != '"') return pos;
		pos++;
		while (pos < text.length)
		{
			var c:String = text.charAt(pos);
			if (c == '\\') { pos++; continue; }
			if (c == '"') return pos + 1;
			pos++;
		}
		return pos;
	}

	static inline function fastSkip(text:String, pos:Int):Int
	{
		while (pos < text.length)
		{
			var c:Int = text.charCodeAt(pos);
			if (c == 32 || c == 10 || c == 13 || c == 9 || c == 44) pos++;
			else break;
		}
		return pos;
	}

	static function fastValAfter(text:String, key:String, pos:Int):Int
	{
		var idx:Int = text.indexOf('"' + key + '"', pos);
		if (idx < 0) return -1;
		idx = text.indexOf(':', idx);
		if (idx < 0) return -1;
		return fastSkip(text, idx + 1);
	}

	static function fastScanSectionNotes(secText:String):Array<Dynamic>
	{
		var arr:Array<Dynamic> = [];
		var mustHit:Bool = fastReadBoolAfter(secText, 'mustHitSection', true);
		var idx:Int = fastValAfter(secText, 'sectionNotes', 0);
		if (idx < 0 || idx >= secText.length || secText.charAt(idx) != '[') return arr;
		var len:Int = secText.length;
		var pos:Int = idx + 1;
		var guard:Int = 0;
		while (pos < len && guard < 3000000)
		{
			guard++;
			pos = fastSkip(secText, pos);
			if (pos >= len || secText.charAt(pos) == ']') break;
			if (secText.charAt(pos) != '[') { pos++; continue; }
			pos++;
			// 类型化 4 槽（t/d/s/typeCode）：避免 2.26M 动态盒装数组的 ~1GB 内存
			var note:Array<Float> = [0, 0, 0, 0];
			var slot:Int = 0;
			for (f in 0...4)
			{
				pos = fastSkip(secText, pos);
				if (pos >= len) break;
				var c:String = secText.charAt(pos);
				if (c == '"')
				{
					var sv:String = fastStrAt(secText, pos);
					// 类型字符串映射为 legacy 数字码（0=空；1-5=默认类型表；未知类型→回退解析）
					var tc:Float = 0;
					if (sv == 'Alt Animation') tc = 1;
					else if (sv == 'Hey!') tc = 2;
					else if (sv == 'Hurt Note') tc = 3;
					else if (sv == 'GF Sing') tc = 4;
					else if (sv == 'No Animation') tc = 5;
					else throw 'unknown noteType: ' + sv;
					note[slot] = tc;
					pos = fastSkip(secText, fastStrAtEnd(secText, pos));
				}
				else if (c >= '0' && c <= '9' || c == '-' || c == '.')
				{
					note[slot] = fastNumAt(secText, pos);
					// 数字读取后必须推进 pos（fastNumAt 是纯函数；否则同位置重复读，整行错位）
					while (pos < len)
					{
						var c2:Int = secText.charCodeAt(pos);
						if ((c2 >= 48 && c2 <= 57) || c2 == 45 || c2 == 46 || c2 == 43 || c2 == 101 || c2 == 69) pos++;
						else break;
					}
					pos = fastSkip(secText, pos);
					if (slot == 1)
					{
						// 列转换（与 convertToPsychV1 一致）：<4 且 mustHitSection → 玩家(0-3)；否则对手(4-7)
						var colR:Float = note[1];
						if (colR != colR) colR = 0;
						var colI:Int = Std.int(colR) % 4;
						var gottaHit:Bool = (Std.int(colR) < 4) ? mustHit : !mustHit;
						note[1] = colI + (gottaHit ? 0 : 4);
					}
				}
				else
				{
					// null / 未知字段：跳到下一个逗号或 ]（否则整行错位，后续音符全部丢失）
					while (pos < len && secText.charAt(pos) != ',' && secText.charAt(pos) != ']') pos++;
					pos = fastSkip(secText, pos);
					continue;
				}
				slot++;
				if (pos < len && secText.charAt(pos) == ']') { pos++; break; }
			}
			arr.push(note);
		}
		return arr;
	}

	// 大括号深度匹配（跳过字符串与转义）
	static function fastFindObjEnd(text:String, start:Int):Int
	{
		var depth:Int = 0;
		var inStr:Bool = false;
		var i:Int = start;
		while (i < text.length)
		{
			var c:String = text.charAt(i);
			if (inStr)
			{
				if (c == '\\') { i++; }
				else if (c == '"') inStr = false;
			}
			else
			{
				if (c == '"') inStr = true;
				else if (c == '{') depth++;
				else if (c == '}') { depth--; if (depth == 0) return i; }
			}
			i++;
		}
		return -1;
	}

	static function fastParseSong(rawJson:String):SwagSong
	{
		var song:Dynamic = {};
		// 元数据必须从"歌对象内部"读取：外层信封也是 "song" 键（{"song":{...}}），
		// 直接匹配会把 { 当字符串读 → 歌名为空/角色错乱
		var inSong:Int = 0;
		var envIdx:Int = rawJson.indexOf('"song"');
		if (envIdx >= 0)
		{
			var braceIdx:Int = rawJson.indexOf('{', envIdx);
			if (braceIdx >= 0) inSong = braceIdx + 1;
		}
		Reflect.setField(song, 'song', fastReadStringAfter2(rawJson, 'song', '', inSong));
		Reflect.setField(song, 'bpm', fastReadNumberAfter2(rawJson, 'bpm', 120.0, inSong));
		Reflect.setField(song, 'speed', fastReadNumberAfter2(rawJson, 'speed', 1.0, inSong));
		Reflect.setField(song, 'player1', fastReadStringAfter2(rawJson, 'player1', 'bf', inSong));
		Reflect.setField(song, 'player2', fastReadStringAfter2(rawJson, 'player2', 'dad', inSong));
		Reflect.setField(song, 'gfVersion', fastReadStringAfter2(rawJson, 'gfVersion', 'gf', inSong));
		Reflect.setField(song, 'stage', fastReadStringAfter2(rawJson, 'stage', 'stage', inSong));
		Reflect.setField(song, 'needsVoices', fastReadBoolAfter2(rawJson, 'needsVoices', true, inSong));
		Reflect.setField(song, 'validScore', fastReadBoolAfter2(rawJson, 'validScore', false, inSong));
		Reflect.setField(song, 'arrowSkin', fastReadStringAfter2(rawJson, 'arrowSkin', null, inSong));
		Reflect.setField(song, 'splashSkin', fastReadStringAfter2(rawJson, 'splashSkin', null, inSong));
		Reflect.setField(song, 'format', 'psych_v1'); // 列已内联转换，跳过 convertToPsychV1

		var notesIdx:Int = rawJson.indexOf('"notes"');
		if (notesIdx < 0) return null;
		var arrStart:Int = rawJson.indexOf('[', notesIdx);
		if (arrStart < 0) return null;

		var notes:Array<Dynamic> = [];
		var pos:Int = arrStart + 1;
		var len:Int = rawJson.length;
		var secCount:Int = 0;
		while (pos < len && secCount < 4096)
		{
			pos = fastSkip(rawJson, pos);
			if (pos >= len || rawJson.charAt(pos) == ']') break;
			if (rawJson.charAt(pos) != '{') { pos++; continue; }
			var secStart:Int = pos;
			var end:Int = fastFindObjEnd(rawJson, secStart);
			if (end < 0) break;
			var secText:String = rawJson.substr(secStart, end - secStart + 1);
			var sec:SwagSection = {
				sectionNotes: fastScanSectionNotes(secText),
				sectionBeats: fastReadNumberAfter(secText, 'sectionBeats', 4),
				typeOfSection: 0,
				mustHitSection: fastReadBoolAfter(secText, 'mustHitSection', true),
				gfSection: fastReadBoolAfter(secText, 'gfSection', false),
				bpm: fastReadNumberAfter(secText, 'bpm', 0),
				changeBPM: fastReadBoolAfter(secText, 'changeBPM', false),
				altAnim: fastReadBoolAfter(secText, 'altAnim', false)
			};
			notes.push(sec);
			secCount++;
			pos = end + 1;
		}
		Reflect.setField(song, 'notes', notes);

		// 自检：大谱面 18 字节/音符级密度，解析总数远低于期望视为解析失败 → 回退通用路径
		var totalParsed:Int = 0;
		for (n in notes)
		{
			var sn2:Array<Dynamic> = n.sectionNotes;
			if (sn2 != null) totalParsed += sn2.length;
		}
		trace('[FASTPARSE] sections=' + notes.length + ' notes=' + totalParsed + ' rawLen=' + rawJson.length);
		if (rawJson.length > 4000000 && totalParsed < Std.int(rawJson.length / 60))
			throw 'fast parse too small: ' + totalParsed;

		// events：量小，取子串用 haxe.Json（避免手写完整事件解析）
		var evIdx:Int = rawJson.indexOf('"events"');
		if (evIdx >= 0)
		{
			var evArrStart:Int = rawJson.indexOf('[', evIdx);
			if (evArrStart >= 0)
			{
				var evEnd:Int = fastFindObjEnd(rawJson, evArrStart); // 数组内对象深度匹配
				var evEnd2:Int = rawJson.indexOf(']', evArrStart);
				var evText:String = null;
				if (evEnd2 > evArrStart) evText = rawJson.substr(evArrStart, evEnd2 - evArrStart + 1);
				try
				{
					if (evText != null) Reflect.setField(song, 'events', haxe.Json.parse(evText));
				}
				catch (e:Dynamic) {}
			}
		}
		if (!Reflect.hasField(song, 'events')) Reflect.setField(song, 'events', []);

		return cast song;
	}

	static function fastReadNumberAfter2(text:String, key:String, fallback:Float, from:Int):Float
	{
		var i:Int = fastValAfter(text, key, from);
		if (i < 0) return fallback;
		if (i < text.length && (text.charAt(i) >= '0' && text.charAt(i) <= '9' || text.charAt(i) == '-' || text.charAt(i) == '.'))
			return fastNumAt(text, i);
		return fallback;
	}

	static function fastReadNumberAfter(text:String, key:String, fallback:Float):Float
	{
		var i:Int = fastValAfter(text, key, 0);
		if (i < 0) return fallback;
		if (i < text.length && (text.charAt(i) >= '0' && text.charAt(i) <= '9' || text.charAt(i) == '-' || text.charAt(i) == '.'))
			return fastNumAt(text, i);
		return fallback;
	}

	static function fastReadBoolAfter2(text:String, key:String, fallback:Bool, from:Int):Bool
	{
		var i:Int = fastValAfter(text, key, from);
		if (i < 0) return fallback;
		if (text.substr(i, 4) == 'true') return true;
		if (text.substr(i, 5) == 'false') return false;
		return fallback;
	}

	static function fastReadStringAfter2(text:String, key:String, fallback:String, from:Int):String
	{
		var i:Int = fastValAfter(text, key, from);
		if (i < 0) return fallback;
		if (i < text.length && text.charAt(i) == '"') return fastStrAt(text, i);
		return fallback;
	}

	static function fastReadBoolAfter(text:String, key:String, fallback:Bool):Bool
	{
		var i:Int = fastValAfter(text, key, 0);
		if (i < 0) return fallback;
		if (text.substr(i, 4) == 'true') return true;
		if (text.substr(i, 5) == 'false') return false;
		return fallback;
	}

	static function fastReadStringAfter(text:String, key:String, fallback:String):String
	{
		var i:Int = fastValAfter(text, key, 0);
		if (i < 0) return fallback;
		if (i < text.length && text.charAt(i) == '"') return fastStrAt(text, i);
		return fallback;
	}
	#end

	public static function parseJSONshit(rawJson:String):SwagSong
	{
		var songJson:Dynamic = null;
		// 快路径：自定义紧凑扫描器（仅 >4MB 大谱面，零 DOM 分配；
		// 小谱面保持通用解析，避免边角回归）。失败自动回退通用路径。
		#if sys
		if (rawJson.length > 4000000)
		{
			try
			{
				var fast:SwagSong = fastParseSong(rawJson);
				if (fast != null)
					return fast;
			}
			catch (e:Dynamic) {}
		}
		#end
		try
		{
			var parsed:Dynamic = haxe.Json.parse(rawJson);
			songJson = Reflect.field(parsed, 'song');
			// 旧格式 chart（Psych 0.6 系 / 部分模组）：歌曲元数据在顶层，
			// "song" 字段只是歌名 String —— 此时直接用整个 JSON 作为歌曲对象，
			// 否则后续 onLoadJson 对 String 做字段赋值会报 "Invalid field: gfVersion"
			if (songJson == null || Std.isOfType(songJson, String))
				songJson = parsed;
		}
		catch(e:Dynamic)
		{
			// 极少数旧谱面带注释/非标准 JSON：回退到 tjson 兼容解析
			try
			{
				var parsed2:Dynamic = TJSON.parse(rawJson);
				songJson = Reflect.field(parsed2, 'song');
				if (songJson == null || Std.isOfType(songJson, String))
					songJson = parsed2;
			}
			catch(e2:Dynamic) {}
		}
		return cast songJson;
	}
}
