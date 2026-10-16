package backend;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

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

	// ================= 备份格式 =================

	/** 自定义二进制格式的魔数（Seiun Engine 用 "SEB1"，这里用自己的 "MSB1"）。 */
	static inline var BIN_MAGIC:String = 'MSB1';
	/** 自定义二进制格式的版本号（结构变化时 +1，还原时按版本校验）。 */
	static inline var BIN_VERSION:Int = 1;
	/** 自定义二进制格式的文件扩展名。 */
	public static inline var BIN_EXT:String = '.msb';

	public static function extOf(f:BackupFormat):String
	{
		if (f == BackupFormat.ZIP) return '.zip';
		if (f == BackupFormat.BINARY) return BIN_EXT;
		return '.json';
	}

	public static function defaultName(f:BackupFormat):String
	{
		if (f == BackupFormat.ZIP) return BACKUP_PREFIX + 'zip';
		if (f == BackupFormat.BINARY) return BACKUP_PREFIX + 'bin';
		return BACKUP_PREFIX + 'json';
	}

	/**
	 * 导出一份备份。
	 *
	 * @param format     备份格式
	 * @param replays    是否包含回放录像（ZIP / BINARY 生效；JSON 本就不含）
	 * @param chartCache 是否包含谱面缓存（ZIP / BINARY 生效）
	 * @return 写出的文件绝对路径；失败 null
	 */
	public static function exportBackup(format:BackupFormat, replays:Bool, chartCache:Bool):String
	{
		#if (sys && !android)
		var stamp:String = DateTools.format(Date.now(), '%Y-%m-%d_%H-%M-%S');
		try
		{
			if (format == BackupFormat.ZIP) return zipBackup(replays, chartCache, stamp);
			if (format == BackupFormat.BINARY) return binBackup(replays, chartCache, stamp);
			return jsonBackup(stamp);
		}
		catch (e:Dynamic)
		{
			trace('[Move] 导出失败（' + extOf(format) + '）：' + Std.string(e));
		}
		#else
		return null;
		#end
		return null;
	}

	static function zipBackup(replays:Bool, chartCache:Bool, stamp:String):String
	{
		var entries:List<haxe.zip.Entry> = new List();
		addFile(entries, 'funkin.sol', 'funkin.sol');
		addFile(entries, 'controls_v3.sol', 'controls_v3.sol');
		addSolFiles(entries);
		if (replays) addDir(entries, Replay.getReplayDir(), 'replays', MAX_REPLAY_FILES);
		if (chartCache) addDir(entries, PackedCache.cacheDir(), 'chartcache', MAX_CACHE_FILES);
		if (entries.length == 0) return null;
		var out:String = backupDir() + BACKUP_PREFIX + 'zip-' + stamp + '.zip';
		var fo = File.write(out);
		new haxe.zip.Writer(fo).write(entries);
		fo.close();
		trace('[Move] 备份(zip) ' + entries.length + ' 项 → ' + out);
		return out;
	}

	/**
	 * 自定义二进制格式：MSB1 | version | flags | itemCount | [nameLen|name|...] | payload
	 * 每项的 payload 长度在前（Int32），便于跳过不认识/不需要的项。
	 */
	static function binBackup(replays:Bool, chartCache:Bool, stamp:String):String
	{
		var items:Array<{name:String, data:Bytes}> = [];
		collectBinItems(items, replays, chartCache);
		if (items.length == 0) return null;

		var flags:Int = (replays ? 1 : 0) | (chartCache ? 2 : 0);
		var body = new haxe.io.BytesBuffer();
		body.addByte(BIN_VERSION);
		body.addByte(flags);
		body.add(int32be(items.length));
		for (it in items)
		{
			var nb:Bytes = Bytes.ofString(it.name);
			body.add(int32be(nb.length));
			body.add(nb);
			body.add(int32be(it.data.length));
			body.add(it.data);
		}
		var payload:Bytes = body.getBytes();
		var out:Bytes = Bytes.ofString(BIN_MAGIC);
		// 拼接魔数与负载
		var outBuf = new BytesBuffer();
		outBuf.add(out);
		outBuf.add(payload);
		out = outBuf.getBytes();

		var path:String = backupDir() + BACKUP_PREFIX + 'bin-' + stamp + BIN_EXT;
		File.saveBytes(path, out);
		trace('[Move] 备份(bin) ' + items.length + ' 项，' + out.length + ' 字节 → ' + path);
		return path;
	}

	static function collectBinItems(items:Array<{name:String, data:Bytes}>, replays:Bool, chartCache:Bool):Void
	{
		addBytesItem(items, 'funkin', settingsAbsDir() + 'funkin.sol');
		addBytesItem(items, 'controls', settingsAbsDir() + 'controls_v3.sol');
		if (replays)
		{
			// 回放量大，统一打成一个 tar 式原始块（自定义格式内部用长度前缀即可）
			var pack = new haxe.io.BytesBuffer();
			var rd:String = Replay.getReplayDir();
			addDirBytes(pack, rd, 'replays/', MAX_REPLAY_FILES);
			items.push({name: 'replays', data: pack.getBytes()});
		}
		if (chartCache)
		{
			var pack = new haxe.io.BytesBuffer();
			addDirBytes(pack, PackedCache.cacheDir(), 'chartcache/', MAX_CACHE_FILES);
			items.push({name: 'chartcache', data: pack.getBytes()});
		}
	}

	static function addBytesItem(items:Array<{name:String, data:Bytes}>, name:String, path:String):Void
	{
		try
		{
			if (!FileSystem.exists(path)) return;
			items.push({name: name, data: File.getBytes(path)});
		}
		catch (e:Dynamic) {}
	}

	/** 把目录下的文件按「相对路径 + Int32 长度 + 内容」串进 buffer（自定义块格式）。 */
	static function addDirBytes(buf:haxe.io.BytesBuffer, root:String, prefix:String, maxFiles:Int):Void
	{
		try
		{
			if (!FileSystem.exists(root)) return;
			var n:Int = 0;
			for (f in FileSystem.readDirectory(root))
			{
				if (n >= maxFiles) break;
				if (f.indexOf(BACKUP_PREFIX) == 0) continue;
				var p:String = root + (StringTools.endsWith(root, '/') ? '' : '/') + f;
				if (FileSystem.isDirectory(p)) continue;
				var b:Bytes = File.getBytes(p);
				if (b == null) continue;
				var rel:Bytes = Bytes.ofString(prefix + f);
				buf.add(int32be(rel.length));
				buf.add(rel);
				buf.add(int32be(b.length));
				buf.add(b);
				n++;
			}
		}
		catch (e:Dynamic) {}
	}

	/** 结构化 JSON：只导出设置类数据（人类可读、体积最小）。 */
	static function jsonBackup(stamp:String):String
	{
		var out:Dynamic = {};
		out.version = 1;
		out.timestamp = Date.now();
		out.engine = 'Meteoric Engine ' + Main.meVersion;
		out.commit = backend.GitInfo.summary();
		out.settings = captureSettingsJson();
		out.keybinds = captureKeybindsJson();
		var path:String = backupDir() + BACKUP_PREFIX + 'json-' + stamp + '.json';
		File.saveContent(path, haxe.Json.stringify(out, '\t'));
		trace('[Move] 备份(json) → ' + path);
		return path;
	}

	static function captureSettingsJson():Dynamic
	{
		var d:Dynamic = {};
		if (ClientPrefs.data == null) return d;
		for (k in Reflect.fields(ClientPrefs.data))
		{
			// 跳过 Map / 数组等非 JSON 友好的类型（键位另有专门结构）
			var v:Dynamic = Reflect.field(ClientPrefs.data, k);
			// 只收基础类型：Array / Date 走 Json 往返会变形或报错；
			// Map 存的是键位等结构化数据，由 captureKeybindsJson 单独处理。
			if (v == null) continue;
			var cls:Class<Dynamic> = Type.getClass(v);
			if (cls == Array || cls == Date) continue;
			Reflect.setField(d, k, v);
		}
		return d;
	}

	static function captureKeybindsJson():Dynamic
	{
		var d:Dynamic = {};
		try
		{
			for (k in ClientPrefs.keyBinds.keys())
			{
				var arr:Array<Int> = [];
				for (kk in ClientPrefs.keyBinds.get(k)) arr.push(kk);
				Reflect.setField(d, k, arr);
			}
		}
		catch (e:Dynamic) {}
		return d;
	}

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

	/** Int32 大端序列化成 4 字节。Haxe 的 BytesBuffer 只有 addByte/addBytes，
	 *  没有 writeInt32 —— 用 Bytes 手工拼（大端，与自定义格式的头部约定一致）。 */
	static inline function int32be(v:Int):Bytes
	{
		var b = Bytes.alloc(4);
		b.set(0, (v >> 24) & 0xFF);
		b.set(1, (v >> 16) & 0xFF);
		b.set(2, (v >> 8) & 0xFF);
		b.set(3, v & 0xFF);
		return b;
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