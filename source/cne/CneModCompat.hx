package cne;

#if (MODS_ALLOWED && sys)
import backend.ClientPrefs;
import backend.Mods;
import backend.Paths;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * 「CNE 模组兼容」——让 Codename Engine（CNE）格式的 mod 能在 Meteoric 里跑起来。
 *
 * 权威依据（按仓库内可查证的一手源码，不靠猜）：
 *  - CNE 资源布局：`CodenameEngine-main/source/funkin/backend/assets/Paths.hx`
 *      chart  = `songs/<song>/charts/[<variant>/]<difficulty>.json`
 *      inst   = `songs/<song>/song/Inst<suffix>[-<difficulty>].<ext>`
 *      vocals = `songs/<song>/song/Voices<suffix>[-<difficulty>].<ext>`
 *      meta   = `songs/<song>/meta.json`（bpm / difficulties / instSuffix / vocalsSuffix …）
 *      char   = `data/characters/<name>.xml`（Sparrow 图集 + `<anim>` 节点）
 *      week   = `data/weeks/weeks/<week>.xml` + `data/weeks/weeks.txt`
 *  - CNE 资源库：`funkin/backend/assets/ModsFolder.hx`（文件夹 / zip 都是 mod，zip 根级即 mod 根）
 *  - CNE→legacy 段结构：`funkin/backend/chart/FNFLegacyParser.hx`（mustHitSection 来自
 *    `Camera Movement` 事件的 strumLine 索引；note 方向由 strumLine type 决定）
 *
 * 输出语义（必须与 Meteoric 一致，勿想当然）：
 *  - 谱面一律产出 **psych_v1**：列号 `<4` = 玩家、`>=4` = 对手，`mustHitSection` 只管镜头；
 *    gf 段落里与 mustHitSection 同方向的列由 GF 演奏（`PlayState.hx:2156-2198`）。
 *    （CNE 自家 `FNFLegacyParser.encode` 产的是 0.6.x 老语义，直接照搬会方向翻转。）
 *  - 任何转换失败都返回 null，引擎退回“找不到资源”的既有行为，不抛异常。
 *
 * 开关：设置 → 编程 → 「CNE 模组兼容」（`ClientPrefs.data.cneModCompat`，默认关）。
 * 调试构建下 `METEORIC_CNE_MOD_FORCE=1` 可无视存档强制开启。
 */
class CneModCompat
{
	/** 缓存：`<mod>|<songKey>` → CNE songs/ 下的真实目录名（找不到记空串）。 */
	static var songDirCache:Map<String, String> = new Map();

	public static function isEnabled():Bool
	{
		#if meteoric_debug
		if (Sys.getEnv('METEORIC_CNE_MOD_FORCE') == '1') return true;
		#end
		return ClientPrefs.data != null && ClientPrefs.data.cneModCompat;
	}

	public static function log(msg:String):Void
	{
		var on:Bool = ClientPrefs.data != null && ClientPrefs.data.cneScriptLogs;
		#if meteoric_debug
		if (Sys.getEnv('METEORIC_CNE_MOD_FORCE') == '1' || Sys.getEnv('METEORIC_CNE_FORCE') == '1') on = true;
		#end
		if (on) Sys.println('[CNE-MOD] ' + msg);
	}

	// ==================== 歌曲目录定位 ====================

	/**
	 * CNE 的歌曲目录名保留空格（`songs/philly nice/`），而 Psych 侧一律格式化成
	 * `philly-nice`。这里扫描已启用 mod 的 `songs/`，用 `Paths.formatToSongPath` 归一化后匹配，
	 * 返回**真实目录名**。找不到返回 null（调用方退回格式化名）。
	 */
	public static function cneSongDir(songKey:String):String
	{
		if (songKey == null || songKey.length == 0) return null;

		var mod:String = (Mods.currentModDirectory != null) ? Mods.currentModDirectory : '';
		var cacheKey:String = mod + '|' + songKey;
		if (songDirCache.exists(cacheKey))
		{
			var cached:String = songDirCache.get(cacheKey);
			return (cached != null && cached.length > 0) ? cached : null;
		}

		var dirs:Array<String> = [];
		if (mod.length > 0) dirs.push(mod);
		for (m in Mods.getGlobalMods()) if (!dirs.contains(m)) dirs.push(m);
		dirs.push(''); // mods 根：`mods/songs/...` 这种全局资源写法

		for (d in dirs)
		{
			var found:String = songDirIn(d, songKey);
			if (found != null)
			{
				songDirCache.set(cacheKey, found);
				return found;
			}
		}

		songDirCache.set(cacheKey, '');
		return null;
	}

	/** 在指定 mod（空串 = mods 根）的 `songs/` 下按归一化曲名找真实目录名；找不到返回 null。 */
	public static function songDirIn(mod:String, songKey:String):String
	{
		if (songKey == null || songKey.length == 0) return null;
		var songsRoot:String = Paths.mods((mod != null && mod.length > 0 ? mod + '/' : '') + 'songs');
		if (!FileSystem.exists(songsRoot) || !FileSystem.isDirectory(songsRoot)) return null;

		var entries:Array<String> = null;
		try entries = FileSystem.readDirectory(songsRoot) catch (e:Dynamic) { entries = []; }
		for (entry in entries)
		{
			if (entry == null || entry.length == 0) continue;
			if (!FileSystem.isDirectory(songsRoot + '/' + entry)) continue;
			if (Paths.formatToSongPath(entry) == songKey) return entry;
		}
		return null;
	}

