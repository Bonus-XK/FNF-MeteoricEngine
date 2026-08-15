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
	// ---------- 安卓外部存储初始化：/sdcard/meteoric（assets + mods） ----------
	var _storageLabel:openfl.text.TextField;
	var _storageError:Bool = false;
	var _storageWaitFrames:Int = 0;

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

		// Android 10：先请求旧存储权限（弹窗）；Android 11+ 弹窗会被系统忽略，随后走"所有文件访问"引导
		backend.AndroidStorage.requestLegacyPermissions();
		var err = backend.AndroidStorage.ensureDirs();
		if (err == null)
		{
			backend.AndroidStorage.startCopyAssets();
		}
		else
		{
			_storageError = true;
			_storageWaitFrames = 180; // 等 3 秒，给用户点权限弹窗的时间
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

		// 权限未就绪：先等权限弹窗，再引导"所有文件访问"
		if (_storageWaitFrames > 0)
		{
			_storageWaitFrames--;
			_storageLabel.text = '请在弹窗中允许存储权限...';
			var err = st.ensureDirs();
			if (err == null)
			{
				_storageError = false;
				st.startCopyAssets();
			}
			return;
		}

		var err2 = st.ensureDirs();
		if (err2 == null)
		{
			_storageError = false;
			st.startCopyAssets();
			return;
		}

		_storageLabel.text = '无法访问 ' + st.root() + '（' + err2 + '）\n\n'
			+ '请在系统设置中为本应用授予“所有文件访问”权限（Android 11+），\n'
			+ '授权后回到游戏会自动继续。';
		if (!_storageError)
		{
			_storageError = true;
			st.openStorageSettings();
		}
	}
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
