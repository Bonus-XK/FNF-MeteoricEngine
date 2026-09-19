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
import objects.Character;
import psychlua.LuaUtils;

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

	/** 原 PlayState.triggerEvent（作用域分析：零遮蔽，92 处成员引用已限定）。 */
	public static function triggerEvent(ps:PlayState, eventName:String, value1:String, value2:String, strumTime:Float)
	{
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(ps.dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						ps.dad.playAnim('cheer', true);
						ps.dad.specialAnim = true;
						ps.dad.heyTimer = flValue2;
					} else if (ps.gf != null) {
						ps.gf.playAnim('cheer', true);
						ps.gf.specialAnim = true;
						ps.gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					ps.boyfriend.playAnim('hey', true);
					ps.boyfriend.specialAnim = true;
					ps.boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				ps.gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					ps.camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = ps.dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = ps.boyfriend;
					case 'gf' | 'girlfriend':
						char = ps.gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = ps.boyfriend;
							case 2: char = ps.gf;
						}
				}

				if (char != null)
				{
					#if (meteoric_debug && sys)
					trace('[DBG-PLAYANIM] t=' + Std.int(strumTime) + ' v1=' + value1 + ' v2=' + value2
						+ ' char=' + char.curCharacter + ' hasAnim=' + (char.animation.getByName(value1) != null)
						+ ' special=' + char.specialAnim);
					#end
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(ps.camFollow != null)
				{
					ps.isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						ps.isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						ps.camFollow.x = flValue1;
						ps.camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = ps.dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = ps.gf;
					case 'boyfriend' | 'bf':
						char = ps.boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = ps.boyfriend;
							case 2: char = ps.gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [ps.camGame, ps.camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(ps.boyfriend != null && ps.boyfriend.curCharacter != value2) {
							if(!ps.boyfriendMap.exists(value2)) {
								ps.addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = ps.boyfriend.alpha;
							ps.boyfriend.alpha = 0.00001;
							// 防御：角色添加失败（图集缺失等）时保持现角色，绝不把 boyfriend 置 null
							var newB:Character = ps.boyfriendMap.get(value2);
							if (newB == null) newB = ps.boyfriend;
							ps.boyfriend = newB;
							ps.boyfriend.alpha = lastAlpha;
							ps.iconP1.changeIcon(ps.boyfriend.healthIcon);
						}
						if (ps.boyfriend != null) ps.setOnScripts('boyfriendName', ps.boyfriend.curCharacter);

					case 1:
						if(ps.dad != null && ps.dad.curCharacter != value2) {
							if(!ps.dadMap.exists(value2)) {
								ps.addCharacterToList(value2, charType);
							}

							var wasGf:Bool = ps.dad.curCharacter.startsWith('gf-') || ps.dad.curCharacter == 'gf';
							var lastAlpha:Float = ps.dad.alpha;
							ps.dad.alpha = 0.00001;
							var newD:Character = ps.dadMap.get(value2);
							if (newD == null) newD = ps.dad; // 防御同上
							ps.dad = newD;
							if(!ps.dad.curCharacter.startsWith('gf-') && ps.dad.curCharacter != 'gf') {
								if(wasGf && ps.gf != null) {
									ps.gf.visible = true;
								}
							} else if(ps.gf != null) {
								ps.gf.visible = false;
							}
							ps.dad.alpha = lastAlpha;
							ps.iconP2.changeIcon(ps.dad.healthIcon);
						}
						if (ps.dad != null) ps.setOnScripts('dadName', ps.dad.curCharacter);

					case 2:
						if(ps.gf != null)
						{
							if(ps.gf.curCharacter != value2)
							{
								if(!ps.gfMap.exists(value2)) {
									ps.addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = ps.gf.alpha;
								ps.gf.alpha = 0.00001;
								var newG:Character = ps.gfMap.get(value2);
								if (newG == null) newG = ps.gf; // 防御同上
								ps.gf = newG;
								ps.gf.alpha = lastAlpha;
							}
							ps.setOnScripts('gfName', ps.gf.curCharacter);
						}
				}
				ps.reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (ps.songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = PlayState.SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						ps.songSpeed = newValue;
					else
						ps.songSpeedTween = FlxTween.tween(ps, {songSpeed: newValue}, flValue2 / ps.playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								ps.songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(ps, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					ps.addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
				}

			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		ps.stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		ps.callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}
}
