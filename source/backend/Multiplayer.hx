package backend;

#if (sys && !html5)
import sys.net.Socket;
import sys.net.Host;
import sys.net.UdpSocket;
import sys.net.Address;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Path;
import haxe.crypto.Base64;
import sys.io.File;
import sys.FileSystem;
import tjson.TJSON as Json;
#end

/**
 * Meteoric 联机核心：房主即服务器（TCP），无中心服务器，局域网直连。
 * 协议为「行分隔消息」，消息内字段用 `~` 分隔（避免与消息级 `|` 冲突）：
 *
 * 大厅：
 *   HI|<nick>                       客户端→房主：连接后上报昵称
 *   WELCOME|<hostNick>|<roomCode>   房主→客户端：欢迎（含房主昵称/房间码）
 *   PLAYER_JOINED / PLAYER_LEFT     房主→客户端：玩家进出（客户端为全局计数提醒）
 *   SELECT|song~diff~modDir~mv~nj~ro   房主→客户端：选曲预览（同步 mod 与判定规则）
 *   START|song~diff~modDir~mv~nj~ro   房主→客户端：开始
 *
 * 发现（UDP 广播，固定端口 27751）：
 *   METEORIC_ROOM|roomCode|hostNick|playerCount|full
 *                 房主建房后每 1s 广播 + 本机回环单播；客户端监听 27751，
 *                 4s 未收到该房间心跳自动移除（详见 startBeacon/discoveryStart）。
 *
 * 对局：
 *   ACK        客户端→房主：PlayState 已就绪（等待 GO）
 *   GO         房主→客户端：双端同时开始倒计时
 *   TIME|<pos> 房主→客户端：周期时间同步（漂移 >45ms 时客户端校正）
 *   HIT|data~rating~scoreDelta~healthDelta~mult~chartSeq   双向：主音符命中（chartSeq 供接收端精确消费对侧谱面音符）
 *   MISS|data~scoreDelta~healthDelta~mult~chartSeq         双向：漏键/空按（无对应音符时 chartSeq=-1）
 *   PRESS|data / RELEASE|data                          双向：对方按键条
 *   PAUSE / RESUME                                     双向：暂停同步
 *   QUIT|<reason>                                      双向：主动退出（回大厅）
 *   DISCONNECTED|<reason>                              双向：网络断开检测
 *   FINISH|score~hits~misses~totalNotesHit~totalPlayed~maxCombo~acc~countsCsv   双向：结算
 */
class Multiplayer
{
	public static var isHost:Bool = false;
	public static var isConnected:Bool = false;
	public static var localIP:String = '0.0.0.0';
	public static var port:Int = 27750;
	public static var roomCode:String = '';
	public static var lastError:String = '';

	// 玩家昵称（大厅输入框写入）
	public static var myNick:String = '玩家';
	public static var oppNick:String = '对手';

	// ==================== 局域网房间自动发现（UDP 广播） ====================
	public static var DISCOVERY_PORT:Int = 27751;       // UDP 发现端口（固定；与 TCP 对局 27750 分离）
	public static var DISCOVERY_MAGIC:String = 'METEORIC_ROOM';
	public static var DISCOVERY_INTERVAL:Float = 1.0;   // 房主广播间隔（秒）
	public static var DISCOVERY_TIMEOUT:Float = 4.0;    // 客户端心跳超时（秒）：超时自动移除房间

	// 客户端被房主强制同步的判定设置（对局结束/离开时恢复）
	static var savedMarvelous:Null<Bool> = null;
	static var savedNoteJudgment:String = '';
	static var savedRatingOffset:Int = 0;

	#if (sys && !html5)
	static var serverSocket:Socket = null;
	static var clientSockets:Array<Socket> = [];
	static var clientSocket:Socket = null;
	static var clientBuffer:BytesBuffer = new BytesBuffer();
	static var hostBuffers:Map<Socket, BytesBuffer> = [];
	static var msgQueue:Array<String> = [];

