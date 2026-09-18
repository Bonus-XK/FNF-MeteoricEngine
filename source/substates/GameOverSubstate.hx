package substates;

import backend.WeekData;

import objects.Character;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.math.FlxPoint;

import states.StoryMenuState;
import states.FreeplayState;

class GameOverSubstate extends MusicBeatSubstate
{
	public var boyfriend:Character;
	var camFollow:FlxObject;
	var updateCamera:Bool = false;
	var playingDeathSound:Bool = false;
	#if mobile
	var pad:objects.MobileControls; // virtualpad 样式 A/B 键（不注册为全局 instance）
	#end

	var stageSuffix:String = "";

	/** Game Over 主题：由 stage 通过 `BaseStage.getGameOverTheme()` 提供、在进入结算时
	 *  **显式传给本类构造函数**。字段为 null 表示"不干预"，回退到谱面字段 / 引擎默认值。
	 *  这样 stage 不再直接写全局；字段优先级与取值等价：硬默认 → 谱面字段 → 主题覆盖。
	 *  ⚠ 求值时点：这四个字段此前由 stage 在 create() 期间写；现在由进入结算的调用点显式传参，
	 *  在**本类构造函数**里应用。引擎内无可观察差异（字段只在本类构造/更新期被读），
	 *  但脚本侧若在死亡**之前**读它们，看到的仍是谱面/默认值（不是该 stage 的主题值）。 */
	public static var characterName:String = 'bf-dead';
	public static var deathSoundName:String = 'fnf_loss_sfx';
	public static var loopSoundName:String = 'gameOver';
	public static var endSoundName:String = 'gameOverEnd';
	public static var deathDelay:Float = 0; //Psych 1.0.4：死亡后延迟打开 Game Over 界面（Weekend 1 用）

	public static var instance:GameOverSubstate;

	public static function resetVariables() {
		characterName = 'bf-dead';
		deathSoundName = 'fnf_loss_sfx';
		loopSoundName = 'gameOver';
		endSoundName = 'gameOverEnd';
		deathDelay = 0;

		var _song = PlayState.SONG;
		if(_song != null)
		{
			if(_song.gameOverChar != null && _song.gameOverChar.trim().length > 0) characterName = _song.gameOverChar;
			if(_song.gameOverSound != null && _song.gameOverSound.trim().length > 0) deathSoundName = _song.gameOverSound;
			if(_song.gameOverLoop != null && _song.gameOverLoop.trim().length > 0) loopSoundName = _song.gameOverLoop;
			if(_song.gameOverEnd != null && _song.gameOverEnd.trim().length > 0) endSoundName = _song.gameOverEnd;
		}
	}

	override function create()
	{
		instance = this;
		FlxG.mouse.visible = true;
		PlayState.instance.callOnScripts('onGameOverStart', []);

		super.create();

		#if mobile
		// virtualpad 样式 A/B 键：A=复活重试（右上），B=返回选歌（A 左侧）
		pad = new objects.MobileControls(false, FlxG.camera, -1, true);
		pad.addPadArrow('back', 'b', FlxG.width - objects.MobileControls.BTN_W * 2 - 20 - 12, FlxG.height - objects.MobileControls.BTN_H - 20, 0xFFCC5555);
		add(pad);
		#end

		loadUIscripts('gameover');
	}

	public function new(x:Float, y:Float, camX:Float, camY:Float, ?theme:GameOverTheme)
	{
		// 入口显式传入的 stage 主题：非 null 的字段覆盖（等价于旧实现里 stage 在 create() 期间的写入）
		if (theme != null)
		{
			if (theme.characterName != null) characterName = theme.characterName;
			if (theme.deathSoundName != null) deathSoundName = theme.deathSoundName;
			if (theme.loopSoundName != null) loopSoundName = theme.loopSoundName;
			if (theme.endSoundName != null) endSoundName = theme.endSoundName;
		}

		super();

		PlayState.instance.setOnScripts('inGameOver', true);

		Conductor.setPosition(0);

		boyfriend = new Character(x, y, characterName, true);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
		add(boyfriend);

		FlxG.sound.play(Paths.sound(deathSoundName));
		FlxG.camera.scroll.set();
		FlxG.camera.target = null;

		boyfriend.playAnim('firstDeath');

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(boyfriend.getGraphicMidpoint().x, boyfriend.getGraphicMidpoint().y);
		FlxG.camera.focusOn(new FlxPoint(FlxG.camera.scroll.x + (FlxG.camera.width / 2), FlxG.camera.scroll.y + (FlxG.camera.height / 2)));
		add(camFollow);
	}

