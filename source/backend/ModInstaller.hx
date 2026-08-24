package backend;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import flixel.FlxG;
import states.MainMenuState;
import states.ModsMenuState;
import backend.ZipReader;
import backend.ZipReader.ZipExtractor;
import backend.ModZipPlanner;

/**
 * 拖入安装 mod（移植自 SeiunEngine 的安装方式）：
 *  - 监听 lime 窗口的 onDropFile（SDL 拖放）
 *  - .zip   -> ZipReader 自研解析（不经过 haxe.zip，避开其 hxcpp 解压堆越界）
 *              + ModZipPlanner 分析安装计划 + ZipExtractor 后台线程解压
 *  - 文件夹 -> 直接拷贝到 mods/
 * 安装全程由 ModInstallUI（FlxSubState）显示进度 / 起名 / 结果。
 *
 * 每帧由 MusicBeatState / MusicBeatSubstate 调 update() 泵后台线程消息。
 */
class ModInstaller
{
	static var _inst:ModInstaller = null;

	public static function get():ModInstaller
	{
		if (_inst == null) _inst = new ModInstaller();
		return _inst;
	}

	public static function init():Void
	{
		get().hookWindow();
	}

	public static function update(elapsed:Float):Void
	{
		get().pump(elapsed);
		get().pumpFolderCopy();
	}

	// ------------------------------------------------------------------
	// Public UI state (read by ModInstallUI)
	// ------------------------------------------------------------------
	public var busy(default, null):Bool = false;
	public var title:String = '';
	public var status:String = '';
	public var detailText:String = '';
	public var progress:Float = 0;
	public var indeterminate:Bool = false;
	public var canCancel:Bool = false;
	public var showPrompt:Bool = false;
	public var showResult:Bool = false;
	public var promptMessage:String = '';
	public var promptDefault:String = '';
	public var resultMessage:String = '';

	/** 最近一次成功安装完成的时间戳（haxe.Timer.stamp()）。
	 *  ModsMenuState 等界面轮询此值检测"打开期间装好了新 mod"，用于自动刷新列表。 */
	public var lastInstallTime:Float = 0;

	/** 看门狗：解压开始时间 / 最后进度时间 / 最后进度计数（防线程卡死无限等待） */
	var extractionStartedAt:Float = 0;
	var lastExtractProgressAt:Float = 0;
	var lastExtractDone:Int = -1;
	var firstProgAt:Float = 0; // 调试：首条进度消息到达时间

	/** 看门狗：文件夹拷贝（同解压） */
	var copierStartedAt:Float = 0;
	var lastCopierProgressAt:Float = 0;
	var lastCopierDone:Int = -1;

	var ui:ModInstallUI;
	var extractor:ZipExtractor;
	var copier:FolderCopier;
	var folderInstallName:String = ''; // 文件夹安装的目标 mod 名（拷贝完成后写 modsList 用）
	var pendingJobs:Array<InstallJob> = null;
	var promptJobIndex:Int = -1;
	var tempRoot:String = null;
	var installedNames:Array<String> = [];
	var pendingDrop:String = null;

	var hooked:Bool = false;

	function new() {}

	function hookWindow():Void
	{
		if (hooked) return;
		hooked = true;
		try
		{
			var window = lime.app.Application.current.window;
			if (window != null) window.onDropFile.add(onDropFile);
			trace('ModInstaller: drop-to-install listening (window.onDropFile).');
		}
		catch (e:Dynamic)
		{
			trace('ModInstaller hook failed: ' + Std.string(e));
		}
	}

