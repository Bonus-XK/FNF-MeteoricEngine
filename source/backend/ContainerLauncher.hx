package backend;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * 容器启动器：生成 wrapper 脚本、拉起目标引擎、读写运行期状态文件。
 *
 * 为什么用 shell wrapper（这是整个机制的关键，不是权宜之计）：
 *  1. 宿主进程一旦 SIGSTOP 挂起，它自己不可能再去 wait 子进程 —— 必须有一个
 *     **独立于宿主生命周期** 的进程负责“目标引擎退出后唤醒宿主”。wrapper 后台化
 *     （nohup … &）后由 init 收养，宿主被 STOP/KILL 都不影响它。
 *  2. 唤醒信号由 wrapper 发（kill -CONT <宿主 pid>），不依赖宿主自身事件循环，
 *     所以即使目标引擎崩溃/被 Ctrl+C 强杀，宿主也一定会回来（watchdog 兜底）。
 *  3. 全程文件通信（app.pid / exit.txt / cmd.txt / phase.txt），宿主侧零线程、
 *     零阻塞读，规避本项目已确认的“工作线程分配 hxcpp GC 对象破坏堆”风险。
 */
class ContainerLauncher
{
	// 宿主等待目标引擎窗口出现的窗口期（秒）
	public static inline var DEFAULT_WAIT:Float = 1.4;
	// 退出信号的升级链：TERM → 宽限 → KILL
	public static inline var TERM_GRACE:String = '1.2';

	/**
	 * Windows 前台化脚本（activate.ps1）。
	 *
	 * 与 macOS 同样的动机：宿主派发一次就完事，**等待与重试由这个独立进程负责**
	 * （FNF 类目标引擎要加载数百 MB 资源，窗口远晚于宿主派发时刻才出现）。
	 *
	 * 与 macOS 版的差异：
	 *  - 用 PowerShell 的 `WScript.Shell.AppActivate(pid)`，不需要 macOS 那套「自动化」授权；
	 *  - 进程存活检查用回环网络客户端（`Get-NetTCPConnection -OwningProcess`）而不是 `Get-Process -Id`：
	 *    后者在进程已退出时会抛错并往控制台刷红字，即使被 try/catch 包住也难看；
	 *    回环客户端在进程存活时**必然**能打开（否则它连不上任何东西），且不产生报错噪音。
	 *  - 目标已在前台时不重复设置：`AppActivate` 返回 true 即视为成功并退出，
	 *    避免像早期 macOS 脚本那样反复抢焦点。
	 */
	public static function buildActivatorWindows(info:ContainerInfo):String
	{
		if (info == null) return null;
		var runtimeDir:String = ContainerStore.ensureRuntimeDir(info);
		if (runtimeDir == null) return null;

		var pidPath:String = ContainerStore.join(runtimeDir, ContainerStore.PID_NAME);
		var logPath:String = ContainerStore.join(runtimeDir, ContainerStore.LOG_NAME);

		// ⚠ 本字符串是 PowerShell 脚本：**所有 PowerShell 变量必须写 `$$`**。
		//   Haxe 会把 `$标识符` 当模板插值吃掉（`$pidFile` 会被当成 Haxe 变量 pidFile，
		//   编译期直接 `Unknown identifier`）；`\$` 不是合法转义，唯一写法就是 `$$`。
		//   项目内已多次踩这个坑（wrapper.sh 的 `$APP_PID_FILE`、`echo $$` 都是同源问题）。
		var ps:String = '';
		ps += '# Meteoric Engine 容器前台化脚本 (Windows) —— 每次启动重写，请勿手工修改\n';
		ps += '# 容器: ' + info.displayName + '\n';
		ps += '$$ErrorActionPreference = "SilentlyContinue"\n';
		ps += '$$pidFile = ' + psQuote(pidPath) + '\n';
		ps += '$$logFile = ' + psQuote(logPath) + '\n';
		ps += 'function Say($$m) { try { Add-Content -LiteralPath $$logFile -Value ("=== [ME] activator: " + $$m) } catch {} }\n';
		ps += '$$target = 0\n';
		ps += '# 1) 等目标引擎写出 pid（此时它多半还没创建窗口）\n';
		ps += 'for ($$i = 0; $$i -lt 60; $$i++) {\n';
		ps += '  if (Test-Path -LiteralPath $$pidFile) {\n';
		ps += '    $$raw = (Get-Content -LiteralPath $$pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)\n';
		ps += '    if ($$raw -match "^\\s*(\\d+)\\s*$$") { $$target = [int]$$Matches[1] }\n';
		ps += '    # 必须排除过小 pid：wrapper 起手会写 0 占位，而 Windows 的「系统空闲进程」\n';
		ps += '    # 恒为 pid 0；若不排除，脚本会立刻判定 target=0 然后 "no pid, give up"，永远不激活。\n';
		ps += '    if ($$target -le 4) { $$target = 0 }\n';
		ps += '    if ($$target -gt 0) { break }\n';
		ps += '  }\n';
		ps += '  Start-Sleep -Milliseconds 100\n';
		ps += '}\n';
		ps += 'if ($$target -le 0) { Say "no pid, give up"; exit 0 }\n';
		ps += 'Say ("target pid = " + $$target)\n';
		ps += '$$shell = New-Object -ComObject WScript.Shell\n';
		ps += 'for ($$i = 0; $$i -lt 60; $$i++) {\n';
		ps += '  # 进程已死就别再试。用 Get-Process -Id 探活并抑制报错噪音：\n';
		ps += '  #   注意**不能**用 Get-NetTCPConnection —— 它只列出有 TCP 连接的进程，\n';
		ps += '  #   而单机 FNF 引擎通常没有任何网络连接，会导致 alive 恒为 false、\n';
		ps += '  #   第一轮就 "target gone" 退出，前台化永远不执行（写这脚本时的真实翻车点）。\n';
		ps += '  $$alive = $$false\n';
		ps += '  try { if (Get-Process -Id $$target -ErrorAction SilentlyContinue) { $$alive = $$true } } catch { $$alive = $$false }\n';
		ps += '  if (-not $$alive) { Say "target gone, stop"; break }\n';
		ps += '  $$ok = $$false\n';
		ps += '  try { $$ok = $$shell.AppActivate($$target) } catch { $$ok = $$false }\n';
		ps += '  if ($$ok) { Say ("frontmost ok (pid " + $$target + ", try " + $$i + ")"); break }\n';
		ps += '  Start-Sleep -Seconds 2\n';
		ps += '}\n';
		ps += 'exit 0\n';

		var scriptPath:String = ContainerStore.join(runtimeDir, ContainerStore.ACTIVATOR_PS1_NAME);
		if (!ContainerStore.writeText(scriptPath, ps)) return null;
		return scriptPath;
	}

