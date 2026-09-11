package backend;

import backend.ClientPrefs;

import flixel.FlxG;
import flixel.input.FlxInput.FlxInputState;
import flixel.input.keyboard.FlxKey;
import openfl.Lib;

#if sys
import sys.FileSystem;
#end

/**
 * 容器会话状态机：启动 → 宿主挂起 → 目标引擎独占 → 唤醒宿主 → 整机重启。
 *
 * 生命周期（每一帧由 Main.hx 的 ENTER_FRAME 钩子驱动，见 Main.setupContainerHook）：
 *
 *   IDLE ──launch()──► LAUNCHING ──0.4s──► HIDING ──0.35s──► STOPPING
 *                                                              │ kill -STOP 自己
 *                                                              ▼
 *                                                          RUNNING（宿主冻结中）
 *                                                              │ wrapper 写 exit.txt
 *                                                              │ wrapper kill -CONT 唤醒宿主
 *                                                              ▼
 *                                                          RETURNING ──► 恢复窗口 + 整机重启
 *
 * 关键约束：
 *  - 宿主挂起后 `tick()` 不再被调用（进程被 STOP），所有“回来之后”的动作都放在
 *    RETURNING 状态，且必须幂等（wrapper 兜底可能重复写 exit.txt）。
 *  - 任何一步失败都不能把宿主留在不可恢复状态：挂起前若 exit.txt 已存在 ⇒ 直接复位。
 *  - 视觉让位用 `window.visible = false`（SDL_HideWindow）而不是“缩成 1×1”：
 *    缩小的窗口**仍是 key window**，macOS 会把目标引擎的前台化请求判为后台应用抢焦点
 *    而拒绝 —— 实测症状正是“点标题栏能把它弄到最前、随即又掉到后面”。隐藏窗口才会让
 *    SDL 交出窗口级焦点，目标窗口才拿得到键盘。
 *  - 前台化**不能由宿主自己重试**：宿主在 STOPPING 阶段就已 SIGSTOP，之后的任何重试代码
 *    都不会执行（旧实现把重试放在 Phase.Running，等于永远不会跑）。因此前台化交给
 *    `ContainerLauncher.buildActivator()` 生成的独立小脚本：在宿主冻结期间按 pid 重试
 *    `set frontmost`，直到目标引擎窗口真的出现并被激活为止。
 */
class ContainerSession
{
	/** 当前是否有容器会话进行中。 */
	public static var active(default, null):Bool = false;

	/** 正在运行的容器（可空）。 */
	public static var current(default, null):ContainerInfo = null;

	/** 面向界面的提示（回到 ContainersMenuState 时显示）。 */
	public static var notice:String = null;

	static var waitSeconds:Float = ContainerLauncher.DEFAULT_WAIT;
	static var phase:Phase = Phase.Idle;
	static var phaseTimer:Float = 0;
	static var hostPid:Int = 0;
	/**
	 * 宿主当前是否处于挂起态。
	 * macOS：`kill -STOP` 成功后为 true（此时 tick 不再被调用）。
	 * Windows：恒为 false —— 宿主不挂起，靠 `Phase.Running` 每帧 poll `exit.txt` 收尾。
	 */
	static var hostSuspended:Bool = false;
	static var originalW:Int = 1280;
	static var originalH:Int = 720;
	static var restored:Bool = false;
	/** 已发过热键退出请求（防每帧刷屏，并切换提示文案）。 */
	static var quitRequested:Bool = false;
	/** 已请求过目标引擎前台化（脚本一次性派发，重试由脚本自己做）。 */
	static var activated:Bool = false;
	static var activateTimer:Float = 0;
	/** 宿主窗口是否已隐藏（只做一次）。 */
	static var hidden:Bool = false;
	/**
	 * 退出组合键的修饰键：必须**按住**它再按 containerExitKeys 里的键才判定退出。
	 * 这是修「单独按 Control 就回标题」的关键 —— 旧实现把 [CONTROL, C] 逐键独立判定，
	 * 等价于 `CONTROL || C`，而界面显示的是组合键 `CONTROL + C`，语义与显示不一致。
	 */
	static var hotkeyModifier:FlxKey = FlxKey.CONTROL;
	/** 本次会话是否记录过“组合键命中的原始按键”（用于日志与提示文案）。 */
	static var hotkeyMainKey:FlxKey = FlxKey.C;
	/** 取宿主 pid 失败时的详情（拼进错误文案，避免只有一句“无法取得”无法排障）。 */
	static var lastPidError:String = null;
	/** 已看到 exit.txt 后的累计等待（Windows 退出核对用）。 */
	static var exitSeenTimer:Float = 0;
	/** 是否已对目标执行过强制结束（防每帧重复 taskkill）。 */
	static var forceKilled:Bool = false;

