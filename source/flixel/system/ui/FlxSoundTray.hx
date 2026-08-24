package flixel.system.ui;

#if FLX_SOUND_SYSTEM
import backend.Paths;
import flixel.FlxG;
import flixel.system.FlxAssets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * 重构版音量悬浮窗（灵动岛）：按下 +/- 或 0 键时从顶部弹出的音量托盘。
 * 折叠态 = 现代圆角音量条（可拖动/点击调节）；
 * 播放器态 = 在 Freeplay 试听时展开成“灵动岛”式播放器
 * （歌名 + 可拖动 seek 的进度条 + 时间 + 播放/暂停 + 停止 ✕），
 * 音量条保留在岛内，-/+ 键在展开状态下仍然生效。
 *
 * 交互采用“按下记录 + 松开确认”双通道（FlxGame 中托盘先于输入刷新运行，
 * justPressed 有 1 帧滞后；双通道 + 宽松命中半径杜绝按钮漏检）。
 * 展开/收起为平滑形变动画（Dynamic Island 风格），收起时内容随形变淡出
 * （停止试听瞬间快照进度，收起动画期间画面不跳变）。
 */
class FlxSoundTray extends Sprite
{
	public var active:Bool;
	var _timer:Float;
	var _defaultScale:Float = 1.0;

	// ===== 形态尺寸（+/- 音量条折叠态 / 播放器展开态）=====
	static inline var W_COLL:Float = 380;
	static inline var H_COLL:Float = 64;
	static inline var W_EXP:Float = 600;
	static inline var H_EXP:Float = 170;

	// 当前动画尺寸（每帧随 morph 更新）
	var _width:Float = W_COLL;
	var _height:Float = H_COLL;

	// 形变进度：0=折叠小音量条，1=展开播放器
	var expandT:Float = 0;
	var _easeT:Float = 0;   // 平滑（smoothstep）后的插值系数
	var expandTarget:Float = 0;

	// ---- 音量条（折叠态 → 展开态位置插值）----
	static inline var TRACK_X_COLL:Float = 112;
	static inline var TRACK_X_EXP:Float = 150;
	static inline var TRACK_Y_COLL:Float = 27;
	static inline var TRACK_Y_EXP:Float = 126;
	static inline var TRACK_W_COLL:Float = 168;
	static inline var TRACK_W_EXP:Float = 250;
	static inline var TRACK_H:Float = 10;
	static inline var HANDLE_R:Float = 11;

	// ---- 播放器展开态布局 ----
	static inline var SEEK_X:Float = 24;
	static inline var SEEK_Y:Float = 66;
	static inline var SEEK_W:Float = 452;
	static inline var SEEK_H:Float = 10;
	static inline var BTN_CY:Float = 71;      // 按钮圆心中线（与进度条对齐）
	static inline var BTN_R:Float = 19;
	static inline var BTN_HIT_R:Float = 28;   // 命中半径（大于视觉半径，容错高）
	static inline var PLAY_CX:Float = 520;
	static inline var STOP_CX:Float = 566;

	// ---- 播放器状态（由 FreeplayState 驱动）----
	public var previewActive:Bool = false;
	public var previewTitle:String = "";
	/** 点击/拖动进度条请求跳转，参数为毫秒（0..length） */
	public var onSeek:Float->Void;
	/** 点击播放/暂停按钮 */
	public var onTogglePlay:Void->Void;
	/** 点击停止 ✕ 按钮 */
	public var onStopPreview:Void->Void;

	/**The sound used when increasing the volume.**/
	public var volumeUpSound:String = "flixel/sounds/beep";

	/**The sound used when decreasing the volume.**/
	public var volumeDownSound:String = 'flixel/sounds/beep';

	/**Whether or not changing the volume should make noise.**/
	public var silent:Bool = false;

	var labelTxt:TextField;
	var pctTxt:TextField;
	var titleTxt:TextField;
	var timeTxt:TextField;

