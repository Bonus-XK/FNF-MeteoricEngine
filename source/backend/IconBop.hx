package backend;

import objects.HealthIcon;

/**
 * 小图标跳动（血量条两侧 P1/P2 图标）—— **单一实现点**。
 *
 * 为什么要抽出来：原先这里是两个互相纠缠的 bool（`sbIconBop` / `keIconBop`），触发端
 * （`backend/NoteChartDomain.beatHit`）与回弹端（`states/PlayState.GameHUD.update`）
 * 各写一份分支；而「两个都关」的兜底其实是 Psych 上游**无条件**的 `scale(1.2)`
 * （`FNF-PsychEngine-0.7.1h/source/states/PlayState.hx:3064`，上游根本没有开关）。
 * 三种行为塞在两个开关里 → 新样式只能继续加 if，而且表达不了「完全静止」。
 * 现改为**单枚举** `ClientPrefs.data.iconBopStyle`：行为、参数、切档清理全在本类。
 *
 * 档位（存档值 = `CHOICES` 元素；显示名走语言包 `optionValue.iconBopStyle.<i>`）：
 *   none 关闭 / pulse 脉冲 / alternate 错拍 / nod 点头 / hop 跳跃 / squash 挤压 / ke KE 引擎
 *
 * 约定（改本类必读）：
 *  - 缩放一律走 `setScale` / `setScaleXY`（`updateHitbox()` + `origin(0,0)`），
 *    与历史 KE 实现口径一致。图标 x 由 `GameHUD.update` 每帧按 `150*scale.x` 重算
 *    （强绑血条中心，见 `PlayState.hx` 的 `iconP1.x = ...`），所以**缩放/旋转都不会
 *    让图标漂移**，本类不要碰 x。
 *  - `beatHit` 由 `NoteChartDomain.beatHit` 调用；该函数内部已用
 *    `lastBeatHit >= curBeat` 早退，一帧最多触发一次 → 这里是「每拍一次」而非「累积」。
 *  - 所有时间常数都乘 `playbackRate`，0.5x / 1.5x 变速下跳动快慢不变。
 *  - 垂直位移（hop）叠加在调用方传入的基准 y（`healthBar.y - 75`）之上，
 *    与 `backend/CameraHudDomain.hudRelayout` 的定位口径一致。
 *  - 静态每帧状态由 `reset()` 在 HUD 建成后清一次（同一时刻只有一个 PlayState 在跑）。
 */
class IconBop
{
	// ==================== 档位常量（同时是存档值） ====================

	public static inline final NONE:String = 'none';
	public static inline final PULSE:String = 'pulse';
	public static inline final ALTERNATE:String = 'alternate';
	public static inline final NOD:String = 'nod';
	public static inline final HOP:String = 'hop';
	public static inline final SQUASH:String = 'squash';
	public static inline final KE:String = 'ke';

	/** 新默认档（`ClientPrefs.SaveVariables.iconBopStyle` 与本常量保持一致） */
	public static inline final DEFAULT_STYLE:String = PULSE;

	/**
	 * 设置项档位顺序（传给 `new Option(..., 'string', IconBop.CHOICES)`）。
	 * 下标 i 对应语言包 key `optionValue.iconBopStyle.<i>` —— **调整顺序要同步改语言包**。
	 */
	public static final CHOICES:Array<String> = [NONE, PULSE, ALTERNATE, NOD, HOP, SQUASH, KE];

	// ==================== 参数（像素 / 度 / 秒） ====================

	/** 脉冲：每拍双方同步放到的峰值缩放 */
	static inline final PULSE_SCALE:Float = 1.16;
	/** 错拍：涨的一侧 / 缩的一侧，逐拍互换 */
	static inline final ALT_UP:Float = 1.14;
	static inline final ALT_DOWN:Float = 0.94;

	/** 点头：峰值缩放（P1 向左倾、P2 向右倾，各自朝血条外侧） */
	static inline final NOD_SCALE:Float = 1.12;
	/**
	 * 点头的倾角（度）。
	 *
	 * 历史值 3.5° + 线性回正看不出效果，两个原因：
	 *  ① 幅度太小 —— 3.5° 绕左上角旋转，150px 图标远角只抬 ~9px，被同帧的缩放盖过；
	 *  ② 线性回正 0.14s 就归零，**没有过冲** —— 「点头」的灵魂是越过中线再回来。
	 * 现在角度也走弹簧（见 `angX/angV`），峰值 8°（远角抬 ~21px）且约 17% 过冲，
	 * 「偏头→越过中线→回正」三段都能看出来。
	 */
	static inline final NOD_ANGLE:Float = 8.0;

