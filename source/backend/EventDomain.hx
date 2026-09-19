package backend;

import openfl.events.Event;
import flixel.FlxG;
import backend.BaseStage;
import backend.MusicBeatState;
import objects.Note.EventNote;
import states.PlayState;
import backend.Paths;
import backend.Controls;
import flixel.input.keyboard.FlxKey;
import backend.ClientPrefs;
import psychlua.FunkinLua;

/** 事件调度域（C4 首批迁出，7 个零遮蔽函数中的 5 个）。
 *  PlayState 保留同签名转发入口，全仓调用点零改动。
 *  可见性说明：原 eventPushed / onStageDeactivate / onStageActivate 为 private，跨模块调用在本类放宽为 public。 */
@:access(states.PlayState)
@:access(backend.MusicBeatState)
class EventDomain
{
	/** 下一段对话（原 PlayState.startNextDialogue）。 */
	public static function startNextDialogue(ps:PlayState):Void {
		ps.dialogueCount++;
		ps.callOnScripts('onNextDialogue', [ps.dialogueCount]);
	}

	/** 跳过对话（原 PlayState.skipDialogue）。 */
	public static function skipDialogue(ps:PlayState):Void {
		ps.callOnScripts('onSkipDialogue', [ps.dialogueCount]);
	}

	/** 事件入队（原 PlayState.eventPushed）。 */
	public static function eventPushed(ps:PlayState, event:EventNote):Void {
		ps.eventPushedUnique(event);
		if(ps.eventsPushed.contains(event.event)) {
			return;
		}

		ps.stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		ps.eventsPushed.push(event.event);
	}

	#if mobile
	/** 退后台：冻结游戏并暂停音频（原 PlayState.onStageDeactivate）。 */
	public static function onStageDeactivate(ps:PlayState, event:Event):Void
	{
		trace('[PAUSE] onStageDeactivate started=' + ps.startedCountdown + ' paused=' + ps.paused + ' canPause=' + ps.canPause);
		if (ps.startedCountdown && !ps.endingSong)
		{
			if (!ps.paused && ps.canPause)
			{
				trace('[PAUSE] openPauseMenu from deactivate');
				ps.openPauseMenu();
			}
			// Meteoric：退后台=冻结游戏——音频位置一并暂停（仅开暂停菜单音乐仍会继续响）
			ps.freezeBackgroundAudio();
		}
	}

	/** 回前台：恢复被后台冻结的音频（原 PlayState.onStageActivate）。 */
	public static function onStageActivate(ps:PlayState, event:Event):Void
	{
		ps.restoreBackgroundAudio();
		// flixel 在焦点恢复时会自动 resume 失焦前“正在播放”的声音（FlxG.sound.onFocus()），
		// 而本钩子在 FlxGame 焦点处理之后执行（FlxGame 先注册）——若暂停菜单仍打开，
		// 歌曲伴奏/人声会被误恢复，立即重新冻结；暂停菜单音乐与场景音效仍由 flixel 正常续播。
		// 玩家点“返回游戏”后由 closeSubState → resyncVocals 统一恢复歌曲。
		if (ps.paused)
		{
			if (FlxG.sound.music != null) FlxG.sound.music.pause();
			if (ps.vocals != null) ps.vocals.pause();
			if (ps.opponentVocals != null) ps.opponentVocals.pause();
		}
	}
	#end

	/** 原 PlayState.cacheCountdown（作用域分析：零遮蔽，13 处成员引用已限定）。 */
	public static function cacheCountdown(ps:PlayState)
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(PlayState.stageUI) {
			case "pixel": ['${PlayState.stageUI}UI/ready-pixel', '${PlayState.stageUI}UI/set-pixel', '${PlayState.stageUI}UI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${PlayState.stageUI}UI/ready', '${PlayState.stageUI}UI/set', '${PlayState.stageUI}UI/go'];
		}
		introAssets.set(PlayState.stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(PlayState.stageUI);
		for (asset in introAlts) Paths.image(asset);

		Paths.sound('intro3' + ps.introSoundsSuffix);
		Paths.sound('intro2' + ps.introSoundsSuffix);
		Paths.sound('intro1' + ps.introSoundsSuffix);
		Paths.sound('introGo' + ps.introSoundsSuffix);
	}

	/** 原 PlayState.getKeyFromEvent（作用域分析：零遮蔽，0 处成员引用已限定）。 */
	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	/** 原 PlayState.makeEvent（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function makeEvent(ps:PlayState, event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		ps.eventNotes.push(subEvent);
		ps.eventPushed(subEvent);
		ps.callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	/** 原 PlayState.eventEarlyTrigger（作用域分析：零遮蔽，1 处成员引用已限定）。 */
	public static function eventEarlyTrigger(ps:PlayState, event:EventNote):Float
	{
		var returnedValue:Null<Float> = ps.callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != FunkinLua.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	/** 原 PlayState.eventPushedUnique（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function eventPushedUnique(ps:PlayState, event:EventNote)
	{
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				ps.addCharacterToList(newCharacter, charType);

			case 'Play Sound':
				ps.precacheList.set(event.value1, 'sound');
				Paths.sound(event.value1);
		}
		ps.stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	/** 原 PlayState.recordReplayEvent（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function recordReplayEvent(ps:PlayState, seq:Int, t:Float, d:Int, r:String):Void
	{
		if (ps.recordingReplay && ps.currentReplay != null && !ps.cpuControlled && !ps.replayMode)
			ps.currentReplay.addEvent(seq, t, d, r);
	}
}
