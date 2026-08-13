package openfl.display;

import openfl.text.TextField;
import openfl.text.TextFormat;
import lime.ui.Window;

#if cpp
@:cppFileCode('
#include <sys/resource.h>
static double meteoric_cpu_time() {
	struct rusage ru;
	if (getrusage(RUSAGE_SELF, &ru) != 0) return -1.0;
	return (double)ru.ru_utime.tv_sec + (double)ru.ru_utime.tv_usec / 1e6
		+ (double)ru.ru_stime.tv_sec + (double)ru.ru_stime.tv_usec / 1e6;
}
')
#end
class FPS extends TextField
{
	public var currentFPS(default, null):Int = 0;

	var _frameCount:Int = 0;
	var _elapsed:Float = 0;

	var _warnColor:Int = 0xFFFF0000;
	var _defaultColor:Int;
	var _fpsColor:Int;

	// 峰值内存：与 Mem 同一口径（totalMemory），取运行以来的最大值
	var _peakMem:Float = 0;

	// 窗口标题栏模式：原始窗口标题（开启标题显示时拼接统计信息，关闭时恢复）
	var _baseTitle:String = null;
	// 上一次写入窗口的完整标题（用于检测引擎其他代码是否改过标题）
	var _lastTitle:String = null;

	#if sys
	// CPU 占用：读取进程累计 CPU 时间，两次采样差值 / 墙钟时间 = 瞬时占用（单核口径，多线程可超 100%）
	var _cpuPct:Float = 0;
	var _cpuTick:Float = 0;
	var _cpuTime:Float = -1;
	var _cpuSamples:Int = 0;
	#end

	public function new(x:Float = 10, y:Float = 10, color:Int = 0xFFFFFFFF)
	{
		super();

		this.x = x;
		this.y = y;

		_defaultColor = color;
		_fpsColor = color;

		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat("VCR OSD Mono", 14, color);
		autoSize = LEFT;
		multiline = true;

		#if desktop
		var w:Window = lime.app.Application.current.window;
		if (w != null) _baseTitle = w.title;
		#end

		#if sys
		_cpuTime = readCpuTime(); // 初次采样建立基准，之后每 1 秒差分一次
		_cpuTick = Sys.time();
		#end
	}

	override function __enterFrame(deltaTime:Float):Void
	{
		_frameCount++;
		_elapsed += deltaTime;

		if (_elapsed >= 500)
		{
			currentFPS = Math.round(_frameCount / (_elapsed / 1000));
			_frameCount = 0;
			_elapsed = 0;

			updateColor();
			updateText();
		}
	}

	function updateColor():Void
	{
		if (currentFPS < 30)
			_fpsColor = _warnColor;
		else
			_fpsColor = switch (ClientPrefs.data.fpsColor.toUpperCase()) {
				case "青色":    0xFF00FFFF;
				case "蓝色":    0xFF0000FF;
				case "红色":     0xFFFF0000;
				case "绿色":   0xFF00FF00;
				case "黄色":  0xFFFFFF00;
				default:        _defaultColor;
			};
	}

	dynamic function updateText():Void
	{
		var mem:Float = openfl.system.System.totalMemory;
		if (mem < 0) mem += 4294967296; // totalMemory 是 Int，超过 2GB 会溢出为负数，这里还原为真实字节数
		if (mem > _peakMem) _peakMem = mem;

		#if sys
		_cpuSamples++;
		if (_cpuSamples % 2 == 0) sampleCpu(); // 两次 500ms tick = 每 1 秒采样一次
		#end

		// 标题栏模式：屏幕计数器隐藏，统计信息写进窗口标题
		if (ClientPrefs.data.fpsInTitleBar)
		{
			#if desktop
			updateWindowTitle(mem);
			#end
			return;
		}

		var buf = new StringBuf();
		buf.add('FPS: $currentFPS');
		buf.add('\nMem: ${formatMem(mem)}');
		buf.add('\nPeak: ${formatMem(_peakMem)}');
		#if sys
		buf.add('\nCPU: ${Math.round(_cpuPct)}%');
		#end
		if (ClientPrefs.data.showVer)
		{
			buf.add('\nMeteoric Engine v${Main.meVersion}');
			buf.add('\nPsych Engine');
		}

		text = buf.toString();
		textColor = _fpsColor;
	}

	// 设置切换时调用：按当前设置切换屏幕显示 / 窗口标题栏显示
	public function applyDisplayMode():Void
	{
		var inTitle:Bool = ClientPrefs.data.fpsInTitleBar;
		visible = inTitle ? false : ClientPrefs.data.showFPS;
		#if desktop
		if (inTitle)
		{
			// 以当前窗口标题为基准（引擎刚设置的菜单/歌曲/暂停上下文）
			var w:Window = lime.app.Application.current.window;
			if (w != null) _baseTitle = w.title;
			var mem:Float = openfl.system.System.totalMemory;
			if (mem < 0) mem += 4294967296;
			if (mem > _peakMem) _peakMem = mem;
			updateWindowTitle(mem);
		}
		else
			restoreWindowTitle();
		#end
	}

	#if desktop
	// 统计信息单行版（窗口标题用）
	function buildStatsLine(mem:Float):String
	{
		var buf = new StringBuf();
		buf.add('FPS: $currentFPS');
		buf.add(' | Mem: ${formatMem(mem)}');
		buf.add(' | Peak: ${formatMem(_peakMem)}');
		#if sys
		buf.add(' | CPU: ${Math.round(_cpuPct)}%');
		#end
		return buf.toString();
	}

	function updateWindowTitle(mem:Float):Void
	{
		var w:Window = lime.app.Application.current.window;
		if (w == null) return;
		if (_baseTitle == null) _baseTitle = w.title;
		// 引擎其他代码（选歌/暂停/结算等）主动改过标题 → 保留它的上下文作为新基准
		if (_lastTitle != null && w.title != _lastTitle)
			_baseTitle = w.title;
		_lastTitle = _baseTitle + ' - ' + buildStatsLine(mem);
		w.title = _lastTitle;
	}

	function restoreWindowTitle():Void
	{
		var w:Window = lime.app.Application.current.window;
		if (w != null && _baseTitle != null) w.title = _baseTitle;
		_lastTitle = null;
	}
	#end

	#if sys
	// 读取进程累计 CPU 时间（秒）。cpp 直接调 getrusage（纯系统调用，不 fork 子进程，避免卡音频）
	function readCpuTime():Float
	{
		#if cpp
		return untyped __cpp__("::meteoric_cpu_time()");
		#else
		return -1;
		#end
	}

	function sampleCpu():Void
	{
		var now:Float = Sys.time();
		var t:Float = readCpuTime();
		if (t >= 0 && _cpuTime >= 0)
		{
			var dt:Float = now - _cpuTick;
			var dc:Float = t - _cpuTime;
			if (dt > 0 && dc >= 0)
				_cpuPct = dc / dt * 100;
		}
		_cpuTick = now;
		_cpuTime = t;
	}
	#end

	function formatMem(mem:Float):String
	{
		if (mem >= 1024 * 1024 * 1024)
			return Math.round(mem / (1024 * 1024 * 1024) * 100) / 100 + ' GB';
		else if (mem > 1024 * 1024)
			return Math.round(mem / (1024 * 1024)) + ' MB';
		else
			return Math.round(mem / 1024) + ' KB';
	}
}