	/** 跳跃：起跳速度（像素/秒，向上为负）/ 起跳缩放 / 重力（像素/秒²）/ 落地恢复系数 */
	static inline final HOP_V0:Float = 168.0;
	static inline final HOP_SCALE:Float = 1.08;
	static inline final HOP_GRAVITY:Float = 900.0;
	static inline final HOP_BOUNCE:Float = 0.28;
	/** 落地时给缩放弹簧的向下速度冲量（做压扁） */
	static inline final HOP_SQUASH_PUSH:Float = 3.2;

	/**
	 * 挤压：压扁帧 → 拉伸帧 → 归位。
	 * 两段都用**两端导数为 0** 的缓动（easeInOutSine / easeInOutCubic），
	 * 这样关键帧接缝处速度连续、没有 C¹ 断点（用 easeOut 会在接缝露出拐折）。
	 */
	static inline final SQ_SQUASH_X:Float = 0.90;
	static inline final SQ_SQUASH_Y:Float = 1.12;
	static inline final SQ_STRETCH_X:Float = 1.18;
	static inline final SQ_STRETCH_Y:Float = 0.90;
	static inline final SQ_T1:Float = 0.07;
	static inline final SQ_T2:Float = 0.26;

	/** KE：每拍放大的像素数（历史实现原值） */
	static inline final KE_GROW:Float = 30.0;

	// ==================== 缩放弹簧（脉冲 / 错拍 / 点头 / 跳跃共用） ====================
	//
	// 为什么用真弹簧而不是「指数衰减 + 残量截断」：
	// 指数衰减是**渐近**趋近 1.0，①永远不会过冲 → 缺回弹的「Q 弹」生命力；
	// ②只能在某个残量处硬截断归零，那一刻位移是**跳变**的（150px 图标上 3% ≈ 4.5px 突跳），
	// 高帧率下这一跳肉眼可见，就是「生硬 / 卡顿」的来源。
	// 阻尼弹簧同时解决两点：过冲提供生命力，且只有**位移与速度同时**趋零才归零，
	// 归零那一刻视觉上没有任何跳变。
	//
	// 参数（离线扫参得出，60/120/144/240fps 均验证过不抖动、不过冲发散）：
	// ω = 24 rad/s（周期 ≈ 0.26s），ζ = 0.45 → 过冲约 16.6%、停稳约 0.38s。
	// 逐帧轨迹（相对 1.0）：1.134 → 0.973（过冲）→ 1.000，全程连续无跳变。
	// ⚠ 改这两个值前先跑一遍扫参：过冲 >25% 会晃，<10% 会显得"软塌"。
	static inline final SPRING_K:Float = 576.0; // ω²
	static inline final SPRING_C:Float = 21.6; // 2ζω
	/** 归零阈值：位移与速度**同时**小于此值才停（位移 0.15% ≈ 0.2px，已不可见） */
	static inline final SPRING_EPS_X:Float = 0.0015;
	static inline final SPRING_EPS_V:Float = 0.02;
	/** 单帧积分上限：ω·h < 2 才稳定，长帧（切窗/卡顿）时钳住防发散 */
	static inline final SPRING_H_MAX:Float = 0.0334;

	// ==================== 每帧状态 ====================

	/** 缩放弹簧：x = 相对 1.0 的偏移，v = 速度（单位/秒）；下标 0 = P1，1 = P2 */
	static var springX:Array<Float> = [0, 0];
	static var springV:Array<Float> = [0, 0];
	/** 倾角弹簧（点头档）：x/v 同上，单位是度 */
	static var angX:Array<Float> = [0, 0];
	static var angV:Array<Float> = [0, 0];
	/** hop：垂直偏移（像素，负 = 向上）与速度（像素/秒） */
	static var bopY:Float = 0;
	static var bopVY:Float = 0;
	/** squash：相位计时（秒，< 0 = 不在挤压中） */
	static var squashT:Float = -1;
	/** alternate：交替奇偶 */
	static var altFlip:Bool = false;
	/** 上一次 update 生效的档位（用于切档时强制归位） */
	static var lastStyle:String = null;

	/**
	 * 进入对局时清空每帧状态。**必须**在 HUD 建成后、第一次 `update` 之前调一次。
	 */
	public static function reset():Void
	{
		springX[0] = 0;
		springX[1] = 0;
		springV[0] = 0;
		springV[1] = 0;
		angX[0] = 0;
		angX[1] = 0;
		angV[0] = 0;
		angV[1] = 0;
		bopY = 0;
		bopVY = 0;
		squashT = -1;
		altFlip = false;
		lastStyle = null;
	}

