package backend;

import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import flixel.FlxSubState;
import flixel.FlxSprite;
import openfl.utils.Assets;

/**
 * 引擎过场动画（转场界面）。
 *
 * 样式由 `ClientPrefs.data.CustomFade` 决定（设置 → 效果 → 过场动画样式）：
 *   MOVE  「移动」 —— 左右横幅水平推入/推出（原版行为，默认）
 *   METEOR「陨星」 —— 程序化流星斜落 → 撞击环形闪光 → 横幅推入
 *   STAR  「星辉」 —— 程序化径向光晕 + 星芒爆发
 *
 * 【动效编排】统一用**显式相位状态机**（PHASE_* 常量 + switch），绝不用匿名对象存函数字段：
 * 曾用 `steps:Array<Dynamic>`（对象字面量里放 enter/update 闭包、靠反射调用）导致
 * **三种样式全部原生 SEGV**（连不碰任何新特效的「移动」也崩），改为类型安全 case 后消失。
 *
 * 【收尾契约】下一步动作一律经 finishOnce() 单点触发（_finished 闩锁）。
 * 【素材事实】loadingAlpha 是不透明平面图（alpha 剖面全 255），**不是光效素材**；
 * loadingL/R 是成对使用的箭头横幅，**不可旋转/非等比拉伸**。详见 meteoric-design skill。
 */
class CustomFadeTransition extends FlxSubState
{
	public static var finishCallback:Void->Void;
	public static var nextCamera:FlxCamera;

	public static inline var MODE_MOVE:String = '移动';
	public static inline var MODE_METEOR:String = '陨星';
	public static inline var MODE_STAR:String = '星辉';

	// 主题色（显式混色后作为乘数染素材；直接写 primary 的乘法着色对高亮素材无效）
	static final THEME_BLEND:Float = 0.45;
	static final THEME_BLEND_STAR:Float = 0.35;
	static final THEME_BAR_ALPHA:Float = 0.9;
	static final THEME_BAR_THICKNESS:Float = 6;

	// 相位编号（显式常量，替代 Dynamic 步骤表）
	static final PHASE_NONE:Int = 0;
	static final PHASE_WAIT:Int = 1;
	static final PHASE_FALL:Int = 2;   // 陨星：流星下落
	static final PHASE_IMPACT:Int = 3; // 陨星：撞击闪光 + 横幅推入
	static final PHASE_BLOOM:Int = 4;  // 星辉：光晕展开
	static final PHASE_PANELS:Int = 5; // 移动：横幅推入
	static final PHASE_SETTLE:Int = 6; // 收尾停顿
	static final PHASE_OUT:Int = 7;    // 出场（三种样式共用）

	// 相位时长（秒）
	static final T_WAIT:Float = 0.08;
	static final T_FALL:Float = 0.60;
	static final T_IMPACT:Float = 0.30;
	static final T_BLOOM:Float = 0.52;
	static final T_PANELS:Float = 0.58;
	static final T_SETTLE:Float = 0.14;
	static final T_OUT:Float = 0.42;

	var isTransIn:Bool = false;
	var duration:Float;

	// 相位状态
	var phase:Int = PHASE_NONE;
	var phaseT:Float = 0;

	// 移动样式
	var loadLeft:FlxSprite;
	var loadRight:FlxSprite;
	// 陨星样式
	var meteorTail:FlxSprite;
	var meteorHead:FlxSprite;
	var meteorGlow:FlxSprite;
	var impactRing:FlxSprite;
	var fallFromX:Float = 0;
	var fallFromY:Float = 0;
	var fallToX:Float = 0;
	var fallToY:Float = 0;
	// 星辉样式
	var bloomRings:Array<FlxSprite> = [];
	var bloomBaseR:Array<Float> = [];
	var rayGroup:Array<FlxSprite> = [];
	var rayBaseAngle:Array<Float> = [];
	var bloomUnit:Float = 45;

