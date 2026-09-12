package states;

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
 * 崩溃测试弹窗（主菜单输入 crash 后弹出）：
 * 选择「Haxe 级报错」（抛未捕获异常 → 游戏内报错界面 + MeteoricEngine_*.txt）
 * 或「原生/底层报错」（写空指针 → native_stack.txt）。
 * 回调: onChoice(0=Haxe 级, 1=原生, 2=取消)
 */
class CrashTestPrompt extends FlxSubState
{
	public var onChoice:Int->Void;

	var buttons:Array<{btn:EditorButton, choice:Int}> = [];

	public function new(?onChoice:Int->Void)
	{
		super();
		this.onChoice = onChoice;
	}

	override function create():Void
	{
		var overlay:FlxSprite = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xAA000000);
		overlay.scrollFactor.set();
		add(overlay);

		var w:Float = 380;
		var h:Float = 190;
		var x:Float = (FlxG.width - w) / 2;
		var y:Float = (FlxG.height - h) / 2;
		var panelBg:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		panelBg.scrollFactor.set();
		FlxSpriteUtil.drawRoundRect(panelBg, 0, 0, w, h, 18, 18, DesignTokens.panelFill, {color: 0x55FFFFFF, thickness: 1.5});
		add(panelBg);

		var title:FlxText = new FlxText(x + 24, y + 16, w - 48, '崩溃测试', 20);
		title.setFormat(Paths.font('future.ttf'), 20, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 1.2;
		title.scrollFactor.set();
		add(title);

		var labels:Array<String> = ['Haxe 级报错（游戏内报错界面 + 日志）', '原生/底层报错（native_stack.txt）'];
		var btnW:Float = w - 48;
		for (i in 0...labels.length)
		{
			var btn:EditorButton = new EditorButton(x + 24, y + 58 + i * 44, btnW, 34, labels[i], function()
			{
				close();
				if (onChoice != null) onChoice(i);
			}, 12);
			add(btn);
			buttons.push({btn: btn, choice: i});
		}

		var cancelBtn:EditorButton = new EditorButton(x + 24, y + h - 44, btnW, 34, '取消', function()
		{
			close();
			if (onChoice != null) onChoice(2);
		}, 13);
		add(cancelBtn);
		buttons.push({btn: cancelBtn, choice: 2});
	}

	override function update(elapsed:Float):Void
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (b in buttons) b.btn.setHovered(b.btn.over(mx, my));
		if (FlxG.mouse.justPressed)
		{
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
		super.update(elapsed);
	}
}
