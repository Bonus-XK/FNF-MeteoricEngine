package states;

import backend.Multiplayer;
import backend.DiscoveredRoom;
import backend.WeekData;
import backend.Difficulty;
import backend.Highscore;
import backend.Mods;
import objects.BackButton;
import objects.UIInputBox;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

/**
 * 联机大厅（两页制）：
 *  - home  页：创建房间 / 加入房间（IP 直连）+ 昵称输入
 *  - lobby 页：玩家列表区 + 房间信息区 + 选曲区 + 状态提示区
 * 交互以鼠标为主（点击菜单/选曲/难度/滚动/确认按钮），键盘导航仅作辅助；
 * 输入框聚焦（打字）期间完全屏蔽游戏键位，避免 W/A/S/D/E/Esc 冲突。
 */
typedef MouseBtn = {
	label:FlxText,
	x:Float,
	y:Float,
	w:Float,
	h:Float,
	base:FlxColor,
	cb:Void->Void
}

class OnlineMenuState extends MusicBeatState
{
	static final THEME:FlxColor = 0xFF8AD7FF;      // 联机主题色（主菜单联机项同款）
	static final PANEL_FILL:FlxColor = 0xCC161622;  // 圆角磨砂面板底色
	static final TEXT_GRAY:FlxColor = 0xFFA9A9B8;
	static final TEXT_LIGHT:FlxColor = 0xFFD7D7E0;

	/** 由 PlayState / 断线检测写入：回到大厅时展示原因 */
	public static var notifyReason:String = '';
	/** 对局结算关闭后保持连接直接进入房间大厅（由 PlayState 写入，进入即消费） */
	public static var openInLobby:Bool = false;

	var page:String = 'home'; // home / discover / lobby
	var joinMode:Bool = false; // home 页内的「加入房间」输入态

	// ---- home 页 ----
	var panelHome:FlxSprite;
	var homeTitle:FlxText;
	var homeSub:FlxText;
	var homeItems:Array<String> = ['创建房间', '加入房间', '发现房间'];
	var homeTexts:Array<FlxText> = [];
	var homeSelected:Int = 0;
	var nickLabel:FlxText;
	var nickInput:UIInputBox;
	var ipLabel:FlxText;
	var ipInput:UIInputBox;
	var connectBtnLabel:FlxText;

	// ---- discover 页（局域网房间自动发现） ----
	var discoverTitle:FlxText;
	var discoverPanel:FlxSprite;
	var discoverRows:Array<FlxText> = [];
	var discoverStatus:FlxText;
	var discoverHint:FlxText;

	// ---- lobby 页 ----
	var panelPlayer:FlxSprite;
	var panelRoom:FlxSprite;
	var panelSong:FlxSprite;
	var lobbyTitle:FlxText;
	var playerListTitle:FlxText;
	var playerRows:Array<FlxText> = [];
	var roomInfoTitle:FlxText;
	var roomInfoText:FlxText;
	var songCardTitle:FlxText;
	var songHeader:FlxText;
	var songRows:Array<FlxText> = [];
	var songFooter:FlxText;
	var diffLeftLabel:FlxText;
	var diffRightLabel:FlxText;
	var scrollUpLabel:FlxText;
	var scrollDownLabel:FlxText;
	var hostSendLabel:FlxText;

	// ---- 鼠标按钮注册表 ----
	var mouseBtns:Array<MouseBtn> = [];

	// ---- 公共 ----
	var statusText:FlxText;
	var backBtn:BackButton;

	// ---- 数据 ----
	var songs:Array<String> = [];
	var songFolders:Map<String, String> = new Map();
	var songCur:Int = 0;
	var selectedDiff:Int = 0;
	var receivedSong:String = '';
	var receivedDiff:String = '';
	var hostSelected:Bool = false;
	var selectPayload:String = ''; // song~diff~modDir~mv~nj~ro
	var lastPlayerCount:Int = 0;
	var fatalHandled:Bool = false; // 本帧已处理 FULL/断线，跳过后续重复提示