	// 播放器内容可见性：开岛后为 true，收起形变完全结束才置 false
	// （保证收起动画期间内容随形变淡出，而不是瞬间消失）
	var playerVisible:Bool = false;
	// 停止试听瞬间的快照：收起动画期间用快照绘制，进度/图标不跳变
	var snapPosMs:Float = 0;
	var snapLenMs:Float = 0;
	var snapPlaying:Bool = true;

	// 点击状态（双通道：justPressed 记录按下位置，justReleased 确认触发）
	var pressedBtn:Int = -1; // 0=播放/暂停 1=停止 -1=无
	var pressedSeek:Bool = false;

	var seekDragging:Bool = false;  // 进度条拖动
	var dragging:Bool = false;      // 音量条拖动
	var btPlayHover:Bool = false;
	var btStopHover:Bool = false;
	var lastDrawVol:Float = -1;
	var lastDrawMuted:Bool = false;

	@:keep
	public function new()
	{
		super();

		// 移动端（触屏/物理高分辨率屏）：托盘放大显示；命中判定按 /scale 换算（见 update 内 mx/my）
		#if mobile
		_defaultScale = 1.25;
		#end
		visible = false;
		scaleX = _defaultScale;
		scaleY = _defaultScale;

		// VOLUME 标签
		labelTxt = new TextField();
		labelTxt.width = 84;
		labelTxt.height = 30;
		labelTxt.selectable = false;
		labelTxt.embedFonts = true;
		labelTxt.defaultTextFormat = new TextFormat(Paths.font('future.ttf'), 15, 0xFFEAF0FF, false);
		labelTxt.text = "VOLUME";
		labelTxt.x = 20;
		labelTxt.y = Math.round((H_COLL - 30) / 2) + 2;
		addChild(labelTxt);

		// 百分比显示（右侧）
		pctTxt = new TextField();
		pctTxt.width = 70;
		pctTxt.height = 30;
		pctTxt.selectable = false;
		pctTxt.embedFonts = true;
		pctTxt.defaultTextFormat = new TextFormat(Paths.font('future.ttf'), 16, 0xFF54C8FF, false, null, null, null, null, TextFormatAlign.RIGHT);
		pctTxt.text = "100%";
		pctTxt.x = W_COLL - 82;
		pctTxt.y = Math.round((H_COLL - 30) / 2) + 1;
		addChild(pctTxt);

		// 播放器：歌名（展开时淡入）
		titleTxt = new TextField();
		titleTxt.width = 430;
		titleTxt.height = 30;
		titleTxt.selectable = false;
		titleTxt.embedFonts = true;
		titleTxt.defaultTextFormat = new TextFormat(Paths.font('future.ttf'), 18, 0xFFF1F4FF, false);
		titleTxt.text = "";
		titleTxt.x = 24;
		titleTxt.y = 12;
		titleTxt.alpha = 0;
		addChild(titleTxt);

		// 播放器：当前/总时长（右上，右对齐）
		timeTxt = new TextField();
		timeTxt.width = 106;
		timeTxt.height = 26;
		timeTxt.selectable = false;
		timeTxt.embedFonts = true;
		timeTxt.defaultTextFormat = new TextFormat(Paths.font('future.ttf'), 15, 0xFF9FB0D8, false, null, null, null, null, TextFormatAlign.RIGHT);
		timeTxt.text = "";
		timeTxt.x = 470;
		timeTxt.y = 14;
		timeTxt.alpha = 0;
		addChild(timeTxt);

		screenCenter();
		drawTray();
		y = -H_COLL;
		visible = false;
	}

	// ===== 灵动岛 API（FreeplayState 调用）=====

