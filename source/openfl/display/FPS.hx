package openfl.display;

import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.display.Sprite;
import lime.ui.Window;

#if cpp
#if windows
@:cppFileCode('
#include <windows.h>
static double meteoric_cpu_time() {
	FILETIME create, exit, kernel, user;
	if (!GetProcessTimes(GetCurrentProcess(), &create, &exit, &kernel, &user)) return -1.0;
	ULARGE_INTEGER k, u;
	k.LowPart = kernel.dwLowDateTime; k.HighPart = kernel.dwHighDateTime;
	u.LowPart = user.dwLowDateTime; u.HighPart = user.dwHighDateTime;
	return (double)(k.QuadPart + u.QuadPart) / 10000000.0;
}
')
#else
@:cppFileCode('
#include <sys/resource.h>
#include <unistd.h>
static double meteoric_cpu_time() {
	struct rusage ru;
	if (getrusage(RUSAGE_SELF, &ru) != 0) return -1.0;
	return (double)ru.ru_utime.tv_sec + (double)ru.ru_utime.tv_usec / 1e6
	+ (double)ru.ru_stime.tv_sec + (double)ru.ru_stime.tv_usec / 1e6;
}
static int meteoric_cpu_cores() {
	long n = sysconf(_SC_NPROCESSORS_ONLN);
	return (n > 0) ? (int)n : 0;
}
')
#end
#end
class FPS extends TextField
{
	public var currentFPS(default, null):Int = 0;

	// 滚动速度指示器：独立 TextField（FPS 不是容器无法挂子对象，由 Main.hx addChild）
	public var speedTxt:TextField;

	// ===== 方块模式（fpsStyle = '方块'）=====
	//   bg     — 方形徽章底（圆角、85% 不透明深色）。半透明深底属 UI-DESIGN §1.1
	//            「跟主题无关的固定暗色」，可硬编码；Main.hx 须最先 addChild（衬底在下）
	//   subTxt — 副行（显示项清单各行，可多行；内容由 fpsStatsList 决定），Main.hx addChild
	// 布局随内容自适应：仅内容结构变化（显示项清单/样式切换）时整块重定边长；
	// 期间尺寸变化走 ±BG_RESIZE_BAND 双向死区（旧版「只增不缩」会留巨型空方块，已废弃）。
	// 自适应边长按实测 textWidth/textHeight 求 max，任何字号与清单组合都不裁字。
	public var bg:Sprite;
	public var subTxt:TextField;

	// 布局基准（桌面像素；手机端按 _k 整体缩放）
	static inline var BG_PAD:Float = 10;          // 方块内边距
	static inline var BG_CORNER:Float = 11;       // 圆角半径
	static inline var BG_GAP:Float = 4;           // 主行与副行间距
	static inline var BG_MIN_SIDE:Float = 84;     // 最小边长（4 位大号数字 + 留白下限）
	static inline var BG_ALPHA:Float = 0.85;      // 85% 不透明（用户指定）
	static inline var BG_RGB:Int = 0x161622;      // 徽章底色（固定深色，不随主题）
	static inline var BG_LINE_RGB:Int = 0xFFFFFF; // 1px 发丝描边色
	static inline var BG_LINE_A:Float = 0.27;     // 描边透明度（≈ DesignTokens.panelOutline 0x45）
	static inline var BG_RESIZE_BAND:Float = 10;  // 边长重排死区（±，小于该变化不重排）
	static inline var BG_Y:Float = 8;             // 方块顶边（x 沿用计数器 x）

	var _bigFmt:TextFormat = new TextFormat("VCR OSD Mono", #if mobile 36 #else 24 #end, 0xFFFFFFFF);
	var _smallFmt:TextFormat = new TextFormat("VCR OSD Mono", #if mobile 28 #else 14 #end, 0xFFFFFFFF);
	var _curMainFmt:TextFormat;          // 主行当前生效字号（换档才 setTextFormat，防重排抖动）
	var _subColor:Int = 0xFFD7D7E0;      // 副行固定亮灰（UI-DESIGN §1.1 悬停行文字同族固定色）
	var _k:Float = #if mobile 2.0 #else 1.0 #end;
	var _sig:String = "";                // 布局签名（"" = 强制下帧整块重排）
	var _bgSide:Float = 0;               // 当前方块边长
	var _lastDrawSide:Float = -1;        // bg 最后一次绘制的边长（仅变化时重绘位图）
	var _baseX:Float = 0;                // 构造时的基准 x（方块锚点；经典模式还原位）
	var _baseY:Float = 0;                // 构造时的基准 y（经典模式还原位）

	var _frameCount:Int = 0;
	var _elapsed:Float = 0;
	// 真实时间基准：Lime 传入的 deltaTime 是 Int 毫秒（0/1ms 量化），高帧率下会把
	// 计数器虚高 4~8 倍；改用 haxe.Timer.stamp() 实测墙钟，与探针 frame_avg 同口径。
	var _lastStamp:Float = 0;

	var _warnColor:Int = 0xFFFF0000;
	var _defaultColor:Int;
	var _fpsColor:Int;

	// 彩虹模式：色相轮循环角度
	var _rainbowHue:Float = 0;

	// 峰值内存：与 Mem 同一口径（totalMemory），取运行以来的最大值
	var _peakMem:Float = 0;

	// 窗口标题栏模式：原始窗口标题（开启标题显示时拼接统计信息，关闭时恢复）
	var _baseTitle:String = null;
	// 上一次写入窗口的完整标题（用于检测引擎其他代码是否改过标题）
	var _lastTitle:String = null;
	// 【性能】窗口标题写入节流（秒）：macOS 上 NSWindow.title 是主线程 WindowServer IPC，
	// 原实现每 100ms（FPS 刷新节拍）写一次 → 标题栏/合成器每 100ms 被打一次点，
	// 表现为游戏内 700~1000 帧的 100ms 级波段抖动（标题栏 FPS 模式用户实测）。
	// 节流到 500ms：FPS 数字仍每 100ms 计算（内存/CPU 数据本就 1s 采样），
	// 窗口标题不再是高频 IPC 打点源。0=关闭节流（调试用）。
	var _titleSetInterval:Float = 0.5;
	var _lastTitleSetAt:Float = -1;

	#if sys
	// CPU 占用：读取进程累计 CPU 时间（全部线程），两次采样差值 / 墙钟时间。
	// 桌面端保持「单核口径」（多线程可超 100%）；手机端按逻辑核数归一化为
	// 「总容量百分比」（永不超过 100，只在 mobile 目标生效）。
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
		// 方块模式的固定锚点：不管 this 被摆到哪里，bg 的基准位都是构造时的坐标。
		// （不能用「当前 x」当锚点 —— x 在方块模式下会被移进方内，形成
		//   bg.x ← x ← bg.x + cx 的正反馈链，每 100ms 右移一次 → 实机「飞出屏幕」根因）
		_baseX = x;
		_baseY = y;

		_defaultColor = color;
		_fpsColor = color;

		selectable = false;
		mouseEnabled = false;
		// 手机端屏幕大（物理像素高），FPS 字号放大方便查看
		#if mobile
		defaultTextFormat = new TextFormat("VCR OSD Mono", 28, color);
		#else
		defaultTextFormat = new TextFormat("VCR OSD Mono", 14, color);
		#end
		autoSize = LEFT;
		multiline = true;

		// 滚动速度指示器（默认隐藏，游戏内且开启设置时才显示）
		speedTxt = new TextField();
		speedTxt.selectable = false;
		speedTxt.mouseEnabled = false;
		#if mobile
		speedTxt.defaultTextFormat = new TextFormat("VCR OSD Mono", 28, 0xFF00FF00);
		#else
		speedTxt.defaultTextFormat = new TextFormat("VCR OSD Mono", 14, 0xFF00FF00);
		#end
		speedTxt.autoSize = LEFT;
		speedTxt.visible = false;

		// 方块模式资源：底 + 副行（样式为 '经典' 时不可见，零绘制成本）
		bg = new Sprite();
		bg.mouseEnabled = false;
		bg.mouseChildren = false;
		bg.visible = false;

		subTxt = new TextField();
		subTxt.selectable = false;
		subTxt.mouseEnabled = false;
		subTxt.defaultTextFormat = _smallFmt;
		subTxt.autoSize = LEFT;
		subTxt.multiline = true; // 副行可多行（FPS+Mem+Peak+CPU / 全部档）
		subTxt.visible = false;

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
		#if METEORIC_PROFILE
		backend.MeteoricProfile.frameTick();
		#end
		_frameCount++;

		// 真实帧周期（秒→毫秒）：取代 Int 量化 deltaTime，高帧率下不再虚高
		var now:Float = haxe.Timer.stamp();
		if (_lastStamp > 0)
			_elapsed += (now - _lastStamp) * 1000.0;
		_lastStamp = now;

		if (_elapsed >= 100) // 显示刷新 100ms（原 Psych 手感），高帧率下数字更跟手
		{
			currentFPS = Math.round(_frameCount / (_elapsed / 1000));
			_frameCount = 0;
			_elapsed = 0;

			updateColor();
			updateText();
			updateSpeedTxt();
		}
	}

	function updateColor():Void
	{
		var mode:String = ClientPrefs.data.fpsColor.toUpperCase();
		if (mode == '自动')
		{
			// 彩色 FPS：按帧率分级变色（高帧绿 / 中帧黄 / 低帧红）
			if (currentFPS >= 55) _fpsColor = 0xFF00FF00;
			else if (currentFPS >= 30) _fpsColor = 0xFFFFFF00;
			else _fpsColor = _warnColor;
			return;
		}
		if (mode == '彩虹')
		{
			// Rainbow FPS（Kade Engine 风格）：颜色在色相轮上循环
			_rainbowHue = (_rainbowHue + 20) % 360;
			_fpsColor = 0xFF000000 | hsvToRgb(_rainbowHue, 1, 1);
			return;
		}
		if (currentFPS < 30)
			_fpsColor = _warnColor;
		else
			// ⚠ mode 是**存储值**（ClientPrefs.data.fpsColor，存档里就是中文），
			// 这里必须按原样比较 —— 不能本地化，否则匹配不上全部落default。
			// 显示层的翻译由 Option 的 optionValue.fpsColor.* 负责（见 InterfaceSettingsSubState）。
			_fpsColor = switch (mode) {
				case '青色':    0xFF00FFFF;
				case '蓝色':    0xFF0000FF;
				case '红色':     0xFFFF0000;
				case '绿色':   0xFF00FF00;
				case '黄色':  0xFFFFFF00;
				default:        _defaultColor;
			};
	}

	// HSV → RGB（0-360 色相），返回 0xRRGGBB
	function hsvToRgb(h:Float, s:Float, v:Float):Int
	{
		var c:Float = v * s;
		var hp:Float = h / 60;
		var x:Float = c * (1 - Math.abs(hp % 2 - 1));
		var r:Float = 0, g:Float = 0, b:Float = 0;
		if (hp < 1) { r = c; g = x; }
		else if (hp < 2) { r = x; g = c; }
		else if (hp < 3) { g = c; b = x; }
		else if (hp < 4) { g = x; b = c; }
		else if (hp < 5) { r = x; b = c; }
		else { r = c; b = x; }
		var m:Float = v - c;
		return (Std.int((r + m) * 255) << 16) | (Std.int((g + m) * 255) << 8) | Std.int((b + m) * 255);
	}

	// 滚动速度指示器：显示当前音符滚动速度，颜色随速度变化（慢绿 / 中黄 / 快红）
	function updateSpeedTxt():Void
	{
		if (!ClientPrefs.data.showScrollSpeed || states.PlayState.instance == null)
		{
			speedTxt.visible = false;
			return;
		}
		var spd:Float = states.PlayState.instance.songSpeed;
		if (spd <= 0) spd = 1;
		speedTxt.text = 'SPD: ' + (Math.round(spd * 100) / 100) + 'x';
		if (spd < 1.5) speedTxt.textColor = 0xFF00FF00;
		else if (spd < 2.5) speedTxt.textColor = 0xFFFFFF00;
		else speedTxt.textColor = 0xFFFF0000;
		speedTxt.x = x;
		// 方块模式：SPD 行钉在方块下缘；经典/标题栏沿用原相对文字位置
		if (bg != null && bg.visible)
			speedTxt.y = bg.y + _bgSide + 4 * _k;
		else
			speedTxt.y = y + textHeight + 4;
		speedTxt.visible = visible;
	}

	dynamic function updateText():Void
	{
		var mem:Float = openfl.system.System.totalMemory;
		if (mem < 0) mem += 4294967296; // totalMemory 是 Int，超过 2GB 会溢出为负数，这里还原为真实字节数
		if (mem > _peakMem) _peakMem = mem;

		#if sys
		_cpuSamples++;
		if (_cpuSamples % 10 == 0) sampleCpu(); // 十次 100ms tick = 每 1 秒采样一次
		#end

		// 标题栏模式：屏幕计数器隐藏，统计信息写进窗口标题
		if (ClientPrefs.data.fpsInTitleBar)
		{
			hideSquare();
			#if desktop
			updateWindowTitle(mem);
			#end
			return;
		}

		if (ClientPrefs.data.fpsStyle == '方块')
			updateSquare(mem);
		else
		{
			hideSquare(); // 经典样式：方块与副行保持隐藏（样式切换即时生效）
			buildStack(mem);
			textColor = _fpsColor;
		}
	}

	// 统计栈（与经典样式逐字一致）：'全部' 档复用；'仅FPS'/'FPS+Mem' 不用它
	// 显示项清单解析：CSV → 去空白/去重/丢弃未知项。FPS 数字固定主行，不在清单内。
	// 方块/经典两种样式与窗口标题栏共用同一张清单（fpsStatsList）。
	// 由 options.FPSStatsEditorState 维护清单内容。
	public static function parseFpsStats():Array<String>
	{
		var raw:String = ClientPrefs.data.fpsStatsList;
		var out:Array<String> = [];
		if (raw == null || raw.length == 0) return out;
		for (tok in raw.split(','))
		{
			tok = StringTools.trim(tok);
			if (tok.length == 0 || out.indexOf(tok) >= 0) continue;
			if (tok == 'Mem' || tok == 'Peak' || tok == 'CPU' || tok == 'Ver') out.push(tok);
		}
		return out;
	}

	/** 单项开关查询（窗口标题栏等单点判断用；100ms tick 级调用，无缓存必要） */
	public static function isStatOn(id:String):Bool
	{
		return parseFpsStats().indexOf(id) >= 0;
	}

	// 按清单项展开副行文本（prefix：经典栈用 '\n'，方块副行用 ''）
	function statLines(item:String, mem:Float, prefix:String):Array<String>
	{
		var out:Array<String> = [];
		switch (item)
		{
			case 'Mem':
				out.push('${prefix}Mem: ${formatMem(mem)}');
			case 'Peak':
				out.push('${prefix}Peak: ${formatMem(_peakMem)}');
			case 'CPU':
				#if sys
				out.push('${prefix}CPU: ${Math.round(_cpuPct)}%');
				#end
			case 'Ver':
				out.push('${prefix}Meteoric Engine v${Main.meVersion}');
				// commit 数 / 短 hash / 分支名 + 未提交标记，编译期由 GitInfo 宏烘焙（运行时零开销）
				var gi:String = backend.GitInfo.summary();
				if (gi != "-" && gi.length > 0) out.push(gi);
				out.push('Psych Engine');
			default:
		}
		return out;
	}

	function buildStack(mem:Float):Void
	{
		var buf = new StringBuf();
		buf.add('FPS: $currentFPS');
		for (item in parseFpsStats())
			for (line in statLines(item, mem, '\n'))
				buf.add(line);

		text = buf.toString();
	}

	// 方块模式主渲染：统一徽章解剖 = 大号数字主行（颜色语义与经典一致 = _fpsColor）
	// + 灰色小字副行（subTxt，可多行；内容 = fpsStatsList 清单，编辑器见 options.FPSStatsEditorState）。
	// 旧版「整块同色多行 + 只增不缩边长」方案已废弃（实机巨型空方块）。
	function updateSquare(mem:Float):Void
	{
		if (bg == null)
		{
			buildStack(mem);
			textColor = _fpsColor;
			return;
		}

		var items:Array<String> = parseFpsStats();

		// 布局签名：内容结构（显示项清单）。变化才整块重定边长；期间尺寸变化走双向死区
		var sig:String = items.join(',');
		var refit:Bool = (sig != _sig);
		_sig = sig;

		bg.visible = visible;

		setMainFormat(_bigFmt);
		var numStr:String = '$currentFPS';
		if (text != numStr) text = numStr;
		textColor = _fpsColor;

		// 副行 = 清单各行（顺序即显示顺序；空清单 = 只有大号数字本体）
		var lines:Array<String> = [];
		for (item in items)
			for (line in statLines(item, mem, ''))
				lines.push(line);

		if (lines.length == 0)
		{
			subTxt.visible = false;
			layoutSquare(width, height, 0, 0, refit);
		}
		else
		{
			subTxt.visible = true;
			subTxt.text = lines.join('\n');
			subTxt.textColor = _subColor;
			layoutSquare(width, height, subTxt.width, subTxt.height, refit);
		}
	}

	// 定边长 + 摆放。边长 = max(最小边, 内容宽+2pad, 内容高+2pad)。
	// 尺寸变化走 ±BG_RESIZE_BAND 双向死区：Mem 值宽度抖动不触发逐秒重排，
	// 但明显的尺寸变化两个方向都立即生效（旧版「只增不缩」会留下巨型空方块）。
	// 内容方内居中：边长富余时留白均分，内容撑不下时取 pad 下限（绝不裁字）。
	function layoutSquare(textW:Float, textH:Float, subW:Float, subH:Float, refit:Bool):Void
	{
		var pad:Float = BG_PAD * _k;
		var gap:Float = BG_GAP * _k;
		var band:Float = BG_RESIZE_BAND * _k;
		var contentW:Float = Math.max(textW, subW);
		var contentH:Float = textH + (subH > 0 ? gap + subH : 0);
		// Haxe 的 Math.max 只收两个参数，三层嵌套
		var need:Float = Math.max(Math.max(BG_MIN_SIDE * _k, contentW + pad * 2), contentH + pad * 2);
		if (refit || _bgSide <= 0) _bgSide = need;
		else if (need > _bgSide + band) _bgSide = need;
		else if (need < _bgSide - band) _bgSide = need;

		// 锚点固定：bg 永远钉在构造基准位（_baseX, BG_Y）。
		// 若拿「当前 x」当基准，会形成 bg.x ← x ← bg.x + cx 的正反馈链 → 徽章匀速飞出屏幕
		if (bg.x != _baseX || bg.y != BG_Y)
		{
			bg.x = _baseX;
			bg.y = BG_Y;
		}
		redrawSquare();

		var cx:Float = Math.max(pad, (_bgSide - contentW) * 0.5);
		var cy:Float = Math.max(pad, (_bgSide - contentH) * 0.5);
		var wantX:Float = Math.round(bg.x + cx);  // 取整：避免半像素导致的文字发虚
		var wantY:Float = Math.round(bg.y + cy);
		// this 即 TextField：x/y 就是文字自身的坐标，直接摆进方块
		if (x != wantX) x = wantX;
		if (y != wantY) y = wantY;
		if (subH > 0)
		{
			var subX:Float = bg.x + Math.max(pad, (_bgSide - subW) * 0.5);
			var subY:Float = y + textH + gap;
			if (subTxt.x != subX) subTxt.x = subX;
			if (subTxt.y != subY) subTxt.y = subY;
		}
	}

	// 方块位图重绘：仅在边长变化时执行（100ms tick 常态命中同尺寸直接跳过）
	function redrawSquare():Void
	{
		var s:Float = Math.round(_bgSide);
		if (s == _lastDrawSide) return;
		_lastDrawSide = s;
		bg.x = Math.round(bg.x);
		bg.y = Math.round(bg.y);
		var g = bg.graphics;
		g.clear();
		g.beginFill(BG_RGB, BG_ALPHA);
		g.lineStyle(1, BG_LINE_RGB, BG_LINE_A);
		g.drawRoundRect(0, 0, s, s, BG_CORNER * _k, BG_CORNER * _k);
		g.endFill();
	}

	// 主行字号切换（方块各档全部用大号数字主行；经典用原字号）；只在换档时触碰 setTextFormat
	inline function setMainFormat(fmt:TextFormat):Void
	{
		if (_curMainFmt != fmt)
		{
			defaultTextFormat = fmt; // this 即 TextField，作用于自身
			setTextFormat(fmt);
			_curMainFmt = fmt;
		}
	}

	// 隐藏方块及副行（经典样式 / 标题栏模式每 100ms 兜底）；并还原计数器基准位
	// （方块模式会把 this 摆进方内，切回经典/标题栏后必须移回 _baseX/_baseY，否则残留偏移）
	inline function hideSquare():Void
	{
		if (bg != null) bg.visible = false;
		subTxt.visible = false;
		if (x != _baseX) x = _baseX;
		if (y != _baseY) y = _baseY;
	}

	// 设置切换时调用：按当前设置切换屏幕显示 / 窗口标题栏显示
	public function applyDisplayMode():Void
	{
		var inTitle:Bool = ClientPrefs.data.fpsInTitleBar;
		visible = inTitle ? false : ClientPrefs.data.showFPS;
		_sig = ""; // 强制下次刷新整块重排（样式/清单可能都已变化）
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
		// commit 信息跟随 Ver 显示项，与屏幕计数器口径一致（都是编译期烘焙，零开销）
		if (isStatOn('Ver'))
		{
			var gi:String = backend.GitInfo.summary();
			if (gi != "-" && gi.length > 0) buf.add(' | $gi');
		}
		return buf.toString();
	}

	function updateWindowTitle(mem:Float):Void
	{
		// 节流：距上次实际写入不足 _titleSetInterval 秒则跳过（FPS 数字照常 100ms 刷新，
		// 只是不再每 100ms 向 WindowServer 提交一次标题变更）
		if (_titleSetInterval > 0)
		{
			var nowMs:Float = haxe.Timer.stamp();
			if (_lastTitleSetAt >= 0 && nowMs - _lastTitleSetAt < _titleSetInterval)
				return;
			_lastTitleSetAt = nowMs;
		}
		var w:Window = lime.app.Application.current.window;
		if (w == null) return;
		if (_baseTitle == null) _baseTitle = w.title;
		// 防累积：当前标题可能已带上一次写入的统计后缀（macOS 下 window.title 读回
		// 与写入值不等价，导致旧判断把整串统计当成新基准，每刷一次叠加一段）。
		// 先剥掉已有的「 - FPS: …」后缀再判断，保证幂等。
		var cur:String = w.title;
		#if METEORIC_PROFILE
		trace('[TITLE] tick sameObj=' + (Lib.application.window == w) + ' cur="' + cur + '" last="' + _lastTitle + '" base="' + _baseTitle + '"');
		#end
		var p:Int = lastIndexOfStatsSuffix(cur);
		if (p >= 0)
			_baseTitle = cur.substring(0, p);
		else if (_lastTitle != null && cur != _lastTitle)
			_baseTitle = cur; // 引擎其他代码（选歌/暂停/结算等）改过标题 → 保留它的上下文作为新基准
		_lastTitle = _baseTitle + ' - ' + buildStatsLine(mem);
		if (w.title != _lastTitle)
			w.title = _lastTitle;
	}

	// 标题中「 - FPS: 」统计后缀的最后一个出现位置（-1 = 无）；统计串本身不含该标记，逐段剥除安全
	static function lastIndexOfStatsSuffix(title:String):Int
	{
		if (title == null) return -1;
		var marker:String = ' - FPS: ';
		var idx:Int = title.indexOf(marker);
		var last:Int = -1;
		while (idx >= 0)
		{
			last = idx;
			idx = title.indexOf(marker, idx + 1);
		}
		return last;
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

	/** 逻辑 CPU 核数（手机端归一化用；0 = 未知/不支持 → 不做归一化）。 */
	function readCpuCores():Int
	{
		#if (cpp && !windows)
		return untyped __cpp__("::meteoric_cpu_cores()");
		#else
		return 0;
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
			{
				var pct:Float = dc / dt * 100;
				#if mobile
				// getrusage 统计全进程所有线程，单核口径在手机多核上会显示 >100%（如 110%）。
				// 手机端改为「占总容量百分比」：除以逻辑核数，并做 100% 上限兜底；
				// 核数未知（readCpuCores<=1）时保持原值，避免无意义地放大。
				var cores:Int = readCpuCores();
				if (cores > 1)
				{
					pct = pct / cores;
					if (pct > 100) pct = 100;
				}
				#end
				_cpuPct = pct;
			}
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
