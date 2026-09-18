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

	static final TOGGLE_W:Float = 96;            // 开关胶囊 96×32（实现见 objects.ToggleSwitch，圆钮/夹取参数都在那边）
	static final TOGGLE_H:Float = 32;
	static final TOGGLE_HIT_W:Float = 260;       // 开关的触控热区（含文字，≥56 高由行高保证）

	var content:FlxSpriteGroup;
	var panel:FlxSprite;
	var scrim:FlxSprite;

	var btnDownload:UIButton;
	var btnIgnore:UIButton;

	/** 开关本体：与设置界面共用 objects.ToggleSwitch（圆钮坐标模型 + 原地重绘都封在组件里） */
	var toggleSw:objects.ToggleSwitch;
	var toggleLabel:FlxText;      // 「稍后提醒 / 不再提示」
	var toggleHint:FlxText;       // 说明：当前这个开关的含义

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

		toggleSw = new objects.ToggleSwitch(tglX, tglY);
		for (spr in toggleSw.sprites) content.add(spr);

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

		// 开关滑块：坐标模型与插值都封在 objects.ToggleSwitch 里（"圆点飞出"的修复随之固化）
		if (toggleSw != null) toggleSw.animate(elapsed);

		super.update(elapsed);
	}

	// ───────────────────────── 开关 ─────────────────────────

	function overToggle(mx:Float, my:Float):Bool
	{
		return toggleSw != null
			&& mx >= toggleSw.track.x - 12 && mx <= toggleSw.track.x + TOGGLE_HIT_W
			&& my >= toggleSw.track.y - 12 && my <= toggleSw.track.y + TOGGLE_H + 12;
	}

	/** 翻转「稍后提醒 / 不再提示」并落盘。 */
	function flipToggle():Void
	{
		ClientPrefs.data.updateNotify = !ClientPrefs.data.updateNotify;
		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refreshToggle();
	}

	/** 刷新开关外观（文案 / 胶囊底 / 圆钮圆心目标），颜色全部走令牌。 */
	function refreshToggle():Void
	{
		var on:Bool = ClientPrefs.data.updateNotify;

		toggleLabel.text = on ? '稍后提醒' : '不再提示';
		toggleLabel.color = on ? FlxColor.WHITE : DesignTokens.secondary;

		// 轨道重绘 / 圆钮目标 / 首次落位全在组件内，这里只喂状态
		if (toggleSw != null) toggleSw.setOn(on);

		// 轨道重绘（开 = primary 填充、关 = 深底+描边）与圆钮落位已移入 objects.ToggleSwitch.setOn()
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
		if (toggleSw != null) toggleSw.destroy();
		toggleSw = null;
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
