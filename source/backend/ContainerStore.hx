package backend;

import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * 容器仓库：目录发现、清单扫描、资源 staging。
 *
 * 目录布局（与 mods 同根，构建脚本已纳入备份/恢复，见 compile-mac.sh）：
 *
 *   <mods>/                                     ← 通常是 Meteoric.app/Contents/Resources/mods
 *     _containers/                              ← 已登记进 Mods.ignoreModFolders ⇒ 不会进模组列表
 *       psych-0.6.3/
 *         container.json                        ← 清单
 *         <目标引擎 bundle>                      ← PE 0.6.3.app / 或 Windows 的 .exe + 目录
 *         resources/                            ← staging 中转到目标引擎的 mods/data/…
 *         runtime/                              ← 引擎生成：wrapper.sh / app.pid / exit.txt / container.log
 *
 * 隔离性：本模块只读容器目录、只向容器自身与目标引擎的落点写入；Meteoric 本体的
 * mods 列表由 Mods.ignoreModFolders 显式排除 '_containers'（那里**没有**下划线前缀
 * 自动跳过规则，必须登记，否则会扫成一个名为 "_containers" 的假模组 —— 实测确认），
 * 因此容器内 mod 不会出现在本体的 Mod 列表。
 */
class ContainerStore
{
	public static inline var CONTAINERS_DIR:String = '_containers';
	public static inline var RUNTIME_DIR:String = 'runtime';
	public static inline var LOG_NAME:String = 'container.log';
	public static inline var PID_NAME:String = 'app.pid';
	public static inline var EXIT_NAME:String = 'exit.txt';
	public static inline var WRAPPER_NAME:String = 'wrapper.sh';
	/** Windows 包装器（bat 包装脚本，与 wrapper.sh 二选一）。 */
	public static inline var WRAPPER_WIN_NAME:String = 'wrapper.bat';
	/** 目标引擎前台化脚本（buildActivator 生成；宿主冻结期间由它重试激活）。 */
	public static inline var ACTIVATOR_NAME:String = 'activate.sh';
	/** Windows 前台化脚本（PowerShell）。 */
	public static inline var ACTIVATOR_PS1_NAME:String = 'activate.ps1';
	public static inline var CMD_NAME:String = 'cmd.txt';
	public static inline var PHASE_NAME:String = 'phase.txt';

	/** 环境变量覆盖（调试/便携模式用，例如把容器放在外置盘）。 */
	inline public static var ENV_ROOT:String = 'METEORIC_CONTAINER_ROOT';

	// ───────────────────────── 路径 ─────────────────────────

	/** 可执行文件所在根目录（macOS：…/Meteoric.app/Contents/Resources）。 */
	public static function appRoot():String
	{
		// 1) 环境变量覆盖
		var env:String = null;
		try
			env = Sys.getEnv(ENV_ROOT)
		catch (e:Dynamic)
			env = null;
		if (env != null && env.length > 0 && dirExists(env)) return tidy(env);

		// 2) cwd：桌面端启动 cwd = Resources（含 mods/assets），最可靠
		var cwd:String = null;
		try
			cwd = Sys.getCwd()
		catch (e:Dynamic)
			cwd = null;
		if (cwd != null && cwd.length > 0 && dirExists(cwd + 'assets')) return tidy(cwd);

		// 3) 从可执行文件逐级向上找含 assets/ 的目录
		var exe:String = null;
		try
			exe = Sys.programPath()
		catch (e:Dynamic)
			exe = null;
		if (exe != null && exe.length > 0)
		{
			var dir:String = Path.directory(exe);
			for (_ in 0...8)
			{
				if (dir == null || dir.length < 1 || dir == '/') break;
				if (dirExists(dir + '/assets')) return tidy(dir);
				dir = Path.directory(dir);
			}
			// 兜底：可执行文件目录本身
			var exeDir:String = Path.directory(exe);
			if (exeDir != null && exeDir.length > 0) return tidy(exeDir);
		}

		if (cwd != null && cwd.length > 0) return tidy(cwd);
		return '.';
	}

	/** mods 根目录（不含尾斜杠）。 */
	public static function modsRoot():String
	{
		return join(appRoot(), 'mods');
	}

