package cne;

#if (MODS_ALLOWED && sys)
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * CNE mod 的 ZIP 装载层（「CNE 模组兼容」开关的包管理底层）。
 *
 * 为什么要暂存而不是直接挂载：
 *  - Meteoric/Psych 的资源管线是**文件系统路径**管线（`Paths.image/sound/json` 全部走
 *    `FileSystem.exists` + `File.getContent` + `FlxGraphic.fromFile` / `Sound.fromFile`），
 *    没有 CNE 那种 `AssetsLibraryList` + `__proxy` 的虚拟资源树，内存挂载意味着重写整条
 *    资源管线；因此 zip mod 首次被访问时透明解包到 `mods/_cnestage/<mod>/`，之后与普通
 *    文件夹 mod 完全同构（`Paths.mods()` 只做一次前缀重映射，48 处调用点无需改动）。
 *  - 暂存目录带指纹文件（zip 体积 + mtime），zip 被替换后自动重解；`_cnestage` 已登记进
 *    `Mods.ignoreModFolders`，不会出现在 Mod 列表里，玩家可以随时整个删掉。
 *
 * 设计纪律：
 *  - 同名真实文件夹永远优先（`remapKey` 只在 `mods/<name>` 不是目录时才劫持）。
 *  - 任何失败都不抛异常到调用方：返回 null，引擎退回"找不到该 mod 资源"的既有行为。
 */
class CneZipStore
{
	/** 暂存根目录名（相对 `mods/`），同时登记在 `Mods.ignoreModFolders`。 */
	public static final STAGE_DIR:String = '_cnestage';

	/** 允许被识别为 zip mod 的扩展名（小写比较）。 */
	static final ZIP_EXTS:Array<String> = ['.zip', '.cnz'];

	/** mod 名 → 暂存目录（解析失败记录为空串，避免反复重试大包解压）。 */
	static var stageDirs:Map<String, String> = new Map();

	/** mod 名 → 解包失败的 zip 指纹：同指纹不重试，zip 变了才重试。 */
	static var failedFingerprints:Map<String, String> = new Map();

	/**
	 * 丢弃暂存缓存（**不删文件**），下次访问重新校验 zip 指纹。
	 * 引擎在 Mod 列表刷新时调用（`cne.CneModCompat.clearCaches`）：玩家在运行中替换 zip
	 * 后打开 Mod 列表即可生效，不必重启。
	 */
	public static function invalidate():Void
	{
		stageDirs = new Map();
		failedFingerprints = new Map();
	}

	/**
	 * `mods/` 根目录 —— 必须与 `Paths.modsRaw('')` 同源（安卓是外部存储根 + `/mods/`），
	 * 否则 zip mod 的暂存目录会和引擎实际读资源的根目录不一致。
	 */
	public static function modsRoot():String
	{
		return backend.Paths.modsRaw('');
	}

