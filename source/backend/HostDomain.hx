package backend;

import states.PlayState;
import objects.Note.CastNote;
import backend.ClientPrefs;
import backend.Conductor;
import backend.CrashHandler;
import flixel.addons.transition.FlxTransitionableState;
import psychlua.FunkinLua;
import backend.Highscore;
import backend.MusicBeatState;
import objects.Note;
import backend.Paths;
import backend.Replay;
import substates.ResultsSubState;
import objects.StrumNote;
import backend.WeekData;

/** HostDomain（C 组续跑新建域模块；函数体自 PlayState 迁出，转发入口保留在原处）。 */
@:access(states.PlayState)
class HostDomain
{

	/** 原 PlayState.endSong（作用域分析：零遮蔽，73 处成员引用已限定）。 */
	public static function endSong(ps:PlayState):Bool
	{
		//Should kill you if you tried to cheat
		if(!ps.startingSong) {
			ps.notes.forEach(function(daNote:Note) {
				// 只扣未命中的玩家音符（命中者不扣——自动游玩打完不再死）
				if(daNote.mustPress && !daNote.wasGoodHit && !daNote.ignoreNote
					&& daNote.strumTime < ps.songLength - Conductor.safeZoneOffset) {
					ps.health -= 0.05 * ps.healthLoss;
				}
			});
			// unspawnNotes 为游标数组（后台压缩后整场保留），只统计"尚未生成"的音符，
			// 否则曲末会把整张谱面（数万条）全部扣血——曲目完毕立马死亡
			for (i in ps.currentSpawnId...ps.unspawnNotes.length) {
				if(ps.unspawnNotes[i].strumTime < ps.songLength - Conductor.safeZoneOffset) {
					ps.health -= 0.05 * ps.healthLoss;
				}
			}

			if(ps.doDeathCheck()) {
				return false;
			}
		}

		ps.clampGameplayTotals();
		ps.timeBar.visible = false;
		ps.timeTxt.visible = false;
		ps.canPause = false;
		ps.endingSong = true;
		ps.camZooming = false;
		ps.inCutscene = false;
		ps.updateTime = false;

		// 曲终释放（Meteoric Fix 续）：最后音符已全部生成，unspawnNotes + CastNote 平行数组
		// 成为死重（约 250MB）。结算界面不再需要它们；重开/回溯/换难度/编谱/回放全部经
		// reloadChartSourceIfNeeded（快扫重解析）恢复，回放指纹已有 create 期存档。
		// 无条件释放（不设 currentSpawnId 守卫）：谱面尾部可能比音频长（最后音符未生成完
		// 也照样进结算），守卫会让释放静默失效；重开路径本就会重解析，无一致性风险。
		ps.unspawnNotes = [];
		PlayState.spamNotes = [];
		CastNote.resetPacked();
		// seqNote/seqHit 链快照（~20MB 引用）一并释放：曲终无判定，重开/回溯重建
		Note.seqNote = [];
		Note.seqHit = [];
		CrashHandler.mark('PlayState.endSong');

		PlayState.deathCounter = 0;
		PlayState.seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		if(ps.achievementObj != null)
			return false;
		else if(!ps.replayMode)
		{
			var noMissWeek:String = WeekData.getWeekFileName() + '_nomiss';
			var achieve:String = ps.checkForAchievement([noMissWeek, 'r_ubad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger']);
			if(achieve != null) {
				ps.startAchievement(achieve);
				return false;
			}
		}
		#end

		var ret:Dynamic = ps.callOnScripts('onEndSong', null, true);
		if(ret != FunkinLua.Function_Stop && !ps.transitioning)
		{
			ps.playbackRate = 1;

			// 本局完成：保存回放文件（自动游玩/回放/编谱不录制）
			var replayForResults:Replay = null;
			if (ps.recordingReplay && ps.currentReplay != null && !ps.usedAutoplay)
			{
				// 游玩期 SONG.notes 已被剥离，指纹用 create 期记录值（内容与完整谱面一致）
				ps.currentReplay.fingerprint = PlayState.recordedChartFingerprint;
				ps.currentReplay.score = ps.songScore;
				ps.currentReplay.misses = ps.songMisses;
				ps.currentReplay.percent = Math.isNaN(ps.ratingPercent) ? 0 : ps.ratingPercent;
				ps.currentReplay.save();
				replayForResults = ps.currentReplay;
				ps.recordingReplay = false;
			}

			if (PlayState.chartingMode)
			{
				ps.openChartEditor();
				return false;
			}

			// 无限轮回：曲目完成后不进入结算，时间回溯后重新开始（不保存分数）
			if (ClientPrefs.getGameplaySetting('infiniteloop', false))
			{
				ps.restartSongWithoutReload(true);
				return false;
			}

			#if !switch
			var percent:Float = ps.ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			if(!ps.usedAutoplay)
				Highscore.saveScore(PlayState.SONG.song, ps.songScore, PlayState.storyDifficulty, percent);
			#end

			// ===== 结算前释放游玩视觉（Meteoric Fix 续：结算时只留场景，人物/判定线/音符移除）=====
			// 原生贴图（人物/判定线/音符）在此真正归还 OS；结算背景保持原版黑底。
			// 重试/回放会重建（finishRestart → generateStaticArrows + reloadDefaultCharacters
			// + generateChartNotes；resetState → 全新 create）。
			#if desktop
			// 1. 音符/seq 链（unspawnNotes 已在 endSong 前段释放，这里清理存活音符与池）
			ps.KillNotes();
			// 2. 判定线（与 finishRestart 同一套拆法）
			while (ps.strumLineNotes.length > 0)
			{
				var strum:StrumNote = ps.strumLineNotes.members[0];
				ps.strumLineNotes.remove(strum, true);
				strum.destroy();
			}
			ps.playerStrums.clear();
			ps.opponentStrums.clear();
			// 3. 人物（BF/Dad/GF 大贴图）
			ps.destroyAllCharacters();
			// 4. 清空本局贴图租约并释放 useCount=0 的贴图（人物/判定线/音符等）
			Paths.localTrackedAssets = [];
			Paths.clearUnusedMemory(false);
			// 5. 上锁：本 State 更新立即暂停（结算转场/关闭回调的窗口期仍会被驱动）
			ps._visualsTorn = true;
			#end

			ps.persistentUpdate = false;
			// 结算时隐藏 HUD 判定侧边栏（stage 级 TextField 不随 flixel 状态隐没；
			// 此处 _visualsTorn 已上锁，updateJudgementTxt 不再运行——必须在此一次隐藏，
			// 结算关闭后 updateJudgementTxt 恢复运行会自动按设置重新显示）
			if (ps.hud != null && ps.hud.judgementField != null) ps.hud.judgementField.visible = false;

			// 联机：进入普通结算界面（精简版，关闭后返回联机大厅）
			if (PlayState.isOnlineMode)
			{
				ps.onlineFinishAndShowResults(false);
				return false;
			}

			var resultsSubState:ResultsSubState = new ResultsSubState(replayForResults != null);
			resultsSubState.closeCallback = function() {
				ps.persistentUpdate = true;
				if (resultsSubState.resultAction == 'retry')
				{
					if (ClientPrefs.data.restartNoChartReload)
						ps.restartSongWithoutReload();
					else
					{
						FlxTransitionableState.skipNextTransIn = true;
						FlxTransitionableState.skipNextTransOut = true;
						MusicBeatState.resetState();
					}
				}
				else if (resultsSubState.resultAction == 'replay')
				{
					if (replayForResults != null)
					{
						// 回放本局：原地重开并进入回放模式
						// 防止 Mod 脚本遗留 hideHud=true 导致回放时 HUD 消失
						ClientPrefs.resetHideHud();
						PlayState.queuedReplay = replayForResults;
						FlxTransitionableState.skipNextTransIn = true;
						FlxTransitionableState.skipNextTransOut = true;
						MusicBeatState.resetState();
						return;
					}
					ps.proceedAfterEndSong();
				}
				else
				{
					ps.proceedAfterEndSong();
				}
			};
			ps.openSubState(resultsSubState);
			return false;
		}
		return true;
	}
}
