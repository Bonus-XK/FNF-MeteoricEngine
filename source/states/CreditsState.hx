package states;
import backend.WheelScroll;

#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end

import objects.BackButton;
import openfl.Lib;
import flixel.util.FlxSpriteUtil;

class CreditsState extends MusicBeatState
{
	var wheelScroll:WheelScroll = new WheelScroll(); // 滚轮限速（Freeplay 同款）
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

	// ===== 左面板：选中项「大卡片」（头像 + 名字 + 职位）=====
	// 行高不再等距：选中行 = 卡片（CARD_H），未选中行 = ROW_H。行位由「逐行累加」算出，
	// 因此卡片展开/收起时它下面的行会整体让位（用户指定），滚动条也按同一套行位跟随。
	static final ROW_H:Float = 56;        // 未选中行高
	static final CARD_H:Float = 104;      // 选中卡片高
	static final ROW_GAP_S:Float = 4;     // 行间留白（卡片本身已有描边，留白压小避免碎片感）
	static final CARD_X:Float = PANEL_L_X + 24;              // 卡片左缘（与面板内边距对齐）
	static final CARD_W:Float = PANEL_L_W - 48;              // 卡片宽 632
	static final CARD_RADIUS:Float = 14;
	static final CARD_PAD:Float = 16;                         // 卡片内边距
	static final AVATAR_SIZE:Float = 64;                      // 卡片内头像直径
	static final CARD_TEXT_X:Float = CARD_X + CARD_PAD + AVATAR_SIZE + 18; // 文字起点 162
	static final CARD_TEXT_W:Float = (CARD_X + CARD_W - CARD_PAD) - CARD_TEXT_X; // 486
	/** 列表可用高度（第一行到底线），滚动窗口容量按它算 */
	static final LIST_BOTTOM:Float = PANEL_L_Y + PANEL_L_H - 12; // 70 + 570 - 12 = 628
	static final LIST_H:Float = LIST_BOTTOM - LIST_Y;            // 628 - 152 = 476
	static final PANEL_BOTTOM:Float = LIST_BOTTOM;               // 行/卡片不得越过此线

	var curSelected:Int = -1;
	var scrollIndex:Int = 0;

	var creditsStuff:Array<Array<String>> = [];
	var rows:Array<FlxText> = [];

	var bg:FlxSprite;
	var intendedColor:FlxColor;
	var colorTween:FlxTween;

	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;

	// 选中卡片（左面板）
	var cardBg:FlxSprite;        // 卡片底（圆角玻璃 + 选中高亮）
	var cardAvatar:FlxSprite;    // 头像：圆内贴图；缺图时退化为「首字母磨砂圆」
	var cardLetter:FlxText;      // 缺图占位首字母
	var cardName:FlxText;        // 名字
	var cardRole:FlxText;        // 职位（取条目描述首句，超宽截断）
	var cardTween:FlxTween;      // 卡片出现动效（低频、可被下一次输入打断）
	var cardShownIndex:Int = -1; // 已构建的卡片条目；-1 = 尚未构建

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

		// ---- 选中高亮条 ----
		// 现在由「选中卡片」（cardBg）承担选中视觉：它是同尺寸的圆角玻璃 + rowHighlight 填充，
		// 只是**更高**（CARD_H 104 vs 46）。selectorBar 保留为**卡片下方的定位层**：
		// 它跟着卡片移动、被卡片完全盖住，负责「高频滚动动效」那 0.12s 的滑动节奏，
		// 卡片自己只用 150ms 淡入，避免每格都播一次位移动画（skill：高频滚动 ≤150ms、可被打断）。
		selectorBar = makePanel(PANEL_L_X + 24, LIST_Y - 3, PANEL_L_W - 48, 46, 14, DesignTokens.rowHighlight, null);
		selectorBar.visible = false;
		add(selectorBar);