	var WaterMark:FlxText;
	var EventText:FlxText;
	var themeBar:FlxSprite;
	var themeBlend:Float = THEME_BLEND;
	var themeListener:Void->Void;

	var allTweens:Array<FlxTween> = [];
	var _finished:Bool = false;
	var _pendingFinish:Float = 0;

	public function new(duration:Float, isTransIn:Bool)
	{
		this.isTransIn = isTransIn;
		this.duration = duration;
		super();
	}

	override function create()
	{
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		switch (ClientPrefs.data.CustomFade)
		{
			case MODE_METEOR:
				createMeteor();
			case MODE_STAR:
				createStar();
			default:
				createMove();
		}

		addThemeAccent();
		themeListener = function() refreshThemeColors();
		DesignTokens.addThemeListener(themeListener);

		phase = isTransIn ? PHASE_OUT : PHASE_WAIT;
		phaseT = 0;

		super.create();
	}

	// ============================================================
	//  样式 1：移动
	// ============================================================

	function createMove():Void
	{
		loadRight = makeScreenSprite('loadingR', isTransIn ? 0 : FlxG.width);
		loadLeft = makeScreenSprite('loadingL', isTransIn ? 0 : -FlxG.width);
		makeTexts();
		if (isTransIn)
		{
			EventText.text = 'COMPLETED !';
		}
		else if (!ClientPrefs.data.CustomFadeText)
		{
			clearTexts();
		}
	}

	// ============================================================
	//  样式 2：陨星（流星斜落 → 撞击闪光 → 横幅推入）
	// ============================================================

	function createMeteor():Void
	{
		// 拖尾：竖向渐变（顶部透明 → 主题色 → 亮头），旋转 −32° 即为斜向。
		// 用 createGradientFlxSprite（已注册 FlxGraphic）而非裸 BitmapData 赋 pixels：
		// 后者在共享/克隆场景会走到未注册图形路径并原生崩溃。
		// 尾迹用**正常混合 + 高不透明度**：ADD 混合在亮色背景（本转场底色是高亮白图）上会直接饱和成白、
		// 完全看不出痕迹。渐变保留"顶端透明 → 末端亮"，形成流动的尾。
		meteorTail = FlxGradient.createGradientFlxSprite(24, 200, [0x00FFFFFF, DesignTokens.primary, 0xFFFFFFFF], 1, 90);
		meteorTail.alpha = 0.95;
		meteorTail.scrollFactor.set();
		meteorTail.antialiasing = ClientPrefs.data.antialiasing;
		meteorTail.scale.set(3.2, 3.2);
		meteorTail.updateHitbox();
		// 复位为"未缩放帧尺寸 + offset 0"：否则 updateHitbox 会把 offset 设成 −22，
		// 使 sprite.x/y 不再等于可见左上角，setMeteorPos 的坐标计算会整体斜偏 22px。
		meteorTail.resetFrameSize();
		meteorTail.resetSizeFromFrame();
		meteorTail.angle = -32;
		meteorTail.origin.set(meteorTail.width * 0.5, meteorTail.height);
		add(meteorTail);

		// 头部 = 正常混合的亮核 + ADD 混合的外层光晕（亮背景上也能看出"发光"）
		meteorHead = new FlxSprite(0, 0).makeGraphic(30, 30, FlxColor.WHITE);
		meteorHead.scrollFactor.set();
		meteorHead.antialiasing = ClientPrefs.data.antialiasing;
		add(meteorHead);

		meteorGlow = new FlxSprite(0, 0).makeGraphic(84, 84, FlxColor.WHITE);
		meteorGlow.scrollFactor.set();
		meteorGlow.antialiasing = ClientPrefs.data.antialiasing;
		meteorGlow.blend = openfl.display.BlendMode.ADD;
		meteorGlow.alpha = 0.55;
		add(meteorGlow);

		impactRing = FlxGradient.createGradientFlxSprite(128, 128, [0xFFFFFFFF, DesignTokens.primary, 0x00FFFFFF], 1, 0);
		impactRing.scrollFactor.set();
		impactRing.antialiasing = ClientPrefs.data.antialiasing;
		impactRing.origin.set(64, 64);
		impactRing.blend = openfl.display.BlendMode.ADD;
		impactRing.alpha = 0;
		impactRing.screenCenter();
		add(impactRing);

		loadRight = makeScreenSprite('loadingR', FlxG.width);
		loadLeft = makeScreenSprite('loadingL', -FlxG.width);
		makeTexts();

		// 起点只放"屏幕外一点点"：曾设成 -0.42 屏高（-302px），配上重力曲线后
		// 流星头部要到 p≈0.83 才进画面，可见窗口只剩 ~0.07s（4 帧）→ 观感就是"没有陨星"。
		// 现在起点贴着左上角外缘，整个下落过程绝大多数时间都在屏内。
		// 起点只需"贴着屏幕外一点点"。曾设 -0.42 屏高 + p⁴ 级加速，流星头部要到 p≈0.83
		// 才进画面 → 可见窗口只剩 9 帧，"看起来没有陨星"。现在起点 -0.24 屏高、
		// 下落 0.60s、二次型加速：可见约 22 帧（0.38s）。
		fallFromX = -FlxG.width * 0.04;
		fallFromY = -FlxG.height * 0.24;
		fallToX = FlxG.width * 0.42;
		fallToY = FlxG.height * 0.84; // 屏内偏下：撞击闪光必须看得见
		setMeteorPos(fallFromX, fallFromY);

		if (isTransIn)
		{
			EventText.text = 'COMPLETED !';
			meteorTail.alpha = 0;
			meteorHead.alpha = 0;
			meteorGlow.alpha = 0;
			impactRing.alpha = 0;
		}
		else if (!ClientPrefs.data.CustomFadeText)
		{
			clearTexts();
		}
	}

