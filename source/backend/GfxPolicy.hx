package backend;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.utils.Assets as OpenFlAssets;

#if sys
import sys.FileSystem;
#end

/**
 * 大纹理显存提交与 CPU 副本释放（移植自 SeiunEngine 的 GfxPolicy）。
 *
 * 解决的问题：角色图集（griefer 8192×8192 = 268MB 等）在 create 期间解码后，
 * openfl 的纹理上传是**惰性**的 —— 直到该精灵第一次被绘制时才 glTexImage2D。
 * 后果：进曲后头几秒内每次遇到新图集都卡一下（上传 268MB 要几十到上百 ms），
 * 且 CPU 侧 268MB + 显存侧 268MB 双份常驻。
 *
 * 做法（一行都不碰 ndll / lib，纯 Haxe + openfl 私有 API）：
 *   1. create 结束时对本局所有 ≥ minDimension 的大纹理**立即** getTexture(ctx)
 *      —— 上传提前到加载阶段，游玩中不再有新上传
 *   2. 上传成功后立刻 disposeImage() 丢掉 CPU 副本 —— openfl 的硬件纹理仍挂在
 *      BitmapData 上，渲染结果完全一致，但 CPU 内存立即少一份
 *   3. 记录被释放的图，context 丢失时（切全屏/改分辨率/驱动重置）可从源文件重载
 *
 * 为什么这样安全：
 *   - disposeImage 后 bitmap.readable = false，但 __texture 仍在，绘制走 GPU 路径
 *   - 只有 ≥2048px 的图集才处理（小图本来就没多少内存）
 *   - 纹理不在显存里的（没上传过）绝不释放 —— 否则真要画的时候没数据
 *
 * 开关：ClientPrefs.data.gfxCpuRelease，**默认 false = 完全关闭，零行为变化**。
 */
class GfxPolicy
{
	/** 只处理长或宽 ≥ 此值的纹理（Seiun 同款 2048） */
	public static var minDimension:Int = 2048;

	/** create 结束后立即全量提交+释放（true）还是只登记、等游玩中周期性 sweep（false） */
	public static var initialSweepDelayMs:Float = 600;
	public static var sweepIntervalMs:Float = 5000;

	public static var releasedCountTotal:Int = 0;
	public static var releasedBytesTotal:Float = 0;
	public static var releasedBytesLive:Float = 0;

	public static var lastSweepCostMs:Float = 0;
	public static var lastSweepReleased:Int = 0;
	public static var sweepCountTotal:Int = 0;

	static var excludedKeys:Map<String, Bool> = [];

	/** key -> 被释放 CPU 副本的图的来源（context 丢失时靠它重载） */
	static var cpuReleased:Map<String, {assetId:String, realPath:String, bytes:Float}> = [];

	static var playAccumMs:Float = 0;
	static var nextSweepAtMs:Float = Math.POSITIVE_INFINITY;

	public static function exclude(key:String):Void
	{
		if (key != null) excludedKeys.set(key, true);
	}

	public static function unexclude(key:String):Void
	{
		if (key != null) excludedKeys.remove(key);
	}

	/** 进入 PlayState.create 时调用：重置计时器 */
	public static function onPlayStateCreate(songName:String):Void
	{
		playAccumMs = 0;
		nextSweepAtMs = enabled() ? initialSweepDelayMs : Math.POSITIVE_INFINITY;
	}

	static inline function enabled():Bool
	{
		var v = ClientPrefs.data.gfxCpuRelease;
		if (v == true) return true;
		var s = Std.string(v);
		return s == "1";
	}

	/** 供 PlayState 判断（GC 压缩等附加动作要不要做） */
	public static inline function enabledInline():Bool
	{
		return enabled();
	}

	/** 每帧调用：按间隔做一次 sweep（处理 create 期间漏掉的图） */
	public static function onPlayUpdate(elapsed:Float):Void
	{
		if (!enabled()) return;
		playAccumMs += elapsed * 1000;
		if (playAccumMs >= nextSweepAtMs)
		{
			nextSweepAtMs = playAccumMs + sweepIntervalMs;
			var freed = sweepCpuReleases();
			if (freed > 0)
				trace('[GfxPolicy] sweep #' + sweepCountTotal + ': 释放 ' + freed + ' 张大图 CPU 副本（累计 '
					+ Math.round(releasedBytesLive / 1048576) + ' MB）');
		}
	}

	/**
	 * 预加载阶段一次性提交：把本局所有大纹理立即推上显存并丢掉 CPU 副本，
	 * 之后游玩过程中不会再有任何纹理上传（Seiun 的 "no hitches" 就来自这一句）。
	 * 在 PlayState.create 末尾调用。
	 */
	public static function preloadWarm():Void
	{
		if (!enabled()) return;
		var ctx = FlxG.stage != null ? FlxG.stage.context3D : null;
		if (ctx == null) return;

		var t0 = haxe.Timer.stamp();
		var uploaded:Int = 0;

		for (key => g in Paths.currentTrackedAssets)
			uploaded += warmOne(key, g, ctx);
		@:privateAccess
		for (key => g in FlxG.bitmap._cache)
			uploaded += warmOne(key, g, ctx);

		var freed = sweepCpuReleases();
		trace('[GfxPolicy] preloadWarm: 提交 ' + uploaded + ' 张大纹理到显存、释放 ' + freed + ' 份 CPU 副本，耗时 '
			+ Math.round((haxe.Timer.stamp() - t0) * 1000) + ' ms');
	}