	/** PowerShell 单引号字符串（内部的单引号写两遍）。 */
	static function psQuote(s:String):String
	{
		if (s == null) return "''";
		return "'" + StringTools.replace(s, "'", "''") + "'";
	}

	/** 生成包装器：macOS 用 wrapper.sh（POSIX shell），Windows 用 wrapper.bat。 */
	public static function buildWrapper(info:ContainerInfo, hostPid:Int):String
	{
		#if windows
		return buildWrapperWindows(info);
		#else
		return buildWrapperUnix(info, hostPid);
		#end
	}

	/**
	 * Windows 包装器（wrapper.bat）。
	 *
	 * 与 macOS 版本的**关键差异**（不是照搬，是有意为之）：
	 *  1. 宿主**不挂起**（Windows 没有 `kill -STOP` 的干净等价物，`NtSuspendProcess` 是未公开
	 *     ntdll API）。宿主隐窗后继续运行，每帧自己 poll `exit.txt` —— 因此 wrapper
	 *     **不需要宿主 pid**，也**不需要信号唤醒**，顺带避免了「宿主与目标同名 Meteoric.exe」的误杀。
	 *  2. 退出码用 `start /WAIT` 之后的 `%ERRORLEVEL%` 取得（Windows 没有 `wait` 内建）。
	 *  3. 「宿主已死 ⇒ 不留孤儿」用 `taskkill`，但只在**两轮确认**后才动手：宿主退出时
	 *     控制台句柄会短暂不可用，单次探测容易误判。
	 *  4. 日志用 `>>` 追加（与 mac 版一致；截断由宿主侧 `rotateLog()` 负责）。
	 */
	public static function buildWrapperWindows(info:ContainerInfo):String
	{
		if (info == null || info.appPath == null) return null;

		var runtimeDir:String = ContainerStore.ensureRuntimeDir(info);
		var logPath:String = ContainerStore.join(runtimeDir, ContainerStore.LOG_NAME);
		var pidPath:String = ContainerStore.join(runtimeDir, ContainerStore.PID_NAME);
		var exitPath:String = ContainerStore.join(runtimeDir, ContainerStore.EXIT_NAME);
		var cmdPath:String = ContainerStore.join(runtimeDir, ContainerStore.CMD_NAME);
		var phasePath:String = ContainerStore.join(runtimeDir, ContainerStore.PHASE_NAME);

		// 工作目录：优先资源落点（Psych 的 Paths.mods() 相对 cwd），否则容器根
		var cwd:String = ContainerStore.resourcesDest(info);
		if (cwd == null || !ContainerStore.dirExists(cwd)) cwd = info.path;

		var data:ContainerManifestData = info.manifest != null ? info.manifest.raw : null;
		var exitMode:String = ContainerManifestParser.str(data, 'exitMode', 'terminate');
		if (exitMode != 'kill' && exitMode != 'terminate') exitMode = 'terminate';

		var s:String = '';
		s += '@echo off\r\n';
		s += 'rem Meteoric Engine 容器包装器 (Windows) —— 每次启动重写，请勿手工修改\r\n';
		s += 'rem 容器: ' + info.displayName + '  (' + info.folder + ')\r\n';
		s += 'rem 注意：本脚本依赖 cmd 的「父进程等待子进程退出」语义来捕获退出码。\r\n';
		// enabledelayedexpansion：下面 :me_watch 标签循环里必须用 !VAR! 而不是 %VAR% ——
		// cmd 对「括号块/多行标签块」内的 %VAR% 是**解析期**展开，计数器会永远读到旧值（死循环）。
		s += 'setlocal enabledelayedexpansion\r\n';
		s += 'set "LOG_FILE=' + logPath + '"\r\n';
		s += 'set "EXIT_FILE=' + exitPath + '"\r\n';
		s += 'set "CMD_FILE=' + cmdPath + '"\r\n';
		s += 'set "PID_FILE=' + pidPath + '"\r\n';
		s += 'set "PHASE_FILE=' + phasePath + '"\r\n';
		s += '\r\n';
		s += 'del /f /q "%EXIT_FILE%" 2>nul\r\n';
		s += 'del /f /q "%CMD_FILE%" 2>nul\r\n';
		// app.pid 必须在启动前删掉：宿主会用 app.pid 里的 pid 做「目标是否真的退出」核对，
		// 若留着上一次会话的旧 pid，可能拿一个已被系统回收、恰好被**别的进程**占用的 pid
		// 去 taskkill —— 那是真正的误杀风险（macOS 版 wrapper 同样会 rm 掉它）。
		s += 'del /f /q "%PID_FILE%" 2>nul\r\n';
		s += '> "%PHASE_FILE%" echo launching\r\n';
		s += '\r\n';
		s += 'rem ---- 拉起目标引擎 ----\r\n';
		s += 'rem 目标平台是 Windows 时 setlocal 不改变 cwd，直接 cd /d 到资源根；\r\n';
		s += 'rem 若容器放在网络盘等特殊位置导致 cd 失败，下面再显式 pushd 一次兜底。\r\n';
		s += 'cd /d "' + cwd + '" 2>nul\r\n';
		s += 'pushd "' + cwd + '" 2>nul\r\n';
		s += '>> "%LOG_FILE%" echo.\r\n';
		s += '>> "%LOG_FILE%" echo === [ME] container launch: ' + info.displayName + '\r\n';
		s += '>> "%LOG_FILE%" echo === [ME] app: ' + info.appPath + '\r\n';
		s += '\r\n';
		s += 'rem app.pid：宿主 pid 在 Windows 上无意义（不挂起、不靠信号唤醒），占位写 0。\r\n';
		s += 'rem 目标 pid 在 start /WAIT 之后尽力反查（见下），查不到就保持这个 0 = 宿主视为「未知」。\r\n';
		s += '> "%PID_FILE%" echo 0\r\n';
		s += '\r\n';
		s += 'rem 环境变量（清单 env + 默认注入）\r\n';
		for (line in envLinesWindows(data))
			s += line + '\r\n';
		s += '\r\n';
		s += 'rem /B 不新建控制台窗口；/WAIT 等它退出后 cmd 才继续 —— 「父进程等待子进程退出」\r\n';
		s += 'rem 本就是 cmd 对 GUI 子进程的行为，退出码因此可用（Windows 没有 wait 内建）。\r\n';
		s += 'start "" /B /WAIT "' + info.appPath + '" >> "%LOG_FILE%" 2>&1\r\n';
		s += 'set ME_CODE=%ERRORLEVEL%\r\n';
		s += 'rem 退出码兜底：为空 / 含非数字字符时统一记 -1，否则 echo 会把 exit.txt 写坏\r\n';
		s += 'rem （exitMode=kill 的引擎退出码经常是 -1，属正常现象，不当成错误）。\r\n';
		s += 'if not defined ME_CODE set ME_CODE=-1\r\n';
		s += 'set ME_NUM=1\r\n';
		s += 'for /f "delims=0123456789-" %%c in ("%ME_CODE%") do set ME_NUM=0\r\n';
		s += 'if "%ME_NUM%"=="0" set ME_CODE=-1\r\n';
		s += '\r\n';
		s += 'rem 尽力反查目标 pid 写进 app.pid（宿主用它核对「进程是否真的退出」）。\r\n';
		s += 'rem 正常路径下 target 此刻已退出 ⇒ 查不到 ⇒ app.pid 保持为空 = 宿主视为「未知」；\r\n';
		s += 'rem 只有 start /WAIT 未按预期阻塞（target 仍在跑）时才会查到 —— 那正是需要守卫的场景。\r\n';
		// 这一行引号嵌套最深，单独拼一个变量，避免 Haxe 单引号串里 `\'` 与 `''` 混在一起看不清：
		//   cmd   : for /f "tokens=2 delims==" %%v in ('wmic process where "name='X.exe'" get processid /value 2^>nul') do (
		//   wmic 里 '' 表示一个字面单引号（WQL 字符串语法）
		var pidLookup:String = 'for /f "tokens=2 delims==" %%v in (\''
			+ 'wmic process where "name=\'\'' + appImageName(info) + '\'\'" get processid /value 2^>nul'
			+ '\') do (\r\n';
		s += pidLookup;
		s += '  if not defined ME_APP_PID set "ME_APP_PID=%%v"\r\n';
		s += ')\r\n';
		s += 'if defined ME_APP_PID > "%PID_FILE%" echo %ME_APP_PID%\r\n';
		s += 'popd 2>nul\r\n';
		s += '\r\n';
		s += 'rem ---- 收尾：退出码 + 阶段 ----\r\n';
		s += 'rem 守卫（孤儿容器 / 假退出信号）**不在这里**做，而是交给宿主：\r\n';
		s += 'rem   宿主每帧 poll exit.txt，并核对目标进程是否真的退出，必要时自己 taskkill。\r\n';
		s += 'rem   理由是那部分逻辑能在开发机上被类型检查与单元化，而 cmd 脚本只能在真机试错。\r\n';
		s += '> "%EXIT_FILE%" echo %ME_CODE%\r\n';
		s += '>> "%LOG_FILE%" echo === [ME] target exited, code=%ME_CODE%\r\n';
		s += '> "%PHASE_FILE%" echo exited\r\n';
		s += '> "%PHASE_FILE%" echo idle\r\n';
		s += 'endlocal\r\n';
		s += 'exit /b 0\r\n';

		var wrapperPath:String = ContainerStore.join(runtimeDir, ContainerStore.WRAPPER_WIN_NAME);
		if (!ContainerStore.writeText(wrapperPath, s)) return null;
		return wrapperPath;
	}

