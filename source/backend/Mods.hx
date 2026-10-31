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

/**
 * Meteoric 模组体系（2026-10-29 独立化）。
 *
 * 与 Psych Engine 的模组约定解耦：
 *  - 元数据：mod.json（不再读取 pack.json，去掉 discordRPC 等 Psych 专属字段）。
 *  - 启用列表：meteoric-mods.txt（不再读取/写入 modsList.txt）。
 *  - 目录仍用 mods/，但只有带 mod.json 的 Meteoric 原生模组才会被默认启用；
 *    仅有 pack.json / 无元数据的旧目录默认关闭（可手动启用），保证零行为变化、
 *    也不会把半成品模组突然加载导致崩溃。
 *  - 脚本走 Meteoric 自研的 mods/<mod>/scripting/（见 PROGRAMMING.md），
 *    Psych 风格的 scripts/、data/<song>/、characters/*.lua 等执行点仍保持闸断。
 *  - 内容目录重分类（2026-10-30）：模组侧 data/→charts/、images/→gfx/、
 *    music/+sounds/→audio/、custom_notetypes/→noteTypes/，映射集中在
 *    Paths.modRelPath —— 引擎内置资源目录不变，覆盖仍靠 key 一致。
 */
class Mods
{
	/** Meteoric 原生模组元数据文件名（区别于 Psych 的 pack.json）。 */
	public static inline var META_FILE:String = 'mod.json';
	/** Meteoric 启用列表文件名（区别于 Psych 的 modsList.txt）。 */
	public static inline var LIST_FILE:String = 'meteoric-mods.txt';
	/** Psych 1.0.4 模组兼容（psychV104Compat）打开时回退读取的元数据 / 列表文件名。 */
	public static inline var PSYCH_META_FILE:String = 'pack.json';
	public static inline var PSYCH_LIST_FILE:String = 'modsList.txt';

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
		// Meteoric 重分类后的模组内容目录（2026-10-30）：必须登记，否则
		// mods/charts、mods/gfx 这类散装目录会被扫成名为 "charts"/"gfx" 的假模组。
		// 旧名（data/images/sounds/music/custom_notetypes）一并保留 —— 老模组里的
		// 散装目录虽然已失效，但保留可避免它们被误扫成假模组。
		'charts', 'gfx', 'audio', 'noteTypes',
		// menus/ 是界面脚本目录（Meteoric 自研 MenuScript 约定），不是模组；
		// 不登记会被 mods/menus 这个散装目录扫成名为 "menus" 的假模组。
		'menus',
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

	/** isLegacyLayout 的结果缓存（模组布局在运行期不会变，避免每帧 FileSystem 探测）。 */
	static var legacyLayoutCache:Map<String, Bool> = [];

	/**
	 * 该模组是否为 **Psych 旧目录布局**（images/ data/ sounds/ music/ custom_notetypes/ 或 pack.json）。
	 *
	 * 为什么按「磁盘结构」而不是按「兼容开关」决定回退旧目录名：
	 * 开关存在 ClientPrefs 存档里，而 Paths 在 loadPrefs() 之前就会被调用（TitleState 早期、
	 * pushGlobalMods 等），那时读到的永远是默认 false。若路径回退也依赖这个开关，
	 * 就会出现 **fileExists 说「存在」、image 却返回 null** 的不一致 → HealthIcon 解引用 null → SEGV。
	 * 布局是磁盘事实，不依赖任何运行期状态，因此永远一致。
	 *
	 * 注意：这里只影响「用哪套目录名找资源」，**不影响是否加载旧模组的脚本**
	 *（脚本加载仍由 psychV104Compat 开关控制，见 HostDomain / PlayState）。
	 */
	public static function isLegacyLayout(folder:String):Bool
	{
		#if MODS_ALLOWED
		if(folder == null || folder.length == 0) return false;
		var cached:Null<Bool> = legacyLayoutCache.get(folder);
		if(cached != null) return cached;

		var legacy:Bool = false;
		try
		{
			var root:String = Paths.mods(folder);
			var hasNative:Bool = FileSystem.exists(root + '/' + META_FILE);
			var hasPsych:Bool = FileSystem.exists(root + '/' + PSYCH_META_FILE);
			if(hasPsych && !hasNative) legacy = true;
			else if(!hasNative)
			{
				// 无任何元数据：看是否摆着旧目录（images/ data/ …）而不是 Meteoric 新目录（gfx/ charts/ …）
				for(d in ['images', 'data', 'sounds', 'music', 'custom_notetypes'])
				{
					if(FileSystem.isDirectory(root + '/' + d)) { legacy = true; break; }
				}
			}
		}
		catch(e:Dynamic) {}

		legacyLayoutCache.set(folder, legacy);
		return legacy;
		#end
		return false;
	}