	/** 容器仓库根目录：<mods>/_containers。 */
	public static function containersRoot():String
	{
		ensureDir(modsRoot());
		var root:String = join(modsRoot(), CONTAINERS_DIR);
		ensureDir(root);
		return root;
	}

	public static function join(a:String, b:String):String
	{
		if (a == null || a.length < 1) return b;
		if (b == null || b.length < 1) return a;
		if (StringTools.endsWith(a, '/')) return a + b;
		return a + '/' + b;
	}

	/** 去掉尾斜杠（保留根 "/"）。 */
	public static function tidy(p:String):String
	{
		if (p == null) return '';
		var s:String = p;
		while (s.length > 1 && StringTools.endsWith(s, '/')) s = s.substr(0, s.length - 1);
		return s;
	}

	// ───────────────────────── 扫描 ─────────────────────────

	/**
	 * 扫描容器列表。
	 *  - 目录名以 `_` / `.` 开头 ⇒ 跳过（`_containers` 自身、临时目录）；
	 *  - 含 container.json ⇒ 正常条目（清单损坏时 info.problem 非空）；
	 *  - 不含 container.json 但含 .app/.exe/可执行主程序 ⇒ 条目 + “缺少清单”提示，
	 *    方便玩家看出“放进去了但没配置”；
	 *  - 其余（看起来是普通 mod）⇒ 完全忽略，不打扰。
	 */
	public static function scan():Array<ContainerInfo>
	{
		var out:Array<ContainerInfo> = [];
		var root:String = containersRoot();
		var entries:Array<String> = null;
		try
			entries = FileSystem.readDirectory(root)
		catch (e:Dynamic)
			return out;
		if (entries == null) return out;

		entries.sort(function(a, b) return a.toLowerCase() < b.toLowerCase() ? -1 : (a.toLowerCase() > b.toLowerCase() ? 1 : 0));

		for (name in entries)
		{
			if (name == null || name.length < 1) continue;
			var c0:String = name.substr(0, 1);
			if (c0 == '_' || c0 == '.') continue;

			var dir:String = join(root, name);
			if (!dirExists(dir)) continue; // 只认目录

			var hasManifest:Bool = fileExists(join(dir, ContainerManifestParser.FILE_NAME));
			var appPath:String = null;
			if (hasManifest)
			{
				var m:ContainerManifest = ContainerManifestParser.load(dir);
				appPath = resolveApp(dir, m.raw);
			}
			else
				appPath = autoDetectApp(dir);

			if (!hasManifest && appPath == null) continue; // 普通目录，不是容器
			out.push(parse(dir, name, hasManifest, appPath));
		}
		return out;
	}

	/** 组装单个容器信息（含自检结果）。 */
	public static function parse(dir:String, folderName:String, hasManifest:Bool, ?appPath:String):ContainerInfo
	{
		var info:ContainerInfo = {
			folder: folderName,
			path: dir,
			displayName: folderName,
			version: '',
			engine: '',
			author: '',
			description: '',
			appPath: appPath,
			manifest: null,
			problem: null
		};

		if (!hasManifest)
		{
			info.problem = '缺少 ' + ContainerManifestParser.FILE_NAME + '：无法确定目标引擎与启动方式';
			return info;
		}

		var m:ContainerManifest = ContainerManifestParser.load(dir);
		info.manifest = m;
		if (m.problem != null)
		{
			info.problem = m.problem;
			return info;
		}

		var data:ContainerManifestData = m.raw;
		var dn:String = ContainerManifestParser.str(data, 'displayName', folderName);
		info.displayName = dn;
		info.version = ContainerManifestParser.str(data, 'version', '');
		info.engine = ContainerManifestParser.str(data, 'engine', '');
		info.author = ContainerManifestParser.str(data, 'author', '');
		info.description = ContainerManifestParser.str(data, 'description', '');
		info.appPath = resolveApp(dir, data);

		if (info.appPath == null)
			info.problem = '找不到目标引擎主程序（container.json 的 app 字段或 bundle 内的可执行文件）';

		return info;
	}

