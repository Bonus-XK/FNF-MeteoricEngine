package backend;

import haxe.io.Output;
import lime.graphics.opengl.GL;
import lime.ui.Window;
import lime.utils.DataPointer;
#if (sys && !android)
import sys.io.Process;
import sys.FileSystem;
#end

/**
 * 引擎内置录像（Render Mode）。
 *
 * 机制与 JS Engine 的 Game Renderer 同源，但换掉了它的经典落盘做法：
 *   JS Engine 经典模式 —— 每帧存一张 PNG/JPG 到 assets/gameRenders/<歌名>/，
 *   唱完整首再手动跑 renderlinux.sh / renderlol.bat 合成视频。
 *   代价是几千次磁盘写 + 事后合成，且**完全没有音频**（脚本里 ffmpeg 只有图像序列一路输入）。
 * 这里改成：帧数据直接管道喂给 ffmpeg 子进程（`-f rawvideo`），不落盘、不吃额外磁盘。
 *
 * 音频同样不实时抓取：直接把**歌曲自己的音频文件**作为 ffmpeg 的第二路输入。
 * 录制从歌曲开始的那一刻启动，音频也从 0 开始，两条时间轴同起点 → 天然同步，
 * 既不用重编游戏音频管线，也不用碰 SDL 回调（不会引入额外延迟）。
 *
 * ============ 抓帧路径：为什么不用 lime 的 Window.readPixels ============
 *
 * lime 的 `Window.readPixels()` 每次调用都 `new UInt8Array(w*h*4)`
 * （lime/_internal/backend/native/NativeWindow.hx:372）。Retina 下物理分辨率
 * 约 3840×2160 → **单帧 33MB**，60fps 就是 ~2GB/s 的分配churn，GC 根本追不上
 * （实测内存每秒涨 3GB，三秒吃光）。这不是逻辑泄漏，是分配风暴。
 *
 * 所以默认走**快路径**：启动时一次性分配一个 `Bytes` + `DataPointer`，
 * 每帧直接 `glReadPixels` 写进这块**同一块**内存，再管道送走 —— 全程零分配。
 * 代价：GL 的帧缓冲是自下而上（bottom-up），而 Window.readPixels 会在 C++ 侧
 * 逐行翻转成自上而下。快路径不翻，改由 ffmpeg 用 `-vf vflip` 翻（零 CPU 开销）。
 *
 * 快路径依赖 `lime_cffi + lime_opengl`（宏关了那条 readPixels 是空壳，会静默
 * 读到垃圾数据）。宏没开时回退到 `Window.readPixels()`，靠周期性 GC 兜住内存 ——
 * 慢且有卡顿，但不会把内存吃光。走哪条由 trace 明确打印。
 */
class VideoRecorder
{
	/** ffmpeg 可执行文件候选路径（Homebrew / PATH）。 */
	static final FFMPEG_CANDIDATES:Array<String> = [
		'/opt/homebrew/bin/ffmpeg', // Apple Silicon Homebrew
		'/usr/local/bin/ffmpeg', // Intel Homebrew
		'/usr/bin/ffmpeg',
		// Windows 常见**跨用户**安装位置（winget 的 per-user Links 目录不做枚举，交给 PATH 探测兜底）
		'C:\\ffmpeg\\bin\\ffmpeg.exe',
		'C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe',
		'C:\\Program Files (x86)\\ffmpeg\\bin\\ffmpeg.exe',
		'C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe',
		'C:\\msys64\\mingw64\\bin\\ffmpeg.exe'
	];

	public static var isRecording:Bool = false;
	/** 已送入 ffmpeg 的帧数（调试用）。 */
	public static var frameCount:Int = 0;
	/** 每次抓帧的耗时（毫秒），供选项页展示/排障。 */
	public static var lastCaptureMs:Float = 0;
	/** 实际使用的抓帧路径（'gl' = 零分配快路径；'window' = 回退，会分配）。 */
	public static var activePath:String = 'none';

