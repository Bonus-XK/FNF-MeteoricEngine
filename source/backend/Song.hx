package backend;

import tjson.TJSON;
import lime.utils.Assets;
import openfl.utils.AssetType;

#if sys
import sys.io.File;
import sys.FileSystem;
import sys.io.FileInput;
#end

import backend.Section;
import backend.PerfProbe;

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

	// ===== Extra Keys：每谱面声明键数（1~12，缺省 4 = 完全旧行为）=====
	// 列号协议（psych_v1 泛化）：绝对列号 col < keys = 玩家、>= keys = 对手、lane = col % keys。
	@:optional var keys:Int;

	// ===== 超大字谱面（packed 路径）专用 =====
	// 音符级流式解析产出：packedNotes 承载**已合并**的音符簇（PackedChart），
	// 此时 sectionNotes 为空数组。PlayState.buildChartNotes 检测到 packedNotes
	// 非空时走 packed 分支，**不再重复合并**。
	// 内存特性：驻留量与音符总数无关，只随「簇数 + 簇内 offs 总数」增长。
	//   实测 200 万音符（880 空 + 1 巨型 section）→ 138MB；旧路径 → 6.9GB 失败。
	@:optional var packedNotes:Array<PackedChart>;
	@:optional var packedTotalNotes:Int;
	@:optional var packedSectionCount:Int;
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
			format: song.format,
			keys: song.keys // Extra Keys：深拷贝必须带上键数，否则缓存/重开路径丢 keys → 退回 4K 且解码错乱
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

		// Extra Keys：旧格式谱面按声明键数泛化（旧引擎谱面只会是 4K，keys 缺省 → 行为不变）
		var chartKeys:Int = ExtraKeys.resolveKeys(songJson.keys);

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
				var gottaHitNote:Bool = (note[1] < chartKeys) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % chartKeys) + (gottaHitNote ? 0 : chartKeys);

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
	/**
	 * 缓存键种子。必须由**写入与读取两侧用同一算法**得出，否则键不同 → 永远不命中。
	 * （开发期真实踩过：写入用歌名、读取用 'parts'，导致缓存写了但读不到。）
	 */
	static function cacheSeedFor(jsonInput:String):String
	{
		return (jsonInput != null) ? jsonInput : '';
	}

	/** 谱面名是否是 Parts 组合难度（"song-parts"，大小写不敏感） */
	public static function isPartsChartName(jsonInput:String):Bool
	{
		if (jsonInput == null) return false;
		return Difficulty.isPartsDifficulty(jsonInput.substr(jsonInput.lastIndexOf('-') + 1));
	}

	public static function resolveChartPath(jsonInput:String, ?folder:String):String
	{
		// 多 Part 组合难度：本体文件不存在，用**第一个 Part** 的真实路径作为
		// 「存在性凭证」，让选歌流程能正常进入。
		// 两种形态：① "song-1+2+3" 显式组合 ② "song-parts" 枚举全部 Part。
		if (jsonInput != null && (jsonInput.indexOf('+') >= 0 || isPartsChartName(jsonInput)))
		{
			var comboPaths:Array<String> = resolvePartPaths(jsonInput, folder);
			if (comboPaths != null)
			{
				for (cp in comboPaths)
					if (cp != null && FileSystem.exists(cp)) return cp;
				return null;
			}
			return null;
		}
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

		// ===== 音符级流式解析（超大字谱面专用，>= STREAM_CHART_MIN 字节）=====
		// 旧路径（File.getContent + fastParseSong）在这类谱面上必崩：
		//   ① 整份 JSON 读成单个 String（1.29GB → hxcpp 上 ~2.6GB UTF-16 连续驻留）
		//   ② 每颗音符变成一个 Array<Float>（5900 万个 → ~6.9GB）
		//   ③ 实测该谱结构为 880 个空 section + 1 个含全部音符的巨型 section，
		//      fastParseSong 的 fastFindObjEnd + substr 会试图切出 1.28GB 的子串
		// 实测证据（同构样本：880 空 + 1 巨型 / 200 万音符）：
		//   旧路径 → 6.9GB 失败；新路径 → 138MB 峰值，音符数与小节数逐项精确。
		//
		// 任何异常一律 throw，由本函数回退到旧整读路径（绝不静默降级）。
		#if (sys && !android)
		try
		{
			var sz:Int = 0;
			try { sz = FileSystem.stat(filePath).size; } catch (eStat:Dynamic) { sz = 0; }
			// 调试开关：METEORIC_NO_PACKED=1 强制走旧整读路径（用于 A/B 对照定位回归）
			var packedDisabled:Bool = false;
			try { packedDisabled = (Sys.getEnv("METEORIC_NO_PACKED") == "1"); } catch (eEnv:Dynamic) {}
			if (packedDisabled) trace('[PACKEDCHART] disabled by METEORIC_NO_PACKED');
			if (sz >= STREAM_CHART_MIN && !packedDisabled)
			{
				var packedSong:SwagSong = loadPackedChart(filePath);
				if (packedSong != null) return packedSong;
			}
		}
		catch (eStream:Dynamic)
		{
			trace('[PACKEDCHART] failed, fallback to full read: ' + Std.string(eStream));
		}
		#end

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
		// ===== 多 Part 组合难度（jsonInput 含 '+'）=====
		// 例如 stupid-griefer-1+2+3：同时叠加三个 Part 的音符。
		// 只走 packed 流式路径（小谱面的合并需物化 sectionNotes，暂不支持组合）。
		if (jsonInput != null && (jsonInput.indexOf('+') >= 0 || isPartsChartName(jsonInput)))
		{
			var partPaths:Array<String> = resolvePartPaths(jsonInput, folder);
			trace('[COMBO] jsonInput=' + jsonInput + ' folder=' + Std.string(folder)
				+ ' resolved=' + (partPaths == null ? "null" : Std.string(partPaths.length) + " paths"));
			if (partPaths != null)
			{
				for (pp in partPaths)
					trace('[COMBO]   part -> ' + pp + (FileSystem.exists(pp) ? " OK" : " MISSING"));
				#if (sys && !android)
				try
				{
					// 统一走 loadCombo：先查磁盘簇缓存（partsCache），未命中再全量扫描。
					// 修复重启/换难度/重开经 loadFromJson 时绕过缓存、重复全量扫描的问题。
					var combo:SwagSong = loadCombo(jsonInput, folder);
					if (combo != null) return combo;
				}
				catch (eCombo:Dynamic)
				{
					trace('[PACKEDPARTS] failed: ' + Std.string(eCombo));
				}
				#end
				// 回退：只加载第一个 Part，保证可玩（并明确记 trace，不静默）
				var firstPart:String = (partPaths.length > 0) ? partFileToJson(partPaths[0], jsonInput, folder) : null;
				if (firstPart != null)
				{
					trace('[PACKEDPARTS] combo path unavailable, loaded first part only: ' + firstPart);
					return loadFromJson(firstPart, folder);
				}
			}
		}

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

	// 分块流式解析的启用阈值（字节）。低于此值整读更划算（避免额外 IO 与状态机开销）。
	// 8MB = 原始整读峰值约 16MB UTF-16 + 解析产物；超过后分块的收益才明显。
	inline static var STREAM_CHART_MIN:Int = 8 * 1024 * 1024;

	// 单块读取字节数。16MB 兼顾 IO 次数与单块驻留：每块在 hxcpp 上是 ~32MB UTF-16，
	// 加上当前小节文本（最大小节实测 1.4MB）仍有充足余量。
	inline static var STREAM_CHUNK:Int = 16 * 1024 * 1024;

	// 跨块残留（pending）的字节上限。超过即判定为「深度匹配无法闭合」——
	// 必须 throw 回退整读路径，绝不能让它无限增长把内存吃光。
	// 正常最大小节实测 1.4MB，64MB 是 45 倍余量。
	inline static var STREAM_PENDING_MAX:Int = 64 * 1024 * 1024;
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

	static function fastScanSectionNotes(secText:String, chartKeys:Int):Array<Dynamic>
	{
		var arr:Array<Dynamic> = [];
		var mustHit:Bool = fastReadBoolAfter(secText, 'mustHitSection', true);
		// chartKeys <= 0 = psych_v1 绝对列号谱面：跳过列转换（col<keys 玩家 / %keys lane 已内联）
		var convert:Bool = chartKeys > 0;
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
					if (slot == 1 && convert)
					{
						// 列转换（与 convertToPsychV1 一致）：<keys 且 mustHitSection → 玩家(0..keys-1)；否则对手(keys..2keys-1)
						var colR:Float = note[1];
						if (colR != colR) colR = 0;
						var colI:Int = Std.int(colR) % chartKeys;
						if (colI < 0) colI += chartKeys;
						var gottaHit:Bool = (Std.int(colR) < chartKeys) ? mustHit : !mustHit;
						note[1] = colI + (gottaHit ? 0 : chartKeys);
					}
				}
				else
				{
					// null / 未知字段：跳到下一个逗号或 ]（否则整行错位，后续音符全部丢失）。
					// 【Obsolescence-spam 关键修复】4 字段谱面（[t,d,s,null]）中 null 走本分支时
					// 会停在音符自身的 ] 上——必须消费该 ] 并结束本音符；否则外层 while 把
					// 音符的 ] 误判为 section 结尾，整节只解析 1 颗 → 11,829,376 颗只剩 1,766,333
					// → 自检"fast parse too small" → 回退 haxe.Json 通用解析 → 对象树超
					// hxcpp GC 块数上限 → Memory exhausted / SIGILL 闪退。
					while (pos < len && secText.charAt(pos) != ',' && secText.charAt(pos) != ']') pos++;
					if (pos < len && secText.charAt(pos) == ']')
					{
						pos++;
						break; // 音符已结束（未知字段是末位），本音符未写入的槽位保持默认值
					}
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
		// Extra Keys：keys 缺省 = 4；psych_v1 谱面列号已是绝对方向，内联转换必须跳过
		// （否则 mustHit=false 段的玩家/对手列会被二次翻转——大谱面 psych_v1 的潜在缺陷，一并修正）
		var chartKeysRead:Int = ExtraKeys.resolveKeys(fastReadNumberAfter2(rawJson, 'keys', 4, inSong));
		var chartFmtFast:String = fastReadStringAfter2(rawJson, 'format', '', inSong);
		var chartIsV1:Bool = chartFmtFast != null && chartFmtFast.startsWith('psych_v1');
		Reflect.setField(song, 'keys', chartKeysRead);
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
				sectionNotes: fastScanSectionNotes(secText, chartIsV1 ? 0 : chartKeysRead),
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

	// ========================================================================
	// 超大字谱面：音符级流式 + 扫描即合并
	// ========================================================================
	// 产出 SwagSong，其中 packedNotes 字段承载**已合并**的音符簇，
	// sectionNotes 保持空数组。下游 buildChartNotes 走 packed 分支时**不再合并**。
	//
	// 元数据（song/bpm/speed/stage/...）仍需读取，这里只读文件头部
	// （实测头部 < 1KB），用一次小范围读取完成，不触碰整份 JSON。
	static function loadPackedChart(filePath:String):SwagSong
	{
		// 头部：只读前 8KB，元数据全在这里
		PerfProbe.mark('packed: begin scan ' + filePath);
		var head:String = readHead(filePath, 8192);
		if (head.length <= 0) return null;

		var song:Dynamic = {};
		var inS:Int = 0;
		var envIdx:Int = head.indexOf('"song"');
		if (envIdx >= 0)
		{
			var braceIdx:Int = head.indexOf('{', envIdx);
			if (braceIdx >= 0) inS = braceIdx + 1;
		}
		Reflect.setField(song, 'song', fastReadStringAfter2(head, 'song', '', inS));
		var bpm:Float = fastReadNumberAfter2(head, 'bpm', 120.0, inS);
		Reflect.setField(song, 'bpm', bpm);
		Reflect.setField(song, 'speed', fastReadNumberAfter2(head, 'speed', 1.0, inS));
		Reflect.setField(song, 'player1', fastReadStringAfter2(head, 'player1', 'bf', inS));
		Reflect.setField(song, 'player2', fastReadStringAfter2(head, 'player2', 'dad', inS));
		Reflect.setField(song, 'gfVersion', fastReadStringAfter2(head, 'gfVersion', 'gf', inS));
		Reflect.setField(song, 'stage', fastReadStringAfter2(head, 'stage', 'stage', inS));
		Reflect.setField(song, 'needsVoices', fastReadBoolAfter2(head, 'needsVoices', true, inS));
		Reflect.setField(song, 'validScore', fastReadBoolAfter2(head, 'validScore', false, inS));
		Reflect.setField(song, 'arrowSkin', fastReadStringAfter2(head, 'arrowSkin', null, inS));
		Reflect.setField(song, 'splashSkin', fastReadStringAfter2(head, 'splashSkin', null, inS));
		// Extra Keys：keys 缺省 = 4；psych_v1 谱面列号已是绝对方向（扫描器跳过列转换）
		var packedKeys:Int = ExtraKeys.resolveKeys(fastReadNumberAfter2(head, 'keys', 4, inS));
		var packedFmt:String = fastReadStringAfter2(head, 'format', '', inS);
		Reflect.setField(song, 'keys', packedKeys);
		Reflect.setField(song, 'format', 'psych_v1');

		// 合并参数与 buildChartNotes 同源（ClientPrefs 的堆叠合并设置）
		var ghostRange:Float = ClientPrefs.data.ghostRange;
		var doMerge:Bool = ClientPrefs.data.skipGhostNotes;
		var ghostDensity:Bool = ClientPrefs.data.ghostDensity;

		var keepLimit:Int = (ClientPrefs.data.boundedOffs) ? Std.int(ClientPrefs.data.boundedOffsKeep) : 0;
		var scanner:PackedScanner = new PackedScanner(ghostRange, ghostDensity, keepLimit);
		scanner.keys = packedKeys;
		scanner.absoluteCols = (packedFmt != null && packedFmt.startsWith('psych_v1'));
		var clusters:Array<PackedChart> = scanner.scan(filePath, bpm, doMerge);
		if (clusters == null) return null;
		PerfProbe.mark('packed: scan done');
		var st:Dynamic = scanner.stats();
		trace('[PACKEDCHART] raw=' + st.raw + ' merged=' + st.merged + ' clusters=' + st.clusters + ' sections=' + st.sections);

		// sectionNotes 置空：packed 路径不再需要逐音符 DOM。
		// ⚠ 下游按 sectionNotes 遍历的路径（currentChartSignature / Replay /
		//   ChartingState）对本谱面会得到「空」—— 已由 PlayState 的 packed 分支覆盖，
		//   且大谱面本就不支持编辑器打开。
		var notes:Array<SwagSection> = [];
		Reflect.setField(song, 'notes', notes);
		Reflect.setField(song, 'packedNotes', clusters);
		Reflect.setField(song, 'packedTotalNotes', st.totalNotes);
		Reflect.setField(song, 'packedSectionCount', st.sections);
		Reflect.setField(song, 'events', []);

		// 自检：解析数明显偏小视为失败（异常谱面回退整读）
		if (st.raw <= 0) return null;
		return cast song;
	}

	// ========================================================================
	// 多 Part 叠加：stupid-griefer-1+2+3 这类「组合难度」
	// ========================================================================
	// 语义（与用户确认一致）：
	//   ① 同时叠加 —— 所有 Part 的音符出现在同 4 条轨道上
	//   ② 同刻同轨两颗算 2 —— 因为**共用一个合并器**，不同 Part 的同刻同轨音符
	//      会并进同一个簇并累加 density，计分天然正确（若各 Part 各自合并再拼接则做不到）
	//   ③ Part 数量不设上限（有多少合多少）
	//
	// 元数据（bpm/speed/stage/characters）取**第一个 Part**，其余 Part 仅提供音符；
	// 若各 Part 的 bpm/stage 不一致会记 trace 警告（不阻断）。
	/**
	 * 多 Part 组合难度入口（供 LoadingState 调用）。
	 * 返回 null = 不是组合难度，或组合加载不可用（调用方应退回单谱路径）。
	 */
	public static function loadCombo(jsonInput:String, ?folder:String):SwagSong
	{
		if (jsonInput == null) return null;
		if (jsonInput.indexOf('+') < 0 && !isPartsChartName(jsonInput)) return null;
		var partPaths:Array<String> = resolvePartPaths(jsonInput, folder);
		trace('[COMBO] loadCombo jsonInput=' + jsonInput + ' folder=' + Std.string(folder)
			+ ' resolved=' + (partPaths == null ? "null" : Std.string(partPaths.length)));
		if (partPaths == null) return null;
		// 【内存遥测】组合谱（36 亿级）加载自动武装 PerfProbe：
		// 每个 mark 自带 GC 堆量（mem=）与 OS 工作集（rss=），加载曲线落盘 crash/perf_probe.txt。
		// 这是唯一武装入口：普通曲目与菜单不产生任何打点开销。
		PerfProbe.arm('combo:' + jsonInput, Std.string(partPaths.length));
		#if (sys && !android)
		// ---- 先查磁盘缓存：命中就完全跳过扫描（79GB 原始数据 → 几十 MB 簇缓存）----
		if (ClientPrefs.data.partsCache)
		{
			var ck:String = PackedCache.keyForParts(partPaths, cacheSeedFor(jsonInput));
			if (ck != null)
			{
				PerfProbe.mark('parts: cache probe ' + ck);
				var hit:Array<PackedChart> = PackedCache.load(ck, partPaths.length);
				// 缓存键不含合并参数：设置改过就必须重扫，否则计分/视觉会静默沿用旧簇。
				var cacheGhostRange:Float = ClientPrefs.data.ghostRange;
				var cacheGhostDensity:Bool = ClientPrefs.data.ghostDensity;
				var cacheKeep:Int = ClientPrefs.data.boundedOffs ? Std.int(ClientPrefs.data.boundedOffsKeep) : 0;
				var cacheDoMerge:Bool = ClientPrefs.data.skipGhostNotes;
				if (hit != null && !PackedCache.metaMatches(PackedCache.lastMeta, partPaths.length,
					cacheGhostRange, cacheGhostDensity, cacheKeep, cacheDoMerge))
				{
					trace('[PACKEDPARTS] CACHE STALE settings changed (ghostRange=' + cacheGhostRange
						+ ' ghostDensity=' + cacheGhostDensity + ' keep=' + cacheKeep
						+ ' merge=' + cacheDoMerge + '); rescan');
					hit = null;
				}
				if (hit != null)
				{
					trace('[PACKEDPARTS] CACHE HIT parts=' + partPaths.length + ' clusters=' + hit.length);
					var songCached:Dynamic = {};
					// 元数据仍从第一个 Part 的头部读（轻量，几 KB）
					var headC:String = readHead(partPaths[0], 8192);
					if (headC == null || headC.length <= 0) return null;
					var inSC:Int = 0;
					var evC:Int = headC.indexOf('"song"');
					if (evC >= 0)
					{
						var brC:Int = headC.indexOf('{', evC);
						if (brC >= 0) inSC = brC + 1;
					}
					Reflect.setField(songCached, 'song', fastReadStringAfter2(headC, 'song', '', inSC));
					Reflect.setField(songCached, 'bpm', fastReadNumberAfter2(headC, 'bpm', 120.0, inSC));
					Reflect.setField(songCached, 'speed', fastReadNumberAfter2(headC, 'speed', 1.0, inSC));
					Reflect.setField(songCached, 'player1', fastReadStringAfter2(headC, 'player1', 'bf', inSC));
					Reflect.setField(songCached, 'player2', fastReadStringAfter2(headC, 'player2', 'dad', inSC));
					Reflect.setField(songCached, 'gfVersion', fastReadStringAfter2(headC, 'gfVersion', 'gf', inSC));
					Reflect.setField(songCached, 'stage', fastReadStringAfter2(headC, 'stage', 'stage', inSC));
					Reflect.setField(songCached, 'needsVoices', fastReadBoolAfter2(headC, 'needsVoices', true, inSC));
					Reflect.setField(songCached, 'arrowSkin', fastReadStringAfter2(headC, 'arrowSkin', null, inSC));
					Reflect.setField(songCached, 'splashSkin', fastReadStringAfter2(headC, 'splashSkin', null, inSC));
					Reflect.setField(songCached, 'keys', ExtraKeys.resolveKeys(fastReadNumberAfter2(headC, 'keys', 4, inSC)));
					Reflect.setField(songCached, 'format', 'psych_v1');
					// 同 PackedScanner：66 Part 的 mustHit 总数可达 ~19.2 亿，逼近 Int32 上限，
					// 用 Float 累加再夹到 Int 范围，避免夹到负数（HUD/判分都依赖它为正）。
					var totF:Float = 0;
					for (c in hit) if (c.mustHit) totF += c.density;
					var tot:Int = (totF > 2147483000) ? 2147483000 : Std.int(totF);
					Reflect.setField(songCached, 'notes', []);
					Reflect.setField(songCached, 'packedNotes', hit);
					Reflect.setField(songCached, 'packedTotalNotes', tot);
					// ⚠ 缓存命中路径原先**漏了 packedSectionCount**（实测 trace 里 sections=-1），
					//   而扫描路径是设置了的 —— 同一首歌两条路径字段集不一致。
					//   从缓存 meta 的 sections 补回来。
					Reflect.setField(songCached, 'packedSectionCount',
						(PackedCache.lastMeta != null && PackedCache.lastMeta.sections != null) ? Std.int(PackedCache.lastMeta.sections) : hit.length);
					Reflect.setField(songCached, 'packedPartCount', partPaths.length);
					Reflect.setField(songCached, 'events', []);
					StageData.loadDirectory(songCached);
					return cast songCached;
				}
			}
		}
		try
		{
			var combo:SwagSong = loadPackedParts(partPaths, jsonInput);
			if (combo != null)
			{
				if (jsonInput != 'events') StageData.loadDirectory(combo);
				return combo;
			}
		}
		catch (e:Dynamic)
		{
			trace('[COMBO] failed: ' + Std.string(e));
		}
		#end
		return null;
	}

	static function loadPackedParts(filePaths:Array<String>, jsonInput:String):SwagSong
	{
		if (filePaths == null || filePaths.length == 0) return null;

		var head:String = readHead(filePaths[0], 8192);
		if (head == null || head.length <= 0) return null;

		var song:Dynamic = {};
		var inS:Int = 0;
		var envIdx:Int = head.indexOf('"song"');
		if (envIdx >= 0)
		{
			var braceIdx:Int = head.indexOf('{', envIdx);
			if (braceIdx >= 0) inS = braceIdx + 1;
		}
		Reflect.setField(song, 'song', fastReadStringAfter2(head, 'song', '', inS));
		var bpm:Float = fastReadNumberAfter2(head, 'bpm', 120.0, inS);
		Reflect.setField(song, 'bpm', bpm);
		Reflect.setField(song, 'speed', fastReadNumberAfter2(head, 'speed', 1.0, inS));
		Reflect.setField(song, 'player1', fastReadStringAfter2(head, 'player1', 'bf', inS));
		Reflect.setField(song, 'player2', fastReadStringAfter2(head, 'player2', 'dad', inS));
		Reflect.setField(song, 'gfVersion', fastReadStringAfter2(head, 'gfVersion', 'gf', inS));
		Reflect.setField(song, 'stage', fastReadStringAfter2(head, 'stage', 'stage', inS));
		Reflect.setField(song, 'needsVoices', fastReadBoolAfter2(head, 'needsVoices', true, inS));
		Reflect.setField(song, 'validScore', fastReadBoolAfter2(head, 'validScore', false, inS));
		Reflect.setField(song, 'arrowSkin', fastReadStringAfter2(head, 'arrowSkin', null, inS));
		Reflect.setField(song, 'splashSkin', fastReadStringAfter2(head, 'splashSkin', null, inS));
		// Extra Keys：keys 缺省 = 4；psych_v1 谱面列号已是绝对方向（扫描器跳过列转换）
		var partsKeys:Int = ExtraKeys.resolveKeys(fastReadNumberAfter2(head, 'keys', 4, inS));
		var partsFmt:String = fastReadStringAfter2(head, 'format', '', inS);
		Reflect.setField(song, 'keys', partsKeys);
		Reflect.setField(song, 'format', 'psych_v1');

		var ghostRange:Float = ClientPrefs.data.ghostRange;
		var doMerge:Bool = ClientPrefs.data.skipGhostNotes;
		var ghostDensity:Bool = ClientPrefs.data.ghostDensity;
		var keepLimit:Int = (ClientPrefs.data.boundedOffs) ? Std.int(ClientPrefs.data.boundedOffsKeep) : 0;

		// 关键：一个 scanner 扫所有 Part —— 合并状态跨文件保持
		var scanner:PackedScanner = new PackedScanner(ghostRange, ghostDensity, keepLimit);
		scanner.keys = partsKeys;
		scanner.absoluteCols = (partsFmt != null && partsFmt.startsWith('psych_v1'));
		var t0:Float = Sys.time();
		var used:Int = 0;
		for (p in filePaths)
		{
			if (p == null || !FileSystem.exists(p)) continue;
			PerfProbe.mark('parts: scan begin ' + p);
			scanner.scanPart(p);
			used++;
			PerfProbe.mark('parts: scan done ' + p);
		}
		if (used <= 0) return null;

		var st:Dynamic = scanner.stats();
		trace('[PACKEDPARTS] parts=' + used + ' raw=' + st.raw + ' merged=' + st.merged + ' clusters=' + st.clusters
			+ ' totalNotes=' + st.totalNotes + ' elapsed=' + Std.string(Std.int(Sys.time() - t0)) + 's');

		var clusters:Array<PackedChart> = scanner.result();
		// 扫描完成后落盘：下次进同一组 Part 直接读缓存，跳过全部扫描（79GB → 几十 MB）
		var cacheKey:String = PackedCache.keyForParts(filePaths, cacheSeedFor(jsonInput));
		if (cacheKey != null)
		{
			PerfProbe.mark('parts: cache save begin');
			PackedCache.save(cacheKey, clusters, {
				parts: used,
				totalNotes: st.totalNotes,
				sections: st.sections,
				raw: st.raw,
				merged: st.merged,
				ghostRange: ghostRange,
				ghostDensity: ghostDensity,
				keep: keepLimit,
				merge: doMerge,
				version: 1
			});
			PerfProbe.mark('parts: cache save done');
		}

		Reflect.setField(song, 'notes', []);
		Reflect.setField(song, 'packedNotes', clusters);
		Reflect.setField(song, 'packedTotalNotes', st.totalNotes);
		Reflect.setField(song, 'packedSectionCount', st.sections);
		Reflect.setField(song, 'packedPartCount', used);
		Reflect.setField(song, 'events', []);
		// ⚠ 判空只看「是否真的读到过音符」，**不能看 rawCount**：
		//   rawCount 是音符总数，Parts 组合下轻松超过 Int32 上限（66 Part ≈ 38.5 亿），
		//   一旦溢出成负数，这里就会 return null，把已经扫好的组合谱**静默丢掉**，
		//   上层退回「只加载第一个 Part」—— 症状是加载极慢且 Note 数量看起来没变化。
		//   （实测 meta 里 raw=-448051906 就是这个坑的现场证据。）
		if (!scanner.sawAnyNote) return null;
		return cast song;
	}

	/**
	 * 把 `song-1+2+3` 解析成各 Part 的实际谱面路径列表。
	 * 命名规则：组合难度名 `A+B+C` → `<song>-A.json` / `<song>-B.json` / `<song>-C.json`
	 * （folder 与 song 名沿用调用方传入值）。
	 * 返回 null 表示不是组合难度（普通单谱）。
	 */
	static function resolvePartPaths(jsonInput:String, folder:String):Array<String>
	{
		if (jsonInput == null) return null;
		// Parts 形态没有 '+'，但同样是组合难度
		if (jsonInput.indexOf('+') < 0 && !isPartsChartName(jsonInput)) return null;
		var songBase:String = Paths.formatToSongPath(folder);
		var jsonName:String = Paths.formatToSongPath(jsonInput);
		// jsonName 形如 "stupid-griefer-1+2+3"：去掉最后一个 "-<组合>" 段
		var cut:Int = jsonName.lastIndexOf('-');
		if (cut <= 0) return null;
		var base:String = jsonName.substr(0, cut);          // stupid-griefer
		var combo:String = jsonName.substr(cut + 1);          // 1+2+3

		var parts:Array<String> = combo.split('+');

		// Parts 组合难度（"song-parts"）：枚举该歌 data/ 目录下的**全部** Part
		if (parts.length == 1 && parts[0].trim().toLowerCase() == 'parts')
			return enumerateAllPartPaths(base, folder);

		var paths:Array<String> = [];
		for (p in parts)
		{
			var t:String = p.trim();
			if (t.length == 0) continue;
			var rel:String = songBase + '/' + base + '-' + t + '.json';
			var resolved:String = resolveChartPath(base + '-' + t, folder);
			paths.push((resolved != null) ? resolved : rel);
		}
		if (paths.length < 2) return null; // 单个片段不算组合
		return paths;
	}

	/** Map 计数（Haxe 的 Map 没有公开 size，这里用显式计数避免 API 依赖） */
	static inline function foundCount(m:Map<String, Int>):Int
	{
		var n:Int = 0;
		for (_ in m.keys()) n++;
		return n;
	}

	/**
	 * 枚举 <base>-<数字>.json 的全部 Part（Parts 组合难度用）。
	 * 按文件名里的数字**数值序**排序 —— 纯字典序会把 10 排到 2 前面。
	 */
	static function enumerateAllPartPaths(base:String, folder:String):Array<String>
	{
		// ⚠ 必须用 base（歌曲名）而不是 folder（mod 目录名）拼 data 路径：
		//   实际布局是 mods/<mod名>/data/<歌曲名>/，用 mod 名会拼成
		//   data/<mod名>/ → 目录不存在 → 枚举返回 null → 加载静默失败。
		var songBase:String = Paths.formatToSongPath(base);
		var rel:String = 'data/' + songBase + '/';

		// ⚠ 不能用 modsJson(base) 反推目录：**本体文件（如 stupid-griefer.json）不存在**
		//   （只有 -1…-66），modFolders 会一路 fallthrough 到默认资源目录，路径全错。
		//
		// 候选根目录必须与 resolveChartPath 的解析链对齐，否则「别的玩家的分段谱」一律
		// 报「找不到 xxx-parts 谱面」。原实现只查了前两级：
		//   ① Mods.currentModDirectory   —— 只有当前正在加载的那个模组
		//   ② Mods.getGlobalMods()       —— 只有 pack.json 里 runsGlobally 的模组
		// 普通歌曲模组**两者都不满足**：它不 runsGlobally，且选曲前还没成为 currentModDirectory。
		// 补上：
		//   ③ Mods.getModDirectories()   —— 扫全部模组
		//   ④ Paths.mods(rel)            —— mods 根下的 data/（modFolders 的第三级兜底）
		//   ⑤ Paths.json(rel)            —— assets/data/（本体歌曲，resolveChartPath 的本体分支）
		var roots:Array<String> = [];
		var seen:Map<String, Bool> = new Map();
		function addRoot(r:String):Void
		{
			if (r == null || r.length == 0 || seen.exists(r)) return;
			seen.set(r, true);
			roots.push(r);
		}
		addRoot(Mods.currentModDirectory);
		for (m in Mods.getGlobalMods()) addRoot(m);
		#if MODS_ALLOWED
		for (m in Mods.getModDirectories()) addRoot(m);
		#end

		var prefix:String = base + '-';

		// 候选目录：先各根下的 data/<歌名>/（标准布局），再 data/ 根下（扁平布局，
		// 少数分段谱把 song-1.json 直接摊在 data/ 里）。扁平布局放在最后，避免抢在标准布局前面。
		var dirs:Array<String> = [];
		for (root in roots)
		{
			var d:String = Paths.mods(root + '/' + rel);
			if (FileSystem.exists(d)) dirs.push(d);
		}
		var modsFlat:String = Paths.mods('data/');
		if (FileSystem.exists(modsFlat)) dirs.push(modsFlat);
		#if (sys && !android)
		var assetDir:String = Paths.json(rel.substr(0, rel.length - 1));
		if (FileSystem.exists(assetDir)) dirs.push(assetDir);
		#end

		for (dir in dirs)
		{
			var found:Map<String, Int> = new Map();   // path → 数字序号
			for (f in FileSystem.readDirectory(dir))
			{
				if (f.indexOf(prefix) != 0 || !StringTools.endsWith(f, '.json')) continue;
				var numStr:String = f.substr(prefix.length, f.length - prefix.length - 5);
				var n:Null<Int> = Std.parseInt(numStr);
				if (n == null) continue;   // 非纯数字后缀（如 -easy）不算 Part
				found.set(dir + '/' + f, n);
			}
			if (foundCount(found) < 2) continue;

			var paths:Array<String> = [for (k in found.keys()) k];
			paths.sort(function(a:String, b:String):Int return found.get(a) - found.get(b));
			trace('[COMBO] enumerateAllPartPaths base=' + base + ' dir=' + dir + ' found=' + paths.length);
			return paths;
		}
		return null;
	}

	/** 把 Part 的实际文件路径还原成 loadFromJson 可用的 jsonInput（如 stupid-griefer-3） */
	static function partFileToJson(absPath:String, comboJson:String, folder:String):String
	{
		if (absPath == null) return null;
		var name:String = haxe.io.Path.extension(absPath) == null ? absPath : absPath.substr(0, absPath.lastIndexOf('.'));
		var slash:Int = name.lastIndexOf('/');
		if (slash >= 0) name = name.substr(slash + 1);
		// 组合名形如 stupid-griefer-1+2+3，取其中的歌名前缀再拼 Part 号
		var cut:Int = comboJson.lastIndexOf('-');
		var base:String = (cut > 0) ? comboJson.substr(0, cut) : comboJson;
		return name.startsWith(base) ? name : base + name.substr(base.length);
	}

	/** 只读文件开头 n 字节（不整读） */
	static function readHead(filePath:String, n:Int):String
	{
		try
		{
			var input:FileInput = File.read(filePath);
			if (input == null) return null;
			var total:Int = FileSystem.stat(filePath).size;
			var want:Int = (total < n) ? total : n;
			if (want <= 0) { input.close(); return null; }
			var b:haxe.io.Bytes = input.read(want);
			input.close();
			if (b == null) return null;
			return b.toString();
		}
		catch (e:Dynamic)
		{
			return null;
		}
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