	/** 展开为播放器并开始显示试听信息 */
	public function openPreview(title:String):Void
	{
		previewTitle = title;
		previewActive = true;
		playerVisible = true;
		expandTarget = 1;
		_timer = 1;
		visible = true;
		active = true;
		pressedBtn = -1;
		pressedSeek = false;
		seekDragging = false;
		dragging = false;
		if (y < 0) y = 0; // 若正处于滑出中，拉回顶部再形变
		drawTray();
	}

	/** 收起为小音量条（试听结束）；内容随形变淡出，随后按常规计时器自动淡出 */
	public function closePreview():Void
	{
		previewActive = false;
		expandTarget = 0;
		seekDragging = false;
		dragging = false;
		pressedBtn = -1;
		pressedSeek = false;
		_timer = 1;
	}

	/** 播放器展开时，鼠标是否落在岛范围内（供 Freeplay 屏蔽穿透点击） */
	public function isOverPanel():Bool
	{
		return isHovered();
	}

	public function update(MS:Float):Void
	{
		// ---- 形变动画（展开快、收起稍慢，先快后慢）----
		// dt 上限夹取（33ms）：首次停止试听时会同步加载 freakyMenu（未缓存，可能卡顿数百毫秒），
		// 若不夹取，卡顿帧的 dt*speed 会被 min(1,...) 夹到 1，expandT 一帧跳完 → 收起动画被吞掉。
		// 夹取后动画永远以约 0.03s/帧 的节奏推进，卡顿只会延缓、不会跳过。
		if (expandT != expandTarget)
		{
			var dt:Float = Math.min(MS / 1000, 0.033);
			var speed:Float = (expandTarget > expandT) ? 12 : 9;
			expandT += (expandTarget - expandT) * Math.min(1, dt * speed);
			if (Math.abs(expandT - expandTarget) < 0.002)
				expandT = expandTarget;
			_easeT = smoothstep(expandT);
			_width = W_COLL + (W_EXP - W_COLL) * _easeT;
			_height = H_COLL + (H_EXP - H_COLL) * _easeT;
			// 弹窗中部随宽度更新（无需等 resize 事件）
			screenCenter();
		}

		// 收起形变完成 → 播放器内容彻底隐藏
		if (!previewActive && expandT <= 0.002)
			playerVisible = false;

		// 局部坐标统一：减 letterbox offset + 除以缩放（判定与放大后视觉完全一致；触屏同享鼠标模拟通道）
		trayMouse(FlxG.game.mouseX, FlxG.game.mouseY);
		var mx:Float = _tmX;
		var my:Float = _tmY;

		// ---- 悬停高亮（仅播放器态有按钮）----
		btPlayHover = playerVisible && hitCircle(mx, my, PLAY_CX, BTN_CY, BTN_HIT_R);
		btStopHover = playerVisible && hitCircle(mx, my, STOP_CX, BTN_CY, BTN_HIT_R);

		// ---- 双通道点击（按下记录 + 松开确认），消除 1 帧输入滞后的漏检 ----
		var overStop:Bool = btStopHover;
		var overPlay:Bool = btPlayHover;
		var overSeek:Bool = playerVisible && isOverSeek(mx, my);

		if (FlxG.mouse.justPressed && isHovered())
		{
			if (overStop && onStopPreview != null)
				pressedBtn = 1;
			else if (overPlay && onTogglePlay != null)
				pressedBtn = 0;
			else if (overSeek)
			{
				pressedSeek = true;
				seekDragging = true;
			}
		}
		if (FlxG.mouse.justReleased)
		{
			// 松开确认：按下与松开都在同一按钮范围内才算有效点击
			if (pressedBtn == 1 && overStop)
			{
				pressedBtn = -1;
				onStopPreview();
				drawTray();
				return;
			}
			if (pressedBtn == 0 && overPlay)
			{
				pressedBtn = -1;
				onTogglePlay();
			}
			else
				pressedBtn = -1;

			pressedSeek = false;
			seekDragging = false;
		}

		// 按住拖动：进度条实时 seek（inst 与 vocals 同步由 FreeplayState 完成）
		if (seekDragging && onSeek != null)
		{
			var mus = FlxG.sound.music;
			if (mus != null && mus.length > 0)
				onSeek(FlxMathBound((mx - SEEK_X) / SEEK_W) * mus.length);
		}

		// ---- 音量条：点击轨道 / 按住圆钮拖动（折叠与展开态均可）----
		// 独立判定链（不经过按钮/进度条的 else-if），与旧版行为一致，
		// 保证非播放状态下 +/- 音量条鼠标点击/拖动永远可用
		if (FlxG.mouse.justPressed && isHovered() && isOverVolTrack(mx, my))
		{
			dragging = true;
			updateFromMouse();
		}
		if (FlxG.mouse.justReleased)
			dragging = false;
		if (dragging)
			updateFromMouse();

		// 键盘 +/- 平滑渐变期间，音量每帧变化，同步刷新显示（播放器态每帧都刷新进度）
		if (lastDrawVol != FlxG.sound.volume || lastDrawMuted != FlxG.sound.muted
			|| playerVisible || expandT != expandTarget)
			drawTray();

		// 鼠标悬停/拖动/试听中不消失，移开后重新计时收起（试听中永不自动收起）
		if (isHovered() || dragging || seekDragging || previewActive)
		{
			_timer = 1;
		}
		else if (_timer > 0)
		{
			_timer -= MS / 1000;
		}

		if (!isHovered() && !dragging && !seekDragging && !previewActive && _timer <= 0 && y > -_height)
		{
			// 滑出同样夹取 dt：卡顿帧不会把托盘瞬移出屏幕
			y -= Math.min(MS / 1000, 0.05) * FlxG.height * 2;

			if (y <= -_height)
			{
				visible = false;
				active = false;

				if (FlxG.save.isBound)
				{
					FlxG.save.data.mute = FlxG.sound.muted;
					FlxG.save.data.volume = FlxG.sound.volume;
					FlxG.save.flush();
				}
			}
		}
	}

