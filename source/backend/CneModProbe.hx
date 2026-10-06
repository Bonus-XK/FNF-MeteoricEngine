package backend;

import sys.FileSystem;

/**
 * CNE 模组格式**只读探测**（2026-10-05 起为引擎唯一残留的 CNE 相关代码）。
 *
 * ## 为什么只剩这个
 *
 * Meteoric 曾经内置完整的 CNE（Codename Engine）模组兼容层：谱面/音频/人物/周目/舞台的
 * 格式转换、`mods/*.zip` 暂存解包、以及一整套 CNE 式 HScript 编程层（状态脚本、全局脚本、
 * `ModState`/`ModSubState`、界面重定向、脚本热重载）。**这些已全部移除**。
 *
 * 保留本类的唯一目的：**在 Mods 界面识别出「这个 mod 是 CNE 格式」并给出提示**，
 * 让玩家知道它为什么不能加载。仅此而已 —— **不加载、不解析、不转换任何 CNE 资源**。
 *
 * 上游立场：Codename Engine 作者明确反对把引擎功能移植到其它引擎，故不再做兼容层，
 * 只留一个「我认识你，但你在这里跑不起来」的识别标记。
 *
 * 判定规则原样取自被删除的 `cne/CneModCompat.isCneMod`（CNE 布局的标志性目录），
 * 是纯文件系统探测，不读文件内容、不抛异常。
 */
class CneModProbe
{
	/**
	 * 该 mod 是不是 CNE 格式（廉价探测）。
	 *
	 * 判定依据（CNE 布局的标志性目录，任一命中即为 CNE mod）：
	 *   - `data/weeks/weeks/`、`data/global/`、`data/states/`
	 *   - 任一 `songs/<歌>/charts/`（最多查 40 首，避免大目录卡顿）
	 *   - `data/characters/` 下任一 `.xml`
	 *
	 * `songs/` 目录的扫描上限 40 与原实现一致（`CneModCompat.isCneMod` 同值）。
	 */
	public static function isCneMod(folder:String):Bool
	{
		#if (MODS_ALLOWED && sys)
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
				if (e.toLowerCase().endsWith('.xml')) return true;
		}
		#else
		// 非 MODS_ALLOWED / 非桌面构建：没有 mods 目录概念，一律不算 CNE mod
		#end
		return false;
	}
}