	/** 系统临时目录（pid 探测的兜底落点，可写性最可靠）。 */
	static function sysTmpDir():String
	{
		#if sys
		try
		{
			var t:String = Sys.getEnv('TMPDIR');
			if (t != null && t.length > 0) return ContainerStore.tidy(t);
		}
		catch (e:Dynamic) {}
		#end
		return '/tmp';
	}

	/** 宿主窗口当前是否有焦点（由 window.onFocusIn/onFocusOut 记账）。 */
	static var hostFocused:Bool = true;
	/** 焦点监听是否已挂（只挂一次）。 */
	static var focusHooked:Bool = false;

	static inline var WAIT_LAUNCH:Float = 0.4;    // 拉起 wrapper 后喘口气再让位
	static inline var WAIT_HIDE:Float = 0.35;     // 隐窗后等一帧落地再 SIGSTOP
	static inline var ACTIVATE_AT:Float = 0.6;    // 派发前台化脚本的时机（脚本自己等待+重试）
	/** Windows 退出核对：看到 exit.txt 后目标仍存活的宽限秒数，超时才强制结束。 */
	static inline var EXIT_GRACE:Float = 1.5;

	public static function isBusy():Bool
	{
		return active;
	}

	// ───────────────────────── 启动 ─────────────────────────

	/**
	 * 启动容器。返回 null 表示成功，否则返回面向玩家的失败原因。
	 * 前置条件：ClientPrefs.data.containersEnabled、容器自检通过（problem == null）。
	 */
	public static function launch(info:ContainerInfo):String
	{
		if (info == null) return '容器为空';
		if (active) return '已有容器正在运行';
		if (!ClientPrefs.data.containersEnabled) return '容器功能已在设置中关闭';
		if (info.problem != null) return info.problem;
		if (info.appPath == null) return '目标引擎主程序未就绪';

		#if !sys
		return '当前平台不支持容器启动';
		#else
		// 1) 资源 staging（唯一会写目标引擎目录的动作，只增不改）
		var staged:Int = 0;
		try
			staged = ContainerStore.stageResources(info)
		catch (e:Dynamic)
			staged = 0;

		// 2) 宿主 pid
		//    - macOS：**必须**拿到 —— wrapper 在目标退出后要用 `kill -CONT <hostPid>` 唤醒被
		//      SIGSTOP 的宿主，拿不到就不能安全启动（宁可不启动）。
		//    - Windows：**不需要** —— 宿主不挂起，自己每帧 poll `exit.txt`；wrapper 只写退出码。
		//      顺带避开「宿主与目标同名 Meteoric.exe」时按名字误杀的风险。
		#if windows
		hostPid = 0;
		#else
		// 候选临时目录按可写性排序：容器 runtime（一定可写）→ app 资源根 → 系统临时目录
		hostPid = resolveHostPid([
			ContainerStore.ensureRuntimeDir(info),
			ContainerStore.appRoot(),
			sysTmpDir()
		]);
		if (hostPid <= 0)
			return '无法取得宿主进程 PID（容器无法安全唤醒，已中止）'
				+ (lastPidError != null ? '：' + lastPidError : '');
		#end

		// 2.5) 陈旧会话保险：上次的目标引擎进程若仍在（玩家上次没走正常返回流程），
		//      先拒绝启动，避免同一个容器出两个实例抢窗口与资源。
		var stalePid:Int = ContainerLauncher.readAppPid(info);
		if (stalePid > 0 && isProcessAlive(stalePid))
			return '该容器的上一次进程仍在运行（pid ' + stalePid + '），请先退出它再切换';

		// 3) 生成 wrapper
		var wrapperPath:String = null;
		try
			wrapperPath = ContainerLauncher.buildWrapper(info, hostPid)
		catch (e:Dynamic)
			wrapperPath = null;
		if (wrapperPath == null) return '包装器生成失败（容器 runtime 目录不可写）';

		// 4) 清掉上一次的退出/命令标记；日志改为“追加 + 启动时轮转”，
		//    这样本次启动参数不会被 wrapper 的日志重定向截掉（旧实现 `>` 覆盖导致 launch 记录丢失）。
		try
		{
			var exitFile:String = ContainerStore.runtimeFile(info, ContainerStore.EXIT_NAME);
			if (FileSystem.exists(exitFile)) FileSystem.deleteFile(exitFile);
			var cmdFile:String = ContainerStore.runtimeFile(info, ContainerStore.CMD_NAME);
			if (FileSystem.exists(cmdFile)) FileSystem.deleteFile(cmdFile);
		}
		catch (e:Dynamic) {}
		ContainerLauncher.rotateLog(info);

		// 5) 记录原始窗口尺寸（复位时还原）
		originalW = Std.int(Lib.application.window.width);
		originalH = Std.int(Lib.application.window.height);
		if (originalW < 64) originalW = 1280;
		if (originalH < 64) originalH = 720;

		// 6) 清单覆盖等待时长
		var data:ContainerManifestData = info.manifest != null ? info.manifest.raw : null;
		waitSeconds = ContainerManifestParser.num(data, 'waitSeconds', ContainerLauncher.DEFAULT_WAIT);
		if (waitSeconds < 0.4) waitSeconds = 0.4;

		hookFocusEvents();
		current = info;
		notice = null;
		quitRequested = false;
		activated = false;
		activateTimer = 0;
		restored = false;
		hidden = false;
		exitSeenTimer = 0;
		forceKilled = false;
		active = true;
		phase = Phase.Launching;
		phaseTimer = 0;

		ContainerLauncher.log(info, 'launch: app=' + info.appPath + '  staged=' + staged
			+ '  hostPid=' + hostPid + '  wait=' + waitSeconds + 's');

		// 7) 拉起
		if (!ContainerLauncher.launch(wrapperPath))
		{
			active = false;
			phase = Phase.Idle;
			current = null;
			return '目标引擎启动失败（wrapper 无法执行）';
		}

		FlxG.log.add('[Container] ' + info.displayName + ' 启动中…');
		return null;
		#end
	}