	// 出站队列：非阻塞 socket 缓冲满时消息先入队，由 pumpOut 按可写能力逐帧续发。
	// 注意：1v1 房间最多 1 个客户端，host 侧只写 clientSockets[0]，字节偏移全局共享是安全的。
	static var outQueue:Array<String> = [];
	static var outBytes:Bytes = null;
	static var outOffset:Int = 0;

	// ===== 局域网发现（仅 sys 平台）=====
	static var beaconSock:UdpSocket = null;      // 房主广播（只发不绑定，避免同机双开 27751 冲突）
	static var beaconElapsed:Float = 0;          // 距上次广播的累计时间
	static var discoverSock:UdpSocket = null;    // 客户端监听（绑定 0.0.0.0:27751）
	static var discoverElapsed:Float = 0;        // 发现页累计时间（也作 lastSeen 时钟）
	static var discoverRooms:Array<DiscoveredRoom> = [];
	static var lastTick:Float = 0;               // 帧间隔计时（Timer.stamp 秒）
	#end

	/** 应用房主广播的判定规则（仅客户端调用；房主自己的设置即权威） */
	public static function applyJudgementOverrides(marvelous:Bool, noteJudgment:String, ratingOffset:Int):Void
	{
		#if (sys && !html5)
		if (savedMarvelous == null)
		{
			savedMarvelous = ClientPrefs.data.marvelousJudgement;
			savedNoteJudgment = ClientPrefs.data.noteJudgment;
			savedRatingOffset = ClientPrefs.data.ratingOffset;
		}
		#end
		ClientPrefs.data.marvelousJudgement = marvelous;
		ClientPrefs.data.noteJudgment = noteJudgment;
		ClientPrefs.data.ratingOffset = ratingOffset;
	}

	/** 离开联机会话时恢复客户端自己的判定设置 */
	public static function restoreJudgementOverrides():Void
	{
		#if (sys && !html5)
		if (savedMarvelous != null)
		{
			ClientPrefs.data.marvelousJudgement = savedMarvelous;
			ClientPrefs.data.noteJudgment = savedNoteJudgment;
			ClientPrefs.data.ratingOffset = savedRatingOffset;
			savedMarvelous = null;
		}
		#end
	}

	public static function startHost(p:Int = 27750):String
	{
		#if (sys && !html5)
		stop();
		port = p;
		isHost = true;
		try
		{
			serverSocket = new Socket();
			serverSocket.bind(new Host('0.0.0.0'), port);
			serverSocket.listen(8);
			serverSocket.setBlocking(false);
			localIP = getLocalIP();
			roomCode = StringTools.hex(Std.int(Math.random() * 0xFFFFFF), 6).toUpperCase();
			isConnected = true;
			lastError = '';
			oppNick = '对手';
			startBeacon(); // 建房成功即开始局域网自动发现广播
			return 'OK';
		}
		catch (e:Dynamic)
		{
			lastError = Std.string(e);
			stop();
			return lastError;
		}
		#else
		return 'NOT_SUPPORTED';
		#end
	}

	public static function connect(input:String, p:Int = 27750):String
	{
		#if (sys && !html5)
		stop();
		port = p;
		isHost = false;

		// 容错解析：支持 "192.168.1.10"、"192.168.1.10:27750"、
		// "IP: 192.168.1.10"、"IP: 192.168.1.10:27750"（含空格/全角冒号自动清理）
		var hostStr:String = Std.string(input).trim();
		hostStr = hostStr.replace('：', ':');
		if (hostStr.indexOf(' ') >= 0)
			hostStr = hostStr.split(' ').pop().trim();
		if (hostStr.indexOf(':') > 0)
		{
			var idx:Int = hostStr.lastIndexOf(':');
			var hostPart:String = hostStr.substring(0, idx).trim();
			var portPart:String = hostStr.substring(idx + 1).trim();
			var parsedPort:Null<Int> = Std.parseInt(portPart);
			if (hostPart.length > 0 && parsedPort != null)
			{
				hostStr = hostPart;
				port = parsedPort;
			}
		}
		if (hostStr.length == 0)
		{
			lastError = '请输入房主 IP';
			return lastError;
		}

		try
		{
			var s = new Socket();
			s.setTimeout(3);
			s.connect(new Host(hostStr), port);
			s.setBlocking(false);
			clientSocket = s;
			clientBuffer = new BytesBuffer();
			isConnected = true;
			lastError = '';
			oppNick = '对手';
			return 'OK';
		}
		catch (e:Dynamic)
		{
			lastError = Std.string(e);
			stop();
			return lastError;
		}
		#else
		return 'NOT_SUPPORTED';
		#end
	}

