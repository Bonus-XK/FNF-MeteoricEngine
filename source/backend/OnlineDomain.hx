package backend;

import flixel.FlxG;
import backend.Multiplayer;
import backend.MusicBeatState;
import states.OnlineMenuState;
import states.PlayState;
import backend.Conductor;
import objects.Character;
import objects.Note;
import substates.ResultsSubState;

/** 联机域（C4 首批迁出）。PlayState 保留同签名转发入口。 */
@:access(states.PlayState)
class OnlineDomain
{
	/** 断开并回联机主菜单（原 PlayState.onlineGoBackToLobby）。 */
	public static function onlineGoBackToLobby(ps:PlayState, reason:String):Void
	{
		Multiplayer.stop();
		PlayState.isOnlineMode = false;
		OnlineMenuState.notifyReason = reason;
		try { FlxG.sound.music.stop(); ps.vocals.stop(); ps.opponentVocals.stop(); } catch (e:Dynamic) {}
		MusicBeatState.switchState(new OnlineMenuState());
	}

	/** 保持连接返回房间大厅（原 PlayState.onlineBackToRoomLobby）。 */
	public static function onlineBackToRoomLobby(ps:PlayState, reason:String):Void
	{
		PlayState.isOnlineMode = false;
		OnlineMenuState.notifyReason = reason;
		OnlineMenuState.openInLobby = true;
		try { FlxG.sound.music.stop(); ps.vocals.stop(); ps.opponentVocals.stop(); } catch (e:Dynamic) {}
		MusicBeatState.switchState(new OnlineMenuState());
	}

