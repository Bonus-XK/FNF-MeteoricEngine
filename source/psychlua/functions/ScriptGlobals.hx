package psychlua.functions;

import psychlua.FunkinLua;
import backend.Mods;
import backend.WeekData;
import objects.Note;
import objects.NoteSplash;

import flixel.FlxG;

//
// ScriptGlobals —— 由 FunkinLua.hx 的 new() 拆分而来（阶段 A：纯搬运，零行为变更）
// 每个 Lua 脚本创建时对其全局表做的一次性初始化：键名、赋值顺序、值表达式逐字保留。
// 唯一改写：set( -> funk.set(（同一实例方法），语义完全一致。
//
class ScriptGlobals
{
	public static function implement(funk:FunkinLua)
	{
		var game:PlayState = PlayState.instance;
		var lua:State = funk.lua;

		// Lua shit
		funk.set('Function_StopLua', FunkinLua.Function_StopLua);
		funk.set('Function_StopHScript', FunkinLua.Function_StopHScript);
		funk.set('Function_StopAll', FunkinLua.Function_StopAll);
		funk.set('Function_Stop', FunkinLua.Function_Stop);
		funk.set('Function_Continue', FunkinLua.Function_Continue);
		funk.set('luaDebugMode', false);
		funk.set('luaDeprecatedWarnings', true);
		funk.set('inChartEditor', false);

		// Song/Week shit
		funk.set('curBpm', Conductor.bpm);
		funk.set('bpm', PlayState.SONG.bpm);
		funk.set('scrollSpeed', PlayState.SONG.speed);
		funk.set('crochet', Conductor.crochet);
		funk.set('stepCrochet', Conductor.stepCrochet);
		funk.set('songLength', FlxG.sound.music.length);
		funk.set('songName', PlayState.SONG.song);
		funk.set('songPath', Paths.formatToSongPath(PlayState.SONG.song));
		funk.set('startedCountdown', false);
		funk.set('curStage', PlayState.SONG.stage);

		funk.set('isStoryMode', PlayState.isStoryMode);
		funk.set('difficulty', PlayState.storyDifficulty);

		funk.set('difficultyName', Difficulty.getString());
		funk.set('difficultyPath', Paths.formatToSongPath(Difficulty.getString()));
		funk.set('weekRaw', PlayState.storyWeek);
		funk.set('week', WeekData.weeksList[PlayState.storyWeek]);
		funk.set('seenCutscene', PlayState.seenCutscene);
		funk.set('hasVocals', PlayState.SONG.needsVoices);

		// Camera poo
		funk.set('cameraX', 0);
		funk.set('cameraY', 0);

		// Screen stuff
		funk.set('screenWidth', FlxG.width);
		funk.set('screenHeight', FlxG.height);

		// PlayState cringe ass nae nae bullcrap
		funk.set('curSection', 0);
		funk.set('curBeat', 0);
		funk.set('curStep', 0);
		funk.set('curDecBeat', 0);
		funk.set('curDecStep', 0);

		funk.set('score', 0);
		funk.set('misses', 0);
		funk.set('hits', 0);
		funk.set('combo', 0);

		funk.set('rating', 0);
		funk.set('ratingName', '');
		funk.set('ratingFC', '');
		funk.set('version', '0.7.3'); // Psych 0.7 模组兼容：模组用 version:find('7.3') 检测引擎版本来开关 shader 特效
		funk.set('meVersion', Main.meVersion.trim());

		funk.set('inGameOver', false);
		funk.set('mustHitSection', false);
		funk.set('altAnim', false);
		funk.set('gfSection', false);

		// Gameplay settings
		funk.set('healthGainMult', game.healthGain);
		funk.set('healthLossMult', game.healthLoss);
		funk.set('playbackRate', game.playbackRate);
		funk.set('instakillOnMiss', game.instakillOnMiss);
		funk.set('botPlay', game.cpuControlled);
		funk.set('practice', game.practiceMode);

		for (i in 0...4) {
			funk.set('defaultPlayerStrumX' + i, 0);
			funk.set('defaultPlayerStrumY' + i, 0);
			funk.set('defaultOpponentStrumX' + i, 0);
			funk.set('defaultOpponentStrumY' + i, 0);
		}

		// Default character positions woooo
		funk.set('defaultBoyfriendX', game.BF_X);
		funk.set('defaultBoyfriendY', game.BF_Y);
		funk.set('defaultOpponentX', game.DAD_X);
		funk.set('defaultOpponentY', game.DAD_Y);
		funk.set('defaultGirlfriendX', game.GF_X);
		funk.set('defaultGirlfriendY', game.GF_Y);

		// Character shit
		funk.set('boyfriendName', PlayState.SONG.player1);
		funk.set('dadName', PlayState.SONG.player2);
		funk.set('gfName', PlayState.SONG.gfVersion);

		// Some settings, no jokes
		funk.set('downscroll', ClientPrefs.data.downScroll);
		funk.set('middlescroll', ClientPrefs.data.middleScroll);
		// 【帧数上限已移除】framerate 偏好已删除，不再暴露给 Lua（桌面端无上限，移动端固定 120）
		funk.set('ghostTapping', ClientPrefs.data.ghostTapping);
		funk.set('hideHud', ClientPrefs.data.hideHud);
		funk.set('timeBarType', ClientPrefs.data.timeBarType);
		funk.set('cameraZoomOnBeat', ClientPrefs.data.camZooms);
		funk.set('flashingLights', ClientPrefs.data.flashing);
		funk.set('noteOffset', ClientPrefs.data.noteOffset);
		funk.set('healthBarAlpha', ClientPrefs.data.healthBarAlpha);
		funk.set('noResetButton', ClientPrefs.data.noReset);
		funk.set('lowQuality', ClientPrefs.data.lowQuality);
		funk.set('shadersEnabled', ClientPrefs.data.shaders);
		funk.set('scriptName', funk.scriptName);
		funk.set('currentModDirectory', Mods.currentModDirectory);

		// Noteskin/Splash
		funk.set('noteSkin', ClientPrefs.data.noteSkin);
		funk.set('noteSkinPostfix', Note.getNoteSkinPostfix());
		funk.set('splashSkin', ClientPrefs.data.splashSkin);
		funk.set('splashSkinPostfix', NoteSplash.getSplashSkinPostfix());
		funk.set('splashAlpha', ClientPrefs.data.splashAlpha);

		funk.set('buildTarget', FunkinLua.getBuildTarget());


	}
}