	override function create()
	{
		super.create();

		// 每次进入联机界面：关闭上一局遗留的联机标记
		PlayState.isOnlineMode = false;
		PlayState.onlineHoldCountdown = false;

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		add(bg);

		buildHomePage();
		buildDiscoverPage();
		buildLobbyPage();
		buildCommon();

		loadSongs();

		// 对局结算后保持连接回房：直接落在房间大厅（房主侧玩家数记为 1——客户端仍在连接中）
		if (openInLobby)
		{
			openInLobby = false;
			page = 'lobby';
			if (Multiplayer.isHost) lastPlayerCount = 1;
		}
		applyPage();

		if (notifyReason != '')
		{
			statusText.text = notifyReason;
			notifyReason = '';
		}
	}

	// ==================== 界面构建 ====================

	function buildHomePage():Void
	{
		homeTitle = makeCenterText(0, 46, FlxG.width, '联机模式', 52, FlxColor.WHITE);
		homeTitle.antialiasing = true;
		add(homeTitle);
		homeSub = makeCenterText(0, 118, FlxG.width, '局域网 1v1 实时对战 · 分数高者胜', 20, THEME);
		homeSub.antialiasing = true;
		add(homeSub);

		panelHome = makePanel(260, 170, 760, 400);
		add(panelHome);

		// 创建房间 / 加入房间 / 发现房间（鼠标点击，键盘辅助；不注册进 mouseBtns——home 行有独立 hover/点击块）
		for (i in 0...homeItems.length)
		{
			var t:FlxText = new FlxText(340, 200 + i * 72, 420, homeItems[i], 36);
			t.setFormat(Paths.font('future.ttf'), 36, (i == 0 ? FlxColor.WHITE : TEXT_GRAY), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.antialiasing = true;
			add(t);
			homeTexts.push(t);
		}

		nickLabel = new FlxText(340, 425, 0, '昵称：', 24);
		nickLabel.setFormat(Paths.font('future.ttf'), 24, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(nickLabel);
		nickInput = new UIInputBox(450, 412, 300, 42, Multiplayer.myNick == '玩家' ? '玩家' : Multiplayer.myNick, 22);
		add(nickInput);

		ipLabel = new FlxText(340, 482, 0, '房主 IP（不带端口）：', 24);
		ipLabel.setFormat(Paths.font('future.ttf'), 24, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(ipLabel);
		ipInput = new UIInputBox(450, 472, 300, 42, '192.168.1.100', 22);
		ipInput.onEnter = doConnect;
		add(ipInput);

		connectBtnLabel = addMouseBtn('连 接', 770, 472, 132, 42, 22, doConnect, THEME);

		ipLabel.visible = false;
		ipInput.visible = false;
		connectBtnLabel.visible = false;
	}

	function buildDiscoverPage():Void
	{
		discoverTitle = makeCenterText(0, 46, FlxG.width, '发现房间 · 局域网', 44, FlxColor.WHITE);
		discoverTitle.antialiasing = true;
		add(discoverTitle);

		discoverPanel = makePanel(260, 150, 760, 420);
		add(discoverPanel);

		discoverRows = [];
		for (i in 0...6)
		{
			var t:FlxText = new FlxText(290, 196 + i * 50, 700, '', 22);
			t.setFormat(Paths.font('future.ttf'), 22, TEXT_GRAY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			add(t);
			discoverRows.push(t);
		}

		discoverHint = new FlxText(290, 500, 700, '点击房间行直接加入（已满房间置灰不可加）· 返回键回首页', 16);
		discoverHint.setFormat(Paths.font('future.ttf'), 16, TEXT_GRAY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(discoverHint);

		discoverStatus = new FlxText(290, 526, 700, '正在扫描局域网...', 18);
		discoverStatus.setFormat(Paths.font('future.ttf'), 18, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(discoverStatus);
	}

	function buildLobbyPage():Void
	{
		lobbyTitle = makeCenterText(0, 34, FlxG.width, '房间大厅', 44, FlxColor.WHITE);
		lobbyTitle.antialiasing = true;
		add(lobbyTitle);

		// 玩家列表区
		panelPlayer = makePanel(60, 120, 390, 190);
		add(panelPlayer);
		playerListTitle = new FlxText(80, 136, 350, '玩家 (1/2)', 20);
		playerListTitle.setFormat(Paths.font('future.ttf'), 20, THEME, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(playerListTitle);
		playerRows = [];
		for (i in 0...2)
		{
			var t:FlxText = new FlxText(80, 176 + i * 48, 350, '', 24);
			t.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			add(t);
			playerRows.push(t);
		}

		// 房间信息区
		panelRoom = makePanel(60, 330, 390, 190);
		add(panelRoom);
		roomInfoTitle = new FlxText(80, 346, 350, '房间信息', 20);
		roomInfoTitle.setFormat(Paths.font('future.ttf'), 20, THEME, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(roomInfoTitle);
		roomInfoText = new FlxText(80, 386, 350, '', 20);
		roomInfoText.setFormat(Paths.font('future.ttf'), 20, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(roomInfoText);

		// 选曲区
		panelSong = makePanel(470, 120, 750, 400);
		add(panelSong);
		songCardTitle = new FlxText(490, 136, 640, '选曲', 20);
		songCardTitle.setFormat(Paths.font('future.ttf'), 20, THEME, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(songCardTitle);
		songHeader = new FlxText(490, 166, 640, '', 16);
		songHeader.setFormat(Paths.font('future.ttf'), 16, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(songHeader);
		songRows = [];
		for (i in 0...7)
		{
			var t:FlxText = new FlxText(490, 200 + i * 36, 640, '', 22);
			t.setFormat(Paths.font('future.ttf'), 22, TEXT_GRAY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.visible = false;
			add(t);
			songRows.push(t);
		}
		songFooter = new FlxText(490, 452, 640, '', 18);
		songFooter.setFormat(Paths.font('future.ttf'), 18, TEXT_GRAY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(songFooter);

		// 难度切换 ◀ ▶ / 列表滚动 ▲ ▼ / 房主「发送选曲→开始对局」
		diffLeftLabel = addMouseBtn('◀', 1140, 160, 36, 30, 18, changeDiffLeft, THEME);
		diffRightLabel = addMouseBtn('▶', 1180, 160, 36, 30, 18, changeDiffRight, THEME);
		scrollUpLabel = addMouseBtn('▲', 1140, 200, 36, 30, 18, scrollSong, THEME);
		scrollDownLabel = addMouseBtn('▼', 1140, 234, 36, 30, 18, scrollSongDown, THEME);
		hostSendLabel = addMouseBtn('发送选曲', 1000, 478, 200, 34, 20, hostConfirmAction, THEME);
	}

	function buildCommon():Void
	{
		statusText = new FlxText(60, 545, 1160, '', 18);
		statusText.setFormat(Paths.font('future.ttf'), 18, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(statusText);

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		FlxG.mouse.visible = true;
	}

	function makeCenterText(x:Float, y:Float, w:Float, text:String, size:Int, color:FlxColor):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('future.ttf'), size, color, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		return t;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, 20, 20, PANEL_FILL);
		spr.scrollFactor.set();
		return spr;
	}

	function addMouseBtn(text:String, x:Float, y:Float, w:Float, h:Float, size:Int, cb:Void->Void, base:FlxColor):FlxText
	{
		var t:FlxText = new FlxText(x, y + (h - size) / 2 - 2, w, text, size);
		t.setFormat(Paths.font('future.ttf'), size, base, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.antialiasing = true;
		add(t);
		mouseBtns.push({label: t, x: x, y: y, w: w, h: h, base: base, cb: cb});
		return t;
	}

	function inRect(mx:Float, my:Float, x:Float, y:Float, w:Float, h:Float):Bool
	{
		return mx >= x && mx <= x + w && my >= y && my <= y + h;
	}

	// ==================== 页面与刷新 ====================

	function applyPage():Void
	{
		var isHome:Bool = (page == 'home');
		var isDiscover:Bool = (page == 'discover');
		// 面板按页切换（只显示当前页的面板，杜绝叠图）
		panelHome.visible = isHome;
		panelPlayer.visible = !isHome && !isDiscover;
		panelRoom.visible = !isHome && !isDiscover;
		panelSong.visible = !isHome && !isDiscover;

		homeTitle.visible = isHome;
		homeSub.visible = isHome;
		lobbyTitle.visible = !isHome && !isDiscover;
		discoverTitle.visible = isDiscover;
		discoverPanel.visible = isDiscover;
		for (t in discoverRows) t.visible = isDiscover;
		discoverStatus.visible = isDiscover;
		discoverHint.visible = isDiscover;
		for (t in homeTexts) t.visible = isHome;
		nickLabel.visible = isHome && !joinMode;
		nickInput.visible = isHome && !joinMode;
		ipLabel.visible = isHome && joinMode;
		ipInput.visible = isHome && joinMode;
		connectBtnLabel.visible = isHome && joinMode;

		playerListTitle.visible = !isHome && !isDiscover;
		for (t in playerRows) t.visible = !isHome && !isDiscover;
		roomInfoTitle.visible = !isHome && !isDiscover;
		roomInfoText.visible = !isHome && !isDiscover;
		songCardTitle.visible = !isHome && !isDiscover;
		songHeader.visible = !isHome && !isDiscover;
		for (t in songRows) t.visible = !isHome && !isDiscover;
		songFooter.visible = !isHome && !isDiscover;
		diffLeftLabel.visible = !isHome && !isDiscover;
		diffRightLabel.visible = !isHome && !isDiscover;
		scrollUpLabel.visible = !isHome && !isDiscover;
		scrollDownLabel.visible = !isHome && !isDiscover;
		hostSendLabel.visible = !isHome && !isDiscover && Multiplayer.isHost;

		// 发现页进入/离开：自动监听开关（幂等）
		if (isDiscover)
		{
			Multiplayer.discoveryStart();
			refreshDiscover();
		}
		else
			Multiplayer.discoveryStop();

		if (isHome)
			refreshHome();
		else if (isDiscover)
			refreshDiscover();
		else
			refreshLobby();
	}

	function refreshHome():Void
	{
		for (i in 0...homeTexts.length)
		{
			homeTexts[i].text = homeItems[i];
			homeTexts[i].color = (i == homeSelected) ? FlxColor.WHITE : TEXT_GRAY;
		}
	}

	function changeHomeSelection(change:Int):Void
	{
		homeSelected = (homeSelected + change + homeItems.length) % homeItems.length;
		refreshHome();
	}

	function refreshDiscover():Void
	{
		var rooms:Array<DiscoveredRoom> = Multiplayer.getDiscoveredRooms();
		for (i in 0...discoverRows.length)
		{
			if (i < rooms.length)
			{
				var r:DiscoveredRoom = rooms[i];
				discoverRows[i].visible = true;
				discoverRows[i].text = (r.full ? '　' : '▶ ') + r.hostNick
					+ '　房间 ' + r.roomCode
					+ '　人数 ' + r.playerCount + '/2'
					+ (r.full ? '　[已满]' : '　[可加入]');
				discoverRows[i].color = r.full ? TEXT_GRAY : FlxColor.WHITE;
			}
			else
			{
				discoverRows[i].visible = false;
				discoverRows[i].text = '';
			}
		}
		discoverStatus.text = rooms.length == 0
			? '正在扫描局域网（自动刷新，约 1 秒）...'
			: '发现 ' + rooms.length + ' 个房间 · 点击可加入（约 1 秒自动刷新）';
	}

	function refreshLobby():Void
	{
		// 玩家列表
		if (Multiplayer.isHost)
		{
			playerListTitle.text = '玩家 (' + (1 + lastPlayerCount) + '/2)';
			playerRows[0].text = '★ 房主  ' + Multiplayer.myNick;
			playerRows[0].color = THEME;
			if (lastPlayerCount > 0)
			{
				playerRows[1].text = '玩家  ' + Multiplayer.oppNick;
				playerRows[1].color = 0xFFFFA0A0;
			}
			else
			{
				playerRows[1].text = '等待玩家加入...';
				playerRows[1].color = TEXT_GRAY;
			}
		}
		else
		{
			playerListTitle.text = '玩家 (2/2)';
			playerRows[0].text = '★ 房主  ' + Multiplayer.oppNick;
			playerRows[0].color = THEME;
			playerRows[1].text = '玩家  ' + Multiplayer.myNick;
			playerRows[1].color = 0xFFFFA0A0;
		}

		// 房间信息
		if (Multiplayer.isHost)
			roomInfoText.text = 'IP: ' + Multiplayer.localIP + ':' + Multiplayer.port
				+ '\n房间码: ' + Multiplayer.roomCode + '\n模式: 1v1 局域网对战';
		else
			roomInfoText.text = '房主: ' + Multiplayer.oppNick
				+ '\n房间码: ' + Multiplayer.roomCode + '\n模式: 1v1 局域网对战';

		// 选曲区
		refreshSongList();
	}

	function refreshSongList():Void
	{
		if (songs.length == 0)
		{
			for (r in songRows) r.visible = false;
			songHeader.text = '';
			songFooter.text = '没有可用歌曲';
			return;
		}

		var song:String = songs[songCur];
		var modDir:String = songFolders.exists(song) ? songFolders.get(song) : '';
		var diffName:String = (selectedDiff >= 0 && selectedDiff < Difficulty.list.length) ? Difficulty.getString(selectedDiff) : Difficulty.getDefault();
		songHeader.text = '曲目: ' + song + '　难度: ' + diffName + (modDir != '' ? '　来源: ' + modDir : '');
		songHeader.color = FlxColor.WHITE;

		var start:Int = Math.floor(songCur / 7) * 7;
		if (songCur < start) start = songCur;
		if (songCur >= start + 7) start = songCur - 6;
		for (i in 0...songRows.length)
		{
			var idx:Int = start + i;
			if (idx < songs.length)
			{
				songRows[i].visible = true;
				songRows[i].text = (idx == songCur ? '▶ ' : '　 ') + songs[idx];
				songRows[i].color = (idx == songCur ? FlxColor.WHITE : TEXT_GRAY);
			}
			else
				songRows[i].visible = false;
		}

		if (Multiplayer.isHost)
		{
			songFooter.text = '点「发送选曲」进入角色选择';
			hostSendLabel.text = '发送选曲';
		}
		else
			songFooter.text = receivedSong != '' ? '房主选曲：' + receivedSong + ' [' + receivedDiff + ']' : '等待房主选曲...';
	}

	// ==================== 鼠标操作 ====================

	function updateMouse(mx:Float, my:Float):Void
	{
		// 通用按钮（连接/难度/滚动/发送开始）
		for (b in mouseBtns)
		{
			if (!b.label.visible) continue;
			var hov:Bool = inRect(mx, my, b.x, b.y, b.w, b.h);
			b.label.color = hov ? FlxColor.WHITE : b.base;
			if (hov && FlxG.mouse.justPressed)
				b.cb();
		}

		// home 三行菜单（hover 高亮 + 点击确认）
		if (page == 'home' && !joinMode)
		{
			for (i in 0...homeTexts.length)
			{
				var hov:Bool = inRect(mx, my, 340, 200 + i * 72, 420, 62);
				if (hov)
					homeTexts[i].color = THEME;
				else
					homeTexts[i].color = (i == homeSelected) ? FlxColor.WHITE : TEXT_GRAY;
				if (hov && FlxG.mouse.justPressed)
				{
					if (i == 0) doCreateRoom();
					else if (i == 1) enterJoinMode();
					else enterDiscover();
				}
			}
		}

		// discover 页：点击房间行直接加入（已满置灰不可点）
		if (page == 'discover')
		{
			var rooms:Array<DiscoveredRoom> = Multiplayer.getDiscoveredRooms();
			for (i in 0...discoverRows.length)
			{
				if (i >= rooms.length) continue;
				var hov:Bool = inRect(mx, my, 290, 196 + i * 50, 700, 44);
				if (hov && !rooms[i].full)
					discoverRows[i].color = THEME;
				else
					discoverRows[i].color = rooms[i].full ? TEXT_GRAY : FlxColor.WHITE;
				if (hov && FlxG.mouse.justPressed)
				{
					if (rooms[i].full)
						statusText.text = '房间已满：' + rooms[i].hostNick + '（' + rooms[i].roomCode + '）';
					else
						joinDiscoveredRoom(rooms[i]);
				}
			}
		}

		// lobby 选曲行点击（选中）
		if (page == 'lobby' && songs.length > 0)
		{
			var start:Int = Math.floor(songCur / 7) * 7;
			if (songCur < start) start = songCur;
			if (songCur >= start + 7) start = songCur - 6;
			for (i in 0...songRows.length)
			{
				if (!songRows[i].visible) continue;
				var hov:Bool = inRect(mx, my, 490, 200 + i * 36, 640, 34);
				if (hov)
					songRows[i].color = (start + i == songCur) ? FlxColor.WHITE : 0xFFB0E0FF;
				else
					songRows[i].color = (start + i == songCur) ? FlxColor.WHITE : TEXT_GRAY;
				if (hov && FlxG.mouse.justPressed && start + i < songs.length)
				{
					songCur = start + i;
					hostSelected = false;
					refreshSongList();
				}
			}
		}
	}

	// ==================== 动作 ====================

	function doCreateRoom():Void
	{
		Multiplayer.myNick = (nickInput.text != null && nickInput.text.trim().length > 0) ? nickInput.text.trim() : '玩家';
		var err = Multiplayer.startHost();
		if (err == 'OK')
		{
			hostSelected = false;
			lastPlayerCount = 0;
			page = 'lobby';
			statusText.text = '房间已创建，等待玩家加入...';
			applyPage();
		}
		else
			statusText.text = '创建失败：' + err;
	}

	function enterJoinMode():Void
	{
		joinMode = true;
		nickInput.visible = false;
		nickLabel.visible = false;
		ipLabel.visible = true;
		ipInput.visible = true;
		connectBtnLabel.visible = true;
		statusText.text = '点击输入框输入房主 IP（可带 :端口），然后点「连接」';
	}

	function enterDiscover():Void
	{
		page = 'discover';
		applyPage();
	}

	function exitJoinMode():Void
	{
		joinMode = false;
		ipLabel.visible = false;
		ipInput.visible = false;
		connectBtnLabel.visible = false;
		nickLabel.visible = true;
		nickInput.visible = true;
		statusText.text = '';
	}

	function doConnect():Void
	{
		Multiplayer.myNick = (nickInput.text != null && nickInput.text.trim().length > 0) ? nickInput.text.trim() : '玩家';
		joinByIP(ipInput.text);
	}

	/** 发现页：点房间行直接加入（beacon 已带房主 IP，无需手输） */
	function joinDiscoveredRoom(r:DiscoveredRoom):Void
	{
		Multiplayer.myNick = (nickInput.text != null && nickInput.text.trim().length > 0) ? nickInput.text.trim() : '玩家';
		joinByIP(r.hostIP);
	}

	function joinByIP(ipText:String):Void
	{
		var err = Multiplayer.connect(ipText);
		if (err == 'OK')
		{
			Multiplayer.send('HI|' + Multiplayer.myNick);
			joinMode = false;
			page = 'lobby';
			statusText.text = '已连接到 ' + ipText + ':' + Multiplayer.port;
			applyPage();
		}
		else
			statusText.text = '连接失败：' + err;
	}

	function changeDiffLeft():Void
	{
		var diffCount:Int = Difficulty.list.length;
		if (diffCount > 0)
		{
			selectedDiff = (selectedDiff - 1 + diffCount) % diffCount;
			hostSelected = false;
			refreshSongList();
		}
	}

	function changeDiffRight():Void
	{
		var diffCount:Int = Difficulty.list.length;
		if (diffCount > 0)
		{
			selectedDiff = (selectedDiff + 1) % diffCount;
			hostSelected = false;
			refreshSongList();
		}
	}

	function scrollSong():Void
	{
		if (songs.length > 0)
		{
			songCur = (songCur - 1 + songs.length) % songs.length;
			hostSelected = false;
			refreshSongList();
		}
	}

	function scrollSongDown():Void
	{
		if (songs.length > 0)
		{
			songCur = (songCur + 1) % songs.length;
			hostSelected = false;
			refreshSongList();
		}
	}

	function hostConfirmAction():Void
	{
		if (!Multiplayer.isHost || songs.length == 0) return;
		var song:String = songs[songCur];
		var modDir:String = songFolders.exists(song) ? songFolders.get(song) : '';
		var diffName:String = (selectedDiff >= 0 && selectedDiff < Difficulty.list.length) ? Difficulty.getString(selectedDiff) : Difficulty.getDefault();
		var mv:String = ClientPrefs.data.marvelousJudgement ? '1' : '0';
		var nj:String = ClientPrefs.data.noteJudgment;
		var ro:String = Std.string(ClientPrefs.data.ratingOffset);
		selectPayload = song + '~' + diffName + '~' + modDir + '~' + mv + '~' + nj + '~' + ro;
		Mods.currentModDirectory = modDir;
		Multiplayer.send('SELECT|' + selectPayload);
		statusText.text = '进入角色选择...';
		MusicBeatState.switchState(new CharacterSelectState(selectPayload));
	}

	// ==================== 更新 ====================

	override function update(elapsed:Float)
	{
		Multiplayer.update();
		processMessages();
		// 先 let 输入框处理本帧点击（hasFocus 切换），再判断 typing，避免「点按钮当帧失效」
		super.update(elapsed);

		// 输入框聚焦（打字）期间：屏蔽一切游戏键位与鼠标命中，避免 WASD/确认/返回冲突
		var typing:Bool = (nickInput != null && nickInput.hasFocus) || (ipInput != null && ipInput.hasFocus);
		if (typing) return;

		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;

		if (page == 'home')
			updateHome();
		else if (page == 'discover')
			updateDiscover();
		else
			updateLobby();

		updateMouse(mx, my);

		// 返回按钮（键盘 Esc 走 updateHome/updateDiscover/updateLobby；鼠标点击在这里）
		backBtn.setHovered(mx, my);
		if (FlxG.mouse.justPressed && backBtn.over(mx, my))
		{
			if (page == 'discover')
			{
				page = 'home';
				applyPage();
			}
			else if (page == 'lobby')
				leaveToHomePage('已退出房间');
			else if (joinMode)
				exitJoinMode();
			else
				leaveToGameMenu();
		}
	}

	function updateHome():Void
	{
		// 键盘仅作辅助（输入框未聚焦时才可达）
		if (joinMode)
		{
			if (controls.ACCEPT) doConnect();
			if (controls.BACK) exitJoinMode();
			return;
		}

		if (controls.UI_UP_P) changeHomeSelection(-1);
		if (controls.UI_DOWN_P) changeHomeSelection(1);
		if (controls.ACCEPT)
		{
			if (homeSelected == 0) doCreateRoom();
			else if (homeSelected == 1) enterJoinMode();
			else enterDiscover();
		}
		if (controls.BACK)
			leaveToGameMenu();
	}

	function updateDiscover():Void
	{
		refreshDiscover();
		if (controls.BACK)
		{
			page = 'home';
			applyPage();
		}
	}

	function updateLobby():Void
	{
		refreshLobby();

		if (songs.length > 0)
		{
			if (controls.UI_UP_P) scrollSong();
			if (controls.UI_DOWN_P) scrollSongDown();
			if (controls.UI_LEFT_P) changeDiffLeft();
			if (controls.UI_RIGHT_P) changeDiffRight();
			if (Multiplayer.isHost && controls.ACCEPT)
				hostConfirmAction();
		}

		if (controls.BACK)
			leaveToHomePage('已退出房间');
	}

	// ==================== 网络消息 ====================

	function processMessages():Void
	{
		fatalHandled = false;
		var msgs = Multiplayer.pollMessages();
		for (m in msgs)
		{
			// 角色资源同步消息：正常只在选角页消费，这里兜底吞掉避免刷状态栏
			if (Multiplayer.handleSyncMessage(m)) continue;

			if (m == 'PLAYER_JOINED')
			{
				lastPlayerCount++;
				if (page == 'lobby')
				{
					statusText.text = Multiplayer.oppNick + ' 已加入房间';
					refreshLobby();
				}
			}
			else if (m == 'PLAYER_LEFT')
			{
				lastPlayerCount--;
				if (lastPlayerCount < 0) lastPlayerCount = 0;
				if (page == 'lobby')
				{
					statusText.text = '玩家已离开房间';
					refreshLobby();
				}
			}
			else if (m.indexOf('HI|') == 0)
			{
				var nick:String = m.substring(3);
				if (nick.trim().length > 0) Multiplayer.oppNick = nick.trim();
				Multiplayer.send('WELCOME|' + Multiplayer.myNick + '|' + Multiplayer.roomCode);
				statusText.text = nick.trim() + ' 已连接';
				refreshLobby();
			}
			else if (m.indexOf('WELCOME|') == 0)
			{
				var parts = m.split('|');
				if (parts.length >= 3)
				{
					Multiplayer.oppNick = parts[1];
					Multiplayer.roomCode = parts[2];
					statusText.text = '已连接到 房主(' + parts[1] + ')  房间码: ' + parts[2];
					refreshLobby();
				}
			}
			else if (m.indexOf('SELECT|') == 0)
			{
				// 客户端收到选曲：进入角色选择页（连接保持）
				MusicBeatState.switchState(new CharacterSelectState(m.substring(7)));
			}
			else if (m.indexOf('START|') == 0)
			{
				var f = m.substring(6).split('~');
				if (f.length >= 6)
				{
					// 客户端强制跟随房主的谱面与判定规则
					Mods.currentModDirectory = f[2];
					Multiplayer.applyJudgementOverrides(f[3] == '1', f[4], Std.parseInt(f[5]));
					// 兼容新协议：START 携带双端角色（hostChar/clientChar）
					PlayState.onlineHostChar = (f.length >= 8) ? f[6] : 'bf';
					PlayState.onlineClientChar = (f.length >= 8) ? f[7] : 'dad';
					statusText.text = '对局开始！';
					startMultiplayerGame(f[0], f[1]);
				}
			}
			else if (m.indexOf('FULL|') == 0)
			{
				fatalHandled = true;
				leaveToHomePage(m.substring(5));
			}
			else if (m.indexOf('QUIT|') == 0)
			{
				fatalHandled = true;
				leaveToHomePage(m.substring(5));
			}
			else if (m.indexOf('FINISH|') == 0)
			{
				// 对局结束消息：结算界面才消费；已回房时忽略，避免状态栏被刷屏
			}
			else if (m.indexOf('DISCONNECTED|') == 0)
			{
				if (fatalHandled) continue;
				leaveToHomePage(m.substring(13));
			}
			else
			{
				statusText.text = '收到消息：' + m;
			}
		}
	}

	// ==================== 音数据与进出 ====================

	function loadSongs():Void
	{
		// 难度列表默认是空数组（FreeplayState 进入时才会 loadFromWeek）——
		// 联机大厅必须自行初始化，否则难度切换 % list.length 直接 Mod by 0
		Difficulty.resetList();

		WeekData.reloadWeekFiles(false);
		for (i in 0...WeekData.weeksList.length)
		{
			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			if (leWeek == null) continue;
			WeekData.setDirectoryFromWeek(leWeek);
			var leFolder:String = Mods.currentModDirectory;
			for (song in leWeek.songs)
			{
				if (songs.indexOf(song[0]) < 0)
				{
					songs.push(song[0]);
					songFolders.set(song[0], leFolder);
				}
			}
		}
		Mods.loadTopMod();
		if (songs.length > 0) songCur = 0;
	}

	function startMultiplayerGame(songName:String, diffName:String):Void
	{
		var diffInt:Int = Difficulty.list.indexOf(diffName);
		if (diffInt < 0) diffInt = 0;
		var songLowercase:String = Paths.formatToSongPath(songName);
		var poop:String = Highscore.formatSong(songLowercase, diffInt);

		// 房主：确保以所选曲目的 mod 目录解析谱面
		if (Multiplayer.isHost)
		{
			var modDir:String = songFolders.exists(songName) ? songFolders.get(songName) : '';
			if (modDir.length > 0) Mods.currentModDirectory = modDir;
		}

		// 标记本局为联机模式：PlayState 会等待 ACK/GO 握手后再开始倒计时
		PlayState.isOnlineMode = true;
		PlayState.onlineIsHost = Multiplayer.isHost;
		PlayState.onlineMyNick = Multiplayer.myNick;
		PlayState.onlineOppNick = Multiplayer.oppNick;
		PlayState.onlineHoldCountdown = true;

		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = diffInt;
		if (!LoadingState.loadSongAndSwitchState(new PlayState(), songLowercase, poop, songLowercase, true, new OnlineMenuState()))
		{
			statusText.text = '加载失败：' + songLowercase;
			PlayState.isOnlineMode = false;
			hostSelected = false;
			refreshSongList();
		}
	}

	function leaveToHomePage(reason:String):Void
	{
		Multiplayer.send('QUIT|' + Multiplayer.myNick + ' 离开了房间');
		Multiplayer.stop();
		page = 'home';
		joinMode = false;
		hostSelected = false;
		lastPlayerCount = 0;
		receivedSong = '';
		receivedDiff = '';
		statusText.text = reason;
		applyPage();
	}

	function leaveToGameMenu():Void
	{
		Multiplayer.send('QUIT|' + Multiplayer.myNick + ' 离开了房间');
		Multiplayer.stop();
		MusicBeatState.switchState(new MainMenuState());
	}

	override function destroy()
	{
		// 注意：不能在这里 stop()——房主/客户端进入对局时本 State 会被销毁，
		// 但网络连接必须保持到对局结束（在线程 goBackToLobby / 结算关闭时统一 stop）。
		super.destroy();
	}
}
