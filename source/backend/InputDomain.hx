package backend;

import states.PlayState;
import backend.ClientPrefs;
import backend.Conductor;
import backend.Multiplayer;
import objects.Note;
import backend.Paths;
import objects.StrumNote;

/** InputDomain（C 组续跑新建域模块；函数体自 PlayState 迁出，转发入口保留在原处）。 */
@:access(states.PlayState)
class InputDomain
{

	/** 原 PlayState.keysCheck（作用域分析：零遮蔽，41 处成员引用已限定）。 */
	public static function keysCheck(ps:PlayState):Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in ps.keysArray)
		{
			holdArray.push(ps.controls.pressed(key));
			pressArray.push(ps.controls.justPressed(key));
			releaseArray.push(ps.controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(ps.controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && ps.strumsBlocked[i] != true)
					ps.keyPressed(i);

		if (ps.startedCountdown && !ps.boyfriend.stunned && ps.generatedMusic)
		{
			// rewritten inputs???
			if(ps.notes.length > 0)
			{
				ps.notes.forEachAlive(function(daNote:Note)
				{
					// hold note functions
					if (ps.strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && holdArray[daNote.noteData] && daNote.canBeHit
					&& daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit) {
						if (ClientPrefs.data.noteJudgment == 'KE 判定')
						{
							// KE 判定：长条不参与判定，按住时子段仅做视觉消除
							daNote.wasGoodHit = true;
							if (ps.recordingReplay && ps.currentReplay != null)
								ps.currentReplay.addEvent(daNote.chartSeq, daNote.strumTime, daNote.noteData, 'sus');
							daNote.active = false;
							daNote.visible = false;
							ps.notes.invalidateNote(daNote);
						}
						else ps.goodNoteHit(daNote);
					}
				});
			}

			if (holdArray.contains(true) && !ps.endingSong) {
				#if ACHIEVEMENTS_ALLOWED
				var achieve:String = ps.checkForAchievement(['oversinging']);
				if (achieve != null) {
					ps.startAchievement(achieve);
				}
				#end
			}
			else if (!ps.endingSong && !ps.finishingSong && !ClientPrefs.data.hudOnly && ps.boyfriend != null
				&& ps.boyfriend.animation != null && ps.boyfriend.animation.curAnim != null
				&& ps.boyfriend.getAnimationName().startsWith('sing') && !ps.boyfriend.getAnimationName().endsWith('miss')
				&& ps.boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 / FlxG.sound.music.pitch) * ps.boyfriend.singDuration)
			{
				ps.boyfriend.dance();
				//boyfriend.animation.curAnim.finish();
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((ps.controls.controllerMode || ps.strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || ps.strumsBlocked[i] == true)
					ps.keyReleased(i);

		// 联机：转发己方按键事件，驱动对方按键条
		if (PlayState.isOnlineMode && ps.startedCountdown && !ps.paused && !ps.endingSong && !ps.cpuControlled && !ps.replayMode)
		{
			for (i in 0...4)
			{
				if (pressArray[i]) Multiplayer.send('PRESS|' + i);
				if (releaseArray[i]) Multiplayer.send('RELEASE|' + i);
			}
		}
	}

	/** 原 PlayState.keyPressed（作用域分析：零遮蔽，38 处成员引用已限定）。 */
	public static function keyPressed(ps:PlayState, key:Int)
	{
		if (!ps.cpuControlled && !ps.paused && !ps.rewinding && key > -1 && ps.startedCountdown && (!ps.replayMode || ps.replayInjecting))
		{
			// 回放录制：记录按键按下事件（重放时按时间注入，走同样的判定路径）
			if (ps.recordingReplay && ps.currentReplay != null)
				ps.currentReplay.recordInput(Conductor.songPosition, key, false);
			var mashPenalty:Bool = false;

			if(ps.notes.length > 0 && !ps.boyfriend.stunned && ps.generatedMusic && !ps.endingSong)
			{
				//more accurate hit time for the ratings?
				var lastTime:Float = Conductor.songPosition;
				if(Conductor.songPosition >= 0) Conductor.syncToMusic();

				var canMiss:Bool = !ClientPrefs.data.ghostTapping;

				// KE 判定：防乱按（Kade Engine 规则）——按下按键数超过可命中音符数时直接扣分
				if (ClientPrefs.data.noteJudgment == 'KE 判定')
				{
					var hasHittable:Bool = false;
					ps.notes.forEachAlive(function(daNote:Note)
					{
						if (daNote.noteData == key && daNote.canBeHit && daNote.mustPress && !daNote.tooLate &&
							!daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
							hasHittable = true;
					});

					if (hasHittable)
					{
						var hittableCount:Int = 0;
						ps.notes.forEachAlive(function(daNote:Note)
						{
							if (daNote.canBeHit && daNote.mustPress && !daNote.tooLate)
								hittableCount++;
						});

						var pressedCount:Int = 0;
						for (i in 0...ps.keysArray.length)
							if (ps.strumsBlocked[i] != true && ps.controls.pressed(ps.keysArray[i]))
								pressedCount++;

						// 只有一个音符时可多容忍一个按键，其余情况不能超过可命中音符数
						var allowedPresses:Int = (hittableCount == 1) ? hittableCount + 1 : hittableCount;
						if (pressedCount > allowedPresses)
						{
							mashPenalty = true;
							ps.songScore -= 25;
							FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
							ps.playerStrums.forEach(function(spr:StrumNote)
							{
								if (spr != null && spr.animation.curAnim.name != 'static')
								{
									spr.playAnim('static');
									spr.resetAnim = 0;
								}
							});
						}
					}
				}

				if (!mashPenalty)
				{
					// heavily based on my own code LOL if it aint broke dont fix it
					var pressNotes:Array<Note> = [];
					var notesStopped:Bool = false;
					var sortedNotesList:Array<Note> = [];
					ps.notes.forEachAlive(function(daNote:Note)
					{
						if (ps.strumsBlocked[daNote.noteData] != true && daNote.canBeHit && daNote.mustPress &&
							!daNote.tooLate && !daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
						{
							if(daNote.noteData == key) sortedNotesList.push(daNote);
							canMiss = true;
						}
					});
					sortedNotesList.sort(PlayState.sortHitNotes);

					if (sortedNotesList.length > 0) {
						for (epicNote in sortedNotesList)
						{
							for (doubleNote in pressNotes) {
								if (Math.abs(doubleNote.strumTime - epicNote.strumTime) < 1) {
									ps.notes.invalidateNote(doubleNote);
								} else
									notesStopped = true;
							}

							// eee jack detection before was not super good
							if (!notesStopped) {
								ps.goodNoteHit(epicNote);
								pressNotes.push(epicNote);
							}

						}
					}
					else {
						ps.callOnScripts('onGhostTap', [key]);
						if (canMiss && !ps.boyfriend.stunned)
						{
							// 回放录制：记录这次会真正触发 Miss 的空按（幽灵点击开启且非 KE 时不记）
							if (ps.recordingReplay && ps.currentReplay != null
								&& (ClientPrefs.data.noteJudgment == 'KE 判定' || !ClientPrefs.data.ghostTapping))
								ps.recordReplayEvent(-1, Conductor.songPosition, key, 'mp');
							// KE 判定防乱按：旁边有可命中音符时，按到没有音符的列也强制 Miss（等同关闭幽灵点击）
							if (ClientPrefs.data.noteJudgment == 'KE 判定')
								ps.noteMissPress(key, true);
							else
								ps.noteMissPress(key);
						}
					}

					// I dunno what you need this for but here you go
					//									- Shubs

					// Shubs, this is for the "Just the Two of Us" achievement lol
					//									- Shadow Mario
					if(!ps.keysPressed.contains(key)) ps.keysPressed.push(key);
				}

				//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
				Conductor.setPosition(lastTime);
			}

			var spr:StrumNote = ps.playerStrums.members[key];
			if(ps.strumsBlocked[key] != true && spr != null && !mashPenalty && spr.animation.curAnim.name != 'confirm')
			{
				if (ClientPrefs.data.playerLightStrum)
				{
					spr.playAnim('pressed');
					spr.resetAnim = 0;
				}
			}
			ps.callOnScripts('onKeyPress', [key]);
		}
	}
}