	function pump(elapsed:Float):Void
	{
		if (busy && extractor != null)
		{
			extractor.pumpMessages();
			if (extractor.finished)
			{
				var ext:ZipExtractor = extractor;
				extractor = null;
				trace('[ModInstaller] extraction finished in ' + Std.int((haxe.Timer.stamp() - extractionStartedAt) * 1000) + 'ms' + (ext.error != null ? ', error=' + ext.error : ''));
				if (ext.error != null)
				{
					abortTask('解压失败：' + ext.error);
				}
				else if (ext.pendingPrompt)
				{
					onExtractionDone(true);
				}
				else
				{
					onExtractionDone(false);
				}
			}
			else if (extractor.total > 0)
			{
				progress = extractor.done / extractor.total;
				// 显示"当前文件 (已处理/总数)"，大文件条目处理期间也能看出在动
				detailText = extractor.currentFile + '  (' + extractor.done + '/' + extractor.total + ')';
				if (firstProgAt == 0) trace('[ModInstaller] first progress after ' + Std.int((haxe.Timer.stamp() - extractionStartedAt) * 1000) + 'ms');
				firstProgAt = haxe.Timer.stamp();
				// 看门狗：进度有变化就刷新"最后活动"时间
				if (extractor.done != lastExtractDone)
				{
					lastExtractDone = extractor.done;
					lastExtractProgressAt = haxe.Timer.stamp();
				}
			}

			// 看门狗：解压线程卡死/异常挂起时不再无限等待
			// （注意：上面的 finished 分支已把 extractor 置 null，这里必须判空）
			// 系统 unzip 无逐文件进度消息（total 恒为 0），超时阈值给足 120 秒
			if (extractor != null && !extractor.finished)
			{
				var now:Float = haxe.Timer.stamp();
				if (extractor.total > 0 && now - lastExtractProgressAt > 90)
					abortTask('解压超时（90 秒无进展），压缩包可能已损坏，已取消。');
				else if (extractor.total <= 0 && now - extractionStartedAt > 120)
					abortTask('解压超时（120 秒未完成），压缩包可能已损坏，已取消。');
			}
		}

		if (pendingDrop != null)
		{
			var p:String = pendingDrop;
			pendingDrop = null;
			onDropFile(p);
		}
	}

	/** 文件夹拷贝进度泵（installFolder 走后台线程时用） */
	function pumpFolderCopy():Void
	{
		if (busy && copier != null)
		{
			copier.pumpMessages();
			if (copier.finished)
			{
				var c:FolderCopier = copier;
				copier = null;
				if (c.error != null)
				{
					abortTask('复制失败：' + c.error);
				}
				else
				{
					// 拷贝完成：写入 modsList 并收尾
					addToModsList(folderInstallName);
					busy = false;
					lastInstallTime = haxe.Timer.stamp();
					showMessage('安装完成', '已安装：' + folderInstallName + '\n\n去 Mods 菜单里选中就能用啦！');
				}
			}
			else if (copier.total > 0)
			{
				progress = copier.done / copier.total;
				detailText = copier.currentFile + '  (' + copier.done + '/' + copier.total + ')';
				status = '正在复制文件夹… (' + copier.done + '/' + copier.total + ')';
				indeterminate = false;
				if (copier.done != lastCopierDone)
				{
					lastCopierDone = copier.done;
					lastCopierProgressAt = haxe.Timer.stamp();
				}
			}

			// 看门狗：拷贝线程卡死兜底
			if (copier != null && !copier.finished)
			{
				var now:Float = haxe.Timer.stamp();
				if (copier.total > 0 && now - lastCopierProgressAt > 90)
					abortTask('复制超时（90 秒无进展），已取消。');
				else if (copier.total <= 0 && now - copierStartedAt > 30)
					abortTask('复制超时（30 秒未开始），已取消。');
			}
		}
	}

	/** Entry point for the lime window drop event. */
	public function onDropFile(path:String):Void
	{
		if (path == null || path.length < 1) return;
		if (busy)
		{
			pendingDrop = path; // 正在安装时，稍后处理新拖入的文件
			return;
		}

		if (!isAllowedContext())
		{
			showMessage('这里不能安装', '请在主菜单或 Mods 菜单里拖入 zip / 文件夹喵～');
			return;
		}

		var lower:String = path.toLowerCase();

		// 文件夹
		if (FileSystem.exists(path) && FileSystem.isDirectory(path))
		{
			installFolder(path);
			return;
		}

		// zip
		if (FileSystem.exists(path) && (lower.endsWith('.zip') || ZipReader.isZipFile(path)))
		{
			startZip(path);
			return;
		}

		showMessage('不支持的文件', '把 .zip 压缩包或 mod 文件夹拖进来才能自动安装。');
	}

	/** 只允许在主菜单 / Mods 菜单（或其上的子状态）里触发安装。 */
	function isAllowedContext():Bool
	{
		var state:flixel.FlxState = FlxG.state;
		if (Std.isOfType(state, MainMenuState)) return true;
		if (Std.isOfType(state, ModsMenuState)) return true;

		var sub:flixel.FlxSubState = state.subState;
		while (sub != null)
		{
			if (Std.isOfType(sub, ModInstallUI)) return true;
			if (Std.isOfType(sub, states.ModsMenuState)) return true;
			sub = sub.subState;
		}
		return false;
	}

