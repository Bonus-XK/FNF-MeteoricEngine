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
 * 重构版音量悬浮窗：按下 +/- 或 0 键时从顶部弹出的音量托盘。
 * 现代圆角面板样式，中间的音量条可直接用鼠标拖动/点击调节，
 * 鼠标悬停在托盘上时不会自动消失。
 */
class FlxSoundTray extends Sprite
{
	public var active:Bool;
	var _timer:Float;
	var _width:Int = 380;
	var _height:Int = 64;
	var _defaultScale:Float = 1.0;

	// 拖动条布局
	static inline var TRACK_X:Float = 112;
	static inline var TRACK_W:Float = 168;
	static inline var TRACK_H:Float = 10;
	static inline var TRACK_Y:Float = 27;
	static inline var HANDLE_R:Float = 11;

	/**The sound used when increasing the volume.**/
	public var volumeUpSound:String = "flixel/sounds/beep";

	/**The sound used when decreasing the volume.**/
	public var volumeDownSound:String = 'flixel/sounds/beep';

	/**Whether or not changing the volume should make noise.**/
	public var silent:Bool = false;

	var labelTxt:TextField;
	var pctTxt:TextField;
	var dragging:Bool = false;
	var lastDrawVol:Float = -1;
	var lastDrawMuted:Bool = false;

	@:keep
	public function new()
	{
		super();

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
		labelTxt.y = Math.round((_height - 30) / 2) + 2;
		addChild(labelTxt);

		// 百分比显示（右侧）
		pctTxt = new TextField();
		pctTxt.width = 70;
		pctTxt.height = 30;
		pctTxt.selectable = false;
		pctTxt.embedFonts = true;
		pctTxt.defaultTextFormat = new TextFormat(Paths.font('future.ttf'), 16, 0xFF54C8FF, false, null, null, null, null, TextFormatAlign.RIGHT);
		pctTxt.text = "100%";
		pctTxt.x = _width - 82;
		pctTxt.y = Math.round((_height - 30) / 2) + 1;
		addChild(pctTxt);

		screenCenter();
		drawTray();
		y = -_height;
		visible = false;
	}

	public function update(MS:Float):Void
	{
		var hovering:Bool = isHovered();

		// 点击轨道 / 按住圆钮拖动
		if (FlxG.mouse.justPressed && hovering && isOverTrack())
		{
			dragging = true;
			updateFromMouse();
		}
		if (FlxG.mouse.justReleased)
			dragging = false;
		if (dragging)
			updateFromMouse();

		// 键盘 +/- 平滑渐变期间，音量每帧变化，同步刷新显示
		if (lastDrawVol != FlxG.sound.volume || lastDrawMuted != FlxG.sound.muted)
			drawTray();

		// 鼠标悬停或拖动中不消失，移开后重新计时收起
		if (hovering || dragging)
		{
			_timer = 1;
		}
		else if (_timer > 0)
		{
			_timer -= MS / 1000;
		}

		if (!hovering && !dragging && _timer <= 0 && y > -_height)
		{
			y -= (MS / 1000) * FlxG.height * 2;

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
		x = (0.5 * (Lib.current.stage.stageWidth - _width * _defaultScale) - FlxG.game.x);
	}

	// 鼠标在托盘范围内
	function isHovered():Bool
	{
		if (!visible) return false;
		var mx:Float = FlxG.mouse.screenX - FlxG.game.x - x;
		var my:Float = FlxG.mouse.screenY - FlxG.game.y - y;
		return mx >= 0 && mx <= _width && my >= 0 && my <= _height;
	}

	// 鼠标在拖动条区域（含圆钮容差）
	function isOverTrack():Bool
	{
		var mx:Float = FlxG.mouse.screenX - FlxG.game.x - x;
		var my:Float = FlxG.mouse.screenY - FlxG.game.y - y;
		return mx >= TRACK_X - 12 && mx <= TRACK_X + TRACK_W + 12
			&& my >= TRACK_Y - 18 && my <= TRACK_Y + TRACK_H + 18;
	}

	// 按鼠标位置设置音量
	function updateFromMouse():Void
	{
		var mx:Float = FlxG.mouse.screenX - FlxG.game.x - x;
		setVolume((mx - TRACK_X) / TRACK_W, false);
	}

	function setVolume(v:Float, playTone:Bool = false):Void
	{
		v = Math.max(0, Math.min(1, v));
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

	// 重绘背景、拖动条与百分比
	function drawTray():Void
	{
		graphics.clear();

		// 圆角背景 + 细边框
		graphics.beginFill(0xE6161622);
		graphics.drawRoundRect(0, 0, _width, _height, 18, 18);
		graphics.endFill();
		graphics.lineStyle(1.5, 0x45FFFFFF, 1, true);
		graphics.drawRoundRect(1, 1, _width - 2, _height - 2, 18, 18);
		graphics.lineStyle(0);

		var vol:Float = FlxG.sound.muted ? 0 : FlxG.sound.volume;
		var fillW:Float = TRACK_W * vol;

		// 轨道背景
		graphics.beginFill(0xFF2B2838);
		graphics.drawRoundRect(TRACK_X, TRACK_Y, TRACK_W, TRACK_H, TRACK_H / 2, TRACK_H / 2);
		graphics.endFill();
		graphics.lineStyle(1, 0xFF4A4660, 1, true);
		graphics.drawRoundRect(TRACK_X, TRACK_Y, TRACK_W, TRACK_H, TRACK_H / 2, TRACK_H / 2);
		graphics.lineStyle(0);

		// 已调部分
		if (fillW > 1)
		{
			graphics.beginFill(0xFF54C8FF);
			graphics.drawRoundRect(TRACK_X, TRACK_Y, fillW, TRACK_H, TRACK_H / 2, TRACK_H / 2);
			graphics.endFill();
		}

		// 圆钮
		if (!FlxG.sound.muted)
		{
			graphics.lineStyle(2.5, 0xFF23202E, 1, true);
			graphics.beginFill(0xFFF4F7FF);
			graphics.drawCircle(TRACK_X + fillW, TRACK_Y + TRACK_H / 2, HANDLE_R);
			graphics.endFill();
			graphics.lineStyle(0);
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
}
#end