	public var startedDeath:Bool = false;
	var isFollowingAlready:Bool = false;
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		PlayState.instance.callOnScripts('onUpdate', [elapsed]);

		#if mobile
		// virtualpad A/B 键判定（走 stage tap 队列兜底，安卓构建 FlxG.touches 为空也能触发）
		if (pad != null)
		{
			if (pad.justPressed('accept'))
			{
				endBullshit();
				return;
			}
			if (pad.justPressed('back'))
			{
				goBackToMenu();
				return;
			}
		}
		#end

		if (controls.ACCEPT)
		{
			endBullshit();
		}

		if (controls.BACK)
			goBackToMenu();
		
		if (boyfriend.animation.curAnim != null)
		{
			if (boyfriend.animation.curAnim.name == 'firstDeath' && boyfriend.animation.curAnim.finished && startedDeath)
				boyfriend.playAnim('deathLoop');

			if(boyfriend.animation.curAnim.name == 'firstDeath')
			{
				if(boyfriend.animation.curAnim.curFrame >= 12 && !isFollowingAlready)
				{
					FlxG.camera.follow(camFollow, LOCKON, 0);
					updateCamera = true;
					isFollowingAlready = true;
				}

				if (boyfriend.animation.curAnim.finished && !playingDeathSound)
				{
					startedDeath = true;
					if (PlayState.SONG.stage == 'tank')
					{
						playingDeathSound = true;
						coolStartDeath(0.2);
						
						var exclude:Array<Int> = [];
						//if(!ClientPrefs.cursing) exclude = [1, 3, 8, 13, 17, 21];

						FlxG.sound.play(Paths.sound('jeffGameover/jeffGameover-' + FlxG.random.int(1, 25, exclude)), 1, false, null, true, function() {
							if(!isEnding)
							{
								FlxG.sound.music.fadeIn(0.2, 1, 4);
							}
						});
					}
					else coolStartDeath();
				}
			}
		}
		
		if(updateCamera) FlxG.camera.followLerp = FlxMath.bound(elapsed * 0.6 / (FlxG.updateFramerate / 60), 0, 1);
		else FlxG.camera.followLerp = 0;

		if (FlxG.sound.music.playing)
		{
			Conductor.syncToMusic();
		}
		PlayState.instance.callOnScripts('onUpdatePost', [elapsed]);
	}

	var isEnding:Bool = false;

	function coolStartDeath(?volume:Float = 1):Void
	{
		FlxG.sound.playMusic(Paths.music(loopSoundName), volume);
	}

	/** B 键 / 返回：回到选歌界面 */
	function goBackToMenu():Void
	{
		#if desktop DiscordClient.resetClientID(); #end
		FlxG.sound.music.stop();
		PlayState.deathCounter = 0;
		PlayState.seenCutscene = false;
		PlayState.chartingMode = false;

		Mods.loadTopMod();
		if (PlayState.isStoryMode)
			MusicBeatState.switchState(new StoryMenuState());
		else
			MusicBeatState.switchState(new FreeplayState());

		FlxG.sound.playMusic(Paths.music('freakyMenu'));
		PlayState.instance.callOnScripts('onGameOverConfirm', [false]);
	}

	function endBullshit():Void
	{
		if (!isEnding)
		{
			isEnding = true;
			boyfriend.playAnim('deathConfirm', true);
			FlxG.sound.music.stop();
			FlxG.sound.play(Paths.music(endSoundName));
			new FlxTimer().start(0.7, function(tmr:FlxTimer)
			{
				// 回放中死亡重试：保留回放数据，重开后继续回放
				if (PlayState.instance.replayMode && PlayState.carryReplay != null)
					PlayState.queuedReplay = PlayState.carryReplay;
				FlxG.camera.fade(FlxColor.BLACK, 2, false, function()
				{
					MusicBeatState.resetState();
				});
			});
			PlayState.instance.callOnScripts('onGameOverConfirm', [true]);
		}
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		instance = null;
		super.destroy();
	}
}
