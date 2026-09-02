package backend;

#if android
import lime.system.JNI;
import sys.FileSystem;
import sys.io.File;
import openfl.utils.Assets;

// 安卓外部存储：优先 /sdcard/.meteoric（隐藏目录，避免图片进相册），
// 无“所有文件访问”权限时自动回退到应用专属外部目录
class AndroidStorage
{
	static var _root:String = null;
	static var _fallbackRoot:String = null;
	static var _useFallbackRoot:Bool = false;
	// 真实写探测缓存：_probeResult = null 表示成功，否则为错误信息；
	// 等待授权期间每帧都会调 hasStoragePermission()，用短 TTL 避免反复写盘
	static var _probeResult:String = null;
	static var _probeAt:Float = -1;
	static final PROBE_TTL:Float = 1.0; // 秒

	public static function root():String
	{
		if (_useFallbackRoot) return fallbackRoot();
		return publicRoot();
	}

	/** 公共根目录 /sdcard/.meteoric（与当前是否处于回退模式无关）：
	 *  崩溃日志必须落在玩家公认的 .meteoric/crash，不能因回退模式而跑到应用专属目录 */
	public static function publicRoot():String
	{
		if (_root == null)
		{
			try
			{
				var getExternalStorageDirectory = JNI.createStaticMethod('android/os/Environment', 'getExternalStorageDirectory', '()Ljava/io/File;', false);
				var file = getExternalStorageDirectory();
				var getPath = JNI.createMemberMethod('java/io/File', 'getPath', '()Ljava/lang/String;', false);
				_root = Std.string(getPath(file));
			}
			catch (e:Dynamic)
			{
				_root = '/sdcard';
			}
			_root = StringTools.endsWith(_root, '/') ? _root + '.meteoric' : _root + '/.meteoric';
		}
		return _root;
	}

	static function fallbackRoot():String
	{
		if (_fallbackRoot == null)
		{
			// 优先 extension-androidtools 的 Context.getExternalFilesDir（兼容性好，无需自写 JNI）
			try
			{
				var ext = extension.androidtools.content.Context.getExternalFilesDir(null);
				if (ext != null && ext != 'null' && ext.length > 0)
					_fallbackRoot = Std.string(ext);
			}
			catch (e:Dynamic) {}
			if (_fallbackRoot == null || _fallbackRoot == 'null' || _fallbackRoot == '')
			{
				try
				{
					var getSingleton = JNI.createStaticField('org/libsdl/app/SDLActivity', 'mSingleton', 'Lorg/libsdl/app/SDLActivity;');
					var act = getSingleton.get();
					if (act != null)
					{
						var getExternalFilesDir = JNI.createMemberMethod('android/app/Activity', 'getExternalFilesDir', '(Ljava/lang/String;)Ljava/io/File;', false);
						var file = getExternalFilesDir(act, null);
						if (file != null)
						{
							var getPath = JNI.createMemberMethod('java/io/File', 'getPath', '()Ljava/lang/String;', false);
							_fallbackRoot = Std.string(getPath(file));
						}
					}
				}
				catch (e:Dynamic) {}
			}
			if (_fallbackRoot == null || _fallbackRoot == 'null' || _fallbackRoot == '')
				_fallbackRoot = '/sdcard/Android/data/' + packageName() + '/files';
			_fallbackRoot = StringTools.endsWith(_fallbackRoot, '/') ? _fallbackRoot + '.meteoric' : _fallbackRoot + '/.meteoric';
		}
		return _fallbackRoot;
	}

	// 创建目录结构；返回 null 表示成功，否则返回错误信息（通常是缺少存储权限）
	public static function ensureDirs():String
	{
		migrateOldFolder();
		var err = tryEnsureDirs(root());
		if (err == null) return null;

		// Android 11+ 没有“所有文件访问”权限时，根目录创建会失败；
		// 自动切换到应用专属外部目录（无需特殊权限）。
		if (!_useFallbackRoot)
		{
			_useFallbackRoot = true;
			err = tryEnsureDirs(root());
			if (err == null) return null;
		}
		return err;
	}

