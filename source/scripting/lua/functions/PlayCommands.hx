package scripting.lua.functions;

import scripting.lua.FunkinLua;
import backend.Highscore;
import substates.PauseSubState;
import flixel.addons.transition.FlxTransitionableState;
import states.StoryMenuState;
import states.FreeplayState;

//
// PlayCommands —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class PlayCommands
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "loadSong", function(?name:String = null, ?difficultyNum:Int = -1) {
			if(name == null || name.length < 1)
				name = PlayState.SONG.song;
			if (difficultyNum == -1)
				difficultyNum = PlayState.storyDifficulty;

			var poop = Highscore.formatSong(name, difficultyNum);
			PlayState.storyDifficulty = difficultyNum;
			game.persistentUpdate = false;
			var __folder:String = Paths.formatToSongPath(name);
			var __chart:String = backend.Song.resolveChartPath(poop, __folder);
			trace('[loadSong] name=' + name + ' diff=' + difficultyNum + ' json=' + poop + ' folder=' + __folder
				+ ' curMod=' + Mods.currentModDirectory + ' globals=' + Mods.getGlobalMods().join(',')
				+ ' difficultyList=[' + backend.Difficulty.list.join(',') + ']'
				+ ' chart=' + Std.string(__chart));
			var __ok:Bool = LoadingState.loadSongAndSwitchState(new PlayState(), Paths.formatToSongPath(name), poop, Paths.formatToSongPath(name));
			trace('[loadSong] switchState ok=' + __ok);
			#if sys
			try
			{
				var __f = sys.io.File.append('/tmp/meteoric_loadsong.log', false);
				__f.writeString('[loadSong] name=' + name + ' diff=' + difficultyNum + ' json=' + poop
					+ ' folder=' + __folder + ' curMod=' + Mods.currentModDirectory
					+ ' globals=' + Mods.getGlobalMods().join(',')
					+ ' difficultyList=[' + backend.Difficulty.list.join(',') + ']'
					+ ' chart=' + Std.string(__chart) + ' ok=' + __ok + '\n');
				__f.close();
			}
			catch(e:Dynamic) {}
			#end

			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
			if(game.vocals != null)
			{
				game.vocals.pause();
				game.vocals.volume = 0;
			}
			FlxG.camera.followLerp = 0;
		});

		Lua_helper.add_callback(lua, "triggerEvent", function(name:String, arg1:Dynamic, arg2:Dynamic) {
			var value1:String = arg1;
			var value2:String = arg2;
			game.triggerEvent(name, value1, value2, Conductor.songPosition);
			//trace('Triggered event: ' + name + ', ' + value1 + ', ' + value2);
			return true;
		});

		Lua_helper.add_callback(lua, "startCountdown", function() {
			game.startCountdown();
			return true;
		});

		Lua_helper.add_callback(lua, "endSong", function() {
			game.KillNotes();
			game.endSong();
			return true;
		});

		Lua_helper.add_callback(lua, "restartSong", function(?skipTransition:Bool = false) {
			game.persistentUpdate = false;
			FlxG.camera.followLerp = 0;
			PauseSubState.restartSong(skipTransition);
			return true;
		});

		Lua_helper.add_callback(lua, "exitSong", function(?skipTransition:Bool = false) {
			if(skipTransition)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
			}

			PlayState.cancelMusicFadeTween();
			CustomFadeTransition.nextCamera = game.camOther;
			if(FlxTransitionableState.skipNextTransIn)
				CustomFadeTransition.nextCamera = null;

			if(PlayState.isStoryMode)
				MusicBeatState.switchState(new StoryMenuState());
			else
				MusicBeatState.switchState(new FreeplayState());

			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			PlayState.changedDifficulty = false;
			PlayState.chartingMode = false;
			game.transitioning = true;
			FlxG.camera.followLerp = 0;
			Mods.loadTopMod();
			return true;
		});

		Lua_helper.add_callback(lua, "getSongPosition", function() {
			return Conductor.songPosition;
		});

		Lua_helper.add_callback(lua, "getMouseX", function(camera:String) {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).x;
		});

		Lua_helper.add_callback(lua, "getMouseY", function(camera:String) {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).y;
		});

		Lua_helper.add_callback(lua, "getPixelColor", function(obj:String, x:Int, y:Int) {
			var split:Array<String> = obj.split('.');
			var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(spr != null) return spr.pixels.getPixel32(x, y);
			return FlxColor.BLACK;
		});
	}
}
