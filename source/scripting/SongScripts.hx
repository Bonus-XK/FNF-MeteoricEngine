package scripting;

#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
import backend.ClientPrefs;
import backend.Mods;
import backend.Paths;
import scripting.ScriptOrder.ScriptOrderEntry;
import sys.FileSystem;

/**
 * 全曲 / 单曲脚本自动发现（`scripting/songs/`）。
 *
 * 目录约定（全部相对 **启用中的 mod**）：
 * ```
 * mods/<mod>/scripting/songs/<任意名>.hx          # 全曲脚本：每首歌都加载
 * mods/<mod>/scripting/songs/<歌曲名>/<任意名>.hx  # 单曲脚本：只在该曲目加载
 * ```
 *
 * `<歌曲名>` 优先用**谱面目录名**（`PlayState.chartFolder`，与 `data/<目录名>/` 同一套）；
 * 该目录下没有脚本时，回退到 `Paths.formatToSongPath(SONG.song)`（`PlayState.songName`）。
 * 例：`data/Obsolescence-spam/` 的谱面里 `song="Obsolescence"` 时，先找
 * `scripting/songs/Obsolescence-spam/`，没有再找 `scripting/songs/obsolescence/`。
 *
 * 与既有 Psych 风格 `data/<歌曲名>/*.hx` 的区别：
 *  - 本机制按 mod 目录自动发现，不需要把脚本塞进谱面目录；
 *  - 全曲 / 单曲两层目录，全曲脚本先于单曲脚本加载；
 *  - 加载进 PlayState 的 HScript 脚本数组（`PS.hscriptArray`），拿到与其它游玩脚本
 *    一样的 `onCreate` / `onUpdate` / `onStepHit` / `onBeatHit` 回调；
 *  - `initHScript` 自带 replayMode 拦截，回放模式不会加载。
 *
 * 开关：`ClientPrefs.data.scriptingSongScripts`（总开关 `scriptingEnabled` 关闭时整体无效）。
 * 目录不存在 = 没有脚本；不会为每个 mod 反复探盘。
 */
class SongScripts
{
	/** 当前是否应加载歌曲脚本。 */
	public static function enabled():Bool
	{
		return Scripting.isEnabled() && ClientPrefs.data != null && ClientPrefs.data.scriptingSongScripts;
	}

	/**
	 * 把本曲目的全曲 / 单曲脚本加载进 PlayState。
	 *
	 * @param ps         当前 PlayState。
	 * @param songName   `PlayState.songName`（`Paths.formatToSongPath(SONG.song)`）。
	 * @param songFolder `PlayState.chartFolder`（谱面目录名，优先）。
	 */
	public static function load(ps:PlayState, songName:String, ?songFolder:String):Void
	{
		if (ps == null || !enabled()) return;
		var paths:Array<String> = collect(songName, songFolder);
		if (paths.length == 0) return;
		for (path in paths)
			ps.initHScript(path);
		trace('[Scripting] song scripts loaded: ' + (songFolder != null && songFolder.length > 0 ? songFolder : songName)
			+ ' (' + paths.length + ')');
	}

	/**
	 * 收集本曲目要加载的脚本路径（已排序、已去重）。
	 *
	 * 顺序：全曲脚本（按 文件名前缀 → mod 顺序 → 文件名）→ 单曲脚本（同一套排序）。
	 * 同一路径只加载一次（同一个 mod 的全曲 / 单曲目录不会重复，防御性去重）。
	 */
	public static function collect(songName:String, ?songFolder:String):Array<String>
	{
		var out:Array<String> = [];
		var mods:Array<String> = enabledMods();
		if (mods.length == 0) return out;

		// 第一层：songs/ 直属 .hx = 全曲脚本。
		var allEntries:Array<ScriptOrderEntry> = [];
		for (i in 0...mods.length)
		{
			var dir:String = Paths.mods(mods[i] + '/scripting/songs');
			collectDir(allEntries, dir, i, true);
		}
		ScriptOrder.sortEntries(allEntries);
		appendPaths(out, allEntries);

		// 第二层：songs/<歌曲名>/ 下的 .hx = 单曲脚本。
		// 优先谱面目录名（chartFolder）；该候选在所有 mod 里都没有脚本时，才回退到
		// SONG.song 的格式化名。避免同一首歌在两处目录各放一份导致重复加载。
		for (candidate in songCandidates(songName, songFolder))
		{
			var songEntries:Array<ScriptOrderEntry> = [];
			for (i in 0...mods.length)
			{
				var dir:String = Paths.mods(mods[i] + '/scripting/songs/' + candidate);
				collectDir(songEntries, dir, i, false);
			}
			if (songEntries.length == 0) continue;
			ScriptOrder.sortEntries(songEntries);
			appendPaths(out, songEntries);
			break;
		}
		return out;
	}

	/** 单曲目录候选：chartFolder 优先，其次 songName；去重、去空。 */
	static function songCandidates(songName:String, ?songFolder:String):Array<String>
	{
		var out:Array<String> = [];
		if (songFolder != null && songFolder.length > 0) out.push(songFolder);
		if (songName != null && songName.length > 0 && !out.contains(songName)) out.push(songName);
		return out;
	}

	/** 扫描一个目录里的 .hx；`filesOnly` = 跳过子目录（全曲层只认直属文件）。 */
	static function collectDir(entries:Array<ScriptOrderEntry>, dir:String, modIndex:Int, filesOnly:Bool):Void
	{
		if (dir == null || !FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return;
		var files:Array<String> = null;
		try files = FileSystem.readDirectory(dir) catch (e:Dynamic) files = [];
		if (files == null) return;
		for (f in files)
		{
			if (f == null || !f.toLowerCase().endsWith('.hx')) continue;
			if (filesOnly && FileSystem.isDirectory(dir + '/' + f)) continue;
			entries.push({path: dir + '/' + f, file: f, priority: ScriptOrder.priorityOf(f), modIndex: modIndex});
		}
	}

	static function appendPaths(out:Array<String>, entries:Array<ScriptOrderEntry>):Void
	{
		for (e in entries)
		{
			if (e == null || e.path == null) continue;
			if (!out.contains(e.path)) out.push(e.path);
		}
	}

	/** 已启用的 mod 列表；任何异常都退回空列表（与 Scripting.activeMods 同语义）。 */
	static function enabledMods():Array<String>
	{
		if (ClientPrefs.data == null) return [];
		try
		{
			return Mods.parseList().enabled;
		}
		catch (e:Dynamic)
		{
			return [];
		}
	}
}
#end
