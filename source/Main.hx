package;

import flixel.graphics.FlxGraphic;

import backend.CrashHandler;

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
		framerate: 120, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPS;

	public static var meVersion:String = '1.1.0';
	public static var meVersionIndex:Int = 1;
	// You can pretty much ignore everything from here on - your code should go in your states.

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
			// 已授权：直接用公共根目录；失败再回退
			var err = st.tryEnsureRootDirs();
			if (err != null && !st.usingFallback())
			{
				st.enableFallback();
				err = st.tryEnsureRootDirs();
			}
			if (err == null)
			{
				// 若此前数据在应用专属目录（升级用户），整体迁到根目录（mods/assets 一并带走）
				st.migrateFromFallback();
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
					+ '正在打开系统设置...';
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
			// 授权成功（设置页返回 / 弹窗授权）：切公共根目录，迁移旧数据，开始复制
			st.enableFallbackOff();
			var err = st.tryEnsureRootDirs();
			if (err == null)
			{
				st.migrateFromFallback();
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
				_storageLabel.text = '未获得存储权限，改用应用专用目录：\n' + st.root()
					+ '\n（下次可在系统设置允许"所有文件访问"后使用根目录 .meteoric）';
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
			backend.ModInstaller.get().onDropFile(file);
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

		// Performance optimizations
		FlxG.fixedTimestep = false;
		openfl.Lib.current.stage.frameRate = 120;

		// FPS 计数器：所有平台都创建，安卓/iOS 同样显示（标题栏模式仅在桌面端生效）
		fpsVar = new FPS(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		if(fpsVar.speedTxt != null) {
			addChild(fpsVar.speedTxt);
		}
		if(fpsVar != null) {
			fpsVar.applyDisplayMode();
		}
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

}