	// ───────────────────── 每帧驱动 ─────────────────────

	/**
	 * 每帧调用（Main.hx 桌面端 ENTER_FRAME）。宿主被 SIGSTOP 期间不会被调用，
	 * 唤醒后第一帧从这里继续走 RETURNING。
	 */
	public static function tick(elapsed:Float):Void
	{
		if (!active || current == null) return;

		// 目标引擎已经收尾（启动失败/秒退/热键退出）⇒ 任何阶段都直接走收尾复位。
		// 放在开关之前：避免在 Launching/Hiding 阶段继续缩窗口+挂起自己，白跑一轮。
		if (exitFileExists())
		{
			if (!targetReallyGone(elapsed)) return;
			finishReturn();
			return;
		}

		phaseTimer += elapsed;
		checkHotkey();

		switch (phase)
		{
			case Phase.Idle:
				// 不应到达

			case Phase.Launching:
				activateTimer += elapsed;
				if (!activated && activateTimer >= ACTIVATE_AT)
				{
					// 只派发一次：真正的等待+重试由独立脚本负责（宿主马上要被 SIGSTOP，
					// 放在这里重试等于永远不会执行 —— 这就是旧版前台化失败的根因）。
					activated = true;
					launchActivator(current);
				}
				if (phaseTimer >= WAIT_LAUNCH) toPhase(Phase.Hiding);

			case Phase.Hiding:
				if (!hidden)
				{
					hidden = true;
					hideHostWindow();
				}
				if (phaseTimer >= WAIT_HIDE) toPhase(Phase.Stopping);

			case Phase.Stopping:
				// 挂起前最后一道保险：wrapper 已收尾就不要停了（上面已判，这里再守一次）
				if (exitFileExists())
				{
					finishReturn();
					return;
				}
				suspendHost();
				toPhase(Phase.Running);

			case Phase.Running:
				// macOS：正常情况宿主已被 SIGSTOP，走不到这里（只有 kill -STOP 失败才会到达，
				//        那时兜底再派发一次前台化脚本）。
				// Windows：宿主**不挂起**，这里就是主力路径 —— 每帧 poll `exit.txt`
				//        （tick 开头已判过 exitFileExists，所以到达此处即表示目标还在跑）。
				//        宿主隐窗 + 不挂起 ⇒ SDL 不渲染隐藏窗口，CPU 接近零。
				if (!hostSuspended)
				{
					// 目标引擎的 pid 一到就前台化（Windows 上宿主不进入 STOP，这条真的会执行）
					if (!activated)
					{
						activateTimer += elapsed;
						if (activateTimer >= ACTIVATE_AT)
						{
							activated = true;
							launchActivator(current);
						}
					}
				}

			case Phase.Returning:
				finishReturn();
		}
	}

	/** 热键请求退出（也可由界面按钮调用）。 */
	public static function requestQuit():Void
	{
		if (!active || current == null) return;
		if (quitRequested) return;
		quitRequested = true;
		var cmdFile:String = ContainerStore.runtimeFile(current, ContainerStore.CMD_NAME);
		if (!ContainerStore.writeText(cmdFile, 'quit\n'))
			FlxG.log.add('[Container] 退出请求写入失败（runtime 目录不可写）');
		else
			FlxG.log.add('[Container] 已请求关闭 ' + current.displayName);
	}

