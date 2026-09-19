package backend;

import flixel.FlxG;
import flixel.util.FlxSort;
import backend.BaseStage;
import backend.ClientPrefs;
import backend.Conductor;
import backend.Discord;
import backend.MusicBeatState;
import backend.Paths;
import backend.Song;
import objects.Note;
import objects.StrumNote;
import states.PlayState;
import states.editors.ChartingState;

/** 音符与谱面域（C2 首批迁出）。
 *  迁出策略：函数体迁到本类；PlayState 保留**同签名转发入口**，故全仓 `PlayState.*` 调用点零改动。
 *  访问 PlayState / MusicBeatState 的私有成员依赖下方 @:access。
 *  可见性说明：原 openChartEditor / flashOppStrums / isSongChartStripped 为 private，跨模块调用故在本类放宽为 public；
 *  外部可及性未变（它们仍只在 PlayState 内部被调用，转发器保持原修饰符）。
 *  说明：本批仅迁出 6 个低依赖函数（原计划 30 个的其余 24 个需先做作用域分析，见 PLAYSTATE-SPLIT-PLAN.md）。 */
@:access(states.PlayState)
@:access(backend.MusicBeatState)
class NoteChartDomain
{
	/** 音符排序：纯函数（原 PlayState.sortHitNotes）。 */
	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	/** 谱面剥离判定：纯函数（原 PlayState.isSongChartStripped）。 */
	public static function isSongChartStripped(s:SwagSong):Bool
	{
		if (s == null || s.notes == null) return false;
		var any:Bool = false;
		for (sec in s.notes)
		{
			if (sec == null) continue;
			if (sec.sectionNotes == null) return false; // 异常态：保守视为未剥离
			if (sec.sectionNotes.length > 0) return false;
			any = true;
		}
		return any;
	}

	/** 音符命中特效（原 PlayState.spawnNoteSplashOnNote）。 */
	public static function spawnNoteSplashOnNote(ps:PlayState, note:Note):Void
	{
		if(note != null) {
			var strum:StrumNote = ps.playerStrums.members[note.noteData];
			if(strum != null)
				ps.spawnNoteSplash(strum.x, strum.y, note.noteData, note);
		}
	}

	/** 联机对手箭头闪光（原 PlayState.flashOppStrums）。 */
	public static function flashOppStrums(ps:PlayState, data:Int, anim:String, confirm:Bool):Void
	{
		if (ps.onlineOppStrums == null) return;
		var s:StrumNote = ps.onlineOppStrums.members[data];
		if (s == null) return;
		s.playAnim(anim, true);
		if (confirm)
			s.resetAnim = Conductor.stepCrochet * 1.25 / 1000 / ps.playbackRate;
	}

	/** 空按（原 PlayState.noteMissPress）。 */
	public static function noteMissPress(ps:PlayState, direction:Int = 1, force:Bool = false):Void
	{
		ps.stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction)); //Psych 1.0.4：场景误触回调（Weekend 1）
		if(ClientPrefs.data.ghostTapping && !force) return; //fuck it

		ps.noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		ps.callOnScripts('noteMissPress', [direction]);
	}

	/** 打开谱面编辑器（原 PlayState.openChartEditor）。 */
	public static function openChartEditor(ps:PlayState):Void
	{
		// 编谱需要完整谱面：若游玩期已剥离 SONG.notes，先从缓存恢复
		PlayState.reloadChartSourceIfNeeded();
		FlxG.camera.followLerp = 0;
		ps.persistentUpdate = false;
		ps.paused = true;
		PlayState.cancelMusicFadeTween();
		PlayState.chartingMode = true;

		#if desktop
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end
		
		MusicBeatState.switchState(new ChartingState());
	}
}
