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
import objects.Note.CastNote;
import backend.CrashHandler;
import objects.Note.SpamNoteData;

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

	/** 原 PlayState.noteSpawn（作用域分析：零遮蔽，124 处成员引用已限定）。 */
	public static function noteSpawn(ps:PlayState):Void
	{
		#if false
		// ===== 安卓：备份式按时间插入（直建 Note 管线配套）=====
		if (ps.unspawnNotes.length > 0)
		{
			var time:Float = ps.spawnTime * ps.playbackRate;
			if (ps.songSpeed < 1) time /= ps.songSpeed;
			if (ps.unspawnNotes[0].multSpeed < 1) time /= ps.unspawnNotes[0].multSpeed;
			while (ps.unspawnNotes.length > 0 && ps.unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = ps.unspawnNotes[0];
				ps.notes.insert(0, dunceNote);
				dunceNote.spawned = true;
				ps.callOnLuas('onSpawnNote', [ps.notes.members.indexOf(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				ps.callOnHScript('onSpawnNote', [dunceNote]);
				ps.unspawnNotes.splice(0, 1);
			}
		}
		return;
		#end
		if (ps.currentSpawnId >= ps.unspawnNotes.length)
		{
			ps.spamSpawn();
			if (ClientPrefs.data.fastSort) ps.notes.fasterSort();
			return;
		}

		// 【Turbo】过载滞回（移植 Seiun）：上一帧数据级结算 ≥128 条 → 进入 30 帧过载档；
		// 滞回防止节流模式在"cursor 被长条头钉住/drain 短暂归零"时反复开关。
		if (PlayState.densePerfMode && ps.cpuControlled && !ps.replayMode && ps._bulkDrainedLast >= 128)
			ps._overloadFrames = 30;
		else if (ps._overloadFrames > 0)
			ps._overloadFrames--;
		ps._bulkDrainedLast = 0;
		// 结算 strum 高亮每帧每轨一次
		ps._settleAnimDone = [false, false, false, false];

		var fixedPosition:Float = Conductor.songPosition - ClientPrefs.data.noteOffset;
		// 快速跳谱（bulkSkip）：只允许在"真实时间跳变"（单帧前进 > JUMP_DELTA 或显式跳时间）时
		// 静默消费已过音符；正常逐帧（含轻度卡顿 GC 掉帧）一律不消费——音符永远按窗口逐帧生成，
		// 杜绝"一小段箭头随机消失、结算总数对不上"的问题。
		if (ClientPrefs.data.bulkSkip && ClientPrefs.data.optimizeSpawnNote
			&& (Conductor.songPosition - ps.lastNoteSpawnPos > PlayState.JUMP_DETECT_MS))
		{
			var skipped:Int = 0;
			var firstId:Int = ps.currentSpawnId;
			var lastId:Int = ps.unspawnNotes.length;
			while (firstId < lastId)
			{
				var middleId:Int = (firstId + lastId) >>> 1;
				if (ps.unspawnNotes[middleId].strumTime <= Conductor.songPosition)
					firstId = middleId + 1;
				else
					lastId = middleId;
			}
			skipped = firstId - ps.currentSpawnId;
			if (skipped > 0)
				trace('[BULKSKIP] consumed=' + skipped + ' at pos=' + Std.int(Conductor.songPosition)
					+ ' delta=' + Std.int(Conductor.songPosition - ps.lastNoteSpawnPos) + 'ms');
			ps.currentSpawnId = firstId;
		}

		var limitCount:Int = 0;
		var limitNotes:Int = ps.perfLimitNotes;
		if (limitNotes > 0) limitCount = ps.notes.countLiving();

		// 全局视觉预算（每 500ms 统计一次，不再逐帧走查 4096 条）
		if (Conductor.songPosition - ps.lastVisBudgetCalc > 500)
		{
			ps.lastVisBudgetCalc = Conductor.songPosition;
			var castsInWin:Int = 0;
			var walk:Int = ps.currentSpawnId;
			var probeEnd:Float = fixedPosition + (PlayState.densePerfMode ? 1100 : ps.spawnTime) * 2;
			while (walk < ps.unspawnNotes.length && castsInWin < 4096)
			{
				if (ps.unspawnNotes[walk].strumTime > probeEnd) break;
				castsInWin++;
				walk++;
			}
			if (castsInWin > 0)
			{
				// 【500 帧补丁】密集谱视觉预算收窄：总预算 1800→(1200→)700，单簇下限 3→(2→)1：
				// 场上精灵数与主循环/回收量同步下降；纯渲染采样，不参与判定/计分，视觉仍是原版"簇"形态。
				var visBudget:Int = PlayState.densePerfMode ? 700 : PlayState.VISUAL_BUDGET;
				var visMin:Int = PlayState.densePerfMode ? 1 : 3;
				var visMax:Int = PlayState.densePerfMode ? 8 : 12;
				ps.clusterVisCap = Std.int(visBudget / castsInWin);
				if (ps.clusterVisCap > visMax) ps.clusterVisCap = visMax;
				if (ps.clusterVisCap < visMin) ps.clusterVisCap = visMin;
			}
			else ps.clusterVisCap = 12;
		}

		if (ps.currentSpawnId == 0 && !ps._stageMarkSpawn)
		{
			ps._stageMarkSpawn = true;
			CrashHandler.mark('PlayState.noteSpawn:start');
		}

		// 【Turbo·数据级批量结算】dense + botplay + 过载 + 非聚合区：
		// 视距内半带（≤ spawnWindow/2 距判定线）的音符不建 Sprite 直接结算（计分/命中/血量
		// 按密度加权、判定恒为满分），物化预算集中到外半带 —— 过载时不再为"注定要结算"的
		// 音符白付构造费，也不触发对象上限的延迟进场（聚合区内禁软截止：走真实物化+上限，
		// 视觉完整）。长条（holdLength>0）留给逐对象路径（保 prevNote/nextNote 链）。
		var canDataSettle:Bool = PlayState.densePerfMode && ps.cpuControlled && !ps.replayMode && ps._overloadFrames > 0;
		if (canDataSettle && !ps.isTurboAggregateIndex(ps.currentSpawnId))
		{
			var settleCut:Float = fixedPosition + ps.spawnWindowFor(ps.unspawnNotes[ps.currentSpawnId]) * 0.5;
			var settleBudget:Int = Std.int(Math.max(4096, Math.min(65536, FlxG.elapsed * 1000 * 100)));
			var settled:Int = 0;
			while (ps.currentSpawnId < ps.unspawnNotes.length && settled < settleBudget)
			{
				var sTarget:CastNote = ps.unspawnNotes[ps.currentSpawnId];
				if (sTarget.strumTime > settleCut) break;
				if (sTarget.holdLength > 0) break; // 长条头/尾走对象路径
				if (sTarget.wasHit)
				{
					ps.currentSpawnId++;
					continue;
				}
				ps.currentSpawnId++;
				settled++;
				ps._bulkDrainedLast++;
				if (sTarget.blockHit)
					continue; // 卡键音符：静默消费（与原路径最终效果一致）
				var den:Int = Std.int(Math.max(1, Math.round(sTarget.density)));
				if ((sTarget.noteData & (1 << 8)) != 0) // mustPress
				{
					ps.settleCastHit(sTarget, den);
				}
				else
				{
					sTarget.wasHit = true; // 对手侧：数据层消费（无计分/无闪，与原 opponentNoteHit 语义一致）
				}
			}
			if (ps._bulkDrainedLast > 0) ps.lastNoteSpawnPos = Conductor.songPosition;
		}

		// 【Turbo·自适应物化预算】dense + botplay：帧时间越长允许生成越多（掉帧自动追补积压、
		// 恢复流畅），预算约 30 条/ms、上下限 [2048, 20000]（非 dense 保持原逻辑）。
		var spawnBudget:Int;
		if (PlayState.densePerfMode && ps.cpuControlled)
			spawnBudget = Std.int(Math.max(2048, Math.min(20000, FlxG.elapsed * 1000 * 30)));
		else
			spawnBudget = ps.perfLimitNotes > 0 ? limitNotes + 512 : 8192;

		var processed:Int = 0;
		while (ps.currentSpawnId < ps.unspawnNotes.length && processed < spawnBudget)
		{
			if (limitNotes > 0 && limitCount >= limitNotes) break;
			// 桌面：静态类型访问 CastNote 平行数组代理（getter 内联，不走 Dynamic __Field 分发；
			// 安卓保持 Dynamic：unspawnNotes 是 Note 实体数组）
		#if false
			var target:Dynamic = ps.unspawnNotes[ps.currentSpawnId];
			#else
			var target:CastNote = ps.unspawnNotes[ps.currentSpawnId];
			#end
			if (target.strumTime - fixedPosition > ps.spawnWindowFor(target)) break;
			if (target.wasHit) { ps.currentSpawnId++; continue; } // 【Turbo】已数据层结算：跳过不物化

			// 【密集对象硬上限】场上精灵对象数达到上限时，距判定线仍 > DENSE_OBJ_LATE_MS
			// 的箭头延迟进场（光标不退、时间推进后自然放行；到窗口内即使超限也生成，
			// 判定/计分/排期命中零影响）。仅视觉上"墙更贴线"，与用户拍板的预期一致。
			if (ps.perfObjCap > 0 && ps.notes.aliveObjectCount >= ps.perfObjCap)
			{
				var lateWin:Float = PlayState.DENSE_OBJ_LATE_MS * ps.playbackRate;
				if (ps.songSpeed < 1) lateWin /= ps.songSpeed;
				if (target.strumTime - fixedPosition > lateWin) break;
			}

			// 挤压音符（H-Slice 谱面字段 cmpSpam）：运行时展开，不预建
			if (target.cmpSpam != null)
			{
				PlayState.spamNotes.push(new SpamNoteData(
					Std.isOfType(target.cmpSpam[0], Float) ? target.cmpSpam[0] : Std.parseFloat(Std.string(target.cmpSpam[0])),
					Std.isOfType(target.cmpSpam[1], Float) ? target.cmpSpam[1] : Std.parseFloat(Std.string(target.cmpSpam[1])),
					target));
				target.cmpSpam = null;
				ps.spamSpawn();
				limitCount = limitNotes > 0 ? ps.notes.countLiving() : limitCount;
			}
			else
			{
				ps.spawnOneWithTail(target);
				processed++;
				limitCount++;
			}
			ps.currentSpawnId++;
		}

		ps.lastNoteSpawnPos = Conductor.songPosition;
		ps.releaseConsumedNotes(); // 【性能】清扫已消费 CastNote（游标左侧），释放 GC 引用

		// ===== 排期命中（架构修复）：到点直接入队，规避 alive-loop 哨兵饿死 =====
		if (ps.cpuControlled && ps.botplayPlan == null && ps.botSchedule.length > 0)
		{
			// 用上帧实测帧步长补偿：密集段帧间隔大（50-180ms），按实时延迟提前入队 → 评级落在 Sick 中心
			ps.lastSchedulePos = Conductor.songPosition;
			// 命中时刻弹出：音符到达判定线（strumTime）当帧入队并命中销毁（+1ms 对齐帧边界）。
			// 击杀竞态已由 botSched 排期保护杜绝，不再需要提前弹出——
			// 提前弹出会让音符在到达判定线之前就被击毁（视觉穿帮）
			var sp:Float = Conductor.songPosition + 1;
			var wi:Int = 0;
			while (wi < ps.botSchedule.length)
			{
				var sn2:Note = ps.botSchedule[wi];
				if (sn2 == null || !sn2.exists || sn2.wasGoodHit)
				{
					// swap-pop：O(1) 出队（splice 是 O(n)，密集段每帧上千次出队会卡死主线程）
					if (sn2 != null) sn2.botSched = false;
					ps.botSchedule[wi] = ps.botSchedule[ps.botSchedule.length - 1];
					ps.botSchedule.pop();
					continue;
				}
				if (sn2.botQueued)
				{
					// alive-loop 已抢先入队：只出队不重复推
					sn2.botSched = false;
					ps.botSchedule[wi] = ps.botSchedule[ps.botSchedule.length - 1];
					ps.botSchedule.pop();
					continue;
				}
				if (sn2.strumTime <= sp && !sn2.blockHit && !sn2.ignoreNote)
				{
					sn2.botQueued = true;
					sn2.botSched = false;
					ps.botHitQueue.push(sn2);
					ps.botSchedule[wi] = ps.botSchedule[ps.botSchedule.length - 1];
					ps.botSchedule.pop();
					continue;
				}
				wi++;
			}
			// 安全上限：全曲基准峰值 ~17k；超过即概率性丢到期——宁可保留绝不丢（每颗被入队/击杀后即出队）
			if (ps.botSchedule.length > 131072)
				ps.botSchedule.splice(0, ps.botSchedule.length - 131072);
		}
	}

	/** 原 PlayState.spamSpawn（作用域分析：零遮蔽，18 处成员引用已限定）。 */
	public static function spamSpawn(ps:PlayState):Void
	{
		if (PlayState.spamNotes.length < 1) return;
		var fixedPosition:Float = Conductor.songPosition - ClientPrefs.data.noteOffset;
		var spawnBPM:Float = PlayState.SONG != null ? PlayState.SONG.bpm : 100;

		for (spam in PlayState.spamNotes)
		{
			var noteInterval:Float = (15000 / spawnBPM) / spam.density;
			var guard:Int = 0;
			var isDisplay:Bool = true;

			// 先跳到当前时间（起点已过则整段快进，不逐颗生成）
			while (isDisplay && spam.remaining > 0 && guard < 8192)
			{
				guard++;
				// 【密集对象硬上限】spam 展开同样受 perfObjCap 约束（与 noteSpawn 同口径）
				if (ps.perfObjCap > 0 && ps.notes.aliveObjectCount >= ps.perfObjCap)
				{
					var lateWin:Float = PlayState.DENSE_OBJ_LATE_MS * ps.playbackRate;
					if (ps.songSpeed < 1) lateWin /= ps.songSpeed;
					if (spam.seedNote.strumTime - fixedPosition > lateWin) break;
				}
				if (spam.seedNote.strumTime < fixedPosition - noteInterval)
				{
					// 完全在出生窗口之前：按整批跳进，不生成
					var bulk:Int = Math.floor((fixedPosition - ps.spawnWindowFor(spam.seedNote) - spam.seedNote.strumTime) / noteInterval);
					if (bulk > 0)
					{
						if (bulk > spam.remaining) bulk = Std.int(spam.remaining);
						spam.seedNote.strumTime += bulk * noteInterval;
						spam.remaining -= bulk;
						if (spam.remaining <= 0) { break; }
					}
				}
				if (spam.seedNote.strumTime - fixedPosition > ps.spawnWindowFor(spam.seedNote)) { isDisplay = false; break; }
				ps.spawnOne(spam.seedNote);
				if (ps.perfLimitNotes > 0 && ps.notes.countLiving() >= ps.perfLimitNotes) break;
				spam.remaining--;
				spam.seedNote.strumTime += noteInterval;
			}
			if (spam.remaining <= 0) PlayState.spamNotes.remove(spam);
		}
	}
}