	// ============== 便携 ffmpeg 自动获取（玩家零安装） ==============
	// 缺 ffmpeg 时由设置页（RenderModeSubState，需 ClientPrefs.data.ffmpegAutoFetch = true）
	// 起一个后台线程：官方静态构建 curl 直下 → 系统 tar 单条目解压 → 改名到
	// 引擎目录 ffmpeg/ffmpeg(.exe) → -version 烟雾测试。与引擎目录一起可携带、随目录跑。
	// 状态机（installState）：idle →（下载中）→（解压中）→ ready / error；
	// 页面只读这几个值做展示，重试 = 下次进设置页自动再来一次（error 态允许重入）。
	#if (sys && !android)
	/** 自动获取当前阶段：'idle' | 'downloading' | 'unpacking' | 'ready' | 'error'。 */
	public static var installState:String = 'idle';
	/** 已下载 MB 数（下载期由工作线程每 0.4s 回填；UI 只读）。 */
	public static var installCurMB:Int = 0;
	/** 失败原因（英文技术信息，UI 直接展示）。 */
	public static var installError:String = null;
	static var installThread:sys.thread.Thread = null;
	// 下载监视线程的握手位：写者仅监视线程（worker 主循环轮询）
	static var installDlDone:Bool = false;
	static var installDlCode:Int = -1;
	#end

	#if (sys && !android)
	static var proc:Process = null;
	static var stdinOut:Output = null;
	static var outPath:String = null;
	static var ffmpegPath:String = null;
	static var nextFrameAt:Float = 0;
	static var frameInterval:Float = 1.0 / 60.0;
	static var win:Window = null;

	// ---- 快路径的预分配缓冲（start 时分配一次，capture 每帧复用）----
	static var frameBuf:haxe.io.Bytes = null;
	// ⚠ DataPointer 是 cpp 原生指针类型，静态平台上不能为 null ——
	//   所以它没有初始化器，「是否已分配」一律由下面的 useFastPath 判定。
	static var framePtr:DataPointer;
	static var bufW:Int = 0;
	static var bufH:Int = 0;
	static var glCtx:Dynamic = null;
	/** 走快路径（零分配）还是回退（每次分配，需要 GC 兜底）。 */
	static var useFastPath:Bool = false;
	#end

