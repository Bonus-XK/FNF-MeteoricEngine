package backend;

#if !desktop
/**
 * 非桌面平台的 DiscordRpc no-op 替身。
 *
 * 背景：`Project.xml` 只为桌面引入该库（`<haxelib name="discord_rpc" if="desktop"/>`），
 * 而 `backend/Discord.hx` 直接 `import discord_rpc.DiscordRpc` 并调用 start/process/shutdown/presence，
 * 因此 Android/iOS 在**编译期**就报 `Type not found : discord_rpc.DiscordRpc`。
 * 这里提供同签名的空实现，`Discord.hx` 仅在 import 处做条件选择，调用点与桌面行为完全不变。
 */
class DiscordRpcStub
{
	public static function start(?options:Dynamic):Void {}

	public static function process():Void {}

	public static function shutdown():Void {}

	public static function presence(?options:Dynamic):Void {}
}
#end
