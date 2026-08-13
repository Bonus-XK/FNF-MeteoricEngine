package states;

#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end

import objects.BackButton;
import openfl.Lib;
import flixel.util.FlxSpriteUtil;

class CreditsState extends MusicBeatState
{
	// ===== 布局常量 =====
	static final PANEL_L_X:Float = 40;
	static final PANEL_L_Y:Float = 70;
	static final PANEL_L_W:Float = 680;
	static final PANEL_L_H:Float = 570;

	static final PANEL_R_X:Float = 740;
	static final PANEL_R_Y:Float = 70;
	static final PANEL_R_W:Float = 460;
	static final PANEL_R_H:Float = 570;

	static final LIST_X:Float = 88;      // 列表文字 X
	static final LIST_Y:Float = 152;     // 第一行 Y
	static final ROW_GAP:Float = 56;     // 行距
	static final ROWS_VISIBLE:Int = 8;   // 可见行数

	static final ICON_X:Float = 890;     // 右侧大图标（居中）
	static final ICON_Y:Float = 170;
	static final ICON_SIZE:Float = 160;

	var curSelected:Int = -1;
	var scrollIndex:Int = 0;

	var creditsStuff:Array<Array<String>> = [];
	var rows:Array<FlxText> = [];

	var bg:FlxSprite;
	var intendedColor:FlxColor;
	var colorTween:FlxTween;

	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

	var iconSpr:FlxSprite;
	var iconLetter:FlxText;
	var nameText:FlxText;
	var descText:FlxText;
	var linkText:FlxText;

	var backBtn:BackButton;

	var mouseActive:Bool = true;  // 鼠标活跃：滚轮/点击可用；键盘操作后冻结
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var quitting:Bool = false;
	var holdTime:Float = 0;

