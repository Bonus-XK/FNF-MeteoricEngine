package backend;

import haxe.io.Path;
import sys.FileSystem;

/**
 * 后台线程复制文件夹（拖文件夹安装 mod 用）。
 *
 * v2（2026-09-05 拖入 20GB mod 崩溃修复）：
 * 旧实现在工作线程里逐文件 sys.io.File.copy —— 对 2.1GB 级谱面 JSON，单文件就要
 * 拉几十万次 Haxe 级 readBytes/writeBytes 调用，且每文件一条跨线程字符串消息，
 * 工作线程持续产生 GC 对象。Release 下表现为 malloc 堆损坏 abort（native_crash
 * 日志：malloc_vreport 链），Debug 下表现为 Thread.create 闭包内未捕获异常 →
 * hxcpp CriticalError（export/debug native_stack.txt：checkedThrow 于 _hx_run）。
 *
 * v2 原则：工作线程零 Haxe 对象分配 —— 命令串在主线程拼好，worker 只执行一条
 * 系统原生命令（macOS ditto / Windows xcopy / Linux cp -R），结束时发送 1 条纯
 * 结果消息（done/err），所有 sendMessage 均包 try/catch，任何异常都无法逃出
 * 线程闭包。进度为不定态（与 ZipExtractor 系统 unzip 路径一致），总超时由
 * ModInstaller 按目标目录字节数预估后写入 timeoutMs。
 */
class FolderCopier
{
	public var done(default, null):Int = 0;
	public var total(default, null):Int = 0;
	public var finished(default, null):Bool = false;
	public var currentFile(default, null):String = '';
	public var error(default, null):String = null;

	/** 看门狗超时（毫秒）：系统命令执行期间无任何消息时的最长等待，由调用方按目标大小预估。 */
	public var timeoutMs:Int = 900000;

	var mainThread:sys.thread.Thread;
	var cancelRequested:Bool = false;
	var cmdLine:String = '';

	public function new() {}

	/**
	 * 估算目录总字节数（主线程调用，供超时预估；失败返回 null 不阻塞安装）。
	 * 仅遍历 stat，不复制、不分配工作线程对象。
	 */
	public static function estimateTotalBytes(src:String):Null<Float>
	{
		try
		{
			var total:Float = 0;
			var stack:Array<String> = [src];
			while (stack.length > 0)
			{
				var dir:String = stack.pop();
				for (entry in FileSystem.readDirectory(dir))
				{
					var full:String = dir + '/' + entry;
					if (FileSystem.isDirectory(full))
						stack.push(full);
					else
						total += FileSystem.stat(full).size;
				}
			}
			return total;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	/**
	 * 后台递归复制 src 到 dst。
	 * 命令串在主线程构建（避免工作线程分配 String）；worker 只 Sys.command + 结果消息。
	 */
	public function start(src:String, dst:String):Void
	{
		var q:String->String = function(s:String):String
			return '"' + StringTools.replace(s, '"', '\\"') + '"';

		#if windows
		// xcopy /E 含子目录 /I 目标视为目录 /H 含隐藏 /Y 覆盖 /Q 静默
		// 退出码 0=成功 1=无文件可复制（对非空源视为成功，统一按 0/1 处理）
		cmdLine = 'xcopy ' + q(src) + ' ' + q(dst) + ' /E /I /H /Y /Q';
		#elseif linux
		cmdLine = 'cp -R ' + q(src) + ' ' + q(dst);
		#else
		// macOS：ditto 保留资源分叉与 unicode 文件名，完全复制目录
		cmdLine = 'ditto ' + q(src) + ' ' + q(dst);
		#end
		currentFile = Path.withoutDirectory(src);

		#if (cpp || neko || hl)
		mainThread = sys.thread.Thread.current();
		sys.thread.Thread.create(function()
		{
			try
				run()
			catch (e:Dynamic)
				safeSend({t: 'err', msg: Std.string(e)});
		});
		#else
		run();
		finished = true;
		#end
	}

	// ------------------------------------------------------------------
	// Worker
	// ------------------------------------------------------------------

	/** 工作线程执行体：只跑一条系统命令，不分配 Haxe 对象，不抛异常。 */
	function run():Void
	{
		try
		{
			var code:Int = Sys.command(cmdLine);
			#if windows
			var ok:Bool = (code == 0 || code == 1);
			#else
			var ok:Bool = (code == 0);
			#end
			if (ok)
				safeSend({t: 'done'});
			else
				safeSend({t: 'err', msg: '系统复制失败（exit ' + code + '）'});
		}
		catch (e:Dynamic)
		{
			safeSend({t: 'err', msg: Std.string(e)});
		}
	}

	/** 跨线程消息发送：任何异常都不允许逃出工作线程（hxcpp 线程闭包无异常保护 → 崩溃）。 */
	function safeSend(msg:Dynamic):Void
	{
		#if (cpp || neko || hl)
		try
		{
			if (mainThread != null) mainThread.sendMessage(msg);
		}
		catch (e:Dynamic) {}
		#end
	}

	public function pumpMessages():Void
	{
		#if (cpp || neko || hl)
		if (mainThread == null) return;
		var msg:Dynamic = sys.thread.Thread.readMessage(false);
		while (msg != null)
		{
			handleMessage(msg);
			msg = sys.thread.Thread.readMessage(false);
		}
		#end
	}

	public function requestCancel():Void
	{
		cancelRequested = true;
		#if (cpp || neko || hl)
		var waited:Int = 0;
		while (!finished && waited < 300)
		{
			pumpMessages();
			Sys.sleep(0.01);
			waited++;
		}
		#end
	}

	function handleMessage(msg:Dynamic):Void
	{
		switch (msg.t)
		{
			case 'prog':
				done = msg.done;
				total = msg.total;
				currentFile = msg.cur;

			case 'done':
				finished = true;

			case 'err':
				error = msg.err;
				finished = true;

			case 'canceled':
				finished = true;

			default:
		}
	}
}