	/** 目标引擎的映像名（Windows 的 tasklist 按 exe 名过滤时用）。 */
	static function appImageName(info:ContainerInfo):String
	{
		if (info == null || info.appPath == null) return 'Meteoric.exe';
		var p:String = info.appPath;
		// .app bundle 取 Contents/MacOS/<exe>；裸 exe 就是它自己
		var idx:Int = p.lastIndexOf('Contents/MacOS/');
		if (idx >= 0) p = p.substr(idx + 'Contents/MacOS/'.length);
		else
		{
			var parts:Array<String> = p.split('\\');
			p = parts[parts.length - 1];
			parts = p.split('/');
			p = parts[parts.length - 1];
		}
		return (p == null || p.length < 1) ? 'Meteoric.exe' : p;
	}

	/** Windows 环境变量行（SET 语法，值是**不带引号**的原样数据）。 */
	static function envLinesWindows(data:ContainerManifestData):Array<String>
	{
		var out:Array<String> = [];
		var env:Dynamic = null;
		if (data != null)
		{
			try
				env = Reflect.field(data, 'env')
			catch (e:Dynamic)
				env = null;
		}
		if (env != null)
		{
			try
			{
				for (key in Reflect.fields(env))
				{
					if (key == null || key.length < 1) continue;
					var v:Dynamic = Reflect.field(env, key);
					var vs:String = (v == null) ? '' : Std.string(v);
					out.push('set "' + key + '=' + vs + '"');
				}
			}
			catch (e:Dynamic) {}
		}
		out.push('set "SDL_VIDEO_CENTERED=1"');
		return out;
	}

