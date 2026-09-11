package backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flixel.tweens.FlxTween;
import flixel.addons.ui.FlxInputText;
import backend.MusicBeatSubstate;
import states.ModsMenuState.ModsButton;

/**
 * 拖入安装 mod 的覆盖界面（磨砂玻璃样式，与 Mods 菜单删除确认框统一）：
 *  - progress 模式：解压 / 安装进度（圆角进度条 + 百分比 + 当前文件）
 *  - prompt 模式：给内层叫 "mods" 的 mod 起名字
 *  - result 模式：成功 / 失败提示（OK / X 图标）
 * 显示状态每帧从 ModInstaller 拉取；开着时每帧泵后台解压线程消息。
 */
class ModInstallUI extends MusicBeatSubstate
{
	// ---- 布局（面板居中，随分辨率缩放）----
	static inline var CARD_W:Int = 760;
	static inline var CARD_H:Int = 500;
	static inline var BAR_W:Int = 520;
	static inline var BAR_H:Int = 16;

	var bg:FlxSprite;
	var card:FlxSprite;
	var titleText:FlxText;
	var statusText:FlxText;
	var detailText:FlxText;
	var percentText:FlxText;
	var barBG:FlxSprite;
	var barFill:FlxSprite;
	var indeterminateBar:FlxSprite;
	var indeterminateDir:Int = 1;
	var promptText:FlxText;
	var promptError:FlxText;
	var inputText:FlxInputText;
	var resultIcon:FlxText;
	var resultText:FlxText;
	var okButton:ModsButton;
	var cancelButton:ModsButton;

	var mode:String = 'progress'; // progress | prompt | result
	var inputFocusRequested:Bool = false;

	public function new()
	{
		super();
	}

