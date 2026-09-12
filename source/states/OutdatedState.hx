package states;

import flixel.util.FlxSpriteUtil;
import objects.UIButton;
import openfl.Lib;

/**
 * 更新提示界面（系统域 · MD3 令牌）。
 *
 * 设计依据：skills/meteoric-design（系统域：圆角磨砂面板 + scrim 压暗 + MD3 按钮语义 +
 * 250ms quadOut 入场）+ skills/meteoric-system（三套输入、触控目标 ≥56）。
 *
 * 版式（用户指定：仍是"一个大窗口"）：
 *   ┌────────────────────────────── 900×520 单面板 ──────────────────────────────┐
 *   │                      发现新版本！                    （30 白）              │
 *   │   当前版本 1.1.2            →            最新版本 1.1.3                     │
 *   │   （次级色 onSurfaceVariant）     箭头（主题色）     （主题色 primary，32）  │
 *   │                    请尽快升级到最新的 ME 引擎          （onSurfaceVariant） │
 *   │   [ 前往下载更新 ]（filled）   [ 忽略更新 ]（tonal）                          │
 *   │   稍后提醒 / 不再提示  [ 开关 ]                                              │
 *   │   Enter 前往下载 · Esc 忽略 · 点击开关切换提醒                                │
 *   └────────────────────────────────────────────────────────────────────────────┘
 *
 * 相对旧版的改动（旧版问题：纯文字当链接、无 scrim、面板 960×560、字号体系混乱）：
 *  ① 两条文字链接 → **真按钮**（objects/UIButton，filled / tonal 语义，悬停叠 0x18 白、按下叠 0x30 白 + 缩放 0.97）。
 *  ② 背景 menuBG（手绘域）→ menuDesat 染主题色 + 0.6 黑遮罩（系统域弹层必须压暗）。
 *  ③ 新增「稍后提醒 / 不再提示」开关，写 ClientPrefs.data.updateNotify；关闭后不再弹本界面。
 *  ④ 字号/间距/圆角全部按令牌：标题 30、版本行 32、说明 20、提示 16；面板圆角 22、按钮 14、触控高 56。
 *  ⑤ 入场：面板 α + 上移 12px，单组 tween 250ms quadOut（并发动效 1 组，符合移动端红线）；
 *     出场 200ms quadIn；键盘初始化动作不等待动画（interactable 之前只吞输入）。
 */
class OutdatedState extends MusicBeatState
{
	public static var leftState:Bool = false;

	// ===== 布局（1280×720 基准） =====
	static final PANEL_W:Float = 900;
	/** 面板高度：按窗口取小值，保证 720 与非 720 窗口都不溢出（上下各留 24px） */
	static function panelHeight():Float
	{
		return Math.min(520, FlxG.height - 48);
	}
	static final PAD:Float = 40;                 // 面板内边距
	static final PANEL_BOTTOM:Float = 648;       // 安全底线

	static final BTN_W:Float = 300;
	static final BTN_H:Float = 56;               // 触控目标 ≥56
	static final BTN_GAP:Float = 24;

	static final TOGGLE_W:Float = 96;            // 开关（pill）
	static final TOGGLE_H:Float = 32;
	static final TOGGLE_HIT_W:Float = 260;       // 开关的触控热区（含文字，≥56 高由行高保证）
	/** 圆钮直径（= 22；圆钮比胶囊小 10px，所以半径 11 **不等于**胶囊半径 16） */
	static final KNOB_D:Float = TOGGLE_H - 10;
	static final KNOB_R:Float = KNOB_D * 0.5;
	/** 圆钮**圆心**在轨道内的活动范围（轨道内坐标）：[16, 80] —— 夹取必须夹圆心，不是夹精灵左边框 */
	static final KNOB_C_MIN:Float = TOGGLE_H * 0.5;
	static final KNOB_C_MAX:Float = TOGGLE_W - TOGGLE_H * 0.5;

	var content:FlxSpriteGroup;
	var panel:FlxSprite;
	var scrim:FlxSprite;

	var btnDownload:UIButton;
	var btnIgnore:UIButton;

