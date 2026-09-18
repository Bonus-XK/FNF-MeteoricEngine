package backend;

import sys.FileSystem;

/**
 * 测试替身：`formatToSongPath` 与仓库 `source/backend/Paths.hx:890-896` 逐行一致；
 * `mods` / `modFolders` / `getPreloadPath` 按仓库语义（当前 mod → 全局 mod → mods 根）实现，
 * 只是把根目录指向测试用假 mods 目录。`SOUND_EXT` 取桌面值。
 */
class Paths
{
	public static var MODS_ROOT:String = 'mods/';

	inline public static var SOUND_EXT:String = 'ogg';

	inline static public function formatToSongPath(path:String)
	{
		var invalidChars = ~/[~&\\;:<>#]/;
		var hideChars = ~/[.,'"%?!]/;

		var path = invalidChars.split(path.replace(' ', '-')).join("-");
		return hideChars.split(path).join("").toLowerCase();
	}

	/** 与仓库同款：先走 CNE zip 重映射，再退回原始 mods 路径。 */
	static public function mods(key:String = ''):String
	{
		var remapped:String = cne.CneZipStore.remapKey(key);
		if (remapped != null) return remapped;
		return modsRaw(key);
	}

	static public function modsRaw(key:String = ''):String
	{
		var p:String = MODS_ROOT + key;
		if (!FileSystem.exists(p))
		{
			var lower:String = MODS_ROOT + key.toLowerCase();
			if (FileSystem.exists(lower)) return lower;
		}
		return p;
	}

	static public function modFolders(key:String):String
	{
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods(Mods.currentModDirectory + '/' + key);
			if (FileSystem.exists(fileToCheck)) return fileToCheck;
		}
		for (mod in Mods.getGlobalMods())
		{
			var fileToCheck:String = mods(mod + '/' + key);
			if (FileSystem.exists(fileToCheck)) return fileToCheck;
		}
		return mods(key);
	}

	/**
	 * 测试替身：真实 `Paths.fileExists` 的 mods 前半段语义（全局 mod → 当前 mod → mods 根）
	 * + preload 资源；测试工程没有 OpenFL 资源清单，因此不查 `OpenFlAssets`。
	 */
	public static function fileExists(key:String, type:openfl.utils.AssetType, ?ignoreMods:Bool = false, ?library:String = null):Bool
	{
		if (!ignoreMods)
		{
			for (mod in Mods.getGlobalMods())
				if (FileSystem.exists(mods(mod + '/' + key))) return true;
			if (FileSystem.exists(mods(Mods.currentModDirectory + '/' + key)) || FileSystem.exists(mods(key))) return true;
		}
		return FileSystem.exists(getPreloadPath(key));
	}

	inline public static function getPreloadPath(file:String = ''):String
	{
		return 'assets/' + file;
	}
}