	// ------------------------------------------------------------------
	// ZIP install
	// ------------------------------------------------------------------

	function startZip(zipPath:String):Void
	{
		if (!ZipReader.isZipFile(zipPath))
		{
			showMessage('不是有效的压缩包', '这个文件看起来不是 ZIP：\n' + Path.withoutDirectory(zipPath));
			return;
		}

		busy = true;
		var zipBaseName:String = ModZipPlanner.sanitizeName(Path.withoutExtension(Path.withoutDirectory(zipPath)));

		var t0:Float = haxe.Timer.stamp();
		var entries:Array<ZipEntry>;
		try
		{
			entries = ZipReader.readEntries(zipPath);
		}
		catch (e:Dynamic)
		{
			busy = false;
			showMessage('解析失败', '无法读取这个压缩包：\n' + Std.string(e));
			return;
		}
		trace('[ModInstaller] readEntries: ' + Std.int((haxe.Timer.stamp() - t0) * 1000) + 'ms, entries=' + entries.length);

		if (entries.length == 0)
		{
			busy = false;
			showMessage('空压缩包', '这个压缩包里什么都没有。');
			return;
		}

		// 先定安装计划（只看元数据，很快）
		var t1:Float = haxe.Timer.stamp();
		var plan = ModZipPlanner.analyze(entries);
		trace('[ModInstaller] analyze: ' + Std.int((haxe.Timer.stamp() - t1) * 1000) + 'ms');
		if (plan == null)
		{
			busy = false;
			showMessage('无法安装', '压缩包里没有看起来像 mod 的内容。');
			return;
		}

		tempRoot = Sys.getCwd() + 'temp/mods-install/' + Date.now().getTime() + '/';
		installedNames = [];

		// zip 根目录就是散装 mod 内容时，用 zip 文件名补名
		for (job in plan.jobs)
		{
			if (job.name == null || job.name.length == 0)
				job.name = zipBaseName;
		}

		if (plan.promptForName)
		{
			pendingJobs = plan.jobs;
			promptJobIndex = plan.promptIndex;
			promptDefault = plan.promptDefault;
			promptMessage = '压缩包里有一层叫 "mods" 的文件夹，请给它起个名字：';
			beginExtraction(zipPath, true);
		}
		else
		{
			pendingJobs = plan.jobs;
			promptJobIndex = -1;
			beginExtraction(zipPath, false);
		}
	}

	function beginExtraction(zipPath:String, willPrompt:Bool):Void
	{
		openUI();
		showPrompt = false;
		showResult = false;
		canCancel = true;
		title = '安装 Mod';
		status = '正在解压…';
		indeterminate = true;
		progress = 0;
		extractionStartedAt = haxe.Timer.stamp();
		lastExtractProgressAt = extractionStartedAt;
		lastExtractDone = -1;
		firstProgAt = 0;

		try
		{
			extractor = new ZipExtractor(zipPath);
			extractor.pendingPrompt = willPrompt;
			extractor.start(tempRoot);
			detailText = '';
		}
		catch (e:Dynamic)
		{
			abortTask('解压失败：' + Std.string(e));
		}
	}

	function onExtractionDone(willPrompt:Bool):Void
	{
		if (willPrompt)
		{
			showPrompt = true;
			canCancel = true;
			title = '给 mod 起个名字';
			status = '';
			indeterminate = false;
			if (ui != null) ui.focusInput();
			return;
		}

		runInstallJobs();
	}

	/** 由 ModInstallUI 在玩家确认名字后调用 */
	public function confirmName(rawName:String):Void
	{
		if (!busy || pendingJobs == null) return;
		var name:String = ModZipPlanner.sanitizeName(rawName);
		if (name.length == 0)
		{
			if (ui != null) ui.showPromptError('名字不能为空或包含非法字符，再试一次');
			return;
		}

		if (promptJobIndex >= 0 && promptJobIndex < pendingJobs.length)
			pendingJobs[promptJobIndex].name = name;
		showPrompt = false;
		runInstallJobs();
	}

	/** 由 ModInstallUI 在玩家取消起名时调用 */
	public function cancelPrompt():Void
	{
		abortTask('已取消安装。');
	}

	/** 由 ModInstallUI 的取消按钮 / ESC 调用 */
	public function cancelTask():Void
	{
		abortTask('已取消安装。');
	}

	// ------------------------------------------------------------------
	// Install execution
	// ------------------------------------------------------------------