	public static function send(msg:String):Bool
	{
		#if (sys && !html5)
		if (!isConnected) return false;
		// 非阻塞 socket：消息先入队，pumpOut 按 socket 可写能力续发。
		// 旧实现直接 writeString 大消息，发送缓冲满时会“部分写入后抛 Blocked”，
		// 被当成断线处理——选角同步一口气发几十个 60KB 分块时连接会全断。
		outQueue.push(msg);
		pumpOut();
		return true;
		#else
		return false;
		#end
	}

	/**
	 * 尽力把积压消息写入 socket：
	 *  - 每次 writeBytes 返回实际写入字节数，部分写入也严格推进偏移（字节流不丢不乱）；
	 *  - Blocked（缓冲满）= 正常背压，留在队列等下一帧续发，绝不视为断线；
	 *  - 真实错误（对方关闭等）才 queueDisconnect + stop。
	 */
	static function pumpOut():Void
	{
		#if (sys && !html5)
		if (!isConnected) return;
		while (outQueue.length > 0)
		{
			if (outBytes == null)
			{
				var msg:String = outQueue.shift();
				outBytes = Bytes.ofString(msg + '\n');
				outOffset = 0;
			}
			if (outOffset >= outBytes.length)
			{
				outBytes = null;
				continue;
			}

			var targets:Array<Socket> = isHost ? clientSockets : (clientSocket != null ? [clientSocket] : []);
			if (targets.length == 0)
			{
				outBytes = null; // 无目标连接：丢弃当前行
				continue;
			}

			var progress:Bool = false;
			for (s in targets)
			{
				try
				{
					var n:Int = s.output.writeBytes(outBytes, outOffset, outBytes.length - outOffset);
					if (n > 0) { outOffset += n; progress = true; }
				}
				catch (e:Dynamic)
				{
					if (Std.string(e).indexOf('Blocked') >= 0) continue; // 背压：稍后重试
					queueDisconnect(isHost ? '对方已断开连接' : '连接已断开');
					stop();
					return;
				}
			}
			if (!progress) return; // 本帧写不进去，保留队列
		}
		outBytes = null;
		#end
	}

	public static function pollMessages():Array<String>
	{
		#if (sys && !html5)
		var out = msgQueue;
		msgQueue = [];
		return out;
		#else
		return [];
		#end
	}

	/** 把已 poll 但暂不处理的消息按原顺序放回队列（暂停期间保活用） */
	public static function reinjectMany(msgs:Array<String>):Void
	{
		#if (sys && !html5)
		if (msgs == null || msgs.length == 0) return;
		msgQueue = msgs.concat(msgQueue);
		#end
	}

	public static function update():Void
	{
		#if (sys && !html5)
		// 发现/广播心跳帧计时（Timer.stamp 秒；页面切走时无 update 调用，重进时按大 dt 立即补发/剔除）
		var now:Float = haxe.Timer.stamp();
		var dt:Float = (lastTick > 0) ? (now - lastTick) : 0;
		lastTick = now;
		beaconTick(dt);
		discoveryTick(dt);

		if (isHost && serverSocket != null)
		{
			var readSocks:Array<Socket> = [serverSocket];
			for (c in clientSockets) readSocks.push(c);
			var sel = Socket.select(readSocks, null, null, 0);
			for (s in sel.read)
			{
				if (s == serverSocket)
				{
					try
					{
						var c = serverSocket.accept();
						c.setBlocking(false);
						// 严格 1v1：已有客户端时拒绝新连接（回执 FULL 后立即关闭）
						if (clientSockets.length >= 1)
						{
							try
							{
								c.output.writeString('FULL|房间已满（1v1 对局仅限 2 人）\n');
								c.output.flush();
							}
							catch (e:Dynamic) {}
							try { c.close(); } catch (e:Dynamic) {}
						}
						else
						{
							clientSockets.push(c);
							hostBuffers.set(c, new BytesBuffer());
							msgQueue.push('PLAYER_JOINED');
						}
					}
					catch (e:Dynamic) {}
				}
				else
				{
					readFromHostClient(s);
				}
			}
		}
		else if (!isHost && clientSocket != null)
		{
			var sel = Socket.select([clientSocket], null, null, 0);
			if (sel.read.length > 0)
			{
				readFromClient();
			}
		}
		pumpOut(); // 每帧续发积压消息（背压时留在队列，不丢不乱）
		#end
	}

