package backend;

#if sys
import sys.FileSystem;
import sys.io.File;
#else
import lime.utils.Assets;
#end
import tjson.TJSON as Json;

typedef ModsList = {
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

class Mods
{
	static public var currentModDirectory:String = '';
	public static var ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'achievements',
		// 多版本容器仓库（backend.ContainerStore.CONTAINERS_DIR）。
		// 必须显式登记：getModDirectories 只按本白名单过滤，**没有**「下划线前缀自动跳过」这条规则，
		// 不写进来 mods/_containers 会被扫成一个名为 "_containers" 的假模组。
		'_containers'
	];

	private static var globalMods:Array<String> = [];

	inline public static function getGlobalMods()
		return globalMods;

	inline public static function pushGlobalMods() // prob a better way to do this but idc
	{
		globalMods = [];
		for(mod in parseList().enabled)
		{
			var pack:Dynamic = getPack(mod);
			if(pack != null && pack.runsGlobally) globalMods.push(mod);
		}
		return globalMods;
	}

	inline public static function getModDirectories():Array<String>
	{
		// [PSYCH-COMPAT-OFF] Psych 模组兼容已停用（2026-10-29）：不扫描 mods 目录，
		// 也不再自动创建 mods/ 文件夹（避免"以为还在加载"的错觉）。
		// 恢复：git revert 去除本闸门的提交。
		var none:Array<String> = [];
		return none;
	}
	
	inline public static function mergeAllTextsNamed(path:String, defaultDirectory:String = null, allowDuplicates:Bool = false)
	{
		if(defaultDirectory == null) defaultDirectory = Paths.getPreloadPath();
		defaultDirectory = defaultDirectory.trim();
		if(!defaultDirectory.endsWith('/')) defaultDirectory += '/';
		if(!defaultDirectory.startsWith('assets/') && !haxe.io.Path.isAbsolute(defaultDirectory)) defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if(paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
		{
			var list:Array<String> = CoolUtil.coolTextFile(file);
			for (value in list)
				if((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);
		}
		return mergedList;
	}

	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true)
	{
		var foldersToCheck:Array<String> = [];
		#if sys
		if(FileSystem.exists(path + fileToFind))
		#end
			foldersToCheck.push(path + fileToFind);

		// [PSYCH-COMPAT-OFF] Psych 模组兼容已停用（2026-10-29）：不再追加 mods/ 下的同名目录
		// （原先依次查 全局模组 → mods/ 根 → 当前模组 三段）。`mods` 形参保留仅为兼容调用签名。
		// 结果：脚本/角色/事件的查找只剩内置 preload 路径，mods 里的 .lua/.hx 一律不会被扫到。
		// 恢复：git revert 去除本闸门的提交。
		return foldersToCheck;
	}

	public static function getPack(?folder:String = null):Dynamic
	{
		// [PSYCH-COMPAT-OFF] Psych 模组兼容已停用（2026-10-29）：不再读取 pack.json。
		// 恢复：git revert 去除本闸门的提交。
		return null;
	}

	public static var updatedOnState:Bool = false;

	// modsList.txt 在安卓上写到外部存储（/sdcard/meteoric），桌面保持原样
	public static inline function modsListPath():String
	{
		#if android
		return backend.AndroidStorage.root() + '/modsList.txt';
		#else
		return 'modsList.txt';
		#end
	}

	inline public static function parseList():ModsList {
		// [PSYCH-COMPAT-OFF] Psych 模组兼容已停用（2026-10-29）：不再读取 modsList.txt、
		// 不再扫描 mods 目录，恒返回空表 → 模组一律不启用。
		// 恢复：git revert 去除本闸门的提交（原实现见 updateModList()，其函数体仍完整保留）。
		var list:ModsList = {enabled: [], disabled: [], all: []};
		return list;
	}
	
	private static function updateModList()
	{
		#if MODS_ALLOWED
		// Find all that are already ordered
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String> = [];
		try {
			for (mod in CoolUtil.coolTextFile(modsListPath()))
			{
				var dat:Array<String> = mod.split("|");
				var folder:String = dat[0];
				var knownMod:Bool = FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder));
				if(folder.trim().length > 0 && knownMod && !added.contains(folder))
				{
					added.push(folder);
					list.push([folder, (dat[1] == "1")]);
				}
			}
		} catch(e) {
			trace(e);
		}
		
		// Scan for folders that aren't on modsList.txt yet
		for (folder in getModDirectories())
		{
			if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) &&
			!ignoreModFolders.contains(folder.toLowerCase()) && !added.contains(folder))
			{
				added.push(folder);
				// 新发现的 mod 文件夹默认【关闭】：
				// 若默认启用，装进来的半成品/缺资源 mod 会立刻被加载，
				// 在 TitleState/PlayState 因缺失贴图（如 spritemap）崩溃，
				// 也会把 loadTopMod 的 currentModDirectory 顶到新 mod 上（"上一个模组失效"）。
				list.push([folder, false]);
			}
		}

		// Now save file
		var fileStr:String = '';
		for (values in list)
		{
			if(fileStr.length > 0) fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

		try {
			File.saveContent(modsListPath(), fileStr);
		} catch(e:Dynamic) {
			trace('Could not save modsList.txt: $e');
		}
		updatedOnState = true;
		//trace('Saved modsList.txt');
		#end
	}

	public static function loadTopMod()
	{
		Mods.currentModDirectory = '';
		
		#if MODS_ALLOWED
		var list:Array<String> = Mods.parseList().enabled;
		if(list != null && list[0] != null)
			Mods.currentModDirectory = list[0];
		#end
	}
}
