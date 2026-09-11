package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxInputText;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import openfl.Lib;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;

/**
 * 引擎风格输入框：
 *  - 圆角深色底 + 描边，聚焦时描边变主题蓝
 *  - 显示层 = flixel 位图 FlxText（future.ttf，与全界面字体统一）
 *  - 输入层 = 舞台上的隐形原生 TextField（获得系统焦点，IME/输入法可用）；
 *    文本经 Event.CHANGE 同步回显示层与游戏逻辑（.text / .hasFocus）
 */
class UIInputBox extends FlxSpriteGroup
{
	static inline var FOCUS_COLOR:FlxColor = 0xFF8AD7FF;   // 聚焦描边（联机主题蓝）
	static inline var IDLE_COLOR:FlxColor = 0xFF3A3A4C;    // 未聚焦描边
	static inline var FILL_COLOR:FlxColor = 0xE01E1E2A;    // 深色圆角底
	static inline var PANEL_PAD:Float = 12;                // 文字内边距

	/** 文本状态与显示载体（游戏逻辑通过 .text 读写） */
	public var input:FlxInputText;
	/** 回车（Enter）时触发（如「连接」） */
	public var onEnter:Void->Void = null;

	var bg:FlxSprite;
	var nativeField:TextField;
	var caretSpr:FlxSprite;
	var boxW:Int;
	var boxH:Int;
	var baseFontSize:Int;
	var _focused:Bool = false;
	var _caretBlink:Float = 0;

	public var text(get, set):String;
	public var hasFocus(get, set):Bool;

	public function new(x:Float, y:Float, w:Int, h:Int, ?startText:String = '', fontSize:Int = 22)
	{
		super(x, y);
		boxW = w;
		boxH = h;
		baseFontSize = fontSize;

		bg = new FlxSprite(0, 0).makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		bg.antialiasing = true;
		add(bg);
		redraw(false);

		// 显示层：flixel 位图 + future.ttf（与全界面一致）；关掉 FlxInputText 自身的按键/聚焦逻辑
		input = new FlxInputText(PANEL_PAD, Std.int((h - fontSize - 8) / 2), w - Std.int(PANEL_PAD * 2), startText, fontSize, FlxColor.WHITE, FlxColor.TRANSPARENT);
		input.setFormat(Paths.font('future.ttf'), fontSize, FlxColor.WHITE, LEFT);
		input.active = false;
		input.maxLength = 24;
		add(input);

		// 自绘光标（聚焦时显示/闪烁；FlxInputText 的 caret 因 active=false 不更新，原生层又隐形）
		caretSpr = new FlxSprite(0, 0);
		caretSpr.makeGraphic(2, fontSize + 4, FOCUS_COLOR);
		caretSpr.visible = false;
		add(caretSpr);

		// 输入层：隐形原生 TextField（alpha=0，仍在显示树上可获得系统焦点）
		nativeField = new TextField();
		nativeField.type = TextFieldType.INPUT;
		nativeField.embedFonts = false;
		nativeField.selectable = true;
		nativeField.background = false;
		nativeField.border = false;
		nativeField.text = startText;
		nativeField.maxChars = 24;
		nativeField.alpha = 0;
		nativeField.addEventListener(Event.CHANGE, onNativeChange);
		nativeField.addEventListener(KeyboardEvent.KEY_DOWN, onNativeKeyDown);

		Lib.current.stage.addChild(nativeField);
	}

	override function destroy():Void
	{
		if (Lib.current.stage != null && nativeField != null)
		{
			if (Lib.current.stage.focus == nativeField)
				Lib.current.stage.focus = null;
			Lib.current.stage.removeChild(nativeField);
			nativeField.removeEventListener(Event.CHANGE, onNativeChange);
			nativeField.removeEventListener(KeyboardEvent.KEY_DOWN, onNativeKeyDown);
		}
		super.destroy();
	}

	function onNativeChange(_:Event):Void
	{
		// 隐形原生层输入（含 IME 组合完成的整串）→ 同步到 future 字体显示层与游戏逻辑
		if (input.text != nativeField.text)
			input.text = nativeField.text;
	}

	function onNativeKeyDown(e:KeyboardEvent):Void
	{
		if (!_focused) return;
		if (e.keyCode == 13) // Enter
		{
			e.preventDefault();
			if (onEnter != null) onEnter();
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// 框内点击聚焦（焦点给原生 TextField → 系统输入法可用）；框外点击失焦
		if (FlxG.mouse.justPressed)
		{
			var vx:Float = FlxG.mouse.x;
			var vy:Float = FlxG.mouse.y;
			if (vx >= this.x && vx <= this.x + boxW && vy >= this.y && vy <= this.y + boxH)
				setNativeFocus(true);
			else if (_focused)
				setNativeFocus(false);
		}

		// 光标：聚焦时闪烁，位置跟随文字末端
		if (_focused)
		{
			_caretBlink += elapsed;
			if (_caretBlink >= 0.5)
			{
				_caretBlink = 0;
				caretSpr.visible = !caretSpr.visible;
			}
			var textW:Float = (input.textField != null) ? input.textField.textWidth : 0;
			// FlxSpriteGroup 子精灵坐标是绝对坐标（add 时组偏移已烘焙进子对象），
			// 这里必须加上组自身位置，否则光标会被覆盖到屏幕左上角（组内局部坐标）。
			caretSpr.x = this.x + PANEL_PAD + textW + 2;
			caretSpr.y = this.y + (boxH - caretSpr.height) / 2;
		}
		else
			caretSpr.visible = false;
	}

	public function setNativeFocus(on:Bool):Void
	{
		if (_focused == on) return;
		_focused = on;
		redraw(on);
		if (on)
		{
			Lib.current.stage.focus = nativeField;
			_caretBlink = 0;
			caretSpr.visible = true;
			var len:Int = nativeField.text.length;
			try nativeField.setSelection(len, len) catch (e:Dynamic) {}
		}
		else
		{
			caretSpr.visible = false;
			if (Lib.current.stage.focus == nativeField)
				Lib.current.stage.focus = null;
		}
	}

	function redraw(focused:Bool):Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, boxW, boxH, 10, 10, FILL_COLOR,
			{color: (focused ? FOCUS_COLOR : IDLE_COLOR), thickness: 1.5});
		bg.dirty = true;
	}

	inline function get_text():String return input.text;
	inline function set_text(v:String):String
	{
		if (nativeField.text != v) nativeField.text = v;
		if (input.text != v) input.text = v;
		return v;
	}

	inline function get_hasFocus():Bool return _focused;
	inline function set_hasFocus(v:Bool):Bool
	{
		setNativeFocus(v);
		return _focused;
	}
}
