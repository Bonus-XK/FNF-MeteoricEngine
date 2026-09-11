package backend;

import objects.Note.CastNote;
import haxe.Json;
import sys.io.File;
import sys.FileSystem;
import haxe.crypto.Md5;

/**
 * Turbo 高密度谱面分析（移植自 SeiunEngine 最新版 TurboDensity.hx，按 Meteoric 适配）：
 * - 只保留「聚合区分析 + 侧车缓存」；Seiun 最新版已移除的假视觉流带/密度分箱不移植。
 * - 聚合区 = unspawnNotes 中一段连续的、不含长条的极高密度 tap 区间（100ms 分箱，
 *   每箱 ≥ TURBO_AGGREGATE_NPS*binMs/1000 且区间 ≥ minZoneMs）。聚合区内走真实 Note
 *   物化 + 对象上限（视觉完整）；聚合区外、过载时走数据级批量结算（fastSkip）。
 * - 缓存：按 song|mod|fingerprint 指纹落盘到 crash/turbo_cache/<md5>.bin，二次加载免分析。
 *   （analysis 只是读 3.3 万条 CastNote 计数，本身很快；缓存主要省 CPU 与保持一致性。）
 */
typedef TurboZone = {
	var startIndex:Int;
	var endIndex:Int;
	var startTime:Float;
	var endTime:Float;
}

class TurboDensity
{
	public static inline final CACHE_VERSION:Int = 1;
	// 聚合区判定：每秒 Note 数（含合并后 density 口径的原始计数用 strumTime 逐条统计）
	public static inline final TURBO_AGGREGATE_NPS:Float = 4000;

	/** 谱面指纹：与 Seiun 同款 FNV-1a，字段改为 CastNote 可读的打包代理字段。 */
	public static function chartFingerprint(notes:Array<CastNote>):Int
	{
		var h:Int = 0x811C9DC5;
		if (notes == null)
			return h;
		for (pn in notes)
		{
			if (pn == null)
			{
				h = (h * 31 + 0xFFFF) & 0x7FFFFFFF;
				continue;
			}
			h = (h * 31 + Std.int(pn.strumTime * 1000)) & 0x7FFFFFFF;
			h = (h * 31 + pn.noteData) & 0x7FFFFFFF;
			h = (h * 31 + Std.int(pn.holdLength * 1000)) & 0x7FFFFFFF;
			h = (h * 31 + Std.int(pn.density * 1000)) & 0x7FFFFFFF;
		}
		return h;
	}

	/**
	 * 100ms 分箱 + 相邻箱合并。聚合判定：无长条（holdLength<=0）的箱且计数 ≥ 阈值；
	 * 连续聚合箱构成 zone（≥ minZoneMs）。
	 */
	public static function buildZones(unspawnNotes:Array<CastNote>, aggregateNPS:Float = TURBO_AGGREGATE_NPS,
		binMs:Int = 100, minZoneMs:Float = 500):Array<TurboZone>
	{
		if (unspawnNotes == null || unspawnNotes.length == 0)
			return [];

		var lastTime:Float = unspawnNotes[unspawnNotes.length - 1].strumTime;
		if (lastTime < 0) lastTime = 0;
		var binCount:Int = Std.int(lastTime / binMs) + 2;
		var bins:Array<Int> = [for (i in 0...binCount) 0];
		var holdBins:Array<Bool> = [for (i in 0...binCount) false];

		for (pn in unspawnNotes)
		{
			var b:Int = Std.int(pn.strumTime / binMs);
			if (b < 0) b = 0;
			if (b >= binCount) b = binCount - 1;
			bins[b]++;
			if (pn.holdLength > 0)
				holdBins[b] = true;
		}

		var thresholdPerBin:Int = Math.ceil(aggregateNPS * binMs / 1000.0);
		var agg:Array<Bool> = [for (i in 0...binCount) false];
		for (i in 0...binCount)
			agg[i] = (!holdBins[i] && bins[i] >= thresholdPerBin);

		var zones:Array<TurboZone> = [];
		var i:Int = 0;
		while (i < binCount)
		{
			if (!agg[i]) { i++; continue; }
			var start:Int = i;
			while (i + 1 < binCount && agg[i + 1]) i++;
			var end:Int = i;
			var zStartTime:Float = start * binMs;
			var zEndTime:Float = (end + 1) * binMs;
			var startIndex:Int = lowerBound(unspawnNotes, zStartTime);
			var endIndex:Int = lowerBound(unspawnNotes, zEndTime);
			if (endIndex > startIndex && (zEndTime - zStartTime) >= minZoneMs)
				zones.push({ startIndex: startIndex, endIndex: endIndex, startTime: zStartTime, endTime: zEndTime });
			i++;
		}
		return zones;
	}