	override function create()
	{
		var W:Int = FlxG.width;
		var H:Int = FlxG.height;
		var cx:Int = Std.int((W - CARD_W) / 2);
		var cy:Int = Std.int((H - CARD_H) / 2);

		// ---- 全屏暗化（磨砂玻璃感）----
		bg = new FlxSprite().makeGraphic(W, H, 0xB3000000);
		bg.scrollFactor.set(0, 0);
		add(bg);

		// ---- 中央圆角面板 ----
		card = new FlxSprite(cx, cy).makeGraphic(CARD_W, CARD_H, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(card, 0, 0, CARD_W, CARD_H, 20, 20, 0xEE161622);
		FlxSpriteUtil.drawRoundRect(card, 1, 1, CARD_W - 2, CARD_H - 2, 20, 20, FlxColor.TRANSPARENT, {color: 0x66FFFFFF, thickness: 1.5});
		// 标题下方分隔线
		FlxSpriteUtil.drawRect(card, 24, 116, CARD_W - 48, 1, 0x33FFFFFF);
		card.scrollFactor.set(0, 0);
		card.alpha = 0;
		add(card);
		FlxTween.tween(card, {alpha: 1}, 0.18);

		// ---- 标题 ----
		titleText = new FlxText(cx, cy + 26, CARD_W, '', 30);
		titleText.scrollFactor.set(0, 0);
		titleText.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(titleText);

		// ---- 状态 ----
		statusText = new FlxText(cx, cy + 138, CARD_W, '', 22);
		statusText.scrollFactor.set(0, 0);
		statusText.setFormat(Paths.font('future.ttf'), 22, 0xFFD7D7E0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(statusText);

		// ---- 圆角进度条 ----
		var barX:Int = Std.int(W / 2 - BAR_W / 2);
		var barY:Int = cy + 200;
		barBG = new FlxSprite(barX, barY).makeGraphic(BAR_W, BAR_H, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(barBG, 0, 0, BAR_W, BAR_H, 8, 8, 0x66161622);
		FlxSpriteUtil.drawRoundRect(barBG, 1, 1, BAR_W - 2, BAR_H - 2, 8, 8, FlxColor.TRANSPARENT, {color: 0x44FFFFFF, thickness: 1});
		barBG.scrollFactor.set(0, 0);
		add(barBG);

		barFill = new FlxSprite(barX + 2, barY + 2).makeGraphic(BAR_W - 4, BAR_H - 4, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(barFill, 0, 0, BAR_W - 4, BAR_H - 4, 6, 6, 0xFF7BFF9E);
		barFill.scrollFactor.set(0, 0);
		barFill.scale.x = 0;
		add(barFill);

		indeterminateBar = new FlxSprite(barX + 2, barY + 2).makeGraphic(90, BAR_H - 4, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(indeterminateBar, 0, 0, 90, BAR_H - 4, 6, 6, 0xFF7BFF9E);
		indeterminateBar.scrollFactor.set(0, 0);
		indeterminateBar.visible = false;
		add(indeterminateBar);

		percentText = new FlxText(barX + BAR_W + 14, barY - 4, 60, '', 16);
		percentText.scrollFactor.set(0, 0);
		percentText.setFormat(Paths.font('future.ttf'), 16, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(percentText);

		// ---- 当前解压文件 ----
		detailText = new FlxText(cx + 40, cy + 240, CARD_W - 80, '', 15);
		detailText.scrollFactor.set(0, 0);
		detailText.setFormat(Paths.font('future.ttf'), 15, 0xFFA9A9B8, CENTER);
		detailText.visible = false;
		add(detailText);

		// ---- prompt：起名 ----
		promptText = new FlxText(cx, cy + 130, CARD_W, '', 22);
		promptText.scrollFactor.set(0, 0);
		promptText.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		promptText.visible = false;
		add(promptText);

		inputText = new FlxInputText(Std.int(W / 2 - 250), cy + 195, 500, '', 20, FlxColor.WHITE, 0xFF1E1E28, true);
		inputText.scrollFactor.set(0, 0);
		inputText.visible = false;
		inputText.font = Paths.font('future.ttf');
		inputText.maxLength = 80;
		add(inputText);

		promptError = new FlxText(cx, cy + 258, CARD_W, '', 15);
		promptError.scrollFactor.set(0, 0);
		promptError.setFormat(Paths.font('future.ttf'), 15, 0xFFFF6B6B, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		promptError.visible = false;
		add(promptError);

		// ---- result：结果 ----
		resultIcon = new FlxText(cx, cy + 118, CARD_W, '', 68);
		resultIcon.scrollFactor.set(0, 0);
		resultIcon.setFormat(Paths.font('future.ttf'), 68, 0xFF7BFF9E, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		resultIcon.visible = false;
		add(resultIcon);

		resultText = new FlxText(cx + 60, cy + 210, CARD_W - 120, '', 19);
		resultText.scrollFactor.set(0, 0);
		resultText.setFormat(Paths.font('future.ttf'), 19, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		resultText.visible = false;
		add(resultText);

		// ---- 圆角磨砂按钮（与 Mods 菜单同一组件）----
		cancelButton = new ModsButton(0, 0, 160, 44, '取消', function() ModInstaller.get().cancelTask());
		add(cancelButton);
		okButton = new ModsButton(0, 0, 160, 44, '确定', function() onOk());
		add(okButton);

		super.create();
	}

	override function update(elapsed:Float)
	{
		var m:ModInstaller = ModInstaller.get();
		ModInstaller.update(elapsed); // 泵后台解压线程消息

		// --- 与管理器状态同步 ---
		titleText.text = m.title;

		if (m.showPrompt)
		{
			mode = 'prompt';
			showPromptMode(m);
		}
		else if (m.showResult)
		{
			mode = 'result';
			showResultMode(m);
		}
		else
		{
			mode = 'progress';
			showProgressMode(m);
		}

		// --- 按钮交互（ModsButton 无内置点击处理，需手动检测）---
		for (btn in [okButton, cancelButton])
		{
			if (!btn.visible) continue;
			btn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
			if (FlxG.mouse.justPressed && btn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
			{
				btn.onClick();
				return;
			}
		}

		// --- 键盘 ---
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.BACKSPACE)
		{
			handleCancel();
		}

		if (mode == 'prompt' && (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.TAB))
		{
			confirmInput();
		}

		super.update(elapsed);
	}

	function showProgressMode(m:ModInstaller):Void
	{
		statusText.visible = true;
		statusText.text = m.status;
		detailText.visible = m.detailText != null && m.detailText.length > 0;
		detailText.text = detailText.visible ? truncate(m.detailText, 90) : '';

		promptText.visible = false;
		promptError.visible = false;
		inputText.visible = false;
		resultIcon.visible = false;
		resultText.visible = false;

		barBG.visible = true;
		if (m.indeterminate)
		{
			barFill.visible = false;
			indeterminateBar.visible = true;
			percentText.text = '';
			indeterminateBar.x += 4 * indeterminateDir;
			var left:Float = barBG.x + 2;
			var right:Float = barBG.x + barBG.width - 2 - indeterminateBar.width;
			if (indeterminateBar.x > right)
			{
				indeterminateBar.x = right;
				indeterminateDir = -1;
			}
			else if (indeterminateBar.x < left)
			{
				indeterminateBar.x = left;
				indeterminateDir = 1;
			}
		}
		else
		{
			barFill.visible = true;
			indeterminateBar.visible = false;
			barFill.scale.x = Math.max(0, Math.min(1, m.progress));
			percentText.text = Std.int(m.progress * 100) + '%';
		}

		okButton.visible = false;
		cancelButton.visible = m.canCancel;
		cancelButton.setText('取消');
		cancelButton.x = FlxG.width / 2 - 80;
		cancelButton.y = card.y + CARD_H - 66;
	}

	function showPromptMode(m:ModInstaller):Void
	{
		statusText.visible = false;
		detailText.visible = false;
		barBG.visible = false;
		barFill.visible = false;
		indeterminateBar.visible = false;
		percentText.text = '';

		promptText.visible = true;
		promptText.text = m.promptMessage;
		resultIcon.visible = false;
		resultText.visible = false;

		inputText.visible = true;
		if (!inputFocusRequested)
		{
			inputFocusRequested = true;
			inputText.text = m.promptDefault;
			focusInput();
		}

		okButton.visible = true;
		okButton.setText('确定');
		okButton.x = FlxG.width / 2 - 190;
		okButton.y = card.y + CARD_H - 66;
		cancelButton.visible = true;
		cancelButton.setText('取消');
		cancelButton.x = FlxG.width / 2 + 30;
		cancelButton.y = card.y + CARD_H - 66;
	}

	function showResultMode(m:ModInstaller):Void
	{
		statusText.visible = false;
		detailText.visible = false;
		barBG.visible = false;
		barFill.visible = false;
		indeterminateBar.visible = false;
		percentText.text = '';
		promptText.visible = false;
		promptError.visible = false;
		inputText.visible = false;

		var isSuccess:Bool = (m.title == '安装完成' || m.title == '下载完成');
		resultIcon.visible = true;
		// 用 ASCII 的 OK/X：future.ttf 没有 ✓(U+2713) / ✗(U+2717) 字形
		resultIcon.text = isSuccess ? 'OK' : 'X';
		resultIcon.color = isSuccess ? 0xFF7BFF9E : 0xFFFF6B6B;
		resultText.visible = true;
		resultText.text = m.resultMessage;
		resultText.screenCenter(X);
		resultText.y = card.y + 215;

		okButton.visible = true;
		okButton.setText('好的');
		okButton.x = FlxG.width / 2 - 80;
		okButton.y = card.y + CARD_H - 66;
		cancelButton.visible = false;
	}

	function confirmInput():Void
	{
		ModInstaller.get().confirmName(inputText.text);
	}

	function handleCancel():Void
	{
		var m:ModInstaller = ModInstaller.get();
		if (mode == 'prompt')
		{
			m.cancelPrompt();
		}
		else if (mode == 'progress' && m.busy && m.canCancel)
		{
			m.cancelTask();
		}
		else if (mode == 'result')
		{
			closeMe();
		}
	}

	function onOk():Void
	{
		if (mode == 'prompt')
			confirmInput();
		else if (mode == 'result')
			closeMe();
	}

	function closeMe():Void
	{
		if (inputText != null && inputText.hasFocus) inputText.hasFocus = false;
		close();
	}

	public function focusInput():Void
	{
		if (inputText != null)
		{
			inputText.hasFocus = true;
		}
	}

	public function showPromptError(msg:String):Void
	{
		promptError.text = msg;
		promptError.visible = true;
	}

	static function truncate(s:String, max:Int):String
	{
		if (s.length <= max) return s;
		return s.substr(0, max - 3) + '…';
	}

	override function close()
	{
		ModInstaller.get().onUIClosed();
		super.close();
	}
}
