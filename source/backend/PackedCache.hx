package backend;

#if sys
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;
import sys.FileSystem;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import lime.system.System;
#end

/**
 * 超大谱面「合并后结果」的磁盘缓存。
 *
 * ===== 为什么缓存合并后的簇，而不是原始 JSON =====
 * 原始 JSON：66 个 Part 共 79GB —— 装不下、写了也没意义。
 * 合并后的簇：每簇 ~20 字节定长头 + ≤12 个偏移，几十万簇也只有**几十 MB**。
 * 于是「第二次进同一首歌」从「重新扫 79GB」变成「读几十 MB」，秒开。
 *
 * ===== 数值编码 =====
 * 时间/长条用 Int32 存**毫秒×100**（谱面时间轴最大约 3.5e5 ms → 3.5e7，
 * 远小于 Int32 上限 2.1e9），精度 0.01ms，远细于一帧 16.6ms。
 * 这样全部字段都能用 Int32 读写 —— hxcpp/neko 的 Bytes **没有**字节级 API
 * （只有 getInt32/getFloat/getDouble），用 Int32 是唯一既紧凑又可移植的编码。
 *
 * ===== 失效判定 =====
 * 缓存键 = 各 Part 的「相对路径 + 字节大小 + mtime」列表的哈希。
 * 任一 Part 被改动/增删 → 键变化 → 缓存失效重扫。不会读到过期谱面。
 */
class PackedCache
{
	// magic + 版本；版本变了直接忽略旧缓存（字段布局变化时必须 bump）
	static inline var MAGIC:String = 'MCPK';
	static inline var VERSION:Int = 1;

	/**
	 * 缓存根目录：**必须在 .app bundle 之外**。
	 *
	 * ⚠⚠ 实测踩坑（2026-10-06）：.app bundle 是**密封**的，往里面写任何运行时文件都会
	 *   破坏代码签名 —— 试过 `Contents/MacOS/cache/`（被当子组件递归校验 → "code object is
	 *   not signed at all"）和 `Contents/Resources/cache/`（密封清单不匹配 → 签名同样失效），
	 *   两者都会让**双击后图标在 dock 一直跳、起不来**。
	 *
	 * 正确做法：用 `System.applicationStorageDirectory`（引擎在 Replay.hx 里存回放用的同一位置），
	 *   它落在用户 Application Support 下，天然在 bundle 之外，且不需要管理员权限。
	 */
	public static function cacheDir():String
	{
		#if sys
		var candidates:Array<String> = [];
		// 携带模式 + 用户勾选「谱面缓存跟着走」时，缓存优先落便携目录。
		// ⚠ 绝对路径（候选列表本身就是绝对路径体系，见下面的 Sys.programPath 兜底）。
		if (ClientPrefs.data != null && ClientPrefs.data.portableChartCache && CoolUtil.isPortable())
		{
			candidates.push(CoolUtil.portableDir() + 'chartcache');
		}
		try
		{
			var storage = System.applicationStorageDirectory;
			if (storage != null && storage.length > 0) candidates.push(storage + '/chartcache');
		}
		catch (e:Dynamic) {}
		try
		{
			// 非 bundle 布局（直接在目录里跑二进制）时的兜底
			candidates.push(haxe.io.Path.directory(Sys.programPath()) + '/chartcache');
		}
		catch (e2:Dynamic) {}
		candidates.push('./chartcache');
		for (c in candidates)
		{
			try
			{
				if (!FileSystem.exists(c)) FileSystem.createDirectory(c);
				if (FileSystem.exists(c)) return c;
			}
			catch (e2:Dynamic) {}
		}
		return null;
		#else
		return null;
		#end
	}

