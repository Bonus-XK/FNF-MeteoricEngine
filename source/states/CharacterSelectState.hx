package states;

import backend.Multiplayer;
import backend.Mods;
import backend.Difficulty;
import backend.Highscore;
import objects.BackButton;
import objects.Character;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
#if sys
import sys.FileSystem;
#end

/**
 * 联机角色选择页（选曲后进入）：
 *  - 左侧：全部角色列表（assets/characters + mods/characters，鼠标/键盘）
 *  - 中间：实时预览（Character 实例渲染）+ 当前角色名
 *  - 右侧：双槽 —— 我的角色（BF，可操作）/ 对手角色（Dad，只读，显示对方确认）
 *  - 底部：状态栏；双方确认后房主出现「开始对局」
 * 协议：CHARPICK / CHARPICKOK / CHARPICKREJECT / CHARCANCEL / START（含双方角色）
 */
typedef CSMouseBtn = {
	label:FlxText,
	x:Float,
	y:Float,
	w:Float,
	h:Float,
	base:FlxColor,
	cb:Void->Void
}

class CharacterSelectState extends MusicBeatState
{
	// 主题色不再用静态常量（static final 会在类初始化时冻结取值）；统一在 create() 内读 DesignTokens.primary
	static final TEXT_GRAY:FlxColor = 0xFFA9A9B8;
	static final TEXT_LIGHT:FlxColor = 0xFFD7D7E0;
		static final ROWS_VISIBLE:Int = 12;

	// 选曲 payload：song~diff~modDir~mv~nj~ro
	var payload:String = '';
	var songName:String = '';
	var diffName:String = '';
	var modDir:String = '';

	// 角色列表
	var charList:Array<String> = [];
	var charCur:Int = 0;
	var listRows:Array<FlxText> = [];
	var listScroll:Int = 0;

	// 预览
	var previewChar:Character = null;
	var previewName:FlxText;

	// 双槽
	var mySlotText:FlxText;
	var oppSlotText:FlxText;

	// 按钮 / 状态
	var confirmBtn:FlxText;
	var startBtn:FlxText;
	var mouseBtns:Array<CSMouseBtn> = [];
	var statusText:FlxText;
	var backBtn:BackButton;

	// 选角状态
	var myChar:String = '';
	var oppChar:String = '';
	var myConfirmed:Bool = false;
	var oppConfirmed:Bool = false;
	/** 对方模组角色资源是否已同步完成（内置角色无 CHARSYNC，保持 true） */
	var oppSyncDone:Bool = true;

	public function new(selPayload:String)
	{
		super();
		payload = selPayload;
	}

