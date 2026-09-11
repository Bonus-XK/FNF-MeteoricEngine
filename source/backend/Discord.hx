package backend;

import Sys.sleep;
import discord_rpc.DiscordRpc;
import lime.app.Application;

class DiscordClient
{
	public static var isInitialized:Bool = false;
	private static var _defaultID:String = "863222024192262205";
	public static var clientID(default, set):String = _defaultID;

	private static var _options:Dynamic = {
		details: "In the Menus",
		state: null,
		largeImageKey: 'icon',
		largeImageText: "Meteoric Engine",
		smallImageKey : null,
		startTimestamp : null,
		endTimestamp : null
	};

	public function new()
	{
		trace("Discord Client starting...");
		DiscordRpc.start({
			clientID: clientID,
			onReady: onReady,
			onError: onError,
			onDisconnected: onDisconnected
		});
		trace("Discord Client started.");
		// process() 由主线程每帧调用（Main ENTER_FRAME → DiscordClient.tick），
		// 不再放守护线程：子线程里的 DiscordRpc.process / trace / 回调会分配 hxcpp GC 对象，
		// 与主线程 GC 并发破坏堆（SIGILL/SIGSEGV 无日志闪退，加载期/游戏期随机出现）。
	}

	/** 主线程每帧调用：处理 Discord RPC 事件（替代原守护线程循环） */
	public static function tick():Void
	{
		if (!isInitialized) return;
		DiscordRpc.process();
	}

	public static function check()
	{
		if(!ClientPrefs.data.discordRPC)
		{
			if(isInitialized) shutdown();
			isInitialized = false;
		}
		else start();
	}
	
	public static function start()
	{
		if (!isInitialized && ClientPrefs.data.discordRPC) {
			initialize();
			Application.current.window.onClose.add(function() {
				shutdown();
			});
		}
	}

	public static function shutdown()
	{
		DiscordRpc.shutdown();
	}
	
	static function onReady()
	{
		DiscordRpc.presence(_options);
	}

	private static function set_clientID(newID:String)
	{
		var change:Bool = (clientID != newID);
		clientID = newID;

		if(change && isInitialized)
		{
			shutdown();
			isInitialized = false;
			start();
			DiscordRpc.process();
		}
		return newID;
	}

	static function onError(_code:Int, _message:String)
	{
		trace('Error! $_code : $_message');
	}

	static function onDisconnected(_code:Int, _message:String)
	{
		trace('Disconnected! $_code : $_message');
	}

	public static function initialize()
	{
		// 直接在主线程启动（原守护线程删除）：DiscordRpc.start 一次性调用 + trace 均在主线程，
		// 回调由主线程 tick() 逐帧处理，子线程不再存在 → 无 GC 并发破坏堆风险
		try
		{
			new DiscordClient();
		}
		catch(e:Dynamic)
		{
			trace('Discord init failed: ' + e);
		}
		trace("Discord Client initialized");
		isInitialized = true;
	}

	public static function changePresence(details:String, state:Null<String>, ?smallImageKey : String, ?hasStartTimestamp : Bool, ?endTimestamp: Float)
	{
		var startTimestamp:Float = 0;
		if (hasStartTimestamp) startTimestamp = Date.now().getTime();
		if (endTimestamp > 0) endTimestamp = startTimestamp + endTimestamp;

		_options.details = details;
		_options.state = state;
		_options.largeImageKey = 'icon';
		_options.largeImageText = "Engine Version: " + Main.meVersion;
		_options.smallImageKey = smallImageKey;
		// Obtained times are in milliseconds so they are divided so Discord can use it
		_options.startTimestamp = Std.int(startTimestamp / 1000);
		_options.endTimestamp = Std.int(endTimestamp / 1000);
		DiscordRpc.presence(_options);

		//trace('Discord RPC Updated. Arguments: $details, $state, $smallImageKey, $hasStartTimestamp, $endTimestamp');
	}
	
	public static function resetClientID()
		clientID = _defaultID;

	#if MODS_ALLOWED
	public static function loadModRPC()
	{
		var pack:Dynamic = Mods.getPack();
		if(pack != null && pack.discordRPC != null && pack.discordRPC != clientID)
		{
			clientID = pack.discordRPC;
			//trace('Changing clientID! $clientID, $_defaultID');
		}
	}
	#end

	#if LUA_ALLOWED
	public static function addLuaCallbacks(lua:State) {
		Lua_helper.add_callback(lua, "changeDiscordPresence", function(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float) {
			changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
		});

		Lua_helper.add_callback(lua, "changeDiscordClientID", function(?newID:String = null) {
			if(newID == null) newID = _defaultID;
			clientID = newID;
		});
	}
	#end
}
