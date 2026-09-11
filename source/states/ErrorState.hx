package states;

import backend.CrashHandler;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.util.FlxColor;

/**
 * 游戏内报错界面。
 * 注意：这里不加载任何 Paths 资源，只使用 makeGraphic 与默认字体，
 * 避免在图形系统可能已经损坏时发生二次崩溃。
 */
class ErrorState extends FlxState
{
	var stackText:FlxText;
	var btnA:FlxSprite;
	var btnB:FlxSprite;
	var btnAText:FlxText;
	var btnBText:FlxText;

	override function create()
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF14141E);
		bg.scrollFactor.set();
		add(bg);

		var topBar:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, 6, 0xFFFF4444);
		add(topBar);

		var title:FlxText = new FlxText(24, 24, FlxG.width - 48, '游戏发生错误', 40);
		title.setFormat(Paths.font('future.ttf'), 40, 0xFFFF5555, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(title);

		var sourceTxt:FlxText = new FlxText(24, 84, FlxG.width - 48, '错误来源：' + CrashHandler.errorSource, 20);
		sourceTxt.setFormat(Paths.font('future.ttf'), 20, 0xFFFFCCCC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(sourceTxt);

		var errTxt:FlxText = new FlxText(24, 114, FlxG.width - 48, '错误信息：' + CrashHandler.errorMessage, 20);
		errTxt.setFormat(Paths.font('future.ttf'), 20, 0xFFFFDDDD, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(errTxt);

		stackText = new FlxText(24, 170, FlxG.width - 48, '调用堆栈：\n' + CrashHandler.errorStack, 16);
		stackText.setFormat(Paths.font('future.ttf'), 16, 0xFFAAAAAA, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(stackText);

		var hintTxt:FlxText = new FlxText(24, FlxG.height - 46, FlxG.width - 48,
			'完整错误信息已保存到 crash 目录下的日志文件\n[Enter] 返回主菜单    [Esc] 退出游戏', 18);
		hintTxt.setFormat(Paths.font('future.ttf'), 18, 0xFFDDDDDD, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(hintTxt);

		// A/B 触控键：A=返回主菜单，B=退出游戏（安卓也能用）
		var btnW:Int = 230;
		var btnH:Int = 64;
		var btnY:Float = FlxG.height - 130;
		btnA = new FlxSprite(FlxG.width / 2 - btnW - 20, btnY).makeGraphic(btnW, btnH, 0xFF2A6B2A);
		btnB = new FlxSprite(FlxG.width / 2 + 20, btnY).makeGraphic(btnW, btnH, 0xFF6B2A2A);
		add(btnA);
		add(btnB);

		btnAText = new FlxText(btnA.x, btnA.y, btnW, 'A = 返回主菜单', 22);
		btnAText.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(btnAText);

		btnBText = new FlxText(btnB.x, btnB.y, btnW, 'B = 退出游戏', 22);
		btnBText.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(btnBText);
	}

	override function update(elapsed:Float)
	{
		// A/B 触控键
		if (FlxG.mouse.justPressed)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;
			if (btnA != null && mx >= btnA.x && mx <= btnA.x + btnA.width && my >= btnA.y && my <= btnA.y + btnA.height)
			{
				CrashHandler.leaveErrorState();
				FlxG.switchState(new MainMenuState());
				return;
			}
			if (btnB != null && mx >= btnB.x && mx <= btnB.x + btnB.width && my >= btnB.y && my <= btnB.y + btnB.height)
			{
				Sys.exit(0);
				return;
			}
		}

		if (FlxG.keys.justPressed.ENTER)
		{
			CrashHandler.leaveErrorState();
			FlxG.switchState(new MainMenuState());
			return;
		}
		if (FlxG.keys.justPressed.ESCAPE)
		{
			Sys.exit(0);
			return;
		}

		// 上下键滚动堆栈
		if (stackText != null && stackText.height > FlxG.height - 220)
		{
			if (FlxG.keys.pressed.UP)
				stackText.y += 8;
			if (FlxG.keys.pressed.DOWN)
				stackText.y -= 8;
			stackText.y = Math.min(170, Math.max(FlxG.height - 60 - stackText.height, stackText.y));
		}

		super.update(elapsed);
	}
}
