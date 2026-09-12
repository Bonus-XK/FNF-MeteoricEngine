package substates;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import backend.MusicBeatSubstate;
import states.ModsMenuState.ModsButton;

/**
 * 删除 Mod 前的二次确认框（删除不可恢复）。
 * 键盘：Enter 确认 / ESC 或 Backspace 取消。
 */
class ModsDeleteConfirmSubstate extends MusicBeatSubstate
{
	var modName:String;
	var onConfirm:Void->Void;
	var confirmBtn:ModsButton;
	var cancelBtn:ModsButton;

	public function new(modName:String, onConfirm:Void->Void)
	{
		this.modName = modName;
		this.onConfirm = onConfirm;
		super();
	}

	override function create()
	{
		var W:Int = FlxG.width;
		var H:Int = FlxG.height;
		var pw:Int = 620;
		var ph:Int = 260;
		var px:Int = Std.int((W - pw) / 2);
		var py:Int = Std.int((H - ph) / 2);

		// 全屏暗化
		var bg:FlxSprite = new FlxSprite().makeGraphic(W, H, 0xB3000000);
		bg.scrollFactor.set(0, 0);
		add(bg);

		// 面板（红色边框提示危险操作）
		var panel:FlxSprite = new FlxSprite(px, py).makeGraphic(pw, ph, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(panel, 0, 0, pw, ph, 18, 18, DesignTokens.panelFill);
		FlxSpriteUtil.drawRoundRect(panel, 1, 1, pw - 2, ph - 2, 18, 18, FlxColor.TRANSPARENT, {color: 0x66FF6B6B, thickness: 1.5});
		panel.scrollFactor.set(0, 0);
		add(panel);

		// 标题
		var title:FlxText = new FlxText(px, py + 28, pw, '删除 Mod', 26);
		title.setFormat(Paths.font('future.ttf'), 26, 0xFFFF6B6B, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set(0, 0);
		add(title);

		// 提示
		var msg:FlxText = new FlxText(px + 40, py + 84, pw - 80, '确定要删除 Mod「' + modName + '」吗？\n删除后无法恢复！', 19);
		msg.setFormat(Paths.font('future.ttf'), 19, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		msg.textField.height = 84;
		msg.scrollFactor.set(0, 0);
		add(msg);

		// 按钮
		confirmBtn = new ModsButton(px + pw / 2 - 190, py + ph - 66, 170, 44, '确认删除', function() { confirm(); });
		confirmBtn.setLabelColor(0xFFFF6B6B);
		add(confirmBtn);

		cancelBtn = new ModsButton(px + pw / 2 + 20, py + ph - 66, 170, 44, '取消', function() { cancel(); });
		add(cancelBtn);

		super.create();
	}

	override function update(elapsed:Float)
	{
		var clickPressed:Bool = FlxG.mouse.justPressed;
		#if mobile
		clickPressed = FlxG.mouse.justReleased && !Main.touchWasDragging();
		#end

		for (btn in [confirmBtn, cancelBtn])
		{
			btn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (clickPressed && btn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
			{
				btn.onClick();
				return;
			}
		}

		if (FlxG.keys.justPressed.ENTER) confirm();
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.BACKSPACE) cancel();

		super.update(elapsed);
	}

	function confirm():Void
	{
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		close();
		if (onConfirm != null) onConfirm();
	}

	function cancel():Void
	{
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.7);
		close();
	}
}