	var toggleTrack:FlxSprite;    // 开关底（pill）
	var toggleKnob:FlxSprite;     // 开关圆钮
	var toggleLabel:FlxText;      // 「稍后提醒 / 不再提示」
	var toggleHint:FlxText;       // 说明：当前这个开关的含义
	var toggleKnobX:Float = 0;    // 圆钮**圆心**目标（轨道内坐标：开 = 80 / 关 = 16）
	var knobCenter:Float = 0;     // 圆钮圆心当前值（插值在**圆心空间**做，再换算成精灵 x）
	var knobPlaced:Bool = false;  // 圆钮是否已落位（首帧直接落位，避免从错误初值滑入）
	#if meteoric_debug
	var _dbgFrames:Int = 0;       // 【临时探针】帧计数
	#end
	var toggleTween:FlxTween;

	var focusIdx:Int = 0;         // 键盘焦点：0=下载 1=忽略 2=开关
	var interactable:Bool = false;
	var fading:Bool = false;
	var leftMX:Float = -9999;     // 鼠标移动唤醒（避免开界面就高亮）
	var leftMY:Float = -9999;
	var mouseAwake:Bool = false;

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		super.create();

		Lib.application.window.title = "FNF':Meteoric Engine - Outdated Version";
		leftState = false;

		// ---- 背景：系统域（menuDesat 染主题色 + 压暗遮罩）----
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = DesignTokens.menuTint;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.screenCenter();
		add(bg);

		scrim = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		scrim.alpha = 0.6; // 弹层必须压暗（skill 硬性规则）
		scrim.scrollFactor.set();
		add(scrim);

		// ---- 面板 ----
		var PANEL_H:Float = panelHeight();
		var px:Float = (FlxG.width - PANEL_W) * 0.5;
		var py:Float = (FlxG.height - PANEL_H) * 0.5;

		content = new FlxSpriteGroup();
		panel = makePanel(px, py, PANEL_W, PANEL_H, 22);
		content.add(panel);

		// ---- 标题 ----
		content.add(makeText(px, py + PAD + 4, PANEL_W, '发现新版本！', 30, FlxColor.WHITE));

		// ---- 版本对比：左「当前」→ 右「最新」 ----
		var rowY:Float = py + 132;
		var half:Float = PANEL_W * 0.5;

		var curCaption:FlxText = makeText(px, rowY, half, '当前版本', 18, 0xFFD7D7E0);
		curCaption.color = 0xFFD7D7E0;
		content.add(curCaption);
		content.add(makeText(px, rowY + 26, half, Main.meVersion, 32, FlxColor.WHITE));

		// 中间箭头：主题色，表意"升级方向"
		var arrow:FlxText = new FlxText(px + half - 20, rowY + 24, 40, '→', 32);
		arrow.setFormat(Paths.font('future.ttf'), 32, DesignTokens.primary, CENTER);
		arrow.scrollFactor.set();
		content.add(arrow);

		var remoteVer:String = (TitleState.updateVersion != null && TitleState.updateVersion.length > 0)
			? TitleState.updateVersion : '—';

		var newCaption:FlxText = makeText(px + half, rowY, half, '最新版本', 18, 0xFFD7D7E0);
		content.add(newCaption);
		content.add(makeText(px + half, rowY + 26, half, remoteVer, 32, DesignTokens.primary));

		// ---- 说明文字（次级色，不抢标题） ----
		content.add(makeText(px + PAD, rowY + 96, PANEL_W - PAD * 2, '请尽快升级到最新的 Meteoric Engine，以获得新功能与问题修复。', 20, 0xFFD7D7E0));

		// ---- 两个按钮（旧版的文字链接 → 真按钮）----
		var btnY:Float = py + PANEL_H - 208;
		var totalW:Float = BTN_W * 2 + BTN_GAP;
		var btnX:Float = px + (PANEL_W - totalW) * 0.5;

		btnDownload = new UIButton(btnX, btnY, BTN_W, BTN_H, '前往下载更新', UIButton.VARIANT_FILLED, goDownload);
		btnIgnore = new UIButton(btnX + BTN_W + BTN_GAP, btnY, BTN_W, BTN_H, '忽略更新', UIButton.VARIANT_TONAL, goNext);
		content.add(btnDownload);
		content.add(btnIgnore);