	function runInstallJobs():Void
	{
		var tStart:Float = haxe.Timer.stamp();
		if (pendingJobs == null || pendingJobs.length == 0)
		{
			abortTask('没有可安装的内容。');
			return;
		}

		var modsDir:String = Sys.getCwd() + 'mods';
		if (!FileSystem.exists(modsDir)) FileSystem.createDirectory(modsDir);

		title = '安装 Mod';
		status = '正在安装…';
		indeterminate = true;
		showPrompt = false;
		canCancel = false;

		installedNames = [];
		var failed:Array<String> = [];
		var total:Int = pendingJobs.length;
		var done:Int = 0;

		for (job in pendingJobs)
		{
			if (job.name == null || StringTools.trim(job.name).length == 0)
			{
				failed.push(job.src);
				done++;
				continue;
			}

			var srcPath:String = job.src.length == 0 ? tempRoot : tempRoot + job.src;
			if (!FileSystem.exists(srcPath))
			{
				failed.push(job.name);
				done++;
				continue;
			}

			var targetName:String = uniqueModName(modsDir, job.name);
			var targetPath:String = modsDir + '/' + targetName;
			try
			{
				moveInto(srcPath, targetPath);
				installedNames.push(targetName);
				addToModsList(targetName);
			}
			catch (e:Dynamic)
			{
				failed.push(job.name + ' (' + Std.string(e) + ')');
			}

			done++;
			progress = done / total;
			status = '正在安装… (' + done + '/' + total + ')';
		}

		cleanupTemp();
		pendingJobs = null;
		busy = false;

		var msg:String = '';
		if (installedNames.length > 0)
			msg += '已安装：' + installedNames.join('、') + '\n';
		if (failed.length > 0)
			msg += '以下内容安装失败：' + failed.join('、') + '\n';
		msg += '\n去 Mods 菜单里选中就能用啦！';
		if (installedNames.length > 0)
			lastInstallTime = haxe.Timer.stamp(); // 通知打开中的 Mods 菜单刷新
		showMessage('安装完成', msg);
		trace('[ModInstaller] install jobs done in ' + Std.int((haxe.Timer.stamp() - tStart) * 1000) + 'ms');
	}

	function uniqueModName(modsDir:String, base:String):String
	{
		var name:String = ModZipPlanner.sanitizeName(base);
		var candidate:String = name;
		var i:Int = 1;
		while (FileSystem.exists(modsDir + '/' + candidate))
		{
			candidate = name + ' (' + i + ')';
			i++;
		}
		return candidate;
	}

	/** 移动文件/目录；rename 不行就递归拷贝 */
	static function moveInto(src:String, dst:String):Void
	{
		if (FileSystem.isDirectory(src))
		{
			try
			{
				FileSystem.rename(src, dst);
				return;
			}
			catch (e:Dynamic)
			{
				copyDir(src, dst);
				deleteDirRecursive(src);
			}
		}
		else
		{
			try
			{
				FileSystem.rename(src, dst);
			}
			catch (e:Dynamic)
			{
				File.copy(src, dst);
				FileSystem.deleteFile(src);
			}
		}
	}

	static function copyDir(src:String, dst:String):Void
	{
		if (!FileSystem.exists(dst)) FileSystem.createDirectory(dst);
		for (entry in FileSystem.readDirectory(src))
		{
			var s:String = src + '/' + entry;
			var d:String = dst + '/' + entry;
			if (FileSystem.isDirectory(s))
				copyDir(s, d);
			else
				File.copy(s, d);
		}
	}