	// ───────────────────── 主程序定位 ─────────────────────

	/** 清单优先：app 字段 → 自动探测。 */
	public static function resolveApp(containerDir:String, data:ContainerManifestData):String
	{
		var app:String = ContainerManifestParser.str(data, 'app', null);
		if (app != null && app.length > 0)
		{
			var p:String = app;
			if (!isAbsolute(p)) p = join(containerDir, app);
			p = tidy(p);
			if (fileExists(p) || dirExists(p))
			{
				// .app 目录 ⇒ 取里面的可执行文件（避免 LaunchServices 高 DPI 降级）
				if (dirExists(p) && StringTools.endsWith(p.toLowerCase(), '.app')) return bundleExecutable(p);
				if (dirExists(p))
				{
					var inner:String = autoDetectApp(p);
					if (inner != null) return inner;
				}
				return p;
			}
			return null;
		}
		return autoDetectApp(containerDir);
	}

	/** 在目录内自动探测可执行主程序：*.app → 目录内可执行文件 → *.exe。 */
	/**
	 * 自动探测目标引擎主程序。
	 *
	 * 平台顺序**有意不同**：
	 *  - Windows：先找 `*.exe`。NTFS 没有 POSIX 执行位，下面第 2 步的 `isExecutable()`
	 *    在 Windows 上必然失败；而且同一个容器里可能同时躺着 mac 的 `.app` 与 win 的 `.exe`
	 *    （玩家把两个平台的发行包放一起），此时在 Windows 上必须选 `.exe`。
	 *  - macOS：先找 `.app` 包，再退回执行位、最后 `.exe`（兼容跨平台搬运的目录）。
	 */
	public static function autoDetectApp(dir:String):String
	{
		var entries:Array<String> = null;
		try
			entries = FileSystem.readDirectory(dir)
		catch (e:Dynamic)
			return null;
		if (entries == null) return null;

		#if windows
		// 1) Windows 可执行文件优先
		for (name in entries)
			if (name != null && StringTools.endsWith(name.toLowerCase(), '.exe') && !FileSystem.isDirectory(join(dir, name)))
				return join(dir, name);
		#end

		// 2) macOS bundle
		for (name in entries)
			if (name != null && StringTools.endsWith(name.toLowerCase(), '.app') && dirExists(join(dir, name)))
				return bundleExecutable(join(dir, name));

		// 3) 目录内自身的可执行文件（POSIX 执行位；Windows 上无意义，靠上面第 1 步）
		for (name in entries)
		{
			if (name == null) continue;
			var p:String = join(dir, name);
			if (FileSystem.isDirectory(p)) continue;
			if (isExecutable(p)) return p;
		}

		// 4) 兜底：.exe（macOS 上跑 Windows 容器的场景不存在，这里只是防御性保留）
		for (name in entries)
			if (name != null && StringTools.endsWith(name.toLowerCase(), '.exe'))
				return join(dir, name);

		return null;
	}

	/** bundle 内的主程序：Contents/MacOS/ 下第一个可执行文件。 */
	public static function bundleExecutable(appBundle:String):String
	{
		var macos:String = join(appBundle, 'Contents/MacOS');
		var entries:Array<String> = null;
		try
			entries = FileSystem.readDirectory(macos)
		catch (e:Dynamic)
			return null;
		if (entries == null) return null;

		var info:String = join(appBundle, 'Contents/Info.plist');
		if (fileExists(info))
		{
			var exeName:String = plistValue(info, 'CFBundleExecutable');
			if (exeName != null && entries.contains(exeName))
			{
				var p:String = join(macos, exeName);
				if (fileExists(p)) return p;
			}
		}
		for (name in entries)
		{
			var p:String = join(macos, name);
			if (!FileSystem.isDirectory(p) && isExecutable(p)) return p;
		}
		return null;
	}