	public function show(up:Bool = false):Void
	{
		if (!silent)
		{
			var sound = FlxAssets.getSound(up ? volumeUpSound : volumeDownSound);
			if (sound != null)
				FlxG.sound.load(sound).play();
		}

		_timer = 1;
		y = 0;
		visible = true;
		active = true;

		drawTray();
	}

	public function screenCenter():Void
	{
		scaleX = _defaultScale;
		scaleY = _defaultScale;
		// 逻辑视口（FlxG.width）居中：老公式用 stage 物理宽 + game.x（letterbox/容器缩放）
		// 双重复换算导致托盘错位（显示与命中都偏）；game 本地坐标下直接按逻辑视口居中即可。
		x = 0.5 * (FlxG.width - _width * _defaultScale);
	}

	// 鼠标位置 → 托盘本地未缩放坐标（实例字段，避免每帧池化点）。
	// 用 FlxG.game.mouseX/Y：托盘挂载于 FlxG.game，同一坐标系（已含容器变换/letterbox 换算），
	// 不再经过 FlxG.mouse.screenX —— 它被 FlxMouse.update 二次除以 scaleMode.scale
	// （FlxG.game.mouseX → setGlobalScreenPositionUnsafe(/scale)），叠加 offset 后大偏移。
	var _tmX:Float = 0;
	var _tmY:Float = 0;
	inline function trayMouse(px:Float, py:Float):Void
	{
		_tmX = (px - x) / scaleX;
		_tmY = (py - y) / scaleY;
	}

	// 鼠标在托盘范围内
	function isHovered():Bool
	{
		if (!visible) return false;
		trayMouse(FlxG.game.mouseX, FlxG.game.mouseY);
		return _tmX >= 0 && _tmX <= _width && _tmY >= 0 && _tmY <= _height;
	}

	// 圆形命中（含容差）
	inline function hitCircle(mx:Float, my:Float, cx:Float, cy:Float, r:Float):Bool
	{
		var dx:Float = mx - cx;
		var dy:Float = my - cy;
		return dx * dx + dy * dy <= r * r;
	}

