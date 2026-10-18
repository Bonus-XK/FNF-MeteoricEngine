package backend;

import haxe.PosInfos;
import StringTools;

/**
 * 性能实测探针（仅在设置 METEORIC_AUTOSONG 环境变量时激活）。
 *
 * 目的：让「加载超大谱面耗时」可被自动化测量 —— 启动即自动进歌，
 * 把各阶段耗时落盘到 crash/perf_probe.txt，外部脚本直接读取，
 * 不依赖人工点选与肉眼掐表。
 *
 * 激活方式：
 *   METEORIC_AUTOSONG=stupid-griefer METEORIC_AUTOPART=3 ./Meteoric
 * 不设置环境变量时本类完全惰性（_armed = false，mark/autoEnter 立刻返回），
 * 对正常游玩零影响。
 */
class PerfProbe
{
	static var _armed:Bool = false;
	static var _song:String = null;
	static var _part:String = null;
	static var _t0:Float = 0;
	static var _fired:Bool = false;
	static var _lines:Array<String> = [];

	static inline function get_ms():Float return (Sys.time() - _t0) * 1000;

	// ===================== 【OS 级内存采样（遥测）】 =====================
	// cpp.vm.Gc.memInfo 只覆盖 Haxe 堆；游玩期涨的还可能是原生/驱动/其他 native 侧，
	// 瘦身决策必须在同一把尺上量。采样线程每 2s 问一次 OS「本进程实际吃多少内存」
	//（Windows=工作集 tasklist，mac=ps RSS，linux=/proc VmRSS），写入 _rssMB。
	// sys.io.Process 每次约 20~60ms，全在子线程；主线程只是读一个 static —— 零开销。
	// 采样惰性启动：第一次 processRSS()（每条 mark、每行 profile 输出都会调）拉起线程。
	static var _rssMB:Float = -1;
	static var _rssStarted:Bool = false;

	/** 最近一次 OS 级采样（MB）。-1 = 尚未采到（线程刚起/平台不支持）。 */
	public static function processRSS():Float
	{
		ensureRSSSampler();
		return _rssMB;
	}

	static function ensureRSSSampler():Void
	{
		if (_rssStarted) return;
		_rssStarted = true;
		#if (sys && cpp)
		cpp.vm.Thread.create(function():Void
		{
			while (true)
			{
				_rssMB = sampleRSSOnce();
				Sys.sleep(2.0);
			}
		});
		#end
	}

	static function sampleRSSOnce():Float
	{
		try
		{
			#if windows
			// tasklist /fi "IMAGENAME eq <self>" /fo csv /nh：
			// 行形如 "Meteoric.exe","1234","Console"," 1","123,456 K"
			// 多开时取**最大行**：正打墙谱的实例必然是占内存最大的那个。
			var exe:String = haxe.io.Path.withoutDirectory(Sys.programPath());
			if (exe.toLowerCase().indexOf('.exe') < 0) exe = exe + '.exe';
			var pr = new sys.io.Process('tasklist', ['/fi', 'IMAGENAME eq ' + exe, '/fo', 'csv', '/nh']);
			var out:String = pr.stdout.readAll().toString();
			pr.close();
			var best:Float = -1;
			var i:Int = 0;
			while (i >= 0)
			{
				var j:Int = out.indexOf('K"', i);
				if (j < 0) break;
				var q1:Int = out.lastIndexOf('"', j - 1);
				if (q1 >= 0)
				{
					var rawNum:String = out.substring(q1 + 1, j);
					rawNum = StringTools.replace(StringTools.trim(rawNum), ',', '');
					var v:Float = Std.parseFloat(rawNum);
					if (Math.isFinite(v) && v > best) best = v;
				}
				i = j + 2;
			}
			return (best >= 0) ? (best / 1024.0) : -1; // KB → MB
			#elseif mac
			// ps -axo rss=,%c 逐行 "123456 Meteoric"（%c 可能截短进程名，按包含匹配）
			var pr = new sys.io.Process('ps', ['-axo', 'rss=,%c']);
			var out:String = pr.stdout.readAll().toString();
			pr.close();
			var base:String = haxe.io.Path.withoutDirectory(Sys.programPath());
			var best:Float = -1;
			for (line in out.split('\n'))
			{
				var k:Int = line.lastIndexOf(','); // %c 默认逗号分隔
				if (k <= 0) continue;
				var nm:String = StringTools.trim(line.substr(k + 1));
				if (nm.length <= 0 || base.indexOf(nm) < 0) continue;
				var rss:Float = Std.parseFloat(StringTools.trim(line.substr(0, k)));
				if (Math.isFinite(rss) && rss > best) best = rss;
			}
			return (best >= 0) ? (best / 1024.0) : -1;
			#else
			var txt:String = sys.io.File.getContent('/proc/self/status');
			for (line in txt.split('\n'))
			{
				if (StringTools.startsWith(line, 'VmRSS:'))
				{
					var kb:Float = Std.parseFloat(StringTools.trim(line.substr(6).split('kB')[0]));
					if (Math.isFinite(kb)) return kb / 1024.0;
					return -1;
				}
			}
			return -1;
			#end
		}
		catch (e:Dynamic)
		{
			return -1;
		}
	}

