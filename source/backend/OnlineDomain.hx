package backend;

import flixel.FlxG;
import backend.Multiplayer;
import backend.MusicBeatState;
import states.OnlineMenuState;
import states.PlayState;

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
}