	#if (sys && !html5)
	static function queueDisconnect(reason:String):Void
	{
		var key:String = 'DISCONNECTED|' + reason;
		if (msgQueue.indexOf(key) < 0)
			msgQueue.push(key);
	}

	static function readFromHostClient(s:Socket):Void
	{
		var buf:BytesBuffer = hostBuffers.get(s);
		if (buf == null) return;
		try
		{
			while (true)
			{
				var c:Int = s.input.readByte();
				if (c == 10)
				{
					if (buf.length > 0) msgQueue.push(decodeLine(buf));
					buf = new BytesBuffer();
				}
				else
				{
					buf.addByte(c);
				}
			}
		}
		catch (e:Dynamic)
		{
			var isBlocked:Bool = (Std.string(e).indexOf('Blocked') >= 0);
			if (!isBlocked)
			{
				queueDisconnect('对方已断开连接');
				clientSockets.remove(s);
				hostBuffers.remove(s);
				try { s.close(); } catch (e2:Dynamic) {}
				msgQueue.push('PLAYER_LEFT');
			}
		}
		hostBuffers.set(s, buf);
	}

	static function readFromClient():Void
	{
		try
		{
			while (true)
			{
				var c:Int = clientSocket.input.readByte();
				if (c == 10)
				{
					if (clientBuffer.length > 0) msgQueue.push(decodeLine(clientBuffer));
					clientBuffer = new BytesBuffer();
				}
				else
				{
					clientBuffer.addByte(c);
				}
			}
		}
		catch (e:Dynamic)
		{
			if (Std.string(e).indexOf('Blocked') < 0)
			{
				queueDisconnect('连接已断开');
				stop();
			}
		}
	}

	/**
	 * 把按字节积攒的一行解码为字符串。
	 * 发送侧 Socket.output.writeString 按 UTF-8 编码写入；接收侧这里逐字节
	 * addByte 攒原始字节，行收齐后必须用 UTF-8 解码成字符串，否则中文昵称
	 * （多字节 UTF-8）会被按 Latin-1 字符拼出乱码（如「玩家」→「çå®¶」）。
	 */
	static function decodeLine(buf:BytesBuffer):String
	{
		var bytes = buf.getBytes();
		return bytes.getString(0, bytes.length);
	}

	// ==================== 局域网房间自动发现（UDP 广播 27751） ====================

	/** 房主：开始广播房间心跳（建房成功后调用；只发送不绑定端口，支持同机双开） */
	public static function startBeacon():Void
	{
		#if (sys && !html5)
		if (beaconSock != null) return;
		try
		{
			beaconSock = new UdpSocket();
			beaconSock.setBlocking(false);
			beaconSock.setBroadcast(true);
			beaconElapsed = DISCOVERY_INTERVAL; // 立即发第一包
		}
		catch (e:Dynamic) { beaconSock = null; }
		#end
	}

	/** 房主：停止广播（离开房间/断线/退出时由 stop() 调用） */
	public static function stopBeacon():Void
	{
		#if (sys && !html5)
		if (beaconSock != null)
		{
			try { beaconSock.close(); } catch (e:Dynamic) {}
			beaconSock = null;
		}
		#end
	}