	/**
	 * 记账宿主窗口焦点（只挂一次）。
	 * lime.ui.Window 只有 onFocusIn/onFocusOut 事件，没有 focused 字段，所以自己维护状态。
	 * 首次 true 的取值是保守假设（无事件时默认有焦点，保证热键可用）。
	 */
	static function hookFocusEvents():Void
	{
		if (focusHooked) return;
		focusHooked = true;
		try
		{
			Lib.application.window.onFocusIn.add(function() hostFocused = true);
			Lib.application.window.onFocusOut.add(function() hostFocused = false);
		}
		catch (e:Dynamic) {}
		hostFocused = true;
	}

	static function checkHotkey():Void
	{
		if (quitRequested) return;
		// 目标引擎在前台时按键不会到宿主（独立进程独立窗口），宿主失焦期间一律不响应，
		// 避免“在目标引擎里按了 Ctrl+C 结果把宿主也搞退出”这类误判。
		// 窗口焦点用 onFocusIn/onFocusOut 自行记账：lime.ui.Window 没有 focused 字段（编译期实证）。
		if (!hostFocused) return;

		var keys:Array<FlxKey> = ClientPrefs.data.containerExitKeys;
		if (keys == null || keys.length < 1) return;
		if (FlxG.keys == null) return;

		// 修饰键闸门：
		//  - macOS / Linux：`Ctrl+C` 是真组合键 —— CONTROL 必须**按住**、C 必须**本帧刚按下**。
		//    （2026-09-11 修复：旧实现逐键独立判定，等价 `CONTROL || C`，单独按 Control 就退出。）
		//  - Windows：默认热键是**单键 F10**（`ClientPrefs` 的 Windows 默认值），没有修饰键，
		//    因此不做修饰键判定；F10 与 FNF 玩法零冲突，也避开「Ctrl+C 在目标引擎里是常用操作」
		//    导致的误触。逐键 JUST_PRESSED 本身保证「按住不放不会连触」，必须松开再按。
		#if !windows
		if (!FlxG.keys.checkStatus(hotkeyModifier, FlxInputState.PRESSED)) return;
		#end

		for (key in keys)
		{
			#if !windows
			// 修饰键本身不算“主键”，否则按住 Control 的瞬间就会命中
			if (cast(key, Int) == cast(hotkeyModifier, Int)) continue;
			#end
			// 注意：FlxKey 是 abstract Int，静态平台上不可为 null，不能写 key == null 判空（编译期实证）
			// FlxG.keys 本身不可调用；逐键查询用 FlxKeyManager.checkStatus（firstJustPressed 只给“任意键”）
			if (FlxG.keys.checkStatus(key, FlxInputState.JUST_PRESSED))
			{
				hotkeyMainKey = key;
				checkHotkeyHitLog();
				requestQuit();
				return;
			}
		}
	}

	/** 热键命中时补一条日志（旧版日志只写 exit=0 (hotkey)，无法区分按键来源）。 */
	static function checkHotkeyHitLog():Void
	{
		if (current == null) return;
		var keyName:String = null;
		try
			keyName = backend.InputFormatter.getKeyName(hotkeyMainKey)
		catch (e:Dynamic)
			keyName = Std.string(hotkeyMainKey);
		#if windows
		ContainerLauncher.log(current, 'hotkey hit: ' + keyName + '（Windows 单键热键）');
		#else
		var modName:String = null;
		try
			modName = backend.InputFormatter.getKeyName(hotkeyModifier)
		catch (e:Dynamic)
			modName = Std.string(hotkeyModifier);
		ContainerLauncher.log(current, 'hotkey hit: ' + modName + '+' + keyName + '（组合键，修饰键需按住）');
		#end
	}

	// ───────────────────── 收尾/复位 ─────────────────────

