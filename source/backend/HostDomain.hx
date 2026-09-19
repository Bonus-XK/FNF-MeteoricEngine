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
import cne.CneScriptCompat;
import psychlua.HScript;
import backend.TurboDensity;
import backend.TurboDensity.TurboZone;
import flixel.addons.display.FlxRuntimeShader;
import backend.BaseStage;
import psychlua.DebugLuaText;
import flixel.util.FlxStringUtil;
import backend.MeteoricProfile;
import backend.Replay.ReplayEvent;
import flixel.FlxSubState;

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

	/** 原 PlayState.initHScript（作用域分析：零遮蔽，15 处成员引用已限定）。 */
	public static function initHScript(ps:PlayState, file:String, ?cneGlobals:Map<String, Dynamic> = null, ?cneCallbacks:Bool = false)
	{
		// 回放模式不加载 HScript（与 Lua 同理：避免脚本修改箭头显示影响回放）
		if (ps.replayMode) return;
		try
		{
			// Psych 0.7.3 兼容：读取 .hx 内容并预处理（var x:Map = [] → new Map()），以代码串交给 SScript
			var scriptCode:String = file;
			#if sys
			try
			{
				if (sys.FileSystem.exists(file))
					scriptCode = HScript.preprocessScript(sys.io.File.getContent(file));
			}
			catch (e:Dynamic) {}
			#end
			// executeNow=false：先把 globals（含 CNE 的 FunkinSprite/stage/insert）注入，再执行脚本。
			// CNE 歌曲脚本顶层就有 `var pluh:FlxSprite = new FlxSprite();` /
			// `var fadeThing:FunkinSprite = new FunkinSprite()...`，若先 execute 会报
			// "Unknown variable: FunkinSprite"（2026-09-18 实测）。
			var newScript:HScript = new HScript(null, scriptCode, false);
			// 66mod 等 Psych 0.7 模组对话脚本需要 songName / startDialogue
			newScript.set('songName', ps.songName);
			newScript.set('startDialogue', function(dialogue:Dynamic) ps.startDialogue(dialogue));
			// Psych 0.7.3 setSpecialObject 等价物：onCreate 阶段即可访问角色/摄像机（setOnScripts 只推给已加载脚本，stage 脚本加载时拿不到）
			newScript.set('dad', ps.dad);
			newScript.set('boyfriend', ps.boyfriend);
			newScript.set('gf', ps.gf);
			newScript.set('camGame', ps.camGame);
			// 兼容 66mod 舞台脚本（home.hx 等直接访问 camFollow/camHUD）
			newScript.set('camFollow', ps.camFollow);
			newScript.set('camHUD', ps.camHUD);
			// CNE 歌曲脚本：注入 CNE 专用 globals（stage/FunkinSprite/insert…），必须在 execute 之前。
			if (cneGlobals != null)
			{
				for (k => v in cneGlobals) newScript.set(k, v);
			}
			try newScript.execute() catch (e:Dynamic) { trace('HScript execute failed: ' + Std.string(e)); }
			// CNE 回调别名（create→onCreate、stepHit→onStepHit…）必须在 execute 之后：
			// 脚本函数已解析，`exists('create')` 才为真；同时要早于下面的 onCreate 调用。
			if (cneCallbacks)
				cne.CneScriptCompat.applyCallbacks(newScript);
			@:privateAccess
			if(newScript.parsingExceptions != null && newScript.parsingExceptions.length > 0)
			{
				@:privateAccess
				for (e in newScript.parsingExceptions)
					if(e != null)
						ps.addTextToDebug('ERROR ON LOADING ($file): ${e.message.substr(0, e.message.indexOf('\n'))}', FlxColor.RED);
				newScript.destroy();
				return;
			}

			ps.hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
						if (e != null)
						{
							var errMsg:String = e.message != null ? e.message : Std.string(e);
							ps.addTextToDebug('ERROR ($file: onCreate) - ${errMsg.substr(0, errMsg.indexOf('\n'))}', FlxColor.RED);
						}

					newScript.destroy();
					ps.hscriptArray.remove(newScript);
					trace('failed to initialize sscript interp!!! ($file)');
				}
				else trace('initialized sscript interp successfully: $file');
			}

		}
		catch(e)
		{
			ps.addTextToDebug('ERROR ($file) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
			var newScript:HScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				ps.hscriptArray.remove(newScript);
			}
		}
	}

	/** 原 PlayState.resyncVocals（作用域分析：零遮蔽，13 处成员引用已限定）。 */
	public static function resyncVocals(ps:PlayState):Void
	{
		if(ps.finishTimer != null) return;
		// 【Obsolescence-spam 0:00 卡死根因修复】空/流式不可用音频（music.length<=0）时，
		// music.time 恒为 0：若仍用 music.time 回写 songPosition，每次 stepHit 的漂移检测
		// （|0 - songPos| > 20ms）都会把歌曲时钟拉回 0 → 音符永不生成、HUD 恒 0:00。
		// 无音频可同步时只做音量/人声恢复，绝不动歌曲时钟（结算由 update 时间轴兜底）。
		if (FlxG.sound.music == null || FlxG.sound.music.length <= 0) return;

		ps.vocals.pause();
		ps.opponentVocals.pause();

		FlxG.sound.music.play();
		FlxG.sound.music.pitch = ps.playbackRate;
		Conductor.syncToMusic();
		if (Conductor.songPosition <= ps.vocals.length)
		{
			ps.vocals.time = Conductor.songPosition;
			ps.opponentVocals.time = Conductor.songPosition;
			ps.vocals.pitch = ps.playbackRate;
			ps.opponentVocals.pitch = ps.playbackRate;
		}
		ps.vocals.play();
		ps.opponentVocals.play();
	}

	/** 原 PlayState.initTurboZones（作用域分析：零遮蔽，11 处成员引用已限定）。 */
	public static function initTurboZones(ps:PlayState):Void
	{
		try
		{
			var meta:Dynamic = {
				song: PlayState.SONG != null ? PlayState.SONG.song : '',
				mod: (backend.Mods.currentModDirectory != null ? backend.Mods.currentModDirectory : ''),
				notes: ps.unspawnNotes != null ? ps.unspawnNotes.length : 0,
				fingerprint: TurboDensity.chartFingerprint(ps.unspawnNotes)
			};
			var path:String = TurboDensity.cachePath(meta.song, meta.mod, ps.unspawnNotes);
			var cached:Array<TurboZone> = TurboDensity.loadCache(path, meta);
			if (cached != null)
			{
				ps.turboZones = cached;
				return;
			}
			ps.turboZones = TurboDensity.buildZones(ps.unspawnNotes);
			TurboDensity.saveCache(path, ps.turboZones, meta);
		}
		catch (e:Dynamic)
		{
			ps.turboZones = [];
		}
	}

	/** 原 PlayState.setSongTime（作用域分析：零遮蔽，12 处成员引用已限定）。 */
	public static function setSongTime(ps:PlayState, time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		ps.vocals.pause();
		ps.opponentVocals.pause();

		FlxG.sound.music.time = time;
		FlxG.sound.music.pitch = ps.playbackRate;
		FlxG.sound.music.play();

		if (Conductor.songPosition <= ps.vocals.length)
		{
			ps.vocals.time = time;
			ps.opponentVocals.time = time;
			ps.vocals.pitch = ps.playbackRate;
			ps.opponentVocals.pitch = ps.playbackRate;
		}
		ps.vocals.play();
		ps.opponentVocals.play();
		Conductor.setPosition(time);
	}

	/** 原 PlayState.startLuasNamed（作用域分析：零遮蔽，1 处成员引用已限定）。 */
	public static function startLuasNamed(ps:PlayState, luaFile:String):Bool
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getPreloadPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getPreloadPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in ps.luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}

	/** 原 PlayState.createRuntimeShader（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function createRuntimeShader(ps:PlayState, name:String):FlxRuntimeShader
	{
		if(!ClientPrefs.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!ps.runtimeShaders.exists(name) && !ps.initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		backend.CrashHandler.logEvent('createRuntimeShader: ' + name);
		var arr:Array<String> = ps.runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	/** 原 PlayState.finishSong（作用域分析：零遮蔽，11 处成员引用已限定）。 */
	public static function finishSong(ps:PlayState, ?ignoreNoteOffset:Bool = false):Void
	{
		if (ps.endingSong || ps.finishingSong) return; // 防重入：哑谱自动结算与空音频 onComplete / 延迟窗口内的重复触发
		ps.finishingSong = true;
		ps.updateTime = false;
		FlxG.sound.music.volume = 0;
		ps.vocals.volume = 0;
		ps.vocals.pause();
		ps.opponentVocals.volume = 0;
		ps.opponentVocals.pause();
		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			ps.endCallback();
		} else {
			ps.finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				ps.endCallback();
			});
		}
	}

	/** 原 PlayState.destroyAllCharacters（作用域分析：零遮蔽，6 处成员引用已限定）。 */
	public static function destroyAllCharacters(ps:PlayState):Void
	{
		for (group in [ps.boyfriendGroup, ps.dadGroup, ps.gfGroup])
		{
			if (group == null) continue;
			for (member in group.members.copy())
			{
				if (member == null || !Std.isOfType(member, Character)) continue;
				group.remove(member, true);
				cast(member, Character).destroy();
			}
		}
		ps.boyfriendMap.clear();
		ps.dadMap.clear();
		ps.gfMap.clear();
	}

	/** 原 PlayState.startHScriptsNamed（作用域分析：零遮蔽，1 处成员引用已限定）。 */
	public static function startHScriptsNamed(ps:PlayState, scriptFile:String):Bool
	{
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getPreloadPath(scriptFile);

		if(FileSystem.exists(scriptToLoad))
		{
			if (SScript.global.exists(scriptToLoad)) return false;

			ps.initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	/** 原 PlayState.startSong（作用域分析：零遮蔽，36 处成员引用已限定）。 */
	public static function startSong(ps:PlayState):Void
	{
		ps.startingSong = false;

		@:privateAccess FlxG.sound.playMusic(ps.inst._sound, 1, false);
		FlxG.sound.music.pitch = ps.playbackRate;
		FlxG.sound.music.onComplete = ps.finishSong.bind();
		ps.vocals.play();
		ps.opponentVocals.play();

		ps.stagesFunc(function(stage:BaseStage) stage.startSong()); //Psych 1.0.4：场景 startSong 钩子（Weekend 1）

		if(PlayState.startOnTime > 0) ps.setSongTime(PlayState.startOnTime - 500);
		PlayState.startOnTime = 0;
		if(ps.paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			ps.vocals.pause();
			ps.opponentVocals.pause();
		}

		// Song duration in a float, useful for the time left feature
		ps.songLength = FlxG.sound.music.length;
		// 【0:00 卡结算 修复二】歌曲时长至少不短于谱面末尾：
		// ① 音频缺失/文件损坏 → 空 Sound，music.length=0 且 onComplete 永不触发；
		// ② 流式 Vorbis（streamSongAudio）等场景 music.length 也可能为 0/不可靠。
		// 一律取 max(音频长度, 谱面末尾) —— HUD 时间有依据，update 的"越过时长即收尾"
		// 也保证任何歌曲都能正常结算，不再依赖 onComplete。
		if (ps.chartEndTimeMs <= 0 && ps.unspawnNotes != null && ps.unspawnNotes.length > 0)
		{
			// 兜底再算一次（覆盖非 generateChartNotes 路径/异常早退）
			var _lastCast0:CastNote = ps.unspawnNotes[ps.unspawnNotes.length - 1];
			ps.chartEndTimeMs = _lastCast0.strumTime + _lastCast0.holdLength + Conductor.safeZoneOffset + 1000;
		}
		if (ps.chartEndTimeMs > ps.songLength)
		{
			ps.songLength = ps.chartEndTimeMs;
			trace('[Audio] songLength 按谱面末尾兜底：' + Std.int(ps.songLength) + 'ms（music.length=' + Std.int(FlxG.sound.music.length) + 'ms）');
		}
		FlxTween.tween(ps.timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(ps.timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if desktop
		// Updating Discord Rich Presence (with Time Left)
		DiscordClient.changePresence(ps.detailsText, PlayState.SONG.song + " (" + ps.storyDifficultyText + ")", ps.iconP2.getCharacter(), true, ps.songLength);
		#end
		ps.setOnScripts('songLength', ps.songLength);
		ps.callOnScripts('onSongStart');
		CrashHandler.mark('PlayState.startSong:music-playing');
	}

	/** 原 PlayState.callOnHScript（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function callOnHScript(ps:PlayState, funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic
	{
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = PlayState._noExclusions;
		if(excludeValues == null) excludeValues = PlayState._noExcludeValues;
		else if (excludeValues != PlayState._noExcludeValues) excludeValues.push(psychlua.FunkinLua.Function_Continue);

		var len:Int = ps.hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len)
		{
			var script:HScript = ps.hscriptArray[i];
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try
			{
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
						FunkinLua.luaTrace('ERROR (${script.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), true, false, FlxColor.RED);
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == FunkinLua.Function_StopHScript || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}

					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	/** 原 PlayState.callOnLuas（作用域分析：零遮蔽，4 处成员引用已限定）。 */
	public static function callOnLuas(ps:PlayState, funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic
	{
		var returnVal:Dynamic = FunkinLua.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = PlayState._noExclusions;
		if(excludeValues == null) excludeValues = PlayState._noExcludeValues;

		var len:Int = ps.luaArray.length;
		var i:Int = 0;
		while(i < len)
		{
			var script:FunkinLua = ps.luaArray[i];
			if(exclusions.contains(script.scriptName))
			{
				i++;
				continue;
			}

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == FunkinLua.Function_StopLua || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(!script.closed) i++;
			else len--;
		}
		#end
		return returnVal;
	}

	/** 原 PlayState.addTextToDebug（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function addTextToDebug(ps:PlayState, text:String, color:FlxColor)
	{
		#if LUA_ALLOWED
		var newText:DebugLuaText = ps.luaDebugGroup.recycle(DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		ps.luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
			spr.y += newText.height + 2;
		});
		ps.luaDebugGroup.add(newText);
		#end
	}

	/** 原 PlayState.setOnLuas（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function setOnLuas(ps:PlayState, variable:String, arg:Dynamic, exclusions:Array<String> = null)
	{
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = PlayState._noExclusions;
		for (script in ps.luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	/** 原 PlayState.setOnHScript（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function setOnHScript(ps:PlayState, variable:String, arg:Dynamic, exclusions:Array<String> = null)
	{
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = PlayState._noExclusions;
		for (script in ps.hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	/** 原 PlayState.isTurboAggregateIndex（作用域分析：零遮蔽，11 处成员引用已限定）。 */
	public static function isTurboAggregateIndex(ps:PlayState, index:Int):Bool
	{
		if (ps.turboZones == null || ps.turboZones.length == 0 || index < 0)
			return false;
		while (ps.turboZoneCursor < ps.turboZones.length && ps.turboZones[ps.turboZoneCursor].endIndex <= index)
			ps.turboZoneCursor++;
		if (ps.turboZoneCursor >= ps.turboZones.length)
			return false;
		var z:TurboZone = ps.turboZones[ps.turboZoneCursor];
		return index >= z.startIndex && index < z.endIndex;
	}

	/** 原 PlayState.freezeBackgroundAudio（作用域分析：零遮蔽，6 处成员引用已限定）。 */
	public static function freezeBackgroundAudio(ps:PlayState):Void
	{
		if (ps._bgAudioFrozen) return;
		ps._bgAudioFrozen = true;
		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		if (ps.vocals != null) ps.vocals.pause();
		if (ps.opponentVocals != null) ps.opponentVocals.pause();
		// 暂停菜单音乐等所有在播 FlxSound 一并冻结，避免锁屏/后台期间仍有声音
		for (sound in FlxG.sound.list.members)
			if (sound != null) sound.pause();
	}

	/** 原 PlayState.restoreBackgroundAudio（作用域分析：零遮蔽，7 处成员引用已限定）。 */
	public static function restoreBackgroundAudio(ps:PlayState):Void
	{
		if (!ps._bgAudioFrozen) return;
		ps._bgAudioFrozen = false;
		// 若玩家仍处于暂停菜单（未返回游戏），保持静音；真正恢复由 closeSubState/resyncVocals 负责
		if (ps.paused) return;
		if (FlxG.sound.music != null) FlxG.sound.music.play();
		if (ps.vocals != null) ps.vocals.play();
		if (ps.opponentVocals != null) ps.opponentVocals.play();
	}

	/** 原 PlayState.containsChinese（作用域分析：零遮蔽，0 处成员引用已限定）。 */
	public static function containsChinese(ps:PlayState, s:String):Bool
	{
		if (s == null || s == '') return false;
		for (i in 0...s.length)
		{
			var c:Int = s.charCodeAt(i);
			if (c >= 0x4E00 && c <= 0x9FFF) return true;
		}
		return false;
	}

	/** 原 PlayState.callOnScripts（作用域分析：零遮蔽，4 处成员引用已限定）。 */
	public static function callOnScripts(ps:PlayState, funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic
	{
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = PlayState._noExclusions;
		if(excludeValues == null) excludeValues = PlayState._noExcludeValues;

		var result:Dynamic = ps.callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = ps.callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	/** 原 PlayState.startCharacterPos（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function startCharacterPos(ps:PlayState, char:Character, ?gfCheck:Bool = false)
	{
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(ps.GF_X, ps.GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	/** 原 PlayState.spawnWindowFor（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function spawnWindowFor(ps:PlayState, target:CastNote):Float
	{
		// 【500 帧冲刺】密集谱出生窗口 2000ms→1100ms：同屏成员数（渲染+followStrum 双头）近似减半；
		// 音符改为约 1.1s 前出现在屏幕（墙略短、贴线更近），判定/计分零影响。
		var t:Float = (PlayState.densePerfMode ? 1100 : ps.spawnTime) * ps.playbackRate;
		if (ps.songSpeed < 1) t /= ps.songSpeed;
		if (target.multSpeed < 1) t /= target.multSpeed;
		return t;
	}

	/** 原 PlayState.resetRPC（作用域分析：零遮蔽，9 处成员引用已限定）。 */
	public static function resetRPC(ps:PlayState, ?cond:Bool = false)
	{
		#if desktop
		if (cond)
			DiscordClient.changePresence(ps.detailsText, PlayState.SONG.song + " (" + ps.storyDifficultyText + ")", ps.iconP2.getCharacter(), true, ps.songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(ps.detailsText, PlayState.SONG.song + " (" + ps.storyDifficultyText + ")", ps.iconP2.getCharacter());
		#end
	}

	/** 原 PlayState.clampGameplayTotals（作用域分析：零遮蔽，15 处成员引用已限定）。 */
	public static function clampGameplayTotals(ps:PlayState):Void
	{
		if (ps.totalNotes > 0 && ps.songHits > ps.totalNotes)
			ps.songHits = ps.totalNotes;
		if (ps.totalNotes > 0 && ps.totalPlayed > ps.totalNotes)
			ps.totalPlayed = ps.totalNotes;
		if (ps.totalNotes > 0 && ps.totalNotesHit > ps.totalNotes)
			ps.totalNotesHit = ps.totalNotes;
	}

	/** 原 PlayState.buildOppCountsLine（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function buildOppCountsLine(ps:PlayState):String
	{
		var parts:Array<String> = [];
		for (r in ps.ratingsData)
			if (ps.onlineOppRatings.exists(r.name) && ps.onlineOppRatings.get(r.name) > 0)
				parts.push(r.name + ':' + ps.onlineOppRatings.get(r.name));
		parts.push('miss:' + ps.onlineOppMisses);
		return parts.join(' ');
	}

	/** 原 PlayState.getLuaObject（作用域分析：零遮蔽，6 处成员引用已限定）。 */
	public static function getLuaObject(ps:PlayState, tag:String, text:Bool=true):FlxSprite
	{
		#if LUA_ALLOWED
		if(ps.modchartSprites.exists(tag)) return ps.modchartSprites.get(tag);
		if(text && ps.modchartTexts.exists(tag)) return ps.modchartTexts.get(tag);
		if(ps.variables.exists(tag)) return ps.variables.get(tag);
		#end
		return null;
	}

	/** 原 PlayState.startAndEnd（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function startAndEnd(ps:PlayState)
	{
		if(ps.endingSong)
			ps.endSong();
		else
			ps.startCountdown();
	}

	/** 原 PlayState.achievementEnd（作用域分析：零遮蔽，4 处成员引用已限定）。 */
	public static function achievementEnd(ps:PlayState):Void
	{
		ps.achievementObj = null;
		if(ps.endingSong && !ps.inCutscene) {
			ps.endSong();
		}
	}

	/** 原 PlayState.cancelMusicFadeTween（作用域分析：零遮蔽，0 处成员引用已限定）。 */
	public static function cancelMusicFadeTween()
	{
		if(FlxG.sound.music.fadeTween != null) {
			FlxG.sound.music.fadeTween.cancel();
		}
		FlxG.sound.music.fadeTween = null;
	}

	/** 原 PlayState.setOnScripts（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function setOnScripts(ps:PlayState, variable:String, arg:Dynamic, exclusions:Array<String> = null)
	{
		if(exclusions == null) exclusions = PlayState._noExclusions;
		ps.setOnLuas(variable, arg, exclusions);
		ps.setOnHScript(variable, arg, exclusions);
	}

	/** 原 PlayState.onAndroidBack（作用域分析：零遮蔽，1 处成员引用已限定）。 */
	public static function onAndroidBack(ps:PlayState):Bool
	{
		ps.androidBackQueued = true;
		return true;
	}

	/** 原 PlayState.update（作用域分析：零遮蔽，241 处成员引用已限定）。 */
	public static function update(ps:PlayState, elapsed:Float)
	{
		#if METEORIC_PROFILE
		backend.MeteoricProfile.begin();
		#end

		/*if (FlxG.keys.justPressed.NINE)
		{
			iconP1.swapOldIcon();
		}*/

		// 拆卸锁：endSong 结算拆卸后（转场/关闭回调窗口期）不再驱动本 State，
		// 否则会访问已销毁的人物/判定线（Null Object Reference）
		if (ps._visualsTorn)
			return;

		// 联机：网络收发 / 消息处理 / 时间同步 / 对手 HUD 刷新
		if (PlayState.isOnlineMode)
			ps.updateOnline(elapsed);

		ps.callOnScripts('onUpdate', [elapsed]);

		// 原生长条按压覆盖：每帧同步判定线位置
		if (ps.holdCoverHandler != null)
			ps.holdCoverHandler.syncPositions(ps.playerStrums, ps.opponentStrums);

		// 角色自愈：mod 脚本 / createInstance / 事件竞态可能把 dad/boyfriend/gf 置空
		// （blissful-erect 接箭头闪退现场）——按谱面默认配置逐个重建缺失角色，绝不闪退
		ps.ensureCharactersAlive();

		// 延迟 GC（一次）：进曲 0.5s 后回收已剥离的谱面 DOM/解析暂存（倒计时期间，无音符生成）
		if (ps._deferredGC)
		{
			ps._deferredGCTime += elapsed;
			if (ps._deferredGCTime >= 0.5)
			{
				ps._deferredGC = false;
				#if desktop
				openfl.system.System.gc();
				#end
			}
		}

		// NPS 滚动窗口：每满 1 秒把计数滚到显示值并清零，同时刷新 Score 栏
		ps._npsTimer += elapsed;
		if (ps._npsTimer >= 1)
		{
			ps.npsDisplay = ps._npsCount;
			ps._npsCount = 0;
			ps._npsTimer -= 1;
			if (ClientPrefs.data.showNPS && !ps.endingSong && ps.scoreTxt != null) ps.updateScore();
		}

		// ===== HUD 权威校验（每帧） =====
		// 1) hideHud 被 Mod/脚本临时改掉 → 立即恢复用户真实设置；
		// 2) healthBar/图标/分数等 visible 被任何代码（Lua/Hscript/遗留逻辑）直接改掉
		//    → 每帧强制拉回设置值。从根上杜绝“游玩中 UI 突然消失”。
		// 注意：此函数只在非暂停/非结算（persistentUpdate=true）时执行，
		// 不会干扰暂停界面、结算界面自身的显隐逻辑。
		ps.enforceHUD();

		// 自愈：paused 卡死但没有打开任何子界面（如 PauseSubState 构造中途异常、
		// Lua 拦截 onPause 后遗留）时解锁，避免“暂停界面显示不出来”却把游戏冻结住。
		if (ps.paused && ps.subState == null && !ps.isDead && !PlayState.chartingMode)
		{
			ps._pausedSelfHealFrames++;
			if (ps._pausedSelfHealFrames >= 3)
			{
				ps._pausedSelfHealFrames = 0;
				ps.paused = false;
			}
		}
		else ps._pausedSelfHealFrames = 0;

		// 镜头缓动。原实现把强度写死为 2.4（≈1.22s 才走完 95%），观感接近瞬移；
		// 现改用设置档位提供的强度（0.3s / 0.5s / 0.8s），公式形状与帧率无关性均保持不变。
		// 暂停/过场/外部接管（cameraSpeed=0）时写 0 → flixel 步长为 0，镜头钉住不动。
		FlxG.camera.followLerp = 0;
		if(!ps.inCutscene && !ps.paused) {
			FlxG.camera.followLerp = FlxMath.bound(elapsed * ps.cameraSmoothSpeed() * ps.cameraSpeed * ps.playbackRate / (FlxG.updateFramerate / 60), 0, 1);
		}

		// 防御：mod 脚本/事件/竞态可能把 boyfriend 置空（blissful-erect 接箭头闪退现场），
		// 待机块永不因角色缺失而崩
		if(!ps.startingSong && !ps.endingSong && ps.boyfriend != null && ps.boyfriend.getAnimationName().startsWith('idle')) {
			ps.boyfriendIdleTime += elapsed;
			if(ps.boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
				ps.boyfriendIdled = true;
			}
		} else {
			ps.boyfriendIdleTime = 0;
		}

		var healthLerp:Float = FlxMath.lerp(ps.smoothHealth, ps.health, FlxMath.bound(elapsed * 9 * ps.playbackRate, 0, 1));
		ps.smoothHealth = healthLerp;

		ps.meteoSuper_update(elapsed);

		// 快速重开回溯：时间倒流（箭头随 songPosition 回退而飞回）
		if (ps.rewinding)
		{
			ps.rewindElapsed += elapsed;
			if (ps.rewindElapsed >= ps.rewindDuration)
			{
				ps.rewinding = false;
				Conductor.setPosition(0);
				trace('[Rewind] FINISH, elapsed=' + ps.rewindElapsed);
				ps.finishRestart();
			}
			else
			{
				// 变速回溯：一开始快、越接近终点越慢（cubicOut）；
				// 终点 = 场上清空的位置（最早音符飞出出生窗口后），收尾正好落在最后几个箭头上
				var rewindProgress:Float = ps.rewindElapsed / ps.rewindDuration;
				Conductor.setPosition(FlxMath.lerp(ps.rewindFromPos, ps.rewindEndPos, FlxEase.cubeOut(rewindProgress)));

				// 回溯中：箭头退回到“出生窗口”之外后回收，场上只保留正在倒流的箭头
				var rewindWindow:Float = ps.spawnTime * ps.playbackRate;
				if (ps.songSpeed < 1) rewindWindow /= ps.songSpeed;
				var noteIdx:Int = ps.notes.members.length - 1;
				while (noteIdx >= 0)
				{
					var rewindNote:Note = ps.notes.members[noteIdx];
					if (rewindNote != null && rewindNote.alive)
					{
						var noteWindow:Float = rewindWindow;
						if (rewindNote.multSpeed < 1) noteWindow /= rewindNote.multSpeed;
						if (rewindNote.strumTime - Conductor.songPosition > noteWindow)
						{
							rewindNote.active = false;
							rewindNote.visible = false;
							ps.notes.invalidateNote(rewindNote);
						}
					}
					noteIdx--;
				}

				// 场上已没有可见箭头时提前结束回溯，不再空转浪费等待时间
				if (ps.notes.length == 0)
				{
					ps.rewinding = false;
					Conductor.setPosition(0);
					trace('[Rewind] FINISH (field empty), elapsed=' + ps.rewindElapsed);
					ps.finishRestart();
				}
			}
		}

		ps.setOnScripts('curDecStep', ps.curDecStep);
		ps.setOnScripts('curDecBeat', ps.curDecBeat);

		// 每帧刷新动态 PlayState 值（Psych 0.7.3 setSpecialObject 等价物）
		ps.setOnScripts('health', ps.health);
		ps.setOnScripts('endingSong', ps.endingSong);
		ps.setOnScripts('curBeat', ps.curBeat);
		ps.setOnScripts('isCameraOnForcedPos', ps.isCameraOnForcedPos);

		// HUD 每帧更新（图标跳动/跟随/阴影滚动/botplay 呼吸/可见性权威）全部收敛到 GameHUD
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseBegin('hud');
		#end
		if (ps.hud != null) ps.hud.update(elapsed);
		#if METEORIC_PROFILE
		backend.MeteoricProfile.phaseEnd('hud');
		#end

		if ((ps.controls.PAUSE || ps.androidBackQueued) && ps.startedCountdown && ps.canPause)
		{
			var ret:Dynamic = ps.callOnScripts('onPause', null, true);
			if(ret != FunkinLua.Function_Stop) {
				ps.openPauseMenu();
			}
		}
		ps.androidBackQueued = false;

		if (ps.controls.justPressed('debug_1') && !ps.endingSong && !ps.inCutscene)
			ps.openChartEditor();

		if (ps.controls.justPressed('debug_2') && !ps.endingSong && !ps.inCutscene)
			ps.openCharacterEditor();

		if (ps.startedCountdown && !ps.paused && !ps.rewinding)
			Conductor.advance(FlxG.elapsed * 1000 * ps.playbackRate);

		if (ps.startingSong)
		{
			if (ps.startedCountdown && Conductor.songPosition >= 0)
			{

				ps.startSong();
			}
			else if(!ps.startedCountdown)
				Conductor.setPosition(-Conductor.crochet * 5);
		}
		else if (!ps.paused && ps.updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			ps.songPercent = (curTime / ps.songLength);

			var songCalc:Float = (ps.songLength - curTime);
			if(ClientPrefs.data.timeBarType == '已过时间') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			if(ClientPrefs.data.timeBarType != '歌曲名称')
				ps.timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
		}

		// 歌曲收尾兜底：音乐 onComplete（空音频/流式音频可能永不触发）与"歌曲位置越过时长"
		// 双保险 —— 任意歌曲到达 max(音频长度, 谱面末尾) 都正常结算；正常运行下
		// onComplete 先触发并置 endingSong/finishingSong，本分支不会重复执行。
		if (!ps.endingSong && !ps.finishingSong && !ps.startingSong && !ps.paused && !ps.rewinding && !ps.inCutscene && ps.songLength > 0
			&& Conductor.songPosition >= ps.songLength)
		{
			ps.finishSong();
		}

		if (ps.camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(ps.defaultCamZoom, FlxG.camera.zoom, FlxMath.bound(1 - (elapsed * 3.125 * ps.camZoomingDecay * ps.playbackRate), 0, 1));
			ps.camHUD.zoom = FlxMath.lerp(1, ps.camHUD.zoom, FlxMath.bound(1 - (elapsed * 3.125 * ps.camZoomingDecay * ps.playbackRate), 0, 1));
		}

		// Watch calls removed for performance

		// RESET = Quick Game Over Screen（联机对局禁用重开，见 addOnlineHUD）
		if (!ClientPrefs.data.noReset && ps.controls.RESET && ps.canReset && !ps.inCutscene && ps.startedCountdown && !ps.endingSong && !PlayState.isOnlineMode)
		{
			ps.health = 0;
			trace("RESET = True");
		}
		ps.doDeathCheck();

		ps.noteSpawn();

		if (ps.generatedMusic)
		{
			if(!ps.inCutscene)
			{
				if(!ps.rewinding && !ps.cpuControlled && !ps.replayMode) {
					ps.keysCheck();
				} else {
					// 回放 v2：按录制时间注入按键（走正常判定路径），并处理长按子段
					if (ps.replayMode && ps.replayV2) ps.updateReplayInputs();
					// 【结算崩溃修复】曲终（finishSong→endSong 启动转场/拆卸）后该恢复块不得再跑：
					// 此帧结束前角色动画已被置空（curAnim=null → inlined getAnimationName NRE）。
					// 加 endingSong/finishingSong 守卫 + 动画非空校验（曲终帧自动游玩/回放路径崩溃修复）。
					var _bfAnim:Dynamic = ps.boyfriend != null ? ps.boyfriend.animation : null;
					if (!ps.endingSong && !ps.finishingSong && !ClientPrefs.data.hudOnly
						&& _bfAnim != null && _bfAnim.curAnim != null
						&& ps.boyfriend.getAnimationName().startsWith('sing') && !ps.boyfriend.getAnimationName().endsWith('miss')
						&& (ps.boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 / FlxG.sound.music.pitch) * ps.boyfriend.singDuration
							|| ps.boyfriend.isAnimationFinished())) {
						// 【视觉修复】原条件只靠 holdTimer 阈值：密集谱逐帧命中把 holdTimer 反复清零，
						// 空段/曲间 BF 会一直卡在最后一个 sing 姿态。补上「sing 动画已播完」即回 idle 的兜底
						// （isAnimationFinished 对 sparrow/atlas 角色都安全；Character 内部也已镜像阈值回 idle）。
						ps.boyfriend.dance();
						//boyfriend.animation.curAnim.finish();
					}
				}

				#if METEORIC_PROFILE
				backend.MeteoricProfile.phaseBegin('notes');
				#end
				if(ps.notes.length > 0)
				{
					if(ps.startedCountdown)
					{
						var fakeCrochet:Float = (60 / PlayState.SONG.bpm) * 1000;
						var songPos:Float = Conductor.songPosition;
						// 自动游玩命中提前量：实测本帧音频前进量的一半（帧轮询下偏差最小），
						// 上限 20ms×倍速，防止卡顿帧后提前量过大导致提前命中掉出 Sick 窗口（45ms）
						var songDelta:Float = songPos - ps.lastBotSongPos;
						ps.lastBotSongPos = songPos;
						var botAdvance:Float = Math.min(Math.max(songDelta, 1000 / FlxG.drawFramerate) * 0.5, 20 * ps.playbackRate);
						// 【性能】手动循环替代 forEachAlive 闭包：免去每帧闭包分配与每音符一次虚调用；
						// 语义与 forEachAlive 完全一致（先取后 ++、循环条件实时读长度、移除节点不回溯）
						var noteSpeed:Float = ps.songSpeed / ps.playbackRate;
						var killWindow:Float = ps.cpuControlled ? ClientPrefs.data.botplayKillWindow : ps.noteKillOffset;
						var ni:Int = 0;
						while (ni < ps.notes.members.length)
						{
							var daNote:Note = ps.notes.members[ni++];
							if (daNote == null || !daNote.exists || !daNote.alive) continue;

							// 【性能】不可见音符（重叠隐藏等）：跳过跟随/裁剪/判定——
							// 与 hideOverlapped 选项"渲染裁剪，不参与判定"语义一致；仅保留超时回收
							if (!daNote.visible)
							{
								if (!ps.rewinding && songPos - daNote.strumTime > killWindow)
									ps.notes.invalidateNote(daNote);
								continue;
							}

							var strumGroup:FlxTypedGroup<StrumNote> = ps.playerStrums;
							if(!daNote.mustPress) strumGroup = ps.opponentStrums;

							// 联机真双人：两侧谱面全部展示（自己打自己半边、对方打对半边）；
							// 对侧音符不再隐藏，由对端 HIT/MISS 按 chartSeq 消费（见 applyOppHit/applyOppMiss）。

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							if (strum == null)
							{
								// 防御 + 现场诊断：strum 缺失时跳过本音符（不整局崩溃），并打印现场
								trace('[STRUM NULL] seq=' + daNote.chartSeq + ' d=' + daNote.noteData
									+ ' must=' + daNote.mustPress + ' pLen=' + ps.playerStrums.length
									+ ' oLen=' + ps.opponentStrums.length + ' pos=' + Std.int(Conductor.songPosition)
									+ ' step=' + ps.curStep + ' gen=' + ps.generatedMusic + ' keepping=' + ps.keepStrumsOnRestart);
								continue;
							}
							daNote.followStrumNote(strum, fakeCrochet, noteSpeed);

							// 视觉副本（blockHit+ignoreNote）快捷路径：只跟随/长条裁剪/超时消亡，不做判定（大优化）
							if (daNote.blockHit && daNote.ignoreNote)
							{
								// 长条副本同样需要判定键裁剪（否则滑过判定线后仍延伸不消失）
								if (daNote.isSustainNote && strum != null && strum.sustainReduce)
								{
									daNote.wasGoodHit = true; // 副本纯视觉：满足裁剪条件
									daNote.clipToStrumNote(strum);
								}
								if (!ps.rewinding && songPos - daNote.strumTime > killWindow)
									ps.notes.invalidateNote(daNote);
								continue;
							}

							if(daNote.mustPress)
							{
								if(!ps.rewinding && (ps.cpuControlled || ps.replayMode) && !daNote.blockHit && !daNote.wasGoodHit
									&& (ps.replayMode || !daNote.botQueued)) // 自动游玩命中：排期与 alive-loop 双路互斥（botQueued 防重）
								{
									var shouldHit:Bool = false;
									if (ps.replayMode && !ps.replayV2)
									{
										// 旧版回放（v1，无按键流）：按录制命中记录合成命中，
										// 未记录的箭头自然滑过并触发 miss，与原局表现一致。
										// 注意：v2（含按键流）不走这里——自动命中会在 strumTime 一到就抢先把
										// 音符打掉，之后注入的真实按键（晚按）找不到可命中音符会变成 ghost miss，
										// 导致回放 Miss 数膨胀（2 → 10）。v2 完全靠 updateReplayInputs 按键注入，
										// 同时间同按键必然命中同一音符，与实玩 1:1 复刻。
										if (ps.replayHitSeqs != null && daNote.chartSeq >= 0 && ps.replayHitSeqs.exists(daNote.chartSeq)
											&& !daNote.tooLate && songPos + botAdvance >= daNote.strumTime)
											shouldHit = true;
									}
									else if (!ps.replayMode && ((ps.botplayPlan != null && !daNote.tooLate && songPos + botAdvance >= daNote.strumTime)
										|| (ps.botplayPlan == null && daNote.canBeHit && (daNote.isSustainNote || songPos + botAdvance >= daNote.strumTime))))
										shouldHit = true;

									if (shouldHit)
									{
										// 本帧命中的音符先收集，循环结束后统一批处理
										// （堆叠命中时合并音效/粒子/动画/评分等副作用，避免单帧爆发卡顿）
										daNote.botQueued = true; // 免杀保护：本帧不再被超时击杀
										daNote.botSched = false;
										ps.botHitQueue.push(daNote);
									}
								}
							}
							// 对手箭头：到达判定线即触发命中（旧条件是 wasGoodHit——对手音符从未被置位，
							// 导致对手箭头永远不会被 opponentNoteHit 回收，直接飞过判定线）
							// 联机：跳过该自动化命中（装饰音符，不闪烁/不触发动画），见上方 visible 屏蔽
							else if (!ps.rewinding && !daNote.hitByOpponent && !daNote.ignoreNote
								&& !daNote.isSustainNote && songPos - daNote.strumTime >= 0 && !PlayState.isOnlineMode)
							{
								ps.opponentNoteHit(daNote);
								// 对手簇视觉副本同步销毁（与玩家侧 processBotHits 一致）：
								// 副本只靠回收窗击杀会飞过判定线，巨堆叠段肉眼即"整簇飞走"。
								// 【500 帧补丁】原实现每命中全表反向扫描（O(命中×成员)）→ 改为登记 chartSeq，
								// 本帧主循环结束后统一一次 O(成员) 批扫（语义等价：同一批命中同帧销毁）。
								if (daNote.chartSeq >= 0)
								{
									if (ps._oppHitSeqs == null) ps._oppHitSeqs = new Map<Int, Bool>();
									ps._oppHitSeqs.set(daNote.chartSeq, true);
								}
							}

							if(daNote.isSustainNote && strum != null && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							// （已入自动命中队列的音符本帧免杀：逾期 1 帧由 processBotHits 记账，杜绝"入队后被击杀丢弃"）
							// 自动游玩：未命中者极小窗口即回收（柱子顶端贴判定线裁齐，不残留 +52ms 残影）
							if (!ps.rewinding && !daNote.botQueued && !(ps.cpuControlled && daNote.botSched) && songPos - daNote.strumTime > killWindow)
							{
								if (daNote.mustPress && !ps.cpuControlled &&!daNote.ignoreNote && !ps.endingSong && (daNote.tooLate || !daNote.wasGoodHit)
								&& (ClientPrefs.data.noteJudgment != 'KE 判定' || !daNote.isSustainNote))
									ps.noteMiss(daNote);

								daNote.active = false;
								daNote.visible = false;

								ps.notes.invalidateNote(daNote);
							}
						}
					}
					else
					{
						// 【性能】倒计时分支同样手动循环（与 forEachAlive 语义一致）
						var ni2:Int = 0;
						while (ni2 < ps.notes.members.length)
						{
							var daNote:Note = ps.notes.members[ni2++];
							if (daNote != null && daNote.exists && daNote.alive)
							{
								daNote.canBeHit = false;
								daNote.wasGoodHit = false;
							}
						}
					}
					// 【500 帧补丁】对手命中兄弟视觉副本：本帧一次批扫（见登记处注释）
					if (ps._oppHitSeqs != null)
					{
						var omi:Int = ps.notes.members.length - 1;
						while (omi >= 0)
						{
							var osib:Note = ps.notes.members[omi];
							if (osib != null && osib.blockHit && osib.ignoreNote && osib.chartSeq >= 0
								&& ps._oppHitSeqs.exists(osib.chartSeq))
								ps.notes.invalidateNote(osib);
							omi--;
						}
						ps._oppHitSeqs = null;
					}
					ps.processBotHits();
				#if METEORIC_PROFILE
				backend.MeteoricProfile.phaseEnd('notes');
				#end
				}

				// 回放（旧版）：按录制时间触发空按（无对应音符的按键），与原局按键时机一致。
				// 回放 v2 的空按由按键注入自然复现，这里跳过避免重复 Miss。
				if (ps.replayMode && !ps.replayV2 && !ps.rewinding && !ps.paused && !ps.endingSong && ps.startedCountdown)
				{
					while (ps.replayPressPtr < ps.replayPressMisses.length && Conductor.songPosition >= ps.replayPressMisses[ps.replayPressPtr].t)
					{
						var pm:ReplayEvent = ps.replayPressMisses[ps.replayPressPtr++];
						ps.noteMissPress(pm.d);
					}
				}
			}
			ps.checkEventNote();
		}

		#if debug
		if(!ps.endingSong && !ps.startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				ps.KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				ps.setSongTime(Conductor.songPosition + 10000);
				ps.clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		ps.setOnScripts('cameraX', ps.camFollow.x);
		ps.setOnScripts('cameraY', ps.camFollow.y);
		ps.setOnScripts('botPlay', ps.cpuControlled);
		ps.callOnScripts('onUpdatePost', [elapsed]);

		#if METEORIC_PROFILE
		backend.MeteoricProfile.end('PlayState.update');
		#end
	}

	/** 原 PlayState.closeSubState（作用域分析：零遮蔽，24 处成员引用已限定）。 */
	public static function closeSubState(ps:PlayState)
	{
		ps.stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (ps.paused)
		{
			if (FlxG.sound.music != null && !ps.startingSong)
			{
				ps.resyncVocals();
			}

			if (ps.startTimer != null && !ps.startTimer.finished) ps.startTimer.active = true;
			if (ps.finishTimer != null && !ps.finishTimer.finished) ps.finishTimer.active = true;
			if (ps.songSpeedTween != null) ps.songSpeedTween.active = true;

			var chars:Array<Character> = [ps.boyfriend, ps.gf, ps.dad];
			for (char in chars)
				if(char != null && char.colorTween != null)
					char.colorTween.active = true;

			#if LUA_ALLOWED
			for (tween in ps.modchartTweens) tween.active = true;
			for (timer in ps.modchartTimers) timer.active = true;
			#end

			// 联机：仅「主动恢复」通知对方解除暂停；远程 RESUME 恢复时不再回发
			if (PlayState.isOnlineMode && !ps.onlineRemoteResume) Multiplayer.send('RESUME');

			ps.paused = false;
			ps.callOnScripts('onResume');
			ps.resetRPC(ps.startTimer != null && ps.startTimer.finished);

			#if mobile
			// 恢复游戏触控板
			if (objects.MobileControls.instance != null)
			{
				objects.MobileControls.instance.visible = true;
			}
			#end
		}

		ps.meteoSuper_closeSubState();
	}

	/** 原 PlayState.openSubState（作用域分析：零遮蔽，17 处成员引用已限定）。 */
	public static function openSubState(ps:PlayState, SubState:FlxSubState)
	{
		ps.stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (ps.paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				ps.vocals.pause();
				ps.opponentVocals.pause();
			}

			if (ps.startTimer != null && !ps.startTimer.finished) ps.startTimer.active = false;
			if (ps.finishTimer != null && !ps.finishTimer.finished) ps.finishTimer.active = false;
			if (ps.songSpeedTween != null) ps.songSpeedTween.active = false;

			var chars:Array<Character> = [ps.boyfriend, ps.gf, ps.dad];
			for (char in chars)
				if(char != null && char.colorTween != null)
					char.colorTween.active = false;

			#if LUA_ALLOWED
			for (tween in ps.modchartTweens) tween.active = false;
			for (timer in ps.modchartTimers) timer.active = false;
			#end
		}

		ps.meteoSuper_openSubState(SubState);
	}

	/** 原 PlayState.onFocusLost（作用域分析：零遮蔽，11 处成员引用已限定）。 */
	public static function onFocusLost(ps:PlayState):Void
	{
		#if desktop
		if (ps.health > 0 && !ps.paused) DiscordClient.changePresence(ps.detailsPausedText, PlayState.SONG.song + " (" + ps.storyDifficultyText + ")", ps.iconP2.getCharacter());
		#end

		#if mobile
		// 退到后台时立即暂停，避免“看似暂停实际还在运行”
		if (ps.startedCountdown && !ps.endingSong && !ps.paused && ps.canPause)
			ps.openPauseMenu();
		#end

		ps.meteoSuper_onFocusLost();
	}

	/** 原 PlayState.onFocus（作用域分析：零遮蔽，4 处成员引用已限定）。 */
	public static function onFocus(ps:PlayState):Void
	{
		if (ps.health > 0 && !ps.paused) ps.resetRPC(Conductor.songPosition > 0.0);
		// Meteoric：从后台回到前台时恢复被冻结的音频（游戏仍停留在暂停菜单，等玩家手动返回）
		#if mobile
		ps.restoreBackgroundAudio();
		#end
		ps.meteoSuper_onFocus();
	}
}