	/** 房主心跳：每 DISCOVERY_INTERVAL 秒广播一次（含本机回环 + 本机局域网 IP，双开也能发现） */
	static function beaconTick(dt:Float):Void
	{
		#if (sys && !html5)
		if (beaconSock == null || !isHost || !isConnected) return;
		beaconElapsed += dt > 0 ? dt : 0;
		if (beaconElapsed < DISCOVERY_INTERVAL) return;
		beaconElapsed = 0;
		var count:Int = 1 + (clientSockets != null ? clientSockets.length : 0);
		var payload:String = DISCOVERY_MAGIC + '|' + roomCode + '|' + myNick + '|' + count + '|' + (count >= 2 ? '1' : '0');
		var bytes:Bytes = Bytes.ofString(payload);
		sendBeaconTo('255.255.255.255', bytes);            // 局域网广播
		sendBeaconTo('127.0.0.1', bytes);                  // 本机回环（单机双开测试）
		if (localIP != null && localIP.length > 0 && localIP != '0.0.0.0')
			sendBeaconTo(localIP, bytes);                  // 部分系统广播不回环自身
		#end
	}

	static function sendBeaconTo(ip:String, bytes:Bytes):Void
	{
		#if (sys && !html5)
		try
		{
			var h:Host = new Host(ip);
			var a:Address = new Address();
			a.host = h.ip;
			a.port = DISCOVERY_PORT;
			beaconSock.sendTo(bytes, 0, bytes.length, a);
		}
		catch (e:Dynamic) {}
		#end
	}

	/** 客户端：开始发现（绑定 0.0.0.0:DISCOVERY_PORT 监听；幂等，重复调用不重建） */
	public static function discoveryStart():Void
	{
		#if (sys && !html5)
		if (discoverSock != null) return;
		try
		{
			discoverSock = new UdpSocket();
			discoverSock.setBlocking(false);
			discoverSock.bind(new Host('0.0.0.0'), DISCOVERY_PORT);
			discoverRooms = [];
			discoverElapsed = 0;
			lastTick = 0;
		}
		catch (e:Dynamic) { discoverSock = null; }
		#end
	}

	/** 客户端：停止发现（离开发现页/退出联机界面时调用） */
	public static function discoveryStop():Void
	{
		#if (sys && !html5)
		if (discoverSock != null)
		{
			try { discoverSock.close(); } catch (e:Dynamic) {}
			discoverSock = null;
		}
		#end
	}

	public static function isDiscovering():Bool
	{
		#if (sys && !html5)
		return discoverSock != null;
		#else
		return false;
		#end
	}

	/** 当前发现的房间列表（副本，UI 只读） */
	public static function getDiscoveredRooms():Array<DiscoveredRoom>
	{
		#if (sys && !html5)
		return discoverRooms.copy();
		#else
		return [];
		#end
	}

	/** 客户端心跳处理：排空 UDP 缓冲 + 超时剔除（每帧由 Multiplayer.update 调用） */
	static function discoveryTick(dt:Float):Void
	{
		#if (sys && !html5)
		if (discoverSock == null) return;
		discoverElapsed += dt > 0 ? dt : 0;
		var buf:Bytes = Bytes.alloc(1024);
		var addr:Address = new Address();
		while (true)
		{
			try
			{
				var n:Int = discoverSock.readFrom(buf, 0, buf.length, addr);
				if (n <= 0) break;
				var line:String = buf.getString(0, n);
				if (line.indexOf(DISCOVERY_MAGIC + '|') == 0)
				{
					var parts:Array<String> = line.split('|');
					if (parts.length >= 5)
					{
						var ip:String = addr.getHost().toString();
						updateDiscoveredRoom(parts[1], parts[2], ip, Std.parseInt(parts[3]), parts[4] == '1');
					}
				}
			}
			catch (e:Dynamic) { break; } // Blocked/Eof：无更多数据
		}
		// 心跳超时移除
		var keep:Array<DiscoveredRoom> = [];
		for (r in discoverRooms)
			if (discoverElapsed - r.lastSeen <= DISCOVERY_TIMEOUT) keep.push(r);
		discoverRooms = keep;
		#end
	}