	/**
	 * 收尾复位：恢复窗口尺寸 → kill -CONT 自己（幂等）→ 清理状态 → 整机重启。
	 * 强制走 FlxG.resetGame()：目标引擎退出后本体可能残留“一帧都没跑过”的中间状态
	 * （音符/音频/条件都停在 SIGSTOP 那一瞬），整机重启比状态回滚可靠，也正是
	 * 需求里“重新启动游戏”的语义。
	 */
	static function finishReturn():Void
	{
		var info:ContainerInfo = current;
		restoreHostWindow();

		var codeTxt:String = null;
		if (info != null)
		{
			codeTxt = ContainerStore.readText(ContainerStore.runtimeFile(info, ContainerStore.EXIT_NAME));
			ContainerLauncher.log(info, 'session end: exit=' + Std.string(codeTxt)
				+ (quitRequested ? ' (hotkey)' : ''));
		}

		var name:String = (info != null) ? info.displayName : '容器';
		var code:Null<Int> = (codeTxt == null) ? null : Std.parseInt(codeTxt);
		if (quitRequested)
			notice = '已从「' + name + '」返回，正在重启 Meteoric…';
		else if (code != null && code != 0)
			// 非 0 退出码 = 目标引擎自己崩了/起不来。这条必须说清楚，否则玩家只会觉得“点了没反应”。
			notice = '「' + name + '」异常退出（退出码 ' + code + '）—— 目标引擎可能无法在本机启动；'
				+ '点「打开日志/容器目录」看 runtime/container.log，并先单独双击运行该引擎确认它能启动';
		else
			notice = '「' + name + '」已退出（退出码 ' + (codeTxt == null ? '?' : codeTxt) + '），正在重启 Meteoric…';
		FlxG.log.add('[Container] ' + notice);

		active = false;
		current = null;
		phase = Phase.Idle;
		phaseTimer = 0;
		quitRequested = false;
		activated = false;
		activateTimer = 0;
		exitSeenTimer = 0;
		forceKilled = false;

		// kill -CONT 必须在任何可能重新进入 STOP 的路径之前发出；重复调用无害
		resumeHost();

		// 保命闸：flixel 在 `_lostFocus == true && FlxG.autoPause == true` 时**整机不更新**
		// （FlxGame.hx:520），此时 state 切换请求（resetGame 只是排队）永远不会被执行。
		// 正常路径下 restoreHostWindow() 的前台化会触发 ACTIVATE 把 _lostFocus 清掉；
		// 这里再兜一层：临时关掉 autoPause，保证复位这一帧一定跑得动。
		// 复位后 FlxGame.onFocus() 会按 `FlxG.autoPause = ClientPrefs.data.autoPause` 恢复用户设置。
		if (FlxG.autoPause)
		{
			FlxG.autoPause = false;
			FlxG.log.add('[Container] 返回时临时关闭 autoPause，确保整机复位不被失焦冻结挡住');
		}

		#if sys
		Sys.sleep(0.2);
		#end

		// 整机重启：卸载全部图形/音频资源，重新走 TitleState（等价“关掉再打开”）
		try
		{
			FlxG.resetGame();
		}
		catch (e:Dynamic)
		{
			FlxG.log.add('[Container] resetGame 失败，回退到软复位：' + Std.string(e));
			try
			{
				Paths.clearStoredMemory();
				Paths.clearUnusedMemory();
			}
			catch (e2:Dynamic) {}
		}
	}

	/** 恢复宿主窗口并确保进程处于运行态（幂等，可重复调用）。 */
	static function restoreHostWindow():Void
	{
		if (restored) return;
		restored = true;
		try
		{
			Lib.application.window.visible = true;
		}
		catch (e:Dynamic) {}
		try
		{
			Lib.application.window.width = originalW;
			Lib.application.window.height = originalH;
		}
		catch (e:Dynamic) {}
		try
			Lib.application.window.focus()
		catch (e:Dynamic) {}
		resumeHost();
		// Windows 到此为止：宿主从未挂起，`visible = true` + `focus()`（SDL_RaiseWindow）就够把
		// 本体带回前台。这里**不**再调 PowerShell AppActivate —— 它在部分机器上要冷启动 1~3 秒，
		// 会把「返回」这一帧卡住；而 macOS 的 osascript 通道已验证够快，且那边宿主刚从 STOP 恢复、
		// 不主动抢前台就会停在失焦（flixel 会因 _lostFocus + autoPause 冻结整机更新）。
		#if !windows
		activateByPid(hostPid);
		#end
	}

	// ───────────────────── 进程/窗口原语 ─────────────────────

	/**
	 * 让位：隐藏宿主窗口（SDL_HideWindow）。
	 *
	 * 为什么不是“缩成 1×1”：缩小后的窗口依然是 key window，macOS 会认为本应用仍占据
	 * 前台，目标引擎的激活请求被判为“后台应用抢焦点”而拒绝 —— 实测症状是目标窗口
	 * 点一下就掉焦、键盘进不去。隐藏窗口才会让 SDL 交出窗口级焦点。
	 * 同时把尺寸也收回 1×1，避免恢复时残留一个巨大的窗口尺寸差。
	 */
	static function hideHostWindow():Void
	{
		#if !windows
		// macOS：先把尺寸收回 1×1，避免恢复时残留一个巨大的窗口尺寸差（SDL 隐藏时不重排 surface）。
		try
		{
			Lib.application.window.width = 1;
			Lib.application.window.height = 1;
		}
		catch (e:Dynamic) {}
		#end
		try
		{
			Lib.application.window.visible = false;
		}
		catch (e:Dynamic)
			FlxG.log.add('[Container] 隐藏宿主窗口失败（继续以缩窗方式让位）：' + Std.string(e));
	}