	/** ffmpeg 是否可用（选项页据此决定是否给出自动获取行）。 */
	public static function ffmpegAvailable():Bool
	{
		#if (sys && !android)
		if (findFFmpeg() != null) return true;
		try
		{
			var pr = new Process('ffmpeg', ['-version']);
			pr.close();
			return true;
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}

	#if (sys && !android)
	/**
	 * 引擎目录下便携 ffmpeg 的绝对路径；拿不到应用目录时 null。
	 * 与录像输出同基准（可执行文件所在目录，见 start() 里的 appDir 注释）——
	 * 换目录/换机器随手整个目录带走就还能用。
	 */
	public static function portableFFmpegPath():String
	{
		var base:String = null;
		try
		{
			base = lime.system.System.applicationDirectory;
		}
		catch (e:Dynamic)
		{
			base = null;
		}
		if (base == null || base.length == 0) return null;
		if (base.charAt(base.length - 1) != '/' && base.charAt(base.length - 1) != '\\') base += '/';
		#if windows
		return base + 'ffmpeg/ffmpeg.exe';
		#else
		return base + 'ffmpeg/ffmpeg';
		#end
	}

	#if (sys && !android)
	/**
	 * 幂等启动后台安装。已在装 / 已装好返回 false；error 态允许重入（下次进设置页自动重试一次）。
	 * @return true = 已交给工作线程
	 *
	 * ⚠ 这一段（startPortableInstall / findFFmpeg / installWorker）必须整体留在
	 *    #if (sys && !android) 里，三个函数互相依赖、且都依赖 #if 内的成员：
	 *      - startPortableInstall 用 installState / installCurMB / installError / installThread
	 *      - findFFmpeg 调 portableFFmpegPath()（本身也在 #if 内）
	 *      - installWorker 是 curl 下载 + tar 解压的桌面端安装流程
	 *    声明漏在外面、成员被排除 → Android 编译报 "has no field"，
	 *    并连带把 RenderModeSubState 的引用一起打挂（实测 5 个错误）。
	 */
	public static function startPortableInstall():Bool
	{
		if (ffmpegAvailable()) return false;
		if (installThread != null) return false;
		if (installState == 'downloading' || installState == 'unpacking') return false;
		installState = 'downloading';
		installCurMB = 0;
		installError = null;
		installThread = sys.thread.Thread.create(installWorker);
		return true;
	}

	/**
	 * ffmpeg 可执行文件解析顺序：便携目录优先（自包含，跟引擎目录走），其次安装位置候选。
	 * 注意**不含** PATH 探测 —— start() 的录像启动只信任「明确的文件」，PATH 探测只给选项页用。
	 */
	static function findFFmpeg():String
	{
		var portable:String = portableFFmpegPath();
		if (portable != null && FileSystem.exists(portable)) return portable;
		for (p in FFMPEG_CANDIDATES)
			if (FileSystem.exists(p)) return p;
		return null;
	}

	/**
	 * 安装工作线程主体。hxcpp 线程闭包没有异常保护 —— 任何逃逸异常 Release 下是堆损坏
	 * abort（见 ZipReader.runWorker 的崩溃加固注释），所以整个函数体包进 try/catch。
	 *
	 * 流程：清上次残件 → curl 官方静态包 → 系统 tar 单条目解压 → 改名就位 →
	 * chmod（mac）→ `ffmpeg -version` 烟雾测试 → 删临时件。任何一步失败置 error 态。
	 */
	static function installWorker():Void
	{
		var stage:String = null;
		var tmpZip:String = null;
		var ok:Bool = false;
		try
		{
			var exePath:String = portableFFmpegPath();
			if (exePath == null) throw 'portable path unavailable on this platform';
			var dir:String = null;
			try
			{
				dir = haxe.io.Path.directory(exePath);
			}
			catch (e:Dynamic)
			{
				dir = null;
			}
			if (dir == null || dir.length == 0) throw 'cannot resolve engine ffmpeg directory';
			stage = dir + '/_stage';
			tmpZip = dir + '/_dl.zip';
			// 清理上次被打断（游戏退出 / 断电 / 断网）留下的残件，从零重下
			try
			{
				if (FileSystem.exists(stage)) ContainerStore.deleteTree(stage);
			}
			catch (e:Dynamic) {}
			try
			{
				if (FileSystem.exists(tmpZip)) FileSystem.deleteFile(tmpZip);
			}
			catch (e:Dynamic) {}
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			FileSystem.createDirectory(stage);

			// 官方静态构建（两条都在本机实测过 URL 有效性 + 包内布局）：
			// Windows：gyan.dev release-essentials（稳定别名 URL，重定向自动跟随）
			//          内部 ffmpeg-<版本>-essentials_build/bin/ffmpeg.exe
			// macOS：evermeet.cx 静态 ffmpeg（Intel 版，Apple Silicon 下走 Rosetta 跑起来）
			//        内部单条目 ffmpeg；URL 钉在具体版本号，包发布后长期在线。
			#if windows
			var url:String = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
			#else
			var url:String = 'https://evermeet.cx/ffmpeg/ffmpeg-9.0.2.zip';
			#end
			if (!downloadPortable(url, tmpZip))
				throw 'download (curl) failed, exit ' + installDlCode;

			installState = 'unpacking';
			// 系统 tar / unzip：bulk deflate 走 native zlib，大条目不进 Haxe 堆（ZipReader 同一依据）
			#if windows
			// essentials 包里还有 400MB+ 的 ffplay/ffprobe，用通配只掏 ffmpeg.exe（bsdtar 提取模式支持通配，已实测）
			var tarCmd:String = 'tar -xf "' + tmpZip + '" -C "' + stage + '" '
				+ '"ffmpeg-*-essentials_build/bin/ffmpeg.exe"';
			#else
			// mac 包单条目，直接全解
			var tarCmd:String = 'tar -xf "' + tmpZip + '" -C "' + stage + '"';
			#end
			var exitTar:Int = -1;
			try
			{
				exitTar = Sys.command(tarCmd);
			}
			catch (e:Dynamic)
			{
				exitTar = -1;
			}
			if (exitTar != 0) throw 'unpack (tar) failed, exit ' + exitTar;

			// 在 stage 里找解出来的可执行文件（Windows 在 <版本目录>/bin/ 下；mac 是根下 ffmpeg）
			// 目录树很小（essentials 通配只解出 3 项以内的路径），仍给 64 次迭代硬上界防异常结构。
			var produced:String = null;
			var stack:Array<String> = [stage];
			var visited:Int = 0;
			while (stack.length > 0 && visited < 64)
			{
				visited++;
				var cur:String = stack.pop();
				for (f in readDirSafe(cur))
				{
					var full:String = cur + '/' + f;
					if (FileSystem.isDirectory(full))
					{
						stack.push(full);
						continue;
					}
					#if windows
					if (f == 'ffmpeg.exe')
					{
						produced = full;
						break;
					}
					#else
					if (f == 'ffmpeg')
					{
						produced = full;
						break;
					}
					#end
				}
				if (produced != null) break;
			}
			if (produced == null) throw 'ffmpeg binary not found in downloaded archive';

			// 原子就位：rename 到最终路径（同分区 rename 是原子的）；先删可能存在的半份旧文件
			try
			{
				if (FileSystem.exists(exePath)) FileSystem.deleteFile(exePath);
			}
			catch (e:Dynamic) {}
			FileSystem.rename(produced, exePath);
			#if mac
			// evermeet 的 zip 自带 +x 位；为防 Haxe 写盘路径改位丢失，补一次
			Sys.command('chmod', ['+x', exePath]);
			#end

			// 烟雾测试：能跑起 -version 且退出码 0 才算装好
			var pr:Process = null;
			var smokeFail:String = '';
			try
			{
				pr = new Process(exePath, ['-version']);
			}
			catch (e:Dynamic)
			{
				smokeFail = Std.string(e);
			}
			if (pr == null) throw 'installed ffmpeg cannot start: ' + smokeFail;
			var smokeCode:Int = -1;
			try
			{
				smokeCode = pr.exitCode();
			}
			catch (e:Dynamic)
			{
				smokeCode = -1;
			}
			try
			{
				pr.close();
			}
			catch (e:Dynamic) {}
			if (smokeCode != 0) throw 'ffmpeg smoke test failed, exit ' + smokeCode;

			installState = 'ready';
			trace('[Recorder] portable ffmpeg ready: ' + exePath);
			ok = true;
		}
		catch (e:Dynamic)
		{
			installError = Std.string(e);
			installState = 'error';
			trace('[Recorder] portable ffmpeg install failed: ' + installError);
		}
		// 收尾：临时件无论成败都尽力清（失败的 zip 留着只会占盘）
		try
		{
			if (stage != null && FileSystem.exists(stage)) ContainerStore.deleteTree(stage);
		}
		catch (e:Dynamic) {}
		try
		{
			if (tmpZip != null && FileSystem.exists(tmpZip)) FileSystem.deleteFile(tmpZip);
		}
		catch (e:Dynamic) {}
		// ⚠ 必须 null 掉线程引用：主线程的重入判定是「installThread != null 就拒绝」，
		//   线程自己退完不清引用 → 后续 error 态重试（重新进设置页）会被永久卡死。
		installThread = null;
	}
	#end

	static function readDirSafe(p:String):Array<String>
	{
		try
		{
			return FileSystem.readDirectory(p);
		}
		catch (e:Dynamic)
		{
			return [];
		}
	}

	/**
	 * curl 下载到 dest。监视线程阻塞收退出码（不占主线程），本线程每 0.4s
	 * 轮询文件大小回填 installCurMB（UI 得到活进度）。
	 * curl 自带说明：-L 跟随重定向；--fail 把 4xx/5xx 变非零退出；
	 * --speed-time/--speed-limit 防「连接死了但没断」半永久挂起；--max-time 30 分钟总兜底。
	 * macOS 的 curl 下载**不带** quarantine xattr，子进程能直接拉起（浏览器下载则会）。
	 */
	static function downloadPortable(url:String, dest:String):Bool
	{
		installDlDone = false;
		installDlCode = -1;
		installCurMB = 0;
		var proc:Process = null;
		// Sys.println 之外的 stderr：curl -sS 进度静默，错误文本极短，不会塞爆管道
		var args:Array<String> = ['-sS', '-L', '--fail', '--retry', '2',
			'--connect-timeout', '20', '--max-time', '1800',
			'--speed-time', '30', '--speed-limit', '1024',
			'-o', dest, url];
		try
		{
			proc = new Process('curl', args);
		}
		catch (e:Dynamic)
		{
			installError = 'curl not available: ' + Std.string(e);
			return false;
		}
		// 监视线程：hxcpp 线程闭包无异常保护 → 全体 try/catch
		sys.thread.Thread.create(function():Void
		{
			var code:Int = -2;
			try
			{
				code = proc.exitCode(); // 阻塞至 curl 收敛
			}
			catch (e:Dynamic)
			{
				code = -2;
			}
			try
			{
				proc.close();
			}
			catch (e:Dynamic) {}
			installDlCode = code;
			installDlDone = true;
		});
		while (!installDlDone)
		{
			Sys.sleep(0.4);
			try
			{
				var st = FileSystem.stat(dest);
				if (st != null && st.size > 0) installCurMB = Std.int(st.size / 1048576);
			}
			catch (e:Dynamic) {}
		}
		return installDlCode == 0 && FileSystem.exists(dest);
	}
	#end

	/**
	 * 解析歌曲 Inst 音频的可用路径（给 ffmpeg 当第二路输入用）。
	 * 与 LoadingState.getSongAudioFiles 同款解析顺序：mod 的 songs/<歌名>/Inst.ext 优先，
	 * 否则回退 assets/songs/<歌名>/Inst.ext。
	 */
	public static function resolveSongAudioPath(songName:String):String
	{
		#if (sys && !android)
		if (songName == null || songName.length == 0) return null;
		var songPath:String = Paths.formatToSongPath(songName);
		var ext:String = Paths.SOUND_EXT;
		#if MODS_ALLOWED
		try
		{
			var modFile:String = Paths.modsSounds('songs', songPath + '/Inst');
			if (FileSystem.exists(modFile)) return modFile;
		}
		catch (e:Dynamic) {}
		#end
		var rel:String = 'assets/songs/' + songPath + '/Inst.' + ext;
		try
		{
			if (FileSystem.exists(rel)) return rel;
		}
		catch (e:Dynamic) {}
		return null;
		#end
		return null;
	}

	/**
	 * 开始录制。
	 *
	 * @param songName  用于文件名
	 * @param audioPath 歌曲音频文件的绝对路径（可空 → 无声视频）
	 * @param fps       视频帧率
	 * @param bitrateMb 视频码率（Mb/s）
	 * @param encoder   视频编码器（libx264 等）
	 * @param dir       输出目录（相对引擎根目录）
	 * @return 成功返回输出文件路径，失败返回 null
	 */
	public static function start(songName:String, audioPath:String, fps:Float, bitrateMb:Float, encoder:String, dir:String):String
	{
		#if (sys && !android)
		if (isRecording) return outPath;

		ffmpegPath = findFFmpeg();
		if (ffmpegPath == null)
		{
			trace('[Recorder] 未找到 ffmpeg，无法录像（装 Homebrew: brew install ffmpeg）');
			return null;
		}

		win = lime.app.Application.current.window;
		if (win == null)
		{
			trace('[Recorder] 拿不到窗口句柄，无法录像');
			return null;
		}

		// 物理像素尺寸：lime 内部渲染用的是 width * scale（Retina 下 scale=2），
		// 用 FlxG.width（逻辑像素）会录出一半分辨率的糊画面。
		var w:Int = Std.int(win.width * win.scale);
		var h:Int = Std.int(win.height * win.scale);
		if (w <= 0 || h <= 0)
		{
			trace('[Recorder] 窗口尺寸异常：' + w + 'x' + h);
			return null;
		}
		w -= (w & 1);
		h -= (h & 1);

		// ---- 决定抓帧路径，并预分配缓冲（快路径必须只分配一次）----
		bufW = w;
		bufH = h;
		frameBuf = null;
		glCtx = null;
		useFastPath = false;
		#if (lime_cffi && (lime_opengl || lime_opengles))
		trace('[Recorder] 快路径宏已开启（lime_cffi + lime_opengl）');
		try
		{
			// ⚠ Windows/桌面 OpenGL 渲染时，context.webgl 是 null（WebGL 兼容层未创建）。
			//   必须用 context.gl（OpenGLRenderContext → NativeOpenGLRenderContext），
			//   它的 readPixels 定义在 NativeOpenGLRenderContext 上（lime 8.2.2 源码确认）。
			glCtx = win.context.gl;
			// 只判非 null；方法是否存在交给 capture() 的 try/catch 实测
			// （Haxe 没有 Reflect.hasMethod，预检只能靠类型判断，反而不可靠）。
			// capture() 首次失败会自动降级成 window 路径，不会崩也不会静默出黑屏。
			if (glCtx != null)
			{
				frameBuf = haxe.io.Bytes.alloc(w * h * 4);
				framePtr = DataPointer.fromBytes(frameBuf);
				useFastPath = frameBuf != null;
			}
		}
		catch (e:Dynamic)
		{
			trace('[Recorder] 快路径初始化失败，回退 Window.readPixels：' + Std.string(e));
			glCtx = null;
			frameBuf = null;
			useFastPath = false;
		}
		#else
		trace('[Recorder] 快路径宏未开启（lime_cffi/lime_opengl 缺一），只能回退 Window.readPixels');
		#end
		activePath = useFastPath ? 'gl' : 'window';

		// 输出目录。
		// ⚠ 不能直接用相对路径：lime 把进程 CWD 设成 .app 内部的 Contents/Resources，
		//   相对路径会落进 bundle 里 —— 本机 bundle 有 79GB（mods 谱面），
		//   再往里塞录像会让 codesign 更慢（已实测单步 30 分钟以上），
		//   而且换 bundle 时录像会一起丢。所以统一以**可执行文件所在目录**为基准。
		var appDir:String = 'recordings/';
		#if (sys && !android)
		try
		{
			var ad:String = lime.system.System.applicationDirectory;
			if (ad != null && ad.length > 0)
			{
				if (ad.charAt(ad.length - 1) != '/' && ad.charAt(ad.length - 1) != '\\') ad += '/';
				appDir = ad;
			}
		}
		catch (e:Dynamic) {}
		#end

		// dir 是相对 app 目录的子目录名（如 'recordings/'）；空则用默认
		var rel:String = (dir == null || dir.length == 0) ? 'recordings/' : dir;
		if (rel.charAt(rel.length - 1) != '/') rel += '/';
		// 防止 dir 传绝对路径时跑到别处（那样可能是用户有意为之，只做规范化）
		while (rel.length > 1 && (rel.charAt(0) == '/' || rel.charAt(0) == '\\')) rel = rel.substr(1);

		var baseDir:String = appDir + rel;
		try
		{
			FileSystem.createDirectory(baseDir);
		}
		catch (e:Dynamic) {}

		var safe:String = (songName == null || songName.length == 0) ? 'song' : songName;
		outPath = baseDir + safe + '-' + DateTools.format(Date.now(), '%Y-%m-%d_%H-%M-%S') + '.mp4';

		var args:Array<String> = [
			'-y',
			// 视频输入：来自 stdin 的原始 RGBA
			'-f', 'rawvideo',
			'-pixel_format', 'rgba',
			'-video_size', w + 'x' + h,
			'-framerate', Std.string(fps),
			'-i', 'pipe:0'
		];

		// 音频输入：直接复用歌曲音频文件（与视频同起点 → 天然同步）
		var hasAudio:Bool = false;
		if (audioPath != null && audioPath.length > 0 && FileSystem.exists(audioPath))
		{
			// ⚠ 音画对齐：抓帧发生在 Flixel 的 update 里，而绘制在 update 之后，
			//   所以每次 readPixels 读到的是**上一帧**已完成的画面 —— 视频整体滞后一帧
			//   （60fps 下 16.7ms，节奏游戏里是能看出来的）。
			//   抓帧时机改不了（绘制必然在 update 后），所以让**音频**等一帧：
			//   -itsoffset 把音频输入的时间戳整体后移 1/fps，与视频的固定滞后抵消。
			args.push('-itsoffset');
			args.push(Std.string(1.0 / Math.max(1.0, fps)));
			args.push('-i');
			args.push(audioPath);
			hasAudio = true;
		}

		args.push('-c:v');
		args.push(encoder);
		args.push('-preset');
		args.push('veryfast');
		args.push('-b:v');
		args.push(Std.string(bitrateMb) + 'M');
		args.push('-pix_fmt');
		args.push('yuv420p'); // 播放器兼容性

		if (useFastPath)
		{
			// 快路径喂的是 GL 原始帧缓冲（自下而上），由 ffmpeg 翻正 —— 零 CPU 开销。
			// （回退路径用 Window.readPixels，lime 已在 C++ 侧翻过，不能再翻。）
			args.push('-vf');
			args.push('vflip');
		}

		if (hasAudio)
		{
			args.push('-c:a');
			args.push('aac');
			args.push('-b:a');
			args.push('192k');
			args.push('-shortest'); // 视频结束即停，别把整首歌的音频拖长尾
		}
		else
		{
			args.push('-an');
		}

		args.push(outPath);

		try
		{
			proc = new Process(ffmpegPath, args);
			stdinOut = proc.stdin;
			isRecording = true;
			frameCount = 0;
			frameInterval = 1.0 / Math.max(1.0, fps);
			nextFrameAt = 0;
			trace('[Recorder] 开始录像 ' + w + 'x' + h + '@' + fps + 'fps 路径=' + activePath + ' 单帧缓冲='
				+ Std.string(Std.int((w * h * 4) / 1048576)) + 'MB → ' + outPath + (hasAudio ? ' (含音频)' : ' (无声)'));
			return outPath;
		}
		catch (e:Dynamic)
		{
			trace('[Recorder] 启动 ffmpeg 失败：' + Std.string(e));
			proc = null;
			stdinOut = null;
			return null;
		}
		#else
		trace('[Recorder] 当前平台不支持录像');
		return null;
		#end
	}

	/**
	 * 每帧调用。内部按 targetFPS 节流 —— 游戏跑 600+fps 时不能真的每秒抓 600 帧，
	 * 既拖慢自己也会让 ffmpeg 侧堆积。
	 * @param now 由 haxe.Timer.stamp() 取的当前秒数
	 */
	public static function update(now:Float):Void
	{
		#if (sys && !android)
		if (!isRecording || stdinOut == null) return;
		if (now < nextFrameAt) return;
		// 落后太多（卡帧）就重置基准，避免「补帧风暴」瞬间抓几十帧
		if (now - nextFrameAt > frameInterval * 4) nextFrameAt = now;
		nextFrameAt += frameInterval;
		capture();
		#end
	}

	/** 抓一帧并写入 ffmpeg stdin。 */
	static function capture():Void
	{
		#if (sys && !android)
		if (!isRecording || win == null || stdinOut == null) return;
		var t0:Float = haxe.Timer.stamp() * 1000;

		// ⚠ 必须在画面画完之后才读：Flixel 的 step() 在 ENTER_FRAME 里跑 update，
		//   绘制发生在这之后，所以此刻帧缓冲里是**上一帧**已完成的画面。
		//   恒定一帧滞后（60fps 下 16ms），对节奏游戏是能看出来的音画偏移；
		//   已在 start() 里用音频侧 -itsoffset 抵消。
		try
		{
			var payload:haxe.io.Bytes = null;

			if (useFastPath)
			{
				// 快路径：写进 start 时就分配好的同一块内存，全程零分配。
				// 任何异常（含方法不存在导致的 Null Function Pointer）都就地降级，
				// 本帧改走 window 路径重来 —— 宁可慢，也不能整段录不出东西。
				try
				{
					glCtx.readPixels(0, 0, bufW, bufH, GL.RGBA, GL.UNSIGNED_BYTE, framePtr);
					payload = frameBuf;
				}
				catch (e:Dynamic)
				{
					trace('[Recorder] 快路径抓帧失败，本帧起降级为 Window.readPixels：' + Std.string(e));
					useFastPath = false;
					activePath = 'window';
					payload = null;
				}
			}

			if (payload == null)
			{
				// 回退：lime 每次都 new 一个新缓冲（Retina 下 33MB/帧）。
				// 这是当初吃掉 3GB/s 内存的那条路，只能靠定期 GC 兜住残留。
				var img:lime.graphics.Image = win.readPixels();
				if (img == null || img.data == null)
				{
					trace('[Recorder] readPixels 返回空，跳过一帧');
					return;
				}
				payload = img.data.toBytes();
				if (frameCount > 0 && frameCount % 30 == 0) cpp.vm.Gc.run(true); // 约每 0.5s 收一次（major GC，同 PlayState:1062 用法）
			}

			stdinOut.writeBytes(payload, 0, payload.length);
			stdinOut.flush();
			frameCount++;
		}
		catch (e:Dynamic)
		{
			trace('[Recorder] 写 ffmpeg 管道失败（可能磁盘满或进程已退出）：' + Std.string(e));
			stop();
			return;
		}
		lastCaptureMs = haxe.Timer.stamp() * 1000 - t0;
		#end
	}

	/** 结束录制：关闭 stdin 让 ffmpeg 收尾，等待退出。 */
	public static function stop():Void
	{
		#if (sys && !android)
		if (!isRecording) return;
		isRecording = false;
		try
		{
			if (stdinOut != null) stdinOut.close();
		}
		catch (e:Dynamic) {}
		stdinOut = null;
		if (proc != null)
		{
			try
			{
				proc.close(); // 阻塞到 ffmpeg 写完 moov atom
			}
			catch (e:Dynamic) {}
			proc = null;
		}
		trace('[Recorder] 结束录像，共 ' + frameCount + ' 帧（路径=' + activePath + '，平均抓帧 '
			+ Std.string(Math.round(lastCaptureMs * 10) / 10) + 'ms）→ ' + outPath);
		outPath = null;
		frameInterval = 1.0 / 60.0;
		nextFrameAt = 0;
		win = null;
		frameBuf = null;
		glCtx = null;
		useFastPath = false;
		activePath = 'none';
		#end
	}
}