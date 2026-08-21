package objects;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxTileFrames;
import flixel.group.FlxSpriteGroup;
import flixel.input.touch.FlxTouch;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flash.geom.Point;
import openfl.Lib;
import openfl.events.KeyboardEvent;
import openfl.events.TouchEvent;
import openfl.utils.Assets;
import backend.ClientPrefs;
import backend.Paths;
import flixel.input.keyboard.FlxKey;
import states.PlayState;

/**
 * 移动端触控板（融合 Psych Engine Mobile 的虚拟按键）：
 * 布局模式（保存于 ClientPrefs.data.mobileControlsMode）：
 *   0 = 右手按键（Psych RIGHT_FULL）
 *   1 = 左手按键（Psych LEFT_FULL）
 *   2 = 自定义布局（右手布局 + 保存的按键位置，可在设置里拖动调整）
 *   3 = 双手按键（Psych BOTH_FULL）
 *   4 = 全屏判定区（Psych HITBOX：四等分全屏列）
 *   5 = 无按键（仅键盘/外设）
 * 暂停/返回角落按钮保持本引擎原有设计。
 *
 * 输入判定保留本引擎已验证的修复：
 *   - 物理坐标 -> 逻辑坐标换算（与 FlxTouch 一致，除以 scaleMode 缩放）
 *   - 底层 stage TouchEvent 捕获兜底（掉帧导致 flixel 丢失触摸时仍能点按）
 * 不再使用 Psych 原版 FlxButton 的 flixel 触摸命中（掉帧时会整段吞键）。
 */
class MobileControls extends FlxSpriteGroup
{
	public static var instance:MobileControls = null;

	public static final MODE_RIGHT:Int = 0;
	public static final MODE_LEFT:Int = 1;
	public static final MODE_CUSTOM:Int = 2;
	public static final MODE_BOTH:Int = 3;
	public static final MODE_HITBOX:Int = 4;
	public static final MODE_KEYBOARD:Int = 5;

	// Psych 虚拟按键尺寸（virtualpad.png 每格 132x127）
	public static final BTN_W:Float = 132;
	public static final BTN_H:Float = 127;

	// 角落按钮边长
	static final CORNER_SIZE:Float = 110;

	// 方向键 -> Psych 贴图名
	static final PAD_GRAPHICS:Map<String, String> = [
		'note_left' => 'left', 'note_down' => 'down', 'note_up' => 'up', 'note_right' => 'right'
	];

	// 自定义模式保存顺序（固定顺序：左 下 上 右）
	public static final CUSTOM_ORDER:Array<String> = ['note_left', 'note_down', 'note_up', 'note_right'];

	/** 渲染与命中判定使用的相机（PlayState 里是 camHUD；设置预览里是主相机） */
	public var controlCam:FlxCamera;
	/** 是否为设置界面的预览实例（不注册为全局 instance，不参与 Controls） */
	public var previewMode:Bool = false;
	/** 是否为菜单模式：只显示 A/B 虚拟按键，不显示游玩方向键 */
	public var menuMode:Bool = false;

	/** 每个控制键对应的按键精灵（BOTH 模式下每个键有两个） */
	public var padButtons:Map<String, Array<FlxSprite>> = [];

	// 滑键支持：记录每个触摸点当前所在按键，用于“不松手滑到另一个键也判定按下”
	var _touchLastKey:Map<Int, String> = new Map();

	var pauseZone:FlxSprite;
	var backZone:FlxSprite;
	var hitboxMode:Bool = false;

	public function new(?registerAsInstance:Bool = true, ?cam:FlxCamera = null, ?modeOverride:Int = -1, ?menuMode:Bool = false)
	{
		super();
		if (registerAsInstance) instance = this;
		previewMode = !registerAsInstance;
		this.menuMode = menuMode;
		scrollFactor.set();
		controlCam = cam != null ? cam : (PlayState.instance != null ? PlayState.instance.camHUD : FlxG.camera);
		cameras = [controlCam];
		clearTapQueue();
		buildControls(modeOverride >= 0 ? modeOverride : getMode());
		installTapCapture();
	}

