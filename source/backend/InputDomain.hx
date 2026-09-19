package backend;

import states.PlayState;
import backend.ClientPrefs;
import backend.Conductor;
import backend.Multiplayer;
import objects.Note;

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
}
