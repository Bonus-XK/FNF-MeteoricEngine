package substates;

import flixel.*;
import flixel.addons.ui.FlxUIButton;
import openfl.text.TextField;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import backend.Paths;

/**
 * 文本输入弹窗（Windows 风格悬浮窗口 + 系统按钮）
 * 界面文字用引擎 future 字体（含中文）；输入框走系统 IME 支持中文输入。
 * 按 ESC/Back 或点“取消”关闭。
 * 用法: openSubState(new TextInputPrompt(title, help, initialValue, function(value){ ... }));
 */
class TextInputPrompt extends MusicBeatSubstate
{
	public var okCallback:String->Void = null;
	public var cancelCallback:Void->Void = null;

	var inputField:TextField;
	var panel:FlxSprite;
	var titleTxt:FlxText;
	var helpTxt:FlxText;
	var buttonAccept:FlxUIButton;
	var buttonCancel:FlxUIButton;

	var initialValue:String = '';
	var titleText:String = '';
	var helpText:String = '';

	public function new(title:String = '', help:String = '', initialValue:String = '', okCallback:String->Void = null, cancelCallback:Void->Void = null)
	{
		super();
		this.titleText = title;
		this.helpText = help;
		this.initialValue = initialValue;
		this.okCallback = okCallback;
		this.cancelCallback = cancelCallback;
	}

	override public function create():Void
	{
		super.create();

		var WIN_W:Int = 648;
		var WIN_H:Int = 372;

		// 阴影
		var shadow = new FlxSprite().makeGraphic(WIN_W + 6, WIN_H + 6, 0x66000000);
		shadow.screenCenter();
		add(shadow);

		// 窗口边框（Windows 深灰）
		var border = new FlxSprite().makeGraphic(WIN_W, WIN_H, 0xFF7A7A7A);
		border.screenCenter();
		add(border);

		// 标题栏（Windows 深色）
		var titleBar = new FlxSprite().makeGraphic(WIN_W - 2, 40, 0xFF2B2B2B);
		titleBar.x = border.x + 1;
		titleBar.y = border.y + 1;
		add(titleBar);

		// 内容区（浅灰，Windows 对话框背景）
		panel = new FlxSprite().makeGraphic(WIN_W - 2, WIN_H - 42, 0xFFF0F0F0);
		panel.x = border.x + 1;
		panel.y = titleBar.y + titleBar.height;
		add(panel);

		// 标题（future 字体，含中文）
		titleTxt = new FlxText(titleBar.x + 12, titleBar.y, titleBar.width - 24, titleText, 16);
		titleTxt.setFormat(Paths.font('future.ttf'), 16, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(titleTxt);

		// 说明文字（future 字体，含中文）
		helpTxt = new FlxText(panel.x + 16, panel.y + 12, panel.width - 32, helpText, 14);
		helpTxt.setFormat(Paths.font('future.ttf'), 14, 0xFF333333, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(helpTxt);

		// 输入框（openfl 原生 TextField，挂到 stage，走系统 IME 支持中文输入）
		// 字体用 future 内部名（含中文），拿不到再回退系统字体
		var inputFont:String = null;
		try {
			var f = openfl.utils.Assets.getFont(Paths.font('future.ttf'));
			if (f != null) inputFont = f.fontName;
		} catch (e:Dynamic) {}
		if (inputFont == null || inputFont == '') {
			#if windows
			inputFont = 'Microsoft YaHei';
			#elseif mac
			inputFont = 'PingFang SC';
			#else
			inputFont = '_sans';
			#end
		}

		inputField = new TextField();
		inputField.type = TextFieldType.INPUT;
		inputField.text = initialValue;
		inputField.border = true;
		inputField.background = true;
		inputField.backgroundColor = 0xFFFFFF;
		inputField.borderColor = 0xFF999999;
		inputField.width = panel.width - 32;
		inputField.height = 28;
		inputField.defaultTextFormat = new TextFormat(inputFont, 15, 0xFF000000, null, null, null, null, null, TextFormatAlign.LEFT);
		inputField.setTextFormat(inputField.defaultTextFormat);
		inputField.x = panel.x + 16;
		inputField.y = panel.y + panel.height - 96;
		FlxG.stage.addChild(inputField);

		// 按钮（flixel-ui 系统风格，future 字体中文标签）
		buttonAccept = new FlxUIButton(0, 0, '确定', function() {
			if (okCallback != null) okCallback(inputField.text);
			close();
		});
		buttonAccept.setLabelFormat(Paths.font('future.ttf'), 14, 0xFF000000, CENTER, FlxTextBorderStyle.NONE, 0x0, true);
		buttonAccept.resize(96, 30);
		buttonAccept.x = panel.x + panel.width - 210;
		buttonAccept.y = panel.y + panel.height - 44;
		add(buttonAccept);

		buttonCancel = new FlxUIButton(0, 0, '取消', function() {
			if (cancelCallback != null) cancelCallback();
			close();
		});
		buttonCancel.setLabelFormat(Paths.font('future.ttf'), 14, 0xFF000000, CENTER, FlxTextBorderStyle.NONE, 0x0, true);
		buttonCancel.resize(96, 30);
		buttonCancel.x = panel.x + panel.width - 106;
		buttonCancel.y = panel.y + panel.height - 44;
		add(buttonCancel);

		FlxG.stage.focus = inputField;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		// 只用 ESC 关闭（Backspace 要留给输入框删除字母，不能用 controls.BACK）
		if (FlxG.keys.justPressed.ESCAPE) close();
	}

	override public function close():Void
	{
		if (inputField != null)
		{
			if (FlxG.stage.focus == inputField) FlxG.stage.focus = null;
			if (inputField.parent != null) FlxG.stage.removeChild(inputField);
		}
		super.close();
	}
}
