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
import openfl.events.TouchEvent;
import openfl.utils.Assets;
import backend.ClientPrefs;
import backend.Paths;
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

	// 菜单模式：只放 A（确认）键，B 键已按要求移除
	function buildMenuButtons():Void
	{
		var aBtn:FlxSprite = makePadSprite('a', 0xFF7CFC8A);
		aBtn.x = FlxG.width - BTN_W - 20;
		aBtn.y = FlxG.height - BTN_H - 20;
		add(aBtn);
		if (!padButtons.exists('accept')) padButtons.set('accept', []);
		padButtons.get('accept').push(aBtn);
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

	function makePadSprite(graphic:String, color:Int):FlxSprite
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
		_tapCaptureInstalled = false;
		var stage = Lib.current.stage;
		stage.removeEventListener(TouchEvent.TOUCH_BEGIN, onTapBegin);
		stage.removeEventListener(TouchEvent.TOUCH_END, onTapEnd);
		for (p in _tapDown) p.put();
		_tapDown.clear();
		_tapDownTime.clear();
		_tapQueue.resize(0);
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
		var p:FlxPoint = stageToLogical(e.stageX, e.stageY);
		_tapDown.set(e.touchPointID, p);
		_tapDownTime.set(e.touchPointID, Lib.getTimer());
	}

	static function onTapEnd(e:TouchEvent):Void
	{
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

	public function pressed(key:String):Bool
	{
		var zones:Array<FlxSprite> = zonesFor(normalizeKey(key));
		if (zones == null || zones.length == 0) return false;
		for (touch in FlxG.touches.list)
			if (touch.pressed && touchInAny(zones, touch))
				return true;
		return false;
	}

	public function justReleased(key:String):Bool
	{
		var zones:Array<FlxSprite> = zonesFor(normalizeKey(key));
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
