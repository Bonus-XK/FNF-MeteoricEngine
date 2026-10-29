package backend;

import flixel.FlxSprite;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;

/**
 * 评分（Sick/Good…）与连击（数字 + Combo 词）弹窗的**弹出方式** —— 单一实现点。
 *
 * 为什么要抽出来：原本 `PlayState.popUpScore` 里只有一种弹出写法，而且是"扔出去"式的——
 * 给精灵一个向上初速度（`velocity.y -= random(140,175)`）加向下重力
 * （`acceleration.y = 550`），再叠一条 alpha 淡出。这个抛物线有两个毛病：
 *   1. 精灵从命中那一刻起就一直在加速下坠，尾巴长、位置会飘；
 *   2. 进入没有任何缓冲，alpha 直接是满值，观感是"贴上来"而不是"弹出来"。
 *
 * 现抽成本类并给出 4 种方式（存档值 = `CHOICES` 元素；
 * 显示名走语言包 `optionValue.popupStyle.<i>`）：
 *   classic 经典抛物 / pop 弹性弹出 / slide 上滑 / fade 淡入淡出
 *
 * 约定（改本类必读）：
 *  - `play()` **接管**精灵的全部运动与销毁。调用后不要再给同一精灵设
 *    velocity / acceleration / alpha 补间，否则两套动画互相覆盖。
 *  - `play()` 必须在 `setGraphicSize()` + `updateHitbox()` **之后**调用：
 *    本类以当时的 scale / x / y 作为基准值；而 `updateHitbox()` 会
 *    `centerOrigin()`，所以缩放支点是精灵中心 —— 原地弹出、不漂移。
 *  - 所有时长都除以 `playbackRate`，变速下节奏不变（与 `IconBop` 同口径）。
 *  - classic 分支**不经过本类**，上游原行为逐字保留。
 *
 * 立体层的口径（`ClientPrefs.data.popup3D`，对齐 Codename Engine 的做法）：
 *  Codename 的 `comboGroup` 是 `new RotatingSpriteGroup(FlxG.width * 0.55, FlxG.height * 0.5 - 60)`
 *  —— **直接用屏幕尺寸算出的值当世界坐标**，随后 `add(comboGroup)` 落到默认相机 `camGame`，
 *  **既不设 `cameras` 也不设 `scrollFactor`（默认 1,1），更不做任何坐标反解**。
 *  于是弹窗被钉在世界里的一个固定点上：镜头推近它跟着变大，镜头平移它跟着移出视野，
 *  但它相对**世界**始终不动 —— 这正是"场景里的物体"该有的行为。
 *
 *  ⚠ 所以本类在立体层下**只换摄像机、不动坐标**。曾经写过一版"按当前 viewLeft/zoom
 *  反解回屏幕位置"的换算，那会让每次弹出都追着镜头跑、失去世界感，已废弃。
 */
class PopupAnim
{
	// ==================== 档位常量（同时是存档值） ====================

	public static inline final CLASSIC:String = 'classic';
	public static inline final POP:String = 'pop';
	public static inline final SLIDE:String = 'slide';
	public static inline final FADE:String = 'fade';

	/** 新默认档（`ClientPrefs.SaveVariables.popupStyle` 与本常量保持一致） */
	public static inline final DEFAULT_STYLE:String = POP;

	/**
	 * 设置项档位顺序（传给 `new Option(..., 'string', PopupAnim.CHOICES)`）。
	 * 下标 i 对应语言包 key `optionValue.popupStyle.<i>` —— **调整顺序要同步改语言包**。
	 */
	public static final CHOICES:Array<String> = [CLASSIC, POP, SLIDE, FADE];

	// ==================== 参数（秒 / 像素，均以 rate=1 为基准） ====================

	/** 进入时长 */
	static inline final IN_TIME:Float = 0.11;
	/** 进入后悬停时长（停一下才走，读起来更从容） */
	static inline final HOLD_TIME:Float = 0.08;
	/** 退出（上浮 + 淡出）时长 */
	static inline final OUT_TIME:Float = 0.16;
	/** 总时长 = 0.11 + 0.08 + 0.16 = 0.35s */

	/** pop：起始缩放（相对基准） */
	static inline final POP_FROM:Float = 0.78;
	/**
	 * pop：过冲峰值（相对基准）。
	 *
	 * ⚠ 刻意压到 6%：2026-10-28 修 `IconBop`「太 Q 弹」时量到的结论是过冲 >10%
	 * 就会读成果冻感；这里只保留"弹一下"的暗示，且回落用 quadOut 一次收干净，
	 * 不像 elastic 那样反复摆。
	 */
	static inline final POP_OVER:Float = 1.06;
	/** pop：过冲后回落时长 = IN_TIME × 本系数 */
	static inline final POP_SETTLE:Float = 1.4;

	/** slide：进入时的起始下移距离（px） */
	static inline final SLIDE_FROM:Float = 20;
	/** 退出时上浮距离（px）：pop / slide 共用；fade 不位移 */
	static inline final LIFT:Float = 14;

	// ==================== 对外 API ====================

	/** 是否为「非经典」风格（= 需要本类接管的） */
	public static inline function isCustom(style:String):Bool
	{
		return style == POP || style == SLIDE || style == FADE;
	}