	/**
	 * 由 CNE 谱面路径反推曲名（`.../songs/<歌曲>/charts/[<variant>/]x.json` → `<歌曲>`）。
	 * CNE 的 `meta.json` 常常**没有** `name` 字段（只有 `displayName`），谱面里也可能没有内嵌 meta，
	 * 此时 Psych 侧 `SONG.song` 会退化成 "Unknown"，导致 `Paths.inst(SONG.song)`（音频）与回放/成绩
	 * 都按错误曲名查找 —— 所以必须用目录名兜底。
	 */
	public static function songNameFromChartPath(chartPath:String):String
	{
		if (chartPath == null || chartPath.length == 0) return null;
		var dir:String = Path.directory(chartPath);
		if (dir == null || dir.length == 0) return null;
		var base:String = Path.withoutDirectory(dir);
		var songDir:String = (base == 'charts') ? Path.directory(dir) : Path.directory(Path.directory(dir));
		var name:String = Path.withoutDirectory(songDir);
		return (name != null && name.length > 0) ? name : null;
	}

	/** mod 切换/重进选歌/Mod 列表刷新时清缓存（songDir 目录名缓存 + zip 暂存指纹校验）。 */
	public static function clearCaches():Void
	{
		songDirCache = new Map();
		CneZipStore.invalidate();
	}

	// ==================== 谱面 ====================

	/** CNE 谱面路径（mod 优先）；无则 null。jsonInput 形如 `song` / `song-hard`。 */
	public static function resolveChartPath(jsonInput:String, folder:String):String
	{
		if (!isEnabled() || jsonInput == null || jsonInput.length == 0) return null;

		var songKey:String = Paths.formatToSongPath((folder != null && folder.length > 0) ? folder : jsonInput);
		var difficulty:String = difficultyFromInput(jsonInput, folder);

		var songDirs:Array<String> = [];
		var real:String = cneSongDir(songKey);
		if (real != null) songDirs.push(real);
		if (!songDirs.contains(songKey)) songDirs.push(songKey);

		var diffs:Array<String> = [];
		if (difficulty != null && difficulty.length > 0)
		{
			diffs.push(difficulty);
			if (difficulty.toLowerCase() != difficulty) diffs.push(difficulty.toLowerCase());
		}
		// 刻意**不**回退到 normal：CNE 的 `Chart.parse` 在指定难度缺谱时直接报
		// "Chart for song ... was not found"；静默改用别的难度会让玩家玩到错误的谱面。

		for (sd in songDirs)
		{
			for (d in diffs)
			{
				var p:String = Paths.modFolders('songs/' + sd + '/charts/' + d + '.json');
				if (FileSystem.exists(p) && !FileSystem.isDirectory(p))
				{
					log('CNE chart: ' + p);
					return p;
				}
			}
		}
		return null;
	}

	/**
	 * 从 `jsonInput`（Psych 侧 `<song>` 或 `<song>-<difficulty>`）解析 CNE 难度名。
	 * Psych 默认难度不带后缀（`Difficulty.defaultDifficulty = 'Normal'`），CNE 默认难度为
	 * `Flags.DEFAULT_DIFFICULTY = 'normal'`，两者在此对齐。
	 */
	static function difficultyFromInput(jsonInput:String, folder:String):String
	{
		var fKey:String = Paths.formatToSongPath(folder != null ? folder : jsonInput);
		var jKey:String = Paths.formatToSongPath(jsonInput);
		if (folder == null || jKey == fKey) return 'normal';
		if (fKey.length > 0 && jKey.length > fKey.length + 1 && jKey.substr(0, fKey.length + 1) == fKey + '-')
			return jKey.substr(fKey.length + 1);
		return jKey; // 调用方直接传了难度名（如编谱器）
	}

	/** 由谱面路径回溯 CNE `meta.json`（`songs/<song>/charts/[<variant>/]x.json` → `songs/<song>/meta.json`）。 */
	public static function metaJsonForChart(chartPath:String):String
	{
		if (chartPath == null || chartPath.length == 0) return null;
		var dir:String = Path.directory(chartPath);
		if (dir == null || dir.length == 0) return null;

		var base:String = Path.withoutDirectory(dir);
		var songDir:String = (base == 'charts') ? Path.directory(dir) : Path.directory(Path.directory(dir));
		var metaPath:String = songDir + '/meta.json';
		if (!FileSystem.exists(metaPath)) return null;
		try return File.getContent(metaPath) catch (e:Dynamic) { return null; }
	}

	/** 读 `<CNE 歌曲目录>/meta.json`（`songKey` 为格式化后的曲名）。 */
	public static function metaJsonForSong(songKey:String):String
	{
		var dir:String = cneSongDir(songKey);
		if (dir == null) dir = songKey;
		var metaPath:String = Paths.modFolders('songs/' + dir + '/meta.json');
		if (!FileSystem.exists(metaPath)) return null;
		try return File.getContent(metaPath) catch (e:Dynamic) { return null; }
	}

	// ==================== 音频 ====================