	static function migrateOldFolder():Void
	{
		if (_useFallbackRoot) return;
		var newRoot:String = root();
		var suffix:String = '/.meteoric';
		if (!newRoot.endsWith(suffix)) return;
		var oldRoot:String = newRoot.substr(0, newRoot.length - suffix.length) + '/meteoric';
		if (FileSystem.exists(oldRoot) && !FileSystem.exists(newRoot))
		{
			try FileSystem.rename(oldRoot, newRoot) catch (e:Dynamic) {}
		}
	}

	static function tryEnsureDirs(base:String):String
	{
		try
		{
			var dirs:Array<String> = ['', 'assets', 'mods'];
			for (d in dirs)
			{
				var p = base + (d == '' ? '' : '/' + d);
				if (!FileSystem.exists(p))
					FileSystem.createDirectory(p);
			}
			// 隐藏目录 + .nomedia，防止 Android 相册扫描到 mod 里的图片
			var nomedia:String = base + '/.nomedia';
			if (!FileSystem.exists(nomedia))
				File.saveContent(nomedia, '');
			return null;
		}
		catch (e:Dynamic)
		{
			return Std.string(e);
		}
	}

	// ---------- 资源复制：把 APK 内嵌 preload 资源复制到外部存储（增量，已存在跳过） ----------
	// 注意：openfl Assets 读取不能在子线程调用（安卓上会因 JNIEnv 未绑定而崩溃），
	// 因此复制在主线程逐帧分批进行，每帧最多复制 6 个文件。
	static var _copyList:Array<String> = null;
	static var _copyIndex:Int = 0;
	static var _copyTotal:Int = 0;
	static var _copyDoneCount:Int = 0;
	static var _copyFinished:Bool = false;
	static var _copyError:String = null;
	static var _copySkipped:Int = 0;

	public static function startCopyAssets():Void
	{
		if (_copyList != null) return;
		_copyList = [];
		try
		{
			// 按库遍历：shared/week_assets/songs 等库的资源必须带"库名:"前缀才能读取
			var libNames:Array<String> = ['default', 'shared', 'week_assets', 'songs', 'videos'];
			for (libName in libNames)
			{
				if (!lime.utils.Assets.hasLibrary(libName)) continue;
				var lib = lime.utils.Assets.getLibrary(libName);
				for (id in lib.list(null))
				{
					if (id.startsWith('assets/') || id.startsWith('mods/'))
					{
						// 内嵌资源（带 className，字体/音乐/部分图片）直接由游戏二进制读取，
						// 不能 getBytes 提取（部分类型会原生崩溃），跳过
						@:privateAccess
						if (lib.classTypes.exists(id)) continue;
						_copyList.push(libName == 'default' ? id : libName + ':' + id);
					}
				}
			}
			_copyTotal = _copyList.length;
		}
		catch (e:Dynamic)
		{
			_copyError = Std.string(e);
			_copyFinished = true;
		}
	}

