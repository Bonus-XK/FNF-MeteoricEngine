package substates;

import backend.BackupFormat;
import backend.ClientPrefs;
import backend.Controls;
import backend.Lang;
import backend.CoolUtil;
import backend.DesignTokens;
import backend.SaveMover;
import backend.WheelScroll;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import objects.BackButton;
import objects.ToggleSwitch;
import backend.Paths;

/**
 * 备份 / 迁移 全屏 State。
 *
 * 形态参照 Seiun Engine 的 BackupSettingsSubState（全屏 State 而非选项子页），
 * 视觉与排版沿用本引擎的设计语言，几何与 ScriptManagerSubstate 同源。
 *
 * ⚠ 控件一律**复用既有组件**，不自造外观：
 *  - 开关 = `objects.ToggleSwitch`（96×32 胶囊 + 22px 白圆滑块），与设置界面、
 *    更新界面同一个类。**不要**用 ■/□ 文字或 26px 方框代替 —— 那是最早那版的做法，
 *    被明确否掉了。
 *  - 选中行 = 整行磨砂高亮条 `DesignTokens.rowHighlight` + 标签白色；
 *    未选中行的开关 `setAlpha(0.85)`、选中行 `setAlpha(1)`（BaseOptionsMenu 同款）。
 *  - 所有颜色取 `DesignTokens.*` 运行时令牌，**禁止**硬编码主题色的字面值；
 *    像素类的暗色可以硬编码（0xFF9A9AA8 行文字等），主题色的必须走令牌。
 *
 * 三种备份格式（玩家可选，Seiun 只有一种自定义格式）：
 *   ① zip  原始文件包，可勾选打包项 —— 最通用，能直接打开看内容
 *   ② msb  自定义二进制（魔数 MSB1 + 版本 + 分项长度），带完整性校验
 *   ③ json 结构化数据（设置/键位/高分），人可读、体积最小
 *
 * ⚠ 9 行全部同屏可见（不滚动）：ROW_START_Y + 8*ROW_GAP + 行高 < PANEL_Y+PANEL_H。
 *   改动 ROW_GAP / ROW_START_Y 时必须重新验算，否则第 9 行会掉出面板。
 */
class BackupSubState extends MusicBeatSubstate
{
	// ===== 布局常量（与 ScriptManagerSubstate 同款几何） =====
	static final TITLE_Y:Float = 22;
	static final TITLE_SIZE:Int = 48;
	static final PANEL_X:Float = 160;
	static final PANEL_Y:Float = 96;
	static final PANEL_W:Float = 960;
	static final PANEL_H:Float = 560;
	static final ROW_X:Float = 204;
	static final ROW_START_Y:Float = 164;
	static final ROW_GAP:Float = 56;
	static final ROW_BOX_H:Float = 40;
	static final ROW_TEXT_SIZE:Int = 24;
	static final VALUE_RIGHT:Float = 1096;
	static final SWITCH_W:Float = 96;
	static final SWITCH_H:Float = 32;
	/** 开关右缘与值列右缘对齐（ToggleSwitch 默认 96×32）。 */
	static final SWITCH_X:Float = VALUE_RIGHT - SWITCH_W;
	/**
	 * 长值行（输出目录）的最大像素宽度。**只对 INFO 行生效** —— 它那一行的左邻只有
	 * 「备份输出目录」6 个字（204~348），所以能开到 700；其它行的值都很短。
	 */
	static final VALUE_MAX_W:Float = 700;
	/** 长值行字号，比标题小一号，视觉上区分「信息」与「操作」。 */
	static final VALUE_SMALL_SIZE:Int = 18;
	static final HINT_Y:Float = 668;
	static final HINT_SIZE:Int = 18;
	static final HIT_PAD:Float = 6;

	/**
	 * 长值裁剪的**硬步数上界**。
	 *
	 * ⚠ 裁剪循环必须同时满足两个条件才可能死循环，这里两个都堵上了：
	 *    ① 兜底循环**只截不加**（`t.substr(1)`，不加回省略号）→ 长度严格递减，`t.length > 4` 才真能收尾；
	 *    ② 再加迭代次数硬上界 → 即使长度判定被改坏也不会卡死。
	 *    （省略号写法 `'…' + t.substr(1)` 每轮长度恒定，只判长度 = 100% CPU 死循环，真发生过。）
	 */
	static final FIT_MAX_STEPS:Int = 512;