	static function updateDiscoveredRoom(roomCode:String, hostNick:String, hostIP:String, count:Int, full:Bool):Void
	{
		#if (sys && !html5)
		if (count < 1) count = 1;
		for (r in discoverRooms)
		{
			if (r.roomCode == roomCode && r.hostIP == hostIP)
			{
				r.hostNick = hostNick;
				r.playerCount = count;
				r.full = full;
				r.lastSeen = discoverElapsed;
				return;
			}
		}
		discoverRooms.push(new DiscoveredRoom(roomCode, hostNick, hostIP, count, full, discoverElapsed));
		#end
	}

	// ==================== 角色资源同步（双方皮肤跨端可见） ====================

	static var syncRecvChar:String = '';
	static var syncRecvExpected:Int = 0;
	static var syncRecvDone:Int = 0;
	static var syncFileRel:String = '';
	static var syncFileTotal:Int = 0;
	static var syncFileChunks:Int = 0;
	static var syncFileB64Parts:Array<String> = [];

	/**
	 * 发送自己的已选角色资源给对端（仅模组角色：characters/<name>.json + 图集/图标，base64 分块）。
	 * 对端没装该模组也能加载并显示这个皮肤；内置角色（assets/…）对端本就有，跳过。
	 */
	public static function beginSendCharSync(charName:String):Void
	{
		#if (sys && !html5)
		if (charName == null || charName.length == 0) return;
		// 本地资源不全（例如之前测试残留的半同步 JSON，但图集 PNG 缺失）不发送：
		// 对端拿到残缺角色只会“看到名字加载不出皮肤”。
		if (!charAssetsComplete(charName)) return;
		var files:Array<{rel:String, bytes:haxe.io.Bytes}> = collectCharFiles(charName);
		if (files.length == 0) return;

		send('CHARSYNC|' + charName + '|' + files.length);
		var chunkSize:Int = 60000;
		for (f in files)
		{
			var b64:String = Base64.encode(f.bytes);
			var total:Int = Std.int(Math.max(1, Math.ceil(b64.length / chunkSize)));
			for (i in 0...total)
			{
				var part:String = b64.substring(i * chunkSize, (i + 1) * chunkSize);
				send('CHARSYNC_FILE|' + charName + '|' + f.rel + '|' + i + '/' + total + '|' + part);
			}
		}
		send('CHARSYNC_END|' + charName);
		#end
	}

	/** 处理对端发来的角色同步消息；返回 true 表示消息已被消费（状态机无需再处理） */
	public static function handleSyncMessage(m:String):Bool
	{
		#if (sys && !html5)
		if (m == null) return false;
		if (m.indexOf('CHARSYNC|') == 0)
		{
			var parts:Array<String> = m.split('|');
			syncRecvChar = parts.length > 1 ? parts[1] : '';
			syncRecvExpected = parts.length > 2 ? Std.parseInt(parts[2]) : 0;
			syncRecvDone = 0;
			syncFileRel = '';
			syncFileTotal = 0;
			syncFileChunks = 0;
			syncFileB64Parts = [];
			return true;
		}
		if (m.indexOf('CHARSYNC_FILE|') == 0)
		{
			var parts:Array<String> = m.split('|');
			if (parts.length >= 5)
			{
				var idxParts:Array<String> = parts[3].split('/');
				var total:Int = (idxParts.length > 1) ? Std.parseInt(idxParts[1]) : 0;
				var idx:Int = (idxParts.length > 0) ? Std.parseInt(idxParts[0]) : 0;
				if (idx == 0) { syncFileRel = parts[2]; syncFileTotal = total; syncFileB64Parts = []; syncFileChunks = 0; }
				syncFileB64Parts.push(parts[4]); // 分块先暂存，收齐后一次性 join 解码（避免大字符串反复拼接）
				syncFileChunks++;
				if (syncFileTotal > 0 && syncFileChunks >= syncFileTotal)
				{
					saveSyncFile(syncFileRel, syncFileB64Parts.join(''));
					syncRecvDone++;
					syncFileRel = '';
					syncFileB64Parts = [];
					syncFileChunks = 0;
				}
			}
			return true;
		}
		if (m.indexOf('CHARSYNC_END|') == 0)
		{
			syncRecvChar = '';
			syncRecvExpected = 0;
			syncRecvDone = 0;
			return true;
		}
		if (m.indexOf('CHARSYNC') == 0) return true;
		#end
		return false;
	}

