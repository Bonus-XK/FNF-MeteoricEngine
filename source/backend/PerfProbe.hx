package backend;

import haxe.PosInfos;

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
		_lines.push('[' + Std.string(Std.int(get_ms())) + 'ms] ' + s);
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