	/**
	 * 挂起宿主。
	 *  - macOS：`kill -STOP` 自己（零 CPU；唤醒由 wrapper 发 SIGCONT）。失败则降级为
	 *    「继续跑但已让位」，不致命。
	 *  - Windows：**不做挂起**。`NtSuspendProcess` 是未公开 ntdll API，不值得为之引入内联 C++；
	 *    宿主改为「隐窗 + 继续运行」，每帧自己 poll `exit.txt`（见 tick 的 Phase.Running）。
	 *    代价是进程留在内存（约数百 MB），收益是全程无信号、无未公开 API、可被任务管理器正常看到。
	 */
	static function suspendHost():Void
	{
		#if windows
		hostSuspended = false;
		FlxG.log.add('[Container] Windows：宿主不挂起，改为隐窗并每帧轮询退出信号');
		#elseif sys
		try
		{
			Sys.command('/bin/sh', ['-c', 'kill -STOP ' + hostPid]);
			hostSuspended = true;
		}
		catch (e:Dynamic)
			FlxG.log.add('[Container] 宿主挂起失败（继续以让位模式运行）：' + Std.string(e));
		#end
	}

	/** 唤醒宿主：`kill -CONT`（幂等；wrapper 也会发一次，重复无害）。Windows 下为空操作。 */
	static function resumeHost():Void
	{
		#if sys
		#if !windows
		if (hostPid <= 0) return;
		try
			Sys.command('/bin/sh', ['-c', 'kill -CONT ' + hostPid])
		catch (e:Dynamic) {}
		#end
		#end
		hostSuspended = false;
	}

	/**
	 * 取宿主 pid（Haxe 没有 Sys.pid()，必须问 shell）。
	 *
	 * 三级兜底，全部失败才返回 0，并把失败详情写进 lastPidError 供界面显示：
	 *  ① /bin/sh -c 'echo $PPID'   —— sh 的父进程就是本进程（最直接，不写任何文件）
	 *  ② /bin/sh -c 'ps -o ppid= -p $$' —— ① 被环境干扰时的等价探测
	 *  ③ 临时文件 `echo $$ > 文件` 再读回 —— 极老 /bin/sh 不支持 $PPID 时的兜底
	 *     （Haxe 侧必须写 `$$$$`，否则 `$$` 被 Haxe 转义成单个 `$`，见实现处注释）
	 * 另备 ④ /usr/bin/perl getppid —— 系统 Perl 存在时的独立通道。
	 *
	 * 修复背景（2026-09-10 实测）：旧实现只走 ③，且临时文件写在 app bundle 内部的
	 * `appRoot()` 下，任何一步失败就只能报「无法取得宿主进程 PID」并中止 —— 这条链
	 * 不该是单点。现在四路并存，任一路成功即可启动容器。
	 */
	static function resolveHostPid(candidates:Array<String>):Int
	{
		#if sys
		// ① $PPID（sh 的父进程 = 本进程）。
		//    ⚠ 必须写 $$PPID：Haxe 的 `$标识符` 会做插值（`$PPID` 会被当成变量 PPID，
		//    当前作用域没有它才侥幸编译通过，一旦将来有同名变量就编译失败）；
		//    `\$` 也不是合法转义。Haxe 里唯一正确的字面美元符写法就是 `$$`（cpp 二进制实测）。
		var v:Int = probePid("/bin/sh -c 'echo $$PPID'");
		if (v > 0) return v;
		// ② ps 查 shell 自己的父进程
		v = probePid("/bin/sh -c 'ps -o ppid= -p $$$$'");
		if (v > 0) return v;
		// ③ 临时文件兜底（双候选目录：可写优先）
		for (dir in candidates)
		{
			if (dir == null || dir.length < 1) continue;
			v = probePidViaFile(dir);
			if (v > 0) return v;
		}
		// ④ perl 独立通道
		v = probePid('/usr/bin/perl -e "print getppid()"');
		if (v > 0) return v;
		#end
		return 0;
	}

	/** 跑一条 shell 命令，把 stdout 解析成正整数 pid；失败返回 0（详情写 lastPidError）。 */
	static function probePid(shellCmd:String):Int
	{
		#if sys
		var proc:sys.io.Process = null;
		try
		{
			proc = new sys.io.Process('/bin/sh', ['-c', shellCmd]);
			var out:String = null;
			try
			{
				out = proc.stdout.readAll().toString();
			}
			catch (e:Dynamic)
			{
				out = null;
			}
			if (out != null)
			{
				var v:Null<Int> = Std.parseInt(StringTools.trim(out));
				if (v != null && v > 0) return v;
			}
		}
		catch (e:Dynamic)
		{
			lastPidError = Std.string(e);
		}
		// 清理放在 finally 之外：proc.close() 只是关闭管道，不会杀进程（echo 早已结束）
		if (proc != null)
		{
			try
			{
				proc.close();
			}
			catch (e:Dynamic) {}
		}
		#end
		return 0;
	}