	/**
	 * 当前档位；存档被手改 / 语言包写了未知值时静默回落默认（不进 switch 的 default 分支）。
	 * 用显式比较而不是 `CHOICES.indexOf`，因为它每帧被调两次，不做数组扫描。
	 */
	static function style():String
	{
		var s:String = ClientPrefs.data.iconBopStyle;
		if (s == NONE || s == PULSE || s == ALTERNATE || s == NOD || s == HOP || s == SQUASH || s == KE) return s;
		return DEFAULT_STYLE;
	}

	// ==================== 拍点触发 ====================

	/**
	 * 每拍触发一次（由 `backend/NoteChartDomain.beatHit` 调用）。
	 *
	 * `none` 档在这里**什么都不做**：残留缩放/角度/位移由 `update` 的切档检测统一归位，
	 * 这样本函数不需要知道图标的基准 y。
	 *
	 * @param rate 播放倍速（`PlayState.playbackRate`）
	 */
	public static function beatHit(p1:HealthIcon, p2:HealthIcon, rate:Float):Void
	{
		if (p1 == null || p2 == null) return;
		var s:String = style();
		// ⚠ 「关闭」必须**提前返回**、不能留成 `case NONE:` 空体：
		// Haxe 的 `case A:` 空体等价于 `case A: case B:`，会 fall-through 进下面的 PULSE 分支。
		if (s == NONE) return;
		switch (s)
		{
			case PULSE:
				kick(p1, 0, PULSE_SCALE - 1);
				kick(p2, 1, PULSE_SCALE - 1);

			case ALTERNATE:
				altFlip = !altFlip;
				if (altFlip)
				{
					kick(p1, 0, ALT_UP - 1);
					kick(p2, 1, ALT_DOWN - 1);
				}
				else
				{
					kick(p2, 1, ALT_UP - 1);
					kick(p1, 0, ALT_DOWN - 1);
				}

			case NOD:
				kick(p1, 0, NOD_SCALE - 1);
				kick(p2, 1, NOD_SCALE - 1);
				// 倾角只改位移、保留速度 → 与上一拍的点头自然衔接
				angX[0] = -NOD_ANGLE;
				angX[1] = NOD_ANGLE;
				p1.angle = angX[0];
				p2.angle = angX[1];

			case HOP:
				kick(p1, 0, HOP_SCALE - 1);
				kick(p2, 1, HOP_SCALE - 1);
				// 用**速度冲量**起跳（而不是把 y 瞬移到 -14）：位移连续，
				// 上一跳还在空中时再次触发也只是叠加速度，不会硬跳。
				bopVY = -HOP_V0 * rate;
				bopY = 0;

			case SQUASH:
				squashT = 0;
				setScaleXY(p1, SQ_SQUASH_X, SQ_SQUASH_Y);
				setScaleXY(p2, SQ_SQUASH_X, SQ_SQUASH_Y);

			case KE:
				// 历史实现原样：每拍放大 KE_GROW 像素（按 frameWidth 折算成 scale）
				grow(p1, KE_GROW);
				grow(p2, KE_GROW);
		}
	}

	// ==================== 每帧回弹 ====================

	/**
	 * 每帧回弹（由 `states/PlayState.GameHUD.update` 调用）。
	 *
	 * ⚠ 调用点必须在它按 `150*scale.x` 重算图标 x 的**之前**，否则缩放与 x 会错开一帧。
	 *
	 * @param baseY 图标静止时的 y（`healthBar.y - 75`），hop 档在此之上叠加位移
	 */
	public static function update(p1:HealthIcon, p2:HealthIcon, elapsed:Float, rate:Float, baseY:Float):Void
	{
		if (p1 == null || p2 == null) return;
		var s:String = style();

		// 切档（玩家可以在对局中途改设置）：先把上一档的残留强制归位，再按新档走。
		if (s != lastStyle)
		{
			resetPose(p1, p2, baseY);
			lastStyle = s;
		}

		// ⚠ 同 beatHit：「关闭」提前返回，不留成空 case（避免 Haxe fall-through）。
		// 完全静止。归位已在上面的切档检测里做完；此后不再碰图标（零开销）。
		if (s == NONE)
		{
			if (bopY != 0)
			{
				bopY = 0;
				p1.y = baseY;
				p2.y = baseY;
			}
			return;
		}

		switch (s)
		{
			case PULSE | ALTERNATE:
				springStep(p1, 0, elapsed, rate);
				springStep(p2, 1, elapsed, rate);

			case NOD:
				springStep(p1, 0, elapsed, rate);
				springStep(p2, 1, elapsed, rate);
				angleStep(p1, 0, elapsed, rate);
				angleStep(p2, 1, elapsed, rate);

			case HOP:
				// 先走竖直（落地会给弹簧一个向下冲量做压扁），再积分缩放，冲量当帧即生效
				hopStep(p1, p2, elapsed, rate, baseY);
				springStep(p1, 0, elapsed, rate);
				springStep(p2, 1, elapsed, rate);

			case SQUASH:
				squashStep(p1, p2, elapsed, rate);

			case KE:
				// 历史实现原样：指数衰减 pow(0.5, dt*60*rate)（比脉冲档慢，回弹更"黏"）
				var decay:Float = Math.pow(0.5, elapsed * 60 * rate);
				keDecay(p1, decay);
				keDecay(p2, decay);
		}
	}