	/** 每条 mark 后缀：GC 堆量（cpp）+ OS 工作集（采到才有）。 */
	static inline function memTag():String
	{
		var s:String = '';
		#if cpp
		try
		{
			var mb:Float = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_CURRENT);
			if (Math.isFinite(mb) && mb > 0) s = ' mem=' + Std.int(mb / 1048576) + 'mb';
		}
		catch (e:Dynamic) {}
		#end
		var rss:Float = processRSS();
		if (rss >= 0) s += ' rss=' + Std.int(rss) + 'mb';
		return s;
	}

	/** 由 Main.setupGame 在引擎刚建好时调用（此刻 FlxGame 已 addChild） */
	public static function arm(song:String, part:String):Void
	{
		_armed = true;
		_song = song;
		_part = part;
		_t0 = Sys.time();
		_fired = false;
		_lines = [];
		add('armed song=' + song + ' part=' + Std.string(part));
		flush();
	}

	public static function armed():Bool return _armed;

	public static function mark(stage:String):Void
	{
		if (!_armed) return;
		add(stage);
		flush();
	}

	static function add(s:String):Void
	{
		_lines.push('[' + Std.string(Std.int(get_ms())) + 'ms] ' + s + memTag());
		if (_lines.length > 400) _lines.shift();
	}

	static function flush():Void
	{
		try
		{
			#if sys
			// 与 CrashHandler 一致：优先 METEORIC_CRASH_DIR，其次 ./crash
			// （之前固定用 './crash' 且 createDirectory 失败被静默吞掉，导致打点全丢）
			var dir:String = './crash';
			var envDir:String = Sys.getEnv("METEORIC_CRASH_DIR");
			if (envDir != null && envDir.length > 0) dir = envDir;
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent(dir + '/perf_probe.txt', _lines.join('\n'));
			#end
		}
		catch (e:Dynamic)
		{
			// 连落盘都失败时退回 stdout，保证至少能从控制台看到时序
			Sys.println('[PerfProbe] flush failed: ' + Std.string(e));
		}
	}

	/**
	 * 由 MusicBeatState.update 每帧调用（所有游戏状态的公共父类钩子）。
	 * 等 TitleState 起来后触发一次真实加载流程 —— 不绕过 LoadingState，
	 * 否则测不到真实加载耗时。
	 */
	public static function tick(state:flixel.FlxState):Void
	{
		if (!_armed || _fired) return;
		if (!Std.isOfType(state, states.TitleState)) return;
		_fired = true;
		var combo = Sys.getEnv("METEORIC_AUTOCOMBO");
		// ⚠ 局部变量名不能叫 chartJson —— 它会遮蔽同名的 chartJson() 函数，
		//   导致右边读到尚未赋值的局部变量（null），自动进歌退化成 null 输入。
		var targetJson = (combo != null && combo.length > 0) ? _song + '-' + combo : chartJson(_song, _part);
		Sys.println('[PerfProbe] tick -> load ' + targetJson);
		mark('TitleState reached -> load ' + targetJson);
		try
		{
			states.LoadingState.loadSongAndSwitchState(new states.PlayState(), _song, targetJson, _song);
		}
		catch (e:Dynamic)
		{
			add('autoEnter FAILED: ' + Std.string(e));
			flush();
		}
	}

	/** 构造进歌所需的 chartJson（无后缀 / 带 -难度后缀） */
	public static function chartJson(song:String, part:String):String
	{
		if (part == null || part.length == 0) return song;
		return song + '-' + part;
	}

	public static function song():String return _song;
	public static function part():String return _part;
}