	// 鼠标在音量拖动条区域（含圆钮容差，位置随形变插值）
	function isOverVolTrack(mx:Float, my:Float):Bool
	{
		var tx:Float = volTrackX();
		var tw:Float = volTrackW();
		var ty:Float = volTrackY();
		return mx >= tx - 12 && mx <= tx + tw + 12
			&& my >= ty - 18 && my <= ty + TRACK_H + 18;
	}

	// 鼠标在进度条区域
	function isOverSeek(mx:Float, my:Float):Bool
	{
		return mx >= SEEK_X - 12 && mx <= SEEK_X + SEEK_W + 12
			&& my >= SEEK_Y - 18 && my <= SEEK_Y + SEEK_H + 18;
	}

	// 按鼠标位置设置音量
	function updateFromMouse():Void
	{
		trayMouse(FlxG.game.mouseX, FlxG.game.mouseY);
		setVolume((_tmX - volTrackX()) / volTrackW(), false);
	}

	function setVolume(v:Float, playTone:Bool = false):Void
	{
		v = FlxMathBound(v);
		if (FlxG.sound.muted && v > 0)
		{
			FlxG.sound.muted = false;
			FlxG.save.data.mute = false;
		}
		if (v != FlxG.sound.volume)
		{
			FlxG.sound.volume = v;
			FlxG.save.data.volume = v;
			drawTray();
		}
	}

	// ===== 形变插值辅助 =====
	inline function smoothstep(t:Float):Float
	{
		return t * t * (3 - 2 * t);
	}

	inline function volTrackX():Float return TRACK_X_COLL + (TRACK_X_EXP - TRACK_X_COLL) * _easeT;
	inline function volTrackY():Float return TRACK_Y_COLL + (TRACK_Y_EXP - TRACK_Y_COLL) * _easeT;
	inline function volTrackW():Float return TRACK_W_COLL + (TRACK_W_EXP - TRACK_W_COLL) * _easeT;

	static inline function FlxMathBound(v:Float):Float
	{
		if (v < 0) return 0;
		if (v > 1) return 1;
		return v;
	}