	/**
	 * 播放弹出动画，结束时 `destroy()` 精灵。
	 *
	 * @param spr      目标精灵（须已完成 setGraphicSize + updateHitbox）
	 * @param style    `CHOICES` 元素；未知值按 fade 兜底
	 * @param rate     `playbackRate`
	 * @param durScale 时长倍率（`ClientPrefs.data.popupDuration`）
	 * @param cam      目标摄像机（HUD 层传 `camHUD`，立体层传 `camGame`）
	 */
	public static function play(spr:FlxSprite, style:String, rate:Float, durScale:Float,
			?cam:FlxCamera):Void
	{
		if (spr == null) return;

		// 本类自己管运动：先清掉 classic 那套抛物线物理，否则 velocity 会继续推着精灵跑
		spr.velocity.set(0, 0);
		spr.acceleration.set(0, 0);

		// 立体层只换摄像机，**不动坐标** —— 见类注释「立体层的口径」。
		if (cam != null) spr.cameras = [cam];

		var bsx:Float = spr.scale.x; // 基准缩放（setGraphicSize 之后的值，常见是 0.7）
		var bsy:Float = spr.scale.y;
		var by:Float = spr.y;

		var r:Float = (rate > 0.01) ? rate : 1.0; // 防 0 除
		var d:Float = (durScale > 0.01) ? durScale : 1.0;
		var tIn:Float = IN_TIME * d / r;
		var tHold:Float = HOLD_TIME * d / r;
		var tOut:Float = OUT_TIME * d / r;

		var finish:Void->Void = function() spr.destroy();

		switch (style)
		{
			case POP:
				spr.alpha = 1;
				scalePop(spr, bsx, bsy, POP_FROM, POP_OVER, tIn, FlxEase.expoOut, function()
			{
				// 过冲后回落：quadOut 一次收干净，不像 elastic 那样反复摆
				scalePop(spr, bsx, bsy, POP_OVER, 1.0, tIn * POP_SETTLE, FlxEase.quadOut);
			});

			case SLIDE:
				spr.alpha = 0;
				spr.y = by + SLIDE_FROM;
				FlxTween.tween(spr, {y: by, alpha: 1}, tIn, {ease: FlxEase.cubeOut});

			default: // FADE（含未知值兜底）
				spr.alpha = 0;
				FlxTween.tween(spr, {alpha: 1}, tIn, {ease: FlxEase.quadOut});
		}

		new FlxTimer().start(tIn + tHold, function(_)
		{
			if (style == FADE)
				FlxTween.tween(spr, {alpha: 0}, tOut, {ease: FlxEase.quadIn, onComplete: function(_) finish()});
			else
				FlxTween.tween(spr, {y: by - LIFT, alpha: 0}, tOut, {ease: FlxEase.quadIn, onComplete: function(_) finish()});
		});
	}

	/**
	 * 立体层兜底：把弹窗的**屏幕位置**夹进摄像机可视区，越界才动。
	 *
	 * 为什么需要：立体层把弹窗钉在世界坐标上，而不同舞台 / 段落的 `camGame.scroll`
	 * 差别很大（Week 1 实测 `scroll.x ∈ [-154, 237]`、`scroll.y ∈ [-9, 175]`），
	 * 镜头一上移，原本贴屏幕顶部的弹窗就会直接跑出可视区、玩家完全看不见。
	 * 正常情况**不改变任何坐标**（只有越界时才夹），所以"世界里的固定点"这个手感保留；
	 * 越界时夹到边缘，保证至少看得见。
	 */
	public static function fitToView(spr:FlxSprite, cam:FlxCamera):Void
	{
		if (spr == null || cam == null) return;
		var sx:Float = cam.totalScaleX;
		var sy:Float = cam.totalScaleY;
		if (!(sx > 0.01)) sx = 1.0;
		if (!(sy > 0.01)) sy = 1.0;

		final PAD:Float = 12; // 留一点边距，别让字紧贴屏幕边缘
		var screenX:Float = (spr.x - cam.viewLeft) * sx;
		var screenY:Float = (spr.y - cam.viewTop) * sy;
		var w:Float = spr.width * sx;
		var h:Float = spr.height * sy;

		var nx:Float = screenX;
		var ny:Float = screenY;
		if (nx < PAD) nx = PAD;
		else if (nx + w > cam.width - PAD) nx = cam.width - PAD - w;
		if (ny < PAD) ny = PAD;
		else if (ny + h > cam.height - PAD) ny = cam.height - PAD - h;

		if (nx != screenX) spr.x = cam.viewLeft + nx / sx;
		if (ny != screenY) spr.y = cam.viewTop + ny / sy;
	}

	/**
	 * 按倍率缩放精灵（以基准缩放 `bsx/bsy` 为单位 1）。
	 *
	 * 用 `FlxTween.num` 而不是直接 tween `spr.scale`：后者依赖 FlxPoint 的字段写入
	 * 语义（不同 flixel 版本对 scale 的 setter 处理不一致），自己插值最稳，
	 * 也便于把过冲量写成一个可读常量。
	 */
	static function scalePop(spr:FlxSprite, bsx:Float, bsy:Float, from:Float, to:Float, dur:Float,
			ease:Float->Float, ?onDone:Void->Void):FlxTween
	{
		var apply:Float->Void = function(v:Float) spr.scale.set(bsx * v, bsy * v);
		apply(from);
		// 第 5 个参数 TweenFunction：每帧以当前插值回调（比 onUpdate 里取 t.value 稳，
		// 因为 onUpdate 的形参类型是基类 FlxTween，拿不到 NumTween.value）
		return FlxTween.num(from, to, dur, {
			ease: ease,
			onComplete: function(_)
			{
				if (onDone != null) onDone();
			}
		}, apply);
	}
}