	/** 收集某角色的全部资源文件（相对 mods 目录的 rel 路径 + 字节） */
	static function collectCharFiles(charName:String):Array<{rel:String, bytes:haxe.io.Bytes}>
	{
		var out:Array<{rel:String, bytes:haxe.io.Bytes}> = [];
		var jsonRel:String = 'characters/' + charName + '.json';
		var jsonPath:String = resolveSyncFile(jsonRel);
		if (jsonPath == null) return out;
		// 只同步模组角色：内置角色（assets/…）对端本来就有，避免无谓流量
		if (jsonPath.indexOf('mods/') < 0) return out;

		addSyncFile(out, jsonRel, jsonPath);

		var json:Dynamic = null;
		try json = Json.parse(File.getContent(jsonPath)) catch (e:Dynamic) {}
		if (json == null) return out;

		collectImageFiles(out, json);
		collectIconFiles(out, json, charName);
		return out;
	}

	static function addSyncFile(out:Array<{rel:String, bytes:haxe.io.Bytes}>, rel:String, absPath:String):Void
	{
		if (absPath == null || !FileSystem.exists(absPath)) return;
		try out.push({rel: rel, bytes: File.getBytes(absPath)}) catch (e:Dynamic) {}
	}

	/** 全模组范围解析资源：当前/全局/根目录（modFolders）→ 所有已安装模组 → 内置 assets */
	public static function resolveSyncFile(rel:String):String
	{
		var p:String = Paths.modFolders(rel);
		if (FileSystem.exists(p)) return p;
		// 角色可能来自某个「非当前、非全局」的模组（例如根目录 characters/ 残留了 JSON，
		// 而图集只在模组目录里）；必须遍历全部已安装模组，否则大图集 PNG 会被漏掉。
		for (mod in Mods.getModDirectories())
		{
			p = Paths.mods(mod + '/' + rel);
			if (FileSystem.exists(p)) return p;
		}
		p = Paths.getPreloadPath(rel);
		if (FileSystem.exists(p)) return p;
		p = Paths.getPath(rel);
		if (FileSystem.exists(p)) return p;
		return null;
	}

	/** 角色资源是否齐备（JSON + 任一图集/图片可解析）；半同步残留角色（有 JSON 无 PNG）返回 false */
	public static function charAssetsComplete(charName:String):Bool
	{
		#if (sys && !html5)
		var jsonPath:String = resolveSyncFile('characters/' + charName + '.json');
		if (jsonPath == null) return false;
		var json:Dynamic = null;
		try json = Json.parse(File.getContent(jsonPath)) catch (e:Dynamic) {}
		if (json == null) return false;
		var imgRaw:String = Reflect.field(json, 'image');
		if (imgRaw == null || imgRaw == '') return false;
		for (part in imgRaw.split(','))
		{
			var img:String = part.trim();
			if (img.length == 0) continue;
			var dirAbs:String = resolveSyncFile('images/' + img);
			if (dirAbs != null && FileSystem.isDirectory(dirAbs)) return true;  // Animate 图集目录
			if (resolveSyncFile('images/' + img + '.png') != null) return true; // 普通 sparrow png(+xml/txt)
		}
		return false;
		#else
		return true;
		#end
	}

	/** 查找包含该角色 JSON 的模组目录名（全模组搜索；内置/找不到返回 ''） */
	public static function findCharMod(charName:String):String
	{
		#if (sys && !html5)
		var rel:String = 'characters/' + charName + '.json';
		var p:String = Paths.modFolders(rel);
		if (FileSystem.exists(p))
		{
			var modName:String = modNameFromPath(p);
			if (modName != null) return modName;
		}
		for (mod in Mods.getModDirectories())
		{
			p = Paths.mods(mod + '/' + rel);
			if (FileSystem.exists(p)) return mod;
		}
		#end
		return '';
	}

