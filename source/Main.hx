package;

import flixel.graphics.FlxGraphic;

import backend.CrashHandler;
import backend.ClientPrefs;

import flixel.FlxGame;
import flixel.FlxState;
import openfl.Assets;
import openfl.Lib;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;
#if mobile
import flixel.input.touch.FlxTouch;
#end

class Main extends Sprite
{
	var game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		zoom: -1.0, // game state bounds
		// ⚠ 启动帧率按平台分（2026-09-11 实测事故：Windows 黑屏卡在加载界面）：
		//   这个值是**首帧就生效**的初始帧率，早于 ClientPrefs.loadPrefs() → applyFramerate()。
		//   100000 哨兵意味着 framePeriod = 0.01ms，只有当原生帧循环的 `nextUpdate` 是浮点
		//   （ci/lime-sdl3-patch 那道墙钟补丁）时才安全 —— 否则 `nextUpdate += framePeriod`
		//   被整型截断成 +0、catch-up 循环永不前进 → 主线程 100% 死循环、卡在黑屏加载界面
		//   （Preloader 阶段就已发生，改设置里的默认值来不及）。
		//   · macOS  —— 构建后恢复 tools/lime.ndll.wallclock 保证补丁在位 → 100000；
		//   · Windows —— 不再靠"假定 ndll 有补丁"，而是启动时探测原生能力标记：
		//                补丁版 ndll 给 100000，老 ndll 回退 1000（老 ndll 上实测安全上限）。
		//                这是"加标记 + 启动自检"的落点，取代了此前"Windows 一律 120"的硬编码。
		//   注意：ClientPrefs 的静态字段此时已初始化（Haxe 静态初始化先于本类的实例化），
		//   所以第 365 行把它同时用于 update/draw 帧率时，两侧取值一致、不会触发 flixel 的
		//   "update 帧率不应小于 draw 帧率" 警告。
		framerate: #if mac 100000 #elseif windows ClientPrefs.unlimitedFramerateValue() #else 120 #end,
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPS;

	public static var meVersion:String = '1.2.0';
	// 版本校验码：与仓库根目录 gitVersion.txt 第 2 行对应（1.1.3 = 4）。
	// 更新判定见 TitleState.checkForUpdates()：远端索引 **大于** 本值才弹更新界面。
	// （预览更新界面时把它临时改成 1 即可，改完记得还原——2026-09-12 用过一次。）
	public static var meVersionIndex:Int = 4;
	// 引擎关闭动画状态（仅桌面目标使用；移动端不启用、设置页也不显示）
	static var allowWindowClose:Bool = false;
	static var closeAnimStarted:Bool = false;
	// You can pretty much ignore everything from here on - your code should go in your states.

	#if desktop
	/**
	 * 多版本容器：每帧驱动 ContainerSession。
	 *
	 * 为什么挂在 ENTER_FRAME（Sprite 级）而不是某个 state 的 update：
	 *  - 宿主被 kill -STOP 挂起期间画面循环整体停摆，唤醒后第一帧就要接管收尾；
	 *  - 容器可以从任意界面启动（主菜单/设置/容器界面），state 会随整机重启被销毁，
	 *    只有贯穿整个进程生命周期的监听才靠得住。
	 * 空闲时（无会话）就是一次 static 布尔判空立即返回，不产生任何分配。
	 */
	static function onContainerFrame(_):Void
	{
		if (!backend.ContainerSession.active) return;
		try
		{
			// 状态机只用它做“等 0.4s / 0.35s”这类粗计时，且容器会话是秒级动作，
			// 固定步长即可（挂起期间进程被 STOP，墙钟时间不参与累计，不需要真实 elapsed）。
			backend.ContainerSession.tick(1 / 60);
		}
		catch (e:Dynamic)
		{
			// 会话异常绝不允许逃进 lime/SDL 事件分发（会变成无日志闪退）
			trace('[Container] tick error: ' + Std.string(e));
		}
	}
	#end