	/** 清除布局缓存（安装/删除/启用切换模组后调用）。 */
	public static function clearLegacyLayoutCache():Void
	{
		legacyLayoutCache = [];
		legacyEnabledCache = null;
	}

	/** hasLegacyEnabled 的缓存（null = 未计算）。 */
	static var legacyEnabledCache:Null<Bool> = null;

	/**
	 * 是否存在「已启用 + 旧目录布局」的模组。
	 *
	 * 这是**脚本加载闸门**的判据，取代原来的 `Paths.psychCompat()`：
	 * 玩家既然在模组菜单里手动启用了这个旧模组，它的资源与脚本就该一起生效。
	 * 只放资源不放脚本会得到「贴图正常、菜单/事件全部失效」的半残状态
	 *（2026-10-30 实测：Sonic 的 data/menu/menu.lua 不加载 → 菜单曲目进成了普通玩法）。
	 *
	 * 注意：这里**不**放开「发现与默认启用」——那仍由 psychV104Compat 开关控制，
	 * 开关关着时旧模组依旧默认 |0，不会被自动拉起。
	 */
	public static function hasLegacyEnabled():Bool
	{
		#if MODS_ALLOWED
		if(legacyEnabledCache != null) return legacyEnabledCache;
		var any:Bool = false;
		for(m in parseList().enabled)
			if(isLegacyLayout(m)) { any = true; break; }
		legacyEnabledCache = any;
		return any;
		#end
		return false;
	}

	/** 该目录是否为 Meteoric 原生模组（存在 mod.json）。决定新发现目录的默认启用状态。 */
	public static function hasMeta(folder:String):Bool
	{
		#if MODS_ALLOWED
		if(folder == null || folder.length == 0) return false;
		try
		{
			if(FileSystem.exists(Paths.mods(folder + '/' + META_FILE))) return true;
			// Psych 1.0.4 兼容：带 pack.json 的旧模组也算「有元数据」→ 首次扫描默认启用（开箱即用）。
			return Paths.psychCompat() && FileSystem.exists(Paths.mods(folder + '/' + PSYCH_META_FILE));
		}
		catch(e:Dynamic) return false;
		#end
		return false;
	}

	inline public static function getModDirectories():Array<String>
	{
		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		// mods 目录不存在时自动创建，否则模组无法扫描 / 安装。
		if(!FileSystem.exists(modsFolder)) {
			try {
				FileSystem.createDirectory(modsFolder);
			} catch(e:Dynamic) {
				trace('Could not create mods folder: $e');
			}
		}
		if(FileSystem.exists(modsFolder)) {
			for (folder in FileSystem.readDirectory(modsFolder))
			{
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (sys.FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder.toLowerCase()) && !list.contains(folder))
					list.push(folder);
			}
		}
		#end
		return list;
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

