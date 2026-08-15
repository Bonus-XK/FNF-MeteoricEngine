package backend;

#if (sys && !html5)
import sys.net.Socket;
import sys.net.Host;
#end

/**
 * 极简联机骨架：房主即服务器（TCP），无中心服务器。
 * 阶段 1 只负责创建/加入房间、连接、收发消息。
 */
class Multiplayer
{
	public static var isHost:Bool = false;
	public static var isConnected:Bool = false;
	public static var localIP:String = '0.0.0.0';
	public static var port:Int = 27750;
	public static var roomCode:String = '';
	public static var lastError:String = '';

	#if (sys && !html5)
	static var serverSocket:Socket = null;
	static var clientSockets:Array<Socket> = [];
	static var clientSocket:Socket = null;
	static var clientBuffer:String = '';
	static var hostBuffers:Map<Socket, String> = [];
	static var msgQueue:Array<String> = [];
	#end

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

	public static function connect(ip:String, p:Int = 27750):String
	{
		#if (sys && !html5)
		stop();
		port = p;
		isHost = false;
		try
		{
			var s = new Socket();
			s.setTimeout(3);
			s.connect(new Host(ip), port);
			s.setBlocking(false);
			clientSocket = s;
			clientBuffer = '';
			isConnected = true;
			lastError = '';
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
		try
		{
			var data = msg + '\n';
			if (isHost)
			{
				for (c in clientSockets)
				{
					c.output.writeString(data);
					c.output.flush();
				}
			}
			else if (clientSocket != null)
			{
				clientSocket.output.writeString(data);
				clientSocket.output.flush();
			}
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		return false;
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

	public static function update():Void
	{
		#if (sys && !html5)
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
						clientSockets.push(c);
						hostBuffers.set(c, '');
						msgQueue.push('PLAYER_JOINED');
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
				readFromClient();
		}
		#end
	}

	#if (sys && !html5)
	static function readFromHostClient(s:Socket):Void
	{
		var buf:String = hostBuffers.get(s);
		if (buf == null) return;
		try
		{
			while (true)
			{
				var c:Int = s.input.readByte();
				if (c == 10)
				{
					if (buf.length > 0) msgQueue.push(buf);
					buf = '';
				}
				else
				{
					buf += String.fromCharCode(c);
				}
			}
		}
		catch (e:Dynamic)
		{
			if (Std.string(e).indexOf('Blocked') < 0)
			{
				clientSockets.remove(s);
				hostBuffers.remove(s);
				try
				{
					s.close();
				}
				catch (e2:Dynamic) {}
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
					if (clientBuffer.length > 0) msgQueue.push(clientBuffer);
					clientBuffer = '';
				}
				else
				{
					clientBuffer += String.fromCharCode(c);
				}
			}
		}
		catch (e:Dynamic)
		{
			if (Std.string(e).indexOf('Blocked') < 0)
			{
				stop();
			}
		}
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
		clientBuffer = '';
		hostBuffers = [];
		msgQueue = [];
		#end
	}
}