	#if mobile
	// 触摸上下滑 → 合成滚轮事件：让所有基于 FlxG.mouse.wheel 的列表滚动在触屏上直接可用
	static var _touchScrollID:Int = -1;
	static var _touchScrollY:Float = -1;
	static var _touchScrollAccum:Float = 0;
	static var _touchSession:Bool = false;
	static var _touchMoved:Float = 0;

	static function processTouchScroll():Void
	{
		if (FlxG.touches == null) return;
		if (FlxG.touches.list.length == 0)
		{
			// 手指全部离开：结束本次按压会话（拖拽状态保留到释放帧结束，供点击判定使用）
			_touchScrollID = -1;
			_touchScrollY = -1;
			_touchScrollAccum = 0;
			_touchSession = false;
			_touchMoved = 0;
			return;
		}

		var touch:FlxTouch = null;
		for (t in FlxG.touches.list)
			if (t.pressed) { touch = t; break; }

		if (touch == null)
		{
			// 释放帧：触摸仍在列表中（justReleased），保留会话供本帧点击判定
			return;
		}

		var y:Float = touch.screenY;
		if (touch.touchPointID != _touchScrollID || _touchScrollY < 0)
		{
			_touchSession = true;
			_touchScrollID = touch.touchPointID;
			_touchScrollY = y;
			_touchScrollAccum = 0;
			_touchMoved = 0;
			return;
		}

		var dy:Float = y - _touchScrollY;
		_touchMoved += Math.abs(dy);
		_touchScrollAccum += dy;
		_touchScrollY = y;

		// 每滑动 45 逻辑像素触发一格滚轮（下滑 = 下一个选项，上滑 = 上一个选项）
		var step:Float = 45;
		while (_touchScrollAccum > step)
		{
			_touchScrollAccum -= step;
			dispatchTouchWheel(-1);
		}
		while (_touchScrollAccum < -step)
		{
			_touchScrollAccum += step;
			dispatchTouchWheel(1);
		}
	}