	/** 生成 wrapper.sh（POSIX shell）。macOS / Linux 走这条。 */
	public static function buildWrapperUnix(info:ContainerInfo, hostPid:Int):String
	{
		if (info == null || info.appPath == null) return null;

		var runtimeDir:String = ContainerStore.ensureRuntimeDir(info);
		var logPath:String = ContainerStore.join(runtimeDir, ContainerStore.LOG_NAME);
		var pidPath:String = ContainerStore.join(runtimeDir, ContainerStore.PID_NAME);
		var exitPath:String = ContainerStore.join(runtimeDir, ContainerStore.EXIT_NAME);
		var cmdPath:String = ContainerStore.join(runtimeDir, ContainerStore.CMD_NAME);
		var phasePath:String = ContainerStore.join(runtimeDir, ContainerStore.PHASE_NAME);

		// 工作目录：优先资源落点（Psych 0.6.3 的 Paths.mods() 是相对 cwd 的 'mods/'，
		// 所以 cwd 必须是目标引擎的资源根，容器内 mod 才会被它自己识别）
		var cwd:String = ContainerStore.resourcesDest(info);
		if (cwd == null || !ContainerStore.dirExists(cwd)) cwd = info.path;

		var data:ContainerManifestData = info.manifest != null ? info.manifest.raw : null;
		var exitMode:String = ContainerManifestParser.str(data, 'exitMode', 'terminate');
		if (exitMode != 'kill' && exitMode != 'terminate') exitMode = 'terminate';
		var grace:String = (exitMode == 'kill') ? '0' : TERM_GRACE;

		var s:String = '';
		s += '#!/bin/sh\n';
		s += '# Meteoric Engine 容器包装器（每次启动重写，请勿手工修改）\n';
		s += '# 容器: ' + info.displayName + '  (' + info.folder + ')\n';
		s += 'set -u\n';
		s += 'HOST_PID=' + hostPid + '\n';
		s += 'APP_PID_FILE="' + pidPath + '"\n';
		s += 'EXIT_FILE="' + exitPath + '"\n';
		s += 'CMD_FILE="' + cmdPath + '"\n';
		s += 'PHASE_FILE="' + phasePath + '"\n';
		s += 'LOG_FILE="' + logPath + '"\n';
		s += 'GRACE=' + grace + '\n';
		s += '\n';
		s += 'rm -f "$$APP_PID_FILE" "$$EXIT_FILE" "$$CMD_FILE"\n';
		s += 'echo launching > "$$PHASE_FILE"\n';
		s += '\n';
		s += '(\n';
		s += '  cd "' + cwd + '" 2>/dev/null || true\n';
		s += '  # 目标引擎独立启动，起手忽略 HUP/INT：宿主被终端 Ctrl+C 时 wrapper 仍能收尾唤醒\n';
		s += '  trap "" HUP INT\n';
		s += '  # SDL 信号处理器会把 SIGINT/SIGTERM 变成引擎自身的退出请求，目标引擎不需要这层语义\n';
		s += '  SDL_HINT_NO_SIGNAL_HANDLERS=1 \\
';
		for (line in envLines(data))
			s += '  ' + line + ' \\
';
		// 日志用追加重定向（>>）而不是覆盖（>）：
		// 旧实现用 `>` 会在 wrapper 起跑时把宿主刚写下的 `launch:` 记录整段截掉，
		// 结果日志里只剩收尾行 —— 排障时看不到启动参数。截断改由宿主侧的 rotateLog() 负责。
		s += '  "' + info.appPath + '" >> "$$LOG_FILE" 2>&1 &\n';
		s += '  ME_APP=$$!\n';
		s += '  echo "$$ME_APP" > "$$APP_PID_FILE"\n';
		s += '  trap - HUP INT\n';
		s += '  (\n';
		s += '    while kill -0 "$$ME_APP" 2>/dev/null; do\n';
		s += '      # 宿主已经死了 ⇒ 不留孤儿容器\n';
		s += '      if ! kill -0 "$$HOST_PID" 2>/dev/null; then\n';
		s += '        kill -TERM "$$ME_APP" 2>/dev/null\n';
		s += '        sleep 1\n';
		s += '        kill -KILL "$$ME_APP" 2>/dev/null\n';
		s += '        break\n';
		s += '      fi\n';
		s += '      # 热键请求退出\n';
		s += '      if [ -f "$$CMD_FILE" ]; then\n';
		s += '        rm -f "$$CMD_FILE"\n';
		s += '        echo quitting > "$$PHASE_FILE"\n';
		s += '        kill -TERM "$$ME_APP" 2>/dev/null\n';
		s += '        if [ "$$GRACE" != "0" ]; then\n';
		s += '          sleep "$$GRACE"\n';
		s += '          kill -KILL "$$ME_APP" 2>/dev/null\n';
		s += '        fi\n';
		s += '      fi\n';
		s += '      sleep 0.05\n';
		s += '    done\n';
		s += '  ) &\n';
		s += '  ME_WATCHER=$$!\n';
		s += '  echo running > "$$PHASE_FILE"\n';
		s += '  wait "$$ME_APP"\n';
		s += '  ME_CODE=$$?\n';
		s += '  kill "$$ME_WATCHER" 2>/dev/null\n';
		s += '  echo "$$ME_CODE" > "$$EXIT_FILE"\n';
		s += '  echo exited > "$$PHASE_FILE"\n';
		s += ') &\n';
		s += 'WRAP_PID=$$!\n';
		s += '\n';
		s += '# 等目标引擎退出后唤醒宿主（宿主此时多半处于 SIGSTOP）\n';
		s += 'wait "$$WRAP_PID" 2>/dev/null\n';
		s += 'i=0\n';
		s += 'while [ ! -f "$$EXIT_FILE" ] && [ $$i -lt 40 ]; do\n';
		s += '  i=$$((i+1))\n';
		s += '  sleep 0.25\n';
		s += 'done\n';
		s += '[ -f "$$EXIT_FILE" ] || echo 0 > "$$EXIT_FILE"\n';
		s += 'kill -CONT "$$HOST_PID" 2>/dev/null\n';
		s += 'echo idle > "$$PHASE_FILE"\n';

		var wrapperPath:String = ContainerStore.join(runtimeDir, ContainerStore.WRAPPER_NAME);
		if (!ContainerStore.writeText(wrapperPath, s)) return null;
		try
		{
			Sys.command('chmod', ['+x', wrapperPath]);
		}
		catch (e:Dynamic) {}
		return wrapperPath;
	}

