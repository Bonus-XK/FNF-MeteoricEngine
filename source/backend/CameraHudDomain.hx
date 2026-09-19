package backend;

import flixel.FlxG;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import backend.ClientPrefs;
import backend.Conductor;
import backend.Paths;
import backend.Song;
import states.PlayState;
import states.PlayState.GameHUD;
import objects.Note;
import objects.StrumNote;

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

	/** 原 PlayState.repositionHUD（作用域分析：零遮蔽，51 处成员引用已限定）。 */
	public static function repositionHUD(ps:PlayState)
	{
		if (ps.strumLineNotes == null) return;

		// 音符 / Phigros 判定线
		var noteOff:Array<Float> = ps.hudGetOffset('note');
		var strumLineX:Float = ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X;
		var strumLineY:Float = (ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50);
		for (i in 0...ps.strumLineNotes.members.length)
		{
			var strum:StrumNote = ps.strumLineNotes.members[i];
			var px:Float = strumLineX + (i * Note.swagWidth) + noteOff[0];
			if (i < 4 && ClientPrefs.data.middleScroll)
			{
				px += 310;
				if (i > 1) px += FlxG.width / 2 + 25;
			}
			strum.x = px;
			strum.y = strumLineY + noteOff[1];
		}
		// 时间条（含时间文字、Autoplay 提示）
		if (ps.timeBar != null)
		{
			var timeOff:Array<Float> = ps.hudGetOffset('timeBar');
			var tbY:Float = 19;
			if (ClientPrefs.data.downScroll) tbY = FlxG.height - 44 - 25;
			ps.timeBar.y = tbY + timeOff[1];
			ps.timeBar.screenCenter(X);
			ps.timeBar.x += timeOff[0];

			if (ps.timeBarOverlay != null) { ps.timeBarOverlay.x = ps.timeBar.x; ps.timeBarOverlay.y = ps.timeBar.y; }
			if (ps.timeTxt != null)
			{
				var txtBase:Float = 25 + (ClientPrefs.data.timeBarType == '歌曲名称' ? 3 : 0);
				ps.timeTxt.x = PlayState.STRUM_X + (FlxG.width / 2) - 248 + timeOff[0];
				ps.timeTxt.y = ps.timeBar.y + txtBase;
				if (ClientPrefs.data.downScroll) ps.timeTxt.y = FlxG.height - 44 + timeOff[1];
			}
			if (ps.botplayTxt != null)
			{
				ps.botplayTxt.y = ps.timeBar.y + 55;
				if (ClientPrefs.data.downScroll) ps.botplayTxt.y = ps.timeBar.y - 78;
			}
		}

		// 血量条（含图标、阴影）
		if (ps.healthBar != null)
		{
			var hpOff:Array<Float> = ps.hudGetOffset('healthBar');
			var hbY:Float = FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11) + hpOff[1];
			ps.healthBar.y = hbY;
			ps.healthBar.screenCenter(X);
			ps.healthBar.x += hpOff[0];

			if (ps.healthBarOverlay != null) { ps.healthBarOverlay.x = ps.healthBar.x; ps.healthBarOverlay.y = ps.healthBar.y; }
			// 图标强绑定血量条（y 跟随，x 由 update 按 barCenter 计算）
			if (ps.iconP1 != null) ps.iconP1.y = ps.healthBar.y - 75;
			if (ps.iconP2 != null) ps.iconP2.y = ps.healthBar.y - 75;
		}

		// 计分文字：以默认血量条位置为基准，与血量条当前偏移解耦
		var defaultHpY:Float = FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11);
		var scoreY:Float = ClientPrefs.data.downScroll ? 5 : defaultHpY + 55;
		var scoreOff:Array<Float> = ps.hudGetOffset('score');
		if (ps.scoreTxt != null)
		{
			ps.scoreTxt.x = scoreOff[0];
			ps.scoreTxt.y = scoreY + scoreOff[1];
		}

		// 左下角水印：独立定位
		var wmOff:Array<Float> = ps.hudGetOffset('watermark');
		if (ps.songTxt != null)
		{
			ps.songTxt.x = 12 + wmOff[0];
			ps.songTxt.y = scoreY + wmOff[1];
		}

		// 判定计数侧边栏：位置由 GameHUD.updateJudgementTxt 每帧管理（openfl TextField）
	}
}
