package backend;

/**
 * 局域网自动发现到的房间条目（Multiplayer 发现列表用，UI 只读）。
 */
class DiscoveredRoom
{
	public var roomCode:String;
	public var hostNick:String;
	public var hostIP:String;
	public var playerCount:Int;
	public var full:Bool;
	public var lastSeen:Float;

	public function new(roomCode:String, hostNick:String, hostIP:String, playerCount:Int, full:Bool, lastSeen:Float)
	{
		this.roomCode = roomCode;
		this.hostNick = hostNick;
		this.hostIP = hostIP;
		this.playerCount = playerCount;
		this.full = full;
		this.lastSeen = lastSeen;
	}
}
