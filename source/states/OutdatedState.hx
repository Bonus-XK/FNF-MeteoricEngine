package states;

import flixel.util.FlxSpriteUtil;
import flixel.math.FlxRect;
import openfl.Lib;

class OutdatedState extends MusicBeatState
{
	public static var leftState:Bool = false;

	static final PANEL_W:Float = 960;
	static final PANEL_H:Float = 560;

	var content:FlxSpriteGroup;
	var links:Array<FlxText> = [];
	var linkRects:Array<FlxRect> = [];
	var linkColors:Array<FlxColor> = [];
	var mouseOnLinks:Array<Bool> = [false, false];

	var lastMX:Float = -9999;     // 上一帧鼠标位置（鼠标移动才判定悬停）
	var lastMY:Float = -9999;
	var hoverWarm:Bool = false;   // 首次移动鼠标后记录相对状态，不高亮
	var interactable:Bool = false; // 进场动画完成后才响应操作
	var fading:Bool = false;

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		super.create();
		Lib.application.window.title = "FNF':Meteoric Engine - Outdated Version";

		// 与主界面一致的背景图
		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		// 内容组仅用于整体淡入淡出，成员全部用绝对坐标
		content = new FlxSpriteGroup();
		var px:Float = (FlxG.width - PANEL_W) / 2;
		var py:Float = (FlxG.height - PANEL_H) / 2;

		// 圆角磨砂面板
		var panel:FlxSprite = makePanel(px, py, PANEL_W, PANEL_H, 22);
		content.add(panel);

		content.add(makeText(px, py + 40, PANEL_W, "发现新版本！", 48, 0xFFFF4D5E));
		content.add(makeText(px, py + 140, PANEL_W, "当前版本：" + Main.meVersion, 32, FlxColor.WHITE));
		content.add(makeText(px, py + 200, PANEL_W, "最新版本：" + TitleState.updateVersion, 32, 0xFFFFD93D));
		content.add(makeText(px, py + 268, PANEL_W, "请尽快升级到最新的 ME 引擎！", 28, 0xFFFF9A9A));

		// 文字链接（整行可点击，悬停高亮）
		addLink(px, py + 360, PANEL_W, "> 前往 Github 下载更新", 0xFF9CE8FF);
		addLink(px, py + 452, PANEL_W, "> 忽略更新", 0xFFFFD9A0);

		content.add(makeText(px, py + PANEL_H - 40, PANEL_W, "Enter 前往下载 · Esc 忽略", 22, 0xFF6A7585));

		add(content);

		FlxG.mouse.visible = true;

		// 进场淡入，动画结束后才可交互
		content.alpha = 0;
		FlxTween.tween(content, {alpha: 1}, 0.5, {ease: FlxEase.quadOut, onComplete: function(twn:FlxTween)
		{
			interactable = true;
		}});
	}

	override function update(elapsed:Float)
	{
		if (!leftState && !fading && interactable)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;

			// 只有鼠标移动时才更新悬停：进入界面时即使停在链接上也不会高亮
			if (mx != lastMX || my != lastMY)
			{
				lastMX = mx;
				lastMY = my;

				if (!hoverWarm)
				{
					// 首次移动：只记录鼠标与链接的相对状态，不高亮
					hoverWarm = true;
					mouseOnLinks[0] = overLink(0);
					mouseOnLinks[1] = overLink(1);
				}
				else
				{
					// 鼠标从链接外部移入才高亮
					for (i in 0...links.length)
					{
						var on:Bool = overLink(i);
						if (on && !mouseOnLinks[i]) setLinkHovered(i, true);
						else if (!on && mouseOnLinks[i]) setLinkHovered(i, false);
						mouseOnLinks[i] = on;
					}
				}
			}

			if (FlxG.mouse.justPressed)
			{
				if (overLink(0)) goDownload();
				else if (overLink(1)) goNext();
			}

			if (controls.ACCEPT) goDownload();
			else if (controls.BACK) goNext();
		}
		super.update(elapsed);
	}

	function setLinkHovered(idx:Int, hovered:Bool)
	{
		links[idx].color = hovered ? 0xFFFFFFFF : linkColors[idx];
	}

	function overLink(idx:Int):Bool
	{
		var r:FlxRect = linkRects[idx];
		return FlxG.mouse.screenX >= r.x && FlxG.mouse.screenX <= r.x + r.width
			&& FlxG.mouse.screenY >= r.y && FlxG.mouse.screenY <= r.y + r.height;
	}

	function addLink(x:Float, y:Float, w:Float, text:String, color:FlxColor)
	{
		var t:FlxText = new FlxText(x, y, w, text, 40);
		t.setFormat(Paths.font("future.ttf"), 40, color, CENTER, FlxTextBorderStyle.OUTLINE, 0x66000000);
		t.borderSize = 2;
		t.antialiasing = true;
		content.add(t);
		links.push(t);
		linkColors.push(color);
		var tw:Float = t.width;
		linkRects.push(new FlxRect(x + (w - tw) / 2, y, tw, t.height));
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, radius:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		spr.antialiasing = true;
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, 0xCC161622, {color: 0x45FFFFFF, thickness: 1.5});
		FlxSpriteUtil.drawRoundRect(spr, 14, 12, w - 28, 10, 5, 5, 0x1EFFFFFF);
		return spr;
	}

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, color:FlxColor):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font("future.ttf"), size, color, CENTER);
		return t;
	}

	function goDownload()
	{
		if (fading) return;
		leftState = true;
		fading = true;
		FlxG.sound.play(Paths.sound('confirmMenu'));
		fadeOut(function() {
			CoolUtil.browserLoad("https://github.com/Bonus-XK/FNF-MeteoricEngine/releases");
			MusicBeatState.switchState(new MainMenuState());
		});
	}

	function goNext()
	{
		if (fading) return;
		leftState = true;
		fading = true;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		fadeOut(function() {
			MusicBeatState.switchState(new MainMenuState());
		});
	}

	function fadeOut(onComplete:Void->Void)
	{
		FlxTween.tween(content, {alpha: 0}, 0.6, {ease: FlxEase.quadIn, onComplete: function(twn:FlxTween) onComplete()});
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
