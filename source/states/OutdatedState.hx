package states;

import openfl.Lib;

class OutdatedState extends MusicBeatState
{
	public static var leftState:Bool = false;

	var warnText:FlxText;
	override function create()
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);

		Lib.application.window.title = "FNF':Meteoric Engine - Outdated Version";
		
		warnText = new FlxText(0, 0, FlxG.width,
			"你好，感谢使用该引擎！\n
			你可能正在运行老版本ME引擎，您的版本如下：" + Main.meVersion + "\n
			请尽快升级到最新的ME引擎！\n
			最新的版本是：" + TitleState.updateVersion + "\n
			> 按下 Enter 进入 Github 下载最新版本\n
			> 按下 ESC 忽略此界面\n
			\n
			不更新今晚上Bonus-XK会去你被窝里玩哦！",
			32);
		warnText.setFormat(Paths.font("future.ttf"), 32, FlxColor.RED, LEFT);
		warnText.screenCenter(Y);
		add(warnText);
	}

	override function update(elapsed:Float)
	{
		if(!leftState) {
			if (controls.ACCEPT) {
				leftState = true;
				CoolUtil.browserLoad("https://github.com/Bonus-XK/FNF-MeteoricEngine/releases");
			}
			else if(controls.BACK) {
				leftState = true;
			}

			if(leftState)
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				FlxTween.tween(warnText, {alpha: 0}, 1, {
					onComplete: function (twn:FlxTween) {
						MusicBeatState.switchState(new MainMenuState());
					}
				});
			}
		}
		super.update(elapsed);
	}
}
