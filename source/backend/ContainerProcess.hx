package backend;

#if sys
import sys.io.Process;
#end

/**
 * 容器机制的进程原语（跨平台）。
 *
 * 为什么单独成文件：容器会话里「探活 / 前台化」两件事在 macOS 与 Windows 上实现完全不同
 * （POSIX 信号 vs Win32 命令行），收在一处后 `ContainerSession` 的状态机就能与平台无关。
 *
 * Windows 侧全部走 `Sys.command` 的**单字符串**形式 —— 项目既有惯例
 * （见 `backend/FolderCopier.hx`、`backend/ZipReader.hx`）：Windows 上等价于 `cmd /c <字符串>`，
 * 所以 `tasklist` / `taskkill` / `powershell` 都能直接调用；而这些分支必须 `#if windows` 包住，
 * 否则在 POSIX 上会被当成可执行文件名去解析。
 */
class ContainerProcess
{
	/** 进程是否存活（只查存在性，不做任何信号/句柄投递）。 */
	public static function isAlive(pid:Int):Bool
	{
		if (pid <= 0) return false;
		#if sys
		#if windows
		// /FI 过滤比拉全表快得多；CSV 输出里出现带引号的 pid 即视为存活
		var out:String = run('tasklist /FI "PID eq ' + pid + '" /NH /FO CSV');
		return out != null && out.indexOf('"' + pid + '"') >= 0;
		#else
		return Sys.command('kill -0 ' + pid + ' 2>/dev/null') == 0;
		#end
		#else
		return false;
		#end
	}

	/**
	 * 通用前台化：把 pid 的窗口提到最前。
	 *  - Windows：PowerShell `WScript.Shell.AppActivate(pid)`（按 pid 精确匹配）；
	 *  - macOS：System Events 按 unix id 置 frontmost（复用已验证的脚本通道）；
	 *  - 其它：空操作。
	 *
	 * 失败只影响观感（玩家手动点一下目标窗口即可），因此一律静默返回 false，绝不抛异常。
	 * pid ≤ 1 直接拒绝：Windows 的 pid 1/0 是系统空闲进程，macOS 的 1 是 launchd，都不该碰。
	 */
	public static function activate(pid:Int):Bool
	{
		if (pid <= 1) return false;
		#if windows
		var cmd:String = 'powershell -NoProfile -ExecutionPolicy Bypass -Command '
			+ '"try { $null = (New-Object -ComObject WScript.Shell).AppActivate(' + pid + ') } catch { }"';
		return Sys.command(cmd) == 0;
		#elseif mac
		return ContainerLauncher.runFrontmostScript(pid);
		#else
		return false;
		#end
	}

	/** 跑一条命令并把 stdout 读回来；失败返回 null，绝不抛。 */
	public static function run(cmd:String):String
	{
		#if sys
		var proc:Process = null;
		try
		{
			proc = new Process(cmd);
			var out:String = proc.stdout.readAll().toString();
			proc.close();
			return out;
		}
		catch (e:Dynamic)
		{
			if (proc != null)
			{
				try
					proc.close()
				catch (e2:Dynamic) {}
			}
			return null;
		}
		#else
		return null;
		#end
	}

	/** 把路径包成命令行安全的双引号形式（Windows 路径含空格时必须）。 */
	public static function quoteCmd(s:String):String
	{
		if (s == null) return '""';
		return '"' + StringTools.replace(s, '"', '""') + '"';
	}
}
