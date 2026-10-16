package backend;

#if (sys && !android)
import sys.io.File;
import sys.FileSystem;
#end

/**
 * 携带模式（Portable Mode）的数据搬迁：备份成 zip / 从 zip 还原。
 *
 * 落盘一律用**绝对**路径。只有 FlxSave.bind 需要「相对 applicationStorageDirectory 的
 * 上溯写法」（见 CoolUtil.portableRelativeTo 的说明），因为 openfl 会自己拼前缀。
 * 这里所有路径都直接喂 FileSystem，必须是绝对路径。
 *
 * ⚠ Haxe 的 haxe.zip 不是流式的：Entry.data 是整个文件内容，写入前必须全部读进内存。
 *   所以回放录像/谱面缓存这类大目录做了条数上限（addDirRecursive 的 maxFiles），
 *   否则会把内存吃光 —— 那正是这个功能最初要解决的问题。
 */
class SaveMover
{
	/** 备份文件名前缀。 */
	public static inline var BACKUP_PREFIX:String = 'MeteoricBackup-';

	/** 回放录像的文件数上限（单个文件通常几十 KB）。 */
	static inline var MAX_REPLAY_FILES:Int = 3000;
	/** 谱面缓存的文件数上限（缓存文件动辄几十 MB，必须限）。 */
	static inline var MAX_CACHE_FILES:Int = 60;

	/** 备份放到哪：引擎目录（.app 旁边）。 */
	public static function backupDir():String
	{
		return CoolUtil.appDirectory();
	}

	/** 列出现在引擎目录里的备份（文件名倒序 = 新的在前）。 */
	public static function listBackups():Array<String>
	{
		#if (sys && !android)
		var out:Array<String> = [];
		try
		{
			var dir:String = backupDir();
			if (!FileSystem.exists(dir)) return out;
			for (f in FileSystem.readDirectory(dir))
				if (f.indexOf(BACKUP_PREFIX) == 0 && StringTools.endsWith(f, '.zip')) out.push(dir + f);
		}
		catch (e:Dynamic) {}
		#end
		return out;
	}

	/** 最新的备份文件路径；没有则 null。 */
	public static function latestBackup():String
	{
		var l:Array<String> = listBackups();
		if (l.length == 0) return null;
		l.sort(function(a:String, b:String):Int return (a < b) ? 1 : ((a > b) ? -1 : 0));
		return l[0];
	}

	/**
	 * 把选中的数据打包成 zip 写到引擎目录。
	 * @return 备份文件路径；失败返回 null
	 */
	public static function backup(includeReplays:Bool, includeChartCache:Bool):String
	{
		#if (sys && !android)
		try
		{
			var entries:List<haxe.zip.Entry> = new List();
			var n:Int = 0;

			addFile(entries, 'funkin.sol', 'funkin.sol');
			addFile(entries, 'controls_v3.sol', 'controls_v3.sol');
			n += addSolFiles(entries);
			if (includeReplays) n += addDir(entries, Replay.getReplayDir(), 'replays', MAX_REPLAY_FILES);
			if (includeChartCache) n += addDir(entries, PackedCache.cacheDir(), 'chartcache', MAX_CACHE_FILES);

			if (entries.length == 0)
			{
				trace('[Move] 没有可备份的数据');
				return null;
			}

			var out:String = backupDir() + BACKUP_PREFIX + DateTools.format(Date.now(), '%Y-%m-%d_%H-%M-%S') + '.zip';
			var fo = File.write(out);
			new haxe.zip.Writer(fo).write(entries);
			fo.close();
			trace('[Move] 备份 ' + entries.length + ' 个文件（扫描 ' + n + ' 项）→ ' + out);
			return out;
		}
		catch (e:Dynamic)
		{
			trace('[Move] 备份失败：' + Std.string(e));
			return null;
		}
		#else
		return null;
		#end
	}

