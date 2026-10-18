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

	// 【update 间隔 gap】上一次 end() 到下一次 begin() 之间的墙钟。探测脚本之外
	// 的代价：GC 回收、文件 IO、合成器/OS 打盹都落在这。读法：gap_max 高而
	// upd_max 不高 → 卡在两次 update 之间（探针落盘/驱动/OS）；两者同高 → 引擎内。
	static var _lastEndT:Float = 0;
	static var _gapAcc:Float = 0;
	static var _gapMax:Float = 0;
	static var _gapN:Int = 0;

	// 子阶段累计
	static var _phT:Float = 0;
	static var _phAcc:Map<String, Float> = new Map();
	static var _phMax:Map<String, Float> = new Map();
	static var _phCnt:Map<String, Int> = new Map();

	// 探针落盘（crash/profile.txt，追加）：release 双击运行时没有控制台，
	// trace 不可见；与 CrashHandler 的 crash/ 目录同址，便于直接发文件。
	static var _profilePath:String = null;

	// ===================== 时钟选择（**先量分辨率再选**） =====================
	// ⚠ 为什么不能直接用 haxe.Timer.stamp()：
	//   cpp 目标上它 = hxcpp 的 __time_stamp()（hx/StdLibs.cpp:334），macOS 走
	//   `gettimeofday` —— 而 macOS 的 gettimeofday 粒度约 **1ms**。我们要测的是
	//   「每帧几十微秒的 phase」，比时钟粗两个数量级，用它只会得到 0 / 1000us 的量化假象。
	//   实测症状：所有 max 都是 1000 的整数倍、直方图 0.5-0.75 与 1.25-1.5 恒空、
	//   p50 恒为 1000us。
	//   可用替代：lime_system_get_timer（CFFI → SDL_GetPerformanceCounter，纳秒），
	//   但它**返回原始值、单位未文档化**，所以下面先标定单位再选。
	static inline var CLK_STAMP:Int = 0; // haxe.Timer.stamp()，原生单位 = 秒
	static inline var CLK_LIME:Int = 1; // lime_system_get_timer，单位待标定
	static var _clk:Int = -1; // -1 = 未选
	static var _clkScale:Float = 1; // 原始单位 → 秒
	static var _limeFn:Dynamic = null;
	static var _clockReady:Bool = false;

	/** 取候选时钟的原始计数值（不做单位换算）。CLK_STAMP 一律返回 **ms**。 */
	static function rawNow(kind:Int):Float
	{
		if (kind == CLK_STAMP) return haxe.Timer.stamp() * 1000.0;
		if (_limeFn == null) _limeFn = tryLoadLime();
		if (_limeFn == null) return haxe.Timer.stamp() * 1000.0;
		try
		{
			var v:Float = cast _limeFn();
			// CFFI 不可用时 load 会返回 var-args 桩（调用得到 {}），这里必须挡住，
			// 否则 cast 会抛，整个探针跟着挂
			if (Math.isFinite(v)) return v;
		}
		catch (e:Dynamic) {}
		_limeFn = null; // 确认不可用 → 永久退回粗时钟，别每帧重试
		return haxe.Timer.stamp() * 1000.0;
	}

	static function tryLoadLime():Dynamic
	{
		try
		{
			var f:Dynamic = lime.system.CFFI.load("lime", "lime_system_get_timer", 0);
			if (f == null) return null;
			var probe:Float = cast f();
			if (!Math.isFinite(probe)) return null;
			return f;
		}
		catch (e:Dynamic)
		{
			trace('[PROFILE-CLOCK] lime_system_get_timer unavailable: ' + Std.string(e));
			return null;
		}
	}

	/**
	 * 量某个时钟的**最小非零步进**（真实分辨率）。
	 *
	 * ⚠ 采样必须**按时间窗口**而不是按次数：固定次数会踩坑 —— 20,000 次调用总耗时
	 *    只有 ~0.2ms，比粗时钟 1ms 的量子还短，一个非零步进都采不到（实测踩过：
	 *    res=-1000ns + lime=unavailable）。这里用粗时钟只界定窗口长度（窗口够长时
	 *    粗时钟本身是准的），窗口内尽量多采。
	 */
	static function probeStep(kind:Int, windowMs:Float = 5.0):Float
	{
		var w0:Float = haxe.Timer.stamp() * 1000.0;
		var min:Float = -1;
		var cnt:Int = 0;
		var prev:Float = rawNow(kind);
		var guard:Int = 0;
		while (haxe.Timer.stamp() * 1000.0 - w0 < windowMs && guard < 20000000)
		{
			guard++;
			var t:Float = rawNow(kind);
			var d:Float = t - prev;
			prev = t;
			cnt++;
			if (d > 0 && (min < 0 || d < min)) min = d;
		}
		_lastProbeCount = cnt;
		return min;
	}

	static var _lastProbeCount:Int = 0;

	/**
	 * 一次性选时钟：实测各候选的最小步进（统一换算到 ms 后比大小），选最细的。
	 *
	 * lime 时钟的**单位用长窗口标定**而不是猜：在 ~0.4s 的窗口上对比粗时钟的漂移，
	 * 此时 ±1ms 的量化误差只占 0.25%，足以区分「秒 / 毫秒 / 微秒 / 纳秒」四种量级。
	 */
	static function pickClock():Void
	{
		var stampStep:Float = probeStep(CLK_STAMP);
		var stampN:Int = _lastProbeCount;
		var best:Int = CLK_STAMP;
		var bestStep:Float = (stampStep > 0) ? stampStep : 1e9;
		var limeStep:Float = -1;
		var limeN:Int = 0;
		var scale:Float = 1;

		if (_limeFn == null) _limeFn = tryLoadLime();
		if (_limeFn != null)
		{
			var s0:Float = haxe.Timer.stamp();
			var l0:Float = rawNow(CLK_LIME);
			// 自旋等一个 ~0.4s 的窗口（粗时钟在长窗口上是准的），步数兜底防死循环
			var guard:Int = 0;
			while (haxe.Timer.stamp() - s0 < 0.4 && guard < 400000000)
			{
				guard++;
			}
			var s1:Float = haxe.Timer.stamp();
			var l1:Float = rawNow(CLK_LIME);
			var ds:Float = s1 - s0;
			var dl:Float = l1 - l0;
			if (ds > 0.05 && dl > 0)
			{
				scale = dl / ds; // 原始单位 → 秒
				var step:Float = probeStep(CLK_LIME);
				limeN = _lastProbeCount;
				if (step > 0)
				{
					limeStep = step * scale * 1000.0; // → ms
					if (limeStep < bestStep)
					{
						best = CLK_LIME;
						bestStep = limeStep;
					}
				}
			}
		}
		_clk = best;
		_clkScale = scale; // 仅 CLK_LIME 时用到（原始单位 → 秒）

		_clockReady = true;
		// 拆成多行拼装：嵌套三元 + 字符串拼接的括号很容易数错，报错还指不到真正的地方
		var who:String = (_clk == CLK_LIME) ? 'lime_system_get_timer' : 'haxe.Timer.stamp()';
		var resTxt:String = (bestStep < 1e8) ? Std.int(bestStep * 1000) + 'ns' : 'unknown';
		var stampTxt:String = (stampStep > 0) ? Std.int(stampStep * 1000) + 'ns' : ('>5ms(n=' + stampN + ')');
		var limeTxt:String = 'unavailable';
		if (limeStep > 0)
			limeTxt = Std.int(limeStep * 1000) + 'ns scale=' + scale + ' n=' + limeN;
		else if (_limeFn != null)
			limeTxt = 'no-step n=' + limeN;
		else
			limeTxt = 'load-failed';
		trace('[PROFILE-CLOCK] chosen=' + who + ' res=' + resTxt + ' | stamp=' + stampTxt + ' | lime=' + limeTxt);
	}

	/** 对外统一时钟：**秒**。命名用 tick 而不是 now —— 避免与调用点局部变量 `now` 遮蔽。 */
	static inline function tick():Float
	{
		if (!_clockReady) pickClock();
		if (_clk == CLK_LIME) return rawNow(CLK_LIME) * _clkScale;
		return haxe.Timer.stamp();
	}

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
		var t:Float = tick();
		if (_frameStart > 0)
		{
			var d:Float = t - _frameStart;
			_fAcc += d;
			if (d > _fMax) _fMax = d;
			var ms:Float = d * 1000;
			_fSamples.push(ms);
			_fBuckets[_fBucketOf(ms)]++;
		}
		_frameStart = t;
	}

	public static inline function begin():Void
	{
		var t:Float = tick();
		// gap 统计（跨窗口保持 _lastEndT：上个窗口的最后一次 end 与本窗口首次 begin 之间的
		// 间隔也计入，能捕捉到状态切换时刻的 IO/GC）
		if (_lastEndT > 0)
		{
			var g:Float = t - _lastEndT;
			_gapAcc += g;
			_gapN++;
			if (g > _gapMax) _gapMax = g;
		}
		_t = t;
	}

	public static inline function phaseBegin(name:String):Void
	{
		_phT = tick();
	}

	public static inline function phaseEnd(name:String):Void
	{
		var d:Float = tick() - _phT;
		_phAcc.set(name, (_phAcc.exists(name) ? _phAcc.get(name) : 0) + d);
		_phCnt.set(name, (_phCnt.exists(name) ? _phCnt.get(name) : 0) + 1);
		var m:Float = _phMax.exists(name) ? _phMax.get(name) : 0;
		if (d > m) _phMax.set(name, d);
	}

	/**
	 * 流式子阶段累计：**不占用 _phT 槽位**，可以安全嵌套在其他 phaseBegin/End 之内
	 * 使用（例如「scriptOnUpdate」外层 phase 内逐脚本计时）。d 单位 = 秒。
	 */
	public static function phaseAdd(name:String, seconds:Float):Void
	{
		_phAcc.set(name, (_phAcc.exists(name) ? _phAcc.get(name) : 0) + seconds);
		_phCnt.set(name, (_phCnt.exists(name) ? _phCnt.get(name) : 0) + 1);
		var m:Float = _phMax.exists(name) ? _phMax.get(name) : 0;
		if (seconds > m) _phMax.set(name, seconds);
	}

	/** 对外取当前探针时钟（秒）。供逐脚本计时这类需要自己拿两次 clock 的场合。 */
	public static inline function tickNow():Float
	{
		return tick();
	}

	public static inline function end(tag:String):Void
	{
		var t:Float = tick();
		var d:Float = t - _t;
		_acc += d;
		if (d > _max) _max = d;
		_n++;
		if (t - _lastLog >= 1.0)
		{
			var sb:StringBuf = new StringBuf();
			sb.add('[PROFILE] ' + tag + ' update_avg=' + Math.round(_acc / _n * 1000000) + 'us update_max=' + Math.round(_max * 1000000)
				+ 'us frame_avg=' + Math.round(_fAcc / _n * 1000000) + 'us frame_max=' + Math.round(_fMax * 1000000) + 'us n=' + _n);
			// gap：update 之间的墙钟（含探针自身每秒落盘的代价——所以 gap 单独高不算引擎问题）
			if (_gapN > 0)
				sb.add(' gap_avg=' + Math.round(_gapAcc / _gapN * 1000000) + 'us gap_max=' + Math.round(_gapMax * 1000000) + 'us g=' + _gapN);
			// 【GC 可见性】heap-in-use（含未回收垃圾，MEM_INFO_CURRENT），逐行看锯齿：
			// 每秒涨多少 + 哪行之后掉回去 = 上一行的尖峰就是那次回收
			#if cpp
			try { sb.add(' mem=' + Std.int(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_CURRENT) / 1048576) + 'mb'); } catch (e:Dynamic) {}
			#end
			// 【OS 级占用】GC 数字不动而物理内存飙升 → 涨在原生侧（PerfProbe 采样线程，主循环零开销）
			{
				var rss:Float = PerfProbe.processRSS();
				sb.add(' ram=' + (rss >= 0 ? (Std.int(rss) + 'mb') : 'n/a'));
			}
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
			_acc = 0; _max = 0; _n = 0; _lastLog = t;
			_gapAcc = 0; _gapMax = 0; _gapN = 0;
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