	/** 原 PlayState.processOnlineMessages（作用域分析：零遮蔽，31 处成员引用已限定）。 */
	public static function processOnlineMessages(ps:PlayState):Void
	{
		for (m in Multiplayer.pollMessages())
		{
			var parts:Array<String> = m.split('|');
			var cmd:String = parts[0];
			switch (cmd)
			{
				case 'ACK':
					if (PlayState.onlineIsHost)
					{
						PlayState.onlineHoldCountdown = false;
						Multiplayer.send('GO');
						ps.startCountdown();
					}
				case 'GO':
					if (!PlayState.onlineIsHost)
					{
						PlayState.onlineHoldCountdown = false;
						ps.startCountdown();
					}
				case 'TIME':
					if (!PlayState.onlineIsHost && ps.startedCountdown && !ps.paused && !ps.endingSong && parts.length >= 2)
					{
						var t:Float = Std.parseFloat(parts[1]);
						if (!Math.isNaN(t) && Math.abs(Conductor.songPosition - t) > 45)
							ps.setSongTime(t);
					}
				case 'HIT':
					if (parts.length >= 2)
					{
						var f:Array<String> = parts[1].split('~');
						if (f.length >= 5)
						{
							var seq:Int = f.length >= 6 ? Std.parseInt(f[5]) : -1;
							ps.applyOppHit(Std.parseInt(f[0]), f[1], Std.parseInt(f[2]), Std.parseFloat(f[3]), Std.parseInt(f[4]), seq);
						}
					}
				case 'MISS':
					if (parts.length >= 2)
					{
						var f:Array<String> = parts[1].split('~');
						if (f.length >= 4)
						{
							var seq:Int = f.length >= 5 ? Std.parseInt(f[4]) : -1;
							ps.applyOppMiss(Std.parseInt(f[0]), Std.parseInt(f[1]), Std.parseFloat(f[2]), Std.parseInt(f[3]), seq);
						}
					}
				case 'PRESS':
					if (parts.length >= 2) ps.flashOppStrums(Std.parseInt(parts[1]), 'press', false);
				case 'RELEASE':
					if (parts.length >= 2) ps.flashOppStrums(Std.parseInt(parts[1]), 'static', false);
				case 'PAUSE':
					if (!ps.paused && !ps.endingSong && ps.startedCountdown && ps.subState == null)
						ps.openPauseMenu(true); // 远程暂停：不再回发 PAUSE
				case 'RESUME':
					if (ps.paused && ps.subState != null)
					{
						ps.onlineRemoteResume = true;
						ps.closeSubState();
						ps.onlineRemoteResume = false;
					}
				case 'QUIT':
					// 对方主动退出对局：同样保持连接回房间大厅（可再来一局）
					ps.onlineBackToRoomLobby(parts.length > 1 ? parts[1] : '对方已退出对局');
				case 'DISCONNECTED':
					ps.onlineGoBackToLobby(parts.length > 1 ? parts[1] : '连接已断开');
				case 'FINISH':
					ps.onlineOppFinished = true;
					if (parts.length >= 2)
					{
						var f:Array<String> = parts[1].split('~');
						if (f.length >= 8)
							ps.onlineOppStats = [f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7]];
					}
					if (ps.onlineFinished)
						ps.openOnlineResults();
			}
		}
	}

	/** 原 PlayState.onlinePauseNetworkTick（作用域分析：零遮蔽，8 处成员引用已限定）。 */
	public static function onlinePauseNetworkTick(ps:PlayState):Void
	{
		if (!PlayState.isOnlineMode) return;
		Multiplayer.update();
		var leftover:Array<String> = [];
		for (m in Multiplayer.pollMessages())
		{
			var parts:Array<String> = m.split('|');
			switch (parts[0])
			{
				case 'RESUME':
					if (ps.paused && ps.subState != null)
					{
						ps.onlineRemoteResume = true;
						ps.closeSubState();
						ps.onlineRemoteResume = false;
					}
				case 'QUIT':
					// 对方主动退出对局：保持连接回房间大厅（可再来一局）
					ps.onlineBackToRoomLobby(parts.length > 1 ? parts[1] : '对方已退出对局');
					return;
				case 'DISCONNECTED':
					ps.onlineGoBackToLobby(parts.length > 1 ? parts[1] : '连接已断开');
					return;
				default:
					// 暂停期间暂存游戏事件；PAUSE 丢弃（恢复后不得重放对方的旧暂停）
					if (parts[0] != 'PAUSE') leftover.push(m);
			}
		}
		Multiplayer.reinjectMany(leftover);
	}

	/** 原 PlayState.updateOnline（作用域分析：零遮蔽，14 处成员引用已限定）。 */
	public static function updateOnline(ps:PlayState, elapsed:Float):Void
	{
		Multiplayer.update();
		ps.processOnlineMessages();

		// 握手超时保护：15 秒内未收到对方就绪/GO 信号则回大厅
		if (PlayState.onlineHoldCountdown)
		{
			ps.onlineWaitTimer += elapsed;
			if (ps.onlineWaitTimer > 15)
			{
				ps.onlineGoBackToLobby('连接超时：对方未就绪');
				return;
			}
		}
		else
			ps.onlineWaitTimer = 0;

		if (PlayState.onlineIsHost && ps.startedCountdown && !ps.paused && !ps.endingSong)
		{
			ps.onlineTimeSyncTimer += elapsed;
			if (ps.onlineTimeSyncTimer >= 0.5)
			{
				ps.onlineTimeSyncTimer = 0;
				Multiplayer.send('TIME|' + Conductor.songPosition);
			}
		}
		ps.refreshOppHud();
	}

	/** 原 PlayState.onlineResultsNetworkTick（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function onlineResultsNetworkTick(ps:PlayState):Void
	{
		if (!PlayState.isOnlineMode) return;
		Multiplayer.update();
		for (m in Multiplayer.pollMessages())
		{
			var parts:Array<String> = m.split('|');
			switch (parts[0])
			{
				case 'FINISH':
					ps.onlineOppFinished = true;
					if (parts.length >= 2)
					{
						var f:Array<String> = parts[1].split('~');
						if (f.length >= 8)
							ps.onlineOppStats = [f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7]];
					}
				case 'QUIT':
					// 对方主动退出对局：保持连接回房间大厅（可再来一局）
					ps.onlineBackToRoomLobby(parts.length > 1 ? parts[1] : '对方已退出对局');
					return;
				case 'DISCONNECTED':
					ps.onlineGoBackToLobby(parts.length > 1 ? parts[1] : '连接已断开');
					return;
				default:
			}
		}
	}

	/** 原 PlayState.playOnlineOppSing（作用域分析：零遮蔽，10 处成员引用已限定）。 */
	public static function playOnlineOppSing(ps:PlayState, data:Int, note:Note):Void
	{
		if (note != null && note.noAnimation) return;
		var char:Character = ps.dad;
		if (note != null)
		{
			if (note.noteType == 'Hey!' && char != null && char.animOffsets.exists('hey'))
			{
				char.playAnim('hey', true);
				char.specialAnim = true;
				char.heyTimer = 0.6;
				return;
			}
			if (note.gfNote) char = ps.gf;
		}
		var altAnim:String = note != null ? note.animSuffix : '';
		if (PlayState.SONG.notes[ps.curSection] != null)
		{
			if (PlayState.SONG.notes[ps.curSection].altAnim && !PlayState.SONG.notes[ps.curSection].gfSection)
				altAnim = '-alt';
		}
		if (char != null)
		{
			char.playAnim(ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length - 1, data)))] + altAnim, true);
			char.holdTimer = 0;
		}
	}

	/** 原 PlayState.onlineFinishAndShowResults（作用域分析：零遮蔽，25 处成员引用已限定）。 */
	public static function onlineFinishAndShowResults(ps:PlayState, died:Bool):Void
	{
		if (ps.onlineFinished && ps.subState != null) return;
		if (!ps.onlineFinished)
		{
			ps.onlineFinished = true;
			var acc:Float = Math.isNaN(ps.ratingPercent) ? 0 : ps.ratingPercent;
			var counts:String = ps.buildRatingCountsCsv();
			ps.onlineMyStats = [ps.songScore, ps.songHits, ps.songMisses, ps.totalNotesHit, ps.totalPlayed, ps.maxCombo, acc, counts];
			Multiplayer.send('FINISH|' + ps.songScore + '~' + ps.songHits + '~' + ps.songMisses + '~' + ps.totalNotesHit
				+ '~' + ps.totalPlayed + '~' + ps.maxCombo + '~' + acc + '~' + counts);
		}
		if (died)
		{
			try { FlxG.sound.music.stop(); ps.vocals.stop(); ps.opponentVocals.stop(); } catch (e:Dynamic) {}
			ps.persistentUpdate = false;
			ps.persistentDraw = false;
		}
		ps.openOnlineResults();
	}

	/** 原 PlayState.openOnlineResults（作用域分析：零遮蔽，5 处成员引用已限定）。 */
	public static function openOnlineResults(ps:PlayState):Void
	{
		if (ps.subState != null) return;
		ps.persistentUpdate = false;
		// 普通结算界面（联机下自动渲染为双栏对比版）：关闭（继续/ESC）后保持连接返回房间大厅
		var onlineResults:ResultsSubState = new ResultsSubState();
		onlineResults.closeCallback = function() {
			ps.persistentUpdate = true;
			ps.onlineBackToRoomLobby('对局结束，返回大厅');
		};
		ps.openSubState(onlineResults);
	}
}
