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
import psychlua.FunkinLua;
import backend.CoolUtil;
import flixel.text.FlxText.FlxTextBorderStyle;
import backend.Rating;

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

	/** 原 PlayState.generateStaticArrows（作用域分析：零遮蔽，9 处成员引用已限定）。 */
	public static function generateStaticArrows(ps:PlayState, player:Int):Void
	{
		var hudNoteOff:Array<Float> = ps.hudGetOffset('note');
		var strumLineX:Float = ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X;
		var strumLineY:Float = (ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50);
		strumLineX += hudNoteOff[0];
		strumLineY += hudNoteOff[1];
		for (i in 0...4)
		{
			// FlxG.log.add(i);
			var targetAlpha:Float = 1;
			if (player < 1)
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
				// 联机：对方箭头 = 单机同款对手段（左侧），强制可见（不受“显示对方箭头”设置影响）
				if (PlayState.isOnlineMode) targetAlpha = 1;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;
			if (!PlayState.isStoryMode && !ps.skipArrowStartTween)
			{
				//babyArrow.y -= 10;
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (player == 1)
				ps.playerStrums.add(babyArrow);
			else
			{
				if(ClientPrefs.data.middleScroll)
				{
					babyArrow.x += 310;
					if(i > 1) { //Up and Right
						babyArrow.x += FlxG.width / 2 + 25;
					}
				}
				ps.opponentStrums.add(babyArrow);
			}

			ps.strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();
		}
	}

	/** 原 PlayState.RecalculateRating（作用域分析：零遮蔽，31 处成员引用已限定）。 */
	public static function RecalculateRating(ps:PlayState, badHit:Bool = false)
	{
		ps.setOnScripts('score', ps.songScore);
		ps.setOnScripts('misses', ps.songMisses);
		ps.setOnScripts('hits', ps.songHits);
		ps.setOnScripts('combo', ps.combo);

		var ret:Dynamic = ps.callOnScripts('onRecalculateRating', null, true);
		if(ret != FunkinLua.Function_Stop)
		{
			ps.ratingName = '?';
			if(ps.totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ps.ratingPercent = Math.min(1, Math.max(0, ps.totalNotesHit / ps.totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ps.ratingName = PlayState.ratingStuff[PlayState.ratingStuff.length-1][0]; //Uses last string
				if(ps.ratingPercent < 1)
					for (i in 0...PlayState.ratingStuff.length-1)
						if(ps.ratingPercent < PlayState.ratingStuff[i][1])
						{
							ps.ratingName = PlayState.ratingStuff[i][0];
							break;
						}
			}
			ps.fullComboFunction();
		}
		ps.updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce -Ghost
		ps.setOnScripts('rating', ps.ratingPercent);
		ps.setOnScripts('ratingName', ps.ratingName);
		ps.setOnScripts('ratingFC', ps.ratingFC);
	}

	/** 原 PlayState.updateScore（作用域分析：零遮蔽，11 处成员引用已限定）。 */
	public static function updateScore(ps:PlayState, miss:Bool = false)
	{
		if(ps.totalPlayed != 0)
		{
			var percent:Float = CoolUtil.floorDecimal(ps.ratingPercent * 100, 2);
		}

		ps.scoreTxt.text = ps.buildScoreText();

		// 字体：文本含中文 → 自动用 future（含中文字形）；否则用设置里的字体
		var fontPath:String;
		if (ps.containsChinese(ps.scoreTxt.text))
			fontPath = Paths.font('future.ttf');
		else if (ClientPrefs.data.scoreTxtFont == 'Bahnschrift')
			fontPath = Paths.font('bahnschrift.ttf');
		else
			fontPath = Paths.font('vcr.ttf');

		var txtColor:FlxColor = FlxColor.WHITE;
		if (ps.health <= 0.4) txtColor = FlxColor.RED;
		else if (ps.health >= 1.55) txtColor = FlxColor.LIME;

		ps.scoreTxt.setFormat(fontPath, 15, txtColor, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		ps.scoreTxt.borderSize = 1.25;
		ps.callOnScripts('onUpdateScore', [miss]);
	}

	/** 原 PlayState.moveCamera（作用域分析：零遮蔽，23 处成员引用已限定）。 */
	public static function moveCamera(ps:PlayState, isDad:Bool)
	{
		if(isDad)
		{
			ps.camFollow.setPosition(ps.dad.getMidpoint().x + 150, ps.dad.getMidpoint().y - 100);
			ps.camFollow.x += ps.dad.cameraPosition[0] + ps.opponentCameraOffset[0];
			ps.camFollow.y += ps.dad.cameraPosition[1] + ps.opponentCameraOffset[1];
			ps.tweenCamIn();
		}
		else
		{
			ps.camFollow.setPosition(ps.boyfriend.getMidpoint().x - 100, ps.boyfriend.getMidpoint().y - 100);
			ps.camFollow.x -= ps.boyfriend.cameraPosition[0] - ps.boyfriendCameraOffset[0];
			ps.camFollow.y += ps.boyfriend.cameraPosition[1] + ps.boyfriendCameraOffset[1];

			if (Paths.formatToSongPath(PlayState.SONG.song) == 'tutorial' && ps.cameraTwn == null && FlxG.camera.zoom != 1)
			{
				ps.cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						ps.cameraTwn = null;
					}
				});
			}
		}
	}

	/** 原 PlayState.moveCameraSection（作用域分析：零遮蔽，19 处成员引用已限定）。 */
	public static function moveCameraSection(ps:PlayState, ?sec:Null<Int>):Void
	{
		if(sec == null) sec = ps.curSection;
		if(sec < 0) sec = 0;

		if(PlayState.SONG.notes[sec] == null) return;

		if (ps.gf != null && PlayState.SONG.notes[sec].gfSection)
		{
			ps.camFollow.setPosition(ps.gf.getMidpoint().x, ps.gf.getMidpoint().y);
			ps.camFollow.x += ps.gf.cameraPosition[0] + ps.girlfriendCameraOffset[0];
			ps.camFollow.y += ps.gf.cameraPosition[1] + ps.girlfriendCameraOffset[1];
			ps.tweenCamIn();
			ps.callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		// 联机真双人-客户端镜像：本端演唱半边与谱面 mustHitSection 相反（客户端唱 Dad 半边），
		// 反转 isDad，保证相机跟随「本屏当前演唱的角色」（房主端不变）。
		var isDad:Bool = (PlayState.SONG.notes[sec].mustHitSection != true) != ps.onlineMirror;
		ps.moveCamera(isDad);
		ps.callOnScripts('onMoveCamera', [isDad ? 'dad' : 'boyfriend']);
	}

	/** 原 PlayState.buildScoreText（作用域分析：零遮蔽，9 处成员引用已限定）。 */
	public static function buildScoreText(ps:PlayState):String
	{
		var fmt:String = ClientPrefs.data.scoreTxtFormat;
		// 兼容旧“显示NPS”开关：开启且格式里没写 {nps} 时，自动在 {fc} 后追加
		if (ClientPrefs.data.showNPS && fmt.indexOf('{nps}') == -1)
			fmt = StringTools.replace(fmt, '{fc}', '{fc} | NPS: {nps}');

		var acc:String = Std.string(CoolUtil.floorDecimal(ps.ratingPercent * 100, 2));
		// health 范围 0~2（默认 1 = 50%），换算成 0%~100%；
		// 开启「血条溢出图标飞出」时改用显示级 healthDisplayPct（音符爆发可冲到 1000%，随后回落到真实血量）
		var healthVal:Float = ClientPrefs.data.iconFlyOverflow ? ps.healthDisplayPct : (ps.health / 2 * 100);
		var healthPct:String = Std.string(Math.round(healthVal)) + '%';
		return fmt
			.replace('{score}', Std.string(ps.songScore))
			.replace('{misses}', Std.string(ps.songMisses))
			.replace('{rank}', ps.ratingName)
			.replace('{accuracy}', acc)
			.replace('{nps}', Std.string(ps.npsDisplay))
			.replace('{fc}', ps.ratingFC)
			.replace('{combo}', Std.string(ps.combo))
			.replace('{health}', healthPct);
	}

	/** 原 PlayState.hudGetOffset（作用域分析：零遮蔽，0 处成员引用已限定）。 */
	public static function hudGetOffset(ps:PlayState, id:String):Array<Float>
	{
		// 防御：旧存档/异常数据下 hudLayout 可能是 null 或 haxe.Json 还原的匿名对象
		// （Map 经 JSON 往返后 .exists()/.get() 会抛 Null Object Reference）——
		// 任何异常都回退默认 [0,0]，绝不因布局数据拖垮整局
		var layout:Dynamic = ClientPrefs.data.hudLayout;
		if (layout != null)
		{
			try
			{
				if (layout.exists(id)) return cast layout.get(id);
			}
			catch (e:Dynamic) {}
		}
		var arr:Array<Float> = [0, 0];
		if (layout != null)
		{
			try { layout.set(id, arr); } catch (e:Dynamic) {}
		}
		return arr;
	}

	/** 原 PlayState.judgeRatingKE（作用域分析：零遮蔽，10 处成员引用已限定）。 */
	public static function judgeRatingKE(ps:PlayState, note:Note):Rating
	{
		// botplay 命中时刻由其排期时刻定义（=音符自身 strumTime），帧延迟/批量弹出不影响评级
		var signedDiff:Float = ps.cpuControlled ? 0 : (note.strumTime - Conductor.songPosition);
		var timeScale:Float = Conductor.safeZoneOffset / 166;
		var off:Int = ClientPrefs.data.marvelousJudgement ? 1 : 0;

		// Marvelous：比 Sick 更严（窗口 = Sick 的一半）
		if (off == 1 && Math.abs(signedDiff) <= ps.ratingsData[0].hitWindow * timeScale)
			return ps.ratingsData[0];

		if (signedDiff > 135 * timeScale) return ps.ratingsData[off + 3]; // way early
		if (signedDiff > 90 * timeScale) return ps.ratingsData[off + 2]; // early
		if (signedDiff > 45 * timeScale) return ps.ratingsData[off + 1]; // kinda there
		if (signedDiff < -45 * timeScale) return ps.ratingsData[off + 1]; // little late
		if (signedDiff < -90 * timeScale) return ps.ratingsData[off + 2]; // late
		if (signedDiff < -135 * timeScale) return ps.ratingsData[off + 3]; // late as fuck
		return ps.ratingsData[off]; // sick（marvelous 窗口外）
	}

	/** 原 PlayState.cachePopUpScore（作用域分析：零遮蔽，3 处成员引用已限定）。 */
	public static function cachePopUpScore(ps:PlayState)
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (PlayState.stageUI != "normal")
		{
			uiPrefix = '${PlayState.stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		for (rating in ps.ratingsData)
			Paths.image(uiPrefix + rating.image + uiSuffix);
		for (i in 0...10)
			Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	/** 原 PlayState.refreshOppHealthFill（作用域分析：零遮蔽，7 处成员引用已限定）。 */
	public static function refreshOppHealthFill(ps:PlayState):Void
	{
		if (ps.onlineOppHealthFill == null) return;
		var pct:Float = FlxMath.bound(ps.onlineOppHealth, 0, 2) / 2;
		var newW:Int = Std.int(ps.onlineOppBarW * pct);
		if (newW <= 0)
		{
			ps.onlineOppHealthFill.visible = false;
			return;
		}
		ps.onlineOppHealthFill.visible = true;
		ps.onlineOppHealthFill.makeGraphic(newW, Std.int(ps.onlineOppBarH), pct >= 0.5 ? 0xFF7BE27B : 0xFFFF6B6B);
	}

	/** 原 PlayState.refreshOppHud（作用域分析：零遮蔽，15 处成员引用已限定）。 */
	public static function refreshOppHud(ps:PlayState):Void
	{
		if (ps.onlineOppTexts == null || ps.onlineOppTexts.length < 5) return;
		ps.onlineOppTexts[0].text = PlayState.onlineOppNick;
		ps.onlineOppTexts[1].text = '连击: ' + ps.onlineOppCombo;
		ps.onlineOppTexts[2].text = '分数: ' + ps.onlineOppScore;
		var oppAcc:Float = ps.onlineOppTotalPlayed > 0 ? ps.onlineOppTotalNotesHit / ps.onlineOppTotalPlayed : 0;
		ps.onlineOppTexts[3].text = '准确率: ' + Math.round(oppAcc * 1000) / 10 + '%';
		ps.onlineOppTexts[4].text = '判定: ' + ps.buildOppCountsLine();
		ps.refreshOppHealthFill();
	}

	/** 原 PlayState.updateHUDVisibility（作用域分析：零遮蔽，14 处成员引用已限定）。 */
	public static function updateHUDVisibility(ps:PlayState)
	{
		var hide:Bool = ClientPrefs.data.hideHud;
		if (ps.healthBar != null) ps.healthBar.visible = !hide;
		if (ps.healthBarOverlay != null) ps.healthBarOverlay.visible = !hide && ClientPrefs.data.healthBarOverlay && !ClientPrefs.data.oldHealthBar;
		if (ps.iconP1 != null) ps.iconP1.visible = !hide;
		if (ps.iconP2 != null) ps.iconP2.visible = !hide;
		if (ps.scoreTxt != null) ps.scoreTxt.visible = !hide;
		if (ps.timeBarOverlay != null) ps.timeBarOverlay.visible = ps.timeBar != null && ps.timeBar.visible && !hide;
	}

	/** 原 PlayState.buildRatingCountsCsv（作用域分析：零遮蔽，2 处成员引用已限定）。 */
	public static function buildRatingCountsCsv(ps:PlayState):String
	{
		var parts:Array<String> = [];
		for (r in ps.ratingsData)
			if (r.hits > 0) parts.push(r.name + ':' + r.hits);
		parts.push('miss:' + ps.songMisses);
		return parts.join(',');
	}

	/** 原 PlayState.cameraSmoothSpeed（作用域分析：零遮蔽，0 处成员引用已限定）。 */
	public static function cameraSmoothSpeed(ps:PlayState):Float
	{
		var presets:Map<String, Float> = ClientPrefs.camSmoothPresets;
		var v:Null<Float> = (ClientPrefs.data != null && presets != null) ? presets.get(ClientPrefs.data.camSmooth) : null;
		return (v == null || v <= 0) ? 2.4 : v; // 兜底 = 原引擎强度（1.22s）
	}
}