	// ===== 重绘（背景、音量条、播放器内容一次成型）=====
	function drawTray():Void
	{
		_easeT = smoothstep(expandT);
		var t:Float = _easeT;

		var w:Int = Std.int(_width);
		var h:Int = Std.int(_height);
		graphics.clear();

		// 圆角背景 + 细边框（跟随形变尺寸）
		graphics.beginFill(0xE6161622);
		graphics.drawRoundRect(0, 0, w, h, 18, 18);
		graphics.endFill();
		graphics.lineStyle(1.5, 0x45FFFFFF, 1, true);
		graphics.drawRoundRect(1, 1, w - 2, h - 2, 18, 18);
		graphics.lineStyle(0);

		// ---- 音量行（两态共有，位置插值）----
		var tx:Float = volTrackX();
		var ty:Float = volTrackY();
		var tw:Float = volTrackW();
		labelTxt.x = 20 + (24 - 20) * t;
		labelTxt.y = Math.round((H_COLL - 30) / 2) + 2 + (122 - (Math.round((H_COLL - 30) / 2) + 2)) * t;
		pctTxt.x = (W_COLL - 82) + (506 - (W_COLL - 82)) * t;
		pctTxt.y = Math.round((H_COLL - 30) / 2) + 1 + (118 - (Math.round((H_COLL - 30) / 2) + 1)) * t;

		var vol:Float = FlxG.sound.muted ? 0 : FlxG.sound.volume;
		var fillW:Float = tw * vol;

		// 轨道背景
		graphics.beginFill(0xFF2B2838);
		graphics.drawRoundRect(tx, ty, tw, TRACK_H, TRACK_H / 2, TRACK_H / 2);
		graphics.endFill();
		graphics.lineStyle(1, 0xFF4A4660, 1, true);
		graphics.drawRoundRect(tx, ty, tw, TRACK_H, TRACK_H / 2, TRACK_H / 2);
		graphics.lineStyle(0);

		// 已调部分 + 圆钮
		if (fillW > 1)
		{
			graphics.beginFill(0xFF54C8FF);
			graphics.drawRoundRect(tx, ty, fillW, TRACK_H, TRACK_H / 2, TRACK_H / 2);
			graphics.endFill();
		}
		if (!FlxG.sound.muted)
		{
			graphics.lineStyle(2.5, 0xFF23202E, 1, true);
			graphics.beginFill(0xFFF4F7FF);
			graphics.drawCircle(tx + fillW, ty + TRACK_H / 2, HANDLE_R);
			graphics.endFill();
			graphics.lineStyle(0);
		}

		// ---- 播放器内容（随形变淡入/淡出 + 等比缩放，收起时用快照，不读实时音频）----
		var pa:Int = Std.int(255 * t); // 内容 alpha
		if (playerVisible && pa > 8)
		{
			// 内容随窗口收缩等比缩放（kX/kY）：收起动画期间所有元素保持在窗口内，
			// 不会因坐标停留在展开态布局而被"挤到窗口外面"
			var kX:Float = _width / W_EXP;
			var kY:Float = _height / H_EXP;

			// 收起期间（!previewActive）显示快照，避免切回菜单音乐后进度跳变
			var useSnap:Bool = !previewActive;
			var posMs:Float = useSnap ? snapPosMs : 0;
			var lenMs:Float = useSnap ? snapLenMs : 0;
			var playing:Bool = useSnap ? snapPlaying : true;
			if (!useSnap)
			{
				var mus = FlxG.sound.music;
				if (mus != null)
				{
					posMs = mus.time;
					lenMs = mus.length;
					playing = mus.playing;
					// 同步快照：收起(停止试听)时的过渡动画直接复用最后一帧的实时值，
					// 与 closePreview 调用时机无关（此时音频可能已被切换为菜单音乐）
					snapPosMs = posMs;
					snapLenMs = lenMs;
					snapPlaying = playing;
				}
			}
			if (lenMs <= 0) lenMs = 1;

			// 歌名 / 时间（TextField 淡入/淡出，位置随收缩比例内收，右对齐文本被夹在窗口内）
			titleTxt.alpha = t;
			titleTxt.text = previewTitle;
			titleTxt.x = 24 * kX;
			titleTxt.y = 12 * kY;
			timeTxt.alpha = t;
			timeTxt.text = fmtTime(posMs) + " / " + fmtTime(lenMs);
			timeTxt.x = Math.min((470 + 106) * kX - 106, _width - 106);

			// 进度条轨道
			var skX:Float = SEEK_X * kX;
			var skY:Float = SEEK_Y * kY;
			var skW:Float = SEEK_W * kX;
			var skH:Float = Math.max(4, SEEK_H * kY);
			graphics.beginFill(blendColor(0xFF2B2838, t));
			graphics.drawRoundRect(skX, skY, skW, skH, skH / 2, skH / 2);
			graphics.endFill();
			graphics.lineStyle(1, blendColor(0xFF4A4660, t), 1, true);
			graphics.drawRoundRect(skX, skY, skW, skH, skH / 2, skH / 2);
			graphics.lineStyle(0);

			// 进度填充 + 圆钮
			var fillPW:Float = FlxMathBound(posMs / lenMs) * skW;
			if (fillPW > 1)
			{
				graphics.beginFill(blendColor(0xFF54C8FF, t));
				graphics.drawRoundRect(skX, skY, fillPW, skH, skH / 2, skH / 2);
				graphics.endFill();
			}
			var handleR:Float = Math.max(5, HANDLE_R * ((kX + kY) / 2));
			graphics.lineStyle(2.5, blendColor(0xFF23202E, t), 1, true);
			graphics.beginFill(blendColor(0xFFF4F7FF, t));
			graphics.drawCircle(skX + fillPW, skY + skH / 2, handleR);
			graphics.endFill();
			graphics.lineStyle(0);

			// 播放/暂停按钮 / 停止 ✕ 按钮（半径随手感缩，命中半径保持展开态不受影响）
			var btnR:Float = Math.max(10, BTN_R * ((kX + kY) / 2));
			drawBtn(graphics, PLAY_CX * kX, BTN_CY * kY, btnR, btPlayHover, playing ? 0 : 1, t);
			drawStopBtn(graphics, STOP_CX * kX, BTN_CY * kY, btnR, btStopHover, t);
		}
		else
		{
			titleTxt.alpha = 0;
			timeTxt.alpha = 0;
		}

		// 百分比 / 静音文字
		if (FlxG.sound.muted)
		{
			pctTxt.text = "MUTED";
			pctTxt.textColor = 0xFFFF5E5E;
		}
		else
		{
			pctTxt.text = Math.round(FlxG.sound.volume * 100) + "%";
			pctTxt.textColor = 0xFF54C8FF;
		}

		lastDrawVol = FlxG.sound.volume;
		lastDrawMuted = FlxG.sound.muted;
	}