	/** 从 Info.plist 里抠出 <key>k</key><string>v</string>（不引 XML 依赖）。 */
	static function plistValue(plistPath:String, key:String):String
	{
		var text:String = null;
		try
			text = File.getContent(plistPath)
		catch (e:Dynamic)
			return null;
		if (text == null) return null;
		var token:String = '<key>' + key + '</key>';
		var i:Int = text.indexOf(token);
		if (i < 0) return null;
		var seg:String = text.substr(i + token.length);
		var s:Int = seg.indexOf('<string>');
		if (s < 0) return null;
		var e:Int = seg.indexOf('</string>', s);
		if (e < 0) return null;
		return StringTools.trim(seg.substring(s + 8, e));
	}

	// ─────────────────── 资源 staging ───────────────────

	/**
	 * 把容器内 `resources/` 的内容搬到目标引擎的资源根目录（bundle/Contents/Resources
	 * 或裸可执行文件同目录）。这是**唯一**会写目标引擎目录的动作，且只增不改：
	 *  - resources/<name>/        ⇒ <target>/<name>/        （整目录覆盖）
	 *  - resources/<name>.zip     ⇒ 搬文件到 <target>/<name>.zip（目标自己的解包逻辑处理）
	 *  - manifest.resources[]     ⇒ {dir, to, file} 自定义规则，优先于默认规则
	 *
	 * @return 搬运条目数；失败条目写入 manifest.problem 供界面显示。
	 */
	public static function stageResources(info:ContainerInfo):Int
	{
		if (info == null || info.path == null) return 0;
		var src:String = join(info.path, 'resources');
		if (!dirExists(src)) return 0;

		var dest:String = resourcesDest(info);
		if (dest == null)
		{
			info.problem = '无法定位目标引擎资源目录（app 字段指向的路径无效）';
			return 0;
		}
		ensureDir(dest);

		var moved:Int = 0;
		var data:ContainerManifestData = info.manifest != null ? info.manifest.raw : null;
		var rules:Array<Dynamic> = null;
		if (data != null)
		{
			try
			{
				var r:Dynamic = Reflect.field(data, 'resources');
				if (r != null && Std.isOfType(r, Array)) rules = cast r;
			}
			catch (e:Dynamic)
				rules = null;
		}

		// 显式规则
		if (rules != null && rules.length > 0)
		{
			for (rule in rules)
			{
				if (rule == null) continue;
				var rel:String = null;
				var to:String = null;
				var single:Bool = false;
				try
				{
					var v:Dynamic = Reflect.field(rule, 'dir');
					if (v != null) rel = Std.string(v);
					var t:Dynamic = Reflect.field(rule, 'to');
					if (t != null) to = Std.string(t);
					var f:Dynamic = Reflect.field(rule, 'file');
					if (f != null) single = Std.string(f).toLowerCase() == 'true';
				}
				catch (e:Dynamic)
					continue;
				if (rel == null || rel.length < 1) continue;
				if (to == null || to.length < 1) to = rel;
				var from:String = join(src, rel);
				if (!exists(from)) continue;
				var target:String = join(dest, to);
				if (single || isFile(from))
				{
					ensureDir(Path.directory(target));
					if (copyFile(from, target)) moved++;
				}
				else if (copyTree(from, target))
					moved++;
			}
			return moved;
		}

		// 默认规则：resources/ 下每个条目按同名搬到资源根
		var entries:Array<String> = null;
		try
			entries = FileSystem.readDirectory(src)
		catch (e:Dynamic)
			return 0;
		if (entries == null) return 0;

		for (name in entries)
		{
			if (name == null || name.length < 1) continue;
			if (name.substr(0, 1) == '.') continue;
			var from:String = join(src, name);
			var target:String = join(dest, name);
			try
			{
				if (FileSystem.isDirectory(from))
				{
					if (copyTree(from, target)) moved++;
				}
				else
				{
					ensureDir(dest);
					if (copyFile(from, target)) moved++;
				}
			}
			catch (e:Dynamic) {}
		}
		return moved;
	}

	/** 目标引擎的资源根：bundle ⇒ Contents/Resources；裸可执行 ⇒ 同目录。 */
	public static function resourcesDest(info:ContainerInfo):String
	{
		if (info == null || info.appPath == null) return null;
		var app:String = info.appPath;
		var marker:String = '/Contents/MacOS/';
		var i:Int = app.indexOf(marker);
		if (i > 0) return app.substring(0, i) + '/Contents/Resources';
		var dir:String = Path.directory(app);
		if (dir == null || dir.length < 1) return null;
		return dir;
	}

