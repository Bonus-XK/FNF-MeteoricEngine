package psychlua.functions;

import psychlua.FunkinLua;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueBoxPsych.DialogueFile;
import sys.FileSystem;

//
// DialogueCommands —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class DialogueCommands
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "startDialogue", function(dialogueFile:String, music:String = null) {
			var path:String;
			#if MODS_ALLOWED
			path = Paths.modsJson(Paths.formatToSongPath(PlayState.SONG.song) + '/' + dialogueFile);
			if(!FileSystem.exists(path))
			#end
				path = Paths.json(Paths.formatToSongPath(PlayState.SONG.song) + '/' + dialogueFile);

			FunkinLua.luaTrace('startDialogue: Trying to load dialogue: ' + path);

			#if MODS_ALLOWED
			if(FileSystem.exists(path))
			#else
			if(Assets.exists(path))
			#end
			{
				var shit:DialogueFile = DialogueBoxPsych.parseDialogue(path);
				if(shit.dialogue.length > 0) {
					game.startDialogue(shit, music);
					FunkinLua.luaTrace('startDialogue: Successfully loaded dialogue', false, false, FlxColor.GREEN);
					return true;
				} else {
					FunkinLua.luaTrace('startDialogue: Your dialogue file is badly formatted!', false, false, FlxColor.RED);
				}
			} else {
				FunkinLua.luaTrace('startDialogue: Dialogue file not found', false, false, FlxColor.RED);
				if(game.endingSong) {
					game.endSong();
				} else {
					game.startCountdown();
				}
			}
			return false;
		});

		Lua_helper.add_callback(lua, "startVideo", function(videoFile:String) {
			#if VIDEOS_ALLOWED
			if(FileSystem.exists(Paths.video(videoFile))) {
				game.startVideo(videoFile);
				return true;
			} else {
				FunkinLua.luaTrace('startVideo: Video file not found: ' + videoFile, false, false, FlxColor.RED);
			}
			return false;

			#else
			if(game.endingSong) {
				game.endSong();
			} else {
				game.startCountdown();
			}
			return true;
			#end
		});
	}
}
