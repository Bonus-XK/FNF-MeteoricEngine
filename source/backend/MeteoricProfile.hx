package backend;

import sys.io.File;
import sys.FileSystem;

/**
 * 每帧耗时探针（默认关闭：仅当编译定义 METEORIC_PROFILE 时生效）。
 *
 * 用法：
 *  - update() 首尾：begin() / end('标签') → 每秒输出
 *      [PROFILE] 标签 update_avg=XXus update_max=XXus frame_avg=XXus frame_max=XXus n=NNNN [子阶段=XXus ...]
 *  - FPS.__enterFrame 顶部调用 frameTick()：测量完整帧周期（update+render+present+wait）
 *  - PlayState 等可用 phaseBegin('名字') / phaseEnd('名字') 计量子阶段
 *
 * 构建示例（macOS）：
 *   haxelib run lime build macos -release -arm64 -D METEORIC_PROFILE
 *
 * 未定义 METEORIC_PROFILE 时，全部为空 inline 函数，零开销。
 */
#if METEORIC_PROFILE
class MeteoricProfile
{
	static var _t:Float = 0;
	static var _acc:Float = 0;
	static var _max:Float = 0;
	static var _n:Int = 0;
	static var _lastLog:Float = 0;

	// 完整帧周期（frameTick 在 FPS.__enterFrame 每帧调用）
	static var _frameStart:Float = 0;
	static var _fAcc:Float = 0;
	static var _fMax:Float = 0;

	// 【抖动直方图】帧耗时分布（ms）：定位"700~1000 乱跳"这类波段/长尾问题
	// （frame_avg/max 只说两头，直方图能区分双峰=合成器节拍 vs 长尾=单帧尖峰）
	static var _fSamples:Array<Float> = [];
	static inline var _fLabel0:String = '<0.5';
	static var _fBuckets:Array<Int> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
	static inline function _fBucketOf(ms:Float):Int
	{
		if (ms < 0.5) return 0;
		if (ms < 0.75) return 1;
		if (ms < 1.0) return 2;
		if (ms < 1.25) return 3;
		if (ms < 1.5) return 4;
		if (ms < 2.0) return 5;
		if (ms < 3.0) return 6;
		if (ms < 5.0) return 7;
		if (ms < 10.0) return 8;
		return 9;
	}

	// 子阶段累计
	static var _phT:Float = 0;
	static var _phAcc:Map<String, Float> = new Map();
	static var _phMax:Map<String, Float> = new Map();
	static var _phCnt:Map<String, Int> = new Map();

	// 探针落盘（crash/profile.txt，追加）：release 双击运行时没有控制台，
	// trace 不可见；与 CrashHandler 的 crash/ 目录同址，便于直接发文件。
	static var _profilePath:String = null;

	static function logToFile(line:String):Void
	{
		if (_profilePath == null)
		{
			var cands:Array<String> = [];
			try { cands.push(haxe.io.Path.directory(haxe.io.Path.directory(Sys.programPath())) + '/Resources/crash'); } catch (e:Dynamic) {}
			cands.push('./crash');
			for (dir in cands)
			{
				try
				{
					if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
					_profilePath = dir + '/profile.txt';
					break;
				}
				catch (e:Dynamic) {}
			}
		}
		if (_profilePath != null)
		{
			try
			{
				var f = File.append(_profilePath, false);
				f.writeString(line + '\n');
				f.close();
			}
			catch (e:Dynamic) {}
		}
	}

	public static inline function frameTick():Void
	{
		var now:Float = haxe.Timer.stamp();
		if (_frameStart > 0)
		{
			var d:Float = now - _frameStart;
			_fAcc += d;
			if (d > _fMax) _fMax = d;
			var ms:Float = d * 1000;
			_fSamples.push(ms);
			_fBuckets[_fBucketOf(ms)]++;
		}
		_frameStart = now;
	}

	public static inline function begin():Void
	{
		_t = haxe.Timer.stamp();
	}

	public static inline function phaseBegin(name:String):Void
	{
		_phT = haxe.Timer.stamp();
	}

	public static inline function phaseEnd(name:String):Void
	{
		var d:Float = haxe.Timer.stamp() - _phT;
		_phAcc.set(name, (_phAcc.exists(name) ? _phAcc.get(name) : 0) + d);
		_phCnt.set(name, (_phCnt.exists(name) ? _phCnt.get(name) : 0) + 1);
		var m:Float = _phMax.exists(name) ? _phMax.get(name) : 0;
		if (d > m) _phMax.set(name, d);
	}

	public static inline function end(tag:String):Void
	{
		var now:Float = haxe.Timer.stamp();
		var d:Float = now - _t;
		_acc += d;
		if (d > _max) _max = d;
		_n++;
		if (now - _lastLog >= 1.0)
		{
			var sb:StringBuf = new StringBuf();
			sb.add('[PROFILE] ' + tag + ' update_avg=' + Math.round(_acc / _n * 1000000) + 'us update_max=' + Math.round(_max * 1000000)
				+ 'us frame_avg=' + Math.round(_fAcc / _n * 1000000) + 'us frame_max=' + Math.round(_fMax * 1000000) + 'us n=' + _n);
			for (k in _phAcc.keys())
			{
				var c:Int = _phCnt.exists(k) ? _phCnt.get(k) : 1;
				if (c > 0)
					sb.add(' [' + k + '_avg=' + Math.round(_phAcc.get(k) / c * 1000000) + 'us max=' + Math.round(_phMax.get(k) * 1000000) + 'us]');
			}
			// 【抖动直方图】P50/P90/P99（ms 帧耗时分位）+ 分布桶
			if (_fSamples.length > 0)
			{
				_fSamples.sort(function(a:Float, b:Float):Int return a < b ? -1 : (a > b ? 1 : 0));
				var p50:Float = _fSamples[Std.int(_fSamples.length * 0.50)];
				var p90:Float = _fSamples[Std.int(_fSamples.length * 0.90)];
				var p99:Float = _fSamples[Std.int(_fSamples.length * 0.99)];
				sb.add(' frame_p50=' + Math.round(p50 * 1000) + 'us p90=' + Math.round(p90 * 1000) + 'us p99=' + Math.round(p99 * 1000) + 'us');
				var labels:Array<String> = [_fLabel0, '0.5-0.75', '0.75-1.0', '1.0-1.25', '1.25-1.5', '1.5-2', '2-3', '3-5', '5-10', '10+'];
				sb.add(' hist=[');
				for (i in 0..._fBuckets.length)
					sb.add(labels[i] + ':' + _fBuckets[i] + (i == _fBuckets.length - 1 ? '' : ','));
				sb.add(']');
			}
			trace(sb.toString());
			logToFile(sb.toString());
			_acc = 0; _max = 0; _n = 0; _lastLog = now;
			_fAcc = 0; _fMax = 0;
			_fSamples.resize(0);
			for (i in 0..._fBuckets.length) _fBuckets[i] = 0;
			_phAcc.clear(); _phCnt.clear(); _phMax.clear();
		}
	}
}
#else
class MeteoricProfile
{
	public static inline function begin():Void {}
	public static inline function end(tag:String):Void {}
	public static inline function frameTick():Void {}
	public static inline function phaseBegin(name:String):Void {}
	public static inline function phaseEnd(name:String):Void {}
}
#end
