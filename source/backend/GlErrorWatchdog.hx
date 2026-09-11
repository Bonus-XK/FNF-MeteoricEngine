package backend;

import flixel.FlxG;
import lime.graphics.opengl.GL;
import openfl.events.Event;

/**
 * GlErrorWatchdog - 移植自 SeiunEngine（mohong2/FNF-SeiunEngine）。
 *
 * 在渲染帧（Event.RENDER 于主线程、GL 上下文有效，不会与 update 定时器竞争）
 * 上按固定间隔轮询 glGetError()，把任何渲染器错误写入 CrashHandler 的结构化
 * 日志环（级别 ERROR + 分类 trace.gl.* + 源文件点）。渲染器故障从此不再静默，
 * 会出现在崩溃报告的「最近游戏日志」与心跳快照里。
 *
 * 与 Seiun 的差异：日志落点从 mohong.TraceManager 改为本引擎 CrashHandler.logRing
 * （轻量级结构化日志，无 mohong/Language 依赖）。
 */
class GlErrorWatchdog
{
	public static var enabled:Bool = true;
	public static var pollInterval:Float = 0.5;
	public static var maxErrorsPerPoll:Int = 8;
	/** 同一种 GL 错误在 N 秒内只记录一次（去重）。 */
	public static var repeatLogCooldown:Float = 10;

	public static var errorCount:Int = 0;
	public static var lastErrorCode:Int = 0;
	public static var lastName:String = '';
	public static var lastErrorAt:Float = 0;

	static var installed:Bool = false;
	static var nextPollAt:Float = 0;
	static var lastLoggedCode:Int = -1;
	static var lastLoggedAt:Float = 0;

	/** 幂等：挂接 stage 渲染事件；任何时刻调用都安全。 */
	public static function install():Void
	{
		if (installed) return;
		installed = true;

		try
		{
			var stage = FlxG.stage;
			if (stage == null) return;
			stage.addEventListener(Event.RENDER, onStageRender);
		}
		catch (e:Dynamic) {}
	}

	static function onStageRender(_):Void
	{
		if (!enabled) return;

		var now:Float = haxe.Timer.stamp();
		if (now < nextPollAt) return;
		nextPollAt = now + pollInterval;

		pollNow(true);
	}

	/** 立即轮询（例如崩溃处理器在主线程调用）。返回最新错误码。 */
	public static function pollNow(logIt:Bool = true):Int
	{
		try
		{
			var ctx = FlxG.stage != null ? FlxG.stage.context3D : null;
			if (ctx == null) return lastErrorCode;
			if (GL.context == null) return lastErrorCode;

			var found:Int = 0;
			while (found < maxErrorsPerPoll)
			{
				var code:Int = GL.getError();
				if (code == GL.NO_ERROR) break;

				found++;
				errorCount++;
				lastErrorCode = code;
				lastName = errorName(code);
				// 用 epoch 秒（Sys.time），snapshot 里 Date.fromTime 才能得到正确的时刻；
				// 去重用的 lastLoggedAt 仍用单调钟（haxe.Timer.stamp），不受系统改时影响。
				lastErrorAt = Sys.time();

				if (logIt)
					logError(code);
			}
		}
		catch (e:Dynamic)
		{
			// 看门狗永远不向外抛
		}
		return lastErrorCode;
	}

	static function logError(code:Int):Void
	{
		var now:Float = haxe.Timer.stamp();
		if (code == lastLoggedCode && now - lastLoggedAt < repeatLogCooldown)
			return; // 同码静默重复

		lastLoggedCode = code;
		lastLoggedAt = now;

		CrashHandler.logError('trace.gl.error',
			'GL error #' + errorCount + ': ' + lastName + ' (0x' + StringTools.hex(code) + ')');
		if (code == GL.OUT_OF_MEMORY || code == GL.CONTEXT_LOST_WEBGL)
			CrashHandler.logError('trace.gl.fatal',
				'GL fatal condition: ' + lastName + ' — renderer device may be lost/reset');
	}

	/** 一行摘要，供 SystemDiag 与心跳使用。 */
	public static function snapshot():String
	{
		if (errorCount == 0)
			return 'none (errors polled: 0)';

		var time:String = '?';
		if (lastErrorAt > 0)
		{
			var d:Date = Date.fromTime(lastErrorAt * 1000);
			time = Std.string(d.getHours()) + ':' + Std.string(d.getMinutes()) + ':' + Std.string(d.getSeconds());
		}
		return 'last=' + lastName + ' (0x' + StringTools.hex(lastErrorCode) + ')'
			+ ' count=' + Std.string(errorCount)
			+ ' at=' + time;
	}

	static function errorName(code:Int):String
	{
		return switch (code)
		{
			case 0: 'GL_NO_ERROR';
			case 0x0500: 'GL_INVALID_ENUM';
			case 0x0501: 'GL_INVALID_VALUE';
			case 0x0502: 'GL_INVALID_OPERATION';
			case 0x0505: 'GL_OUT_OF_MEMORY';
			case 0x0506: 'GL_INVALID_FRAMEBUFFER_OPERATION';
			case 0x9242: 'GL_CONTEXT_LOST_WEBGL';
			default: StringTools.hex(code);
		}
	}
}