		// ---- 「稍后提醒 / 不再提示」开关 ----
		var tglY:Float = btnY + BTN_H + 40;
		var tglX:Float = px + (PANEL_W - (TOGGLE_W + 16 + 190)) * 0.5; // 开关 + 间距 + 文字，整组居中

		toggleTrack = new FlxSprite(tglX, tglY);
		toggleTrack.scrollFactor.set();
		content.add(toggleTrack);

		toggleKnob = new FlxSprite(0, 0);
		toggleKnob.scrollFactor.set();
		content.add(toggleKnob);

		toggleLabel = new FlxText(tglX + TOGGLE_W + 16, tglY + 4, 190, '', 22);
		toggleLabel.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, LEFT);
		toggleLabel.scrollFactor.set();
		content.add(toggleLabel);

		toggleHint = makeText(px + PAD, tglY + 40, PANEL_W - PAD * 2,
			'关闭后本提示不再弹出（可在设置里重新打开检测更新）', 16, 0xFF9A9AA8);
		content.add(toggleHint);

		// ---- 底部操作提示（面板内坐标：py 是面板顶，绝不能再拿"屏幕绝对底线"当相对偏移）----
		content.add(makeText(px, py + PANEL_H - 44, PANEL_W, 'Enter 前往下载 · Esc 忽略 · 点击开关切换提醒', 16, 0xFF9A9AA8));

		add(content);

		FlxG.mouse.visible = true;
		refreshToggle();

		// ---- 入场：α + 上移 12px，单组 tween 250ms quadOut ----
		content.alpha = 0;
		content.y = 12;
		FlxTween.tween(content, {alpha: 1, y: 0}, 0.25, {
			ease: FlxEase.quadOut,
			onComplete: function(_) interactable = true
		});
	}

	override function update(elapsed:Float)
	{
		if (!leftState && !fading && interactable)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;

			// 鼠标移动唤醒（首次移动只记录，不高亮）
			if (mx != leftMX || my != leftMY)
			{
				leftMX = mx;
				leftMY = my;
				if (mouseAwake)
				{
					btnDownload.setHovered(mx, my);
					btnIgnore.setHovered(mx, my);
				}
				else
				{
					mouseAwake = true;
					btnDownload.setHovered(mx, my);
					btnIgnore.setHovered(mx, my);
				}
			}

			// 鼠标/触控：按下
			if (FlxG.mouse.justPressed)
			{
				if (btnDownload.over(mx, my))
				{
					btnDownload.setPressed(true);
					goDownload();
				}
				else if (btnIgnore.over(mx, my))
				{
					btnIgnore.setPressed(true);
					goNext();
				}
				else if (overToggle(mx, my))
				{
					flipToggle();
				}
			}
			if (FlxG.mouse.justReleased)
			{
				btnDownload.setPressed(false);
				btnIgnore.setPressed(false);
			}

			// 键盘：←/→ 或 ↑/↓ 切焦点，Enter 触发焦点项，Esc 忽略
			if (controls.UI_LEFT_P || controls.UI_UP_P)
			{
				setFocus((focusIdx + 2) % 3);
				mouseAwake = false; // 键盘接管后需再次明显移动鼠标才恢复悬停
			}
			else if (controls.UI_RIGHT_P || controls.UI_DOWN_P)
			{
				setFocus((focusIdx + 1) % 3);
				mouseAwake = false; // 键盘接管后需再次明显移动鼠标才恢复悬停
			}

			if (controls.ACCEPT)
			{
				if (focusIdx == 0) goDownload();
				else if (focusIdx == 1) goNext();
				else flipToggle();
			}
			else if (controls.BACK) goNext();
		}

		// 开关圆钮（坐标模型，2026-09-12 修正）：
		//   · `toggleKnobX` / `knobCenter` 一律是**圆心在轨道内的坐标**（关 16 / 开 80）；
		//   · 精灵 x 由 knobXFromCenter() 换算：x = toggleTrack.x + 圆心 − 圆钮半径。
		//   轨道与圆钮是 content 的**同级子精灵**（x 同基准），必须显式加上 toggleTrack.x。
		//   从前把"轨道内相对量"直接写进 `toggleKnob.x`（16/80），圆钮就被画到屏幕左侧、
		//   距轨道 409px（实测探针 knob.x=80 / track.x=489）—— 这就是「圆点飞出」。
		#if meteoric_debug
		// 【临时探针】每 60 帧打一次；验收判据：dx 关态 = 5 / 开态 = 69（验证后连同本段删除）
		if (toggleKnob != null)
		{
			_dbgFrames++;
			if (_dbgFrames % 60 == 0)
				Sys.println('[TOGGLE] dx=' + Std.int(toggleKnob.x - toggleTrack.x)
					+ ' knob.x=' + Std.int(toggleKnob.x) + ' track.x=' + Std.int(toggleTrack.x)
					+ ' center=' + Std.int(knobCenter) + ' target=' + Std.int(toggleKnobX)
					+ ' knob.y=' + Std.int(toggleKnob.y) + ' track.y=' + Std.int(toggleTrack.y)
					+ ' on=' + ClientPrefs.data.updateNotify
					+ ' placed=' + knobPlaced);
		}
		#end
		if (toggleKnob != null)
		{
			if (!knobPlaced)
			{
				knobPlaced = true;
				knobCenter = clampCenter(toggleKnobX);
			}
			else
			{
				knobCenter = clampCenter(FlxMath.lerp(knobCenter, toggleKnobX, Math.min(1, elapsed * 18)));
			}
			toggleKnob.x = knobXFromCenter(knobCenter);
		}
		if (toggleKnob != null) syncKnobColor();

		super.update(elapsed);
	}

	// ───────────────────────── 开关 ─────────────────────────

	function overToggle(mx:Float, my:Float):Bool
	{
		return mx >= toggleTrack.x - 12 && mx <= toggleTrack.x + TOGGLE_HIT_W
			&& my >= toggleTrack.y - 12 && my <= toggleTrack.y + TOGGLE_H + 12;
	}

	/** 翻转「稍后提醒 / 不再提示」并落盘。 */
	function flipToggle():Void
	{
		ClientPrefs.data.updateNotify = !ClientPrefs.data.updateNotify;
		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refreshToggle();
	}

	/** 圆心（轨道内坐标）→ 子精灵 x。轨道与圆钮是 content 的**同级子精灵**，x 同基准。 */
	inline function knobXFromCenter(center:Float):Float
	{
		return toggleTrack.x + center - KNOB_R;
	}

	/** 把圆心夹进轨道有效区间（夹的是**圆心**，不是精灵左边框）。 */
	inline function clampCenter(c:Float):Float
	{
		return c < KNOB_C_MIN ? KNOB_C_MIN : (c > KNOB_C_MAX ? KNOB_C_MAX : c);
	}

	/** 刷新开关外观（文案 / 胶囊底 / 圆钮圆心目标），颜色全部走令牌。 */
	function refreshToggle():Void
	{
		var on:Bool = ClientPrefs.data.updateNotify;

		toggleLabel.text = on ? '稍后提醒' : '不再提示';
		toggleLabel.color = on ? FlxColor.WHITE : DesignTokens.secondary;

		// 胶囊底：原地重绘（先清后画）。
		// ⚠ 不能用 makeGraphic "重建"：尺寸不变时命中的是缓存里同一张 BitmapData，
		// 旧像素不会被清 → "开"态的 primary 填充会残留在"关"态胶囊上（同尺寸精灵还会互相串图）。
		if (toggleTrack.graphic == null)
			toggleTrack.makeGraphic(Std.int(TOGGLE_W), Std.int(TOGGLE_H), FlxColor.TRANSPARENT, true);
		else
			toggleTrack.pixels.fillRect(toggleTrack.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(toggleTrack, 0, 0, TOGGLE_W, TOGGLE_H, TOGGLE_H * 0.5, TOGGLE_H * 0.5,
			on ? DesignTokens.primary : 0x66161622);
		FlxSpriteUtil.drawRoundRect(toggleTrack, 1, 1, TOGGLE_W - 2, TOGGLE_H - 2, TOGGLE_H * 0.5, TOGGLE_H * 0.5,
			FlxColor.TRANSPARENT, {color: on ? DesignTokens.primary : DesignTokens.panelOutline, thickness: 1.5});
		toggleTrack.dirty = true;

		// 圆钮：圆心目标（开 80 / 关 16）；首次**直接落位**，之后由 update 在圆心空间插值。
		toggleKnobX = on ? KNOB_C_MAX : KNOB_C_MIN;
		if (toggleKnob.graphic == null)
		{
			knobCenter = clampCenter(toggleKnobX);
			toggleKnob.x = knobXFromCenter(knobCenter);
		}
		syncKnobColor();
	}

	/**
	 * 圆钮：白圆 + 与轨道**垂直居中**（水平位置由 update 在圆心空间插值后换算）。
	 *
	 * x/y 都是 content 组内的**同基准坐标**（轨道与圆钮是同级子精灵），所以：
	 *  · x 必须写 `toggleTrack.x + 圆心 − 圆钮半径` —— 直接把"轨道内相对量"写进来会让圆钮
	 *    被画到面板左边（实测：knob.x=80 而 track.x=489），即「圆点飞出」；
	 *  · y 用 `toggleTrack.y + (胶囊高 − 圆钮高)/2` 即可（两者同为组内坐标，不要额外加绝对偏移）。
	 * 圆钮位图同样 unique=true：否则可能命中别的 22×22 缓存位图、白圆会带着别人的残留。
	 */
	function syncKnobColor():Void
	{
		var kn:Float = KNOB_D;
		if (toggleKnob.graphic == null || toggleKnob.width != kn)
		{
			toggleKnob.makeGraphic(Std.int(kn), Std.int(kn), FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawCircle(toggleKnob, kn * 0.5, kn * 0.5, KNOB_R, 0xFFFFFFFF);
			toggleKnob.updateHitbox();
		}
		toggleKnob.y = toggleTrack.y + (TOGGLE_H - toggleKnob.height) * 0.5;
	}

	// ───────────────────────── 焦点 ─────────────────────────

	function setFocus(idx:Int):Void
	{
		focusIdx = idx;
		btnDownload.setFocused(idx == 0);
		btnIgnore.setFocused(idx == 1);
	}

	// ───────────────────────── 动作 ─────────────────────────

	/**
	 * 转场前显式复位「按下态」。
	 *
	 * 为什么必须手工复位：`update()` 的输入分支整体被 `!leftState && !fading && interactable` 门控，
	 * 而点击那一帧就 `setPressed(true)` 并在同一帧调用 goDownload()/goNext()（内部立刻置
	 * `leftState = true; fading = true;`）→ `FlxG.mouse.justReleased` 里的 `setPressed(false)`
	 * 永远执行不到，按钮会带着 0x30 白层 + 0.97 缩放僵在整段转场里（看着像"两个都亮"的残留态）。
	 */
	function clearPressed():Void
	{
		btnDownload.setPressed(false);
		btnIgnore.setPressed(false);
	}

	function goDownload():Void
	{
		if (fading) return;
		clearPressed();
		leftState = true;
		fading = true;
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
		fadeOut(function()
		{
			CoolUtil.browserLoad("https://github.com/Bonus-XK/FNF-MeteoricEngine/releases");
			MusicBeatState.switchState(new MainMenuState());
		});
	}

	function goNext():Void
	{
		if (fading) return;
		clearPressed();
		leftState = true;
		fading = true;
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.7);
		fadeOut(function()
		{
			MusicBeatState.switchState(new MainMenuState());
		});
	}

	function fadeOut(onComplete:Void->Void):Void
	{
		FlxTween.tween(content, {alpha: 0}, 0.2, {ease: FlxEase.quadIn, onComplete: function(_) onComplete()});
	}

	// ───────────────────────── 绘制工具 ─────────────────────────

	function makePanel(x:Float, y:Float, w:Float, h:Float, radius:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		spr.antialiasing = true;
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, DesignTokens.panelFill);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT,
			{color: DesignTokens.panelOutline, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, color:FlxColor):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('future.ttf'), size, color, CENTER);
		t.scrollFactor.set();
		return t;
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
