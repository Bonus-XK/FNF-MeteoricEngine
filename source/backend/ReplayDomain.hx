package backend;

import states.PlayState;
import backend.ClientPrefs;
import backend.Conductor;
import objects.Note;
import backend.Replay.ReplayInput;

/** ReplayDomain（C 组续跑新建域模块；函数体自 PlayState 迁出，转发入口保留在原处）。 */
@:access(states.PlayState)
class ReplayDomain
{

	/** 原 PlayState.updateReplayInputs（作用域分析：零遮蔽，26 处成员引用已限定）。 */
	public static function updateReplayInputs(ps:PlayState):Void
	{
		if (!ps.startedCountdown || ps.paused || ps.rewinding || ps.endingSong || ps.inCutscene) return;

		// 注入到点按键事件：按下走 keyPressed（真实判定），抬起走 keyReleased（strum 复位）
		ps.replayInjecting = true;
		while (ps.replayInputPtr < ps.replayInputs.length && Conductor.songPosition >= ps.replayInputs[ps.replayInputPtr].t)
		{
			var ev:ReplayInput = ps.replayInputs[ps.replayInputPtr++];
			if (ev.d < 0 || ev.d > 3) continue;
			if (ev.u)
			{
				ps.replayHeld[ev.d] = false;
				ps.keyReleased(ev.d);
			}
			else
			{
				ps.replayHeld[ev.d] = true;
				ps.keyPressed(ev.d);
			}
		}
		ps.replayInjecting = false;

		// 长按：与 keysCheck 的 HOLD 段一致（按住期间长条子段逐个命中/消除）
		if (ps.generatedMusic && ps.notes.length > 0 && !ps.boyfriend.stunned)
		{
			var anyHold:Bool = false;
			for (i in 0...4)
				if (ps.replayHeld[i]) { anyHold = true; break; }
			if (anyHold)
			{
				ps.notes.forEachAlive(function(daNote:Note)
				{
					if (ps.strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && ps.replayHeld[daNote.noteData]
						&& daNote.canBeHit && daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit)
					{
						if (ClientPrefs.data.noteJudgment == 'KE 判定')
						{
							// KE 判定：长条不参与判定，按住时子段仅做视觉消除
							daNote.wasGoodHit = true;
							daNote.active = false;
							daNote.visible = false;
							ps.notes.invalidateNote(daNote);
						}
						else ps.goodNoteHit(daNote);
					}
				});
			}
		}
	}

	/** 原 PlayState.resetReplayToTime（作用域分析：零遮蔽，7 处成员引用已限定）。 */
	public static function resetReplayToTime(ps:PlayState, t:Float):Void
	{
		ps.replayInputPtr = 0;
		while (ps.replayInputPtr < ps.replayInputs.length && ps.replayInputs[ps.replayInputPtr].t < t)
			ps.replayInputPtr++;
		ps.replayHeld = [false, false, false, false];
	}
}