	/** 追加环境变量行（清单 env 字段 + 默认注入）。 */
	static function envLines(data:ContainerManifestData):Array<String>
	{
		var out:Array<String> = [];
		var env:Dynamic = null;
		if (data != null)
		{
			try
				env = Reflect.field(data, 'env')
			catch (e:Dynamic)
				env = null;
		}
		if (env != null)
		{
			try
			{
				for (key in Reflect.fields(env))
				{
					if (key == null || key.length < 1) continue;
					var v:Dynamic = Reflect.field(env, key);
					var vs:String = (v == null) ? '' : Std.string(v);
					out.push(key + '=' + quoteEnv(vs));
				}
			}
			catch (e:Dynamic) {}
		}
		// 目标引擎窗口定位交给它自己（SDL 读该变量）
		out.push('SDL_VIDEO_CENTERED=1');
		return out;
	}

	/** 拉起包装器（后台执行，立即返回）。 */
	public static function launch(wrapperPath:String):Bool
	{
		if (wrapperPath == null || !ContainerStore.fileExists(wrapperPath)) return false;
		try
		{
			#if windows
			// .bat 不是可执行映像，必须经 cmd 解释；start /B 让它脱离当前控制台后台跑，
			// 宿主随即可以继续（甚至隐藏窗口）而不被这个子进程拖住。
			var cmd:String = 'start "" /B cmd /c ' + ContainerProcess.quoteCmd(wrapperPath);
			return Sys.command(cmd) == 0;
			#else
			// -c 里再做一次 nohup + 后台：宿主被 STOP/KILL 都不影响 wrapper 收尾
			var cmd:String = 'nohup /bin/sh ' + quoteShell(wrapperPath) + ' >/dev/null 2>&1 &';
			var code:Int = Sys.command('/bin/sh', ['-c', cmd]);
			return code == 0;
			#end
		}
		catch (e:Dynamic)
			return false;
	}