	/** 兜底通道：把 $$ 写进文件再读回（用于不支持 $PPID / ps 受限的极端环境）。 */
	static function probePidViaFile(dir:String):Int
	{
		#if sys
		var tmp:String = ContainerStore.join(dir, '.me_hostpid.tmp');
		try
		{
			// ⚠ Haxe 会把 `$$` 转义成一个字面 `$`：写 'echo $$ >' 生成的命令是 `echo $ >`，
			//   写入文件的只有一个 "$"，Std.parseInt 必然 null（真机 cpp 二进制实测复现）。
			//   要得到 shell 的 `$$`（pid）必须写四个美元符：Haxe 吃掉两个 → 剩下两个给 shell。
			var cmd:String = 'echo $$$$ > ' + ContainerLauncher.quoteShell(tmp);
			Sys.command('/bin/sh', ['-c', cmd]);
			var txt:String = ContainerStore.readText(tmp);
			try
			{
				FileSystem.deleteFile(tmp);
			}
			catch (e:Dynamic) {}
			if (txt != null && txt.length > 0)
			{
				var v:Null<Int> = Std.parseInt(txt);
				if (v != null && v > 0) return v;
				lastPidError = '临时文件内容不是数字: ' + txt;
			}
			else
				lastPidError = '临时文件读取为空: ' + tmp;
		}
		catch (e:Dynamic)
		{
			lastPidError = Std.string(e);
		}
		#end
		return 0;
	}

	/**
	 * 派发“目标引擎前台化”脚本（无窗口期 → 宿主隐窗 → 按 pid 重试 set frontmost）。
	 *
	 * 为什么必须是独立脚本而不是宿主自己循环重试：
	 *  宿主在 STOPPING 阶段就 SIGSTOP 了，之后任何 Haxe 侧的重试代码都不会执行；
	 *  而目标引擎窗口（FNF 类引擎要加载几百 MB 资源）远晚于这个时刻才创建。
	 *  旧实现只在 0.6s 试一次、失败后把 activated 置 true，重试分支又落在宿主冻结之后 ——
	 *  等于“前台化从来没成功过”，正是“点一下就被压回去”的根因。
	 * 脚本由 nohup 拉起（独立于宿主生命周期），宿主被 STOP/KILL 都不影响它继续重试。
	 */
	static function launchActivator(info:ContainerInfo):Void
	{
		if (info == null) return;

		#if windows
		// Windows：PowerShell 后台脚本（-WindowStyle Hidden 抑制控制台闪窗）。
		// 宿主不挂起，所以这里派发之后宿主仍在跑；脚本负责「等 pid → 反复 AppActivate」。
		var path:String = ContainerLauncher.buildActivatorWindows(info);
		if (path == null)
		{
			FlxG.log.add('[Container] 前台化脚本生成失败（runtime 目录不可写）');
			return;
		}
		var cmd:String = 'start "" /B powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '
			+ ContainerProcess.quoteCmd(path);
		try
			Sys.command(cmd)
		catch (e:Dynamic)
			FlxG.log.add('[Container] 前台化脚本派发失败：' + Std.string(e));
		ContainerLauncher.log(info, 'activator dispatched (ps1)');
		#elseif mac
		// macOS：由 nohup 拉起的 shell 脚本 —— 宿主马上要被 SIGSTOP，只能靠独立进程重试。
		var path:String = ContainerLauncher.buildActivator(info);
		if (path == null)
		{
			FlxG.log.add('[Container] 前台化脚本生成失败（runtime 目录不可写）');
			return;
		}
		ContainerLauncher.launch(path);
		ContainerLauncher.log(info, 'activator dispatched（宿主不再自行重试）');
		#end
	}

