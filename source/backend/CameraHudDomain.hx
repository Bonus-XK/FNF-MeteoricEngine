package backend;

import flixel.FlxG;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import backend.ClientPrefs;
import backend.Conductor;
import backend.Paths;
import backend.Song;
import states.PlayState;

/** 相机与 HUD 域（C3 首批迁出）。
 *  迁出策略：函数体迁到本类；PlayState 保留**同签名转发入口**，全仓 `PlayState.*` 调用点零改动。
 *  本批按用户裁定 A 只迁出 6 个**零冲突**函数（46 行）：它们引用的字段名不与本函数内局部变量/参数同名，
 *  故可安全加 `ps.` 前缀；其余 17 个函数（809 行）存在大量同名遮蔽（如 cameraSmoothSpeed 61 依赖/59 遮蔽），
 *  机械改写会静默改坏，须先有作用域分析工具 —— 见 PLAYSTATE-SPLIT-PLAN.md 与 evidence/24。
 *  可见性说明：原 fullComboUpdate / getRatingModByName 为 private，跨模块调用在本类放宽为 public。 */
@:access(states.PlayState)
class CameraHudDomain
{
	/** 全连段位文本（原 PlayState.fullComboUpdate）。 */
	public static function fullComboUpdate(ps:PlayState):Void
	{
		if(ps.songMisses < 1)
		{
			ps.ratingFC = 'FC';
		}else if (ps.songMisses < 10){
			ps.ratingFC = 'SDCB';
		}else{
			ps.ratingFC = 'Clear';
		}
	}

	/** tutorial 开场镜头缓动（原 PlayState.tweenCamIn）。**公式与时长未改动**。 */
	public static function tweenCamIn(ps:PlayState):Void
	{
		if (Paths.formatToSongPath(PlayState.SONG.song) == 'tutorial' && ps.cameraTwn == null && FlxG.camera.zoom != 1.3) {
			ps.cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					ps.cameraTwn = null;
				}
			});
		}
	}

	/** 重置某个 HUD 元素偏移（原 PlayState.hudResetElement）。 */
	public static function hudResetElement(ps:PlayState, id:String):Void
	{
		try { ClientPrefs.data.hudLayout.set(id, [0, 0]); } catch (e:Dynamic) {}
		ps.repositionHUD();
	}

	/** 按名字取判定修正系数（原 PlayState.getRatingModByName）。 */
	public static function getRatingModByName(ps:PlayState, name:String):Float
	{
		for (r in ps.ratingsData)
			if (r.name == name) return r.ratingMod;
		return 1;
	}

	/** 每帧 HUD 可见性权威（原 PlayState.enforceHUD）。 */
	public static function enforceHUD(ps:PlayState):Void
	{
		// 已收敛到 GameHUD.enforce()（每帧可见性权威）
		if (ps.hud != null) ps.hud.enforce();
	}

	/** 重载血条配色（原 PlayState.reloadHealthBarColors）。 */
	public static function reloadHealthBarColors(ps:PlayState):Void
	{
		if (ps.hud != null) ps.hud.reloadHealthBarColors();
	}
}