	/** 流星头跟随拖尾前端（拖尾绕底端旋转，头在下方偏移处）。 */
	function setMeteorPos(x:Float, y:Float):Void
	{
		// meteorTail 的 origin 在**底端**（拖尾自下而上渐隐，底端即流星头所在）：
		// 传入的 (x,y) 是"头的位置"，锚点（origin 所在）必须沿运动反方向后退一个尾长。
		// 曾把符号写成 `- len*cos` → 头部跑到拖尾上方 546px，整条流星在屏幕外飞完整段下落，
		// 观感就是"根本没有陨星"（靠运行期打点抓到：head.y 全程为负）。
		var rad:Float = meteorTail.angle * Math.PI / 180;
		var len:Float = meteorTail.height;
		meteorTail.setPosition(x - Math.sin(rad) * len, y - Math.cos(rad) * len);
		meteorHead.setPosition(x - meteorHead.width * 0.5, y - meteorHead.height * 0.5);
		if (meteorGlow != null) meteorGlow.setPosition(x - meteorGlow.width * 0.5, y - meteorGlow.height * 0.5);
	}
	// ============================================================
	//  样式 3：星辉（程序化径向光晕 + 星芒）
	// ============================================================

	function createStar():Void
	{
		themeBlend = THEME_BLEND_STAR;

		// 径向光晕 = 多层同心圆：半径与 α 同时递减 → 无 shader 的软边辉光标准手法
		// α 之和必须留在 ~1 以内：曾用 [0.16,0.22,0.3,0.42,0.58,0.8]（Σ≈2.5）叠加，
		// 中心直接饱和成一块死白 —— 观感是"大白块贴脸"而不是光晕（用户实测）。
		var radii:Array<Float> = [1.0, 0.78, 0.58, 0.4, 0.26, 0.15];
		for (i in 0...radii.length)
		{
			var ring:FlxSprite = new FlxSprite(0, 0).makeGraphic(64, 64, FlxColor.WHITE);
			ring.scrollFactor.set();
			ring.antialiasing = ClientPrefs.data.antialiasing;
			ring.blend = openfl.display.BlendMode.ADD;
			ring.origin.set(32, 32);
			ring.screenCenter();
			ring.scale.set(0.01, 0.01);
			ring.alpha = 0;
			add(ring);
			bloomRings.push(ring);
			bloomBaseR.push(radii[i]);
		}

		// 星芒：24×128「白→透明」渐变模板，clone() 出 12 份各自旋转
		var rayTemplate:FlxSprite = FlxGradient.createGradientFlxSprite(24, 128, [0xFFFFFFFF, 0x00FFFFFF], 1, 90);
		for (i in 0...12)
		{
			var ray:FlxSprite = rayTemplate.clone();
			ray.scrollFactor.set();
			ray.antialiasing = ClientPrefs.data.antialiasing;
			ray.blend = openfl.display.BlendMode.ADD;
			ray.angle = i * 30;
			ray.alpha = 0;
			ray.screenCenter();
			add(ray);
			rayGroup.push(ray);
			rayBaseAngle.push(i * 30);
		}

		bloomUnit = Math.sqrt(FlxG.width * FlxG.width + FlxG.height * FlxG.height) * 2 / 64;

		makeTexts();
		if (isTransIn)
		{
			EventText.text = 'COMPLETED !';
			paintBloom(1.0);
		}
		else
		{
			WaterMark.alpha = 0;
			EventText.alpha = 0;
			if (!ClientPrefs.data.CustomFadeText) clearTexts();
		}
	}

