package backend;

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

	// 子阶段累计
	static var _phT:Float = 0;
	static var _phAcc:Map<String, Float> = new Map();
	static var _phMax:Map<String, Float> = new Map();
	static var _phCnt:Map<String, Int> = new Map();

	public static inline function frameTick():Void
	{
		var now:Float = haxe.Timer.stamp();
		if (_frameStart > 0)
		{
			var d:Float = now - _frameStart;
			_fAcc += d;
			if (d > _fMax) _fMax = d;
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
			trace(sb.toString());
			_acc = 0; _max = 0; _n = 0; _lastLog = now;
			_fAcc = 0; _fMax = 0;
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
