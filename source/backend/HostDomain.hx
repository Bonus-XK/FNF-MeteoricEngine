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
import sys.io.File;
import sys.FileSystem;
import backend.Mods;
import lime.utils.Assets;
import tea.SScript;
import objects.Character;
import backend.StageData;
import backend.StageData.StageFile;
import backend.Achievements;
import backend.Difficulty;
import backend.Discord.DiscordClient;
import objects.MobileControls;
import backend.Multiplayer;
import substates.PauseSubState;

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

	/** 原 PlayState.initLuaShader（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function initLuaShader(ps:PlayState, name:String, ?glslVersion:Int = 120):Bool
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(ps.runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));

		for(mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));

		for (folder in foldersToCheck)
		{
			if(FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if(FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else frag = null;

				if(FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else vert = null;

				if(found)
				{
					ps.runtimeShaders.set(name, [frag, vert]);
					//trace('Found shader $name!');
					return true;
				}
			}
		}
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}

	/** 原 PlayState.startCharacterScripts（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function startCharacterScripts(ps:PlayState, name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/' + name + '.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getPreloadPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getPreloadPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in ps.luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		{
			scriptFile = Paths.getPreloadPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}

		if(doPush)
		{
			if(SScript.global.exists(scriptFile))
				doPush = false;

			if(doPush) ps.initHScript(scriptFile);
		}
		#end
	}

	/** 原 PlayState.ensureCharactersAlive（作用域分析：零遮蔽，56 处成员引用已限定）。 */
	public static function ensureCharactersAlive(ps:PlayState):Void
	{
		#if desktop
		if (PlayState.SONG == null) return;
		if (ps.boyfriend == null)
		{
			var cName:String = (PlayState.SONG.player1 != null && PlayState.SONG.player1.length > 0) ? PlayState.SONG.player1 : 'bf';
			try
			{
				ps.boyfriend = ps.boyfriendMap.get(cName);
				if (ps.boyfriend == null)
				{
					ps.boyfriend = new Character(0, 0, cName, true);
					ps.boyfriendMap.set(cName, ps.boyfriend);
				}
				if (!ps.boyfriendGroup.members.contains(ps.boyfriend))
				{
					ps.startCharacterPos(ps.boyfriend);
					ps.boyfriendGroup.add(ps.boyfriend);
					ps.startCharacterScripts(ps.boyfriend.curCharacter);
				}
			}
			catch (e:Dynamic) { trace('[角色自愈] boyfriend 重建失败：' + e); }
		}
		if (ps.dad == null)
		{
			var cName:String = (PlayState.SONG.player2 != null && PlayState.SONG.player2.length > 0) ? PlayState.SONG.player2 : 'dad';
			try
			{
				ps.dad = ps.dadMap.get(cName);
				if (ps.dad == null)
				{
					ps.dad = new Character(0, 0, cName);
					ps.dadMap.set(cName, ps.dad);
				}
				if (!ps.dadGroup.members.contains(ps.dad))
				{
					ps.startCharacterPos(ps.dad, true);
					ps.dadGroup.add(ps.dad);
					ps.startCharacterScripts(ps.dad.curCharacter);
				}
			}
			catch (e:Dynamic) { trace('[角色自愈] dad 重建失败：' + e); }
		}
		if (ps.gf == null)
		{
			var cName:String = (PlayState.SONG.gfVersion != null && PlayState.SONG.gfVersion.length > 0) ? PlayState.SONG.gfVersion : 'gf';
			try
			{
				ps.gf = ps.gfMap.get(cName);
				if (ps.gf == null)
				{
					ps.gf = new Character(0, 0, cName);
					ps.gfMap.set(cName, ps.gf);
				}
				if (!ps.gfGroup.members.contains(ps.gf))
				{
					ps.startCharacterPos(ps.gf);
					ps.gf.scrollFactor.set(0.95, 0.95);
					ps.gfGroup.add(ps.gf);
					ps.startCharacterScripts(ps.gf.curCharacter);
				}
			}
			catch (e:Dynamic) { trace('[角色自愈] gf 重建失败：' + e); }
		}
		#end
	}

	/** 原 PlayState.reloadDefaultCharacters（作用域分析：零遮蔽，63 处成员引用已限定）。 */
	public static function reloadDefaultCharacters(ps:PlayState):Void
	{
		// 销毁旧角色实例并清空缓存（角色脚本通过 PlayState 动态访问角色，不受影响）
		ps.destroyAllCharacters();

		// 重新创建默认角色（与 create() 逻辑一致：全新对象、正确位置与状态）
		var stageData:StageFile = StageData.getStageFile(PlayState.curStage);
		if (stageData == null) stageData = StageData.dummy();
		if (!stageData.hide_girlfriend)
		{
			if (PlayState.SONG.gfVersion == null || PlayState.SONG.gfVersion.length < 1) PlayState.SONG.gfVersion = 'gf';
			ps.gf = new Character(0, 0, PlayState.SONG.gfVersion);
			ps.startCharacterPos(ps.gf);
			ps.gf.scrollFactor.set(0.95, 0.95);
			ps.gfGroup.add(ps.gf);
			ps.gfMap.set(PlayState.SONG.gfVersion, ps.gf);
			ps.startCharacterScripts(ps.gf.curCharacter);
		}

		ps.dad = new Character(0, 0, PlayState.SONG.player2);
		ps.startCharacterPos(ps.dad, true);
		ps.dadGroup.add(ps.dad);
		ps.dadMap.set(PlayState.SONG.player2, ps.dad);
		ps.startCharacterScripts(ps.dad.curCharacter);

		ps.boyfriend = new Character(0, 0, PlayState.SONG.player1, true);
		ps.startCharacterPos(ps.boyfriend);
		ps.boyfriendGroup.add(ps.boyfriend);
		ps.boyfriendMap.set(PlayState.SONG.player1, ps.boyfriend);
		ps.startCharacterScripts(ps.boyfriend.curCharacter);

		// JS Engine 移植：只显示 HUD——快速重开重建角色后保持角色组不可见
		if (ClientPrefs.data.hudOnly)
		{
			ps.gfGroup.visible = false;
			ps.dadGroup.visible = false;
			ps.boyfriendGroup.visible = false;
		}

		if (ps.dad.curCharacter.startsWith('gf'))
		{
			ps.dad.setPosition(ps.GF_X, ps.GF_Y);
			if (ps.gf != null) ps.gf.visible = false;
		}

		// 重新预加载 Event 会切换到的角色（与完整重开的 eventPushed 预加载一致）
		if (ps.cachedEventNotes != null)
		{
			for (event in ps.cachedEventNotes)
			{
				if (event.event != 'Change Character' || event.value1 == null) continue;
				var charType:Int = 0;
				switch(event.value1.toLowerCase().trim())
				{
					case 'gf' | 'girlfriend': charType = 2;
					case 'dad' | 'opponent': charType = 1;
					default:
						charType = Std.parseInt(event.value1);
						if (Math.isNaN(charType)) charType = 0;
				}
				ps.addCharacterToList(event.value2, charType);
			}
		}

		ps.iconP1.changeIcon(ps.boyfriend.healthIcon);
		ps.iconP2.changeIcon(ps.dad.healthIcon);
		ps.setOnScripts('boyfriendName', ps.boyfriend.curCharacter);
		ps.setOnScripts('dadName', ps.dad.curCharacter);
		if (ps.gf != null) ps.setOnScripts('gfName', ps.gf.curCharacter);
		ps.reloadHealthBarColors();
	}

	/** 原 PlayState.checkForAchievement（作用域分析：零遮蔽，14 处成员引用已限定）。 */
	public static function checkForAchievement(ps:PlayState, achievesToCheck:Array<String> = null):String
	{
		if(PlayState.chartingMode) return null;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		for (i in 0...achievesToCheck.length) {
			var achievementName:String = achievesToCheck[i];
			if(!Achievements.isAchievementUnlocked(achievementName) && !ps.cpuControlled && Achievements.getAchievementIndex(achievementName) > -1) {
				var unlock:Bool = false;
				if (achievementName == WeekData.getWeekFileName() + '_nomiss') // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
				{
					if(PlayState.isStoryMode && PlayState.campaignMisses + ps.songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
						&& PlayState.storyPlaylist.length <= 1 && !PlayState.changedDifficulty && !usedPractice)
						unlock = true;
				}
				else
				{
					switch(achievementName)
					{
						case 'ur_bad':
							unlock = (ps.ratingPercent < 0.2 && !ps.practiceMode);

						case 'ur_good':
							unlock = (ps.ratingPercent >= 1 && !usedPractice);

						case 'roadkill_enthusiast':
							unlock = (Achievements.henchmenDeath >= 50);

						case 'oversinging':
							unlock = (ps.boyfriend.holdTimer >= 10 && !usedPractice);

						case 'hype':
							unlock = (!ps.boyfriendIdled && !usedPractice);

						case 'two_keys':
							unlock = (!usedPractice && ps.keysPressed.length <= 2);

						case 'toastie':
							unlock = (/*ClientPrefs.data.framerate <= 60 &&*/ !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

						case 'debugger':
							unlock = (Paths.formatToSongPath(PlayState.SONG.song) == 'test' && !usedPractice);
					}
				}

				if(unlock) {
					Achievements.unlockAchievement(achievementName);
					return achievementName;
				}
			}
		}
		return null;
	}

	/** 原 PlayState.openPauseMenu（作用域分析：零遮蔽，19 处成员引用已限定）。 */
	public static function openPauseMenu(ps:PlayState, fromRemote:Bool = false)
	{
		// 防重入：后台/失焦/按键可能在同一帧多次触发，避免打开多个暂停界面
		if (ps.paused) return;

		FlxG.camera.followLerp = 0;
		ps.persistentUpdate = false;
		ps.persistentDraw = true;
		ps.paused = true;
		// 联机：仅「主动暂停」广播 PAUSE；远程收到的 PAUSE 打开时不再回发，
		// 否则对方点继续后会被这个回显 PAUSE 再次强制暂停（无法恢复游玩）
		if (PlayState.isOnlineMode && !fromRemote) Multiplayer.send('PAUSE');
		// 侧边栏（stage 级 TextField）不随 flixel 暂停，需手动隐藏，恢复后 updateJudgementTxt 自动显示
		if (ps.hud != null && ps.hud.judgementField != null) ps.hud.judgementField.visible = false;

		// 1 / 1000 chance for Gitaroo Man easter egg
		/*if (FlxG.random.bool(0.1))
		{
			// gitaroo man easter egg
			cancelMusicFadeTween();
			MusicBeatState.switchState(new GitarooPause());
		}
		else {*/
		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			ps.vocals.pause();
			ps.opponentVocals.pause();
		}
		if(!ps.cpuControlled)
		{
			for (note in ps.playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		#if mobile
		// 暂停时隐藏游戏触控板，避免暂停界面还显示游戏方向键
		if (objects.MobileControls.instance != null)
		{
			objects.MobileControls.instance.visible = false;
		}
		#end
		// 防“暂停键判定两次”：此时 flixel 输入还未被 onStateSwitch 重置，
		// 捕获打开暂停的按键是否仍按住 → 传给暂停菜单锁定确认，直到该键物理松开
		var pauseKeyHeld:Bool = FlxG.keys.anyPressed(PauseSubState.getPauseKeys());
		ps.openSubState(new PauseSubState(ps.boyfriend.getScreenPosition().x, ps.boyfriend.getScreenPosition().y, pauseKeyHeld));
		//}

		#if desktop
		DiscordClient.changePresence(ps.detailsPausedText, PlayState.SONG.song + " (" + ps.storyDifficultyText + ")", ps.iconP2.getCharacter());
		#end
	}

	/** 原 PlayState.startVideo（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function startVideo(ps:PlayState, name:String, ?onComplete:Void->Void = null)
	{
		#if VIDEOS_ALLOWED
		ps.inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			if(onComplete != null) onComplete();
			else ps.startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				if(onComplete != null) onComplete();
				else ps.startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				if(onComplete != null) onComplete();
				else ps.startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		ps.startAndEnd();
		return;
		#end
	}

	/** 原 PlayState.addCharacterToList（作用域分析：零遮蔽，16 处成员引用已限定）。 */
	public static function addCharacterToList(ps:PlayState, newCharacter:String, type:Int)
	{
		switch(type) {
			case 0:
				if(!ps.boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					ps.boyfriendMap.set(newCharacter, newBoyfriend);
					ps.boyfriendGroup.add(newBoyfriend);
					ps.startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					ps.startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!ps.dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					ps.dadMap.set(newCharacter, newDad);
					ps.dadGroup.add(newDad);
					ps.startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					ps.startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(ps.gf != null && !ps.gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					ps.gfMap.set(newCharacter, newGf);
					ps.gfGroup.add(newGf);
					ps.startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					ps.startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	/** 原 PlayState.syncGameplaySettings（作用域分析：零遮蔽，24 处成员引用已限定）。 */
	public static function syncGameplaySettings(ps:PlayState):Void
	{
		var oldPractice:Bool = ps.practiceMode;
		var oldBotplay:Bool = ps.cpuControlled;

		ps.playbackRate = ClientPrefs.getGameplaySetting('songspeed');
		ps.songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(ps.songSpeedType)
		{
			case "multiplicative":
				ps.songSpeed = PlayState.SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				ps.songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}
		ps.healthGain = ClientPrefs.getGameplaySetting('healthgain');
		ps.healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		ps.instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		ps.practiceMode = ClientPrefs.getGameplaySetting('practice');
		ps.cpuControlled = ClientPrefs.getGameplaySetting('botplay');

		if (ps.cpuControlled) ps.usedAutoplay = true;

		if (ps.practiceMode != oldPractice || ps.cpuControlled != oldBotplay)
			PlayState.changedDifficulty = true;

		if (ps.botplayTxt != null)
		{
			ps.botplayTxt.visible = ps.cpuControlled || ps.replayMode;
			ps.botplayTxt.alpha = 1;
			ps.botplaySine = 0;
		}
	}
}