	/** 递归删除目录树；只允许删自己的临时安装根目录 */
	static function deleteDirRecursive(path:String):Void
	{
		if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) return;
		var cwd:String = Sys.getCwd();
		var tempBase:String = cwd + 'temp/mods-install';
		if (path != tempBase && path.indexOf(tempBase + '/') != 0)
		{
			trace('ModInstaller: refusing to delete outside temp: ' + path);
			return;
		}
		for (entry in FileSystem.readDirectory(path))
		{
			var full:String = path + '/' + entry;
			if (FileSystem.isDirectory(full))
				deleteDirRecursive(full);
			else
				FileSystem.deleteFile(full);
		}
		FileSystem.deleteDirectory(path);
	}

	function cleanupTemp():Void
	{
		if (tempRoot != null && tempRoot.length > 0)
		{
			var p:String = tempRoot;
			tempRoot = null;
			// 异步删除临时目录：大 mod 解压出的几百个文件删除也要一两秒，
			// 放后台线程避免安装完成瞬间主线程卡顿
			#if (cpp || neko || hl)
			sys.thread.Thread.create(function() deleteDirRecursive(p));
			#else
			deleteDirRecursive(p);
			#end
		}
	}

	function addToModsList(modName:String):Void
	{
		try
		{
			var listPath:String = Mods.modsListPath();
			var lines:Array<String> = [];
			var found:Bool = false;
			if (FileSystem.exists(listPath))
			{
				for (line in CoolUtil.coolTextFile(listPath))
				{
					if (line.trim().length < 1) continue;
					var parts:Array<String> = line.split('|');
					if (parts.length >= 1 && parts[0] == modName)
					{
						found = true; // 已在列表里（比如重装），保留原行
						lines.push(line);
					}
					else
					{
						lines.push(line); // 原样保留其它 mod 行（含启用状态）
					}
				}
			}

			if (!found)
			{
				// 新 mod 默认关闭（|0）：
				// 1) 直接 File.append 会粘在无尾换行的最后一行上（modsList.txt 由
				//    Mods.updateModList 写出时最后一行不带 \n），把上一行启用标志破坏成
				//    "A|1B|B" → 上一个启用的 mod 被解析成关闭（"安装后模组自动关闭" bug 根因）
				// 2) 若默认启用且排在前，loadTopMod 会把 currentModDirectory 切到新 mod，
				//    让当前生效的 mod 资源全部失效
				lines.push(modName + '|0');
				File.saveContent(listPath, lines.join('\n'));
				trace('ModInstaller: added ' + modName + '|0 to ' + listPath);
			}
		}
		catch (e:Dynamic)
		{
			trace('ModInstaller: could not update modsList.txt: ' + Std.string(e));
		}
	}

	// ------------------------------------------------------------------
	// Folder drop
	// ------------------------------------------------------------------

	function installFolder(folderPath:String):Void
	{
		var modsDir:String = Sys.getCwd() + 'mods';
		if (!FileSystem.exists(modsDir)) FileSystem.createDirectory(modsDir);

		var absSrc:String = haxe.io.Path.normalize(folderPath);
		var absMods:String = haxe.io.Path.normalize(modsDir);
		if (absSrc == absMods || absSrc.indexOf(absMods + '/') == 0 || absSrc.indexOf(absMods + '\\') == 0)
		{
			showMessage('不需要', '这就是 mods 文件夹本身，拖别的来～');
			return;
		}

		busy = true;
		openUI();
		title = '安装 Mod';
		status = '正在复制文件夹…';
		indeterminate = true;
		canCancel = true;
		showPrompt = false;
		showResult = false;
		copierStartedAt = haxe.Timer.stamp();
		lastCopierProgressAt = copierStartedAt;
		lastCopierDone = -1;

		var baseName:String = ModZipPlanner.sanitizeName(Path.withoutDirectory(folderPath));
		var targetName:String = uniqueModName(modsDir, baseName);
		try
		{
			// 后台线程递归拷贝（大文件夹不堵主线程），pumpFolderCopy 每帧泵进度
			folderInstallName = targetName;
			copier = new FolderCopier();
			copier.start(folderPath, modsDir + '/' + targetName);
			detailText = '';
		}
		catch (e:Dynamic)
		{
			abortTask('复制失败：' + Std.string(e));
		}
	}

	// ------------------------------------------------------------------
	// UI plumbing
	// ------------------------------------------------------------------

	public function openUI():Void
	{
		if (ui != null && ui.exists) return;
		ui = new ModInstallUI();
		FlxG.state.openSubState(ui);
	}

	/** 由 ModInstallUI 关闭时调用 */
	public function onUIClosed():Void
	{
		ui = null;
	}

	function showMessage(titleText:String, message:String):Void
	{
		openUI();
		this.title = titleText;
		this.resultMessage = message;
		this.showResult = true;
		this.showPrompt = false;
		this.canCancel = false;
		this.progress = 0;
		this.indeterminate = false;
		this.status = '';
	}

	function abortTask(message:String):Void
	{
		if (extractor != null)
		{
			extractor.requestCancel();
			extractor = null;
		}
		if (copier != null)
		{
			copier.requestCancel();
			copier = null;
		}
		cleanupTemp();
		pendingJobs = null;
		busy = false;
		showPrompt = false;
		showMessage('已取消', message);
	}
}