	// 每帧调用一次：复制一批文件
	public static function copyAssetsStep():Void
	{
		if (_copyFinished || _copyList == null) return;
		var n:Int = 0;
		while (n < 6 && _copyIndex < _copyList.length)
		{
			var id = _copyList[_copyIndex++];
			var skipThis:Bool = false;
			try
			{
				var colon = id.indexOf(':');
				var writePath = colon >= 0 ? id.substring(colon + 1) : id;
				var dst = root() + '/' + writePath;
				if (FileSystem.exists(dst))
					skipThis = true;
				else
				{
					ensureParentDir(dst);
					// 内嵌资源（字体/音乐/部分图片，classType）无法用 getBytes 提取，
					// 它们直接由游戏从二进制读取，不需要外部副本——只有这类“提取失败”才允许跳过。
					var bytes:Dynamic = null;
					try
					{
						bytes = Assets.getBytes(id);
					}
					catch (e:Dynamic)
					{
						var msg = Std.string(e);
						if (msg.indexOf('Invalid Cast') >= 0 || msg.indexOf('null') >= 0 || msg.indexOf('There is no') >= 0)
							skipThis = true;
						else
						{
							_copyError = msg;
							_copyFinished = true;
							return;
						}
					}
					if (!skipThis)
					{
						if (bytes == null || bytes.length == 0)
							skipThis = true; // 空占位文件（data-goes-here.txt 等）不落盘，避免原生崩溃
						else
							File.saveBytes(dst, bytes); // 写盘失败 = 真实错误，绝不静默吞掉
					}
				}
			}
			catch (e:Dynamic)
			{
				// 到这里只剩写盘/建目录等真实 IO 错误：记录并停止，不静默跳过
				_copyError = Std.string(e);
				_copyFinished = true;
				return;
			}
			if (skipThis) _copySkipped++;
			_copyDoneCount++;
			n++;
		}
		if (_copyIndex >= _copyList.length)
			_copyFinished = true;
	}

	static function ensureParentDir(path:String):Void
	{
		var dir = haxe.io.Path.directory(path);
		if (dir == null || dir == '' || dir == '.') return;
		if (!FileSystem.exists(dir))
		{
			ensureParentDir(dir);
			try FileSystem.createDirectory(dir) catch (e:Dynamic) {}
		}
	}

	public static function copyPercent():Float
	{
		if (_copyTotal <= 0) return 0;
		return _copyDoneCount / _copyTotal;
	}

	public static function copyFinished():Bool return _copyFinished;
	public static function copyError():String return _copyError;
	public static function copyDoneCount():Int return _copyDoneCount;
	public static function copyTotal():Int return _copyTotal;
	public static function copySkipped():Int return _copySkipped;

	// ---------- 权限 ----------
	// Android 10：运行时请求旧存储权限（配合 manifest 的 requestLegacyExternalStorage）
	// 注意：只请求 WRITE（Android 上 WRITE 已隐含 READ）；连发两个会被系统拒绝（"only one set of permissions at a time"）
	public static function requestLegacyPermissions():Void
	{
		try
		{
			var req = JNI.createStaticMethod('org/libsdl/app/SDLActivity', 'requestPermission', '(Ljava/lang/String;I)V', false);
			req('android.permission.WRITE_EXTERNAL_STORAGE', 1001);
		}
		catch (e:Dynamic) {}
	}

	// Android 11+：跳转到"所有文件访问"设置页（GameActivity.openStorageSettings，见 lime 模板补丁）
	public static function openStorageSettings():Void
	{
		try
		{
			var open = JNI.createStaticMethod('org/haxe/lime/GameActivity', 'openStorageSettings', '(Ljava/lang/String;)V', false, true);
			if (open != null) open(packageName());
		}
		catch (e:Dynamic) {}
	}

	// ---------- 权限状态判定（Main 的启动流程按此决策，不再静默回退）----------

