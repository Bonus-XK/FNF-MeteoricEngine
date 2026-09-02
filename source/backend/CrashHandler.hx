package backend;

import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;

/** 结构化日志级别（轻量级 TraceManager，Seiun 式）。 */
enum TraceLevel
{
	DEBUG;
	INFO;
	WARN;
	ERROR;
}

/** 结构化日志条目：级别 + 分类键 + 消息 + 源文件点 + HH:MM:SS 时间。 */
typedef LogEntry =
{
	level:TraceLevel,
	category:String,
	msg:String,
	source:String,
	time:String
}

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

	// 时间戳：每次崩溃独立文件 native_crash_YYYYMMDD_HHMMSS.txt（保留全部历史）
	struct tm tmv;
	time_t now = time(NULL);
	localtime_r(&now, &tmv);
	char tbuf[64], ts[64];
	strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tmv);
	strftime(ts, sizeof(ts), "%Y%m%d_%H%M%S", &tmv);

	const char* sigName = (sig == SIGSEGV) ? "SEGV" : (sig == SIGABRT) ? "ABRT" : (sig == SIGILL) ? "ILL" : "BUS";

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

	for (int di = 0; di < nd; di++) {
		int ok = 0;
		if (bl > 0 && bl < (int)sizeof(body)) {
			// 1) 时间戳独立文件（每次崩溃都保留）
			snprintf(p, sizeof(p), "%s/native_crash_%s.txt", dirs[di], ts);
			int fdd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
			if (fdd >= 0) {
				ssize_t wr = write(fdd, body, bl);
				(void)wr;
				close(fdd);
				ok = 1;
			}
			// 2) 「最新一次」快捷副本（与旧行为兼容）
			snprintf(p, sizeof(p), "%s/native_stack.txt", dirs[di]);
			fdd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
			if (fdd >= 0) {
				ssize_t wr = write(fdd, body, bl);
				(void)wr;
				close(fdd);
				ok = 1;
			}
		}
		if (ok) break;
	}
	// 目录全部不可写：兜底打到 stderr（Android logcat / 桌面终端可见）
	if (bl > 0) {
		ssize_t wr = write(2, body, bl);
		(void)wr;
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
 * - 原生信号崩溃（SIGSEGV/ABRT/ILL/BUS）：native_stack.txt（PC/SP/FP 指针 + 符号化回溯 + 平台 + 最后阶段）
 *   与时间戳文件 native_crash_YYYYMMDD_HHMMSS.txt（保留全部历史）。
 *   安卓与桌面 Mac/Linux 均启用（Windows SEH 暂缓）。
 * - 结构化日志环（级别/分类/源点/去重限流）+ 黑匣子事件环 + GL 错误看门狗（Seiun 式）。
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
		// 黑匣子：每 5 秒把最近事件写入 crash/heartbeat.txt（崩溃前最多丢失 5 秒历史）
		try
		{
			logEvent('crash-handler-init');
			startHeartbeat();
			installTraceRing();
		}
		catch (e:Dynamic) {}
		#end

		// GL 错误看门狗（Seiun 式）：渲染帧轮询 glGetError → 结构化日志环。
		// 所有平台都安装（install/poll 内部自带 try/catch，绝不外抛）。
		try { GlErrorWatchdog.install(); } catch (e:Dynamic) {}
		try
		{
			logInfo('crash.system', 'CrashHandler initialized (GL watchdog ' + (GlErrorWatchdog.enabled ? 'on' : 'off') + ')');
		}
		catch (e:Dynamic) {}
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

		// ---- 系统报告（Seiun SystemDiag 移植；每个采集器独立 try/catch） ----
		lines.push('');
		lines.push('===== 系统报告 =====');
		lines.push('--- 引擎 ---');
		lines.push('引擎        : Meteoric Engine v' + Main.meVersion + ' (Psych 0.7.1h 基座)');
		lines.push('构建特性    : ' + buildDefines());
		lines.push('HAXE/FLIXEL : FlxG ' + flixel.FlxG.VERSION);
		lines.push('--- 系统 / 设备 ---');
		diagDeviceLines(lines);
		lines.push('--- 窗口 / 显示 ---');
		diagWindowLines(lines);
		lines.push('--- 渲染器 / GPU ---');
		diagRendererLines(lines);
		lines.push('--- 运行态 ---');
		diagRuntimeLines(lines);
		lines.push('--- 最新 GL 错误（运行期轮询快照） ---');
		lines.push(GlErrorWatchdog.snapshot());
		lines.push('--- 原生崩溃日志（crash/native_crash_*.txt，最多 5 份） ---');
		diagNativeCrashLines(lines);
		lines.push('');
		lines.push('--- 最近游戏日志（结构化日志环，最后 60 条 / 共 ' + Std.string(logRing.length) + ' 条） ---');
		if (logRing.length > 0)
			lines.push(logRing.slice(Std.int(Math.max(0, logRing.length - 60))).map(formatLogEntry).join('\n'));
		else
			lines.push('(无日志记录)');
		#if (cpp && !windows)
		try
		{
			var dir:String = ensureCrashDir();
			if (dir != null && sys.FileSystem.exists(dir))
			{
				var files:Array<String> = sys.FileSystem.readDirectory(dir);
				files.sort(Reflect.compare);
				lines.push('');
				lines.push('--- 崩溃目录文件（' + dir + '）---');
				if (files.length > 0)
					lines.push(files.join('\n'));
				else
					lines.push('(空)');
			}
		}
		catch (e:Dynamic) {}
		#end
		#if (cpp && !windows)
		lines.push('原生栈提示  : 若是原生崩溃，请一并发送 crash/native_stack.txt 与 crash/native_crash_*.txt（含 PC/SP/FP 指针与符号化回溯）');
		#end
		return lines.join('\n');
		#else
		return '';
		#end
	}

	// ===== 系统诊断采集器（Seiun SystemDiag 移植，逐个容错） =====

	static function safeDiag(fn:Void->String, fallback:String):String
	{
		try
		{
			var v:String = fn();
			return (v == null || v.length == 0) ? fallback : v;
		}
		catch (e:Dynamic) return fallback;
	}

	static function formatBytes(bytes:Float):String
	{
		if (bytes <= 0) return '0 B';
		if (bytes >= 1024 * 1024 * 1024) return Math.round(bytes / (1024 * 1024 * 1024) * 10) / 10 + ' GB';
		if (bytes >= 1024 * 1024) return Math.round(bytes / (1024 * 1024)) + ' MB';
		return Math.round(bytes / 1024) + ' KB';
	}

	static function diagDeviceLines(out:Array<String>):Void
	{
		out.push('平台名      : ' + safeDiag(() -> lime.system.System.platformName + ' ' + lime.system.System.platformLabel
			+ ' (' + lime.system.System.platformVersion + ')', '?'));
		out.push('显示器      : ' + safeDiag(() -> Std.string(lime.system.System.numDisplays), '?'));
		out.push('逻辑 CPU    : ' + safeDiag(() -> {
			#if (cpp && !windows)
			return Std.string(untyped __cpp__("(int)sysconf(_SC_NPROCESSORS_ONLN)"));
			#elseif windows
			var s:String = Sys.getEnv('NUMBER_OF_PROCESSORS');
			var n:Int = (s == null) ? 0 : Std.parseInt(s);
			return (n > 0) ? Std.string(n) : '?';
			#else
			return '?';
			#end
		}, '?'));
		out.push('进程内存    : ' + safeDiag(() -> formatBytes(openfl.system.System.totalMemory), '?'));
	}

	static function diagWindowLines(out:Array<String>):Void
	{
		out.push('窗口        : ' + safeDiag(() -> {
			var w = flixel.FlxG.stage.window;
			if (w == null) return '(no window)';
			return Std.string(w.width) + 'x' + Std.string(w.height)
				+ ' pos=' + w.x + ',' + w.y
				+ ' scale=' + Std.string(w.scale)
				+ ' fullscreen=' + Std.string(w.fullscreen)
				+ ' borderless=' + Std.string(w.borderless);
		}, '(no window)'));
		out.push('显示模式    : ' + safeDiag(() -> {
			var dm = flixel.FlxG.stage.window.displayMode;
			if (dm == null) return '?';
			return Std.string(dm.width) + 'x' + Std.string(dm.height) + ' @' + Std.string(dm.refreshRate) + 'Hz';
		}, '?'));
		out.push('Stage       : ' + safeDiag(() -> {
			var st = flixel.FlxG.stage;
			return Std.string(st.stageWidth) + 'x' + Std.string(st.stageHeight) + ' mode=' + Std.string(st.scaleMode);
		}, '?'));
	}

	static function diagRendererLines(out:Array<String>):Void
	{
		out.push('渲染上下文  : ' + safeDiag(() -> {
			var ctx = flixel.FlxG.stage.window.context;
			if (ctx == null) return '(no render context)';
			var a = ctx.attributes;
			var attrs:String = '';
			if (a != null)
				attrs = ' hardware=' + Std.string(a.hardware) + ' vsync=' + Std.string(a.vsync)
					+ ' depth=' + Std.string(a.depth) + ' stencil=' + Std.string(a.stencil)
					+ ' antialias=' + Std.string(a.antialiasing) + ' colorDepth=' + Std.string(a.colorDepth);
			return 'type=' + Std.string(ctx.type) + ' version=' + Std.string(ctx.version) + attrs;
		}, '(no render context)'));
		out.push('Context3D   : ' + safeDiag(() -> {
			var c3d = flixel.FlxG.stage.context3D;
			if (c3d == null) return '(null - no GL context yet)';
			return Std.string(c3d.driverInfo) + ' | maxBackBuffer='
				+ Std.string(c3d.maxBackBufferWidth) + 'x' + Std.string(c3d.maxBackBufferHeight);
		}, '(null)'));
		out.push('GL 厂商     : ' + safeDiag(() -> Std.string(lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.VENDOR)), '?'));
		out.push('GL 渲染器   : ' + safeDiag(() -> Std.string(lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.RENDERER)), '?'));
		out.push('GL 版本     : ' + safeDiag(() -> Std.string(lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.VERSION)), '?'));
		out.push('GLSL        : ' + safeDiag(() -> Std.string(lime.graphics.opengl.GL.getParameter(lime.graphics.opengl.GL.SHADING_LANGUAGE_VERSION)), '?'));
		out.push('GL 扩展     : ' + safeDiag(() -> {
			var s:String = lime.graphics.opengl.GL.getString(lime.graphics.opengl.GL.EXTENSIONS);
			if (s == null || s.length == 0) return '(none)';
			var list:Array<String> = s.split(' ');
			var shown:String = '';
			for (e in list)
			{
				if (e.length == 0) continue;
				if (shown.length + e.length + 1 > 1500)
					return shown + ' ... (共 ' + list.length + ' 个)';
				shown += (shown.length > 0 ? ' ' : '') + e;
			}
			return shown + ' (共 ' + list.length + ' 个)';
		}, '(none)'));
		out.push('GPU 内存    : ' + safeDiag(() -> {
			var c3d = flixel.FlxG.stage.context3D;
			if (c3d == null) return '(null)';
			var mem:Int = 0;
			try { mem = c3d.totalGPUMemory; } catch (e:Dynamic) { mem = 0; }
			return (mem > 0) ? formatBytes(mem) + ' (驱动支持)' : '不支持（驱动未暴露）';
		}, '(GPU memory unavailable)'));
	}

	static function diagRuntimeLines(out:Array<String>):Void
	{
		out.push('FPS(设定)   : ' + safeDiag(() -> Std.string(flixel.FlxG.updateFramerate) + ' / ' + Std.string(flixel.FlxG.drawFramerate), '?'));
		out.push('FPS(实际)   : ' + safeDiag(() -> Std.string(Main.fpsVar.currentFPS), '?'));
		out.push('DrawCalls  : ' + safeDiag(() -> Std.string(openfl.display._internal.stats.Context3DStats.totalDrawCalls()), '?'));
		out.push('图形缓存    : ' + safeDiag(() -> {
			@:privateAccess
			var count:Int = 0;
			untyped { for (_k in flixel.FlxG.bitmap._cache.keys()) count++; }
			var tracked:Int = 0;
			try { tracked = Lambda.count(Paths.currentTrackedAssets); } catch (e:Dynamic) {}
			var mod:String = '';
			try
			{
				if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
					mod = ' | activeMod=' + Mods.currentModDirectory;
			}
			catch (e:Dynamic) {}
			return Std.string(count) + ' 项 | tracked=' + Std.string(tracked) + mod;
		}, '?'));
	}

	/** 附带最近 5 份 native_crash_*.txt 内容（每份截断 3000 字符）。 */
	static function diagNativeCrashLines(out:Array<String>):Void
	{
		#if (cpp && !windows)
		try
		{
			var dir:String = ensureCrashDir();
			if (dir == null || !sys.FileSystem.exists(dir))
			{
				out.push('(无 crash 目录)');
				return;
			}
			var files:Array<String> = [];
			for (f in sys.FileSystem.readDirectory(dir))
				if (f.indexOf('native_crash_') == 0 && f.endsWith('.txt'))
					files.push(f);
			// 时间戳文件名按字典序即时间序（YYYYMMDD_HHMMSS）
			files.sort(Reflect.compare);
			if (files.length == 0)
			{
				out.push('(无 native_crash_*.txt)');
				return;
			}
			for (f in files.slice(-5))
			{
				out.push('---- ' + f + ' ----');
				var content:String = sys.io.File.getContent(dir + '/' + f);
				if (content.length > 3000) content = content.substr(0, 3000) + '\n... (截断)';
				out.push(content);
			}
		}
		catch (e:Dynamic)
		{
			out.push('(读取原生崩溃日志失败: ' + Std.string(e) + ')');
		}
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

		// 崩溃瞬间的 GL 错误状态（主线程）：轮询并写入结构化日志环，随报告一并输出
		try { GlErrorWatchdog.pollNow(true); } catch (e:Dynamic) {}
		try { logError('crash.report', 'Writing crash log (source=' + source + ')'); } catch (e:Dynamic) {}

		var dateNow:String = Date.now().toString().replace(' ', '_').replace(':', "'");
		flushHeartbeat();
		var errMsg:String = '===== Meteoric Crash Report =====\n'
			+ buildCrashMeta() + '\n'
			+ buildMessage(source, error) + '\n\n'
			+ '事件时间线（黑匣子，最近 120 条）：\n' + (ring.length > 0 ? ring.join('\n') : '(无)') + '\n\n'
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

	// ===== 结构化日志环（轻量级 TraceManager，Seiun 式） =====
	static var logRing:Array<LogEntry> = [];
	static var _logHookInstalled:Bool = false;
	static var lastDedupKey:String = '';
	static var lastDedupAt:Float = 0;
	static var _logPerSecCount:Int = 0;
	static var _logPerSecAt:Float = 0;
	static var _throttleLogged:Bool = false;
	static var MAX_LOG_ENTRIES:Int = 500;
	static var DEDUP_COOLDOWN:Float = 10;
	static var MAX_LOGS_PER_SEC:Int = 300;

	/** DEBUG 级日志（分类键 + 消息；pos 由编译器自动填充为调用点）。 */
	public static function logDebug(category:String, msg:String, ?pos:haxe.PosInfos):Void
	{
		log(DEBUG, category, msg, pos);
	}

	public static function logInfo(category:String, msg:String, ?pos:haxe.PosInfos):Void
	{
		log(INFO, category, msg, pos);
	}

	public static function logWarn(category:String, msg:String, ?pos:haxe.PosInfos):Void
	{
		log(WARN, category, msg, pos);
	}

	public static function logError(category:String, msg:String, ?pos:haxe.PosInfos):Void
	{
		log(ERROR, category, msg, pos);
	}

	/** 结构化日志核心：每秒限流 + 同键 10s 去重后入环（环满丢最旧）。 */
	public static function log(level:TraceLevel, category:String, msg:String, ?pos:haxe.PosInfos):Void
	{
		try
		{
			var now:Float = haxe.Timer.stamp();
			if (now - _logPerSecAt >= 1)
			{
				_logPerSecAt = now;
				_logPerSecCount = 0;
				_throttleLogged = false;
			}
			_logPerSecCount++;
			if (_logPerSecCount > MAX_LOGS_PER_SEC)
			{
				if (!_throttleLogged)
				{
					_throttleLogged = true;
					rawPush(WARN, 'trace.throttle', '日志超过每秒 ' + MAX_LOGS_PER_SEC + ' 条，已限流（其余丢弃）',
						'CrashHandler.hx', Date.now().toString().substr(11, 8));
				}
				return;
			}

			var source:String = (pos != null && pos.fileName != null) ? pos.fileName + ':' + pos.lineNumber : '';
			var key:String = Std.string(level) + '|' + category + '|' + msg;
			if (key == lastDedupKey && now - lastDedupAt < DEDUP_COOLDOWN)
				return; // 同键静默重复
			lastDedupKey = key;
			lastDedupAt = now;

			rawPush(level, category, msg, source, Date.now().toString().substr(11, 8));
		}
		catch (e:Dynamic) {}
	}

	static function rawPush(level:TraceLevel, category:String, msg:String, source:String, time:String):Void
	{
		logRing.push({ level: level, category: category, msg: msg, source: source, time: time });
		if (logRing.length > MAX_LOG_ENTRIES) logRing.shift();
	}

	static function formatLogEntry(e:LogEntry):String
	{
		var lv:String = switch (e.level)
		{
			case DEBUG: 'DEBUG';
			case INFO:  'INFO';
			case WARN:  'WARN';
			case ERROR: 'ERROR';
		}
		var src:String = (e.source != null && e.source.length > 0) ? e.source + ' ' : '';
		return '[' + e.time + '][' + lv + '] ' + e.category + '> ' + src + e.msg;
	}

	/** 全局 trace 钩子（Seiun 式 Recent Game Log）：拦截 haxe.Log.trace，全部进入结构化日志环（INFO/trace）。 */
	static function installTraceRing():Void
	{
		if (_logHookInstalled) return;
		_logHookInstalled = true;
		var orig = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?pos:haxe.PosInfos)
		{
			try
			{
				var source:String = (pos != null && pos.fileName != null) ? pos.fileName + ':' + pos.lineNumber : '';
				rawPush(INFO, 'trace', Std.string(v), source, Date.now().toString().substr(11, 8));
			}
			catch (e:Dynamic) {}
			if (orig != null) orig(v, pos);
		};
	}

	static function buildDefines():String
	{
		var arr:Array<String> = [];
		#if CRASH_HANDLER arr.push('CRASH_HANDLER'); #end
		#if MODS_ALLOWED arr.push('MODS_ALLOWED'); #end
		#if LUA_ALLOWED arr.push('LUA_ALLOWED'); #end
		#if HSCRIPT_ALLOWED arr.push('HSCRIPT_ALLOWED'); #end
		#if VIDEOS_ALLOWED arr.push('VIDEOS_ALLOWED'); #end
		#if ACHIEVEMENTS_ALLOWED arr.push('ACHIEVEMENTS_ALLOWED'); #end
		#if mobile arr.push('mobile'); #end
		#if desktop arr.push('desktop'); #end
		#if android arr.push('android'); #end
		#if hxcodec arr.push('hxcodec'); #end
		return arr.length > 0 ? arr.join(' ') : '(未知)';
	}

	// ===== 黑匣子（崩溃前事件记录） =====
	static var ring:Array<String> = [];
	static var ringTimer:haxe.Timer = null;

	/** 记录一条事件（带 HH:MM:SS），环形缓冲最多 120 条；每 5 秒由 heartbeat 落盘 */
	public static function logEvent(msg:String):Void
	{
		try
		{
			var t:String = Date.now().toString().substr(11, 8);
			ring.push('[' + t + '] ' + msg);
			if (ring.length > 120) ring.shift();
		}
		catch (e:Dynamic) {}
	}

	static function startHeartbeat():Void
	{
		#if (cpp && !windows)
		try
		{
			if (ringTimer == null)
			{
				logEvent('session-start');
				flushHeartbeat();
				ringTimer = new haxe.Timer(5000);
				ringTimer.run = function() flushHeartbeat(true);
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	static function flushHeartbeat(keepRunning:Bool = true):Void
	{
		#if (cpp && !windows)
		try
		{
			var dir:String = ensureCrashDir();
			if (dir != null && dir.length > 0)
			{
				var h:String = '===== Meteoric Heartbeat (' + Date.now().toString() + ') =====\n'
					+ '平台=' + platformInfo() + '\n'
					+ 'GL=' + GlErrorWatchdog.snapshot() + '\n'
					+ (ring.length > 0 ? ring.join('\n') : '(空)') + '\n';
				File.saveContent(dir + '/heartbeat.txt', h);
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	// ===== 原生崩溃阶段簿 =====
	// SIGSEGV/SIGILL 绕过 Haxe 异常处理器（不产生 MeteoricEngine_*.txt）；本函数把
	// 最近一个跨过的阶段实时落盘 last_stage.txt（覆盖写）并写入进程环境变量
	// METEORIC_LAST_STAGE（原生处理器读取）——原生崩溃后最后一行 = 死因阶段。
	// 调用点少量（进曲/生成/首次命中/结算约 10 次/曲），无性能影响。
	public static function mark(stage:String):Void
	{
		lastStage = stage;
		logEvent('stage:' + stage);
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
