package backend;

import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;

#if (cpp && !windows)
@:cppFileCode('
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>
#include <sys/ucontext.h>
#if defined(__APPLE__)
	#include <sys/utsname.h>
	#include <sys/sysctl.h>
#elif defined(__ANDROID__)
	#include <sys/system_properties.h>
#elif defined(__linux__)
	#include <sys/utsname.h>
#endif

// 平台/系统信息（安卓版本+ABI / macOS 版本+架构 / Linux 发行信息）→ 静态字符串。
static const char* meteoric_os_cstr() {
	static char buf[256];
	#if defined(__ANDROID__)
	char rel[128] = {0}, abi[128] = {0};
	__system_property_get("ro.build.version.release", rel);
	__system_property_get("ro.product.cpu.abi", abi);
	snprintf(buf, sizeof(buf), "Android %s (%s)", rel[0] ? rel : "?", abi[0] ? abi : "?");
	#else
	struct utsname u;
	memset(&u, 0, sizeof(u));
	uname(&u);
	#if defined(__APPLE__)
	char ver[128] = {0};
	size_t vsz = sizeof(ver);
	if (sysctlbyname("kern.osproductversion", ver, &vsz, NULL, 0) != 0 || !ver[0])
		snprintf(ver, sizeof(ver), "%s", u.release);
	snprintf(buf, sizeof(buf), "macOS %s (%s)", ver, u.machine);
	#elif defined(__linux__)
	snprintf(buf, sizeof(buf), "Linux %s (%s)", u.release, u.machine);
	#else
	snprintf(buf, sizeof(buf), "%s %s (%s)", u.sysname, u.release, u.machine);
	#endif
	#endif
	return buf;
}

// 原生崩溃处理器：SIGSEGV/SIGABRT/SIGILL/SIGBUS → 写 native_stack.txt
// （含 signal、PC/SP/FP 指针、fault 符号化、帧指针链回溯、平台/时间/最后阶段）。
static void meteoric_native_sig_handler(int sig, siginfo_t* si, void* uctx) {
	uint64_t pc = 0, sp = 0, fp = 0;
	ucontext_t* uc = (ucontext_t*)uctx;
	if (uc) {
	#if defined(__x86_64__) || defined(__amd64__)
		#if defined(__ANDROID__) || defined(__linux__)
			pc = uc->uc_mcontext.gregs[REG_RIP];
			sp = uc->uc_mcontext.gregs[REG_RSP];
			fp = uc->uc_mcontext.gregs[REG_RBP];
		#else
			pc = uc->uc_mcontext->__ss.__rip;
			sp = uc->uc_mcontext->__ss.__rsp;
			fp = uc->uc_mcontext->__ss.__rbp;
		#endif
	#elif defined(__aarch64__)
		#if defined(__ANDROID__) || defined(__linux__)
			pc = uc->uc_mcontext.pc;
			sp = uc->uc_mcontext.sp;
			fp = uc->uc_mcontext.regs[29];
		#else
			pc = uc->uc_mcontext->__ss.__pc;
			sp = uc->uc_mcontext->__ss.__sp;
			fp = uc->uc_mcontext->__ss.__fp;
		#endif
	#elif defined(__arm__)
		#if defined(__ANDROID__)
			pc = uc->uc_mcontext.arm_pc;
			sp = uc->uc_mcontext.arm_sp;
			fp = uc->uc_mcontext.arm_fp;
		#else
			pc = uc->uc_mcontext->__ss.__pc;
			sp = uc->uc_mcontext->__ss.__sp;
			fp = uc->uc_mcontext->__ss.__fp;
		#endif
	#endif
	}

	const char* dirm = getenv("METEORIC_CRASH_DIR");
	const char* stage = getenv("METEORIC_LAST_STAGE");
	char p[700];
	const char* dirs[3];
	int nd = 0;
	if (dirm && dirm[0]) dirs[nd++] = dirm;
	dirs[nd++] = "./crash";

	for (int di = 0; di < nd; di++) {
		snprintf(p, sizeof(p), "%s/native_stack.txt", dirs[di]);
		FILE* f = fopen(p, "w");
		if (f) {
			const char* sigName = (sig == SIGSEGV) ? "SEGV" : (sig == SIGABRT) ? "ABRT" : (sig == SIGILL) ? "ILL" : "BUS";
			struct tm tmv;
			time_t now = time(NULL);
			localtime_r(&now, &tmv);
			char tbuf[64];
			strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tmv);

			char body[4096];
			int bl = 0;
			bl += snprintf(body + bl, sizeof(body) - bl, "============================================================\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "  Meteoric Engine - Native Crash Report\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "============================================================\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "时间       : %s\\n", tbuf);
			bl += snprintf(body + bl, sizeof(body) - bl, "平台/系统   : %s\\n", meteoric_os_cstr());
			bl += snprintf(body + bl, sizeof(body) - bl, "信号       : %d (%s)\\n", sig, sigName);
			bl += snprintf(body + bl, sizeof(body) - bl, "PC/SP/FP   : 0x%llx / 0x%llx / 0x%llx\\n",
				(unsigned long long)pc, (unsigned long long)sp, (unsigned long long)fp);
			if (stage && stage[0])
				bl += snprintf(body + bl, sizeof(body) - bl, "最后阶段   : %.300s\\n", stage);
			else
				bl += snprintf(body + bl, sizeof(body) - bl, "最后阶段   : (无)\\n");
			Dl_info di2;
			if (dladdr((void*)pc, &di2) && di2.dli_sname)
				bl += snprintf(body + bl, sizeof(body) - bl, "故障点     : %s + 0x%lx\\n", di2.dli_sname, (long)((char*)pc - (char*)di2.dli_saddr));
			else
				bl += snprintf(body + bl, sizeof(body) - bl, "故障点     : 0x%llx (no symbol)\\n", (unsigned long long)pc);
			bl += snprintf(body + bl, sizeof(body) - bl, "------------------------------------------------------------\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "回溯 (帧指针链):\\n");
			uint64_t cur = fp;
			for (int k = 0; k < 24 && cur && bl < (int)sizeof(body) - 200; k++) {
				uint64_t ret = 0, next = 0;
				memcpy(&ret, (void*)(cur + 8), sizeof(ret));
				if (ret < 0x100000ULL) break;
				if (dladdr((void*)ret, &di2) && di2.dli_sname)
					bl += snprintf(body + bl, sizeof(body) - bl, "#%02d %s + 0x%lx\\n", k, di2.dli_sname, (long)((char*)ret - (char*)di2.dli_saddr));
				else
					bl += snprintf(body + bl, sizeof(body) - bl, "#%02d 0x%llx\\n", k, (unsigned long long)ret);
				memcpy(&next, (void*)cur, sizeof(next));
				if (next <= cur) break;
				cur = next;
			}
			bl += snprintf(body + bl, sizeof(body) - bl, "------------------------------------------------------------\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "提示: 若回溯以地址为主（无符号），请用 atos 配合带符号构建文件解析；\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "      请将本文件与 last_stage.txt 一起发送给开发者。\\n");
			bl += snprintf(body + bl, sizeof(body) - bl, "============================================================\\n");
			if (bl > 0 && bl < (int)sizeof(body)) {
				int fdd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
				if (fdd >= 0) {
					ssize_t wr = write(fdd, body, bl);
					(void)wr;
					close(fdd);
					break;
				}
			}
			// 目录全部不可写：兜底打到 stderr（Android logcat / 桌面终端可见）
			if (bl > 0) {
				ssize_t wr = write(2, body, bl);
				(void)wr;
			}
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
 * 游戏内报错系统 + 详细崩溃日志：
 * - Haxe 未捕获异常：写崩溃报告（时间/平台/架构/当前 State/阶段标记/堆栈）→ 游戏内报错界面（桌面）
 *   或 Toast + 退出（安卓）。
 * - 原生信号崩溃（SIGSEGV/ABRT/ILL/BUS）：native_stack.txt（PC/SP/FP 指针 + 符号化回溯 + 平台 + 最后阶段）。
 *   安卓与桌面 Mac/Linux 均启用（Windows/mingw 无 execinfo 故排除）。
 */
class CrashHandler
{
	public static var errorSource:String = '';
	public static var errorMessage:String = '';
	public static var errorStack:String = '';

	static var errorCount:Int = 0;
	static var inErrorState:Bool = false;
	static var lastStage:String = '';

	public static function init():Void
	{
		#if !html5
		// 安卓/桌面都启用游戏内崩溃界面；HTML5 不支持这个事件
		openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#end
		// 原生信号处理器：SIGSEGV/SIGABRT/SIGILL/SIGBUS 落盘 native_stack.txt（POSIX 系；Windows 跳过）
		#if (cpp && !windows)
		installNativeHandlers();
		// 尽早确定崩溃目录并写入环境变量：此后任意时刻的原生崩溃都有明确的落盘目标
		try
		{
			var dir:String = ensureCrashDir();
			if (dir != null && dir.length > 0)
				Sys.putEnv('METEORIC_CRASH_DIR', dir);
			Sys.putEnv('METEORIC_LAST_STAGE', 'init');
		}
		catch (e:Dynamic) {}
		#end
	}

	#if (cpp && !windows)
	public static function installNativeHandlers():Void
	{
		untyped __cpp__("meteoric_install_native_handlers()");
	}

	static function platformInfo():String
	{
		try {
			return untyped __cpp__("meteoric_os_cstr()");
		} catch (e:Dynamic) {
			return '未知平台';
		}
	}
	#else
	static function platformInfo():String
	{
		// 桌面端（Windows 等）：显示当前系统版本号
		#if windows
		try
		{
			var osTxt:String = '';
			try { osTxt = openfl.system.Capabilities.os; } catch (e:Dynamic) {}
			if (osTxt == null || osTxt.length == 0) osTxt = 'Windows';
			var archTxt:String = (untyped __cpp__("(int)sizeof(void*)") == 8 ? ' (64-bit)' : ' (32-bit)');
			return osTxt + archTxt;
		}
		catch (e:Dynamic) return 'Windows';
		#else
		return Sys.systemName();
		#end
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

	/** 彩蛋/测试用：触发真实原生段错误（写空指针），走 meteoric_native_sig_handler → native_stack.txt */
	public static function triggerNativeCrash():Void
	{
		#if (cpp && !windows)
		mark('test:manual-native-crash');
		try { Sys.sleep(0.05); } catch (e:Dynamic) {}
		untyped __cpp__("*(volatile int*)(intptr_t)0 = 1");
		#else
		throw '原生崩溃触发仅支持 cpp 平台';
		#end
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

	/** 崩溃报告头：时间 / 平台+架构 / 指针宽度 / 当前 State / 阶段标记 / 原生栈提示 */
	static function buildCrashMeta():String
	{
		#if !html5
		var lines:Array<String> = [];
		lines.push('============================================================');
		lines.push('  Meteoric Engine - Crash Report (Haxe)');
		lines.push('============================================================');
		lines.push('时间       : ' + Date.now().toString());
		lines.push('平台/系统   : ' + platformInfo());
		lines.push('指针宽度    : ' + Std.string(#if (cpp) untyped __cpp__("(int)sizeof(void*)") #else 4 #end) + 'B ('
			+ #if (cpp && !windows) (untyped __cpp__("(int)sizeof(void*)") == 8 ? '64-bit' : '32-bit') #else '?' #end + ')');

		var state:Dynamic = null;
		try { state = flixel.FlxG.state; } catch (e:Dynamic) {}
		if (state != null)
		{
			var cls:String = Type.getClassName(Type.getClass(state));
			lines.push('当前 State  : ' + cls);
			// 游玩/编谱状态附加信息
			try
			{
				if (Std.isOfType(state, states.PlayState))
				{
					var st:states.PlayState = cast state;
					var songTxt:String = (states.PlayState.SONG != null) ? states.PlayState.SONG.song : '?';
					lines.push('曲目        : ' + songTxt + (states.PlayState.chartingMode ? ' [编谱]' : ' [游玩]'));
				}
			}
			catch (e:Dynamic) {}
		}
		else
			lines.push('当前 State  : (null)');

		if (lastStage.length > 0)
			lines.push('阶段标记    : ' + lastStage);
		else
			lines.push('阶段标记    : (无)');

		#if (cpp && !windows)
		lines.push('原生栈提示  : 若是原生崩溃，请一并发送 crash/native_stack.txt（含 PC/SP/FP 指针与符号化回溯）');
		#end
		return lines.join('\n');
		#else
		return '';
		#end
	}

	static function writeCrashLog(source:String, error:String, stack:Array<StackItem>):Void
	{
		// 先确保原生崩溃处理器知道往哪写（同一目录 + 最后阶段）
		#if (cpp && !windows)
		try {
			var dir = ensureCrashDir();
			if (dir != null && dir.length > 0)
				Sys.putEnv('METEORIC_CRASH_DIR', dir);
		} catch (e:Dynamic) {}
		#end

		var dateNow:String = Date.now().toString().replace(' ', '_').replace(':', "'");
		var errMsg:String = '===== Meteoric Crash Report =====\n'
			+ buildCrashMeta() + '\n'
			+ buildMessage(source, error) + '\n\n'
			+ '调用堆栈：\n' + formatStack(stack) + '\n';

		// 依次尝试多个可写目录，单个失败绝不中断（每个都包 try/catch）。
		// 安卓：崩溃文件必须落在玩家公认的 .meteoric/crash（公共根目录，与回退模式无关）——
		// './crash/' 是相对路径（进程 cwd=/，不可写），回退模式下 root() 指向应用专属目录，
		// 两者都可能导致"崩溃无日志"。
		var dirs:Array<String> = collectCrashDirs();
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

	static function collectCrashDirs():Array<String>
	{
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
		return dirs;
	}

	static function ensureCrashDir():String
	{
		for (dir in collectCrashDirs())
		{
			try
			{
				if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
				return dir;
			}
			catch (e:Dynamic) {}
		}
		return null;
	}

	// ===== 原生崩溃阶段簿 =====
	// SIGSEGV/SIGILL 绕过 Haxe 异常处理器（不产生 MeteoricEngine_*.txt）；本函数把
	// 最近一个跨过的阶段实时落盘 last_stage.txt（覆盖写）并写入进程环境变量
	// METEORIC_LAST_STAGE（原生处理器读取）——原生崩溃后最后一行 = 死因阶段。
	// 调用点少量（进曲/生成/首次命中/结算约 10 次/曲），无性能影响。
	public static function mark(stage:String):Void
	{
		lastStage = stage;
		#if (cpp && !windows)
		try
		{
			Sys.putEnv('METEORIC_LAST_STAGE', stage);
			var dir:String = ensureCrashDir();
			if (dir != null)
			{
				Sys.putEnv('METEORIC_CRASH_DIR', dir);
				File.saveContent(dir + '/last_stage.txt', Date.now().toString() + '\n' + stage + '\n');
			}
		}
		catch (e:Dynamic) {}
		#else
		try
		{
			var content:String = Date.now().toString() + '\n' + stage + '\n';
			var dirs:Array<String> = ['./crash'];
			try { dirs.push(haxe.io.Path.directory(Sys.programPath()) + '/crash'); } catch (e:Dynamic) {}
			for (dir in dirs)
			{
				try
				{
					if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
					File.saveContent(dir + '/last_stage.txt', content);
					return;
				}
				catch (e:Dynamic) {}
			}
		}
		catch (e:Dynamic) {}
		#end
	}
}
