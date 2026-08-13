package backend;

import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;

/**
 * 游戏内报错系统：
 * 捕获未处理异常后不再直接闪退，而是写入崩溃日志并切换到游戏内的报错界面。
 * 只有报错界面本身也出错、或连续多次出错时，才使用原生弹窗兜底退出。
 */
class CrashHandler
{
	public static var errorSource:String = '';
	public static var errorMessage:String = '';
	public static var errorStack:String = '';

	static var errorCount:Int = 0;
	static var inErrorState:Bool = false;

	public static function init():Void
	{
		#if !mobile
		openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#end
	}

	static function onUncaughtError(e:UncaughtErrorEvent):Void
	{
		e.preventDefault();
		handleError('未捕获异常', Std.string(e.error), CallStack.exceptionStack(true));
	}

	public static function handleError(source:String, error:String, stack:Array<StackItem>):Void
	{
		errorCount++;

		// 报错界面本身出错，或连续多次出错：写日志后用原生弹窗兜底退出，避免死循环
		if (inErrorState || errorCount >= 3)
		{
			writeCrashLog(source, error, stack);
			fallbackDialog(source, error);
			return;
		}

		writeCrashLog(source, error, stack);

		errorSource = source;
		errorMessage = error;
		errorStack = formatStack(stack);

		try
		{
			inErrorState = true;
			flixel.FlxG.switchState(new states.ErrorState());
		}
		catch (_)
		{
			fallbackDialog(source, error);
		}
	}

	public static function leaveErrorState():Void
	{
		inErrorState = false;
	}

	static function fallbackDialog(source:String, error:String):Void
	{
		#if desktop
		DiscordClient.shutdown();
		#end
		openfl.Lib.application.window.alert(buildMessage(source, error), 'Meteoric Engine - Error');
		Sys.exit(1);
	}

	static function buildMessage(source:String, error:String):String
	{
		return '错误来源：' + source + '\n错误信息：' + error
			+ '\n\n请将 crash 目录下的日志文件发送给开发者，感谢反馈！';
	}

	static function formatStack(stack:Array<StackItem>):String
	{
		if (stack == null || stack.length == 0)
			return '(无堆栈信息)';

		var lines:Array<String> = [];
		for (item in stack)
		{
			switch (item)
			{
				case FilePos(s, file, line, column):
					lines.push('    at ' + file + ' (line ' + line + ')');
				case Method(classname, method):
					lines.push('    at ' + classname + '.' + method);
				case LocalFunction(v):
					lines.push('    at LocalFunction #' + v);
				case Module(m):
					lines.push('    at Module ' + m);
				default:
					lines.push('    ' + Std.string(item));
			}
		}
		return lines.join('\n');
	}

	static function writeCrashLog(source:String, error:String, stack:Array<StackItem>):Void
	{
		var dateNow:String = Date.now().toString().replace(' ', '_').replace(':', "'");
		var path:String = './crash/MeteoricEngine_' + dateNow + '.txt';

		if (!FileSystem.exists('./crash/'))
			FileSystem.createDirectory('./crash/');

		var errMsg:String = buildMessage(source, error) + '\n\n' + formatStack(stack) + '\n';
		File.saveContent(path, errMsg);

		Sys.println(errMsg);
		Sys.println('Crash dump saved in ' + Path.normalize(path));
	}
}