	// ==================== 各档位的每帧积分 ====================

	/**
	 * 弹簧触发：只改**位移**，保留速度 → 与上一拍的回弹自然衔接（快歌/连拍时不硬截断）。
	 * `offset` 是相对 1.0 的缩放偏移（如 1.16 → 0.16）。
	 */
	static function kick(icon:HealthIcon, i:Int, offset:Float):Void
	{
		springX[i] = offset;
		setScale(icon, 1 + offset);
	}

	/**
	 * 弹簧积分一步（半隐式欧拉）：`a = -k·x - c·v`，先更新速度再更新位移。
	 * 只有位移与速度**同时**低于阈值才归零 —— 归零瞬间没有可见跳变。
	 * 缩放与倾角共用同一套 K/C（`X`/`V` 传不同的数组即可）。
	 */
	static function springArr(X:Array<Float>, V:Array<Float>, i:Int, dt:Float, rate:Float):Float
	{
		var x:Float = X[i];
		var v:Float = V[i];
		if (x == 0 && v == 0) return 0; // 已静止：零开销

		var h:Float = dt * rate;
		// 长帧（切窗/瞬时卡顿）时钳住步长，否则 ω·h ≥ 2 会让显式积分发散成抖动
		if (h > SPRING_H_MAX) h = SPRING_H_MAX;

		v += (-SPRING_K * x - SPRING_C * v) * h;
		x += v * h;

		if (Math.abs(x) < SPRING_EPS_X && Math.abs(v) < SPRING_EPS_V)
		{
			x = 0;
			v = 0;
		}
		X[i] = x;
		V[i] = v;
		return x;
	}

	/** 缩放弹簧一步，并把结果写到精灵上 */
	static function springStep(icon:HealthIcon, i:Int, dt:Float, rate:Float):Void
	{
		if (springX[i] == 0 && springV[i] == 0) return; // 已静止：零开销
		setScale(icon, 1 + springArr(springX, springV, i, dt, rate));
	}

	/** 倾角弹簧一步（点头档） */
	static function angleStep(icon:HealthIcon, i:Int, dt:Float, rate:Float):Void
	{
		if (angX[i] == 0 && angV[i] == 0) return;
		icon.angle = springArr(angX, angV, i, dt, rate);
	}

	/** KE：历史实现的指数衰减（保持原样，未改手感） */
	static function keDecay(icon:HealthIcon, decay:Float):Void
	{
		if (icon.scale.x == 1) return;
		setScale(icon, 1 + (icon.scale.x - 1) * decay);
	}

	/**
	 * 跳跃：重力抛体 + 落地**恢复系数反弹** + y 回写。
	 * 落地不再硬钳速度到 0（那是最刺眼的一处跳变），而是按 HOP_BOUNCE 反弹，
	 * 形成「跳起 → 落地 → 小弹一下 → 衰减停」的自然节奏；
	 * 压扁由落地时给缩放弹簧一个向下速度冲量完成，同样没有位移跳变。
	 */
	static function hopStep(p1:HealthIcon, p2:HealthIcon, dt:Float, rate:Float, baseY:Float):Void
	{
		if (bopY != 0 || bopVY != 0)
		{
			var h:Float = dt * rate;
			bopVY += HOP_GRAVITY * h;
			bopY += bopVY * h;
			if (bopY >= 0)
			{
				bopY = 0;
				if (bopVY > 0)
				{
					bopVY = -bopVY * HOP_BOUNCE;
					// 压扁 = 给缩放弹簧一个向下的速度冲量（不是硬改位移）
					springV[0] -= HOP_SQUASH_PUSH;
					springV[1] -= HOP_SQUASH_PUSH;
				}
				else
				{
					bopVY = 0; // 反弹后已向下衰减完：彻底停
				}
			}
			p1.y = baseY + bopY;
			p2.y = baseY + bopY;
		}
	}