	function buildControls(mode:Int):Void
	{
		hitboxMode = (mode == MODE_HITBOX);
		if (menuMode)
		{
			buildMenuButtons();
			return;
		}
		switch (mode)
		{
			case MODE_RIGHT:
				buildDpad(false);
			case MODE_LEFT:
				buildDpad(true);
			case MODE_CUSTOM:
				buildDpad(false, true);
			case MODE_BOTH:
				buildDpad(true);
				buildDpad(false, false, true);
			case MODE_HITBOX:
				buildHitbox();
			case MODE_KEYBOARD:
				// 无触控按键
		}
		if (!previewMode)
			buildCorners();
	}

	// ---- Psych 方向键布局（坐标取自 Psych FlxVirtualPad）----

	function buildDpad(leftSide:Bool, custom:Bool = false, secondary:Bool = false):Void
	{
		var positions:Array<Array<Float>> = leftSide
			? [[0, FlxG.height - 243], [105, FlxG.height - 135], [105, FlxG.height - 345], [207, FlxG.height - 243]]
			: [[FlxG.width - 384, FlxG.height - 309], [FlxG.width - 258, FlxG.height - 201], [FlxG.width - 258, FlxG.height - 408], [FlxG.width - 132, FlxG.height - 309]];

		if (custom)
		{
			var saved:Array<Array<Float>> = getCustomPositions();
			if (saved != null && saved.length >= 4)
				for (i in 0...4)
					positions[i] = [FlxMath.bound(saved[i][0], 0, FlxG.width - BTN_W), FlxMath.bound(saved[i][1], 0, FlxG.height - BTN_H)];
		}

		for (i in 0...4)
		{
			var key:String = CUSTOM_ORDER[i];
			var spr:FlxSprite = makePadSprite(PAD_GRAPHICS.get(key), arrowColor(i));
			spr.x = positions[i][0];
			spr.y = positions[i][1];
			add(spr);
			if (!padButtons.exists(key)) padButtons.set(key, []);
			padButtons.get(key).push(spr);
		}
	}

	// 菜单模式：A（确认）+ B（取消/返回）键
	function buildMenuButtons():Void
	{
		var aBtn:FlxSprite = makePadSprite('a', 0xFF7CFC8A);
		aBtn.x = FlxG.width - BTN_W - 20;
		aBtn.y = FlxG.height - BTN_H - 20;
		add(aBtn);
		if (!padButtons.exists('accept')) padButtons.set('accept', []);
		padButtons.get('accept').push(aBtn);

		var bBtn:FlxSprite = makePadSprite('b', 0xFFFC7C7C);
		bBtn.x = aBtn.x - BTN_W - 20;
		bBtn.y = aBtn.y;
		add(bBtn);
		if (!padButtons.exists('back')) padButtons.set('back', []);
		padButtons.get('back').push(bBtn);
	}