	/** 从 'mods/<模组名>/...' 路径提取模组名（'mods/characters/...' 这类根目录同步残留返回 null） */
	static function modNameFromPath(p:String):String
	{
		var idx:Int = p.indexOf('mods/');
		if (idx < 0) return null;
		var rest:String = p.substring(idx + 5);
		var slash:Int = rest.indexOf('/');
		if (slash <= 0) return null;
		var modName:String = rest.substring(0, slash);
		if (modName.length == 0 || Mods.ignoreModFolders.contains(modName.toLowerCase())) return null;
		return modName;
	}

	static function collectImageFiles(out:Array<{rel:String, bytes:haxe.io.Bytes}>, json:Dynamic):Void
	{
		var imgRaw:String = Reflect.field(json, 'image');
		if (imgRaw == null) return;
		for (part in imgRaw.split(','))
		{
			var img:String = part.trim();
			if (img.length == 0) continue;
			var dirRel:String = 'images/' + img;
			var dirAbs:String = resolveSyncFile(dirRel);
			if (dirAbs != null && FileSystem.isDirectory(dirAbs))
			{
				// Adobe Animate 图集（spritemap1.json/Animation.json/spritemap*.png…）：整目录同步
				for (fn in FileSystem.readDirectory(dirAbs))
					addSyncFile(out, dirRel + '/' + fn, Path.join([dirAbs, fn]));
				continue;
			}
			addSyncFile(out, dirRel + '.png', resolveSyncFile(dirRel + '.png'));
			addSyncFile(out, dirRel + '.xml', resolveSyncFile(dirRel + '.xml'));
			addSyncFile(out, dirRel + '.txt', resolveSyncFile(dirRel + '.txt'));
		}
	}

	static function collectIconFiles(out:Array<{rel:String, bytes:haxe.io.Bytes}>, json:Dynamic, charName:String):Void
	{
		var h:String = Reflect.field(json, 'healthicon');
		if (h == null || h == '') h = charName;
		var variants:Array<String> = [h, 'icon-' + h, h + '-pixel', 'icon-' + h + '-pixel'];
		for (v in variants)
		{
			var rel:String = 'images/icons/' + v + '.png';
			addSyncFile(out, rel, resolveSyncFile(rel));
		}
	}

	static function saveSyncFile(rel:String, b64:String):Void
	{
		try
		{
			var bytes:haxe.io.Bytes = Base64.decode(b64);
			var dest:String = Paths.mods(rel);
			makeDirs(Path.directory(dest));
			File.saveBytes(dest, bytes);
			trace('[CHARSYNC] saved ' + rel + ' (' + bytes.length + ' B)');
		}
		catch (e:Dynamic) { trace('[CHARSYNC] save failed ' + rel + ': ' + e); }
	}

	static function makeDirs(dir:String):Void
	{
		if (dir == null || dir.length == 0) return;
		if (FileSystem.exists(dir)) return;
		makeDirs(Path.directory(dir));
		try FileSystem.createDirectory(dir) catch (e:Dynamic) {}
	}

	static function getLocalIP():String
	{
		try
		{
			var s = new Socket();
			s.connect(new Host('8.8.8.8'), 53);
			var ip = s.host().host.toString();
			s.close();
			return ip;
		}
		catch (e:Dynamic) {}
		return '0.0.0.0';
	}
	#end

	public static function stop():Void
	{
		#if (sys && !html5)
		isConnected = false;
		isHost = false;
		try
		{
			if (serverSocket != null) serverSocket.close();
			for (c in clientSockets) c.close();
			if (clientSocket != null) clientSocket.close();
		}
		catch (e:Dynamic) {}
		serverSocket = null;
		clientSockets = [];
		clientSocket = null;
		clientBuffer = new BytesBuffer();
		hostBuffers = [];
		outQueue = [];
		outBytes = null;
		outOffset = 0;
		// 注意：不清空 msgQueue —— 断线提示由 UI poll 一次消费
		stopBeacon();
		restoreJudgementOverrides();
		#end
	}
}