	/** 由 Part 文件清单算出缓存键（任一 Part 的大小/mtime 变化都会改变键） */
	public static function keyForParts(paths:Array<String>, song:String):String
	{
		#if sys
		var sb:StringBuf = new StringBuf();
		sb.add(song);
		sb.add('|');
		var parts:Array<String> = paths.copy();
		parts.sort(Reflect.compare); // 与顺序无关，避免 Part 顺序不同导致重复缓存
		for (p in parts)
		{
			sb.add(p);
			sb.add(':');
			try
			{
				var st = FileSystem.stat(p);
				sb.add(Std.string(st.size));
				sb.add('@');
				sb.add(Std.string(st.mtime.getTime()));
			}
			catch (e:Dynamic)
			{
				sb.add('missing');
			}
			sb.add(';');
		}
		return hash(sb.toString());
		#else
		return null;
		#end
	}

	static function hash(s:String):String
	{
		// FNV-1a 32bit，够用且无依赖
		var h:Int = 0x811c9dc5;
		for (i in 0...s.length)
		{
			h ^= s.charCodeAt(i);
			h = (h * 0x01000193) & 0xFFFFFFFF;
		}
		var t:String = Std.string(h);
		while (t.length < 8) t = '0' + t;
		return t;
	}

	/**
	 * 校验缓存 meta 与当前扫描设置是否一致。
	 *
	 * ⚠ 缓存键只覆盖 Part 的路径/大小/mtime，**不包含合并参数**。只改
	 * `ghostRange` / `ghostDensity` / `boundedOffsKeep` / `skipGhostNotes` 时
	 * 键不变；若不校验就直接复用旧簇，计分密度与视觉会静默沿用旧语义
	 * （例如合并窗口 15→30ms 后仍读旧簇）。返回 false 时调用方按未命中处理，
	 * 重新扫描并由 `save()` 覆盖同一键的旧文件。
	 *
	 * 旧缓存没有 `merge` 字段：历史默认 `skipGhostNotes=true`，按 true 兼容；
	 * 当前为 false 时才强制重扫。其余字段缺失一律视为不可信（重扫）。
	 */
	public static function metaMatches(meta:Dynamic, expectParts:Int, ghostRange:Float, ghostDensity:Bool, keepLimit:Int, doMerge:Bool):Bool
	{
		if (meta == null) return false;
		if (expectParts > 0 && meta.parts != null && Std.int(meta.parts) != expectParts) return false;
		if (meta.ghostRange == null || Math.abs((cast meta.ghostRange : Float) - ghostRange) > 0.0001) return false;
		if (meta.ghostDensity == null || (meta.ghostDensity == true) != ghostDensity) return false;
		if (meta.keep == null || Std.int(meta.keep) != keepLimit) return false;
		var cachedMerge:Bool = (meta.merge == null) ? true : (meta.merge == true);
		if (cachedMerge != doMerge) return false;
		return true;
	}

	/** 读缓存 → 命中返回簇数组，失败返回 null */
	/** 最近一次 load() 读出的缓存 meta（调用方据此补齐 packedSectionCount 等扫描路径字段）。 */
	public static var lastMeta:Dynamic = null;