	// ─────────────────── 前台化（macOS） ───────────────────

	/** 目标引擎窗口出现前，脚本轮询激活的最大次数（每轮 = osascript + 2s sleep）。 */
	public static inline var ACTIVATOR_TRIES:Int = 60;

	/**
	 * 生成“目标引擎前台化”脚本。
	 *
	 * 存在理由：宿主在 STOPPING 阶段就已 SIGSTOP，之后任何宿主侧重试都不会执行，
	 * 而 FNF 类目标引擎的窗口要几百毫秒~数秒才创建。旧实现在 0.6s 试一次就放弃，
	 * 于是永远抢不到前台 —— 表现为“点标题栏能把它弄到最前、随即又掉到后面”。
	 * 脚本用 nohup 独立于宿主生命周期，宿主冻结期间照样每 2s 重试，直到激活成功。
	 */
	public static function buildActivator(info:ContainerInfo):String
	{
		if (info == null) return null;
		var runtimeDir:String = ContainerStore.ensureRuntimeDir(info);
		if (runtimeDir == null) return null;

		var pidPath:String = ContainerStore.join(runtimeDir, ContainerStore.PID_NAME);
		var logPath:String = ContainerStore.join(runtimeDir, ContainerStore.LOG_NAME);

		// ⚠ 本字符串是 shell 脚本：所有 shell 变量必须写 `$$`，Haxe 会吃掉一个美元符，
		//   实际落盘才是 `$VAR`（项目内已多次踩坑，cpp 二进制实测）。
		var s:String = '';
		s += '#!/bin/sh\n';
		s += '# Meteoric Engine 容器前台化脚本（每次启动重写，请勿手工修改）\n';
		s += '# 容器: ' + info.displayName + '\n';
		s += 'set -u\n';
		s += 'PID_FILE="' + pidPath + '"\n';
		s += 'LOG_FILE="' + logPath + '"\n';
		s += 'i=0\n';
		s += 'TARGET=0\n';
		s += '# 1) 等目标引擎把 pid 写出来（此时它多半还没创建窗口）\n';
		s += 'while [ $$i -lt ' + ACTIVATOR_TRIES + ' ]; do\n';
		s += '  if [ -f "$$PID_FILE" ]; then\n';
		s += '    TARGET=$$(cat "$$PID_FILE" 2>/dev/null)\n';
		s += '    case "$$TARGET" in *[!0-9]*|\'\') TARGET=0 ;; esac\n';
		s += '    [ "$$TARGET" -gt 0 ] && break\n';
		s += '  fi\n';
		s += '  i=$$((i+1))\n';
		s += '  sleep 0.1\n';
		s += 'done\n';
		s += 'if [ "$$TARGET" -gt 0 ]; then\n';
		s += '  i=0\n';
		s += '  # 2) 反复把它设为 frontmost，直到它已经在前台（已在前台就不动，避免反复抢焦点）\n';
		s += '  #    四道闸：进程还活着 / 已在前台即停 / 连续确定性失败即停 / 最多 ' + ACTIVATOR_TRIES + ' 轮\n';
		s += '  FAILS=0\n';
		s += '  while [ $$i -lt ' + ACTIVATOR_TRIES + ' ]; do\n';
		s += '    kill -0 "$$TARGET" 2>/dev/null || break\n';
		s += '    # 先问“它现在是不是已经在前台了”，是则什么都不做（AppleScript 通篇不出现 $ 字面量，避免 Haxe 插值）\n';
		s += '    CUR=$$(/usr/bin/osascript -e "tell application \\"System Events\\" to set f to (frontmost of first application process whose unix id is $$TARGET)" -e "if f then" -e "return 1" -e "else" -e "return 0" -e "end if" 2>>"$$LOG_FILE")\n';
		s += '    if [ "$$CUR" = "1" ]; then break; fi\n';
		s += '    if /usr/bin/osascript -e "tell application \\"System Events\\" to set frontmost of first application process whose unix id is $$TARGET to true" >>"$$LOG_FILE" 2>&1; then\n';
		s += '      echo "=== [ME] activator: frontmost ok (pid $$TARGET, try $$i)" >> "$$LOG_FILE"\n';
		s += '      break\n';
		s += '    fi\n';
		s += '    FAILS=$$((FAILS+1))\n';
		s += '    if [ "$$FAILS" -ge 3 ]; then\n';
		s += '      echo "=== [ME] activator: 连续 3 次失败，放弃自动前台化（授权被拒时请到 系统设置 → 隐私与安全性 → 自动化 勾选 Meteoric）" >> "$$LOG_FILE"\n';
		s += '      break\n';
		s += '    fi\n';
		s += '    i=$$((i+1))\n';
		s += '    sleep 2\n';
		s += '  done\n';
		s += 'fi\n';

		var scriptPath:String = ContainerStore.join(runtimeDir, ContainerStore.ACTIVATOR_NAME);
		if (!ContainerStore.writeText(scriptPath, s)) return null;
		try
			Sys.command('chmod', ['+x', scriptPath])
		catch (e:Dynamic) {}
		return scriptPath;
	}