	static function warmOne(key:String, g:FlxGraphic, ctx:Dynamic):Int
	{
		if (key == null || g == null || g.bitmap == null || !g.bitmap.readable) return 0;
		if (excludedKeys.exists(key)) return 0;
		if (g.bitmap.width < minDimension && g.bitmap.height < minDimension) return 0;
		if (hasLiveTexture(g.bitmap)) return 0;
		try
		{
			g.bitmap.getTexture(ctx);
		}
		catch (e:Dynamic)
		{
			return 0;
		}
		return 1;
	}

	public static function sweepCpuReleases():Int
	{
		if (!enabled()) return 0;
		var t0 = haxe.Timer.stamp();

		if (FlxG.stage == null || FlxG.stage.context3D == null)
			return 0;

		lastSweepReleased = 0;

		for (key => g in Paths.currentTrackedAssets)
			if (tryRelease(key, g))
				lastSweepReleased++;

		@:privateAccess
		for (key => g in FlxG.bitmap._cache)
			if (tryRelease(key, g))
				lastSweepReleased++;

		lastSweepCostMs = (haxe.Timer.stamp() - t0) * 1000;
		sweepCountTotal++;
		return lastSweepReleased;
	}

	/** 释放单张图的 CPU 副本（前提：已上传显存，否则返回 false 不动它） */
	public static function tryRelease(key:String, g:FlxGraphic):Bool
	{
		if (key == null || key.length == 0 || g == null) return false;
		// 用 graphic 的规范 key，避免 shared: / assets/ 两种拼法产生重复登记
		var regKey:String = g.key != null && g.key.length > 0 ? g.key : key;
		if (excludedKeys.exists(key) || excludedKeys.exists(regKey)) return false;
		if (cpuReleased.exists(regKey)) return false;

		var bmp = g.bitmap;
		if (bmp == null || !bmp.readable) return false;
		if (bmp.width < minDimension && bmp.height < minDimension) return false;
		if (!hasLiveTexture(bmp)) return false; // 没上过显存 → 不能丢 CPU 数据

		var resolved = resolveSource(regKey);
		if (resolved == null) return false;

		var bytes:Float = bmp.width * bmp.height * 4;
		// 释放失败就不记账（否则以后再也不补回来）
		try
		{
			bmp.disposeImage();
		}
		catch (e:Dynamic)
		{
			return false;
		}

		cpuReleased.set(regKey, {assetId: regKey, realPath: resolved, bytes: bytes});
		releasedCountTotal++;
		releasedBytesTotal += bytes;
		releasedBytesLive += bytes;
		return true;
	}

	static function resolveSource(key:String):String
	{
		#if sys
		if (FileSystem.exists(key)) return key;
		var ci = key.indexOf(':');
		if (ci > 0)
		{
			var stripped = key.substr(ci + 1);
			if (stripped.length > 0 && FileSystem.exists(stripped)) return stripped;
		}
		#end

		try
		{
			if (OpenFlAssets.exists(key))
				return key;
		}
		catch (e:Dynamic) {}

		return null;
	}

	public static function hasLiveTexture(bmp:BitmapData):Bool
	{
		return @:privateAccess (bmp.__isValid && bmp.__texture != null);
	}

	static function findGraphicByKey(key:String):FlxGraphic
	{
		var g = Paths.currentTrackedAssets.get(key);
		if (g != null) return g;
		g = @:privateAccess FlxG.bitmap._cache.get(key);
		if (g != null) return g;

		for (candidate in Paths.currentTrackedAssets)
			if (candidate != null && candidate.key == key) return candidate;
		@:privateAccess
		for (candidate in FlxG.bitmap._cache)
			if (candidate != null && candidate.key == key) return candidate;
		return null;
	}

	/** 清理已失效的登记（图被销毁 / CPU 副本又回来了） */
	public static function pruneRegistry():Void
	{
		if (Lambda.count(cpuReleased) == 0) return;
		var dead:Array<String> = [];
		for (key => entry in cpuReleased)
		{
			var stale = false;
			var g = findGraphicByKey(key);
			if (g == null)
				stale = true;
			else if (g.bitmap != null && g.bitmap.readable)
				stale = true;

			if (stale)
			{
				releasedBytesLive -= entry.bytes;
				dead.push(key);
			}
		}
		for (k in dead)
			cpuReleased.remove(k);
		if (releasedBytesLive < 0) releasedBytesLive = 0;
	}

	public static function forgetReleased(key:String):Void
	{
		if (key == null) return;
		var entry = cpuReleased.get(key);
		if (entry != null)
		{
			releasedBytesLive -= entry.bytes;
			cpuReleased.remove(key);
			if (releasedBytesLive < 0) releasedBytesLive = 0;
		}
	}
}
