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

	public static function root():String
	{
		if (_useFallbackRoot) return fallbackRoot();
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
			try
			{
				var colon = id.indexOf(':');
				var writePath = colon >= 0 ? id.substring(colon + 1) : id;
				var dst = root() + '/' + writePath;
				if (FileSystem.exists(dst))
					_copySkipped++;
				else
				{
					ensureParentDir(dst);
					var bytes = Assets.getBytes(id);
					if (bytes == null || bytes.length == 0)
						_copySkipped++; // 空占位文件（data-goes-here.txt 等）不落盘，避免原生崩溃
					else
						File.saveBytes(dst, bytes);
				}
			}
			catch (e:Dynamic)
			{
				// 内嵌资源（字体/音乐/部分图片）无法用 getBytes 提取，跳过不中断；
				// 它们直接由游戏从二进制读取，不需要外部副本。
				var msg = Std.string(e);
				if (msg.indexOf('Invalid Cast') >= 0 || msg.indexOf('null') >= 0 || msg.indexOf('There is no') >= 0)
				{
					_copySkipped++;
					_copyDoneCount++;
					n++;
					continue;
				}
				_copyError = msg;
				_copyFinished = true;
				return;
			}
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
	public static function requestLegacyPermissions():Void
	{
		try
		{
			var req = JNI.createStaticMethod('org/libsdl/app/SDLActivity', 'requestPermission', '(Ljava/lang/String;I)V', false);
			req('android.permission.WRITE_EXTERNAL_STORAGE', 1001);
			req('android.permission.READ_EXTERNAL_STORAGE', 1002);
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
