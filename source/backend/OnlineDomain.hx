package backend;

import flixel.FlxG;
import backend.Multiplayer;
import backend.MusicBeatState;
import states.OnlineMenuState;
import states.PlayState;
import backend.Conductor;

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
}
