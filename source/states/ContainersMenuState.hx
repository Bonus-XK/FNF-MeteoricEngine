package states;

import backend.ClientPrefs;
import backend.ContainerInfo;
import backend.ContainerLauncher;
import backend.ContainerManifestData;
import backend.ContainerManifestParser;
import backend.ContainerSession;
import backend.ContainerStore;
import backend.MusicBeatState;
import backend.Paths;
import backend.WeekData;
import backend.WheelScroll;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

import objects.BackButton;

import options.OptionsState;

import states.LoadingState;

import openfl.Lib;


#if sys
import sys.FileSystem;
#end

/**
 * 容器管理界面（系统域 · MD3）。
 *
 * 设计依据：skills/meteoric-design（系统域圆角面板 + MD3 令牌）与 skills/meteoric-system
 * （三套输入、统一动效）。左侧容器列表，右侧详情/自检，底部操作条。
 *
 * 交互：
 *  - 键盘：↑/↓（或 W/S）选择，Enter/空格 启动，Esc/Backspace 返回，R 重新扫描
 *  - 鼠标：点击行=选中，双击行或点「切换到此容器」=启动；滚轮滚动列表
 *  - 触控：滑动滚动列表（Main.processTouchScroll 合成滚轮事件），点击等同鼠标
 */
class ContainersMenuState extends MusicBeatState
{
	// ===== 布局（1280×720 基准） =====
	static final PANEL_L_X:Float = 40;
	static final PANEL_L_Y:Float = 96;
	static final PANEL_L_W:Float = 700;
	static final PANEL_L_H:Float = 520;

	static final PANEL_R_X:Float = 760;
	static final PANEL_R_Y:Float = 96;
	static final PANEL_R_W:Float = 480;
	static final PANEL_R_H:Float = 520;

	static final LIST_X:Float = 72;
	static final LIST_Y:Float = 168;
	static final ROW_GAP:Float = 46;
	static final ROWS_VISIBLE:Int = 9;

	// ===== MD3 令牌（与 Options/Mods 系统域一致） =====
	static final TEXT_PRIMARY:Int = 0xFFD7D7E0;
	static final TEXT_MUTED:Int = 0xFFCFCFDC;
	static final TEXT_DIM:Int = 0xFF9A9AA8;
	static final ACCENT:Int = 0xFFFFD9A0;
	static final ACCENT_CYAN:Int = 0xFF33E0FF;
	static final DANGER:Int = 0xFFFF6B6B;
	static final ROW_SEL:Int = 0x3AFFFFFF;

	var wheelScroll:WheelScroll = new WheelScroll();

	var containers:Array<ContainerInfo> = [];
	var curSelected:Int = 0;
	var scrollOffset:Int = 0;

	var rowTexts:Array<FlxText> = [];
	var rowBars:Array<FlxSprite> = [];

	var statusText:FlxText;
	var emptyText:FlxText;
	/** 最近一次操作的错误文案（非 null 时状态行显示红色，且不被默认状态覆盖）。 */
	var statusError:String = null;
	/** 最近一次操作的中性提示（非 null 时状态行显示它，优先于默认状态）。 */
	var statusInfo:String = null;

	// 详情区
	var detName:FlxText;
	var detMeta:FlxText;
	var detDesc:FlxText;
	var detPath:FlxText;
	var detProblem:FlxText;
	var detHint:FlxText;

	var toggleBtn:ContainerButton;
	var switchBtn:ContainerButton;
	var rescanBtn:ContainerButton;
	var folderBtn:ContainerButton;
	var backBtn:BackButton;

	// 鼠标/键盘输入分离（与 MainMenuState / ModsMenuState 同款）
	var mouseActive:Bool = true;
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	static final MOUSE_REACTIVATE_DIST:Float = 10;
	var lastClickIndex:Int = -1;
	var lastClickTime:Float = 0;
	static final DOUBLE_CLICK_TIME:Float = 0.35;

	var selectedSomethin:Bool = false;

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		WeekData.setDirectoryFromWeek();

		#if desktop
		DiscordClient.changePresence("In the Menus", null);
		#end

		Lib.application.window.title = "FNF':Meteoric Engine - Containers";

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		// ---- 面板 ----
		add(makePanel(PANEL_L_X, PANEL_L_Y, PANEL_L_W, PANEL_L_H, 22));
		add(makePanel(PANEL_R_X, PANEL_R_Y, PANEL_R_W, PANEL_R_H, 22));
		add(makePanel(40, 636, 1200, 56, 14));