	public static function load(key:String, expectParts:Int):Array<PackedChart>
	{
		lastMeta = null;
		#if sys
		var dir:String = cacheDir();
		if (dir == null || key == null) return null;
		var path:String = dir + '/packed-' + key + '.bin';
		if (!FileSystem.exists(path)) return null;
		try
		{
			var input:FileInput = File.read(path);
			var bytes:Bytes = input.readAll();
			input.close();
			if (bytes.length < 16) return null;
			var pos:Int = 0;
			if (bytes.getString(pos, 4) != MAGIC) return null;
			pos += 4;
			if (bytes.getInt32(pos) != VERSION) return null;
			pos += 4;
			var metaLen:Int = bytes.getInt32(pos);
			pos += 4;
			if (metaLen < 0 || pos + metaLen > bytes.length) return null;
			var meta:Dynamic = haxe.Json.parse(bytes.getString(pos, metaLen));
			lastMeta = meta;
			pos += metaLen;
			var count:Int = bytes.getInt32(pos);
			pos += 4;
			if (count <= 0 || expectParts > 0 && meta.parts != expectParts) return null;
			if (pos + count * 20 > bytes.length + 4096) return null; // 明显截断

			var out:Array<PackedChart> = [];
			out.resize(count);
			for (i in 0...count)
			{
				var c = new PackedChart();
				var tMilli:Int = bytes.getInt32(pos);
				pos += 4;
				c.t = tMilli / 100.0;
				var flags:Int = bytes.getInt32(pos);
				pos += 4;
				c.lane = flags & 0xF;
				c.mustHit = (flags & 0x10) != 0;
				c.gfNote = (flags & 0x20) != 0;
				var dens:Int = bytes.getInt32(pos);
				pos += 4;
				c.density = dens;
				var holdMilli:Int = bytes.getInt32(pos);
				pos += 4;
				c.holdLength = holdMilli / 100.0;
				var seq:Int = bytes.getInt32(pos);
				pos += 4;
				c.chartSeq = seq;
				var oc:Int = bytes.getInt32(pos);
				pos += 4;
				if (oc > 0)
				{
					c.offs = [];
					c.offs.resize(oc);
					for (j in 0...oc)
					{
						c.offs[j] = bytes.getInt32(pos) / 100.0;
						pos += 4;
					}
				}
				c.offsKeep = dens; // 簇内原始数量 == density（有界化后仍以 density 为准）
				out[i] = c;
			}
			return out;
		}
		catch (e:Dynamic)
		{
			return null;
		}
		#else
		return null;
		#end
	}

	/** 写缓存。失败静默（缓存是优化，不是正确性依赖） */
	public static function save(key:String, clusters:Array<PackedChart>, meta:Dynamic):Void
	{
		#if sys
		var dir:String = cacheDir();
		if (dir == null || key == null || clusters == null || clusters.length == 0) return;
		try
		{
			var bb:BytesBuffer = new BytesBuffer();
			bb.addString(MAGIC);
			bb.addInt32(VERSION);
			var metaStr:String = haxe.Json.stringify(meta);
			var mb:Bytes = Bytes.ofString(metaStr);
			bb.addInt32(mb.length);
			bb.add(mb);
			bb.addInt32(clusters.length);
			for (c in clusters)
			{
				bb.addInt32(Std.int(c.t * 100));
				var flags:Int = (c.lane & 0xF) | (c.mustHit ? 0x10 : 0) | (c.gfNote ? 0x20 : 0);
				bb.addInt32(flags);
				bb.addInt32(c.density);
				bb.addInt32(Std.int(c.holdLength * 100));
				bb.addInt32(c.chartSeq);
				var n:Int = (c.offs == null) ? 0 : c.offs.length;
				bb.addInt32(n);
				if (n > 0)
					for (o in c.offs) bb.addInt32(Std.int(o * 100));
			}
			// 一次性落盘：File.saveBytes 比手动 FileOutput 简单且可移植
			// （FileOutput 只 extends haxe.io.Output，没有便捷的 writeBytes）。
			// 写失败只影响性能不影响正确性，故完全静默。
			File.saveBytes(dir + '/packed-' + key + '.bin', bb.getBytes());
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 列出全部谱面缓存（供设置页显示/清理） */
	public static function listCaches():Array<Dynamic>
	{
		#if sys
		var out:Array<Dynamic> = [];
		var dir:String = cacheDir();
		if (dir == null) return out;
		try
		{
			for (f in FileSystem.readDirectory(dir))
			{
				if (StringTools.startsWith(f, 'packed-') && StringTools.endsWith(f, '.bin'))
				{
					var p:String = dir + '/' + f;
					var st = FileSystem.stat(p);
					out.push({file: p, name: f, size: st.size, mtime: st.mtime.getTime()});
				}
			}
		}
		catch (e:Dynamic) {}
		return out;
		#else
		return [];
		#end
	}

	public static function clearAll():Int
	{
		#if sys
		var n:Int = 0;
		var dir:String = cacheDir();
		if (dir == null) return 0;
		for (c in listCaches())
		{
			try
			{
				FileSystem.deleteFile(c.file);
				n++;
			}
			catch (e:Dynamic) {}
		}
		return n;
		#else
		return 0;
		#end
	}
}