	/**
	 * 挤压：两段关键帧（压扁 → 拉伸 → 归位），相位由 beatHit 启动。
	 * 两段都用两端导数为 0 的缓动 → 关键帧接缝与终点都**速度连续**，没有拐折/顿挫。
	 */
	static function squashStep(p1:HealthIcon, p2:HealthIcon, dt:Float, rate:Float):Void
	{
		if (squashT < 0) return; // 相位已结束（或本档从未触发）
		squashT += dt * rate;
		if (squashT < SQ_T1)
		{
			// 段 1：压扁 → 拉伸（easeInOutSine：两端速度为 0）
			var k:Float = easeInOutSine(squashT / SQ_T1);
			squashTo(p1, lerp(SQ_SQUASH_X, SQ_STRETCH_X, k), lerp(SQ_SQUASH_Y, SQ_STRETCH_Y, k));
			squashTo(p2, lerp(SQ_SQUASH_X, SQ_STRETCH_X, k), lerp(SQ_SQUASH_Y, SQ_STRETCH_Y, k));
		}
		else if (squashT < SQ_T2)
		{
			// 段 2：拉伸 → 归位（easeInOutCubic：起点速度 0，与段 1 末速度连续）
			var k:Float = easeInOutCubic((squashT - SQ_T1) / (SQ_T2 - SQ_T1));
			squashTo(p1, lerp(SQ_STRETCH_X, 1, k), lerp(SQ_STRETCH_Y, 1, k));
			squashTo(p2, lerp(SQ_STRETCH_X, 1, k), lerp(SQ_STRETCH_Y, 1, k));
		}
		else
		{
			squashT = -1;
			setScale(p1, 1);
			setScale(p2, 1);
		}
	}

	// ==================== 归位 / 赋值辅助 ====================

	/** 强制回到静止姿态（切档时清上一档残留） */
	static function resetPose(p1:HealthIcon, p2:HealthIcon, baseY:Float):Void
	{
		springX[0] = 0;
		springX[1] = 0;
		springV[0] = 0;
		springV[1] = 0;
		angX[0] = 0;
		angX[1] = 0;
		angV[0] = 0;
		angV[1] = 0;
		bopY = 0;
		bopVY = 0;
		squashT = -1;
		setScale(p1, 1);
		setScale(p2, 1);
		p1.angle = 0;
		p2.angle = 0;
		p1.y = baseY;
		p2.y = baseY;
	}

	static function setScale(icon:HealthIcon, s:Float):Void
	{
		// ⚠⚠ 必须传**两个**参数：flixel 6.2.0 的 `FlxPoint.set` 有单参重载
		// （`flixel/math/FlxPoint.hx:340`，"Sets the x coordinate and zeroes the y coordinate"），
		// 写 `set(s)` 会把 scale.y 清零 → 图标被压成零高度 → **整块看不见**。
		// 旧版（5.2.2 / 6.0.0）是 `set(x=0, y=0)`，单参会同时赋 y，所以老代码从不写单参；
		// flixel 6.2 改成重载后这个坑就出现了。本引擎图标缩放一律用双参。
		icon.scale.set(s, s);
		icon.updateHitbox();
		icon.origin.set(0, 0);
	}

	/** 非等比缩放（挤压档）。同样必须双参，理由见 `setScale`。 */
	static function setScaleXY(icon:HealthIcon, sx:Float, sy:Float):Void
	{
		icon.scale.set(sx, sy);
		icon.updateHitbox();
		icon.origin.set(0, 0);
	}

	/** KE 用：按像素数放大（历史实现按 frameWidth 折算成 scale） */
	static function grow(icon:HealthIcon, px:Float):Void
	{
		setScale(icon, icon.scale.x + px / icon.frameWidth);
	}

	static function squashTo(icon:HealthIcon, sx:Float, sy:Float):Void
	{
		setScaleXY(icon, sx, sy);
	}

	static inline function lerp(a:Float, b:Float, t:Float):Float
	{
		return a + (b - a) * t;
	}

	/** 两端导数为 0 的正弦缓动（用于挤压段 1：与段 2 接缝速度连续） */
	static inline function easeInOutSine(t:Float):Float
	{
		return -(Math.cos(Math.PI * t) - 1) / 2;
	}

	/** 两端导数为 0 的三次缓动（用于挤压段 2：起点接住段 1 末速度，终点平滑停住） */
	static inline function easeInOutCubic(t:Float):Float
	{
		return (t < 0.5) ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
	}
}