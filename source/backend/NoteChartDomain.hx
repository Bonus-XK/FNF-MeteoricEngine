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
import states.LoadingState;
import states.stages.School;
import backend.Song.SwagSong;
import sys.FileSystem;
import objects.NoteGroup;
import states.PlayState.PreGenResult;
import backend.Section.SwagSection;
import objects.Character;
import backend.Multiplayer;
import backend.Rating;
import objects.NoteSplash;
import psychlua.FunkinLua;

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

	/** 原 PlayState.reloadChartSourceIfNeeded（作用域分析：零遮蔽，15 处成员引用已限定）。 */
	public static function reloadChartSourceIfNeeded():Void
	{
		// 同曲重入（LoadingState 复用静态 SONG 且 registerChartSource 已把标记重置为 false）
		// 时，SONG 可能仍处于剥离态（sectionNotes 全为空数组）——按真实数据状态判定，
		// 标记与数据不一致时以数据为准，否则二次加载同一首歌会在空 DOM 上生成 0 音符。
		if (!PlayState.chartDataStripped && !PlayState.isSongChartStripped(PlayState.SONG)) return;
		if (PlayState.SONG == null || PlayState.chartJsonInput == null || PlayState.chartSongName != PlayState.SONG.song)
		{
			// 无登记身份或对象与身份不一致（如 tutorial 兜底）：放弃剥离，避免误恢复
			PlayState.chartDataStripped = false;
			return;
		}
		try
		{
			var fresh:SwagSong = Song.loadFromJson(PlayState.chartJsonInput, PlayState.chartFolder);
			if (fresh != null)
			{
				// 保留引擎运行期派生的字段：School.setDefaultGF('gf-pixel')/vanillaSongStage 等只在
				// 首次 create 时写入 SONG（roses.json 等基础谱面本身没有这些字段）。重开从 JSON
				// 重新解析出的 fresh 会丢失它们 → GF 变普通贴图 + 位置错（快速重开 GF 瞬移 bug）。
				if (fresh.stage == null || fresh.stage.length < 1)
					fresh.stage = PlayState.SONG.stage;
				if (fresh.gfVersion == null || fresh.gfVersion.length < 1)
					fresh.gfVersion = PlayState.SONG.gfVersion;
				PlayState.setSong(fresh); // 缓存命中（或重新解析）→ 完整 DOM 回归；后续 generateChartNotes 正常消费
			}
			else
			{
				trace('[Memory] 谱面恢复失败（缓存/文件缺失）：' + PlayState.chartJsonInput);
				PlayState.chartDataStripped = false;
			}
		}
		catch (e:Dynamic)
		{
			trace('[Memory] 谱面恢复异常：' + e);
			// 保留剥离标记：下次重开再试（文件丢失属极端异常，不再额外清空）
		}
	}

	/** 原 PlayState.generateChartNotes（作用域分析：零遮蔽，93 处成员引用已限定）。 */
	public static function generateChartNotes(ps:PlayState, loadPhase:Bool):Void
	{
		// 重开/回溯路径可能带着被剥离的 SONG：先恢复完整逐音符 DOM 再生成
		PlayState.reloadChartSourceIfNeeded();
		// 生成完成后标记 done（原生崩溃时日志簿显示最终到达的阶段）
		ps.totalNotes = 0;
		// 新曲/重开：stage 落盘标记复位（每曲各记一次首次生成/首次命中）
		ps._stageMarkSpawn = false;
		ps._stageMarkPop = false;
		ps.botplayPlan = Note.getBotplayPlan();
		if (ps.botplayPlan != null) ps.botLaneCounts = [0, 0, 0, 0];
		// 【视觉】生效值：只透传用户设置（重叠隐藏不再对密集谱自动开启——
		// 用户实测会隐藏真实箭头/长条头，表现"箭头消失但可打"；场上上限同理不自动改。
		// 500 帧降载改由：quad 合批 + 密集谱 063 原生贴图（关 RGB）+ 视觉采样预算 + 命中批扫承担。
		ps.perfLimitNotes = ClientPrefs.data.limitNotes;
		ps.perfHideOverlapped = ClientPrefs.data.hideOverlapped;
		var songData = PlayState.SONG;
		ps.noteTypes = [];
		ps.noteTypeLuaPaths = [];
		ps.noteTypeHxPaths = [];
		ps.eventsPushed = [];
		var chartSeqCounter:Int = 0;

		var noteData:Array<SwagSection> = songData.notes;

		if (loadPhase)
		{
			if (ps.cachedEventsData == null)
			{
				var file:String = Paths.json(ps.songName + '/events');
				#if MODS_ALLOWED
				if (FileSystem.exists(Paths.modsJson(ps.songName + '/events')) || FileSystem.exists(file)) {
				#else
				if (OpenFlAssets.exists(file)) {
				#end
					ps.cachedEventsData = Song.loadFromJson('events', ps.songName).events;
				}
				else {
					ps.cachedEventsData = [];
				}
			}
			for (event in ps.cachedEventsData) //Event Notes
				for (i in 0...event[1].length)
					ps.makeEvent(event, i);
		}
		else
		{
			for (event in ps.cachedEventNotes)
				ps.eventNotes.push(event);
		}

		#if false
		// ===== 安卓最稳定管线：备份式直建 Note 对象（8月17 实机验证可用）=====
		// 不使用 CastNote/对象池/回收；音符在生成期直接创建，noteSpawn 按时间插入。
		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % 4);
				// Psych 1.0.4 格式：列号直接决定方向（<4 玩家、>=4 对手）。
				// 谱面在加载时已由 convertToPsychV1 转成该格式（mustHitSection 已烘焙进列号），
				// 与桌面 buildChartNotes 语义一致；旧逻辑再加 mustHitSection 翻转会把
				// 对手段（mustHitSection=false + 列 4-7）翻成玩家 → 对手箭头全跑到玩家侧。
				var gottaHitNote:Bool = (songNotes[1] < 4);

				var oldNote:Note;
				if (ps.unspawnNotes.length > 0)
					oldNote = ps.unspawnNotes[Std.int(ps.unspawnNotes.length - 1)];
				else
					oldNote = null;

				var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote, false, false, null);
				swagNote.chartSeq = chartSeqCounter++;
				swagNote.mustPress = gottaHitNote;
				swagNote.sustainLength = songNotes[2];
				swagNote.gfNote = (section.gfSection == true && songNotes[1] < 4);
				swagNote.noteType = songNotes[3];
				if (!Std.isOfType(songNotes[3], String)) swagNote.noteType = ChartingState.noteTypeList[songNotes[3]];

				swagNote.scrollFactor.set();

				var susLength:Float = swagNote.sustainLength;
				susLength = susLength / Conductor.stepCrochet;
				ps.unspawnNotes.push(swagNote);

				var floorSus:Int = Math.floor(susLength);
				if (ps.botplayPlan != null && gottaHitNote)
				{
					ps.botLaneCounts[daNoteData]++;
					if (floorSus > 0) ps.botLaneCounts[daNoteData] += floorSus + 1;
				}
				if (floorSus > 0)
				{
					for (susNote in 0...floorSus + 1)
					{
						oldNote = ps.unspawnNotes[Std.int(ps.unspawnNotes.length - 1)];
						var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote), daNoteData, oldNote, true, false, null);
						sustainNote.chartSeq = chartSeqCounter++;
						sustainNote.mustPress = gottaHitNote;
						sustainNote.gfNote = (section.gfSection == true && songNotes[1] < 4);
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						swagNote.tail.push(sustainNote);
						sustainNote.parent = swagNote;
						ps.unspawnNotes.push(sustainNote);

						sustainNote.correctionOffset = swagNote.height / 2;
						if (!PlayState.isPixelStage)
						{
							if (oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
								oldNote.scale.y /= ps.playbackRate;
								oldNote.updateHitbox();
							}
							if (ClientPrefs.data.downScroll && !ps.isPhigrosStyle)
								sustainNote.correctionOffset = 0;
						}
						else if (oldNote.isSustainNote)
						{
							oldNote.scale.y /= ps.playbackRate;
							oldNote.updateHitbox();
						}

						if (sustainNote.mustPress) sustainNote.x += FlxG.width / 2;
						else if (ClientPrefs.data.middleScroll)
						{
							sustainNote.x += 310;
							if (daNoteData > 1) sustainNote.x += FlxG.width / 2 + 25;
						}
					}
				}

				if (swagNote.mustPress) swagNote.x += FlxG.width / 2;
				else if (ClientPrefs.data.middleScroll)
				{
					swagNote.x += 310;
					if (daNoteData > 1) swagNote.x += FlxG.width / 2 + 25;
				}

				if (!ps.noteTypes.contains(swagNote.noteType)) ps.noteTypes.push(swagNote.noteType);
				if (gottaHitNote) ps.totalNotes++;
			}
		}
		#else
		var consumedPreGen:Bool = loadPhase && PlayState.preGenNotes != null && PlayState.preGenSong == Paths.formatToSongPath(PlayState.SONG.song);
		if (consumedPreGen)
		{
			// 消费加载期预生成的音符（已排序、已含 chartSeq 链）
			ps.unspawnNotes = PlayState.preGenNotes;
			PlayState.preGenNotes = null;
			PlayState.preGenSong = null;
			ps.noteTypes = PlayState.preGenNoteTypes;
			PlayState.preGenNoteTypes = null;
			ps.rebuildNoteTypePaths();
			ps.totalNotes = PlayState.preGenTotalNotes;
			if (ps.botplayPlan != null) ps.botLaneCounts = PlayState.preGenBotLaneCounts;
			PlayState.preGenBotLaneCounts = null;
		}
		else
		{
			// 兜底：预生成不可用（快速重开/预生成失败）时生成轻量 CastNote（与预生成同一路径）。
			// 直接在共享 SONG 上构建（只读 + clearSections=false）；SONG 的逐音符剥离统一
			// 由 create 尾 releaseSongChartDom 执行（重开/回溯前 reloadChartSourceIfNeeded 按需重解析）。
			// 不再深拷贝：11.8M 音符级谱面的 copySong 会让加载峰值翻倍（Obsolescence-spam 闪退主因之一）。
			var res:PreGenResult = PlayState.buildChartNotes(PlayState.SONG, ps.botplayPlan, ps.isPhigrosStyle,
				{ songSpeed: ps.songSpeed }, ps.playbackRate, false);
			if (res.botplayLanes != null)
				Note.storeBotplayPlan(res.botplayLanes);
			ps.unspawnNotes = res.notes;
			ps.noteTypes = res.noteTypes;
			ps.rebuildNoteTypePaths();
			ps.totalNotes = res.totalNotes;
			if (ps.botplayPlan != null) ps.botLaneCounts = res.botLaneCounts;
		}
		#end
		if (loadPhase)
		{
			for (event in songData.events) //Event Notes
				for (i in 0...event[1].length)
					ps.makeEvent(event, i);
		}
		// 【密集对象硬上限】在 densePerfMode 定案后（预生成与创建期兜底的 buildChartNotes
		// 均已执行、此处为两路径汇合点）再生效：只对超密集谱自动开启（不写存档；非密集谱恒 0=关闭）
		ps.perfObjCap = PlayState.densePerfMode ? PlayState.DENSE_OBJ_CAP : 0;
		// 【Turbo】dense 档启用 notePool 复用（非密集谱恒关闭，行为与旧版一致）
		NoteGroup.poolEnabled = PlayState.densePerfMode;
		// 【Turbo】聚合区分析（含侧车缓存）：仅 dense 谱；失败/空结果时 turboZones=[]，
		// 数据级结算对全部 dense 段生效（更保守，视觉略稀）。
		ps.turboZones = [];
		ps.turboZoneCursor = 0;
		if (PlayState.densePerfMode)
			ps.initTurboZones();

		if (ps.botplayPlan != null)
		{
			// 校验预演与正式生成完全一致（同一遍历逻辑下必然一致；不一致时回退实时判定，防止错位）
			for (lane in 0...4)
				if (ps.botLaneCounts[lane] != ps.botplayPlan[lane].length)
				{
					ps.botplayPlan = null;
					break;
				}
		}
		#if false
		ps.unspawnNotes.sort(PlayState.sortByTime);
		#else
		if (!consumedPreGen) ps.unspawnNotes.sort(PlayState.sortByTime);
		#end

		// 谱面末尾时间（ms）：已排序数组的最后一条 strumTime+holdLength 即谱面终点。
		// 在生成期（DOM/音频均未剥离时）一次性记录，供 startSong 兜底歌曲时长（0:00 卡结算修复）。
		ps.chartEndTimeMs = 0;
		if (ps.unspawnNotes != null && ps.unspawnNotes.length > 0)
		{
			var _lastCast:CastNote = ps.unspawnNotes[ps.unspawnNotes.length - 1];
			ps.chartEndTimeMs = _lastCast.strumTime + _lastCast.holdLength + Conductor.safeZoneOffset + 1000;
		}

		ps.generatedMusic = true;
		CrashHandler.mark('PlayState.generateChartNotes:done');
	}

	/** 原 PlayState.noteMissCommon（作用域分析：零遮蔽，37 处成员引用已限定）。 */
	public static function noteMissCommon(ps:PlayState, direction:Int, note:Note = null)
	{
		// KE 结算散点图：主音符 Miss 记录（贴外沿窗口 = 视为最晚；空按/长条子段不记）
		if (note != null && !note.isSustainNote && !ps.cpuControlled)
		{
			var outer:Float = (ps.ratingsData != null && ps.ratingsData.length > 0) ? ps.ratingsData[ps.ratingsData.length - 1].hitWindow : 166;
			if (outer <= 0) outer = 166;
			ps.judgementHistory.push({t: note.strumTime, d: outer, r: 'miss'});
		}
		// PF 移植：任何失误（含空按）即退出“全 Sick”金色 Combo
		ps.allSicks = false;

		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;
		ps.health -= subtract * ps.healthLoss;

		if(ps.instakillOnMiss)
		{
			ps.vocals.volume = 0;
			ps.opponentVocals.volume = 0;
			ps.doDeathCheck(true);
		}
		ps.combo = 0;

		var missMult:Int = note != null ? Std.int(note.density) : 1; // H-Slice 移植：堆叠合并按 density 计 Miss
		if (missMult < 1) missMult = 1;
		ps.songScore -= 10 * missMult;
		if(!ps.endingSong) ps.songMisses += missMult;
		ps.totalPlayed += missMult;
		ps.RecalculateRating(true);

		// 联机：广播己方失误（分数增量/血量增量/密度 + 音符序号），对方据此扣对方血量并给自己回血，
		// 并按 chartSeq 精确消费对侧音符/播放对方 Miss 动画
		if (PlayState.isOnlineMode && !ps.cpuControlled)
			Multiplayer.send('MISS|' + direction + '~' + (-10 * missMult) + '~' + (-(subtract * ps.healthLoss)) + '~' + missMult + '~' + (note != null ? note.chartSeq : -1));

		// play character anims
		var char:Character = ps.boyfriend;
		if((note != null && note.gfNote) || (PlayState.SONG.notes[ps.curSection] != null && PlayState.SONG.notes[ps.curSection].gfSection)) char = ps.gf;

		if(!ClientPrefs.data.hudOnly && char != null && char.hasMissAnimations)
		{
			var suffix:String = '';
			if(note != null) suffix = note.animSuffix;

			var animToPlay:String = ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length-1, direction)))] + 'miss' + suffix;
			char.playAnim(animToPlay, true);

			if(char != ps.gf && ps.combo > 5 && ps.gf != null && ps.gf.animOffsets.exists('sad'))
			{
				ps.gf.playAnim('sad');
				ps.gf.specialAnim = true;
			}
		}
		ps.vocals.volume = 0;
	}

	/** 原 PlayState.processBotHits（作用域分析：零遮蔽，24 处成员引用已限定）。 */
	public static function processBotHits(ps:PlayState):Void
	{
		if (ps.botHitQueue.length == 0) return;
		if (ps.rewinding) { ps.botHitQueue.resize(0); return; }
		ps.botHitBatch = true;
		ps.botBatchSeenSeq = new Map<Int, Bool>(); // 批内按 chartSeq 去重：同帧池化复活对象不二次计分
		ps.notes.beginBatchKill(); // 【密集批·延迟移除】命中击杀登记，帧末一次 O(n) 清扫
		for (note in ps.botHitQueue)
		{
			if (note == null || !note.alive || note.blockHit) continue;
			if (note.chartSeq >= 0)
			{
				if (ps.botBatchSeenSeq.exists(note.chartSeq)) continue;
				ps.botBatchSeenSeq.set(note.chartSeq, true);
			}
			// 【500 帧补丁】同簇视觉副本不再逐命中全表扫描，统一在批处理末尾一次 O(成员) 扫
			if (ClientPrefs.data.noteJudgment == 'KE 判定' && note.isSustainNote)
			{
				// KE 判定：长条不参与判定，子段仅做视觉消除
				note.wasGoodHit = true;
				note.active = false;
				note.visible = false;
				ps.notes.invalidateNote(note);
				continue;
			}
			ps.goodNoteHit(note);
			if (!note.wasGoodHit) note.wasGoodHit = true; // ignore/伤害音符：只消费一次，避免下帧重复收集
			// 批处理下 goodNoteHit 只回收批内第一颗（其余在 botBatchScoreShown 早退）——
			// 这里对仍存活的命中音符统一视觉回收：命中即灭，杜绝"击中但飞过判定线"
			if (!note.isSustainNote && note.alive)
			{
				note.active = false;
				note.visible = false;
				ps.notes.invalidateNote(note);
			}
		}
		// 【500 帧补丁】批内兄弟视觉副本统一回收：原每命中全表扫描 O(命中×成员) → 本帧一次 O(成员)。
		// 倒序 + splice 安全（与旧逐命中扫同款遍历方式）；botBatchSeenSeq 已含本帧全部命中 chartSeq。
		if (ps.botBatchSeenSeq.keys().hasNext())
		{
			var mi:Int = ps.notes.members.length - 1;
			while (mi >= 0)
			{
				var sib:Note = ps.notes.members[mi];
				if (sib != null && sib.blockHit && sib.ignoreNote && sib.chartSeq >= 0
					&& ps.botBatchSeenSeq.exists(sib.chartSeq))
					ps.notes.invalidateNote(sib);
				mi--;
			}
		}
		ps.notes.endBatchKill(); // 【密集批·延迟移除】帧末一次 O(n) 清扫（含命中与兄弟副本）
		ps.botHitBatch = false;
		ps.botHitQueue.resize(0);
		ps.botBatchAnimDone = [false, false, false, false];
		ps.botBatchSplashDone = [false, false, false, false];
		ps.botBatchHitsoundDone = false;
		ps.botBatchScoreShown = false;
	}

	/** 原 PlayState.settleCastHit（作用域分析：零遮蔽，27 处成员引用已限定）。 */
	public static function settleCastHit(ps:PlayState, target:CastNote, hitMult:Int):Void
	{
		// 计数权威封顶（与 goodNoteHit 同款）：结算/命中不超过总音符数
		if (ps.totalNotes > 0)
		{
			if (ps.songHits >= ps.totalNotes) hitMult = 0;
			else if (ps.songHits + hitMult > ps.totalNotes) hitMult = Std.int(ps.totalNotes - ps.songHits);
		}
		if (hitMult <= 0) return;

		var daRating:Rating = ps.ratingsData[0]; // botplay diff=0：marvelous 时=marvelous，否则=sick
		ps.totalNotesHit += daRating.ratingMod * hitMult;
		ps.totalPlayed += hitMult;
		ps.songHits += hitMult;
		daRating.hits += hitMult;
		ps.songScore += daRating.score * hitMult;
		ps.combo += hitMult;
		if (ps.combo > ps.maxCombo) ps.maxCombo = ps.combo;
		ps._npsCount += hitMult;
		ps.health += 0.023 * ps.healthGain * hitMult; // Note.hitHealth 默认 0.023
		// 结算恒为满分（marvelous/sick）→ 不触碰 allSicks（保持全 S 金 Combo）
		// 评级/分数文本节流（与 popUpScore 同款 250ms）
		if (haxe.Timer.stamp() - ps._lastRatingRecalc >= 0.25)
		{
			ps._lastRatingRecalc = haxe.Timer.stamp();
			ps.RecalculateRating(false);
		}
		// strum confirm 高亮：每帧每轨一次（与批处理 botBatchAnimDone 同款节流）
		var lane:Int = target.noteData & 255;
		if (lane >= 0 && lane < 4 && !ps._settleAnimDone[lane])
		{
			ps._settleAnimDone[lane] = true;
			ps.strumPlayAnim(false, lane, Conductor.stepCrochet * 1.25 / 1000 / ps.playbackRate);
		}
		target.wasHit = true;
	}

	/** 原 PlayState.clearNotesBefore（作用域分析：零遮蔽，8 处成员引用已限定）。 */
	public static function clearNotesBefore(ps:PlayState, time:Float)
	{
		// H-Slice 移植：CastNote 数组用生成游标二分跳进（O(log n)），不再逐条 remove/销毁
		var firstId:Int = ps.currentSpawnId;
		var lastId:Int = ps.unspawnNotes.length;
		while (firstId < lastId)
		{
			var middleId:Int = (firstId + lastId) >>> 1;
			if (ps.unspawnNotes[middleId].strumTime - 350 < time)
				firstId = middleId + 1;
			else
				lastId = middleId;
		}
		ps.currentSpawnId = firstId;
		ps.releaseConsumedNotes();

		// 已生成的音符同样静默回收（与旧行为一致：不判 miss、不溅射）
		var i:Int = ps.notes.length - 1;
		while (i >= 0) {
			var daNote:Note = ps.notes.members[i];
			if(daNote != null && daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				ps.notes.invalidateNote(daNote);
			}
			--i;
		}
	}

	/** 原 PlayState.onlineOppHitVisual（作用域分析：零遮蔽，8 处成员引用已限定）。 */
	public static function onlineOppHitVisual(ps:PlayState, data:Int, seq:Int):Void
	{
		var note:Note = ps.findOnlineOppNoteBySeq(seq);
		if (note != null)
		{
			note.wasGoodHit = true;
			note.active = false;
			note.visible = false;
			ps.notes.invalidateNote(note);
			// 同簇视觉副本一并销毁（与玩家侧 processBotHits 一致，避免副本飞过判定线滞留）
			if (note.chartSeq >= 0)
			{
				var i:Int = ps.notes.members.length - 1;
				while (i >= 0)
				{
					var sib:Note = ps.notes.members[i];
					if (sib != null && sib != note && sib.blockHit && sib.ignoreNote && sib.chartSeq == note.chartSeq)
						ps.notes.invalidateNote(sib);
					i--;
				}
			}
		}
		ps.playOnlineOppSing(data, note);
		if (ps.opponentVocals != null) ps.opponentVocals.volume = 1;
	}

	/** 原 PlayState.checkEventNote（作用域分析：零遮蔽，10 处成员引用已限定）。 */
	public static function checkEventNote(ps:PlayState)
	{
		if (ps.rewinding) return; // 回溯中不触发谱面事件
		while(ps.eventNotes.length > 0) {
			var leStrumTime:Float = ps.eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(ps.eventNotes[0].value1 != null)
				value1 = ps.eventNotes[0].value1;

			var value2:String = '';
			if(ps.eventNotes[0].value2 != null)
				value2 = ps.eventNotes[0].value2;

			ps.triggerEvent(ps.eventNotes[0].event, value1, value2, leStrumTime);
			ps.eventNotes.shift();
		}
	}

	/** 原 PlayState.releaseConsumedNotes（作用域分析：零遮蔽，11 处成员引用已限定）。 */
	public static function releaseConsumedNotes(ps:PlayState):Void
	{
		#if !android
		if (ps.currentSpawnId < ps.lastSpawnGc) ps.lastSpawnGc = ps.currentSpawnId;
		if (ps.currentSpawnId - ps.lastSpawnGc >= 2048)
		{
			var gi:Int = ps.lastSpawnGc;
			while (gi < ps.currentSpawnId)
			{
				ps.unspawnNotes[gi] = null;
				gi++;
			}
			ps.lastSpawnGc = ps.currentSpawnId;
		}
		#end
	}

	/** 原 PlayState.applyOppMiss（作用域分析：零遮蔽，12 处成员引用已限定）。 */
	public static function applyOppMiss(ps:PlayState, data:Int, scoreDelta:Int, healthDelta:Float, mult:Int, seq:Int = -1):Void
	{
		ps.onlineOppScore += scoreDelta;
		ps.onlineOppMisses += mult;
		ps.onlineOppTotalPlayed += mult;
		ps.onlineOppCombo = 0;
		ps.onlineOppHealth = FlxMath.bound(ps.onlineOppHealth + healthDelta, 0, 2);
		// 攻防式：对方 Miss → 我方按比例回血
		if (healthDelta < 0)
			ps.health = FlxMath.bound(ps.health + (-healthDelta) * PlayState.ONLINE_OPP_MISS_GAIN, 0, 2);
		ps.flashOppStrums(data, 'static', false);
		// 真双人：对方 Miss —— 对侧音符不消费（自然飞过判定线，由回收窗清理），
		// 仅播放对方角色 Miss 动画 + 对方人声静音
		ps.playOnlineOppMiss(data, ps.findOnlineOppNoteBySeq(seq));
	}

	/** 原 PlayState.spawnNoteSplash（作用域分析：零遮蔽，7 处成员引用已限定）。 */
	public static function spawnNoteSplash(ps:PlayState, x:Float, y:Float, data:Int, ?note:Note = null)
	{
		// 【视觉/性能】密集谱自动游玩：每轨 250ms 最多 1 次溅射。原实现 botHitBatch 只限
		// "每帧每轨 1 个"——700fps 下每秒最多 2800 个、同屏上千个溅射精灵：既是"五颜六色"
		// 乱象，也是密集段渲染/更新的大头。节流后每轨约 2~4 个/秒，观感恢复正常。
		if (PlayState.densePerfMode && (ps.cpuControlled || ps.replayMode) && data >= 0 && data < 4)
		{
			var nowSplash:Float = Conductor.songPosition;
			if (nowSplash - ps.lastSplashLane[data] < 250) return;
			ps.lastSplashLane[data] = nowSplash;
		}
		var splash:NoteSplash = ps.grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		ps.grpNoteSplashes.add(splash);
	}

	/** 原 PlayState.releaseSongChartDom（作用域分析：零遮蔽，9 处成员引用已限定）。 */
	public static function releaseSongChartDom():Void
	{
		#if desktop
		if (PlayState.SONG != null && PlayState.chartJsonInput != null && PlayState.chartSongName == PlayState.SONG.song)
		{
			if (!PlayState.chartDataStripped)
			{
				Song.stripSectionNotes(PlayState.SONG);
				PlayState.chartDataStripped = true;
			}
			Song.evictLargeChartFromCache(PlayState.chartJsonInput, PlayState.chartFolder);
		}
		#end
	}

	/** 原 PlayState.applyOppHit（作用域分析：零遮蔽，17 处成员引用已限定）。 */
	public static function applyOppHit(ps:PlayState, data:Int, rating:String, scoreDelta:Int, healthDelta:Float, mult:Int, seq:Int = -1):Void
	{
		ps.onlineOppScore += scoreDelta;
		ps.onlineOppCombo += mult;
		if (ps.onlineOppCombo > ps.onlineOppMaxCombo) ps.onlineOppMaxCombo = ps.onlineOppCombo;
		ps.onlineOppHits += mult;
		ps.onlineOppTotalPlayed += mult;
		ps.onlineOppTotalNotesHit += ps.getRatingModByName(rating) * mult;
		ps.onlineOppRatings.set(rating, (ps.onlineOppRatings.exists(rating) ? ps.onlineOppRatings.get(rating) : 0) + mult);
		ps.onlineOppHealth = FlxMath.bound(ps.onlineOppHealth + healthDelta, 0, 2);
		ps.flashOppStrums(data, 'confirm', true);
		// 真双人：对侧谱面由对方按键打击——按 chartSeq 消费对侧音符 + 对方角色唱歌 + 对方人声响起
		ps.onlineOppHitVisual(data, seq);
	}

	/** 原 PlayState.strumPlayAnim（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function strumPlayAnim(ps:PlayState, isDad:Bool, id:Int, time:Float)
	{
		var spr:StrumNote = null;
		if(isDad) {
			spr = ps.opponentStrums.members[id];
		} else {
			spr = ps.playerStrums.members[id];
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	/** 原 PlayState.findOnlineOppNoteBySeq（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function findOnlineOppNoteBySeq(ps:PlayState, seq:Int):Note
	{
		if (seq < 0 || seq >= Note.seqNote.length) return null;
		var n:Note = Note.seqNote[seq];
		if (n != null && n.alive && n.exists && !n.blockHit) return n;
		// seqNote 可能被同 chartSeq 的视觉副本（blockHit）覆盖：回退扫描基准音符
		var found:Note = null;
		if (ps.notes != null)
			ps.notes.forEachAlive(function(c:Note) {
				if (found == null && c.chartSeq == seq && !c.blockHit) found = c;
			});
		return found;
	}

	/** 原 PlayState.KillNotes（作用域分析：零遮蔽，8 处成员引用已限定）。 */
	public static function KillNotes(ps:PlayState)
	{
		ps.botHitQueue.resize(0); // 丢弃待批处理的命中，避免引用已销毁音符
		while(ps.notes.length > 0) {
			var daNote:Note = ps.notes.members[0];
			ps.notes.invalidateNote(daNote); // 池化回收（替代直接 destroy）
		}
		ps.unspawnNotes = [];
		ps.currentSpawnId = 0;
		PlayState.spamNotes = [];
		Note.seqNote = [];
		Note.seqHit = [];
		ps.eventNotes = [];
	}

	/** 原 PlayState.rebuildNoteTypePaths（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function rebuildNoteTypePaths(ps:PlayState):Void
	{
		ps.noteTypeLuaPaths = [];
		ps.noteTypeHxPaths = [];
		for (nt in ps.noteTypes)
		{
			if (nt == null || nt.length < 1) continue;
			var path:String = 'custom_notetypes/' + nt;
			ps.noteTypeLuaPaths.push(path + '.lua');
			ps.noteTypeHxPaths.push(path + '.hx');
		}
	}

	/** 原 PlayState.goodNoteHit（作用域分析：零遮蔽，74 处成员引用已限定）。 */
	public static function goodNoteHit(ps:PlayState, note:Note):Void
	{
		// 【密集谱自动游玩·命中开销收敛】stagesFunc 每命中创建一个闭包并派发（每次命中都分配），
		// 密集批（≈每帧数百命中）下是 notes 阶段 300us+ 的来源之一；
		// 密集自动游玩/回放跳过场景命中回调（Weekend 1 等舞台点亮对自动游玩无意义），手动游玩不受影响。
		if (!(PlayState.densePerfMode && (ps.cpuControlled || ps.replayMode)))
			ps.stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note)); //Psych 1.0.4：场景命中回调（Weekend 1）
		var onlineScoreDelta:Int = 0;
		var onlineHealthDelta:Float = 0;
		if (!note.wasGoodHit)
		{
			var hitMult:Int = Std.int(note.density); // H-Slice 移植：堆叠合并按 density 计分/加血
			if (hitMult < 1) hitMult = 1;
			// 计数权威封顶：命中/连击/评级/分数累计不得超过总音符数（批次去重噪声等超额在此截断），
			// 结算时 Combo/Marvelous/…/分数恰好等于总音符数（1,130,083 级谱面 = totalNotes）
			if (ps.totalNotes > 0)
			{
				if (ps.songHits >= ps.totalNotes) hitMult = 0;
				else if (ps.songHits + hitMult > ps.totalNotes) hitMult = Std.int(ps.totalNotes - ps.songHits);
			}
			// NPS 统计：每个音符（含长条）只计一次，只计独立音符（堆叠合并按 density 计）
			if (!note.isSustainNote) ps._npsCount += hitMult;
			if(ps.cpuControlled && (note.ignoreNote || note.hitCausesMiss)) return;

			note.wasGoodHit = true;
			// 回放录制：长条子段命中（Psych 判定按住时的子段逐个记录）
			if (ps.recordingReplay && !ps.cpuControlled && ps.currentReplay != null && note.isSustainNote)
				ps.currentReplay.addEvent(note.chartSeq, note.strumTime, note.noteData, 'sus');
			if (ClientPrefs.data.hitsoundVolume > 0 && !note.hitsoundDisabled && !(ps.botHitBatch && ps.botBatchHitsoundDone))
			{
				FlxG.sound.play(Paths.sound(note.hitsound), ClientPrefs.data.hitsoundVolume);
				if (ps.botHitBatch) ps.botBatchHitsoundDone = true;
			}

			if(note.hitCausesMiss) {
				// 回放录制：伤害音符的命中（回放时同样走命中→受伤流程）
				if (ps.recordingReplay && !ps.cpuControlled && ps.currentReplay != null && !note.isSustainNote)
					ps.currentReplay.addEvent(note.chartSeq, note.strumTime, note.noteData, 'hurt');
				ps.noteMiss(note);
				if(!note.noteSplashData.disabled && !note.isSustainNote) {
					ps.spawnNoteSplashOnNote(note);
				}

				if(!note.noMissAnimation)
				{
					switch(note.noteType) {
						case 'Hurt Note': //Hurt note
							if(ps.boyfriend.animation.getByName('hurt') != null) {
								ps.boyfriend.playAnim('hurt', true);
								ps.boyfriend.specialAnim = true;
							}
					}
				}

				if (!note.isSustainNote)
				{
					ps.notes.invalidateNote(note);
				}
				return;
			}

			if (!note.isSustainNote)
			{
				ps.combo += hitMult;
				if (ps.combo > ps.maxCombo) ps.maxCombo = ps.combo; // 最高连击追踪
				var onlinePrevScore:Int = ps.songScore;
				ps.popUpScore(note, hitMult); // 传入已封顶的 density：计分/评级/命中同源封顶
				onlineScoreDelta = ps.songScore - onlinePrevScore;
				// 回放录制：主音符命中（评分取本局真实判定结果）
				if (ps.recordingReplay && !ps.cpuControlled && ps.currentReplay != null)
					ps.currentReplay.addEvent(note.chartSeq, note.strumTime, note.noteData, note.rating);
			}
			onlineHealthDelta = note.hitHealth * ps.healthGain * hitMult;
			ps.health += onlineHealthDelta;
			// 血条溢出图标飞出：堆叠命中（density≥2）即上报——小型堆叠也飞，幅度 = 该堆叠提供的血量%
			// （堆叠越大飞得越远、显示越高，封顶 1000%）；由 GameHUD 在当帧统一结算
			if (ClientPrefs.data.iconFlyOverflow && hitMult > 1 && !note.isSustainNote)
			{
				var stackGainPct:Float = (note.hitHealth * ps.healthGain * hitMult) / 2 * 100;
				ps.pendingFlySpikePct = Math.max(ps.pendingFlySpikePct, Math.min(100 + stackGainPct, 1000));
			}
			// Bad 及以下评分扣一点点血
			if (!note.isSustainNote && (note.rating == 'bad' || note.rating == 'shit'))
			{
				onlineHealthDelta -= 0.02 * ps.healthLoss * hitMult;
				ps.health -= 0.02 * ps.healthLoss * hitMult;
			}
			// 联机：广播己方命中（分数增量/血量增量/密度 + 音符序号），对方据此重建对手面板与血量，
			// 并按 chartSeq 精确消费对侧音符（真双人：对侧谱面由对方按键打击）
			if (PlayState.isOnlineMode && !ps.cpuControlled && !note.isSustainNote)
				Multiplayer.send('HIT|' + note.noteData + '~' + note.rating + '~' + onlineScoreDelta + '~' + onlineHealthDelta + '~' + hitMult + '~' + note.chartSeq);

			if(!ClientPrefs.data.hudOnly && !note.noAnimation && !(ps.botHitBatch && ps.botBatchAnimDone[note.noteData])) {
				var animToPlay:String = ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length-1, note.noteData)))];

				var char:Character = ps.boyfriend;
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = ps.gf;
					animCheck = 'cheer';
				}

				if(char != null)
				{
					char.playAnim(animToPlay + note.animSuffix, true);
					char.holdTimer = 0;

					if(note.noteType == 'Hey!') {
						if(char.animOffsets.exists(animCheck)) {
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
				if (ps.botHitBatch) ps.botBatchAnimDone[note.noteData] = true;
			}

			if(!ps.cpuControlled && !ps.replayMode)
			{
				// 手动命中：strum 高亮由松键（keyReleased -> static）熄灭
				var spr = ps.playerStrums.members[note.noteData];
				if(spr != null && ClientPrefs.data.playerLightStrum) spr.playAnim('confirm', true);
			}
			else if (!(ps.botHitBatch && ps.botBatchAnimDone[note.noteData]) && ClientPrefs.data.botLightStrum)
				// 自动游玩/回放：confirm 高亮带复位计时，避免判定后常亮
				ps.strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / ps.playbackRate);
			ps.vocals.volume = 1;

			var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
			var leData:Int = Math.round(Math.abs(note.noteData));
			var leType:String = note.noteType;

			// JS Engine 移植：关闭命中回调（noHitFuncs）
			if (!ClientPrefs.data.noHitFuncs)
			{
				var result:Dynamic = ps.callOnLuas('goodNoteHit', [ps.notes.members.indexOf(note), leData, leType, isSus]);
				if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) ps.callOnHScript('goodNoteHit', [note]);
			}

			// 原生长条按压覆盖（模组 goodNoteHit 回调同点触发）
			if (ps.holdCoverHandler != null && note.isSustainNote)
				ps.holdCoverHandler.onHit(Std.int(Math.abs(note.noteData)));

			if (!note.isSustainNote)
			{
				ps.notes.invalidateNote(note);
			}
		}
	}

	/** 原 PlayState.opponentNoteHit（作用域分析：零遮蔽，31 处成员引用已限定）。 */
	public static function opponentNoteHit(ps:PlayState, note:Note):Void
	{
		ps.stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note)); //Psych 1.0.4：场景命中回调（Weekend 1）
		if (Paths.formatToSongPath(PlayState.SONG.song) != 'tutorial')
			ps.camZooming = true;

		if(note.noteType == 'Hey!' && !ClientPrefs.data.hudOnly && ps.dad.animOffsets.exists('hey')) {
			ps.dad.playAnim('hey', true);
			ps.dad.specialAnim = true;
			ps.dad.heyTimer = 0.6;
		} else if(!ClientPrefs.data.hudOnly && !note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (PlayState.SONG.notes[ps.curSection] != null)
			{
				if (PlayState.SONG.notes[ps.curSection].altAnim && !PlayState.SONG.notes[ps.curSection].gfSection) {
					altAnim = '-alt';
				}
			}

			var char:Character = ps.dad;
			var animToPlay:String = ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length-1, note.noteData)))] + altAnim;
			if(note.gfNote) {
				char = ps.gf;
			}

			if(char != null)
			{
				char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if (PlayState.SONG.needsVoices && ps.opponentVocals.length <= 0)
			ps.vocals.volume = 1;

		if (ClientPrefs.data.opponentLightStrum)
			ps.strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / ps.playbackRate);
		note.hitByOpponent = true;

		// JS Engine 移植：关闭命中回调（noHitFuncs）
		if (!ClientPrefs.data.noHitFuncs)
		{
			var result:Dynamic = ps.callOnLuas('opponentNoteHit', [ps.notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
			if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) ps.callOnHScript('opponentNoteHit', [note]);
		}

		// 原生长条按压覆盖（模组 opponentNoteHit 回调同点触发，轨偏移 +4）
		if (ps.holdCoverHandler != null && note.isSustainNote)
			ps.holdCoverHandler.onHit(4 + Std.int(Math.abs(note.noteData)));

		if (!note.isSustainNote)
		{
			// 对方推条：开启后对手命中箭头会像玩家一样加血（推条向对方侧移动），但最低保留一点血量，不会被推死
			if (ClientPrefs.getGameplaySetting('opponentpush') == true)
				ps.health -= Math.min(note.hitHealth * ps.healthLoss, Math.max(0, ps.health - 0.01));
			ps.notes.invalidateNote(note);
		}
	}

	/** 原 PlayState.noteMiss（作用域分析：零遮蔽，8 处成员引用已限定）。 */
	public static function noteMiss(ps:PlayState, daNote:Note):Void
	{
		 //You didn't hit the key and let it go offscreen, also used by Hurt Notes
				ps.stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote)); //Psych 1.0.4：场景 miss 回调（Weekend 1）
				// NPS 统计：漏掉的音符也计入“收到”（堆叠合并按 density 计）
				if (!daNote.isSustainNote) ps._npsCount += Std.int(daNote.density);
				// Dupe note remove：只移除"谱面原始重复"（charter 在同一个时间刻度上放了多颗完全相同音符）。
				// 展开簇内同时间箭头（同 chartSeq）不在此列——否则整簇被静默杀掉不计数，结算总数对不上。
				ps.notes.forEachAlive(function(note:Note) {
					if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData
						&& daNote.isSustainNote == note.isSustainNote
						&& Math.abs(daNote.strumTime - note.strumTime) < 1
						&& note.chartSeq != daNote.chartSeq) {
						ps.notes.invalidateNote(note);
					}
				});

				ps.noteMissCommon(daNote.noteData, daNote);
				var result:Dynamic = ps.callOnLuas('noteMiss', [ps.notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
				if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) ps.callOnHScript('noteMiss', [daNote]);
	}

	/** 原 PlayState.playOnlineOppMiss（作用域分析：零遮蔽，6 处成员引用已限定）。 */
	public static function playOnlineOppMiss(ps:PlayState, data:Int, note:Note):Void
	{
		var char:Character = ps.dad;
		if (note != null && note.gfNote) char = ps.gf;
		if (char != null && char.hasMissAnimations)
		{
			var suffix:String = note != null ? note.animSuffix : '';
			char.playAnim(ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length - 1, data)))] + 'miss' + suffix, true);
		}
		if (ps.opponentVocals != null) ps.opponentVocals.volume = 0;
	}

	/** 原 PlayState.beatHit（作用域分析：零遮蔽，57 处成员引用已限定）。 */
	public static function beatHit(ps:PlayState)
	{
			if (ps.rewinding) return; // 回溯期间不触发拍点回调（角色/图标保持静止）

			if(ps.lastBeatHit >= ps.curBeat) {
				//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
				return;
			}

			if (ps.generatedMusic)
				ps.notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		if(ClientPrefs.data.sbIconBop){
			if (ps.curBeat % ps.gfSpeed == 0) {
				if (ps.curBeat % (ps.gfSpeed * 2) == 0) {
					ps.iconP1.scale.set(0.8, 0.8);
					ps.iconP2.scale.set(1.2, 1.3);

					ps.iconP1.angle = -15;
					ps.iconP2.angle = 15;
				} else {
					ps.iconP2.scale.set(0.8, 0.8);
					ps.iconP1.scale.set(1.2, 1.3);

					ps.iconP2.angle = -15;
					ps.iconP1.angle = 15;
				}
			}
		}

			if (ClientPrefs.data.keIconBop)
			{
				// KE 引擎图标跳动：每拍放大 30px（相当于 scale + 30/frameWidth），随后在 update 中按时间缩回
				ps.iconP1.scale.x += 30 / ps.iconP1.frameWidth;
				ps.iconP1.scale.y = ps.iconP1.scale.x;
				ps.iconP1.updateHitbox();
				ps.iconP1.origin.set(0, 0); // Kade 风格：以左上角为缩放中心，放大时向右下扩展
				ps.iconP2.scale.x += 30 / ps.iconP2.frameWidth;
				ps.iconP2.scale.y = ps.iconP2.scale.x;
				ps.iconP2.updateHitbox();
				ps.iconP2.origin.set(0, 0);
			}
			else
			{
				ps.iconP1.scale.set(1.2, 1.2);
				ps.iconP2.scale.set(1.2, 1.2);

				ps.iconP1.updateHitbox();
				ps.iconP2.updateHitbox();
			}

			if (!ClientPrefs.data.hudOnly && ps.gf != null && ps.curBeat % Math.round(ps.gfSpeed * ps.gf.danceEveryNumBeats) == 0 && !ps.gf.getAnimationName().startsWith('sing') && !ps.gf.stunned)
				ps.gf.dance();
			if (!ClientPrefs.data.hudOnly && ps.boyfriend != null && ps.curBeat % ps.boyfriend.danceEveryNumBeats == 0 && !ps.boyfriend.getAnimationName().startsWith('sing') && !ps.boyfriend.stunned)
				ps.boyfriend.dance();
			if (!ClientPrefs.data.hudOnly && ps.dad != null && ps.curBeat % ps.dad.danceEveryNumBeats == 0 && !ps.dad.getAnimationName().startsWith('sing') && !ps.dad.stunned)
				ps.dad.dance();

			ps.meteoSuper_beatHit();
			ps.lastBeatHit = ps.curBeat;

			ps.setOnScripts('curBeat', ps.curBeat);
			ps.callOnScripts('onBeatHit');
	}

	/** 原 PlayState.sectionHit（作用域分析：零遮蔽，30 处成员引用已限定）。 */
	public static function sectionHit(ps:PlayState)
	{
		if (ps.rewinding) return; // 回溯中不移动镜头、不改 BPM
		if (PlayState.SONG.notes[ps.curSection] != null)
		{
			if (ps.generatedMusic && !ps.endingSong && !ps.isCameraOnForcedPos)
				ps.moveCameraSection();

			if (ps.camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
			{
				FlxG.camera.zoom += 0.015 * ps.camZoomingMult;
				ps.camHUD.zoom += 0.03 * ps.camZoomingMult;
			}

			if (PlayState.SONG.notes[ps.curSection].changeBPM)
			{
				Conductor.bpm = PlayState.SONG.notes[ps.curSection].bpm;
				ps.setOnScripts('curBpm', Conductor.bpm);
				ps.setOnScripts('crochet', Conductor.crochet);
				ps.setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			ps.setOnScripts('mustHitSection', PlayState.SONG.notes[ps.curSection].mustHitSection);
			ps.setOnScripts('altAnim', PlayState.SONG.notes[ps.curSection].altAnim);
			ps.setOnScripts('gfSection', PlayState.SONG.notes[ps.curSection].gfSection);
		}
		ps.meteoSuper_sectionHit();

		ps.setOnScripts('curSection', ps.curSection);
		ps.callOnScripts('onSectionHit');
	}

	/** 原 PlayState.stepHit（作用域分析：零遮蔽，17 处成员引用已限定）。 */
	public static function stepHit(ps:PlayState)
	{
		if (ps.rewinding) return; // 回溯期间不触发步点回调，避免重开音频

		if(FlxG.sound.music.length > 0 && FlxG.sound.music.time >= -ClientPrefs.data.noteOffset)
		{
			// 音频不可用（length=0）时跳过漂移检测：空音频 music.time 恒 0，
			// 会把 songPosition 误判为"漂移>20ms"→ resyncVocals 把时钟拉回 0（0:00 卡死根因）
			var drift:Float = FlxG.sound.music.time - (Conductor.songPosition - Conductor.offset);
			if (Math.abs(drift) > (20 * ps.playbackRate)
				|| (PlayState.SONG.needsVoices && Math.abs(ps.vocals.time - (Conductor.songPosition - Conductor.offset)) > (20 * ps.playbackRate))
				|| (PlayState.SONG.needsVoices && ps.opponentVocals.length > 0 && Math.abs(ps.opponentVocals.time - (Conductor.songPosition - Conductor.offset)) > (20 * ps.playbackRate)))
			{
				ps.resyncVocals();
			}
		}

		ps.meteoSuper_stepHit();

		if(ps.curStep == ps.lastStepHit) {
			return;
		}

		ps.lastStepHit = ps.curStep;
		ps.setOnScripts('curStep', ps.curStep);
		ps.callOnScripts('onStepHit');
	}
}