	/**
	 * 用 osascript 把某个 pid 的进程置为前台（宿主自己回来时也用它）。
	 * 用 System Events 按 unix id 精确匹配，不需要知道 app 名。
	 * 首次会弹一次「自动化 → System Events」授权，拒绝只影响自动前台化，不影响启停与返回。
	 * 失败原因写入 lastPidError 之外单独记日志，避免静默。
	 */
	static function activateByPid(pid:Int):Bool
	{
		#if mac
		if (pid <= 1) return false; // 1 = launchd，绝不碰
		try
		{
			var ok:Bool = ContainerLauncher.runFrontmostScript(pid);
			if (!ok) FlxG.log.add('[Container] 前台化失败（pid ' + pid + '）：检查 系统设置 → 隐私与安全性 → 自动化');
			return ok;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		return false;
		#end
	}

	/** 进程是否存活（委托跨平台原语：macOS 用 `kill -0`，Windows 用 `tasklist`）。 */
	static function isProcessAlive(pid:Int):Bool
	{
		return ContainerProcess.isAlive(pid);
	}

	/** 目标引擎 pid（wrapper 写入 app.pid；未就绪返回 0）。 */
	public static function targetAppPid():Int
	{
		if (current == null) return 0;
		return ContainerLauncher.readAppPid(current);
	}

	/**
	 * 诊断埋点用：把当前会话的关键状态摊平成一行文本。
	 * bug 3（返回后 TitleState 不跳）需要区分“宿主失焦冻结”与“音乐时间源冻结”，
	 * 这两者在界面上看不出差别，只能靠日志里的数字判定。
	 */
	public static function diagSnapshot():String
	{
		if (current == null) return 'container=none';
		var logPath:String = ContainerStore.join(ContainerStore.ensureRuntimeDir(current), ContainerStore.LOG_NAME);
		return 'container=' + current.folder
			+ ' phase=' + Std.string(phase)
			+ ' hostFocused=' + hostFocused
			+ ' hidden=' + hidden
			+ ' activated=' + activated
			+ ' quitRequested=' + quitRequested
			+ ' hostPid=' + hostPid
			+ ' targetPid=' + ContainerLauncher.readAppPid(current)
			+ ' log=' + logPath;
	}

	static function exitFileExists():Bool
	{
		if (current == null) return false;
		return ContainerStore.fileExists(ContainerStore.runtimeFile(current, ContainerStore.EXIT_NAME));
	}

	/**
	 * 退出核对：确认目标引擎**进程本身**已经结束，才允许收尾复位。
	 *
	 * 为什么需要：`exit.txt` 是包装器写的，只能证明「包装器认为目标退出了」。
	 *  - macOS：wrapper 是 `wait $ME_APP` 之后才写退出码，语义可靠，本函数直接放行（不做额外开销）。
	 *  - Windows：`wrapper.bat` 依赖 `start /WAIT` 阻塞语义。万一它没按预期阻塞（cmd 版本差异、
	 *    目标是被「重定向到一个已在运行的实例」吸收等），退出码会在目标仍在跑时就写下来，
	 *    宿主若立刻收尾就会把目标进程变成**孤儿窗口**（玩家看到 Meteoric 回来了、目标还在前台）。
	 *
	 * 判定策略（只信任「进程已不存在」，绝不信任时间）：
	 *  1. pid 未知（0）⇒ 无从核对，放行（保守：宁可相信 wrapper，也不做无谓等待）；
	 *  2. 进程已不存在 ⇒ 放行；
	 *  3. 仍在跑 ⇒ 等待，最长 EXIT_GRACE 秒；
	 *  4. 超时仍活 ⇒ 记录并 `taskkill /F /T`（连同子进程），再给一小段收尸时间，然后放行。
	 *
	 * 每次等待都会 `return false`，让状态机下一帧再进来 —— 宿主在 Windows 上不挂起，
	 * 帧循环照常跑，所以「等待」就是几帧的空转，不会卡住。
	 */
	static function targetReallyGone(elapsed:Float):Bool
	{
		#if windows
		if (current == null) return true;

		var pid:Int = ContainerLauncher.readAppPid(current);
		if (pid <= 0) return true; // 未知 ⇒ 放行

		if (!ContainerProcess.isAlive(pid)) return true; // 真的退了

		exitSeenTimer += elapsed;

		if (!forceKilled && exitSeenTimer >= EXIT_GRACE)
		{
			forceKilled = true;
			var ok:Bool = ContainerLauncher.forceKill(current);
			ContainerLauncher.log(current, 'target still alive (pid ' + pid + ') after exit.txt; forceKill='
				+ ok + '（可能是 start /WAIT 未阻塞或退出码提前落盘）');
		}

		// 强杀后再给两帧收尸；否则本帧就把状态机带进收尾，界面会先回来、目标残影还在前台
		if (exitSeenTimer >= EXIT_GRACE + 0.1) return true;
		return false;
		#else
		return true;
		#end
	}

	static function toPhase(p:Phase):Void
	{
		phase = p;
		phaseTimer = 0;
	}

	/** 校验容器是否可启动（界面按钮启用态用）。 */
	public static function isReady(info:ContainerInfo):Bool
	{
		return info != null && info.problem == null && info.appPath != null;
	}

	/** 供界面显示的一行状态。 */
	public static function statusLine():String
	{
		if (!active) return '空闲';
		var name:String = (current != null) ? current.displayName : '?';
		return switch (phase)
		{
			case Phase.Launching: '正在启动「' + name + '」…（' + waitSeconds + 's 后让位）';
			case Phase.Hiding: '正在为「' + name + '」让位（隐藏宿主窗口）…';
			case Phase.Stopping: '正在挂起 Meteoric（' + name + ' 即将独占窗口）…';
			case Phase.Running: '「' + name + '」运行中' + (quitRequested ? '（正在退出…）' : '');
			case Phase.Returning: '正在返回 Meteoric…';
			case Phase.Idle: '空闲';
		}
	}
}