	/** 按 e(0→1+) 绘制径向光晕：每层半径按 bloomBaseR 递减、α 随层号收束。 */
	function paintBloom(e:Float):Void
	{
		var k:Float = FlxMath.bound(e, 0.02, 1.2);
		for (i in 0...bloomRings.length)
		{
			var sc:Float = bloomUnit * bloomBaseR[i] * k;
			bloomRings[i].scale.set(sc, sc);
			// 真·径向衰减：中心 0.34 → 外缘 0.08（各层依次覆盖，视觉上就是连续软边）。
			// 曾经中心层 α0.9 且 6 层叠加 Σ≈2.5 → 中心饱和成一块死白（用户实测"大白块贴脸"）。
			var a:Float = 0.08 + 0.26 * (i / 5.0);
			bloomRings[i].alpha = FlxMath.bound(k * a, 0, 0.42);
		}
	}

	// ============================================================
	//  相位推进
	// ============================================================

	function phaseDuration():Float
	{
		return switch (phase)
		{
			case PHASE_WAIT: T_WAIT;
			case PHASE_FALL: T_FALL;
			case PHASE_IMPACT: T_IMPACT;
			case PHASE_BLOOM: T_BLOOM;
			case PHASE_PANELS: T_PANELS;
			case PHASE_SETTLE: T_SETTLE;
			case PHASE_OUT: duration * 0.85;
			default: 0;
		}
	}

	function nextPhase():Void
	{
		switch (phase)
		{
			case PHASE_WAIT:
				switch (ClientPrefs.data.CustomFade)
				{
					case MODE_METEOR: phase = PHASE_FALL;
					case MODE_STAR: phase = PHASE_BLOOM;
					default: phase = PHASE_PANELS;
				}
			case PHASE_FALL: phase = PHASE_IMPACT;
			case PHASE_IMPACT, PHASE_BLOOM, PHASE_PANELS: phase = PHASE_SETTLE;
			case PHASE_SETTLE, PHASE_OUT: phase = PHASE_NONE;
			default: phase = PHASE_NONE;
		}
		phaseT = 0;
		if (phase == PHASE_IMPACT) enterImpact();
		else if (phase == PHASE_SETTLE) enterSettle();
	}

	function enterImpact():Void
	{
		if (impactRing != null) impactRing.setPosition(fallToX - impactRing.width * 0.5, fallToY - impactRing.height * 0.5);
	}

	function enterSettle():Void
	{
		if (impactRing != null) impactRing.alpha = 0;
		easePanels(1, FlxEase.linear);
		if (ClientPrefs.data.CustomFade == MODE_STAR)
		{
			for (r in rayGroup) r.alpha = 0; // 星芒收尾前散掉，避免残留
		}
	}