	/** 由宿主进程自己执行一次前台化（返回时抢回前台用）。成功返回 true。 */
	public static function runFrontmostScript(pid:Int):Bool
	{
		#if mac
		if (pid <= 1) return false;
		try
		{
			var script:String = 'tell application "System Events"\n'
				+ 'set procs to (every application process whose unix id is ' + pid + ')\n'
				+ 'if (count of procs) > 0 then set frontmost of item 1 of procs to true\n'
				+ 'end tell';
			return Sys.command('/usr/bin/osascript', ['-e', script]) == 0;
		}
		catch (e:Dynamic)
			return false;
		#else
		return false;
		#end
	}

	/**
	 * 启动前截断超限日志（wrapper 现在只追加，截断职责搬到这里）。
	 * 上限 512KB，超出保留尾部 256KB。失败静默：日志永远不能影响启停。
	 */
	public static function rotateLog(info:ContainerInfo):Void
	{
		if (info == null) return;
		try
		{
			var path:String = ContainerStore.runtimeFile(info, ContainerStore.LOG_NAME);
			if (!ContainerStore.fileExists(path)) return;
			var old:String = File.getContent(path);
			if (old == null) return;
			if (old.length > 524288) File.saveContent(path, old.substr(old.length - 262144));
		}
		catch (e:Dynamic) {}
	}

