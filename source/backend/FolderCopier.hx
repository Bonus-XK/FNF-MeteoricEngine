package backend;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;

/**
 * 后台线程递归拷贝文件夹（拖文件夹安装 mod 用）。
 * 与 ZipExtractor 同模式：worker 线程做文件 IO，主线程用 pumpMessages()
 * 每帧收进度消息，游戏 UI 不会因大文件夹拷贝而卡死。
 */
class FolderCopier
{
	public var done(default, null):Int = 0;
	public var total(default, null):Int = 0;
	public var finished(default, null):Bool = false;
	public var currentFile(default, null):String = '';
	public var error(default, null):String = null;

	var mainThread:sys.thread.Thread;
	var cancelRequested:Bool = false;

	public function new() {}

	/**
	 * 后台递归拷贝 src 下的所有文件到 dst。
	 */
	public function start(src:String, dst:String):Void
	{
		#if (cpp || neko || hl)
		mainThread = sys.thread.Thread.current();
		sys.thread.Thread.create(function() run(src, dst));
		#else
		run(src, dst);
		finished = true;
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

	// ------------------------------------------------------------------
	// Worker
	// ------------------------------------------------------------------

	function run(src:String, dst:String):Void
	{
		try
		{
			// 先统计文件总数（进度显示用）
			var files:Array<String> = [];
			collectFiles(src, files);
			var totalFiles:Int = files.length;

			total = totalFiles;
			done = 0;
			currentFile = '';
			sendMessage({t: 'prog', done: 0, total: totalFiles, cur: ''});

			var doneCount:Int = 0;
			for (f in files)
			{
				if (cancelRequested) break;
				currentFile = f;

				var rel:String = f.substr(src.length + 1);
				var outPath:String = Path.join([dst, rel]);
				var outDir:String = Path.directory(outPath);
				if (outDir.length > 0 && !FileSystem.exists(outDir))
					FileSystem.createDirectory(outDir);
				File.copy(f, outPath);

				doneCount++;
				done = doneCount;
				sendMessage({t: 'prog', done: doneCount, total: totalFiles, cur: currentFile});
			}

			done = totalFiles;
			if (cancelRequested)
				sendMessage({t: 'canceled'});
			else
				sendMessage({t: 'done'});
		}
		catch (e:Dynamic)
		{
			sendMessage({t: 'err', msg: Std.string(e)});
		}
	}

	/** 递归收集 src 下所有文件（不包含目录本身） */
	static function collectFiles(src:String, out:Array<String>):Void
	{
		for (entry in FileSystem.readDirectory(src))
		{
			var full:String = src + '/' + entry;
			if (FileSystem.isDirectory(full))
				collectFiles(full, out);
			else
				out.push(full);
		}
	}

	function sendMessage(msg:Dynamic):Void
	{
		#if (cpp || neko || hl)
		if (mainThread != null) mainThread.sendMessage(msg);
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