	override function create()
	{
		super.create();

		var parts:Array<String> = payload.split('~');
		if (parts.length >= 2)
		{
			songName = parts[0];
			diffName = parts[1];
		}
		if (parts.length >= 3) modDir = parts[2];

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		add(bg);

		var title:FlxText = new FlxText(0, 34, FlxG.width, '选择角色', 44);
		title.setFormat(Paths.font('future.ttf'), 44, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(title);
		var sub:FlxText = new FlxText(0, 88, FlxG.width, '曲目: ' + songName + '　难度: ' + diffName
			+ '　我的角色 = BF　对手角色 = Dad', 18);
		sub.setFormat(Paths.font('future.ttf'), 18, TEXT_LIGHT, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(sub);

		// 左：角色列表
		makePanel(60, 120, 520, 440);
		var listTitle:FlxText = new FlxText(80, 136, 480, '角色列表（↑↓ 选择 · 点击确认）', 20);
		listTitle.setFormat(Paths.font('future.ttf'), 20, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(listTitle);
		listRows = [];
		for (i in 0...ROWS_VISIBLE)
		{
			var t:FlxText = new FlxText(80, 176 + i * 30, 480, '', 20);
			t.setFormat(Paths.font('future.ttf'), 20, TEXT_GRAY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			add(t);
			listRows.push(t);
		}
		addMouseBtn('▲', 540, 170, 30, 26, 16, scrollList, TEXT_GRAY);
		addMouseBtn('▼', 540, 200, 30, 26, 16, scrollListDown, TEXT_GRAY);

		// 中：预览
		makePanel(600, 120, 320, 440);
		var prevTitle:FlxText = new FlxText(620, 136, 280, '预览', 20);
		prevTitle.setFormat(Paths.font('future.ttf'), 20, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(prevTitle);
		previewName = new FlxText(620, 500, 280, '', 22);
		previewName.setFormat(Paths.font('future.ttf'), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(previewName);

		// 右：双槽
		makePanel(940, 120, 280, 440);
		var slotsTitle:FlxText = new FlxText(960, 136, 240, '对局角色', 20);
		slotsTitle.setFormat(Paths.font('future.ttf'), 20, DesignTokens.primary, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(slotsTitle);
		mySlotText = new FlxText(960, 180, 240, '', 20);
		mySlotText.setFormat(Paths.font('future.ttf'), 20, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(mySlotText);
		oppSlotText = new FlxText(960, 240, 240, '', 20);
		oppSlotText.setFormat(Paths.font('future.ttf'), 20, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(oppSlotText);
		confirmBtn = addMouseBtn('确认选择', 960, 300, 240, 42, 22, tryConfirm, DesignTokens.primary);
		confirmBtn.visible = true;
		startBtn = addMouseBtn('开始对局', 960, 380, 240, 42, 22, hostStart, DesignTokens.primary);
		startBtn.visible = false;

		statusText = new FlxText(60, 585, 1160, '', 18);
		statusText.setFormat(Paths.font('future.ttf'), 18, TEXT_LIGHT, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(statusText);

		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		FlxG.mouse.visible = true;

		loadCharacters();
		updateSlots();
		refreshList();
	}

	// ==================== 角色列表与预览 ====================

	function loadCharacters():Void
	{
		charList = [];
		#if sys
		var dirs:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'characters/');
		for (d in dirs)
		{
			if (!FileSystem.exists(d)) continue;
			for (f in FileSystem.readDirectory(d))
			{
				if (f.toLowerCase().endsWith('.json'))
				{
					var name:String = f.substring(0, f.length - 5);
					if (charList.indexOf(name) < 0) charList.push(name);
				}
			}
		}
		#end
		charList.sort(Reflect.compare);
		// 过滤“资源不全”的角色（例如之前测试残留的半同步 JSON 在、图集 PNG 缺失）：
		// 本地没完整资源的角色不该出现在列表里——选了也加载/同步不出来。
		charList = charList.filter(function(name:String) return Multiplayer.charAssetsComplete(name));
		if (charList.indexOf('bf') < 0) charList.insert(0, 'bf');
		if (charList.indexOf('dad') < 0) charList.insert(1, 'dad');

		charCur = charList.indexOf('bf');
		if (charCur < 0) charCur = 0;
		updatePreview();
	}

	function refreshList():Void
	{
		if (listScroll > charList.length - ROWS_VISIBLE) listScroll = Std.int(Math.max(0, charList.length - ROWS_VISIBLE));
		if (listScroll < 0) listScroll = 0;
		for (i in 0...ROWS_VISIBLE)
		{
			var idx:Int = listScroll + i;
			if (idx < charList.length)
			{
				listRows[i].visible = true;
				listRows[i].text = (idx == charCur ? '▶ ' : '　 ') + charList[idx];
				listRows[i].color = (idx == charCur ? FlxColor.WHITE : TEXT_GRAY);
			}
			else
				listRows[i].visible = false;
		}
	}

	function updatePreview():Void
	{
		var name:String = charList[charCur];
		previewName.text = name;

		if (previewChar != null)
		{
			remove(previewChar, true);
			previewChar = null;
		}
		try
		{
			previewChar = new Character(760, 330, name, true);
			var s:Float = 0.7;
			if (previewChar.width > 420) s = 0.5;
			if (previewChar.width > 700) s = 0.35;
			previewChar.scale.set(s, s);
			previewChar.updateHitbox();
			add(previewChar);
		}
		catch (e:Dynamic)
		{
			previewName.text = name + '（加载失败，回退 bf）';
			try
			{
				previewChar = new Character(760, 330, 'bf', true);
				add(previewChar);
			}
			catch (e2:Dynamic) {}
		}
	}

	function changeChar(change:Int):Void
	{
		if (charList.length == 0) return;
		charCur = (charCur + change + charList.length) % charList.length;
		if (charCur < listScroll) listScroll = charCur;
		else if (charCur >= listScroll + ROWS_VISIBLE) listScroll = charCur - ROWS_VISIBLE + 1;
		refreshList();
		updatePreview();
	}

	function scrollList():Void
	{
		if (listScroll > 0) { listScroll--; refreshList(); }
	}

	function scrollListDown():Void
	{
		if (listScroll + ROWS_VISIBLE < charList.length) { listScroll++; refreshList(); }
	}

	// ==================== 选角与协议 ====================

	function tryConfirm():Void
	{
		if (myConfirmed) { statusText.text = '已确认角色：' + myChar; return; }
		var cur:String = charList[charCur];
		// 重复校验：后确认者重选
		if (oppConfirmed && oppChar == cur)
		{
			statusText.text = '「' + cur + '」已被对方选择，请重选';
			return;
		}
		myChar = cur;
		myConfirmed = true;
		statusText.text = '已确认角色：' + myChar;
		if (Multiplayer.isHost)
			Multiplayer.send('CHARPICKOK|' + myChar); // 房主选角广播
		else
			Multiplayer.send('CHARPICK|' + myChar);   // 客户端请求，房主仲裁
		// 模组角色：把皮肤资源（json+图集+图标）推给对端，对方没装模组也能看到这个皮肤
		Multiplayer.beginSendCharSync(myChar);
		updateSlots();
	}

	function hostStart():Void
	{
		if (!Multiplayer.isHost) return;
		if (!myConfirmed || !oppConfirmed)
		{
			statusText.text = '双方都确认角色后才能开始';
			return;
		}
		if (!oppSyncDone)
		{
			statusText.text = '对方角色资源同步中，请稍候...';
			return;
		}
		PlayState.onlineHostChar = myChar;
		PlayState.onlineClientChar = oppChar;
		Multiplayer.send('START|' + payload + '~' + myChar + '~' + oppChar);
		statusText.text = '开始对局...';
		startGame(songName, diffName, myChar, oppChar);
	}

	function processMessages():Void
	{
		for (m in Multiplayer.pollMessages())
		{
			// 对方模组角色资源同步（分块写入 mods/）；同步完成后才允许房主开始
			if (m.indexOf('CHARSYNC|') == 0) oppSyncDone = false;
			else if (m.indexOf('CHARSYNC_END|') == 0) oppSyncDone = true;
			if (Multiplayer.handleSyncMessage(m)) continue;

			var parts:Array<String> = m.split('|');
			var cmd:String = parts[0];
			switch (cmd)
			{
				case 'CHARPICK':
					// 房主仲裁客户端选角（重复则由房主拒绝）
					if (Multiplayer.isHost && parts.length >= 2)
					{
						var c:String = parts[1];
						if (myConfirmed && myChar == c)
						{
							Multiplayer.send('CHARPICKREJECT|' + c);
							statusText.text = '对方选择了重复角色，已要求重选';
						}
						else
						{
							oppChar = c;
							oppConfirmed = true;
							// 不要再回发 CHARPICKOK：旧实现把客户端自己的选角原样回显，
							// 客户端会把它误写进「对手角色」槽（自己的选角覆盖房主的显示）。
							// CHARPICKOK 现在仅表示「房主自己的选角」，客户端本地已确认自己的选择。
							statusText.text = '对方已选角色：' + c;
							updateSlots();
						}
					}
				case 'CHARPICKOK':
					if (parts.length >= 2)
					{
						oppChar = parts[1];
						oppConfirmed = true;
						statusText.text = '对方已选角色：' + oppChar;
						updateSlots();
					}
				case 'CHARPICKREJECT':
					myConfirmed = false;
					myChar = '';
					statusText.text = '该角色已被对方选择，请重选';
					updateSlots();
				case 'CHARCANCEL':
					backToLobby('对方取消了选角，已回到房间大厅');
				case 'START':
					if (parts.length >= 2)
					{
						var f:Array<String> = parts[1].split('~');
						if (f.length >= 8)
						{
							Mods.currentModDirectory = f[2];
							Multiplayer.applyJudgementOverrides(f[3] == '1', f[4], Std.parseInt(f[5]));
							PlayState.onlineHostChar = f[6];
							PlayState.onlineClientChar = f[7];
							statusText.text = '对局开始！';
							startGame(f[0], f[1], f[6], f[7]);
						}
					}
				case 'DISCONNECTED':
					backToLobby(parts.length > 1 ? parts[1] : '连接已断开');
				case 'QUIT':
					backToLobby(parts.length > 1 ? parts[1] : '对方已离开');
				default:
			}
		}
	}

	function updateSlots():Void
	{
		// 联机双端均为标准单机布局：我=右侧 BF 位、对手=左侧 Dad 位（各唱自己选的半边）
		mySlotText.text = '我的角色（BF）:\n' + (myConfirmed ? '▶ ' + myChar : '未选择');
		mySlotText.color = myConfirmed ? FlxColor.WHITE : TEXT_LIGHT;
		oppSlotText.text = '对手角色（Dad）:\n' + (oppConfirmed ? '▶ ' + oppChar : '等待对方选择...');
		oppSlotText.color = oppConfirmed ? 0xFFB0E0FF : TEXT_LIGHT;
		confirmBtn.text = myConfirmed ? '已确认' : '确认选择';
		startBtn.visible = Multiplayer.isHost && myConfirmed && oppConfirmed;
		if (Multiplayer.isHost)
			statusText.text = myConfirmed ? (oppConfirmed ? '双方已确认，点「开始对局」' : '已确认角色：' + myChar + '，等待对方...') : statusText.text;
		else
			statusText.text = myConfirmed ? '已确认角色：' + myChar + (oppConfirmed ? '，等待房主开始...' : '，等待对方...') : statusText.text;
	}

	// ==================== 输入 ====================

	override function update(elapsed:Float)
	{
		Multiplayer.update();
		processMessages();
		super.update(elapsed);

		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;

		// 鼠标按钮
		for (b in mouseBtns)
		{
			if (!b.label.visible) continue;
			var hov:Bool = mx >= b.x && mx <= b.x + b.w && my >= b.y && my <= b.y + b.h;
			b.label.color = hov ? FlxColor.WHITE : b.base;
			if (hov && FlxG.mouse.justPressed) b.cb();
		}

		// 列表行点击
		for (i in 0...ROWS_VISIBLE)
		{
			if (!listRows[i].visible) continue;
			var idx:Int = listScroll + i;
			var hov:Bool = mx >= 80 && mx <= 520 && my >= 176 + i * 30 && my <= 176 + i * 30 + 28;
			if (hov)
				listRows[i].color = 0xFFB0E0FF;
			else
				listRows[i].color = (idx == charCur ? FlxColor.WHITE : TEXT_GRAY);
			if (hov && FlxG.mouse.justPressed && idx < charList.length)
			{
				charCur = idx;
				refreshList();
				updatePreview();
			}
		}

		// 键盘辅助
		if (controls.UI_UP_P) changeChar(-1);
		if (controls.UI_DOWN_P) changeChar(1);
		if (controls.ACCEPT) tryConfirm();

		// 返回
		backBtn.setHovered(mx, my);
		if (FlxG.mouse.justPressed && backBtn.over(mx, my))
			cancelToLobby();
		if (controls.BACK)
			cancelToLobby();
	}

	// ==================== 进出 ====================

	function cancelToLobby():Void
	{
		Multiplayer.send('CHARCANCEL|' + Multiplayer.myNick + ' 取消了选角');
		backToLobby('已取消选角，回到房间大厅');
	}

	function backToLobby(reason:String):Void
	{
		OnlineMenuState.notifyReason = reason;
		MusicBeatState.switchState(new OnlineMenuState());
	}

	function startGame(song:String, diff:String, hostChar:String, clientChar:String):Void
	{
		var diffInt:Int = Difficulty.list.indexOf(diff);
		if (diffInt < 0) diffInt = 0;
		var songLowercase:String = Paths.formatToSongPath(song);
		var poop:String = Highscore.formatSong(songLowercase, diffInt);

		if (Multiplayer.isHost && modDir.length > 0) Mods.currentModDirectory = modDir;
		PlayState.onlineHostChar = hostChar;
		PlayState.onlineClientChar = clientChar;

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
		}
	}

	// ==================== UI 工具 ====================

	function makePanel(x:Float, y:Float, w:Float, h:Float):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, 20, 20, DesignTokens.panelFill);
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

	override function destroy()
	{
		// 连接保持：回大厅/进对局时由目标状态管理（OnlineMenuState.destroy 同样不 stop）
		if (previewChar != null)
		{
			remove(previewChar, true);
			previewChar = null;
		}
		super.destroy();
	}
}
