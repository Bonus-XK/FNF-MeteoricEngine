package backend;

import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;

#if (cpp && !android && !windows)
@:cppFileCode('
#include <signal.h>
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>
#include <sys/ucontext.h>
// 注：POSIX 专用（execinfo/dlopen/ucontext），mingw-w64 无 execinfo.h，
// Windows 目标不编译此原生信号处理器（保持 Haxe 层游戏内报错界面）。

static void meteoric_native_sig_handler(int sig, siginfo_t* si, void* uctx) {
	uint64_t rip = 0, rbp = 0;
	ucontext_t* uc = (ucontext_t*)uctx;
	if (uc) {
#if defined(__x86_64__)
		rip = uc->uc_mcontext->__ss.__rip;
		rbp = uc->uc_mcontext->__ss.__rbp;
#else
		rip = uc->uc_mcontext->__ss.__pc;
		rbp = uc->uc_mcontext->__ss.__fp;
#endif
	}
	const char* dirs[] = {"./crash", "crash"};
	for (int i = 0; i < 2; i++) {
		char p[600];
		snprintf(p, sizeof(p), "%s/native_stack.txt", dirs[i]);
		FILE* f = fopen(p, "w");
		if (f) {
			fprintf(f, "signal=%d\\n", sig);
			fprintf(f, "RIP=0x%llx RBP=0x%llx\\n", (unsigned long long)rip, (unsigned long long)rbp);
			// 故障指令直接符号化（Debug 构建有符号；符号表缺失时给出地址）
			Dl_info di;
			if (dladdr((void*)rip, &di) && di.dli_sname) {
				fprintf(f, "fault=%s + 0x%lx\\n", di.dli_sname, (long)((char*)rip - (char*)di.dli_saddr));
			} else {
				fprintf(f, "fault=0x%llx (no symbol)\\n", (unsigned long long)rip);
			}
			// 帧指针链手动回溯（Debug/带帧指针构建可靠）：每个返回地址符号化
			uint64_t fp = rbp;
			for (int k = 0; k < 20 && fp; k++) {
				uint64_t ret = 0;
				memcpy(&ret, (void*)(fp + 8), sizeof(ret));
				if (ret < 0x100000000ULL) break;
				if (dladdr((void*)ret, &di) && di.dli_sname)
					fprintf(f, "#%d %s + 0x%lx\\n", k + 1, di.dli_sname, (long)((char*)ret - (char*)di.dli_saddr));
				else
					fprintf(f, "#%d 0x%llx\\n", k + 1, (unsigned long long)ret);
				uint64_t next = 0;
				memcpy(&next, (void*)fp, sizeof(next));
				if (next <= fp) break;
				fp = next;
			}
			fclose(f);
			break;
		}
	}
	_exit(128 + sig);
}

static void meteoric_install_native_handlers() {
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = meteoric_native_sig_handler;
	sa.sa_flags = SA_SIGINFO;
	sigaction(SIGSEGV, &sa, NULL);
	sigaction(SIGABRT, &sa, NULL);
	sigaction(SIGILL, &sa, NULL);
	sigaction(SIGBUS, &sa, NULL);
}
')
#end

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
		#if !html5
		// 安卓/桌面都启用游戏内崩溃界面；HTML5 不支持这个事件
		openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#end
		// 原生信号处理器：SIGSEGV/SIGABRT/SIGILL/SIGBUS 落盘 native_stack.txt（符号化调用栈；POSIX 专用，Windows 跳过）
		#if (cpp && !android && !windows)
		installNativeHandlers();
		#end
	}

	#if (cpp && !android && !windows)
	public static function installNativeHandlers():Void
	{
		untyped __cpp__("meteoric_install_native_handlers()");
	}
	#end

	static function onUncaughtError(e:UncaughtErrorEvent):Void
	{
		e.preventDefault();
		handleError('未捕获异常', Std.string(e.error), CallStack.exceptionStack(true));
	}

	public static function handleError(source:String, error:String, stack:Array<StackItem>):Void
	{
		errorCount++;

		#if android
		// 安卓端：写崩溃日志（绝对路径，玩家可发给开发者）→ Toast 提示 → 退出。
		// 任何一步都不能抛异常：安卓上 window.alert 不可用、相对 './crash/' 不可写，
		// 只要有一环抛异常，崩溃处理自身就会死掉 → "无弹窗、无日志"的静默闪退。
		try { writeCrashLog(source, error, stack); } catch (e:Dynamic) {}
		try { fallbackDialog(source, error); } catch (e:Dynamic) {}
		return;
		#end

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
		#if android
		// 安卓：lime 的 window.alert 未实现（调了会抛异常 → 静默扇退），改用系统 Toast
		try { extension.androidtools.widget.Toast.makeText('Meteoric Engine 发生错误，崩溃日志已保存：' + error, 1); } catch (e:Dynamic) {}
		#else
		try { openfl.Lib.application.window.alert(buildMessage(source, error), 'Meteoric Engine - Error'); } catch (e:Dynamic) {}
		#end
		Sys.exit(1);
	}

	static function buildMessage(source:String, error:String):String
	{
		var logHint:String = #if android '\n\n崩溃日志已保存到：手机存储的 .meteoric/crash 目录' #else '\n\n请将 crash 目录下的日志文件发送给开发者，感谢反馈！' #end;
		return '错误来源：' + source + '\n错误信息：' + error + logHint;
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
		var errMsg:String = buildMessage(source, error) + '\n\n' + formatStack(stack) + '\n';

		// 依次尝试多个可写目录，单个失败绝不中断（每个都包 try/catch）。
		// 安卓：崩溃文件必须落在玩家公认的 .meteoric/crash（公共根目录，与回退模式无关）——
		// './crash/' 是相对路径（进程 cwd=/，不可写），回退模式下 root() 指向应用专属目录，
		// 两者都可能导致"崩溃无日志"。
		var dirs:Array<String> = [];
		#if android
		try
		{
			var pubDir:String = AndroidStorage.publicRoot() + '/crash';
			dirs.push(pubDir);
		}
		catch (e:Dynamic) {}
		try
		{
			var curDir:String = AndroidStorage.root() + '/crash';
			if (!dirs.contains(curDir)) dirs.push(curDir);
		}
		catch (e:Dynamic) {}
		#end
		dirs.push('./crash');
		try { dirs.push(haxe.io.Path.directory(Sys.programPath()) + '/crash'); } catch (e:Dynamic) {}

		var written:Bool = false;
		for (dir in dirs)
		{
			try
			{
				if (!FileSystem.exists(dir))
					FileSystem.createDirectory(dir);
				File.saveContent(dir + '/MeteoricEngine_' + dateNow + '.txt', errMsg);
				written = true;
				Sys.println('Crash dump saved in ' + Path.normalize(dir + '/MeteoricEngine_' + dateNow + '.txt'));
				break;
			}
			catch (e:Dynamic) {}
		}
		if (!written)
		{
			// 目录全部不可写：至少把完整内容打到 stdout（adb logcat 可见）
			try { Sys.println(errMsg); } catch (e:Dynamic) {}
		}
	}

	// ===== 原生崩溃阶段簿（Meteoric Fix 续）=====
	// SIGSEGV/SIGILL 绕过 Haxe 异常处理器（不产生 MeteoricEngine_*.txt）；本函数把
	// 最近一个跨过的阶段实时落盘 last_stage.txt（覆盖写）——原生崩溃后最后一行 = 死因阶段。
	// 调用点少量（进曲/生成/首次命中/结算约 10 次/曲），无性能影响。
	static var lastStageDir:String = null;
	public static function mark(stage:String):Void
	{
		#if desktop
		try
		{
			var content:String = Date.now().toString() + '\n' + stage + '\n';
			if (lastStageDir != null)
			{
				File.saveContent(lastStageDir + '/last_stage.txt', content);
				return;
			}
			var dirs:Array<String> = ['./crash'];
			try { dirs.push(haxe.io.Path.directory(Sys.programPath()) + '/crash'); } catch (e:Dynamic) {}
			for (dir in dirs)
			{
				try
				{
					if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
					File.saveContent(dir + '/last_stage.txt', content);
					lastStageDir = dir;
					return;
				}
				catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) {}
		#end
	}
}