	/** Android 11+（API 30+）？决定走"所有文件访问"还是旧 WRITE 权限 */
	public static function isAndroid11Plus():Bool
	{
		try
		{
			return extension.androidtools.os.Build.VERSION.SDK_INT >= 30;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	/** 真实写探测：在公共根目录的**父目录**（/storage/emulated/0）写入并删除一个探针文件。
	 *  isExternalStorageManager() 在部分定制 ROM（MIUI/HyperOS、ColorOS 等）上存在
	 *  “已授权仍返回 false / 授权页不可靠”的问题；能否真的写进公共根目录才是唯一可靠判定。
	 *  注意：只探父目录、不创建 .meteoric 本身——若探测先建出空目录，
	 *  migrateFromFallback 会因“目标已存在”跳过，回退数据永远搬不回根目录。
	 *  返回 null = 公共根目录真实可写，否则返回错误信息。 */
	public static function probePublicRoot():String
	{
		try
		{
			var parent:String = haxe.io.Path.directory(publicRoot());
			if (parent == null || parent.length == 0) parent = '/sdcard';
			var probe:String = parent + '/.storage_probe_meteoric';
			File.saveContent(probe, '1');
			try FileSystem.deleteFile(probe) catch (e:Dynamic) {}
			return null;
		}
		catch (e:Dynamic)
		{
			return Std.string(e);
		}
	}

	static function probePublicRootCached():String
	{
		var now:Float = haxe.Timer.stamp();
		if (_probeAt < 0 || now - _probeAt > PROBE_TTL)
		{
			_probeResult = probePublicRoot();
			_probeAt = now;
		}
		return _probeResult;
	}

	/** 已获得在根目录 /sdcard/.meteoric 的真实读写能力？
	 *  Android 10 的 WRITE 授权与 Android 11+ 的“所有文件访问”最终都体现在
	 *  “能否真的写入公共根目录”上，因此统一用写探测判定（API 判定仅供参考）。 */
	public static function hasStoragePermission():Bool
	{
		try
		{
			return probePublicRootCached() == null;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	static function hasWritePermission():Bool
	{
		try
		{
			var getSingleton = JNI.createStaticField('org/libsdl/app/SDLActivity', 'mSingleton', 'Lorg/libsdl/app/SDLActivity;');
			var act = getSingleton.get();
			if (act == null) return false;
			var check = JNI.createMemberMethod('android/app/Activity', 'checkSelfPermission', '(Ljava/lang/String;)I', false);
			var granted:Dynamic = check(act, 'android.permission.WRITE_EXTERNAL_STORAGE');
			return granted != null && Std.int(granted) == 0;
		}
		catch (e:Dynamic) { return false; }
	}

	/** 只尝试当前 root()（公共根目录或回退目录）的目录结构，失败返回错误，绝不静默切换（决策权在 Main） */
	public static function tryEnsureRootDirs():String
	{
		return tryEnsureDirs(root());
	}

	/** 是否处于回退模式（应用专属目录） */
	public static function usingFallback():Bool
	{
		return _useFallbackRoot;
	}

	/** 切到应用专属回退目录（仅在明确失败/用户拒绝时，由 Main 决策调用） */
	public static function enableFallback():Void
	{
		_useFallbackRoot = true;
	}

	/** 关闭回退模式（授权成功时调用）：root() 恢复指向公共根目录 /sdcard/.meteoric */
	public static function enableFallbackOff():Void
	{
		_useFallbackRoot = false;
	}

	/** 把回退目录整体迁移到公共根目录（同卷 rename，秒级；mods/assets/进度全部带走）。
	 *  仅当公共目录尚不存在、回退目录存在时执行；返回是否迁移成功 */
	public static function migrateFromFallback():Bool
	{
		try
		{
			if (_useFallbackRoot) return false;
			var pub:String = root();
			var fb:String = fallbackRoot();
			if (pub == fb) return false;
			if (FileSystem.exists(pub) || !FileSystem.exists(fb)) return false;
			var parent:String = haxe.io.Path.directory(pub);
			if (parent != null && parent.length > 0 && !FileSystem.exists(parent))
				FileSystem.createDirectory(parent);
			FileSystem.rename(fb, pub);
			// 迁移成功后回退模式解锁：后续 root() 稳定指向公共目录
			_fallbackRoot = pub;
			return true;
		}
		catch (e:Dynamic) { return false; }
	}

	static function packageName():String
	{
		try
		{
			var getSingleton = JNI.createStaticField('org/libsdl/app/SDLActivity', 'mSingleton', 'Lorg/libsdl/app/SDLActivity;');
			var act = getSingleton.get();
			if (act != null)
			{
				var getPackageName = JNI.createMemberMethod('android/app/Activity', 'getPackageName', '()Ljava/lang/String;', false);
				var name = getPackageName(act);
				if (name != null) return Std.string(name);
			}
		}
		catch (e:Dynamic) {}
		return 'com.bonusxk.meteoric';
	}
}
#end