	static function dispatchTouchWheel(delta:Int):Void
	{
		if (FlxG.stage != null)
			FlxG.stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_WHEEL, true, false, 0, 0, null, false, false, false, false, delta));
	}

	// 本次按压是否为滑动（位移超过阈值）：界面层用来区分“点击”与“拖动滚动”，避免拖动误触发选择
	public static function touchWasDragging():Bool
	{
		return _touchSession && _touchMoved > 14;
	}
	#end

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();

		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		#if android
		setupAndroidStorage();
		#else
		setupGame();
		#end
	}

	#if android
	// ---------- 安卓外部存储初始化：/sdcard/.meteoric（assets + mods） ----------
	// 权限决策链（Android 10 旧 WRITE / Android 11+ "所有文件访问"）：
	//   已授权 → 直接尝试公共根目录 /sdcard/.meteoric（失败才回退）；
	//   未授权 → Android 10 弹旧权限框；Android 11+ 跳"所有文件访问"设置页；
	//           等待授权（10 秒），成功 → 公共根目录 + 自动迁移旧数据；
	//           超时/拒绝 → 提示后回退到应用专属目录继续（不卡死）。
	var _storageLabel:openfl.text.TextField;
	var _storageError:Bool = false;
	var _storageWaitFrames:Int = 0;
	var _storageGuideShown:Bool = false; // 本会话已引导过权限页（避免反复跳转）

	function setupAndroidStorage():Void
	{
		_storageLabel = new openfl.text.TextField();
		_storageLabel.width = Lib.current.stage.stageWidth;
		_storageLabel.height = Lib.current.stage.stageHeight;
		_storageLabel.multiline = true;
		_storageLabel.selectable = false;
		_storageLabel.defaultTextFormat = new openfl.text.TextFormat('', 26, 0xFFFFFF, true);
		_storageLabel.text = '正在准备 ' + backend.AndroidStorage.root() + ' ...';
		addChild(_storageLabel);

		var st = backend.AndroidStorage;

		if (st.hasStoragePermission())
		{
			// 已具备真实写权限：若此前数据在应用专属目录（回退/升级用户），
			// 必须先整体迁移再建目录——否则 tryEnsureRootDirs 先建出公共目录，
			// migrateFromFallback 会因"目标已存在"跳过，mods/assets 就永远搬不上来。
			st.migrateFromFallback();
			var err = st.tryEnsureRootDirs();
			if (err != null && !st.usingFallback())
			{
				st.enableFallback();
				err = st.tryEnsureRootDirs();
			}
			if (err == null)
			{
				st.startCopyAssets();
			}
			else
			{
				_storageError = true;
				_storageLabel.text = '无法访问存储（' + err + '）';
			}
		}
		else
		{
			// 未授权：进入权限引导阶段（Android 10 弹窗 / 11+ 跳设置页），等待轮询
			_storageError = true;
			_storageWaitFrames = 600; // 10 秒等待授权
			if (st.isAndroid11Plus())
			{
				_storageLabel.text = '需要"所有文件访问"权限\n'
					+ '授权后即可把 Mod 直接放进手机根目录的 .meteoric/mods 文件夹\n'
					+ '正在打开系统设置...\n\n'
					+ '若未自动跳转，请手动：系统设置 → 应用 → 本应用 → 权限 → 所有文件访问\n'
					+ '（部分机型在"特殊应用权限"里，请在应用详情页开启）';
				st.openStorageSettings();
			}
			else
			{
				_storageLabel.text = '请在弹窗中允许存储权限...';
				st.requestLegacyPermissions();
			}
		}
		addEventListener(Event.ENTER_FRAME, onAndroidStorageFrame);
	}

	function onAndroidStorageFrame(_):Void
	{
		var st = backend.AndroidStorage;
		if (!_storageError)
		{
			st.copyAssetsStep(); // 主线程分批复制
			if (st.copyFinished())
			{
				// 复制完成（或已跳过全部）：进入游戏
				removeEventListener(Event.ENTER_FRAME, onAndroidStorageFrame);
				removeChild(_storageLabel);
				_storageLabel = null;
				setupGame();
				return;
			}

			var pct = Math.round(st.copyPercent() * 100);
			_storageLabel.text = '正在复制游戏资源到 ' + st.root() + '/assets ...\n'
				+ pct + '%（' + st.copyDoneCount() + '/' + st.copyTotal() + '）\n\n'
				+ '首次启动需要复制资源，完成后会直接读取外部目录，方便替换/添加素材。';
			return;
		}

		// ---- 权限等待阶段：每帧检查授权结果 ----
		if (st.hasStoragePermission())
		{
			// 授权成功（设置页返回 / 弹窗授权）：先迁移旧数据再切公共根目录（顺序不可反）
			st.enableFallbackOff();
			st.migrateFromFallback();
			var err = st.tryEnsureRootDirs();
			if (err == null)
			{
				_storageError = false;
				st.startCopyAssets();
				return;
			}
			// 公共目录仍失败：保持现状（下面走超时/回退逻辑）
		}

		if (_storageWaitFrames > 0)
		{
			_storageWaitFrames--;
			if (st.isAndroid11Plus())
				_storageLabel.text = '等待"所有文件访问"授权...\n'
					+ '完成后把 Mod 放进手机根目录 .meteoric/mods 即可\n'
					+ '（返回游戏自动继续）';
			else
				_storageLabel.text = '请在弹窗中允许存储权限...';
			return;
		}

		// ---- 超时/用户拒绝：提示后回退到应用专属目录，不卡死 ----
		if (!st.usingFallback())
		{
			st.enableFallback();
			var err = st.tryEnsureRootDirs();
			if (err == null)
			{
				_storageError = false;
				_storageLabel.text = '未获得"所有文件访问"权限，已改用应用专用目录：\n' + st.root()
					+ '\n\n授权方法：系统设置 → 应用 → 本应用 → 权限 → 所有文件访问\n'
					+ '（部分机型在"特殊应用权限"里）\n'
					+ '授权后重启游戏，会自动把 Mod 与资源迁移到根目录 .meteoric。';
				try { extension.androidtools.widget.Toast.makeText('未获权限，使用应用专用目录', 0); } catch (e:Dynamic) {}
				st.startCopyAssets();
				return;
			}
		}
		_storageLabel.text = '无法访问存储目录\n请在系统设置中为本应用授予"所有文件访问"权限（Android 11+），\n授权后回到游戏会自动继续。';
		if (!_storageGuideShown)
		{
			_storageGuideShown = true;
			st.openStorageSettings();
		}
	}
	#end

	#if sys
	// ---------- 拖入 zip / 文件夹安装 mod ----------
	// 闭包存为字段：传给 lime C++ 事件（onDropFile）的 Haxe 闭包若没有本侧强引用，
	// 会被 GC 回收导致 C++ 侧悬垂（malloc free 崩溃）。
	var _dropHandler:String->Void;
	#end

	private function setupGame():Void
	{
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		#if mobile
		// 移动端：首次 surface 尺寸可能还没定型（旋转/系统栏未隐藏），
		// 固定 16:9 逻辑分辨率，交给 flixel 等比缩放适配任意屏幕，避免界面偏移。
		game.zoom = 1.0;
		game.width = 1280;
		game.height = 720;
		#else
		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = stageHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(stageHeight / game.zoom);
		}
		#end
	
		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		var flxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen);
		addChild(flxGame);

		#if sys
		// ---- 拖入 zip / 文件夹安装 mod（SDL 拖放 → lime window.onDropFile → ModInstaller） ----
		// 闭包存字段（_dropHandler）：lime C++ 事件持有时 Haxe 侧无引用会被 GC 回收 → 悬垂 free 崩溃
		_dropHandler = function(file:String)
		{
			try
			{
				backend.ModInstaller.get().onDropFile(file);
			}
			catch (e:Dynamic)
			{
				// 兜底：异常不允许逃进 lime C++ 事件分发（避免无弹窗闪退）
				trace('onDropFile handler error: ' + Std.string(e));
			}
		};
		try
		{
			stage.window.onDropFile.add(_dropHandler);
		}
		catch (e:Dynamic)
		{
			trace('onDropFile hook failed: ' + Std.string(e));
		}
		#end

		#if mobile
		// 移动端：显示尺寸变化（旋转、系统栏隐藏/显示）有时不触发 stage RESIZE，
		// 逐帧比对一次，变了就补发 RESIZE，让 flixel 走完整的重新等比居中流程。
		var lastStageW:Int = stageWidth;
		var lastStageH:Int = stageHeight;
		stage.addEventListener(Event.ENTER_FRAME, function(_)
		{
			var w:Int = Lib.current.stage.stageWidth;
			var h:Int = Lib.current.stage.stageHeight;
			if (w != lastStageW || h != lastStageH)
			{
				lastStageW = w;
				lastStageH = h;
				stage.dispatchEvent(new Event(Event.RESIZE));
			}
			processTouchScroll();
			#if desktop
			// Discord RPC 主线程 tick（替代原守护线程：子线程分配与主线程 GC 并发破坏堆）
			if (backend.DiscordClient.isInitialized)
				backend.DiscordClient.tick();
			#end
		});
		#end

		// 使用系统鼠标光标，而不是 Flixel 自绘光标
		FlxG.mouse.useSystemCursor = true;

		#if desktop
		// ---- 多版本容器会话钩子 ----
		// 容器启动后宿主会被 SIGSTOP 挂起，唤醒后的第一帧必须立刻接上状态机收尾
		// （恢复窗口尺寸 + kill -CONT + 整机重启）。用 ENTER_FRAME 而不是 FlxG.state.update：
		// 会话可能在任何状态（含暂停菜单、加载界面）被唤醒，画面循环才是唯一稳定的锚点。
		// 注意：此处（init 早期）FlxG.stage 可能尚未就绪，挂到本 Sprite 自己的 stage 上，
		// 与文件末尾 startCloseAnimation 的 stage.addEventListener 同款，必然可用。
		stage.addEventListener(Event.ENTER_FRAME, onContainerFrame);
		#end

		// Performance optimizations
		FlxG.fixedTimestep = false;
		// 【帧数上限已移除】不再硬编码 stage.frameRate = 120。
		// flixel 5.2.2 会在 create()/onFocus() 自动执行 stage.frameRate = FlxG.drawFramerate，
		// 桌面端 drawFramerate 由上方配置为 100000（仅作“无人工限制”哨兵）→ SDL 帧循环走
		// 墙钟自调度（ci/lime-sdl3-patch：HiResMs + WaitEventTimeout + SDL_DelayNS/spin，
		// nextUpdate/currentUpdate/lastUpdate 全 double，无定时器 1ms 地板、无事件洪泛、
		// 无整数截断死循环），帧数只由 CPU/GPU 渲染提交决定（实测 Retina 2x 前台 4000~12000）；
		// 移动端保持 120，避免高帧导致发热/耗电问题。

		// FPS 计数器：所有平台都创建，安卓/iOS 同样显示（标题栏模式仅在桌面端生效）
		fpsVar = new FPS(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		if(fpsVar.speedTxt != null) {
			addChild(fpsVar.speedTxt);
		}
		if(fpsVar != null) {
			fpsVar.applyDisplayMode();
		}

		// FPS 波动图功能已移除（曾因渲染/数据口径问题反复调试，删除避免持续困扰）
		
		#if desktop
		// F3 已释放（FPS 波动图移除后不再占用）
		#end

		#if !mobile
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end
		
		#if CRASH_HANDLER
		CrashHandler.init();
		#elseif (cpp && !android)
		// 非 release 构建也安装原生信号处理器（栈落盘 native_stack.txt；Haxe 异常界面不启用）
		CrashHandler.installNativeHandlers();
		#end

		#if desktop
		DiscordClient.start();
		#end

		#if desktop
		// 引擎关闭动画：拦截窗口关闭（X / Alt+F4），按设置播完窗口变换动画后再真正关闭
		setupWindowCloseHandler();
		#end

		// shader coords fix
		FlxG.signals.gameResized.add(function (w, h) {
		     if (FlxG.cameras != null) {
			   for (cam in FlxG.cameras.list) {
				@:privateAccess
				if (cam != null && cam._filters != null)
					resetSpriteCache(cam.flashSprite);
			   }
		     }

		     if (FlxG.game != null)
			 resetSpriteCache(FlxG.game);
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void {
		@:privateAccess {
		        sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	// ═══════════════════════════════════════════════════════════════════
	// 引擎关闭动画（Seiun 融合移植）：
	//   拦截桌面窗口关闭（X 按钮 / Alt+F4 → lime window.onClose），按设置里的
	//   「引擎关闭动画 / 关闭动画样式 / 关闭动画速度」播放窗口变换动画，
	//   动画结束后才真正 window.close()。
	//   模组扩展：onCloseAnimStart(style,speed) / onCloseAnimUpdate(progress,style,speed)
	//   / onCloseAnimEnd(style)，经 PlayState 的 Lua+HScript 或菜单态 UI Lua 广播。
	//   注意：macOS 的 Cmd+Q / Dock 退出走 SDL_EVENT_QUIT，不经过 onClose，无法拦截。
	// ═══════════════════════════════════════════════════════════════════
	#if desktop
	static function setupWindowCloseHandler():Void
	{
		var window = Lib.application.window;
		if (window == null) return;

		window.onClose.add(function()
		{
			// 动画完成后的最终关闭：不再拦截，放行原生关闭
			if (allowWindowClose) return;

			// 设置未加载（极早期加载中）或总开关关闭：直接放行原生关闭
			if (ClientPrefs.data == null || !ClientPrefs.data.closeAnimEnabled) return;

			// 关闭动画播放中：拦截重复的关闭请求（防 Alt+F4 连按）
			if (closeAnimStarted)
			{
				window.onClose.cancel();
				return;
			}

			// 拦截本次原生关闭，先播动画，动画结束后再真正关闭
			window.onClose.cancel();
			startCloseAnimation(window);
		});
	}

	/**
	 * 从脚本返回值里取字段（Lua 表在非 JS 目标上会转成匿名对象，HScript 返回的对象也是匿名结构）。
	 * 取不到或解析失败时用 fallback。
	 */
	static function scriptNumField(obj:Dynamic, name:String, fallback:Float):Float
	{
		if (obj == null) return fallback;
		var v:Dynamic = null;
		try { v = Reflect.field(obj, name); } catch (e:Dynamic) { return fallback; }
		if (v == null) return fallback;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? fallback : f;
	}

	/**
	 * 模组扩展分发：调用当前状态的脚本钩子。
	 * - PlayState：Lua（callOnLuas）+ HScript（callOnHScript），返回值聚合（HScript 先、Lua 后，与 Seiun 一致）；
	 * - 菜单等 MusicBeatState：现有 UI Lua 脚本（callUIScripts）广播事件（无法返回值）。
	 */
	static function callCloseAnimScripts(func:String, args:Array<Dynamic>):Dynamic
	{
		var ret:Dynamic = null;
		var st = FlxG.state;
		if (st == null) return null;

		if (Std.isOfType(st, states.PlayState) && states.PlayState.instance != null)
		{
			#if HSCRIPT_ALLOWED
			var hxRet:Dynamic = states.PlayState.instance.callOnHScript(func, args);
			if (hxRet != null && hxRet != psychlua.FunkinLua.Function_Continue) ret = hxRet;
			#end
			#if LUA_ALLOWED
			var luaRet:Dynamic = states.PlayState.instance.callOnLuas(func, args);
			if (luaRet != null && luaRet != psychlua.FunkinLua.Function_Continue) ret = luaRet;
			#end
		}
		#if LUA_ALLOWED
		else if (Std.isOfType(st, backend.MusicBeatState))
			cast(st, backend.MusicBeatState).callUIScripts(func, args);
		#end
		return ret;
	}

	/**
	 * 关闭动画：按设置中的样式（squeeze/zoom/drop/slide）与速度倍率播放，
	 * 完成后才真正调用 window.close()。
	 * 使用主线程 ENTER_FRAME 驱动，不依赖 FlxG 的更新循环，
	 * 因此在暂停菜单等状态下按 Alt+F4 也能正常播放。
	 */
	static function startCloseAnimation(window:lime.ui.Window):Void
	{
		closeAnimStarted = true;

		var style:String = ClientPrefs.data.closeAnimStyle;
		var speed:Float = ClientPrefs.data.closeAnimSpeed;
		if (style == null || style.length == 0) style = 'squeeze';
		if (speed <= 0) speed = 1.0;

		// ── 模组扩展：onCloseAnimStart 可改样式 / 时长，或返回 "off" 直接关闭 ──
		var customDuration:Float = -1;
		var startRet:Dynamic = callCloseAnimScripts('onCloseAnimStart', [style, speed]);
		if (startRet != null && startRet != 0)
		{
			if (Std.isOfType(startRet, String))
				style = Std.string(startRet);
			else
			{
				var s:Dynamic = null;
				var d:Dynamic = null;
				try
				{
					s = Reflect.field(startRet, 'style');
					d = Reflect.field(startRet, 'duration');
				}
				catch (e:Dynamic) {}
				if (s != null) style = Std.string(s);
				if (d != null)
				{
					var dv:Float = Std.parseFloat(Std.string(d));
					if (!Math.isNaN(dv) && dv > 0) customDuration = dv;
				}
			}
		}

		// 未启用关闭动画（脚本要求 "off"）：直接关闭
		if (style == 'off')
		{
			callCloseAnimScripts('onCloseAnimEnd', [style]);
			allowWindowClose = true;
			window.close();
			return;
		}

		// 全屏时窗口尺寸无法正常缩放，先退回窗口模式再播动画
		if (window.fullscreen)
			window.fullscreen = false;

		// 以退出全屏后的实际尺寸为准（退出全屏会触发一次 resize）
		var startWidth:Int = window.width;
		var startHeight:Int = window.height;
		var centerX:Float = window.x + startWidth * 0.5;
		var centerY:Float = window.y + startHeight * 0.5;

		var minSize:Int = 1; // 避免缩到 0 导致渲染/系统异常

		// 基础时长（秒），除以速度倍率得到实际时长
		var durationH:Float = 0.30 / speed; // squeeze 高度段
		var durationW:Float = 0.35 / speed; // squeeze 宽度段
		var duration:Float = switch (style)
		{
			case 'zoom': 0.40 / speed;
			case 'drop': 0.50 / speed;
			case 'slide': 0.50 / speed;
			default: 0.40 / speed; // squeeze 外的未知样式（模组自定义）按缩放兜底
		}
		if (customDuration > 0) duration = customDuration / speed;

		var phase:Int = 0; // 0 = 高度，1 = 宽度
		var t0:Float = haxe.Timer.stamp();
		var stage = Lib.current.stage;
		if (stage == null) // 极端情况：没有舞台就直接关
		{
			allowWindowClose = true;
			window.close();
			return;
		}

		var onFrame:openfl.events.Event->Void = null;
		onFrame = function(_)
		{
			var elapsed:Float = haxe.Timer.stamp() - t0;
			var curDuration:Float = (style == 'squeeze') ? (phase == 0 ? durationH : durationW) : duration;
			var progress:Float = Math.min(1, elapsed / curDuration);
			// 快速起步、末尾放缓，让「压扁」显得干脆
			var eased:Float = progress * (2 - progress);

			var newWidth:Int = startWidth;
			var newHeight:Int = startHeight;
			var newX:Float = centerX - startWidth * 0.5;
			var newY:Float = centerY - startHeight * 0.5;

			var builtin:String = switch (style)
			{
				case 'squeeze': 'squeeze';
				case 'drop': 'drop';
				case 'slide': 'slide';
				default: 'zoom'; // 模组自定义样式兜底为缩放
			}
			switch (builtin)
			{
				case 'zoom':
					newWidth = Math.round(startWidth * (1 - eased));
					newHeight = Math.round(startHeight * (1 - eased));
					newX = centerX - newWidth * 0.5;
					newY = centerY - newHeight * 0.5;

				case 'drop':
					newWidth = Math.round(startWidth * (1 - eased));
					newHeight = Math.round(startHeight * (1 - eased));
					newX = centerX - newWidth * 0.5;
					// 下落：先慢后快的重力感
					var fall:Float = progress * progress;
					newY = centerY - newHeight * 0.5 + startHeight * fall * 1.2;

				case 'slide':
					newWidth = Math.round(startWidth * (1 - eased));
					newHeight = Math.round(startHeight * (1 - eased));
					newY = centerY - newHeight * 0.5;
					// 向左滑出屏幕
					newX = centerX - newWidth * 0.5 - startWidth * eased * 0.7;

				default: // squeeze：先压扁高度，再压扁宽度
					if (phase == 0)
					{
						newHeight = Math.round(startHeight * (1 - eased));
						newY = centerY - newHeight * 0.5;
					}
					else
					{
						newWidth = Math.round(startWidth * (1 - eased));
						newHeight = minSize;
						newX = centerX - newWidth * 0.5;
						newY = centerY - newHeight * 0.5;
					}
			}

			// ── 模组扩展：onCloseAnimUpdate 逐帧覆盖窗口变换 ──
			var overrideRet:Dynamic = callCloseAnimScripts('onCloseAnimUpdate', [progress, style, speed]);
			if (overrideRet != null && overrideRet != 0)
			{
				newWidth = Std.int(scriptNumField(overrideRet, 'width', newWidth));
				newHeight = Std.int(scriptNumField(overrideRet, 'height', newHeight));
				newX = scriptNumField(overrideRet, 'x', newX);
				newY = scriptNumField(overrideRet, 'y', newY);
			}

			if (newWidth < minSize) newWidth = minSize;
			if (newHeight < minSize) newHeight = minSize;

			window.width = newWidth;
			window.height = newHeight;
			window.x = Math.round(newX);
			window.y = Math.round(newY);

			if (progress >= 1)
			{
				if (style == 'squeeze' && phase == 0)
				{
					// 高度压扁完成，进入宽度段
					phase = 1;
					t0 = haxe.Timer.stamp();
					window.height = minSize;
				}
				else
				{
					stage.removeEventListener(Event.ENTER_FRAME, onFrame);
					callCloseAnimScripts('onCloseAnimEnd', [style]);
					allowWindowClose = true;
					window.close();
				}
			}
		};

		stage.addEventListener(Event.ENTER_FRAME, onFrame);
	}
	#end

}