		// ---- 标题 ----
		var leftTitle:FlxText = new FlxText(LIST_X, 112, 0, '容器列表', 26);
		leftTitle.setFormat(Paths.font('future.ttf'), 26, TEXT_PRIMARY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		leftTitle.borderSize = 2;
		leftTitle.scrollFactor.set();
		add(leftTitle);

		var rightTitle:FlxText = new FlxText(PANEL_R_X + 32, 112, 0, '容器详情', 26);
		rightTitle.setFormat(Paths.font('future.ttf'), 26, TEXT_PRIMARY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rightTitle.borderSize = 2;
		rightTitle.scrollFactor.set();
		add(rightTitle);

		var subTitle:FlxText = new FlxText(LIST_X, 142, 0, '放入 ' + ContainerStore.CONTAINERS_DIR + '/<名称>/ 后点「重新扫描」', 15);
		subTitle.setFormat(Paths.font('future.ttf'), 15, TEXT_DIM, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		subTitle.scrollFactor.set();
		add(subTitle);

		// ---- 列表行 ----
		for (i in 0...ROWS_VISIBLE)
		{
			var bar:FlxSprite = new FlxSprite(LIST_X - 14, LIST_Y + i * ROW_GAP - 6)
				.makeGraphic(Std.int(PANEL_L_W - 56), Std.int(ROW_GAP - 8), FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRoundRect(bar, 0, 0, PANEL_L_W - 56, ROW_GAP - 8, 10, 10, ROW_SEL);
			bar.scrollFactor.set();
			bar.visible = false;
			add(bar);
			rowBars.push(bar);

			var t:FlxText = new FlxText(LIST_X, LIST_Y + i * ROW_GAP, Std.int(PANEL_L_W - 90), '', 19);
			t.setFormat(Paths.font('future.ttf'), 19, TEXT_MUTED, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.borderSize = 1.5;
			t.scrollFactor.set();
			add(t);
			rowTexts.push(t);
		}

		emptyText = new FlxText(LIST_X, LIST_Y + 40, Std.int(PANEL_L_W - 90),
			'（还没有容器）\n\n把目标引擎放进：\n' + ContainerStore.containersRoot() + '/<名称>/\n'
			+ '再补一个 ' + ContainerManifestParser.FILE_NAME + '（见 CONTAINERS.md 示例）', 17);
		emptyText.setFormat(Paths.font('future.ttf'), 17, TEXT_DIM, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyText.borderSize = 1.5;
		emptyText.scrollFactor.set();
		add(emptyText);

		// ---- 详情 ----
		var dx:Float = PANEL_R_X + 32;
		var dw:Int = Std.int(PANEL_R_W - 64);

		detName = makeDetail(dx, 158, dw, '', 21, ACCENT);
		detMeta = makeDetail(dx, 194, dw, '', 16, TEXT_MUTED);
		detDesc = makeDetail(dx, 232, dw, '', 16, TEXT_MUTED);
		detPath = makeDetail(dx, 424, dw, '', 13, TEXT_DIM);
		detProblem = makeDetail(dx, 520, dw, '', 16, DANGER);
		detHint = makeDetail(dx, 588, dw, '', 14, TEXT_DIM);

		// ---- 底部操作条 ----
		// 布局：4 键等宽贴合 40..1240 的操作条（1200 宽）。
		// 顺序按使用频率：开关（首次必须点）→ 切换 → 重新扫描 → 打开文件夹。
		toggleBtn = new ContainerButton(52, 642, 250, 44, '', function() toggleEnabled());
		switchBtn = new ContainerButton(314, 642, 250, 44, '切换到此容器', function() attemptLaunch());
		rescanBtn = new ContainerButton(576, 642, 210, 44, '重新扫描', function() refresh(true));
		folderBtn = new ContainerButton(798, 642, 260, 44, '打开日志/容器目录', function() openSelectedFolder());
		add(toggleBtn);
		add(switchBtn);
		add(rescanBtn);
		add(folderBtn);
		toggleBtn.spr.color = 0xFFCFE8FF; // 开关按钮轻微着色以示“可点击状态项”
		updateToggleLabel();

		// 状态行挪到操作条上方：底部右侧位置已被第 4 个按钮占用
		statusText = new FlxText(44, 620, 1192, '', 14);
		statusText.setFormat(Paths.font('future.ttf'), 14, TEXT_DIM, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.borderSize = 1.5;
		statusText.scrollFactor.set();
		add(statusText);

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		// ---- 数据 ----
		refresh(false);

		// 会话提示（从容器回来时由 ContainerSession.notice 写入）：只显示一次
		if (ContainerSession.notice != null)
		{
			// 从容器回来（尤其目标引擎秒退/崩溃）时这条提示必须留住：它带退出码，
			// 是玩家判断“为什么没进去”的唯一线索。
			statusInfo = ContainerSession.notice;
			ContainerSession.notice = null;
		}

		transIn = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;

		// 本界面全鼠标可交互（列表行命中、双击启动、四个按钮），必须显式开鼠标：
		// MusicBeatState 不会自动开，OptionsState 是在 destroy 里关的，谁开谁关。
		FlxG.mouse.visible = true;

		super.create();
	}

	function makeDetail(x:Float, y:Float, w:Int, text:String, size:Int, color:Int):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('future.ttf'), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		add(t);
		return t;
	}

	// ───────────────────────── 数据 ─────────────────────────

	function refresh(?keepSelection:Bool):Void
	{
		var prevFolder:String = null;
		if (keepSelection && curSelected >= 0 && curSelected < containers.length)
			prevFolder = containers[curSelected].folder;

		containers = ContainerStore.scan();
		if (containers == null) containers = [];

		curSelected = 0;
		if (prevFolder != null)
		{
			for (i in 0...containers.length)
				if (containers[i].folder == prevFolder)
				{
					curSelected = i;
					break;
				}
		}
		scrollOffset = 0;
		updateRows();
		updateDetails();
	}

	function visibleRows():Int
	{
		return Std.int(Math.min(ROWS_VISIBLE, containers.length));
	}

	function updateRows():Void
	{
		var count:Int = containers.length;

		emptyText.visible = (count < 1);

		if (count > 0)
		{
			var maxOffset:Int = Std.int(Math.max(0, count - ROWS_VISIBLE));
			if (scrollOffset > maxOffset) scrollOffset = maxOffset;
			if (scrollOffset < 0) scrollOffset = 0;
		}
		else
			scrollOffset = 0;

		for (i in 0...ROWS_VISIBLE)
		{
			var idx:Int = scrollOffset + i;
			var t:FlxText = rowTexts[i];
			var bar:FlxSprite = rowBars[i];
			if (idx >= count)
			{
				t.text = '';
				bar.visible = false;
				continue;
			}
			var info:ContainerInfo = containers[idx];
			var ready:Bool = ContainerSession.isReady(info);
			var mark:String = ready ? '' : '⚠ ';
			var engineTxt:String = (info.engine != null && info.engine.length > 0) ? ('  ·  ' + info.engine) : '';
			t.text = mark + (idx + 1) + '. ' + info.displayName + engineTxt;
			t.color = ready ? (idx == curSelected ? ACCENT : TEXT_MUTED) : DANGER;
			bar.visible = (idx == curSelected);
		}

		var activeFolder:String = (ContainerSession.current != null) ? ContainerSession.current.folder : null;
		if (activeFolder != null)
		{
			for (i in 0...ROWS_VISIBLE)
			{
				var idx:Int = scrollOffset + i;
				if (idx < count && containers[idx].folder == activeFolder)
				{
					rowTexts[i].text += '   ← 运行中';
					break;
				}
			}
		}
	}

	function updateDetails():Void
	{
		if (containers.length < 1)
		{
			detName.text = '—';
			detMeta.text = '';
			detDesc.text = '';
			detPath.text = '';
			detProblem.text = '';
			detHint.text = '提示：先点左下「容器功能」开关打开功能，再把目标引擎放进容器文件夹，\n然后点「重新扫描」。容器与本体 mod 完全隔离。';
			switchBtn.visible = false;
			return;
		}

		var info:ContainerInfo = containers[curSelected];
		detName.text = info.displayName;

		var meta:String = '';
		if (info.version != null && info.version.length > 0) meta += '版本 ' + info.version + '   ';
		if (info.engine != null && info.engine.length > 0) meta += '目标引擎 ' + info.engine + '   ';
		if (info.author != null && info.author.length > 0) meta += '作者 ' + info.author;
		detMeta.text = meta;

		detDesc.text = (info.description != null && info.description.length > 0) ? info.description : '（无描述）';

		var pathTxt:String = '目录：' + info.path + '\n主程序：' + (info.appPath == null ? '未找到' : info.appPath);
		detPath.text = pathTxt;

		detProblem.text = (info.problem != null) ? ('⚠ ' + info.problem) : '';

		var data:ContainerManifestData = (info.manifest != null) ? info.manifest.raw : null;
		var exitMode:String = ContainerManifestParser.str(data, 'exitMode', 'terminate');
		var wait:Float = ContainerManifestParser.num(data, 'waitSeconds', ContainerLauncher.DEFAULT_WAIT);
		var hotkeyTxt:String = describeHotkey();
		detHint.text = '退出方式 ' + exitMode + '   ·   等待窗口 ' + wait + 's\n'
			+ '退出容器：直接关掉目标引擎窗口，Meteoric 会自动唤醒并重启\n'
			+ '返回热键 ' + hotkeyTxt + hotkeyHowto()
			+ '\n退出后 Meteoric 会自动重启（本体整机复位）';

		switchBtn.visible = true;
		switchBtn.setEnabled(ContainerSession.isReady(info) && !ContainerSession.active);
	}

	/** 把绑定的 FlxKey 值还原成可读名字（用于详情区提示）。 */
	function describeHotkey():String
	{
		var keys:Array<flixel.input.keyboard.FlxKey> = ClientPrefs.data.containerExitKeys;
		if (keys == null || keys.length < 1) return '（未绑定）';
		var out:Array<String> = [];
		for (k in keys)
		{
			// FlxKey 是 abstract Int：静态平台上不可为 null，不做判空（编译期实证）
			out.push(backend.InputFormatter.getKeyName(k));
		}
		return out.length > 0 ? out.join(' + ') : '（未绑定）';
	}

	/**
	 * 热键使用说明。两个平台的语义**不同**，不能写死一句：
	 *  - Windows：单键（默认 F10），直接按即可；
	 *  - macOS / Linux：真组合键（CONTROL 按住 + C 刚按下），单按任一键都不触发。
	 * 另外两平台都受同一条限制：目标引擎拿到焦点后按键进它，宿主收不到 —— 所以「关窗口」才是主路径。
	 */
	function hotkeyHowto():String
	{
		#if windows
		return '（单键，直接按；目标引擎在前台时按键进它，此时请关窗口退出）';
		#else
		return '（组合键：先按住 CONTROL 再按 C；目标引擎在前台时按键进它，此时请关窗口退出）';
		#end
	}

	// ───────────────────────── 交互 ─────────────────────────

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (selectedSomethin) return;

		if (FlxG.mouse.justMoved || FlxG.mouse.justPressed || FlxG.mouse.wheel != 0)
		{
			var dx:Float = FlxG.mouse.screenX - mouseLockX;
			var dy:Float = FlxG.mouse.screenY - mouseLockY;
			if (FlxG.mouse.justPressed || FlxG.mouse.wheel != 0 || dx * dx + dy * dy > MOUSE_REACTIVATE_DIST * MOUSE_REACTIVATE_DIST)
				mouseActive = true;
		}

		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		var clickPressed:Bool = FlxG.mouse.justPressed;

		// ---- 返回 ----
		if (controls.BACK || (clickPressed && backBtn.over(mx, my)))
		{
			exitToOptions();
			return;
		}

		// ---- 按钮 ----
		if (clickPressed)
		{
			if (switchBtn.visible && switchBtn.over(mx, my))
			{
				attemptLaunch();
				return;
			}
			if (toggleBtn.over(mx, my))
			{
				toggleEnabled();
				return;
			}
			if (rescanBtn.over(mx, my))
			{
				refresh(true);
				setInfo('已重新扫描：' + containers.length + ' 个容器');
				return;
			}
			if (folderBtn.over(mx, my))
			{
				openSelectedFolder();
				return;
			}
		}

		if (mouseActive)
		{
			toggleBtn.setHovered(mx, my);
			switchBtn.setHovered(mx, my);
			rescanBtn.setHovered(mx, my);
			folderBtn.setHovered(mx, my);
			backBtn.setHovered(mx, my);
		}

		// ---- 滚轮/触控滑动（WheelScroll 约定：上滚 = -1 选中上一个，与 MainMenu 一致） ----
		var wheelStep:Int = wheelScroll.process(FlxG.mouse.wheel);
		if (wheelStep != 0)
		{
			mouseActive = true;
			changeSelection(wheelStep);
		}

		// ---- 列表行命中 ----
		if (clickPressed)
		{
			var hit:Int = rowAt(mx, my);
			if (hit >= 0)
			{
				if (hit != curSelected)
				{
					curSelected = hit;
					updateRows();
					updateDetails();
					lastClickIndex = hit;
					lastClickTime = 0;
				}
				else if (lastClickIndex == hit && lastClickTime <= DOUBLE_CLICK_TIME)
				{
					attemptLaunch(); // 双击同一行 = 启动
					return;
				}
				else
				{
					lastClickIndex = hit;
					lastClickTime = 0;
				}
				mouseLockX = mx;
				mouseLockY = my;
			}
		}
		if (lastClickTime <= DOUBLE_CLICK_TIME) lastClickTime += elapsed;

		// ---- 键盘 ----
		var upPressed:Bool = controls.UI_UP_P;
		var downPressed:Bool = controls.UI_DOWN_P;
		if (upPressed || downPressed)
		{
			mouseActive = false;
			mouseLockX = mx;
			mouseLockY = my;
			changeSelection(upPressed ? -1 : 1);
		}
		if (FlxG.keys != null && FlxG.keys.justPressed.R) rescanBtn.onClick();
		if (controls.ACCEPT) attemptLaunch();

		updateStatusText();
	}

	/** 鼠标命中的行索引（-1 = 未命中）。 */
	function rowAt(mx:Float, my:Float):Int
	{
		if (mx < LIST_X - 14 || mx > LIST_X - 14 + PANEL_L_W - 56) return -1;
		for (i in 0...ROWS_VISIBLE)
		{
			var top:Float = LIST_Y + i * ROW_GAP - 6;
			if (my >= top && my <= top + ROW_GAP - 8)
			{
				var idx:Int = scrollOffset + i;
				return (idx < containers.length) ? idx : -1;
			}
		}
		return -1;
	}

	function changeSelection(change:Int):Void
	{
		if (containers.length < 1) return;
		curSelected += change;
		if (curSelected < 0) curSelected = containers.length - 1;
		if (curSelected >= containers.length) curSelected = 0;

		// 跟随滚动
		if (curSelected < scrollOffset) scrollOffset = curSelected;
		if (curSelected >= scrollOffset + ROWS_VISIBLE) scrollOffset = curSelected - ROWS_VISIBLE + 1;

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		updateRows();
		updateDetails();
	}

	// ───────────────────────── 动作 ─────────────────────────

	/** 切换容器功能总开关（写 ClientPrefs 并落盘）。 */
	function toggleEnabled():Void
	{
		ClientPrefs.data.containersEnabled = !ClientPrefs.data.containersEnabled;
		ClientPrefs.saveSettings();
		updateToggleLabel();
		updateDetails();
		setInfo(ClientPrefs.data.containersEnabled
			? '容器功能已启用 —— 选中容器后按 Enter 或点「切换到此容器」'
			: '容器功能已关闭（关闭后不允许启动容器）');
	}

	/** 同步开关按钮文案与配色（启用=强调色，关闭=暗色）。 */
	function updateToggleLabel():Void
	{
		var on:Bool = ClientPrefs.data.containersEnabled;
		toggleBtn.label.text = on ? '容器功能：已启用' : '容器功能：已关闭';
		toggleBtn.label.color = on ? 0xFFFFD9A0 : 0xFF9A9AA8;
	}

	/**
	 * 状态行统一刷新。
	 * 修复：原实现在 update() 里每帧写 `ContainerSession.active ? statusLine() : '容器功能：…'`，
	 * 会把 attemptLaunch() 刚写进去的错误文案在**同一帧**覆盖掉 —— 玩家侧表现就是
	 * “点了切换毫无反应”。现在错误/提示有粘性，直到下一次操作或成功启动才清除。
	 */
	function updateStatusText():Void
	{
		if (statusError != null)
		{
			statusText.text = '⚠ ' + statusError;
			statusText.color = DANGER;
			return;
		}
		statusText.color = TEXT_DIM;
		if (ContainerSession.active)
		{
			statusText.text = ContainerSession.statusLine();
			return;
		}
		if (statusInfo != null)
		{
			statusText.text = statusInfo;
			return;
		}
		statusText.text = '容器功能：' + (ClientPrefs.data.containersEnabled ? '已启用' : '已在设置中关闭')
			+ '   ·   选中容器后按 Enter 或点「切换到此容器」';
	}

	function setError(msg:String):Void
	{
		statusError = msg;
		statusInfo = null;
		updateStatusText();
	}

	function setInfo(msg:String):Void
	{
		statusInfo = msg;
		statusError = null;
		updateStatusText();
	}

	function attemptLaunch():Void
	{
		if (selectedSomethin) return;
		if (containers.length < 1)
		{
			setError('没有可启动的容器');
			return;
		}
		var info:ContainerInfo = containers[curSelected];

		if (ContainerSession.active)
		{
			// 会话进行中：Enter 语义改为“请求当前容器退出”
			ContainerSession.requestQuit();
			setInfo('已请求退出「' + (ContainerSession.current != null ? ContainerSession.current.displayName : '?') + '」…');
			return;
		}

		if (!ClientPrefs.data.containersEnabled)
		{
			setError('容器功能未启用：点左下「容器功能：已关闭」按钮打开');
			return;
		}

		var err:String = ContainerSession.launch(info);
		if (err != null)
		{
			setError('启动失败：' + err);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			return;
		}

		selectedSomethin = true;
		statusError = null;
		statusInfo = null;
		FlxG.sound.play(Paths.sound('confirmMenu'));
		updateStatusText();
		// 不做场景切换：会话状态机由 Main 的每帧钩子驱动，Meteoric 会在 1 秒内让位并挂起
	}

	/** 打开当前选中容器的 runtime 目录（排障：container.log / exit.txt / wrapper.sh 都在这里）。 */
	function openSelectedFolder():Void
	{
		var target:String = ContainerStore.containersRoot();
		if (containers.length > 0 && curSelected >= 0 && curSelected < containers.length)
		{
			var info:ContainerInfo = containers[curSelected];
			var rt:String = ContainerStore.join(info.path, ContainerStore.RUNTIME_DIR);
			target = ContainerStore.dirExists(rt) ? rt : info.path;
		}
		#if mac
		Sys.command('/usr/bin/open', [target]);
		#elseif windows
		Sys.command('explorer', [target]);
		#else
		Sys.command('xdg-open', [target]);
		#end
		setInfo('已打开：' + target);
	}

	function exitToOptions():Void
	{
		if (selectedSomethin) return;
		selectedSomethin = true;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		LoadingState.loadAndSwitchState(new OptionsState());
		OptionsState.onPlayState = false;
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}

	// ───────────────────────── 面板绘制 ─────────────────────────

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}
}

/**
 * 系统域圆角按钮（MD3 令牌；与 ModsMenuState 的按钮同款观感，独立成类避免跨模块耦合）。
 */
class ContainerButton extends FlxSpriteGroup
{
	public var onClick:Void->Void;
	public var spr:FlxSprite;
	/** 按钮文字：开关类按钮需要运行期改文案/配色（ContainerButton 是本文件私有类，公开无风险）。 */
	public var label:FlxText;
	public var btnW:Float;
	public var btnH:Float;
	var hovered:Bool = false;
	var awake:Bool = false;
	var lastX:Float = 0;
	var lastY:Float = 0;
	var enabled:Bool = true;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, ?cb:Void->Void)
	{
		super(x, y);
		onClick = cb;
		btnW = w;
		btnH = h;

		spr = new FlxSprite().makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, 14, 14, 0x66161622);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, 14, 14, FlxColor.TRANSPARENT, {color: 0x8CFFFFFF, thickness: 1.5});
		spr.alpha = 0.85;
		spr.scrollFactor.set();
		add(spr);

		label = new FlxText(0, 0, Std.int(w), text, 18);
		label.setFormat(Paths.font('future.ttf'), 18, 0xFFCFCFDC, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.5;
		label.textField.height = 44;
		label.scrollFactor.set();
		label.y = 12;
		add(label);

		scrollFactor.set();
		lastX = FlxG.mouse.screenX;
		lastY = FlxG.mouse.screenY;
	}

	public function setEnabled(v:Bool):Void
	{
		enabled = v;
		alpha = v ? 1 : 0.45;
	}

	public function over(mx:Float, my:Float):Bool
	{
		if (!visible || !enabled) return false;
		return mx >= x && mx <= x + btnW && my >= y && my <= y + btnH;
	}

	public function setHovered(mx:Float, my:Float)
	{
		if (!awake)
		{
			var dx:Float = mx - lastX;
			var dy:Float = my - lastY;
			if (dx * dx + dy * dy < 100) return;
			awake = true;
		}
		lastX = mx;
		lastY = my;

		var v:Bool = over(mx, my);
		if (hovered == v) return;
		hovered = v;
		spr.color = v ? 0xFFFFFFFF : 0xFFD5D9DF;
		spr.alpha = v ? 1 : 0.85;
	}
}