	/**
	 * CNE 音频回退：`songs/<song>/song/Inst<suffix>[-<diff>]` / `Voices<suffix>[-<diff>]`。
	 * 只在 Psych 路径（`songs/<song>/Inst.ogg`）不存在时调用；只接管无 postfix 的
	 * `Inst` / `Voices`（Psych 的 `Voices-Player/-Opponent` 拆分人声由调用方自己回退）。
	 */
	public static function resolveCneSound(path:String, key:String):String
	{
		if (!isEnabled() || path != 'songs' || key == null) return null;

		var slash:Int = key.lastIndexOf('/');
		if (slash <= 0) return null;
		var file:String = key.substr(slash + 1);
		if (file != 'Inst' && file != 'Voices') return null;

		var songKey:String = key.substr(0, slash);
		var songDir:String = cneSongDir(songKey);
		if (songDir == null) songDir = songKey;

		var suffix:String = '';
		var meta:Dynamic = null;
		var metaRaw:String = metaJsonForSong(songKey);
		if (metaRaw != null)
		{
			try meta = haxe.Json.parse(metaRaw) catch (e:Dynamic) { meta = null; }
		}
		if (meta != null)
		{
			var f:Dynamic = (file == 'Inst') ? Reflect.field(meta, 'instSuffix') : Reflect.field(meta, 'vocalsSuffix');
			if (f != null) suffix = Std.string(f);
		}

		var diffs:Array<String> = [];
		var d:String = currentDifficulty();
		if (d != null && d.length > 0)
		{
			diffs.push(d.toLowerCase());
			if (d != d.toLowerCase()) diffs.push(d);
		}

		var names:Array<String> = [];
		for (dd in diffs) names.push(file + suffix + '-' + dd);
		names.push(file + suffix);
		if (suffix.length > 0)
		{
			for (dd in diffs) names.push(file + '-' + dd);
			names.push(file);
		}

		var exts:Array<String> = (Paths.SOUND_EXT == 'ogg') ? ['ogg', 'mp3'] : [Paths.SOUND_EXT];
		for (n in names)
		{
			for (ext in exts)
			{
				var p:String = Paths.modFolders('songs/' + songDir + '/song/' + n + '.' + ext);
				if (FileSystem.exists(p) && !FileSystem.isDirectory(p))
				{
					log('CNE audio: ' + p);
					return p;
				}
			}
		}
		return null;
	}