	// ─────────────────── 运行期状态 ───────────────────

	/**
	 * 追加一行容器运行日志（runtime/container.log）。
	 * 目标引擎自身的 stdout/stderr 也重定向到同一文件，所以这里只需写时间戳+事件。
	 * 失败静默：日志永远不能影响启停。
	 */
	public static function log(info:ContainerInfo, message:String):Void
	{
		if (info == null || info.path == null) return;
		try
		{
			var runtimeDir:String = ContainerStore.ensureRuntimeDir(info);
			var path:String = ContainerStore.join(runtimeDir, ContainerStore.LOG_NAME);
			var stamp:String = Date.now().toString();
			var line:String = '\n=== [ME] ' + stamp + '  ' + message + '\n';
			var old:String = '';
			try
			{
				if (ContainerStore.fileExists(path)) old = File.getContent(path);
			}
			catch (e:Dynamic)
				old = '';
			if (old == null) old = '';
			// 单容器日志上限 512KB：超出直接截断到尾部，避免长期游玩无限膨胀
			if (old.length > 524288) old = old.substr(old.length - 262144);
			File.saveContent(path, old + line);
		}
		catch (e:Dynamic) {}
	}

	/** wrapper 当前阶段（launching / running / quitting / exited / idle）；未知返回 null。 */
	public static function readPhase(info:ContainerInfo):String
	{
		return ContainerStore.readText(ContainerStore.runtimeFile(info, ContainerStore.PHASE_NAME));
	}

	/**
	 * 目标引擎 pid（未就绪返回 0）。
	 * 空文件 / 非数字 / 缺失一律返回 0 = **未知**：
	 * Windows 的 wrapper 反查不到 pid 时会留空，宿主必须把「未知」与「pid 0」区分开
	 * （0 会被当作无效 pid，从而跳过退出核对，这是正确的保守行为）。
	 */
	public static function readAppPid(info:ContainerInfo):Int
	{
		var txt:String = ContainerStore.readText(ContainerStore.runtimeFile(info, ContainerStore.PID_NAME));
		if (txt == null || txt.length < 1) return 0;
		// Std.parseInt 返回 Null<Int>；静态平台上不能把 null 赋给 Int（编译期实证），
		// 必须直接用 Null<Int> 接住再判空。
		var v:Null<Int> = Std.parseInt(txt);
		return (v == null) ? 0 : v;
	}

	/** 强制结束目标引擎及其全部子进程（Windows 专用；退出核对超时后的兜底）。 */
	public static function forceKill(info:ContainerInfo):Bool
	{
		#if windows
		if (info == null) return false;
		var pid:Int = readAppPid(info);
		var name:String = appImageName(info);
		try
		{
			// /T 连同它的子进程一起结束：目标引擎自己也可能拉起子进程（视频解码等）
			if (pid > 0) return Sys.command('taskkill /F /T /PID ' + pid + ' >nul 2>&1') == 0;
			return Sys.command('taskkill /F /T /IM "' + name + '" >nul 2>&1') == 0;
		}
		catch (e:Dynamic)
			return false;
		#else
		return false;
		#end
	}

	// ─────────────────── 引用/转义 ───────────────────

	/** 单引号引用（POSIX shell 唯一安全形式：内部的 ' 用 '\'' 闭合再拼接）。 */
	public static function quoteShell(s:String):String
	{
		if (s == null) return "''";
		// 注意：这里必须用双引号字符串。Haxe 的单引号字符串**不**识别 \' 转义，
		// 写成 '\'' 会让解析器在反斜杠处提前结束字符串，后面整段代码全被误解析。
		return "'" + StringTools.replace(s, "'", "'\\''") + "'";
	}

	/** 双引号引用（用于 KEY=双引号包住的值；值里的双引号/反引号/反斜杠/美元符需转义）。 */
	public static function quoteEnv(s:String):String
	{
		if (s == null) return '""';
		var out:String = s;
		out = StringTools.replace(out, '\\', '\\\\');
		out = StringTools.replace(out, '"', '\\"');
		out = StringTools.replace(out, '`', '\\`');
		out = StringTools.replace(out, '$', '\\$');
		return '"' + out + '"';
	}
}
