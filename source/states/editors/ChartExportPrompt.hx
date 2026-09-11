package states.editors;

import backend.ClientPrefs;
import backend.Paths;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import states.editors.ChartWidgets.EditorButton;

/**
 * 导出谱面格式选择弹窗（沿用编谱面板控件库）。
 * 回调: onChoice(0=Psych 1.0.4, 1=Psych 0.6.3 旧版, 2=CNE, 3=取消)
 */
class ChartExportPrompt extends FlxSubState
{
	public var onChoice:Int->Void;

	var buttons:Array<{btn:EditorButton, choice:Int}> = [];
	var overlay:FlxSprite;
	var panelBg:FlxSprite;

	public function new(?onChoice:Int->Void)
	{
		super();
		this.onChoice = onChoice;
	}

	override function create():Void
	{
		overlay = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xAA000000);
		overlay.scrollFactor.set();
		add(overlay);

		var w:Float = 380;
		var h:Float = 250;
		var x:Float = (FlxG.width - w) / 2;
		var y:Float = (FlxG.height - h) / 2;
		panelBg = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		panelBg.scrollFactor.set();
		FlxSpriteUtil.drawRoundRect(panelBg, 0, 0, w, h, 18, 18, 0xEE161622, {color: 0x55FFFFFF, thickness: 1.5});
		add(panelBg);

		var title:FlxText = new FlxText(x + 24, y + 16, w - 48, '导出谱面…', 20);
		title.setFormat(Paths.font('future.ttf'), 20, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 1.2;
		title.scrollFactor.set();
		add(title);

		var labels:Array<String> = [
			'Psych 1.0.4（当前格式）',
			'Psych 0.6.3（旧版兼容）',
			'Codename Engine (CNE)'
		];
		var btnW:Float = w - 48;
		for (i in 0...labels.length)
		{
			var bx:Float = x + 24;
			var by:Float = y + 60 + i * 44;
			var btn:EditorButton = new EditorButton(bx, by, btnW, 34, labels[i], function()
			{
				close();
				if (onChoice != null) onChoice(i);
			}, 13);
			add(btn);
			buttons.push({btn: btn, choice: i});
		}

		var cancelBtn:EditorButton = new EditorButton(x + 24, y + h - 44, btnW, 34, '取消', function()
		{
			close();
			if (onChoice != null) onChoice(3);
		}, 13);
		add(cancelBtn);
		buttons.push({btn: cancelBtn, choice: 3});
	}

	override function update(elapsed:Float):Void
	{
		if (FlxG.mouse.justPressed)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;
			for (b in buttons)
			{
				if (b.btn.over(mx, my))
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
					b.btn.onClick();
					return;
				}
			}
		}
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (b in buttons) b.btn.setHovered(b.btn.over(mx, my));
		super.update(elapsed);
	}
}