	static function lowerBound(arr:Array<CastNote>, time:Float):Int
	{
		var lo:Int = 0;
		var hi:Int = arr.length;
		while (lo < hi)
		{
			var mid:Int = (lo + hi) >>> 1;
			if (arr[mid].strumTime < time)
				lo = mid + 1;
			else
				hi = mid;
		}
		return lo;
	}

	// ===================== 侧车缓存（仅 sys 目标） =====================

	public static function cachePath(song:String, mod:String, notes:Array<CastNote>):String
	{
		var key:String = song + '|' + mod + '|' + Std.string(notes == null ? 0 : notes.length)
			+ '|' + Std.string(chartFingerprint(notes));
		var hash:String = Md5.encode(key).substr(0, 16);
		return cacheDir() + '/turbo-' + hash + '.bin';
	}

	static function cacheDir():String
	{
		var cands:Array<String> = [];
		try { cands.push(haxe.io.Path.directory(haxe.io.Path.directory(Sys.programPath())) + '/Resources/crash'); } catch (e:Dynamic) {}
		cands.push('./crash');
		for (dir in cands)
		{
			try
			{
				if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
				return dir;
			}
			catch (e:Dynamic) {}
		}
		return './crash';
	}

	public static function saveCache(path:String, zones:Array<TurboZone>, meta:Dynamic):Void
	{
		try
		{
			var buf:haxe.io.BytesBuffer = new haxe.io.BytesBuffer();
			buf.addString('METB');
			buf.addInt32(CACHE_VERSION);
			var metaStr:String = Json.stringify(meta);
			var metaBytes:haxe.io.Bytes = haxe.io.Bytes.ofString(metaStr);
			buf.addInt32(metaBytes.length);
			buf.add(metaBytes);
			buf.addInt32(zones == null ? 0 : zones.length);
			if (zones != null)
				for (z in zones)
				{
					buf.addInt32(z.startIndex);
					buf.addInt32(z.endIndex);
					buf.addDouble(z.startTime);
					buf.addDouble(z.endTime);
				}
			File.saveBytes(path, buf.getBytes());
		}
		catch (e:Dynamic) {} // 缓存失败不影响运行
	}

	public static function loadCache(path:String, expectedMeta:Dynamic):Null<Array<TurboZone>>
	{
		if (!FileSystem.exists(path)) return null;
		try
		{
			var bytes:haxe.io.Bytes = File.getBytes(path);
			if (bytes == null || bytes.length < 8) return null;
			var pos:Int = 0;
			if (bytes.getString(pos, 4) != 'METB') return null;
			pos += 4;
			if (bytes.getInt32(pos) != CACHE_VERSION) return null;
			pos += 4;
			var metaLen:Int = bytes.getInt32(pos);
			pos += 4;
			var metaStr:String = bytes.getString(pos, metaLen);
			pos += metaLen;
			if (!cacheMetaMatches(Json.parse(metaStr), expectedMeta)) return null;
			var count:Int = bytes.getInt32(pos);
			pos += 4;
			var zones:Array<TurboZone> = [];
			for (i in 0...count)
			{
				zones.push({
					startIndex: bytes.getInt32(pos),
					endIndex: bytes.getInt32(pos + 4),
					startTime: bytes.getDouble(pos + 8),
					endTime: bytes.getDouble(pos + 16)
				});
				pos += 24;
			}
			return zones;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function cacheMetaMatches(a:Dynamic, b:Dynamic):Bool
	{
		if (a == null || b == null) return false;
		return a.song == b.song && a.mod == b.mod && a.notes == b.notes && a.fingerprint == b.fingerprint;
	}
}