	/**
	 * 从 zip 还原。⚠ 覆盖同名文件。
	 * @return 还原的文件数；失败返回 -1
	 */
	public static function restore(zipPath:String):Int
	{
		#if (sys && !android)
		if (zipPath == null || !FileSystem.exists(zipPath)) return -1;
		try
		{
			var fi = File.read(zipPath);
			var list:List<haxe.zip.Entry> = haxe.zip.Reader.readZip(fi);
			fi.close();
			if (list == null) return -1;

			var settingsDir:String = settingsAbsDir();
			if (settingsDir == null) settingsDir = './';

			var n:Int = 0;
			for (e in list)
			{
				var name:String = e.fileName;
				var target:String = null;
				var slash:Int = name.lastIndexOf('/');
				if (slash < 0)
				{
					// 顶层条目：设置/键位/插件存档 → 生效的存档目录
					if (StringTools.endsWith(name, '.sol')) target = settingsDir + name;
				}
				else if (name.indexOf('replays/') == 0) target = Replay.getReplayDir() + name.substr('replays/'.length);
				else if (name.indexOf('chartcache/') == 0) target = PackedCache.cacheDir() + '/' + name.substr('chartcache/'.length);
				if (target == null) continue;

				var dir:String = target.substr(0, target.lastIndexOf('/') + 1);
				try
				{
					if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
				}
				catch (e2:Dynamic) {}

				var bytes:haxe.io.Bytes = e.data;
				if (bytes == null) bytes = haxe.zip.Reader.unzip(e);
				if (bytes == null) continue;
				// ⚠ saveContent 只收 String；.sol 是二进制，必须走 saveBytes
				File.saveBytes(target, bytes);
				n++;
			}
			trace('[Move] 还原 ' + n + ' 个文件（来源 ' + zipPath + '）');
			return n;
		}
		catch (e:Dynamic)
		{
			trace('[Move] 还原失败：' + Std.string(e));
			return -1;
		}
		#else
		return -1;
		#end
	}

	static function addFile(entries:List<haxe.zip.Entry>, path:String, name:String):Void
	{
		try
		{
			if (!FileSystem.exists(path)) return;
			var bytes:haxe.io.Bytes = File.getBytes(path);
			if (bytes == null) return;
			entries.push({
				fileName: name,
				fileSize: bytes.length,
				fileTime: Date.now(),
				compressed: false,
				dataSize: 0,
				data: bytes,
				crc32: null
			});
		}
		catch (e:Dynamic) {}
	}

	/** 把设置目录里其它 .sol（插件/扩展存档）也带上。 */
	static function addSolFiles(entries:List<haxe.zip.Entry>):Int
	{
		var n:Int = 0;
		try
		{
			var dir:String = settingsAbsDir();
			if (dir == null || !FileSystem.exists(dir)) return 0;
			for (f in FileSystem.readDirectory(dir))
			{
				if (f.indexOf(BACKUP_PREFIX) == 0) continue;
				if (!StringTools.endsWith(f, '.sol')) continue;
				if (f == 'funkin.sol' || f == 'controls_v3.sol') continue; // 上面已加
				addFile(entries, dir + f, f);
				n++;
			}
		}
		catch (e:Dynamic) {}
		return n;
	}

	/** 递归把目录塞进 zip（受 maxFiles 限制；超限就截断并告知）。 */
	static function addDir(entries:List<haxe.zip.Entry>, root:String, prefix:String, maxFiles:Int):Int
	{
		var n:Int = 0;
		try
		{
			if (!FileSystem.exists(root)) return 0;
			var queue:Array<{dir:String, rel:String}> = [{dir: root, rel: prefix}];
			while (queue.length > 0 && entries.length < maxFiles)
			{
				var cur:Dynamic = queue.shift();
				for (f in FileSystem.readDirectory(cur.dir))
				{
					if (entries.length >= maxFiles) break;
					if (f.indexOf(BACKUP_PREFIX) == 0) continue;
					var full:String = cur.dir + (StringTools.endsWith(cur.dir, '/') ? '' : '/') + f;
					if (FileSystem.isDirectory(full))
					{
						queue.push({dir: full, rel: cur.rel + '/' + f});
					}
					else
					{
						addFile(entries, full, cur.rel + '/' + f);
						n++;
					}
				}
			}
		}
		catch (e:Dynamic) {}
		return n;
	}

	/** 设置文件所在目录（绝对）。便携相对写法要反解。 */
	static function settingsAbsDir():String
	{
		var portable:String = CoolUtil.portableSavePath();
		if (portable != null)
		{
			var storage:String = lime.system.System.applicationStorageDirectory;
			if (storage != null && storage.length > 0) return haxe.io.Path.normalize('$storage/$portable');
		}
		var sd:String = lime.system.System.applicationStorageDirectory;
		if (sd != null && sd.length > 0)
		{
			if (sd.charAt(sd.length - 1) != '/') sd += '/';
			return sd + CoolUtil.getSavePath();
		}
		return null;
	}
}