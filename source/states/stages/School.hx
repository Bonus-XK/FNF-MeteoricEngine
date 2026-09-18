package states.stages;

import states.stages.objects.*;
import substates.GameOverSubstate;
import substates.GameOverTheme;
import cutscenes.DialogueBox;

#if MODS_ALLOWED
import sys.FileSystem;
#else
import openfl.utils.Assets as OpenFlAssets;
#end

class School extends BaseStage
{
	var bgGirls:BackgroundGirls;
	override function create()
	{
		var _song = PlayState.SONG;

		var bgSky:BGSprite = new BGSprite('weeb/weebSky', 0, 0, 0.1, 0.1);
		add(bgSky);
		bgSky.antialiasing = false;

		var repositionShit = -200;

		var bgSchool:BGSprite = new BGSprite('weeb/weebSchool', repositionShit, 0, 0.6, 0.90);
		add(bgSchool);
		bgSchool.antialiasing = false;

		var bgStreet:BGSprite = new BGSprite('weeb/weebStreet', repositionShit, 0, 0.95, 0.95);
		add(bgStreet);
		bgStreet.antialiasing = false;

		var widShit = Std.int(bgSky.width * PlayState.daPixelZoom);
		if(!ClientPrefs.data.lowQuality) {
			var fgTrees:BGSprite = new BGSprite('weeb/weebTreesBack', repositionShit + 170, 130, 0.9, 0.9);
			fgTrees.setGraphicSize(Std.int(widShit * 0.8));
			fgTrees.updateHitbox();
			add(fgTrees);
			fgTrees.antialiasing = false;
		}

		var bgTrees:FlxSprite = new FlxSprite(repositionShit - 380, -800);
		bgTrees.frames = Paths.getPackerAtlas('weeb/weebTrees');
		bgTrees.animation.add('treeLoop', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18], 12);
		bgTrees.animation.play('treeLoop');
		bgTrees.scrollFactor.set(0.85, 0.85);
		add(bgTrees);
		bgTrees.antialiasing = false;

		if(!ClientPrefs.data.lowQuality) {
			var treeLeaves:BGSprite = new BGSprite('weeb/petals', repositionShit, -40, 0.85, 0.85, ['PETALS ALL'], true);
			treeLeaves.setGraphicSize(widShit);
			treeLeaves.updateHitbox();
			add(treeLeaves);
			treeLeaves.antialiasing = false;
		}

		bgSky.setGraphicSize(widShit);
		bgSchool.setGraphicSize(widShit);
		bgStreet.setGraphicSize(widShit);
		bgTrees.setGraphicSize(Std.int(widShit * 1.4));

		bgSky.updateHitbox();
		bgSchool.updateHitbox();
		bgStreet.updateHitbox();
		bgTrees.updateHitbox();

		if(!ClientPrefs.data.lowQuality) {
			bgGirls = new BackgroundGirls(-100, 190);
			bgGirls.scrollFactor.set(0.9, 0.9);
			add(bgGirls);
		}
		setDefaultGF('gf-pixel');

		switch (songName)
		{
			case 'senpai':
				FlxG.sound.playMusic(Paths.music('Lunchbox'), 0);
				FlxG.sound.music.fadeIn(1, 0, 0.8);
			case 'roses':
				FlxG.sound.play(Paths.sound('ANGRY_TEXT_BOX'));
		}
		if(isStoryMode && !seenCutscene)
		{
			if(songName == 'roses') FlxG.sound.play(Paths.sound('ANGRY'));
			initDoof();
			setStartCallback(schoolIntro);
		}
	}

	override function resetForRestart()
	{
		// 快速重开不重建舞台：bgGirls 表情状态会残留（事件重放颠倒）。
		// resetState 恢复到“构造完成态”（事件前 = 开心），重放的 BG Freaks Expression
		// 事件在同一帧内翻回生气 → 与首开一致（重开瞬间即生气）。
		if (bgGirls != null) bgGirls.resetState();
	}

	override function beatHit()
	{
		if(bgGirls != null) bgGirls.dance();
	}

	// For events
	override function eventCalled(eventName:String, value1:String, value2:String, flValue1:Null<Float>, flValue2:Null<Float>, strumTime:Float)
	{
		switch(eventName)
		{
			case "BG Freaks Expression":
				if(bgGirls != null) bgGirls.swapDanceType();
		}
	}

	var doof:DialogueBox = null;
	function initDoof()
	{
		var file:String = Paths.txt(songName + '/' + songName + 'Dialogue'); //Checks for vanilla/Senpai dialogue
		#if MODS_ALLOWED
		if (!FileSystem.exists(file))
		#else
		if (!OpenFlAssets.exists(file))
		#end
		{
			startCountdown();
			return;
		}

		doof = new DialogueBox(false, CoolUtil.coolTextFile(file));
		doof.cameras = [camHUD];
		doof.scrollFactor.set();
		doof.finishThing = startCountdown;
		doof.nextDialogueThing = PlayState.instance.startNextDialogue;
		doof.skipDialogueThing = PlayState.instance.skipDialogue;
	}
	
	function schoolIntro():Void
	{
		inCutscene = true;
		var black:FlxSprite = new FlxSprite(-100, -100).makeGraphic(FlxG.width * 2, FlxG.height * 2, FlxColor.BLACK);
		black.scrollFactor.set();
		if(songName == 'senpai') add(black);

		new FlxTimer().start(0.3, function(tmr:FlxTimer)
		{
			black.alpha -= 0.15;

			if (black.alpha > 0)
				tmr.reset(0.3);
			else
			{
				if (doof != null)
					add(doof);
				else
					startCountdown();

				remove(black);
				black.destroy();
			}
		});
	}

	// 结算主题：**恒返回非 null map**（null 字段 = 不干预）——PlayState 用返回 null 判定「本 stage 不参与」，
	//   若未来要改为返回 null，需同步调整 PlayState 的合并逻辑。
	// 原说明：谱面字段为空时提供本 stage 的主题资源（等价于旧实现里 create() 期间的直接写入）
	override function getGameOverTheme():GameOverTheme
	{
		var _song = PlayState.SONG;
		return {
			deathSoundName: (_song.gameOverSound == null || _song.gameOverSound.trim().length < 1) ? 'fnf_loss_sfx-pixel' : null,
			loopSoundName: (_song.gameOverLoop == null || _song.gameOverLoop.trim().length < 1) ? 'gameOver-pixel' : null,
			endSoundName: (_song.gameOverEnd == null || _song.gameOverEnd.trim().length < 1) ? 'gameOverEnd-pixel' : null,
			characterName: (_song.gameOverChar == null || _song.gameOverChar.trim().length < 1) ? 'bf-pixel-dead' : null,
		};
	}
}