	static final COLOR_ROW:Int = 0xFF9A9AA8;
	static final COLOR_ROW_HOVER:Int = 0xFFD7D7E0;
	/** 底部提示用灰（与 ScriptManagerSubstate 同款）；主题色留给值列。 */
	static final COLOR_HINT:Int = 0xFFA9A9B8;
	/** 未选中行的开关透明度（选中 1，未选中 0.85 —— BaseOptionsMenu 同款）。 */
	static final SWITCH_ALPHA_IDLE:Float = 0.85;
	static final SWITCH_ALPHA_SEL:Float = 1.0;

	var rows:Array<BackupRow> = [];
	var rowLabels:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];
	/** TOGGLE 行的开关（与设置界面同款 objects.ToggleSwitch），按行下标与 rows 对齐。 */
	var switchCols:Array<ToggleSwitch> = [];
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var backBtn:BackButton;
	var hintText:FlxText;
	var titleText:FlxText;
	var wheelScroll:WheelScroll = new WheelScroll();
	var curSelected:Int = 0;
	var hovered:Int = -1;
	/** 进入页面后的回车防误触冷却帧数；<=0 才接受 ACCEPT。 */
	var nextAccept:Int = 5;
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var musicWasPlaying:Bool = false;
	var themeListener:Void->Void;

	public function new()
	{
		super();
	}

	override function create()
	{
		super.create();

		// 主题色变更 → 开关轨道（像素图）必须原地重绘，否则换主题后开关还是旧色。
		// DesignTokens 的监听表是静态的，契约要求 destroy 里摘除。
		themeListener = function() rethemeNow();
		DesignTokens.addThemeListener(themeListener);

		// 固定渲染在专用相机上：zoom=1、scroll=(0,0)，暂停/游玩中打开都不受游戏相机影响
		var settingsCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [settingsCam];

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.72;
		bg.scrollFactor.set();
		add(bg);

		titleText = new FlxText(0, TITLE_Y, FlxG.width, Lang.tOr('backup.title', '备份与迁移'), TITLE_SIZE);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), TITLE_SIZE, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		add(makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 20));

		buildRows();

		for (i in 0...rows.length)
		{
			var y:Float = ROW_START_Y + i * ROW_GAP;

			// 标签用 autoSize（构造宽度 0 + wordWrap=false）：OpenFL 会把文本框宽度锁成
			// 文字实际宽度 + 4，无论文案多长都完整绘制，从根本上杜绝裁切与折行顶行。
			var lbl:FlxText = new FlxText(ROW_X, y + 2, 0, '', ROW_TEXT_SIZE);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, COLOR_ROW, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.wordWrap = false;
			lbl.textField.x = 1; // 左/上 1px 内边距，避免描边被裁
			lbl.textField.y = 1;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			rowLabels.push(lbl);

			// TOGGLE 行的右值由开关画，文本留空并隐藏
			var isToggle:Bool = (rows[i].kind == BackupKind.TOGGLE);
			var val:FlxText = new FlxText(0, y + 2, 0, '', ROW_TEXT_SIZE);
			val.scrollFactor.set();
			val.wordWrap = false;
			val.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			val.visible = !isToggle;
			add(val);
			rowValues.push(val);

			if (isToggle)
			{
				// 垂直居中：行盒 ROW_BOX_H=40 高，开关 32 高 → 偏移 (40-32)/2 = 4，
				// 行盒顶在 y-4，故开关 y = y-4+4 = y
				var sw:ToggleSwitch = new ToggleSwitch(SWITCH_X, y, SWITCH_W, SWITCH_H);
				for (spr in sw.sprites) add(spr);
				switchCols.push(sw);
			}
			else
			{
				switchCols.push(null);
			}
		}

		// 整行高亮选中条（不是 4px 竖线）：与 ScriptManagerSubstate / 游玩设置一致
		selectorBar = makePanel(PANEL_X + 16, ROW_START_Y - 4, PANEL_W - 32, ROW_BOX_H, 12, DesignTokens.rowHighlight, null);
		add(selectorBar);

		// 返回按钮放**右上角**：左上角 (44,16) 会被 FPS 计数器压住，看不见也点不到
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		hintText = new FlxText(0, HINT_Y, FlxG.width, '', HINT_SIZE);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), HINT_SIZE, COLOR_HINT, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);
		hintText.text = Lang.tOr('backup.hint', '↑ ↓ 选择 · ← → 切换开关 · 回车 执行 / 切换 · 鼠标点击与滚轮同样可用 · ESC 返回');
		hintText.alpha = 1;

		// 开关首次落位直接吸附（否则「已开」的行会从关闭位置滑一段才到位）
		syncSwitches(true);
		refreshAll();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		// 暂停 BGM：整屏工具页不该和主菜单音乐叠在一起（返回时恢复）
		musicWasPlaying = (FlxG.sound.music != null && FlxG.sound.music.playing);
		if (FlxG.sound.music != null) FlxG.sound.music.pause();

		// 必须显式打开光标：BackupSubState 是整屏 State，外层没有别的地方会把它设成 true
		FlxG.mouse.visible = true;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (cameras != null && cameras[0] != null)
		{
			cameras[0].zoom = 1;
			cameras[0].scroll.set(0, 0);
		}

		// 开关滑块逐帧插值（圆心空间，elapsed*18）—— 与 BaseOptionsMenu 同款调用位置
		for (sw in switchCols)
			if (sw != null && sw.track != null && sw.track.visible) sw.animate(elapsed);

		var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());
		var ctrl:Controls = Controls.instance;

		// ===== 键盘 / 手柄 =====
		if (ctrl != null)
		{
			if (ctrl.UI_UP_P)
			{
				freezeMouse(mousePos);
				moveSelection(-1);
			}
			if (ctrl.UI_DOWN_P)
			{
				freezeMouse(mousePos);
				moveSelection(1);
			}
			if (ctrl.UI_LEFT_P || ctrl.UI_RIGHT_P) tryToggle();
			if (nextAccept <= 0 && ctrl.ACCEPT) acceptRow();
			if (nextAccept > 0) nextAccept -= 1;
			if (ctrl.BACK)
			{
				mousePos.put();
				onBack();
				return;
			}
		}

		// ===== 鼠标 / 触屏 =====
		if (ctrl == null || !ctrl.controllerMode)
		{
			var hit:Int = rowAt(mousePos.x, mousePos.y);
			if (hit != hovered)
			{
				hovered = hit;
				refreshAll();
			}

			if (!mouseActive)
			{
				var dx:Float = mousePos.x - mouseLockX;
				var dy:Float = mousePos.y - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
			if (wheelStep != 0)
			{
				mouseActive = true;
				moveSelection(wheelStep);
			}

			backBtn.setHovered(mousePos.x, mousePos.y);
			if (FlxG.mouse.justPressed && backBtn.over(mousePos.x, mousePos.y))
			{
				mousePos.put();
				onBack();
				return;
			}

			if (FlxG.mouse.justPressed)
			{
				var swHit:Int = switchAt(mousePos.x, mousePos.y);
				if (swHit >= 0)
				{
					// 点在开关本体上：即使该行未选中，第一次点击也直接切换（设置界面同款，
					// 否则「点一下开关」只是选中、要点第二下才生效，用起来像失灵）
					mouseActive = true;
					if (swHit != curSelected) setSelection(swHit);
					acceptRow();
				}
				else if (hit >= 0)
				{
					mouseActive = true;
					if (hit != curSelected) setSelection(hit);
					else acceptRow();
				}
			}
		}

		mousePos.put();
	}

	override function destroy()
	{
		for (sw in switchCols)
			if (sw != null) sw.destroy();
		switchCols = [];

		// 主题监听是静态表，不摘除会留下对已销毁精灵的僵尸回调
		if (themeListener != null)
		{
			DesignTokens.removeThemeListener(themeListener);
			themeListener = null;
		}

		super.destroy();
	}

	/** 主题切换：开关轨道是像素图，必须重绘（文本色是 FlxText 属性，改令牌即生效）。 */
	function rethemeNow():Void
	{
		for (sw in switchCols)
			if (sw != null) sw.refreshTheme();
		refreshAll();
	}

	/**
	 * 开关状态同步。
	 * @param instant true = 直接吸附（页面刚建好时用，否则「开」的开关会从关闭位置滑过来）
	 */
	function syncSwitches(instant:Bool):Void
	{
		for (i in 0...rows.length)
		{
			var sw:ToggleSwitch = switchCols[i];
			if (sw == null) continue;
			var st:Bool = (rows[i].readState != null) ? rows[i].readState() : false;
			if (instant || sw.on != st) sw.setOn(st, instant);
		}
	}

	/** 键盘操作时冻结鼠标跟随，鼠标一动就恢复（与 ScriptManagerSubstate 同款）。 */
	function freezeMouse(mousePos:FlxPoint):Void
	{
		mouseActive = false;
		mouseLockX = mousePos.x;
		mouseLockY = mousePos.y;
	}

	/** 统一返回：回设置页（全屏页与设置之间成对，见 OptionsState.enterBackupScreen）。 */
	function onBack():Void
	{
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		if (musicWasPlaying && FlxG.sound.music != null) FlxG.sound.music.play();
		options.OptionsState.onPlayState = false;
		FlxG.switchState(new options.OptionsState());
	}

	/** 行的固定命中区域：整行整宽（不依赖文本宽度），点击/悬停永远对得上。 */
	function rowRect(i:Int):FlxRect
	{
		return new FlxRect(PANEL_X + 16, ROW_START_Y + i * ROW_GAP - HIT_PAD, PANEL_W - 32, ROW_GAP + HIT_PAD * 2);
	}

	/** 鼠标 y 落在第几行；不在任何行上返回 -1。 */
	function rowAt(mx:Float, my:Float):Int
	{
		for (i in 0...rows.length)
		{
			var r:FlxRect = rowRect(i);
			if (mx >= r.x && mx <= r.x + r.width && my >= r.y && my <= r.y + r.height) return i;
		}
		return -1;
	}

	/** 鼠标落在哪个开关本体上；不在任何开关上返回 -1。
	 *  外扩 12 → 命中高 32+24 = 56，满足触控目标红线（BaseOptionsMenu.getHoveredCheckbox 同款）。 */
	function switchAt(mx:Float, my:Float):Int
	{
		for (i in 0...switchCols.length)
		{
			var sw:ToggleSwitch = switchCols[i];
			if (sw == null || sw.track == null) continue;
			if (sw.hits(mx, my, 12)) return i;
		}
		return -1;
	}

	function moveSelection(delta:Int):Void
	{
		if (rows.length == 0) return;
		// Haxe 的 % 是取余不是取模，负数要自己纠正（Math.floorMod 在本版本不存在）
		var n:Int = (curSelected + delta) % rows.length;
		curSelected = (n < 0) ? n + rows.length : n;
		playScroll();
	}

	function setSelection(idx:Int):Void
	{
		if (idx < 0 || idx >= rows.length || idx == curSelected) return;
		curSelected = idx;
		playScroll();
	}

	function playScroll():Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refreshAll();
	}

	function tryToggle():Void
	{
		var r:BackupRow = rows[curSelected];
		if (r == null || r.kind != BackupKind.TOGGLE) return;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		r.onToggle();
		ClientPrefs.saveSettings();
		refreshAll();
	}

	function acceptRow():Void
	{
		if (nextAccept > 0) return;
		var r:BackupRow = rows[curSelected];
		if (r == null) return;
		if (r.kind == BackupKind.ACTION)
		{
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
			r.onAccept();
			refreshAll();
		}
		else if (r.kind == BackupKind.TOGGLE)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			r.onToggle();
			ClientPrefs.saveSettings();
			refreshAll();
		}
		nextAccept = 5;
	}

	function refreshAll():Void
	{
		for (i in 0...rows.length)
		{
			var isSel:Bool = (i == curSelected);
			var lbl:FlxText = rowLabels[i];
			lbl.text = rows[i].label;
			lbl.color = isSel ? FlxColor.WHITE : ((i == hovered) ? COLOR_ROW_HOVER : COLOR_ROW);

			var sw:ToggleSwitch = switchCols[i];
			if (sw != null)
			{
				// ⚠ 现读权威来源，不读快照（快照不会随切换回调更新，会把开关按回去 → 表现为「拨不动」）
				var st:Bool = (rows[i].readState != null) ? rows[i].readState() : false;
				// 只在状态真变时 setOn：setOn 内部会整块重画轨道像素，每次刷新都调是白费
				if (sw.on != st) sw.setOn(st);
				sw.setAlpha(isSel ? SWITCH_ALPHA_SEL : SWITCH_ALPHA_IDLE);
			}

			applyValue(rowValues[i], i);
		}

		if (selectorBar != null)
		{
			var barY:Float = ROW_START_Y - 4 + curSelected * ROW_GAP;
			if (selectorBar.y != barY)
			{
				if (selectorTween != null)
				{
					selectorTween.cancel();
					selectorTween = null;
				}
				selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
			}
		}
	}

	/**
	 * 刷一行右值。TOGGLE 行交给开关，这里隐藏文本；其余行右对齐到 VALUE_RIGHT。
	 *
	 * autoSize 文本框靠文字宽度定位，**不能**用 alignment=RIGHT 对齐（那需要一个固定宽度盒子，
	 * 而固定宽度盒子 + 超出即折行/裁切，正是旧版路径压住标签的原因）。
	 *
	 * ⚠ 长值裁剪两条纪律（两条都踩过）：
	 *    ① 必须「先赋文本再量宽度」—— 只量不赋等于量的是上一段的宽度，循环一次都不触发，
	 *       长文本直接撑爆面板；
	 *    ② 必须有 FIT_MAX_STEPS 硬上界 —— `'…' + substr(1)` 每轮把省略号加回来、
	 *       长度恒定不变，所以只判 `t.length > 4` 是**死循环**（100% CPU 卡死）。
	 */
	function applyValue(val:FlxText, i:Int):Void
	{
		var r:BackupRow = rows[i];
		if (r.kind == BackupKind.TOGGLE)
		{
			val.visible = false;
			return;
		}
		val.visible = true;
		if (r.longValue)
		{
			val.setFormat(Paths.font('future.ttf'), VALUE_SMALL_SIZE, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			var t:String = (r.value == null || r.value.length == 0) ? '-' : r.value;
			val.text = t;

			// 第一遍：按实测整串宽度**一次性**估出能放下的字符数（比例估算，留 8% 余量给字宽不均）
			var fullW:Float = val.width;
			if (fullW > VALUE_MAX_W && t.length > 5)
			{
				var keep:Int = Math.floor(t.length * (VALUE_MAX_W / fullW) * 0.92) - 1;
				if (keep < 4) keep = 4;
				if (keep > t.length - 1) keep = t.length - 1;
				t = '…' + t.substr(t.length - keep);
				val.text = t;

				// 第二遍：比例估算不准时逐字符收尾。
				// ⚠ 这里**只截不加**（不加回省略号）—— 长度严格递减，配合 step 硬上界双重保证终止。
				//    写成 `'…' + t.substr(1)` 会让长度恒定 → 只判 t.length > 4 就是死循环。
				var step:Int = 0;
				while (val.width > VALUE_MAX_W && step < FIT_MAX_STEPS && t.length > 4)
				{
					t = t.substr(1);
					val.text = t;
					step++;
				}
			}
		}
		else
		{
			val.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.text = r.value;
		}
		val.x = VALUE_RIGHT - val.width;
	}

	function notify(msg:String):Void
	{
		hintText.text = msg;
		hintText.alpha = 1;
	}

	function buildRows():Void
	{
		var doIt:String = Lang.tOr('backup.exportDo', '导出');
		var restoreDo:String = Lang.tOr('backup.restoreDo', '还原');

		rows = [
			new BackupRow(Lang.tOr('backup.portable', '携带模式（设置跟着引擎目录走）'),
				'', BackupKind.TOGGLE, function() return CoolUtil.isPortable(), function() {
					var now:Bool = CoolUtil.setPortable(!CoolUtil.isPortable());
					notify(now ? Lang.tOr('backup.portableOn', '已开启：下次启动后设置写入引擎目录')
						: Lang.tOr('backup.portableOff', '已关闭：下次启动后恢复系统目录'));
				}, null),

			new BackupRow(Lang.tOr('backup.includeReplays', '打包回放录像（仅 zip / msb）'),
				'', BackupKind.TOGGLE, function() return ClientPrefs.data.backupIncludeReplays, function() {
					ClientPrefs.data.backupIncludeReplays = !ClientPrefs.data.backupIncludeReplays;
				}, null),

			new BackupRow(Lang.tOr('backup.includeCache', '打包谱面缓存（仅 zip / msb，几 GB）'),
				'', BackupKind.TOGGLE, function() return ClientPrefs.data.backupIncludeCache, function() {
					ClientPrefs.data.backupIncludeCache = !ClientPrefs.data.backupIncludeCache;
				}, null),

			new BackupRow(Lang.tOr('backup.replaysFollow', '回放跟随携带模式'),
				'', BackupKind.TOGGLE, function() return ClientPrefs.data.portableReplays, function() {
					ClientPrefs.data.portableReplays = !ClientPrefs.data.portableReplays;
				}, null),

			new BackupRow(Lang.tOr('backup.dst', '备份输出目录'), SaveMover.backupDir(), BackupKind.INFO, null, null, null, true),

			new BackupRow(Lang.tOr('backup.exportZip', '导出 · zip 原始包'), doIt, BackupKind.ACTION, null, null, function() {
				var p:String = SaveMover.exportBackup(BackupFormat.ZIP, ClientPrefs.data.backupIncludeReplays, ClientPrefs.data.backupIncludeCache);
				notify(p == null ? Lang.tOr('backup.fail', '失败：没有可打包的数据')
					: Lang.tOr('backup.done', '已导出') + ' → ' + p);
			}),

			new BackupRow(Lang.tOr('backup.exportBin', '导出 · msb 自定义二进制'), doIt, BackupKind.ACTION, null, null, function() {
				var p:String = SaveMover.exportBackup(BackupFormat.BINARY, ClientPrefs.data.backupIncludeReplays, ClientPrefs.data.backupIncludeCache);
				notify(p == null ? Lang.tOr('backup.fail', '失败：没有可打包的数据')
					: Lang.tOr('backup.done', '已导出') + ' → ' + p);
			}),

			new BackupRow(Lang.tOr('backup.exportJson', '导出 · json 结构化'), doIt, BackupKind.ACTION, null, null, function() {
				var p:String = SaveMover.exportBackup(BackupFormat.JSON, false, false);
				notify(p == null ? Lang.tOr('backup.fail', '设置尚未初始化') : Lang.tOr('backup.done', '已导出') + ' → ' + p);
			}),

			new BackupRow(Lang.tOr('backup.import', '从最新备份还原'), restoreDo, BackupKind.ACTION, null, null, function() {
				var z:String = SaveMover.latestBackup();
				if (z == null)
				{
					notify(Lang.tOr('backup.noBackup', '输出目录里没有备份文件'));
					return;
				}
				var n:Int = SaveMover.restore(z);
				notify(n < 0 ? Lang.tOr('backup.fail', '还原失败')
					: Lang.tOr('backup.restored', '已还原') + ' ' + n + Lang.tOr('backup.files', ' 个文件') + '，建议重启引擎');
			})
		];
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Null<Int> = null, ?border:Null<Int> = null):FlxSprite
	{
		// 参数默认值必须是**编译期常量**，不能写 DesignTokens.panelFill（运行时求值会被 Haxe 拒绝），
		// 故默认传 null、在此解析 —— 同时保证取到的是「当前主题」的值，而不是类加载时的快照。
		if (fill == null) fill = DesignTokens.panelFill;
		if (border == null) border = DesignTokens.panelOutline;
		// ⚠ unique = true：同尺寸+同色会命中缓存里同一张 BitmapData，原地重绘会波及其它精灵。
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}
}