	override function create()
	{
		// 进入界面时自动清理 RAM（先清理再加载，避免误删当前界面资源）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Lib.application.window.title = "FNF':Meteoric Engine - Credits";

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		persistentUpdate = true;
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();

		// ---- 圆角磨砂面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 662, 1160, 48, 14));

		// ---- 面板标题 ----
		addTitle(PANEL_L_X + 48, 100, '制作人员');
		addTitle(PANEL_R_X + 32, 100, '成员信息');

		// ---- 列表行（静态行：切换时只移动高亮条，行本身不滑动） ----
		for (r in 0...ROWS_VISIBLE)
		{
			var row:FlxText = new FlxText(LIST_X, LIST_Y + (r * ROW_GAP), 0, '', 26);
			row.setFormat(Paths.font('future.ttf'), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			row.borderSize = 2;
			row.antialiasing = ClientPrefs.data.antialiasing;
			row.scrollFactor.set();
			row.visible = false;
			add(row);
			rows.push(row);
		}

		// ---- 选中高亮条（只做视觉，不悬停切换） ----
		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, 0x2EFFFFFF, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 右侧：大图标 ----
		iconSpr = new FlxSprite(ICON_X, ICON_Y);
		iconSpr.antialiasing = ClientPrefs.data.antialiasing;
		iconSpr.scrollFactor.set();
		add(iconSpr);

		iconLetter = new FlxText(ICON_X, ICON_Y + 56, ICON_SIZE, '', 48);
		iconLetter.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER);
		iconLetter.scrollFactor.set();
		iconLetter.visible = false;
		add(iconLetter);

		// ---- 右侧：名字 + 描述 + 链接 ----
		nameText = new FlxText(PANEL_R_X + 30, 352, PANEL_R_W - 60, '', 30);
		nameText.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		nameText.borderSize = 2;
		nameText.scrollFactor.set();
		add(nameText);

		descText = new FlxText(PANEL_R_X + 30, 408, PANEL_R_W - 60, '', 24);
		descText.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.borderSize = 2;
		descText.scrollFactor.set();
		add(descText);

		linkText = new FlxText(PANEL_R_X + 30, 584, PANEL_R_W - 60, '', 20);
		linkText.setFormat(Paths.font('future.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		linkText.borderSize = 2;
		linkText.scrollFactor.set();
		add(linkText);

		// ---- 数据 ----
		#if MODS_ALLOWED
		for (mod in Mods.parseList().enabled) pushModCreditsToList(mod);
		#end

		var defaultList:Array<Array<String>> = [ //Name - Icon name - Description - Link - BG Color
			["Meteoric Engine Credits"],
			['Bonus-XK',		'bxk',		'Meteoric Engine的主创作者，\n是个小学生awa',								'https://space.bilibili.com/3461572190013717',	'FCFBFC'],
			['Maple_autumn',	'maple',		'负责Meteoric Engine的代码，为ME引擎做出巨大贡献！',								'',	'FFFFFF'],
			['Fu Hefei',		'fhf',			'是我，复合肥！\n早期版本Meteoric Engine测试成员',								'https://space.bilibili.com/1311432244',			'80FCC6'],
			['Rs-Drfeaoer',		'Rs',			'Rs-Drfeaoer\n早期版本Meteoric Engine测试成员',								'https://space.bilibili.com/1817033215',			'FF9B9B'],
			[''],
			["Funkin' Crew"],
			['ninjamuffin99',	'ninjamuffin99',	"FNF的主程序员",							'https://twitter.com/ninja_muffin99',	'CF2D2D'],
			['PhantomArcade',	'phantomarcade',	"FNF的动画制作者",								'https://twitter.com/PhantomArcade3K',	'FADC45'],
			['evilsk8r',		'evilsk8r',			"FNF的画师",								'https://twitter.com/evilsk8r',			'5ABD4B'],
			['kawaisprite',		'kawaisprite',		"FNF的曲师",								'https://twitter.com/kawaisprite',		'378FC7']
		];

		for (i in defaultList) creditsStuff.push(i);

		for (i in 0...creditsStuff.length)
		{
			if (!unselectableCheck(i) && curSelected == -1) curSelected = i;
		}

		if (curSelected >= 0)
		{
			bg.color = CoolUtil.colorFromString(creditsStuff[curSelected][4]);
			intendedColor = bg.color;
			changeSelection();
		}

		// ---- 底部提示 ----
		var hint:FlxText = new FlxText(40, 672, 1160, '滚轮 / 方向键 选择 · Enter / 点击 打开主页 · 点击 < 返回', 16);
		hint.setFormat(Paths.font("future.ttf"), 16, FlxColor.WHITE, CENTER);
		hint.scrollFactor.set();
		add(hint);

		// ---- 返回按钮（右上角） ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		FlxG.mouse.visible = true;
		super.create();
	}

	function addTitle(x:Float, y:Float, text:String)
	{
		var t:FlxText = new FlxText(x, y, 0, text, 26);
		t.setFormat(Paths.font('future.ttf'), 26, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.scrollFactor.set();
		t.antialiasing = ClientPrefs.data.antialiasing;
		add(t);
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music.volume < 0.7)
		{
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
		}

		if (!quitting && curSelected >= 0)
		{
			if (creditsStuff.length > 1)
			{
				var shiftMult:Int = 1;
				if (FlxG.keys.pressed.SHIFT) shiftMult = 3;

				if (controls.UI_UP_P)
				{
					mouseActive = false;
					mouseLockX = FlxG.mouse.screenX;
					mouseLockY = FlxG.mouse.screenY;
					changeSelection(-shiftMult);
					holdTime = 0;
				}
				if (controls.UI_DOWN_P)
				{
					mouseActive = false;
					mouseLockX = FlxG.mouse.screenX;
					mouseLockY = FlxG.mouse.screenY;
					changeSelection(shiftMult);
					holdTime = 0;
				}

				if (controls.UI_DOWN || controls.UI_UP)
				{
					mouseActive = false;
					mouseLockX = FlxG.mouse.screenX;
					mouseLockY = FlxG.mouse.screenY;
					var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

					if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
					{
						changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
					}
				}

				if (!controls.controllerMode)
				{
					// 键盘接管后，鼠标移动超过阈值才恢复鼠标操作
					if (!mouseActive)
					{
						var dx:Float = FlxG.mouse.screenX - mouseLockX;
						var dy:Float = FlxG.mouse.screenY - mouseLockY;
						if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
					}

					// 滚轮：每帧最多 1 格
					if (FlxG.mouse.wheel != 0)
					{
						mouseActive = true;
						changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
					}

					// 返回按钮：悬停发光，点击返回
					backBtn.setHovered(FlxG.mouse.screenX, FlxG.mouse.screenY);
					if (FlxG.mouse.justPressed && backBtn.over(FlxG.mouse.screenX, FlxG.mouse.screenY))
					{
						mouseActive = true;
						quitting = true;
						if (colorTween != null) colorTween.cancel();
						FlxG.sound.play(Paths.sound('cancelMenu'));
						MusicBeatState.switchState(new MainMenuState());
						return;
					}

					// 点击列表行：选中；点击已选中的行则打开主页
					if (FlxG.mouse.justPressed)
					{
						var hoveredID:Int = getHoveredOptionID();
						if (hoveredID >= 0)
						{
							mouseActive = true;
							if (hoveredID != curSelected)
							{
								changeSelection(hoveredID - curSelected);
								holdTime = 0;
							}
							else if (hasLink(curSelected))
							{
								CoolUtil.browserLoad(creditsStuff[curSelected][3]);
							}
						}
					}
				}
			}

			if (controls.ACCEPT && hasLink(curSelected))
			{
				CoolUtil.browserLoad(creditsStuff[curSelected][3]);
			}
			else if (controls.BACK)
			{
				quitting = true;
				if (colorTween != null) colorTween.cancel();
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		super.update(elapsed);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}

	function changeSelection(change:Int = 0)
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		do {
			curSelected += change;
			if (curSelected < 0)
				curSelected = creditsStuff.length - 1;
			if (curSelected >= creditsStuff.length)
				curSelected = 0;
		} while (unselectableCheck(curSelected));

		// 滚动窗口：只有越过可见区时才整页滚动
		if (curSelected < scrollIndex)
			scrollIndex = curSelected;
		else if (curSelected > scrollIndex + ROWS_VISIBLE - 1)
			scrollIndex = curSelected - ROWS_VISIBLE + 1;

		var newColor:FlxColor = CoolUtil.colorFromString(creditsStuff[curSelected][4]);
		if (newColor != intendedColor)
		{
			if (colorTween != null) colorTween.cancel();
			intendedColor = newColor;
			colorTween = FlxTween.color(bg, 1, bg.color, intendedColor, {
				onComplete: function(twn:FlxTween) {
					colorTween = null;
				}
			});
		}

		refreshRows();

		// ---- 右侧信息 ----
		#if MODS_ALLOWED
		if (creditsStuff[curSelected][5] != null)
		{
			Mods.currentModDirectory = creditsStuff[curSelected][5];
		}
		#end

		var graphic = Paths.image('credits/' + creditsStuff[curSelected][1]);
		if (graphic == null)
		{
			// 图标缺失：画一个磨砂圆占位，显示名字首字母
			iconSpr.makeGraphic(Std.int(ICON_SIZE), Std.int(ICON_SIZE), FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawCircle(iconSpr, ICON_SIZE / 2, ICON_SIZE / 2, ICON_SIZE / 2 - 2, 0x2EFFFFFF, {color: 0x8CFFFFFF, thickness: 2});
			iconSpr.updateHitbox();
			iconSpr.x = ICON_X;
			iconSpr.y = ICON_Y;
			iconLetter.text = creditsStuff[curSelected][0].substring(0, 1);
			iconLetter.visible = true;
		}
		else
		{
			iconSpr.loadGraphic(graphic);
			iconSpr.setGraphicSize(Std.int(ICON_SIZE), Std.int(ICON_SIZE));
			iconSpr.updateHitbox();
			iconSpr.x = ICON_X;
			iconSpr.y = ICON_Y;
			iconLetter.visible = false;
		}

		#if MODS_ALLOWED
		Mods.currentModDirectory = '';
		#end

		nameText.text = creditsStuff[curSelected][0];
		nameText.updateHitbox();

		descText.text = creditsStuff[curSelected][2];
		descText.updateHitbox();

		linkText.text = hasLink(curSelected) ? '主页链接：' + creditsStuff[curSelected][3] : '暂无主页链接';
		linkText.color = hasLink(curSelected) ? 0xFF9CE8FF : 0xFF6A7585;
		linkText.updateHitbox();

		callUIScripts('onChangeSelection', [curSelected, creditsStuff[curSelected][0]]);
	}

	function refreshRows()
	{
		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:FlxText = rows[r];

			if (idx >= creditsStuff.length)
			{
				row.visible = false;
				continue;
			}

			var isTitle:Bool = unselectableCheck(idx);
			var isSel:Bool = (idx == curSelected);

			row.visible = true;
			row.text = creditsStuff[idx][0];
			if (isTitle)
			{
				row.fieldWidth = PANEL_L_W - 48;
				row.x = PANEL_L_X + 24;
				row.alignment = CENTER;
				row.alpha = 0.9;
				row.color = 0xFFFFD9A0;
			}
			else
			{
				row.fieldWidth = 0;
				row.x = LIST_X;
				row.alignment = LEFT;
				row.alpha = isSel ? 1 : 0.55;
				row.color = isSel ? FlxColor.WHITE : 0xFFB8B8C8;
			}
			row.updateHitbox();
		}

		var barY:Float = LIST_Y - 3 + ((curSelected - scrollIndex) * ROW_GAP);
		selectorBar.visible = true;
		if (selectorTween != null)
		{
			selectorTween.cancel();
			selectorTween = null;
		}
		if (selectorBar.y != barY)
			selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
	}

	#if MODS_ALLOWED
	function pushModCreditsToList(folder:String)
	{
		var creditsFile:String = null;
		if (folder != null && folder.trim().length > 0) creditsFile = Paths.mods(folder + '/data/credits.txt');
		else creditsFile = Paths.mods('data/credits.txt');

		if (FileSystem.exists(creditsFile))
		{
			var firstarray:Array<String> = File.getContent(creditsFile).split('\n');
			for (i in firstarray)
			{
				var arr:Array<String> = i.replace('\\n', '\n').split('::');
				if (arr.length >= 5) arr.push(folder);
				creditsStuff.push(arr);
			}
			creditsStuff.push(['']);
		}
	}
	#end

	function getHoveredOptionID():Int
	{
		var hoveredID:Int = -1;
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		for (r in 0...rows.length)
		{
			var row:FlxText = rows[r];
			if (!row.visible) continue;
			var idx:Int = scrollIndex + r;
			if (unselectableCheck(idx)) continue;
			if (mx >= row.x && mx <= row.x + row.width && my >= row.y && my <= row.y + row.height)
				hoveredID = idx;
		}
		return hoveredID;
	}

	function hasLink(idx:Int):Bool
	{
		return idx >= 0 && idx < creditsStuff.length && creditsStuff[idx].length > 4
			&& creditsStuff[idx][3] != null && creditsStuff[idx][3].length > 4;
	}

	private function unselectableCheck(num:Int):Bool
	{
		return creditsStuff[num].length <= 1;
	}
}