	// ─────────────────── 文件系统小工具 ───────────────────

	public static function exists(p:String):Bool
	{
		try
			return FileSystem.exists(p)
		catch (e:Dynamic)
			return false;
	}

	public static function fileExists(p:String):Bool
	{
		try
			return FileSystem.exists(p) && !FileSystem.isDirectory(p)
		catch (e:Dynamic)
			return false;
	}

	public static function dirExists(p:String):Bool
	{
		try
			return FileSystem.exists(p) && FileSystem.isDirectory(p)
		catch (e:Dynamic)
			return false;
	}

	public static function isFile(p:String):Bool
	{
		return fileExists(p);
	}

	public static function ensureDir(p:String):Void
	{
		if (p == null || p.length < 1) return;
		try
		{
			if (!FileSystem.exists(p)) FileSystem.createDirectory(p);
		}
		catch (e:Dynamic) {}
	}

	public static function isAbsolute(p:String):Bool
	{
		if (p == null || p.length < 1) return false;
		if (p.substr(0, 1) == '/') return true;
		if (p.length > 2 && p.substr(1, 1) == ':') return true; // Windows 盘符
		return false;
	}

	/** POSIX 执行位判断（Windows 上恒 false，由 .exe 分支兜底）。 */
	public static function isExecutable(p:String):Bool
	{
		#if mac
		if (!sys.FileSystem.exists(p) || sys.FileSystem.isDirectory(p)) return false;
		var mode:Int = sys.FileSystem.stat(p).mode;
		return (mode & 0x49) != 0; // 0o111：owner/group/other 任一可执行
		#else
		return false;
		#end
	}

	public static function copyFile(from:String, to:String):Bool
	{
		try
		{
			ensureDir(Path.directory(to));
			File.copy(from, to);
			return true;
		}
		catch (e:Dynamic)
			return false;
	}

	/** 递归复制（目标存在则先整目录删除，避免 mods/mods 嵌套这类老问题）。 */
	public static function copyTree(from:String, to:String):Bool
	{
		if (!dirExists(from)) return false;
		try
		{
			if (dirExists(to)) deleteTree(to);
			ensureDir(to);
			for (name in FileSystem.readDirectory(from))
			{
				if (name == null || name.length < 1) continue;
				var src:String = join(from, name);
				var dst:String = join(to, name);
				if (FileSystem.isDirectory(src))
					copyTree(src, dst);
				else
					copyFile(src, dst);
			}
			return true;
		}
		catch (e:Dynamic)
			return false;
	}

	public static function deleteTree(p:String):Bool
	{
		if (!dirExists(p)) return false;
		try
		{
			for (name in FileSystem.readDirectory(p))
			{
				var child:String = join(p, name);
				if (FileSystem.isDirectory(child))
					deleteTree(child);
				else
					FileSystem.deleteFile(child);
			}
			FileSystem.deleteDirectory(p);
			return true;
		}
		catch (e:Dynamic)
			return false;
	}

	/** 读取一小段文本（PID/退出码/命令文件通用）；不存在或失败返回 null。 */
	public static function readText(p:String):String
	{
		try
		{
			if (!FileSystem.exists(p)) return null;
			var s:String = File.getContent(p);
			return s == null ? null : StringTools.trim(s);
		}
		catch (e:Dynamic)
			return null;
	}

	public static function writeText(p:String, content:String):Bool
	{
		try
		{
			ensureDir(Path.directory(p));
			File.saveContent(p, content);
			return true;
		}
		catch (e:Dynamic)
			return false;
	}

	/** 运行期文件路径（wrapper.sh / app.pid / exit.txt / container.log）。 */
	public static function runtimeFile(info:ContainerInfo, name:String):String
	{
		return join(join(info.path, RUNTIME_DIR), name);
	}

	public static function ensureRuntimeDir(info:ContainerInfo):String
	{
		var dir:String = join(info.path, RUNTIME_DIR);
		ensureDir(dir);
		return dir;
	}
}