	// type: 0=暂停图标（两条竖杠） 1=播放图标（三角）
	function drawBtn(g:openfl.display.Graphics, cx:Float, cy:Float, r:Float, hover:Bool, type:Int, t:Float):Void
	{
		// 圆底
		g.lineStyle(1.5, blendColor(0xFF5A5F7C, t), 1, true);
		g.beginFill(blendColor(hover ? 0xFF3A4258 : 0xFF262B3E, t));
		g.drawCircle(cx, cy, r);
		g.endFill();
		g.lineStyle(0);

		var glyph:Int = blendColor(0xFFEAF0FF, t);
		if (type == 0)
		{
			// 暂停：两根竖条
			g.beginFill(glyph);
			g.drawRect(cx - 7, cy - 7, 4.5, 14);
			g.drawRect(cx + 2.5, cy - 7, 4.5, 14);
			g.endFill();
		}
		else
		{
			// 播放：三角
			g.beginFill(glyph);
			g.moveTo(cx - 5, cy - 9);
			g.lineTo(cx - 5, cy + 9);
			g.lineTo(cx + 10, cy);
			g.lineTo(cx - 5, cy - 9);
			g.endFill();
		}
	}

	function drawStopBtn(g:openfl.display.Graphics, cx:Float, cy:Float, r:Float, hover:Bool, t:Float):Void
	{
		g.lineStyle(1.5, blendColor(0xFF5A5F7C, t), 1, true);
		g.beginFill(blendColor(hover ? 0xFF58404A : 0xFF262B3E, t));
		g.drawCircle(cx, cy, r);
		g.endFill();
		g.lineStyle(0);

		// ✕
		g.lineStyle(3, blendColor(0xFFEAF0FF, t), 1, true);
		g.moveTo(cx - 6, cy - 6);
		g.lineTo(cx + 6, cy + 6);
		g.moveTo(cx + 6, cy - 6);
		g.lineTo(cx - 6, cy + 6);
		g.lineStyle(0);
	}

	/** 把 RGB 基色与形变 alpha 混合成 ARGB */
	static inline function blendColor(base:Int, a:Float):Int
	{
		var ia:Int = Std.int(Math.min(1, Math.max(0, a)) * 255);
		return (ia << 24) | (0xFFFFFF & base);
	}

	static inline function fmtTime(ms:Float):String
	{
		var total:Int = Std.int(ms / 1000);
		var m:Int = Std.int(total / 60);
		var s:Int = total % 60;
		return m + ":" + (s < 10 ? "0" : "") + s;
	}
}
#end