	static function currentDifficulty():String
	{
		try
		{
			return backend.Difficulty.getString();
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	// ==================== 人物 ====================

	/**
	 * CNE 人物 XML → Psych 人物 JSON 字符串（`data/characters/<name>.xml`）。
	 * 找不到或解析失败返回 null，`Character.hx` 再退回引擎默认人物。
	 * 映射依据：`CodenameEngine-main/source/funkin/game/Character.hx` +
	 * `funkin/backend/utils/XMLUtil.hx`（属性名 / anim 节点字段）。
	 */
	public static function characterJson(name:String):String
	{
		if (!isEnabled() || name == null || name.length == 0) return null;

		var xmlPath:String = Paths.modFolders('data/characters/' + name + '.xml');
		if (!FileSystem.exists(xmlPath)) return null;

		var raw:String = null;
		try raw = File.getContent(xmlPath) catch (e:Dynamic) { return null; }

		try
		{
			var xml:Xml = Xml.parse(raw).firstElement();
			if (xml == null || xml.nodeName != 'character') return null;

			var sprite:String = attr(xml, 'sprite');
			if (sprite == null || sprite.length == 0) sprite = name;
			var image:String = (sprite.indexOf('/') >= 0) ? sprite : 'characters/' + sprite;

			var icon:String = attr(xml, 'icon');
			if (icon == null || icon.length == 0) icon = name;

			var scaleV:Float = parseFloat(attr(xml, 'scale'), 1);
			var holdTime:Float = parseFloat(attr(xml, 'holdTime'), 4);
			var posX:Float = parseFloat(attr(xml, 'x'), 0);
			var posY:Float = parseFloat(attr(xml, 'y'), 0);
			var camX:Float = parseFloat(attr(xml, 'camx'), 0);
			var camY:Float = parseFloat(attr(xml, 'camy'), 0);
			var flipX:Bool = (attr(xml, 'flipX') == 'true');
			var antialiasing:Bool = (attr(xml, 'antialiasing') != 'false');
			var colors:Array<Int> = parseHexColor(attr(xml, 'color'));
			if (colors == null) colors = [255, 255, 255];

			var anims:Array<Dynamic> = [];
			for (node in xml.elements())
			{
				if (node.nodeName != 'anim') continue;
				var animName:String = attr(node, 'name');
				if (animName == null || animName.length == 0) continue;

				var prefix:String = attr(node, 'anim');
				if (prefix == null || prefix.length == 0) prefix = animName;

				var fps:Float = parseFloat(attr(node, 'fps'), 24);
				var loop:Bool = (attr(node, 'loop') == 'true');
				var offsets:Array<Int> = [
					Std.int(parseFloat(attr(node, 'x'), 0)),
					Std.int(parseFloat(attr(node, 'y'), 0))
				];
				anims.push({
					anim: animName,
					name: prefix,
					fps: Std.int(fps),
					loop: loop,
					indices: parseNumberRange(attr(node, 'indices')),
					offsets: offsets
				});
			}
			if (anims.length == 0) return null;

			var json:Dynamic = {
				animations: anims,
				image: image,
				scale: scaleV,
				sing_duration: holdTime,
				healthicon: icon,
				position: [posX, posY],
				camera_position: [camX, camY],
				flip_x: flipX,
				no_antialiasing: !antialiasing,
				healthbar_colors: colors,
				vocals_file: ''
			};
			log('CNE character: ' + xmlPath + ' → Psych JSON (' + anims.length + ' anims)');
			return haxe.Json.stringify(json);
		}
		catch (e:Dynamic)
		{
			log('CNE character parse failed (' + xmlPath + '): ' + Std.string(e));
			return null;
		}
	}

	// ==================== 周目 ====================

	/**
	 * 把某个 mod 的 CNE 周目（`data/weeks/weeks/*.xml`，顺序取 `data/weeks/weeks.txt`）
	 * 翻译成 Psych `WeekFile`，返回 `[{name, week}]`。失败/无周目返回空数组。
	 */
	public static function cneWeekFiles(mod:String):Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		if (!isEnabled() || mod == null || mod.length == 0) return out;

		var weeksDir:String = Paths.mods(mod + '/data/weeks/weeks');
		if (!FileSystem.exists(weeksDir) || !FileSystem.isDirectory(weeksDir)) return out;

		var names:Array<String> = [];
		var seen:Map<String, Bool> = new Map();
		var orderFile:String = Paths.mods(mod + '/data/weeks/weeks.txt');
		if (FileSystem.exists(orderFile))
		{
			var lines:Array<String> = null;
			try lines = backend.CoolUtil.coolTextFile(orderFile) catch (e:Dynamic) { lines = null; }
			if (lines != null)
			{
				for (line in lines)
				{
					var l:String = StringTools.trim(line);
					if (l.length == 0 || l.charAt(0) == '#') continue;
					if (seen.exists(l)) continue;
					seen.set(l, true);
					names.push(l);
				}
			}
		}

		var entries:Array<String> = null;
		try entries = FileSystem.readDirectory(weeksDir) catch (e:Dynamic) { entries = []; }
		for (f in entries)
		{
			var lower:String = f.toLowerCase();
			if (lower.length <= 4 || lower.substr(lower.length - 4) != '.xml') continue;
			var n:String = f.substr(0, f.length - 4);
			if (seen.exists(n)) continue;
			seen.set(n, true);
			names.push(n);
		}

		for (n in names)
		{
			var weekFile:Dynamic = parseWeekXml(Paths.mods(mod + '/data/weeks/weeks/' + n + '.xml'), n);
			if (weekFile != null) out.push({name: n, week: weekFile});
		}
		return out;
	}

	static function parseWeekXml(path:String, id:String):Dynamic
	{
		if (!FileSystem.exists(path)) return null;
		var raw:String = null;
		try raw = File.getContent(path) catch (e:Dynamic) { return null; }

		try
		{
			var xml:Xml = Xml.parse(raw).firstElement();
			if (xml == null || xml.nodeName != 'week') return null;

			var weekName:String = attr(xml, 'name');
			if (weekName == null || weekName.length == 0) return null;

			var chars:Array<String> = [];
			var charsAttr:String = attr(xml, 'chars');
			if (charsAttr != null)
			{
				for (c in charsAttr.split(','))
				{
					var t:String = StringTools.trim(c);
					chars.push((t == '' || t == 'none' || t == 'null') ? '' : t);
				}
			}
			while (chars.length < 3) chars.push('');

			var sprite:String = attr(xml, 'sprite');
			if (sprite == null) sprite = id;

			var colors:Array<Int> = parseHexColor(attr(xml, 'bgColor'));
			if (colors == null) colors = [146, 113, 253];

			var songs:Array<Dynamic> = [];
			var diffs:Array<String> = [];
			for (node in xml.elements())
			{
				if (node.nodeName == 'song')
				{
					var songName:String = childText(node);
					if (songName.length == 0) continue;
					songs.push([songName, (chars[1].length > 0 ? chars[1] : 'bf'), colors]);
				}
				else if (node.nodeName == 'difficulty')
				{
					var dn:String = attr(node, 'name');
					if (dn != null && dn.length > 0 && !diffs.contains(dn)) diffs.push(dn);
				}
			}
			if (songs.length == 0) return null;

			// Psych 的周目背景是 `images/menubackgrounds/menu_<weekBackground>.png`；
			// CNE 用 `images/menus/storymenu/weeks/<sprite>.png`。找不到对应图就用空串
			// （StoryMenuState 会隐藏背景），绝不拼一个不存在的贴图路径导致加载失败。
			var background:String = '';
			if (storyBackgroundExists(sprite)) background = sprite;

			var weekFile:Dynamic = {
				songs: songs,
				weekCharacters: chars,
				weekBackground: background,
				weekBefore: '',
				storyName: weekName,
				weekName: weekName,
				freeplayColor: colors,
				startUnlocked: true,
				hiddenUntilUnlocked: false,
				hideStoryMode: false,
				hideFreeplay: false,
				difficulties: diffs.join(',')
			};
			log('CNE week: ' + id + ' (' + songs.length + ' songs)');
			return weekFile;
		}
		catch (e:Dynamic)
		{
			log('CNE week parse failed (' + path + '): ' + Std.string(e));
			return null;
		}
	}

	static function storyBackgroundExists(sprite:String):Bool
	{
		if (sprite == null || sprite.length == 0) return false;
		var key:String = 'images/menubackgrounds/menu_' + sprite + '.png';
		if (FileSystem.exists(Paths.modFolders(key))) return true;
		return FileSystem.exists(Paths.getPreloadPath(key));
	}

	// ==================== Freeplay 曲目列表（无周目的 CNE mod） ====================

	/**
	 * 很多 CNE mod（例如 saturday_morning_alive）**没有周目 XML**，而是用
	 * `data/config/freeplaySonglist.txt`（旧路径 `data/freeplaySonglist.txt`）在 Freeplay 里列歌；
	 * 列表缺失时 CNE 直接扫 `songs/` 下含 `charts/` 的目录（`funkin/menus/FreeplayState.hx:461-490`）。
	 *
	 * Meteoric 的 Freeplay **完全由周目驱动**（`states/FreeplayState.hx:116-139`），所以这里把 CNE 的
	 * 曲目列表翻译成一个**仅 Freeplay 可见的合成周目**（`hideStoryMode = true`）：
	 *  - `songs[i]` = `[displayName, icon, [r,g,b]]`（meta.json 的 displayName / icon / color）；
	 *  - `difficulties` = 各曲 `meta.json` difficulties 的并集 —— 这是关键：SMA 只提供 `charts/hard.json`，
	 *    Freeplay 必须把难度列成 Hard，才能拼出 `-hard` 后缀命中 CNE 谱面；
	 *  - `folder = mod`，于是选中歌曲时 `Mods.currentModDirectory` 指向该 mod（谱面/音频/人物都从它取）。
	 */
	public static function cneFreeplayWeek(mod:String):Dynamic
	{
		if (!isEnabled() || mod == null || mod.length == 0) return null;

		var names:Array<String> = [];
		var listPath:String = null;
		for (key in ['data/config/freeplaySonglist.txt', 'data/freeplaySonglist.txt'])
		{
			var p:String = Paths.mods(mod + '/' + key);
			if (FileSystem.exists(p) && !FileSystem.isDirectory(p)) { listPath = p; break; }
		}
		if (listPath != null)
		{
			var lines:Array<String> = null;
			try lines = backend.CoolUtil.coolTextFile(listPath) catch (e:Dynamic) { lines = null; }
			if (lines != null)
			{
				for (line in lines)
				{
					var l:String = StringTools.trim(line);
					if (l.length == 0 || l.charAt(0) == '#') continue;
					if (!names.contains(l)) names.push(l);
				}
			}
		}

		if (names.length == 0)
		{
			// 列表缺失 → 与 CNE 同款回退：扫 songs/ 下含 charts/ 的目录
			var songsRoot:String = Paths.mods(mod + '/songs');
			if (FileSystem.exists(songsRoot) && FileSystem.isDirectory(songsRoot))
			{
				var entries:Array<String> = null;
				try entries = FileSystem.readDirectory(songsRoot) catch (e:Dynamic) { entries = []; }
				entries.sort(function(a:String, b:String):Int return Reflect.compare(a.toLowerCase(), b.toLowerCase()));
				for (e in entries)
				{
					if (!FileSystem.isDirectory(songsRoot + '/' + e)) continue;
					if (!FileSystem.exists(songsRoot + '/' + e + '/charts')) continue;
					if (!names.contains(e)) names.push(e);
				}
			}
		}
		if (names.length == 0) return null;

		var songs:Array<Dynamic> = [];
		var difficulties:Array<String> = [];
		var firstColor:Array<Int> = null;

		for (n in names)
		{
			var dir:String = n;
			var metaPath:String = Paths.mods(mod + '/songs/' + dir + '/meta.json');
			if (!FileSystem.exists(metaPath))
			{
				var real:String = songDirIn(mod, Paths.formatToSongPath(n));
				if (real == null) continue;
				dir = real;
				metaPath = Paths.mods(mod + '/songs/' + dir + '/meta.json');
			}

			var meta:Dynamic = null;
			if (FileSystem.exists(metaPath))
			{
				try meta = haxe.Json.parse(File.getContent(metaPath)) catch (e:Dynamic) { meta = null; }
			}

			var display:String = (meta != null && meta.displayName != null && Std.string(meta.displayName).length > 0)
				? Std.string(meta.displayName) : dir;
			var icon:String = (meta != null && meta.icon != null && Std.string(meta.icon).length > 0)
				? Std.string(meta.icon) : 'face';
			// CNE 的 meta.json `icon` 经常是占位：SMA 全部 5 首曲都写 "face"，而 mod 里
			// 根本没有 face 图标 → 走 Psych 的 `icons/icon-face` 通用兜底，Freeplay 显示小灰人。
			// CNE 的真实图标是目录形态 `images/icons/<角色>/icon.png`，所以这里在 meta.icon
			// 解析不到真图标时，用该曲谱面**玩家 strumLine（type 1）**的角色名兜底 ——
			// 正好复用 `objects/HealthIcon.changeIcon` 里已加的 CNE 目录图标兜底。
			if (!iconUsable(mod, icon))
			{
				var fallbackChar:String = iconCharacterForSong(mod, dir, meta);
				if (fallbackChar != null && fallbackChar.length > 0 && iconUsable(mod, fallbackChar))
				{
					log('CNE freeplay icon fallback: ' + icon + ' → ' + fallbackChar + ' (' + dir + ')');
					icon = fallbackChar;
				}
			}
			var color:Array<Int> = (meta != null) ? parseHexColor(meta.color != null ? Std.string(meta.color) : null) : null;
			if (color == null) color = [255, 255, 255];
			if (firstColor == null) firstColor = color;

			if (meta != null && meta.difficulties != null)
			{
				for (d in cast(meta.difficulties, Array<Dynamic>))
				{
					if (d == null) continue;
					var dn:String = Std.string(d);
					if (dn.length > 0 && !difficulties.contains(dn)) difficulties.push(dn);
				}
			}
			songs.push([display, icon, color]);
		}
		if (songs.length == 0) return null;

		var weekFile:Dynamic = {
			songs: songs,
			weekCharacters: ['dad', 'bf', 'gf'],
			weekBackground: '',
			weekBefore: '',
			storyName: mod,
			weekName: mod,
			freeplayColor: firstColor,
			startUnlocked: true,
			hiddenUntilUnlocked: false,
			hideStoryMode: true,   // 合成周目只在 Freeplay 出现，不污染 Story
			hideFreeplay: false,
			difficulties: difficulties.join(',')
		};
		log('CNE freeplay list: ' + mod + ' → ' + songs.length + ' songs, difficulties="' + difficulties.join(',') + '"');
		return weekFile;
	}

	/**
	 * `meta.icon` 是否真能解析到一张图标。
	 *
	 * 与 `objects/HealthIcon.changeIcon` 的**实际查找顺序**一致：
	 *   ① `images/icons/<名>.png`
	 *   ② 不存在时 `images/icons/icon-<名>.png`（旧版 Psych）
	 *   ③ ② 也不存在时才轮到 CNE 目录图标 `images/icons/<名>/icon.png`
	 * 但**不把引擎通用兜底 `icons/icon-face.png` 当成 `face` 的有效图标** —— 它的存在会
	 * 挡住 ③（HealthIcon 的条件是 `!exists(icon-<名>.png)`），于是 `face` 永远显示灰脸。
	 * 所以 `face` 只认 ①，让调用方改用谱面里的真实角色名。
	 */
	static function iconUsable(mod:String, name:String):Bool
	{
		if (name == null || name.length == 0) return false;

		var prev:String = Mods.currentModDirectory;
		Mods.currentModDirectory = (mod != null) ? mod : '';
		var ok:Bool = false;
		try
		{
			if (Paths.fileExists('images/icons/' + name + '.png', openfl.utils.AssetType.IMAGE))
			{
				ok = true;
			}
			else
			{
				var legacyExists:Bool = Paths.fileExists('images/icons/icon-' + name + '.png', openfl.utils.AssetType.IMAGE);
				if (legacyExists && name.toLowerCase() != 'face')
					ok = true;
				else if (!legacyExists
					&& Paths.fileExists('images/icons/' + name + '/icon.png', openfl.utils.AssetType.IMAGE))
					ok = true;
			}
		}
		catch (e:Dynamic) { ok = false; }
		Mods.currentModDirectory = prev;
		return ok;
	}

	/**
	 * 从该曲谱面里取第一个**图标可解析**的角色名，供 Freeplay 图标兜底。
	 *
	 * 顺序（SMA 实测）：
	 *   ① 先对手线（type 0）：Freeplay 惯例显示歌曲主角色 —— SMA 的老鼠在这里
	 *      （Happy/Unhappy → sadrat、Really Happy → reallyhappyrat、Smile → randy）。
	 *   ② 对手线没有可用图标时再玩家线（type 1）：例如 WHISPERS 的对手 `whispers`
	 *      在 mod/引擎里都没有图标，退回 `bf`（引擎 `icon-bf.png`）。
	 *   ③ 每行内按 `characters` 顺序取第一个 `iconUsable` 的角色：SMA `smile` 的对手线
	 *      是 `["randah","randy"]`，`randah` 无图标、必须跳到 `randy`。
	 *   ④ 都没有则返回第一个对手名、否则第一个玩家名（调用方会再校验一次，不满足就保留原 icon）。
	 *
	 * 谱面优先用 `meta.difficulties` 的第一项，缺失/不存在时取 `charts/` 下第一个 `.json`。
	 * 只解析 `strumLines`，不建整张谱（Freeplay 列表每首歌都会调用一次）。
	 */
	static function iconCharacterForSong(mod:String, songDir:String, meta:Dynamic):String
	{
		var chartsDir:String = Paths.mods(mod + '/songs/' + songDir + '/charts');
		if (!FileSystem.exists(chartsDir) || !FileSystem.isDirectory(chartsDir)) return null;

		var chartPath:String = null;
		if (meta != null && meta.difficulties != null)
		{
			for (d in cast(meta.difficulties, Array<Dynamic>))
			{
				if (d == null) continue;
				var dn:String = Std.string(d);
				if (dn.length == 0) continue;
				for (cand in [dn, dn.toLowerCase()])
				{
					var p:String = chartsDir + '/' + cand + '.json';
					if (FileSystem.exists(p) && !FileSystem.isDirectory(p)) { chartPath = p; break; }
				}
				if (chartPath != null) break;
			}
		}
		if (chartPath == null)
		{
			var files:Array<String> = null;
			try files = FileSystem.readDirectory(chartsDir) catch (e:Dynamic) { files = []; }
			files.sort(function(a:String, b:String):Int { return Reflect.compare(a.toLowerCase(), b.toLowerCase()); });
			for (f in files)
			{
				if (f == null || !f.toLowerCase().endsWith('.json')) continue;
				var p:String = chartsDir + '/' + f;
				if (FileSystem.exists(p) && !FileSystem.isDirectory(p)) { chartPath = p; break; }
			}
		}
		if (chartPath == null) return null;

		var raw:String = null;
		try raw = File.getContent(chartPath) catch (e:Dynamic) { raw = null; }
		if (raw == null) return null;
		var data:Dynamic = null;
		try data = haxe.Json.parse(raw) catch (e:Dynamic) { data = null; }
		if (data == null) return null;

		var lines:Array<Dynamic> = cast data.strumLines;
		if (lines == null) return null;
		var firstOpponent:String = null;
		var firstPlayer:String = null;
		for (pass in 0...2)
		{
			var want:Int = (pass == 0) ? 0 : 1;
			for (line in lines)
			{
				if (line == null) continue;
				if (intOf(line.type, -1) != want) continue;
				var chars:Array<Dynamic> = cast line.characters;
				if (chars == null) continue;
				for (ch in chars)
				{
					if (ch == null) continue;
					var c:String = Std.string(ch);
					if (c.length == 0) continue;
					if (want == 0) { if (firstOpponent == null) firstOpponent = c; }
					else if (firstPlayer == null) firstPlayer = c;
					if (iconUsable(mod, c)) return c;
				}
			}
		}
		return (firstOpponent != null) ? firstOpponent : firstPlayer;
	}

	/** `Dynamic` → Int（CNE JSON 里 type 可能是 Int/Float/Bool/String）。 */
	static function intOf(v:Dynamic, def:Int):Int
	{
		if (v == null) return def;
		if (Std.isOfType(v, Bool)) return (cast v) ? 1 : 0;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Float)) return Std.int(cast v);
		var parsed:Null<Int> = Std.parseInt(Std.string(v));
		return (parsed == null) ? def : cast parsed;
	}

	// ==================== 记谱皮肤（CNE NOTE 贴图） ====================

	/**
	 * CNE 的箭头贴图约定是 `images/game/notes/NOTE_assets*.png|xml`（mod 可换名，如 SMA 的
	 * `NOTE_assets_mack`，名字写在 `songs/UI.hx` 的 `onNoteCreation` 里）。Psych 侧箭头贴图走
	 * `SONG.arrowSkin`（`StrumNote.hx:59` / `Note.hx:994` 优先于用户设置），所以这里扫一遍该目录、
	 * 把找到的键交给谱面 → 不用执行 CNE 脚本也能用上 mod 的箭头。
	 * 多个候选时优先标准名 `NOTE_assets`，否则取第一个。
	 */
	public static function noteSkin():String
	{
		if (!isEnabled()) return null;
		var mod:String = (Mods.currentModDirectory != null) ? Mods.currentModDirectory : '';
		var dir:String = Paths.mods((mod.length > 0 ? mod + '/' : '') + 'images/game/notes');
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return null;

		var entries:Array<String> = null;
		try entries = FileSystem.readDirectory(dir) catch (e:Dynamic) { entries = []; }
		var best:String = null;
		for (e in entries)
		{
			if (e == null) continue;
			var lower:String = e.toLowerCase();
			if (!lower.startsWith('note_assets') || !lower.endsWith('.png')) continue;
			var key:String = 'game/notes/' + e.substr(0, e.length - 4);
			if (lower == 'note_assets.png') return key;   // 标准名优先
			if (best == null) best = key;
		}
		if (best != null) log('CNE note skin: ' + best);
		return best;
	}

	// ==================== 舞台（CNE stage XML） ====================

	/** 该 mod 是否有 CNE 舞台定义 `data/stages/<名>.xml`。 */
	public static function hasStageXml(name:String):Bool
	{
		if (!isEnabled() || name == null || name.length == 0) return false;
		return stageXmlRaw(name) != null;
	}

	/** CNE 舞台 XML 原文（`mods/<mod>/data/stages/<名>.xml`）；无则 null。 */
	public static function stageXmlRaw(name:String):String
	{
		if (!isEnabled() || name == null || name.length == 0) return null;
		var p:String = Paths.modFolders('data/stages/' + name + '.xml');
		if (!FileSystem.exists(p)) return null;
		try return File.getContent(p) catch (e:Dynamic) { return null; }
	}

	/** CNE 舞台的图层元素（`<sprite>`），供 `states.stages.CneXmlStage` 建背景。 */
	public static function stageSpriteNodes(name:String):Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		var raw:String = stageXmlRaw(name);
		if (raw == null) return out;
		try
		{
			var xml:Xml = Xml.parse(raw).firstElement();
			if (xml == null || xml.nodeName != 'stage') return out;
			var folder:String = attr(xml, 'folder');
			if (folder == null) folder = '';
			while (folder.startsWith('/')) folder = folder.substr(1);
			for (node in xml.elements())
			{
				if (node.nodeName != 'sprite') continue;
				out.push({
					folder: folder,
					sprite: attr(node, 'sprite'),
					name: attr(node, 'name'),
					x: parseFloat(attr(node, 'x'), 0),
					y: parseFloat(attr(node, 'y'), 0),
					scaleX: parseFloat(attr(node, 'scalex') != null ? attr(node, 'scalex') : attr(node, 'scale'), 1),
					scaleY: parseFloat(attr(node, 'scaley') != null ? attr(node, 'scaley') : attr(node, 'scale'), 1),
					alpha: parseFloat(attr(node, 'alpha'), 1),
					flipX: (attr(node, 'flipx') == 'true'),
					scrollX: parseFloat(attr(node, 'scrollx'), 1),
					scrollY: parseFloat(attr(node, 'scrolly'), 1),
					antialiasing: (attr(node, 'antialiasing') != 'false')
				});
			}
		}
		catch (e:Dynamic)
		{
			log('CNE stage parse failed (' + name + '): ' + Std.string(e));
		}
		return out;
	}

	/**
	 * CNE 舞台 XML → Psych `StageFile`（Dynamic，调用方 cast）。
	 *
	 * 这是「背景不显示」的修法：Psych 的角色站位与相机缩放全部来自 `StageFile`
	 * （`PlayState.hx:762/781-785` 读 `stageData.defaultZoom/boyfriend/girlfriend/opponent/camera_*`），
	 * 而 CNE 把它们写在 `data/stages/<名>.xml` 的 `<boyfriend>/<dad>/<girlfriend>` 元素上。
	 * 图层（`<sprite>`）由 `states.stages.CneXmlStage` 负责，`StageFile` 里没有对应字段。
	 */
	public static function stageFile(name:String):Dynamic
	{
		var raw:String = stageXmlRaw(name);
		if (raw == null) return null;

		try
		{
			var xml:Xml = Xml.parse(raw).firstElement();
			if (xml == null || xml.nodeName != 'stage') return null;

			var zoom:Float = parseFloat(attr(xml, 'zoom'), 0.9);
			if (zoom <= 0) zoom = 0.9;

			var bfPos:Array<Float> = [770.0, 100.0];
			var dadPos:Array<Float> = [100.0, 100.0];
			var gfPos:Array<Float> = [400.0, 130.0];
			var bfCam:Array<Float> = [0.0, 0.0];
			var dadCam:Array<Float> = [0.0, 0.0];
			var gfCam:Array<Float> = [0.0, 0.0];

			for (node in xml.elements())
			{
				switch (node.nodeName)
				{
					case 'boyfriend':
						bfPos = [parseFloat(attr(node, 'x'), bfPos[0]), parseFloat(attr(node, 'y'), bfPos[1])];
						bfCam = [parseFloat(attr(node, 'camxoffset'), 0), parseFloat(attr(node, 'camyoffset'), 0)];
					case 'dad' | 'opponent':
						dadPos = [parseFloat(attr(node, 'x'), dadPos[0]), parseFloat(attr(node, 'y'), dadPos[1])];
						dadCam = [parseFloat(attr(node, 'camxoffset'), 0), parseFloat(attr(node, 'camyoffset'), 0)];
					case 'girlfriend':
						gfPos = [parseFloat(attr(node, 'x'), gfPos[0]), parseFloat(attr(node, 'y'), gfPos[1])];
						gfCam = [parseFloat(attr(node, 'camxoffset'), 0), parseFloat(attr(node, 'camyoffset'), 0)];
					default:
				}
			}

			log('CNE stage: ' + name + ' → StageFile (zoom=' + zoom + ', bf=' + bfPos + ', dad=' + dadPos + ', gf=' + gfPos + ')');
			return {
				directory: '',
				defaultZoom: zoom,
				isPixelStage: false,
				stageUI: 'normal',
				boyfriend: bfPos,
				girlfriend: gfPos,
				opponent: dadPos,
				hide_girlfriend: false,
				camera_boyfriend: bfCam,
				camera_opponent: dadCam,
				camera_girlfriend: gfCam,
				camera_speed: null
			};
		}
		catch (e:Dynamic)
		{
			log('CNE stage convert failed (' + name + '): ' + Std.string(e));
			return null;
		}
	}

	// ==================== 类型识别（Mods 界面用） ====================

	/**
	 * 该 mod 是否是 CNE 格式（用于 Mods 管理与提示）。只做廉价的目录/文件存在性探测，
	 * 命中即返回，不做全量扫描。判定依据是 CNE 独有布局（Psych 模组不会有）。
	 */
	public static function isCneMod(folder:String):Bool
	{
		if (folder == null || folder.length == 0) return false;

		if (FileSystem.exists(Paths.mods(folder + '/data/weeks/weeks'))) return true;
		if (FileSystem.exists(Paths.mods(folder + '/data/global'))) return true;
		if (FileSystem.exists(Paths.mods(folder + '/data/states'))) return true;

		var songsRoot:String = Paths.mods(folder + '/songs');
		if (FileSystem.exists(songsRoot) && FileSystem.isDirectory(songsRoot))
		{
			var entries:Array<String> = null;
			try entries = FileSystem.readDirectory(songsRoot) catch (e:Dynamic) { entries = []; }
			var checked:Int = 0;
			for (e in entries)
			{
				if (checked >= 40) break;
				checked++;
				if (!FileSystem.isDirectory(songsRoot + '/' + e)) continue;
				if (FileSystem.exists(songsRoot + '/' + e + '/charts')) return true;
			}
		}

		var charsRoot:String = Paths.mods(folder + '/data/characters');
		if (FileSystem.exists(charsRoot) && FileSystem.isDirectory(charsRoot))
		{
			var entries:Array<String> = null;
			try entries = FileSystem.readDirectory(charsRoot) catch (e:Dynamic) { entries = []; }
			for (e in entries)
			{
				if (e.toLowerCase().endsWith('.xml')) return true;
			}
		}
		return false;
	}

	// ==================== 工具 ====================

	static function attr(node:Xml, name:String):String
	{
		if (node == null || !node.exists(name)) return null;
		var v:String = node.get(name);
		return v == null ? null : StringTools.trim(v);
	}

	static function childText(node:Xml):String
	{
		if (node == null) return '';
		var sb:StringBuf = new StringBuf();
		for (child in node)
		{
			if (child != null && child.nodeType == Xml.PCData) sb.add(child.nodeValue);
		}
		return StringTools.trim(sb.toString());
	}

	static function parseFloat(value:String, def:Float):Float
	{
		if (value == null || value.length == 0) return def;
		var f:Null<Float> = Std.parseFloat(value);
		if (f == null || Math.isNaN(f)) return def;
		return f;
	}

	/** `#RRGGBB` / `#RRGGBBAA` / `RRGGBB` / `0xAARRGGBB` → [r, g, b]；无法解析返回 null。 */
	static function parseHexColor(value:String):Array<Int>
	{
		if (value == null) return null;
		var s:String = StringTools.trim(value);
		if (s.length == 0) return null;
		if (s.substr(0, 2).toLowerCase() == '0x') s = s.substr(2);
		if (s.charAt(0) == '#') s = s.substr(1);
		if (s.length != 6 && s.length != 8) return null;
		for (i in 0...s.length)
		{
			var c:String = s.charAt(i).toLowerCase();
			var ok:Bool = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
			if (!ok) return null;
		}
		var offset:Int = (s.length == 8) ? 2 : 0; // 8 位按 AARRGGBB 处理，取后 6 位
		var r:Int = Std.parseInt('0x' + s.substr(offset, 2));
		var g:Int = Std.parseInt('0x' + s.substr(offset + 2, 2));
		var b:Int = Std.parseInt('0x' + s.substr(offset + 4, 2));
		return [r, g, b];
	}

	/** CNE `CoolUtil.parseNumberRange`：`"2..12,0,1"` → [2,3,…,12,0,1]（含反向区间）。 */
	static function parseNumberRange(input:String):Array<Int>
	{
		var result:Array<Int> = [];
		if (input == null || input.length == 0) return result;

		for (part in input.split(','))
		{
			var p:String = StringTools.trim(part);
			if (p.length == 0) continue;
			var idx:Int = p.indexOf('..');
			if (idx != -1)
			{
				var startNull:Null<Int> = Std.parseInt(StringTools.trim(p.substr(0, idx)));
				var endNull:Null<Int> = Std.parseInt(StringTools.trim(p.substr(idx + 2)));
				if (startNull == null || endNull == null) continue;
				var start:Int = cast startNull;
				var end:Int = cast endNull;
				if (start < end)
				{
					for (j in start...(end + 1)) result.push(j);
				}
				else
				{
					for (j in end...(start + 1)) result.push(start + end - j);
				}
			}
			else
			{
				var numNull:Null<Int> = Std.parseInt(p);
				if (numNull != null) result.push(cast numNull);
			}
		}
		return result;
	}
}
#end