	/** 供 Freeplay 等界面额外添加 virtualpad 风格字母键（如 L / P） */
	public function addMenuButton(key:String, label:String, x:Float, y:Float, ?color:Int = 0xFFAAAAAA):Void
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(BTN_W), Std.int(BTN_H), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, BTN_W, BTN_H, 16, 16, color);
		spr.immovable = true;
		add(spr);

		var txt:FlxText = new FlxText(0, 0, 0, label, 44);
		txt.font = Paths.font('vcr.ttf');
		txt.color = FlxColor.WHITE;
		txt.borderStyle = FlxTextBorderStyle.OUTLINE;
		txt.borderColor = FlxColor.BLACK;
		txt.borderSize = 2;
		txt.screenCenter();
		txt.x = spr.x + (spr.width - txt.width) / 2;
		txt.y = spr.y + (spr.height - txt.height) / 2;
		add(txt);

		if (!padButtons.exists(key)) padButtons.set(key, []);
		padButtons.get(key).push(spr);
	}

	/** 供调试界面添加 virtualpad 左右箭头贴图（key 传 ui_left/ui_right 等） */
	public function addPadArrow(key:String, graphic:String, x:Float, y:Float, ?color:Int = 0xFFFFFFFF):Void
	{
		var spr:FlxSprite = makePadSprite(graphic, color);
		spr.x = x;
		spr.y = y;
		add(spr);
		var realKey:String = normalizeKey(key);
		if (!padButtons.exists(realKey)) padButtons.set(realKey, []);
		padButtons.get(realKey).push(spr);
	}

	// 全屏判定区：四等分列，按下时高亮
	function buildHitbox():Void
	{
		var colW:Float = FlxG.width / 4;
		for (i in 0...4)
		{
			var key:String = CUSTOM_ORDER[i];
			var spr:FlxSprite = new FlxSprite(colW * i, 0).makeGraphic(Std.int(colW), FlxG.height, 0x66FFFFFF);
			spr.solid = false;
			spr.immovable = true;
			spr.moves = false;
			spr.scrollFactor.set();
			spr.color = arrowColor(i);
			spr.alpha = 0.10;
			add(spr);
			padButtons.set(key, [spr]);
		}
	}

	// ---- 视觉 ----

	/** 创建 virtualpad 样式按键贴图（公开静态：供结算/回放列表等轻量界面直接复用，不挂实例） */
	public static function makePadSprite(graphic:String, color:Int):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite();
		try
		{
			// virtualpad.png 每个箭头 396x127，切成 3 帧（普通/高亮/按下），只取普通与按下帧
			spr.frames = FlxTileFrames.fromFrame(
				FlxAtlasFrames.fromSparrow(Assets.getBitmapData('assets/mobile/virtualpad.png'), Assets.getText('assets/mobile/virtualpad.xml')).getByName(graphic),
				FlxPoint.get(BTN_W, BTN_H));
			spr.resetSizeFromFrame();
		}
		catch (e:Dynamic)
		{
			// 贴图缺失兜底：纯色方块，保证按键仍可点
			spr.makeGraphic(Std.int(BTN_W), Std.int(BTN_H), 0x66FFFFFF);
		}
		spr.solid = false;
		spr.immovable = true;
		spr.moves = false;
		spr.scrollFactor.set();
		spr.color = color;
		spr.alpha = 0.75;
		return spr;
	}

	function arrowColor(i:Int):Int
	{
		if (ClientPrefs.data != null && ClientPrefs.data.arrowRGB != null && ClientPrefs.data.arrowRGB[i] != null)
			return ClientPrefs.data.arrowRGB[i][0];
		return 0xFFFFFFFF;
	}

	function buildCorners():Void
	{
		pauseZone = makeZone(FlxG.width - CORNER_SIZE, 0, CORNER_SIZE, CORNER_SIZE, 0x22FFFFFF);
		backZone = makeZone(0, 0, CORNER_SIZE, CORNER_SIZE, 0x22FFFFFF);
		makeCornerLabel(pauseZone, 'II');
		makeCornerLabel(backZone, 'X');
	}

	function makeZone(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), color);
		spr.immovable = true;
		add(spr);
		return spr;
	}

	function makeCornerLabel(zone:FlxSprite, text:String):Void
	{
		var label:FlxText = new FlxText(0, 0, 0, text, Math.floor(CORNER_SIZE * 0.5));
		label.font = Paths.font('vcr.ttf');
		label.alpha = 0.6;
		label.screenCenter();
		label.x = zone.x + (zone.width - label.width) / 2;
		label.y = zone.y + (zone.height - label.height) / 2;
		add(label);
	}

	// ---- 模式持久化（Psych 兼容）----

	public static function getMode():Int
	{
		#if mobile
		if (ClientPrefs.data != null) return ClientPrefs.data.mobileControlsMode;
		#end
		return MODE_RIGHT;
	}

	public static function setMode(mode:Int):Void
	{
		#if mobile
		if (ClientPrefs.data != null)
		{
			ClientPrefs.data.mobileControlsMode = mode;
			ClientPrefs.saveSettings();
		}
		#end
	}

	public static function saveCustomPositions(positions:Array<Array<Float>>):Void
	{
		FlxG.save.data.mobilePadButtons = positions;
		FlxG.save.flush();
	}

	public static function getCustomPositions():Array<Array<Float>>
	{
		var saved:Dynamic = FlxG.save.data.mobilePadButtons;
		if (saved is Array && saved.length >= 4) return saved;
		return null;
	}

	// ---- 底层触摸捕获（flixel 触摸在游戏掉帧时会整段丢失）----
	// 直接监听 stage 的 TouchEvent：只要系统把事件发到应用，即使 down+up 落在同一帧间隔内、
	// 甚至 flixel 已把触摸对象清理掉，点按也不会丢。只记录“快速点按”
	// （按下→抬起时间短、位移小），避免把长按/滑动误判成点按。
	static final TAP_MAX_MS:Int = 400;
	static final TAP_MAX_MOVE:Float = 40;
	static var _tapDown:Map<Int, FlxPoint> = new Map<Int, FlxPoint>();
	static var _tapDownTime:Map<Int, Int> = new Map<Int, Int>();
	static var _tapQueue:Array<QueuedTap> = [];
	// stage 级拖动跟踪（结算/回放列表等界面滚动用，不依赖 FlxG.touches/鼠标模拟）
	static var _dragID:Int = -1;
	static var _dragLastY:Float = 0;
	static var _dragAccum:Float = 0;
	static var _dragSteps:Int = 0;
	// ---- 安卓滑键（stage 级触摸跟踪，不依赖 FlxG.touches）----
	// 手指按住不放从一个按键滑到另一个按键时，按键判定跟随触点：
	// 触点当前所在按键 = 按住（pressed），滑入瞬间 = 按下（justPressed），滑出/抬起 = 释放（justReleased）
	static var _touchKey:Map<Int, String> = new Map<Int, String>();       // touchPointID -> 当前所在按键（note_left 等）
	static var _slidePresses:Map<String, Bool> = new Map<String, Bool>(); // 滑入/按下事件（justPressed 消费）
	static var _slideReleases:Map<String, Bool> = new Map<String, Bool>();// 滑出/抬起事件（justReleased 消费）
	// ---- 触控按键 -> 键盘注入（映射到按键设置里的键位）----
	// 让读取物理键盘状态的 Mod/Lua（如 FlxG.keys.pressed.A）在触控游玩时同样生效
	static var _injectedKeys:Map<String, Bool> = new Map<String, Bool>(); // 已注入 KEY_DOWN 的按键（防止重复注入）
	static var _stagePoint:Point = new Point();
	static var _tapCaptureInstalled:Bool = false;
	static var _tapCaptureUsers:Int = 0;

	public static function ensureTapCapture():Void
	{
		_tapCaptureUsers++;
		if (_tapCaptureInstalled) return;
		_tapCaptureInstalled = true;
		var stage = Lib.current.stage;
		stage.addEventListener(TouchEvent.TOUCH_BEGIN, onTapBegin);
		stage.addEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
		stage.addEventListener(TouchEvent.TOUCH_END, onTapEnd);
	}

	function installTapCapture():Void
	{
		ensureTapCapture();
	}

	function uninstallTapCapture():Void
	{
		_tapCaptureUsers--;
		if (_tapCaptureUsers > 0 || !_tapCaptureInstalled) return;
		// 监听常驻：安卓端 FlxG.touches 为空，stage tap 队列是全局唯一触控通道，
		// 主菜单/StoryMenu/结算/设置等界面都在消费它，不能随 instance 生命周期卸载。
		// 这里只清理会话状态，不移除 stage 监听。
		for (p in _tapDown) p.put();
		_tapDown.clear();
		_tapDownTime.clear();
		_tapQueue.resize(0);
		_dragID = -1;
		_dragSteps = 0;
		_touchKey.clear();
		_slidePresses.clear();
		_slideReleases.clear();
		_injectedKeys.clear();
	}

	static function clearTapQueue():Void
	{
		for (p in _tapDown) p.put();
		_tapDown.clear();
		_tapDownTime.clear();
		_tapQueue.resize(0);
	}

	// stage 像素 → 游戏逻辑坐标（与 FlxTouch.setXY 完全一致：先换算到 FlxG.game 局部，
	// 再除以 scaleMode 缩放）
	static function stageToLogical(sx:Float, sy:Float):FlxPoint
	{
		_stagePoint.setTo(sx, sy);
		FlxG.game.globalToLocal(_stagePoint);
		var p:FlxPoint = FlxPoint.get();
		p.x = _stagePoint.x / FlxG.scaleMode.scale.x;
		p.y = _stagePoint.y / FlxG.scaleMode.scale.y;
		return p;
	}

	static function onTapBegin(e:TouchEvent):Void
	{
		// 清理该触点的残留状态（防 TOUCH_END 事件丢失导致键盘键卡住、动画只播一次）
		var staleKey:String = _touchKey.get(e.touchPointID);
		if (staleKey != null)
		{
			if (injectedKeyCode(staleKey) < 0) _slideReleases.set(staleKey, true);
			injectKeyUp(staleKey);
		}
		_touchKey.remove(e.touchPointID);

		var p:FlxPoint = stageToLogical(e.stageX, e.stageY);
		_tapDown.set(e.touchPointID, p);
		_tapDownTime.set(e.touchPointID, Lib.getTimer());
		// 滑键：记录触点初始所在按键（按下即按住）
		trackSlideKey(e.touchPointID, p.x, p.y);
		// 拖动会话开始（跟随第一个按下的触点）
		if (_dragID < 0)
		{
			_dragID = e.touchPointID;
			_dragLastY = p.y;
			_dragAccum = 0;
			_dragSteps = 0;
		}
	}

	// stage 级拖动：每滑动 90 逻辑像素累计一格滚动步数（避免过快）
	// 方向约定：往上拖 → 上一个选项（-1），往下拖 → 下一个选项（+1）
	static function onTouchMove(e:TouchEvent):Void
	{
		var p:FlxPoint = stageToLogical(e.stageX, e.stageY);
		// 滑键跟踪：所有触点都跟随（不限于 _dragID），滑入/滑出即按键切换
		trackSlideKey(e.touchPointID, p.x, p.y);

		if (e.touchPointID != _dragID) { p.put(); return; }
		var dy:Float = p.y - _dragLastY;
		_dragLastY = p.y;
		_dragAccum += dy;
		while (_dragAccum >= 90)
		{
			_dragAccum -= 90;
			_dragSteps++;
		}
		while (_dragAccum <= -90)
		{
			_dragAccum += 90;
			_dragSteps--;
		}
		p.put();
	}

	/** 消费本帧累计的拖动滚动格数（+1 向下一个选项，-1 向上一个选项） */
	public static function consumeDragSteps():Int
	{
		var s:Int = _dragSteps;
		_dragSteps = 0;
		return s;
	}

	static function onTapEnd(e:TouchEvent):Void
	{
		if (e.touchPointID == _dragID) _dragID = -1;
		// 滑键：触点抬起释放所在按键（并注入键盘释放）
		var relKey:String = _touchKey.get(e.touchPointID);
		if (relKey != null)
		{
			if (injectedKeyCode(relKey) < 0) _slideReleases.set(relKey, true);
			injectKeyUp(relKey);
		}
		_touchKey.remove(e.touchPointID);
		var down:FlxPoint = _tapDown.get(e.touchPointID);
		var downT:Null<Int> = _tapDownTime.get(e.touchPointID);
		_tapDown.remove(e.touchPointID);
		_tapDownTime.remove(e.touchPointID);
		if (down == null || downT == null) return;
		var up:FlxPoint = stageToLogical(e.stageX, e.stageY);
		var now:Int = Lib.getTimer();
		var isTap:Bool = (now - downT) <= TAP_MAX_MS
			&& Math.abs(up.x - down.x) + Math.abs(up.y - down.y) <= TAP_MAX_MOVE;
		down.put();
		up.put();
		if (!isTap) return;
		// 队列里存逻辑坐标（物理/缩放后），消费时再换算到对应控制相机视图
		_tapQueue.push({id: e.touchPointID, x: up.x, y: up.y, t: now});
	}

	static function flixelHasTouch(id:Int):Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.touchPointID == id) return true;
		return false;
	}

	public static function clearQueuedTap(id:Int):Void
	{
		var i:Int = _tapQueue.length - 1;
		while (i >= 0)
		{
			if (_tapQueue[i].id == id) _tapQueue.splice(i, 1);
			i--;
		}
	}

	function consumeQueuedTap(zones:Array<FlxSprite>):Bool
	{
		var now:Int = Lib.getTimer();
		var i:Int = _tapQueue.length - 1;
		while (i >= 0)
		{
			var tap:QueuedTap = _tapQueue[i];
			// 已过期，或该触摸仍被 flixel 托管（由 flixel 路径处理），丢弃记录
			if (now - tap.t > TAP_MAX_MS || flixelHasTouch(tap.id))
			{
				_tapQueue.splice(i, 1);
			}
			else
			{
				// 逻辑坐标 -> 控制相机视图坐标（与 getPositionInCameraView 同一公式）
				var vx:Float = (tap.x - controlCam.x) / controlCam.zoom + controlCam.viewMarginX;
				var vy:Float = (tap.y - controlCam.y) / controlCam.zoom + controlCam.viewMarginY;
				for (zone in zones)
				{
					if (vx >= zone.x && vx <= zone.x + zone.width && vy >= zone.y && vy <= zone.y + zone.height)
					{
						_tapQueue.splice(i, 1);
						return true;
					}
				}
			}
			i--;
		}
		return false;
	}

	/** 供设置子状态使用的矩形点按判定（逻辑坐标，主相机 1:1） */
	public static function drainTapInRect(x:Float, y:Float, w:Float, h:Float):Bool
	{
		var now:Int = Lib.getTimer();
		var i:Int = _tapQueue.length - 1;
		while (i >= 0)
		{
			var tap:QueuedTap = _tapQueue[i];
			if (now - tap.t > TAP_MAX_MS || flixelHasTouch(tap.id))
				_tapQueue.splice(i, 1);
			else if (tap.x >= x && tap.x <= x + w && tap.y >= y && tap.y <= y + h)
			{
				_tapQueue.splice(i, 1);
				return true;
			}
			i--;
		}
		return false;
	}

	// ---- 输入判定 ----

	static var _touchPoint:FlxPoint = FlxPoint.get();

	inline function normalizeKey(key:String):String
	{
		return key.startsWith('ui_') ? 'note_' + key.substr(3) : key;
	}

	function zonesFor(key:String):Array<FlxSprite>
	{
		switch (key)
		{
			case 'pause': return pauseZone != null ? [pauseZone] : [];
			// 左上角 X = 返回桌面（退出游戏），不再充当"返回上一级"
			case 'exit': return backZone != null ? [backZone] : [];
			case 'back': return menuMode && padButtons.exists('back') ? padButtons.get('back') : [];
			case 'accept': return menuMode && padButtons.exists('accept') ? padButtons.get('accept') : [];
		}
		return padButtons.exists(key) ? padButtons.get(key) : [];
	}

	function touchInAny(zones:Array<FlxSprite>, touch:FlxTouch):Bool
	{
		// 区域绘制在 controlCam（zoom=1，无滚动）上，触摸坐标也换算到该相机视图再比较
		var pos:FlxPoint = touch.getPositionInCameraView(controlCam, _touchPoint);
		for (zone in zones)
			if (pos.x >= zone.x && pos.x <= zone.x + zone.width
				&& pos.y >= zone.y && pos.y <= zone.y + zone.height)
				return true;
		return false;
	}

	public function justPressed(key:String):Bool
	{
		var normKey:String = normalizeKey(key);
		// 安卓滑键（stage 级）：仅当 flixel 无触摸托管时启用（避免与 flixel 触摸路径双触发），
		// 触点滑入/按下该键的瞬间判定为“按下”
		if (FlxG.touches.list.length == 0 && _slidePresses.exists(normKey))
		{
			_slidePresses.remove(normKey);
			return true;
		}
		var zones:Array<FlxSprite> = zonesFor(normKey);
		if (zones == null || zones.length == 0) return false;

		// 滑键：手指不松开从其他按键滑进当前按键时，也判定为“按下”
		for (touch in FlxG.touches.list)
		{
			if (touch.pressed)
			{
				var cur:String = currentKeyFor(touch);
				if (cur != null)
				{
					var last:String = _touchLastKey.get(touch.touchPointID);
					if (last != null && last != cur && cur == normKey)
					{
						_touchLastKey.set(touch.touchPointID, cur);
						clearQueuedTap(touch.touchPointID);
						return true;
					}
					_touchLastKey.set(touch.touchPointID, cur);
				}
			}
			else
			{
				_touchLastKey.remove(touch.touchPointID);
			}
		}

		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && touchInAny(zones, touch))
			{
				clearQueuedTap(touch.touchPointID);
				return true;
			}
			// 卡顿兜底：down+up 若落在同一帧间隔内，触摸会直接以 justReleased 状态出现
			// （位置=落点），此时 justPressed 永远为假，把它当作一次点按。
			// justPressedTimeInTicks == -1 说明 flixel 从未观察到按下帧（正常按住/点按都有值）
			if (touch.justReleased && touch.justPressedTimeInTicks == -1 && touchInAny(zones, touch))
			{
				clearQueuedTap(touch.touchPointID);
				return true;
			}
		}
		// 底层事件捕获兜底：掉帧导致 flixel 已清理该触摸时，点按记录仍然有效
		return consumeQueuedTap(zones);
	}

	function currentKeyFor(touch:FlxTouch):String
	{
		for (key => zones in padButtons)
		{
			if (zones != null && zones.length > 0 && touchInAny(zones, touch))
				return key;
		}
		return null;
	}

	/** 安卓滑键：逻辑坐标 -> 触点所在按键（与 consumeQueuedTap 同一套 controlCam 视图换算） */
	static function keyAt(x:Float, y:Float):String
	{
		var inst:MobileControls = instance;
		if (inst == null) return null;
		var vx:Float = (x - inst.controlCam.x) / inst.controlCam.zoom + inst.controlCam.viewMarginX;
		var vy:Float = (y - inst.controlCam.y) / inst.controlCam.zoom + inst.controlCam.viewMarginY;
		for (key => zones in inst.padButtons)
		{
			if (zones == null) continue;
			for (zone in zones)
			{
				if (vx >= zone.x && vx <= zone.x + zone.width && vy >= zone.y && vy <= zone.y + zone.height)
					return key;
			}
		}
		return null;
	}

	/** 安卓滑键：触点按下/移动/抬起时更新触点所在按键与滑入滑出事件。
	 *  有键盘绑定的键由键盘注入负责 justPressed/justReleased（避免双触发），
	 *  无绑定的键（injectedKeyCode < 0）才记录滑键事件走 instance 路径 */
	static function trackSlideKey(id:Int, x:Float, y:Float):Void
	{
		var newKey:String = keyAt(x, y);
		var oldKey:String = _touchKey.get(id);
		if (newKey == oldKey) return;
		if (oldKey != null)
		{
			if (injectedKeyCode(oldKey) < 0) _slideReleases.set(oldKey, true);
			injectKeyUp(oldKey);
		}
		_touchKey.set(id, newKey);
		if (newKey != null)
		{
			if (injectedKeyCode(newKey) < 0) _slidePresses.set(newKey, true);
			injectKeyDown(newKey);
		}
	}

	/** 触控按键对应的键盘键码（按键设置里该按键的第一个绑定键，如 note_left -> A） */
	static function injectedKeyCode(normKey:String):Int
	{
		var binds:Array<FlxKey> = ClientPrefs.keyBinds.get(normKey);
		if (binds == null || binds.length == 0) return -1;
		// A 确认键对应 Enter：绑定里有 Enter 时优先用 Enter
		// （SPACE 会与暂停等冲突，且部分脚本/Mod 只认 FlxG.keys.justPressed.ENTER）
		if (normKey == 'accept')
		{
			for (k in binds)
				if (k == FlxKey.ENTER) return k;
		}
		return binds[0];
	}

	/** 注入键盘按下：触控按下某键时，同时按下按键设置中对应的键盘键（供读 FlxG.keys 的 Mod/Lua 生效）。
	 *  若键盘键仍处于按下（TOUCH_END 丢失导致的卡键），先补发 KEY_UP 再按下，保证每次触控按下都产生 justPressed */
	static function injectKeyDown(normKey:String):Void
	{
		var kc:Int = injectedKeyCode(normKey);
		if (kc < 0) return;
		if (FlxG.keys.anyPressed([cast kc]))
		{
			var up:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_UP, true, false, kc, kc);
			Lib.current.stage.dispatchEvent(up);
		}
		var ev:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, false, kc, kc);
		Lib.current.stage.dispatchEvent(ev);
		_injectedKeys.set(normKey, true);
	}

	/** 注入键盘释放：触控抬起/滑出时释放对应的键盘键 */
	static function injectKeyUp(normKey:String):Void
	{
		if (!_injectedKeys.exists(normKey)) return;
		_injectedKeys.remove(normKey);
		var kc:Int = injectedKeyCode(normKey);
		if (kc < 0) return;
		var ev:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_UP, true, false, kc, kc);
		Lib.current.stage.dispatchEvent(ev);
	}

	public function pressed(key:String):Bool
	{
		var normKey:String = normalizeKey(key);
		// 安卓滑键（stage 级）：触点当前所在按键视为按住
		if (FlxG.touches.list.length == 0)
		{
			for (id => k in _touchKey)
				if (k == normKey) return true;
		}
		var zones:Array<FlxSprite> = zonesFor(normKey);
		if (zones == null || zones.length == 0) return false;
		for (touch in FlxG.touches.list)
			if (touch.pressed && touchInAny(zones, touch))
				return true;
		return false;
	}

	public function justReleased(key:String):Bool
	{
		var normKey:String = normalizeKey(key);
		// 安卓滑键（stage 级）：触点滑出/抬起该键的瞬间判定为“释放”
		if (FlxG.touches.list.length == 0 && _slideReleases.exists(normKey))
		{
			_slideReleases.remove(normKey);
			return true;
		}
		var zones:Array<FlxSprite> = zonesFor(normKey);
		if (zones == null || zones.length == 0) return false;
		for (touch in FlxG.touches.list)
			if (touch.justReleased && touchInAny(zones, touch))
				return true;
		return false;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		// 按键视觉反馈：按下帧 / 判定区高亮
		for (key => zones in padButtons)
		{
			var held:Bool = pressed(key);
			for (zone in zones)
			{
				if (hitboxMode)
					zone.alpha = held ? 0.45 : 0.10;
				else if (zone.frames != null && zone.frames.frames.length >= 3)
					zone.animation.frameIndex = held ? 2 : 0;
			}
		}
	}

	override function destroy()
	{
		if (instance == this) instance = null;
		uninstallTapCapture();
		super.destroy();
	}
}

typedef QueuedTap = {id:Int, x:Float, y:Float, t:Int}