		// ---- 左面板：选中卡片（先建，才能被行文字盖住？不 —— 卡片必须在**文字之下**）----
		// 绘制顺序契约：卡片 → 头像 → 行文字（refreshRows 里文字在 create 期已 add，
		// 故这里用 add 顺序保证卡片在下层）。文字始终画在卡片之上，不会被卡片边缘压住。
		cardBg = makePanel(CARD_X, LIST_Y, CARD_W, CARD_H, CARD_RADIUS, DesignTokens.rowHighlight, DesignTokens.panelOutline);
		cardBg.visible = false;
		add(cardBg);

		cardAvatar = new FlxSprite(0, 0);
		cardAvatar.antialiasing = ClientPrefs.data.antialiasing;
		cardAvatar.scrollFactor.set();
		cardAvatar.visible = false;
		add(cardAvatar);

		cardLetter = new FlxText(0, 0, AVATAR_SIZE, '', 30);
		cardLetter.setFormat(Paths.font('future.ttf'), 30, FlxColor.WHITE, CENTER);
		cardLetter.scrollFactor.set();
		cardLetter.visible = false;
		add(cardLetter);

		cardName = new FlxText(CARD_TEXT_X, LIST_Y, CARD_TEXT_W, '', 32);
		cardName.setFormat(Paths.font('future.ttf'), 32, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		cardName.borderSize = 2;
		cardName.wordWrap = false;
		cardName.scrollFactor.set();
		cardName.visible = false;
		add(cardName);

		cardRole = new FlxText(CARD_TEXT_X, LIST_Y, CARD_TEXT_W, '', 18);
		cardRole.setFormat(Paths.font('future.ttf'), 18, 0xFFD7D7E0, LEFT);
		cardRole.wordWrap = false;
		cardRole.scrollFactor.set();
		cardRole.visible = false;
		add(cardRole);

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
		var defaultList:Array<Array<String>> = [ //Name - Icon name - Description - Link - BG Color
			["Meteoric Engine Credits"],
			['Real-bonuX',		'bxk',		'Meteoric Engine的主创作者，\n是个12岁的初中生awa',								'https://space.bilibili.com/3461572190013717',	'FCFBFC'],
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

		#if MODS_ALLOWED
		for (mod in Mods.parseList().enabled) pushModCreditsToList(mod);
		#end

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

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是**编译期常量**，不能写 DesignTokens.panelFill（运行时求值会被 Haxe 拒绝），
		// 故默认传 null、在此解析 —— 同时保证取到的是「当前主题」的值，而不是类加载时的快照。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
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
					var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
					if (wheelStep != 0)
					{
						mouseActive = true;
						changeSelection(wheelStep);
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

					// 触控/点击只负责选中，打开链接由 A 键触发
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

		// 滚动窗口：**选中项必须始终在窗口内**，且窗口里要装得下"更高的选中卡片"。
		// 旧的 `ROWS_VISIBLE - 1` 规则不再成立：选中行占 CARD_H（104）而不是 ROW_H（56），
		// 所以按实际高度算每页能装几行（cardRowCapacity），保证
		//   ① 选到窗口底部时整页下移（否则选中项会跑出左面板，正是"顶出左面板"的现象）
		//   ② 卡片展开后下面仍有行可显示（卡片多占的 48px 只挤掉一行，不会挤掉整页）
		// ⚠ 这里必须用 `curSelected` 自己那一行占 CARD_H 来算容量 —— 窗口里永远只有 1 张卡片。
		// ⚠ 容量必须按**真实可用高度 LIST_H** 算（第一行到底线），不是面板高度：
		//   用面板高度算过一次，容量偏大 → 卡片被放到最后一格时底边越过底线 → 顶出左面板。
		var slotH:Float = CARD_H + ROW_GAP_S;
		var rowsCapacity:Int = 1 + Math.floor((LIST_H - slotH) / (ROW_H + ROW_GAP_S));
		if (rowsCapacity < 1) rowsCapacity = 1;
		if (rowsCapacity > ROWS_VISIBLE) rowsCapacity = ROWS_VISIBLE;

		// 合法窗口区间 [lo, hi]：
		//   hi = curSelected - capacity + 1 —— 选中项落在窗口最后一格；
		//   lo = curSelected - capacity + 2 —— 选中项落在窗口**倒数第二格**。
		// 为什么 lo 要多一格：卡片占窗口最后一格时底边几乎贴住底线，任何常量偏差都会越界
		// （实测 capacity=7 时最后两格分别越界 96px / 36px）。让卡片最多落在倒数第二格，
		// 底边就留出一整行的余量。capacity=1 时 lo 会大于 hi，做保护夹取。
		var hi:Int = curSelected - rowsCapacity + 1;
		var lo:Int = curSelected - rowsCapacity + 2;
		if (lo > hi) lo = hi;
		if (lo < 0) lo = 0;

		// 把旧窗口位置**夹进合法区间**：优先保持原位（避免每选一格整屏乱跳），越界才移动最小距离。
		// 这样同时满足两条约束：① 选中项在窗口内（否则卡片与行文字一起消失）
		// ② 卡片一定放得下面板（否则顶出左面板）。
		scrollIndex = Std.int(Math.max(lo, Math.min(hi, scrollIndex)));

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
		linkText.color = hasLink(curSelected) ? DesignTokens.primary : 0xFF6A7585;
		linkText.updateHitbox();

		callUIScripts('onChangeSelection', [curSelected, creditsStuff[curSelected][0]]);
	}

	function refreshRows()
	{
		// 选中卡片只构建一次：内容没变就别重复构建（每格重设贴图 = 无谓开销）
		if (cardShownIndex != curSelected)
		{
			cardShownIndex = curSelected;
			buildCard();
		}
		layoutRows();
	}

	/**
	 * 行位表：选中行占 CARD_H，其余占 ROW_H，逐行累加。
	 * 这是"下面行给卡片让位"的唯一实现点 —— 任何行位计算都必须走这里，不要再写 `r * ROW_GAP`。
	 */
	function computeRowYs():Array<Float>
	{
		var ys:Array<Float> = [];
		var y:Float = LIST_Y;
		for (r in 0...ROWS_VISIBLE)
		{
			ys.push(y);
			var idx:Int = scrollIndex + r;
			var isCard:Bool = (idx == curSelected);
			y += (isCard ? CARD_H : ROW_H) + ROW_GAP_S;
		}
		return ys;
	}

	/** 应用行位 + 卡片位置/内容开关。所有尺寸都按当前行高动态算，不依赖等距 ROW_GAP。 */
	function layoutRows()
	{
		var ys:Array<Float> = computeRowYs();
		var isCardVisible:Bool = false;

		for (r in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollIndex + r;
			var row:FlxText = rows[r];
			var top:Float = ys[r];
			var isSel:Bool = (idx == curSelected);

			if (idx >= creditsStuff.length)
			{
				row.visible = false;
				continue;
			}

			var isTitle:Bool = unselectableCheck(idx);
			var rowH:Float = isSel ? CARD_H : ROW_H;

			// 越过面板底线的**普通行**隐藏（卡片展开会把下面的行推下去），避免压到底部提示条。
			// ⚠ 选中行（卡片）**绝不能**走这条裁剪：卡片比普通行高 48px，滚动窗口又按 ROWS_VISIBLE 算，
			//   一旦卡片被推到面板底线以下，这里会把它整个隐藏 —— 实测表现就是
			//   「向下选中并滚动后大卡片不显示」。卡片位置由 changeSelection 的窗口规则 +
			//   layoutRows 的行位表共同保证：选中项永远落在窗口内，卡片永远在面板底线之上。
			if (!isSel && top + rowH > PANEL_BOTTOM)
			{
				row.visible = false;
				continue;
			}

			row.visible = true;
			row.text = creditsStuff[idx][0];
			row.updateHitbox(); // 先按新文本刷新尺寸，行内垂直居中才用的是**新**高度

			if (isTitle)
			{
				row.fieldWidth = PANEL_L_W - 48;
				row.x = PANEL_L_X + 24;
				row.alignment = CENTER;
				row.y = top + (ROW_H - row.height) * 0.5; // 栏目标题在行内居中
				row.alpha = 0.9;
				row.color = DesignTokens.secondary;
			}
			else if (isSel)
			{
				// 选中行：名字交给卡片里的 cardName；行文字隐藏（避免与卡片内容重复渲染）
				row.visible = false;
				isCardVisible = true;
			}
			else
			{
				row.fieldWidth = 0;
				row.x = LIST_X;
				row.alignment = LEFT;
				row.y = top + (rowH - row.height) * 0.5;
				row.alpha = 0.55;
				row.color = 0xFFB8B8C8;
			}
		}

		// ---- 卡片定位 + 内部内容 ----
		cardBg.visible = isCardVisible;
		cardAvatar.visible = isCardVisible && cardAvatar.graphic != null;
		cardLetter.visible = isCardVisible && (cardAvatar.graphic == null);
		cardName.visible = isCardVisible;
		cardRole.visible = isCardVisible;

		if (isCardVisible)
		{
			// 窗口内下标：由 changeSelection 的 rowsCapacity 规则保证落在 0..ROWS_VISIBLE-1，
			// 这里再夹取一次作硬防护（越界会把卡片画到屏幕外，且 Haxe 数组越界在 cpp 上是崩而不是报错）
			var slot:Int = curSelected - scrollIndex;
			if (slot < 0) slot = 0;
			if (slot > ROWS_VISIBLE - 1) slot = ROWS_VISIBLE - 1;
			var cardY:Float = ys[slot];

			// 【硬约束】卡片底边绝不允许越过面板底线 —— 越界就是用户看到的「卡片顶出左面板、
			// 压在底部提示条上」。行位表是自顶向下累加的，窗口容量只是"尽量"保证放得下；
			// 一旦估算偏差（常量/字号/行距任何一处改动都会重新引入），这里直接夹住：
			// 宁可让卡片与下面某一行视觉重叠，也绝不允许它越出面板（重叠只影响观感，越界是破图）。
			var cardMaxY:Float = PANEL_BOTTOM - CARD_H;
			if (cardY > cardMaxY) cardY = cardMaxY;
			if (cardY < LIST_Y) cardY = LIST_Y;

			var cy:Float = cardY + CARD_H * 0.5;

			cardBg.y = cardY;
			if (cardBg.alpha < 1) cardBg.alpha = 1;

			// 头像：贴图存在则等比缩放居中放进圆内；缺图时用磨砂圆 + 首字母（与右侧大图标同款退化）
			var avCx:Float = CARD_X + CARD_PAD + AVATAR_SIZE * 0.5;
			if (cardAvatar.graphic != null)
			{
				cardAvatar.x = avCx - cardAvatar.width * 0.5;
				cardAvatar.y = cy - cardAvatar.height * 0.5;
			}
			if (cardLetter.visible)
			{
				cardLetter.fieldWidth = AVATAR_SIZE;
				cardLetter.x = CARD_X + CARD_PAD;
				cardLetter.y = cy - 20;
			}

			// 名字 + 职位：两行文字整体在卡片内垂直居中
			cardName.x = CARD_TEXT_X;
			cardName.y = cy - 26;
			cardName.fieldWidth = CARD_TEXT_W;
			cardName.color = FlxColor.WHITE;

			cardRole.x = CARD_TEXT_X;
			cardRole.y = cy + 8;
			cardRole.fieldWidth = CARD_TEXT_W;
			cardRole.color = 0xFFD7D7E0;
		}

		// ---- 高亮条 ----
		// 已废弃：卡片（cardBg）就是选中视觉。原先保留它当"卡片下方的定位层"是错的 ——
		// 卡片 104 高、它只有 46 高且下移 3px，会从卡片下缘露出约 55px，
		// 表现为「同时出现一个小长方形和一个大卡片」（用户实测）。这里彻底不显示。
		selectorBar.visible = false;
		if (selectorTween != null)
		{
			selectorTween.cancel();
			selectorTween = null;
		}
	}

	/**
	 * 构建选中卡片的内容：头像（`credits/<icon>`）+ 名字 + 职位。
	 * 只在选中项变化时调用（见 refreshRows 的 cardShownIndex 守卫）：
	 * 头像贴图每格重设属于无谓开销，且 `Paths.image` 已带缓存，切换回来的成本只是查表。
	 */
	function buildCard()
	{
		if (curSelected < 0 || curSelected >= creditsStuff.length) return;

		var info:Array<String> = creditsStuff[curSelected];
		var letter:String = (info[0] != null && info[0].length > 0) ? info[0].substring(0, 1) : '?';

		cardName.text = info[0];
		cardName.updateHitbox();

		// 职位 = 条目描述的首句（数据里没有独立职位字段；用户确认「只用现有数据」）
		cardRole.text = firstSentence(info[2]);
		cardRole.updateHitbox();

		#if MODS_ALLOWED
		if (info[5] != null) Mods.currentModDirectory = info[5];
		#end

		var graphic = Paths.image('credits/' + info[1]);
		if (graphic == null)
		{
			// 缺图：磨砂圆 + 首字母（与右侧大图标同款退化表现）
			cardAvatar.makeGraphic(Std.int(AVATAR_SIZE), Std.int(AVATAR_SIZE), FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawCircle(cardAvatar, AVATAR_SIZE * 0.5, AVATAR_SIZE * 0.5, AVATAR_SIZE * 0.5 - 2,
				0x2EFFFFFF, {color: 0x8CFFFFFF, thickness: 2});
			cardAvatar.updateHitbox();
			cardLetter.text = letter;
		}
		else
		{
			// 有图：**短边**贴到圆内直径并居中（长边会被圆/卡片边界自然裁掉，脸不会变形）
			cardAvatar.loadGraphic(graphic);
			var k:Float = AVATAR_SIZE / Math.min(graphic.width, graphic.height);
			cardAvatar.setGraphicSize(Std.int(graphic.width * k), Std.int(graphic.height * k));
			cardAvatar.updateHitbox();
			cardLetter.text = '';
		}

		#if MODS_ALLOWED
		Mods.currentModDirectory = '';
		#end

		// 低频、可打断的出现动效（skill：150ms quadOut；复用的 tween 先 kill）
		if (cardTween != null)
		{
			cardTween.cancel();
			cardTween = null;
		}
		cardBg.alpha = 0.4;
		cardTween = FlxTween.tween(cardBg, {alpha: 1}, 0.15, {
			ease: FlxEase.quadOut,
			onComplete: function(_) cardTween = null
		});
	}

	/** 取描述首句（按换行/句号/问叹号切），并用 getTextWidth 逐字收敛到卡片可用宽度。 */
	static function firstSentence(s:String):String
	{
		if (s == null) return '';
		var out:String = s.split('\n')[0];
		for (p in ['。', '！', '？', '.', '!', '?'])
		{
			var i:Int = out.indexOf(p);
			if (i > 0)
			{
				out = out.substring(0, i);
				break;
			}
		}
		return fitToWidth(out.trim(), CARD_TEXT_W, 18);
	}

	/** 逐字截断到指定像素宽（超宽补省略号）。不依赖 TextField.numLines 之类的非公开成员。 */
	static function fitToWidth(s:String, maxPx:Float, size:Int):String
	{
		if (s == null || s.length < 1) return '';
		var probe:FlxText = new FlxText(0, 0, 0, s, size);
		probe.setFormat(Paths.font('future.ttf'), size, FlxColor.WHITE, LEFT);
		var t:String = s;
		var n:Int = s.length;
		while (n > 1)
		{
			probe.text = t + '…';
			if (probe.textField.textWidth <= maxPx) break;
			n--;
			t = s.substring(0, n);
		}
		probe.destroy();
		return (n < s.length) ? (t + '…') : s;
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