	function runPhase(p:Float):Void
	{
		switch (phase)
		{
			case PHASE_FALL:
				var q:Float = 0.35 * p + 0.65 * p * p; // 先匀速后加速（重力感但不"一闪而过"）
				setMeteorPos(fallFromX + (fallToX - fallFromX) * q, fallFromY + (fallToY - fallFromY) * q);
			case PHASE_IMPACT:
				var sc:Float = 0.35 + 2.6 * FlxEase.quartOut(p);
				if (impactRing != null)
				{
					impactRing.scale.set(sc, sc);
					impactRing.alpha = (1 - p) * 0.95;
				}
				var fade:Float = Math.max(0, 1 - p * 4);
				if (meteorTail != null) meteorTail.alpha = fade;
				if (meteorHead != null) meteorHead.alpha = fade;
				if (meteorGlow != null) meteorGlow.alpha = fade * 0.55;
				if (p > 0.35) easePanels((p - 0.35) / 0.65, FlxEase.quintOut);
				textSlide(p);
			case PHASE_BLOOM:
				var e:Float = FlxEase.quartOut(p);
				paintBloom(0.06 + 0.94 * e);
				for (i in 0...rayGroup.length)
				{
					rayGroup[i].scale.set(1, 1.1 + 1.6 * e);
					rayGroup[i].alpha = Math.max(0, 0.5 * (1 - Math.abs(p - 0.45) * 1.6));
					rayGroup[i].angle = rayBaseAngle[i] + 26 * (1 - p);
				}
				textSlide(p);
			case PHASE_PANELS:
				easePanels(p, FlxEase.expoInOut);
				textSlide(p);
			case PHASE_SETTLE:
				if (ClientPrefs.data.CustomFade == MODE_STAR) paintBloom(1.0);
			case PHASE_OUT:
				var e2:Float = FlxEase.quintIn(p);
				if (loadLeft != null) loadLeft.x = -FlxG.width * e2;
				if (loadRight != null) loadRight.x = FlxG.width * e2;
				if (WaterMark != null) WaterMark.x = 50 - 1280 * e2;
				if (EventText != null) EventText.x = 50 - 1280 * e2;
				if (ClientPrefs.data.CustomFade == MODE_STAR)
				{
					paintBloom(1.0 - e2);
					for (r in rayGroup) r.alpha = Math.max(0, 0.3 * (1 - p * 1.3));
				}
			default:
				// PHASE_WAIT / PHASE_NONE：不动
		}
	}

	override function update(elapsed:Float):Void
	{
		if (_pendingFinish > 0)
		{
			_pendingFinish -= elapsed;
			if (_pendingFinish <= 0)
			{
				_pendingFinish = 0;
				doFinish();
				return;
			}
		}

		if (phase != PHASE_NONE)
		{
			var dur:Float = phaseDuration();
			if (dur <= 0)
			{
				nextPhase();
				if (phase == PHASE_NONE) finishOnce(0);
			}
			else
			{
				phaseT += elapsed;
				runPhase(FlxMath.bound(phaseT / dur, 0, 1));
				if (phaseT >= dur)
				{
					var carried:Float = phaseT - dur;
					nextPhase();
					if (phase == PHASE_NONE) finishOnce(0);
					else phaseT = carried;
				}
			}
		}

		super.update(elapsed);
	}

	// ============================================================
	//  公共构件
	// ============================================================

	/** 横幅推拉到位（p: 0→1）。 */
	function easePanels(p:Float, ease:Float->Float):Void
	{
		var e:Float = ease(FlxMath.bound(p, 0, 1));
		if (loadLeft != null) loadLeft.x = -FlxG.width * (1 - e);
		if (loadRight != null) loadRight.x = FlxG.width * (1 - e);
	}