	/** `mods/` 下所有 zip mod 名（不含扩展名，按目录顺序）。 */
	public static function zipNames():Array<String>
	{
		var out:Array<String> = [];
		var root:String = modsRoot();
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root)) return out;

		var entries:Array<String> = null;
		try entries = FileSystem.readDirectory(root) catch (e:Dynamic) return out;
		for (entry in entries)
		{
			if (entry == null || entry.length == 0) continue;
			var full:String = root + entry;
			if (FileSystem.isDirectory(full)) continue;
			if (zipPathOf(entry) != null) out.push(Path.withoutExtension(entry));
		}
		return out;
	}

	/** 该 mod 名是否存在对应的 zip 包。 */
	public static function isZipMod(name:String):Bool
	{
		return zipPath(name) != null;
	}

	/**
	 * 把 `Paths.mods()` 的 key（`<mod>/<rel>` 或 `<mod>`）重映射到暂存目录。
	 * 非 zip mod（含同名真实文件夹、非 mod 前缀的裸 key）返回 null，调用方原样处理。
	 */
	public static function remapKey(key:String):String
	{
		if (!enabled() || key == null || key.length == 0) return null;

		var slash:Int = key.indexOf('/');
		var seg:String = slash < 0 ? key : key.substr(0, slash);
		if (seg.length == 0 || seg == STAGE_DIR) return null;

		var root:String = modsRoot();
		var plain:String = root + seg;
		// 真实文件夹优先：同名文件夹与 zip 并存时不劫持
		if (FileSystem.exists(plain) && FileSystem.isDirectory(plain)) return null;
		if (zipPath(seg) == null) return null;

		var dir:String = stage(seg);
		if (dir == null) return null;

		var rest:String = slash < 0 ? '' : key.substr(slash); // 含前导 '/'
		return dir + rest;
	}

	/** 确保 zip mod 已暂存，返回暂存目录（失败返回 null）。 */
	public static function stage(name:String):String
	{
		if (stageDirs.exists(name)) {
			var cached:String = stageDirs.get(name);
			return (cached != null && cached.length > 0) ? cached : null;
		}

		var zip:String = zipPath(name);
		if (zip == null) return null;

		var root:String = modsRoot();
		var stageRoot:String = root + STAGE_DIR + '/';
		var dir:String = stageRoot + name;
		var stampPath:String = stageRoot + name + '.stamp';
		var fp:String = fingerprint(zip);

		// 同一份坏 zip 只报一次错、只试一次解包（否则每次资源查找都会重试）
		if (failedFingerprints.exists(name) && failedFingerprints.get(name) == fp) return null;

		if (FileSystem.exists(dir) && FileSystem.isDirectory(dir) && stampMatches(stampPath, fp))
		{
			stageDirs.set(name, dir);
			return dir;
		}

		try
		{
			deleteRecursive(dir);
			if (!FileSystem.exists(stageRoot)) FileSystem.createDirectory(stageRoot);
			FileSystem.createDirectory(dir);

			cne.CneModCompat.log('staging zip mod "' + name + '" → ' + dir);
			var t0:Float = haxe.Timer.stamp();
			backend.ZipReader.extract(zip, dir);
			flattenSingleTop(dir);
			File.saveContent(stampPath, fp);
			cne.CneModCompat.log('zip mod "' + name + '" staged in ' + Std.int((haxe.Timer.stamp() - t0) * 1000) + 'ms');
		}
		catch (e:Dynamic)
		{
			cne.CneModCompat.log('failed to stage zip mod "' + name + '": ' + Std.string(e));
			deleteRecursive(dir);
			failedFingerprints.set(name, fp);
			stageDirs.set(name, '');
			return null;
		}

		stageDirs.set(name, dir);
		return dir;
	}

	/** zip 包路径（不存在返回 null）。 */
	public static function zipPath(name:String):String
	{
		if (name == null || name.length == 0) return null;
		var root:String = modsRoot();
		for (ext in ZIP_EXTS)
		{
			var p:String = root + name + ext;
			if (FileSystem.exists(p) && !FileSystem.isDirectory(p)) return p;
		}
		return null;
	}

	// ==================== 内部 ====================

	static function enabled():Bool
	{
		return cne.CneModCompat.isEnabled();
	}

	static function zipPathOf(entry:String):String
	{
		var lower:String = entry.toLowerCase();
		for (ext in ZIP_EXTS)
			if (lower.length > ext.length && lower.endsWith(ext)) return entry;
		return null;
	}

	static function fingerprint(zip:String):String
	{
		try
		{
			var stat = FileSystem.stat(zip);
			return Std.string(stat.size) + '|' + Std.string(stat.mtime.getTime());
		}
		catch (e:Dynamic)
		{
			return 'unknown';
		}
	}

	static function stampMatches(stampPath:String, fp:String):Bool
	{
		if (!FileSystem.exists(stampPath)) return false;
		try
		{
			return StringTools.trim(File.getContent(stampPath)) == fp;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	static function deleteRecursive(path:String):Void
	{
		if (path == null || path.length == 0 || !FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path))
		{
			var entries:Array<String> = null;
			try entries = FileSystem.readDirectory(path) catch (e:Dynamic) { entries = []; }
			for (f in entries) deleteRecursive(path + '/' + f);
			try FileSystem.deleteDirectory(path) catch (e:Dynamic) {}
		}
		else
		{
			try FileSystem.deleteFile(path) catch (e:Dynamic) {}
		}
	}

	/**
	 * 玩家把 zip 打成"外面再套一层文件夹"时（`mod.zip/my mod/data/...`），
	 * 把唯一顶层目录的内容上提一层。只处理"顶层恰好一个目录"的情况，避免误伤。
	 */
	static function flattenSingleTop(dir:String):Void
	{
		var entries:Array<String> = null;
		try entries = FileSystem.readDirectory(dir) catch (e:Dynamic) return;
		if (entries.length != 1) return;

		var only:String = entries[0];
		var inner:String = dir + '/' + only;
		if (!FileSystem.isDirectory(inner)) return;

		var children:Array<String> = null;
		try children = FileSystem.readDirectory(inner) catch (e:Dynamic) return;
		for (c in children)
		{
			try FileSystem.rename(inner + '/' + c, dir + '/' + c) catch (e:Dynamic) {}
		}
		try FileSystem.deleteDirectory(inner) catch (e:Dynamic) {}
	}
}
#end