	/**
	 * 查找同名目录：内置 preload + 全局模组 → mods 根 → 当前模组。
	 * mods=false 时只返回内置 preload 段 —— 用于仍须闸断的 Psych 脚本执行点
	 *（mods/<mod>/scripts/、mods/<mod>/data/<song>/ 等），避免取消掉的 Psych 兼容复活。
	 */
	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true)
	{
		var foldersToCheck:Array<String> = [];
		#if sys
		if(FileSystem.exists(path + fileToFind))
		#end
			foldersToCheck.push(path + fileToFind);

		#if MODS_ALLOWED
		if(mods)
		{
			// 模组侧按 Meteoric 重分类后的目录名查找（data/→charts/、images/→gfx/ …）；
			// 上面已 push 的内置段仍用原路径，两侧互不干扰。
			// 每个模组用 Paths.modKeysFor 单独算候选（新名 → 按需回退旧名），
			// 与 Paths.modCandidates 完全同口径；根目录段没有模组上下文，故只看兼容开关。
			var modRel:String = Paths.modRelPath(fileToFind);
			var rootKeys:Array<String> = [modRel];
			if(Paths.psychCompat() && modRel != fileToFind) rootKeys.push(fileToFind);

			// Global mods first
			for(mod in Mods.getGlobalMods())
				for(k in Paths.modKeysFor(mod, fileToFind))
				{
					var folder:String = Paths.mods(mod + '/' + k);
					if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
				}

			// Then the engine's "mods/" root folder
			for(k in rootKeys)
			{
				var folder:String = Paths.mods(k);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}

			// And lastly, the loaded mod's folder
			if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
				for(k in Paths.modKeysFor(Mods.currentModDirectory, fileToFind))
				{
					var folder:String = Paths.mods(Mods.currentModDirectory + '/' + k);
					if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
				}
		}
		#end
		return foldersToCheck;
	}

	/** 读取 Meteoric 原生 mod.json；缺失或解析失败返回 null（不再读取 pack.json）。 */
	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED
		if(folder == null) folder = Mods.currentModDirectory;
		if(folder == null || folder.length == 0) return null;

		// Meteoric 原生 mod.json 优先；Psych 兼容打开、或该模组本身就是旧布局时回退 pack.json
		//（tjson 能容忍 Sonic 那类带尾逗号的 pack.json，不要换成 haxe.Json）。
		// 用 isLegacyLayout 兜底的理由同 hasLegacyEnabled：玩家启用了旧模组，
		// 它的 runsGlobally 之类的元数据必须读得到，否则资源/全局覆盖会莫名其妙失效。
		var meta:String = META_FILE;
		var path = Paths.mods(folder + '/' + meta);
		if(!FileSystem.exists(path) && (Paths.psychCompat() || isLegacyLayout(folder)))
		{
			meta = PSYCH_META_FILE;
			path = Paths.mods(folder + '/' + meta);
		}
		if(FileSystem.exists(path)) {
			try {
				#if sys
				var rawJson:String = File.getContent(path);
				#else
				var rawJson:String = Assets.getText(path);
				#end
				if(rawJson != null && rawJson.length > 0) return Json.parse(rawJson);
			} catch(e:Dynamic) {
				trace('[Mods] failed to read $meta for "$folder": $e');
			}
		}
		#end
		return null;
	}

	public static var updatedOnState:Bool = false;

	// Meteoric 启用列表在安卓上写到外部存储（AndroidStorage.root()），桌面保持相对路径
	public static inline function modsListPath():String
	{
		#if android
		return backend.AndroidStorage.root() + '/' + LIST_FILE;
		#else
		return LIST_FILE;
		#end
	}

	/** Psych 1.0.4 的 modsList.txt 路径（兼容打开时只读，不写）。 */
	public static inline function psychListPath():String
	{
		#if android
		return backend.AndroidStorage.root() + '/' + PSYCH_LIST_FILE;
		#else
		return PSYCH_LIST_FILE;
		#end
	}

	inline public static function parseList():ModsList {
		if(!updatedOnState) updateModList();
		var list:ModsList = {enabled: [], disabled: [], all: []};

		#if MODS_ALLOWED
		try {
			for (mod in CoolUtil.coolTextFile(modsListPath()))
			{
				if(mod.trim().length < 1) continue;

				var dat:Array<String> = mod.split("|");
				list.all.push(dat[0]);
				if (dat[1] == "1")
					list.enabled.push(dat[0]);
				else
					list.disabled.push(dat[0]);
			}
		} catch(e) {
			trace(e);
		}

		// Psych 1.0.4 兼容：额外合并读 modsList.txt。**只加读**——写入仍走 meteoric-mods.txt，
		// 否则会把存量 Meteoric 用户的启用状态清零。
		// 目录不存在的条目直接跳过：Psych 包常见「列表名 ≠ 目录名」（如 SonicTheFunk 对
		// SonicTheFunkChinese），这类靠 updateModList 扫盘 + hasMeta 补齐为默认启用。
		if(Paths.psychCompat()) {
			try {
				for (mod in CoolUtil.coolTextFile(psychListPath()))
				{
					if(mod.trim().length < 1) continue;
					var dat:Array<String> = mod.split("|");
					var name:String = dat[0];
					if(name == null || name.length == 0 || list.all.contains(name)) continue;
					if(!FileSystem.exists(Paths.mods(name))) continue;
					list.all.push(name);
					if (dat[1] == "1") list.enabled.push(name);
					else list.disabled.push(name);
				}
			} catch(e:Dynamic) { trace(e); }
		}
		#end
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
		
		// Scan for folders that aren't on the list yet
		for (folder in getModDirectories())
		{
			if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) &&
			!ignoreModFolders.contains(folder.toLowerCase()) && !added.contains(folder))
			{
				added.push(folder);
				// Meteoric 原生模组（带 mod.json）默认启用 —— 放进来即开箱即用；
				// 仅有 pack.json / 无元数据的旧目录默认关闭：既保持磁盘现状的零行为变化，
				// 也避免半成品 / Psych 格式模组被突然加载（缺贴图会让 TitleState/PlayState 崩溃）。
				list.push([folder, hasMeta(folder)]);
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
			trace('Could not save $LIST_FILE: $e');
		}
		updatedOnState = true;
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