	/** 文字从左侧滑入（跟着横幅铺满的节奏）。 */
	function textSlide(p:Float):Void
	{
		var e:Float = FlxEase.cubeOut(FlxMath.bound(p * 1.6, 0, 1));
		if (WaterMark != null) WaterMark.x = -900 + 950 * e;
		if (EventText != null) EventText.x = -900 + 950 * e;
	}

	function makeScreenSprite(image:String, x:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, 0).loadGraphic(Paths.image(image));
		spr.scrollFactor.set();
		spr.antialiasing = ClientPrefs.data.antialiasing;
		spr.setGraphicSize(FlxG.width, FlxG.height);
		spr.updateHitbox();
		spr.x = x;
		spr.y = 0;
		add(spr);
		return spr;
	}

	function makeTexts():Void
	{
		WaterMark = new FlxText(isTransIn ? 50 : -900, 720 - 50 - 50 * 2, 0, 'ME ENGINE V' + Main.meVersion, 50);
		WaterMark.scrollFactor.set();
		WaterMark.setFormat(Assets.getFont("assets/fonts/loadText.ttf").fontName, 50, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		WaterMark.antialiasing = ClientPrefs.data.antialiasing;
		add(WaterMark);

		EventText = new FlxText(isTransIn ? 50 : -900, 720 - 50 - 50, 0, 'LOADING . . . . . . ', 50);
		EventText.scrollFactor.set();
		EventText.setFormat(Assets.getFont("assets/fonts/loadText.ttf").fontName, 50, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		EventText.antialiasing = ClientPrefs.data.antialiasing;
		add(EventText);
	}

	function clearTexts():Void
	{
		if (WaterMark != null) WaterMark.text = '';
		if (EventText != null) EventText.text = '';
	}

	// ============================================================
	//  主题色
	// ============================================================

	function addThemeAccent():Void
	{
		themeBar = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.WHITE);
		themeBar.scrollFactor.set();
		themeBar.alpha = THEME_BAR_ALPHA;
		add(themeBar);
		refreshThemeColors();
	}

	function refreshThemeColors():Void
	{
		var primary:FlxColor = DesignTokens.primary;

		applyThemeColor(loadLeft);
		applyThemeColor(loadRight);
		if (meteorHead != null && meteorHead.alive) meteorHead.color = primary;
		for (b in bloomRings) applyThemeColor(b);

		if (themeBar != null && themeBar.alive)
		{
			themeBar.color = primary;
			themeBar.scale.set(FlxG.width, FlxG.height * (THEME_BAR_THICKNESS / 720));
			themeBar.updateHitbox();
			themeBar.x = 0;
			themeBar.y = FlxG.height - themeBar.height;
		}
		if (EventText != null && EventText.alive) EventText.color = primary;
	}

	function applyThemeColor(spr:FlxSprite):Void
	{
		if (spr == null || !spr.alive) return;
		var blended:Null<FlxColor> = FlxColor.interpolate((FlxColor.WHITE : FlxColor), DesignTokens.primary, themeBlend);
		spr.color = (blended == null) ? DesignTokens.primary : blended;
	}

	// ============================================================
	//  收尾与清理
	// ============================================================

	function finishOnce(delay:Float):Void
	{
		if (_finished) return;
		_finished = true;
		if (delay <= 0)
		{
			doFinish();
			return;
		}
		_pendingFinish = delay;
	}

	function doFinish():Void
	{
		if (isTransIn)
		{
			close();
		}
		else if (finishCallback != null)
		{
			var cb:Void->Void = finishCallback;
			finishCallback = null;
			cb(); // 只把新状态排队进 FlxG._requestedState（真正交换在下一帧）
			close(); // 关键：这一帧结束前必须收掉转场层，否则残留
		}
		else
		{
			close();
		}
	}


	override function destroy():Void
	{
		if (themeListener != null)
		{
			DesignTokens.removeThemeListener(themeListener);
			themeListener = null;
		}
		for (t in allTweens)
		{
			if (t != null) t.cancel();
		}
		allTweens = [];
		super.destroy();
	}
}
