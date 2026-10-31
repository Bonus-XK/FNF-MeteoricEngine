package backend;

import flixel.util.FlxSave;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

class CoolUtil
{
	inline public static function quantize(f:Float, snap:Float){
		// changed so this actually works lol
		var m:Float = Math.fround(f * snap);
		trace(snap);
		return (m / snap);
	}

	inline public static function capitalize(text:String)
		return text.charAt(0).toUpperCase() + text.substr(1).toLowerCase();

	inline public static function coolTextFile(path:String):Array<String>
	{
		var daList:String = null;
		#if (sys && MODS_ALLOWED)
		var formatted:Array<String> = path.split(':'); //prevent "shared:", "preload:" and other library names on file path
		path = formatted[formatted.length-1];
		if(FileSystem.exists(path)) daList = File.getContent(path);
		#else
		if(Assets.exists(path)) daList = Assets.getText(path);
		#end
		return daList != null ? listFromString(daList) : [];
	}

	inline public static function colorFromString(color:String):FlxColor
	{
		var hideChars = ~/[\t\n\r]/;
		var color:String = hideChars.split(color).join('').trim();
		if(color.startsWith('0x')) color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if(colorNum == null) colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
	}

	inline public static function listFromString(string:String):Array<String>
	{
		var daList:Array<String> = [];
		daList = string.trim().split('\n');

		for (i in 0...daList.length)
			daList[i] = daList[i].trim();

		return daList;
	}

	public static function floorDecimal(value:Float, decimals:Int):Float
	{
		if(decimals < 1)
			return Math.floor(value);

		var tempMult:Float = 1;
		for (i in 0...decimals)
			tempMult *= 10;

		var newValue:Float = Math.floor(value * tempMult);
		return newValue / tempMult;
	}
	
	inline public static function dominantColor(sprite:flixel.FlxSprite):Int
	{
		var countByColor:Map<Int, Int> = [];
		for(col in 0...sprite.frameWidth) {
			for(row in 0...sprite.frameHeight) {
				var colorOfThisPixel:Int = sprite.pixels.getPixel32(col, row);
				if(colorOfThisPixel != 0) {
					if(countByColor.exists(colorOfThisPixel))
						countByColor[colorOfThisPixel] = countByColor[colorOfThisPixel] + 1;
					else if(countByColor[colorOfThisPixel] != 13520687 - (2*13520687))
						countByColor[colorOfThisPixel] = 1;
				}
			}
		}

		var maxCount = 0;
		var maxKey:Int = 0; //after the loop this will store the max color
		countByColor[FlxColor.BLACK] = 0;
		for(key in countByColor.keys()) {
			if(countByColor[key] >= maxCount) {
				maxCount = countByColor[key];
				maxKey = key;
			}
		}
		countByColor = [];
		return maxKey;
	}

	inline public static function numberArray(max:Int, ?min = 0):Array<Int>
	{
		var dumbArray:Array<Int> = [];
		for (i in min...max) dumbArray.push(i);

		return dumbArray;
	}

	inline public static function browserLoad(site:String) {
		#if linux
		Sys.command('/usr/bin/xdg-open', [site]);
		#else
		FlxG.openURL(site);
		#end
	}

	/** 存档目录根（Flixel 5+ 由 Project.xml 的 company / file 元数据决定 → Bonus-XK/Meteoric）
		`folder` 参数只在 flixel < 5 的旧分支生效；flixel 6.2.0 下走 else 分支，该参数不参与取值，
		保留只为兼容既有调用签名。默认值写引擎名，避免再出现上游作者名。 **/
	inline public static function getSavePath(folder:String = 'Meteoric'):String {
		#if (sys && !android)
		// 测试隔离：METEORIC_SAVE_DIR 优先级最高 —— 自动化/bot 冒烟跑在独立目录，
		// 存档全部写到那里，**绝不触碰玩家真实存档**。详见 testSavePath()。
		var isolated:String = testSavePath();
		if (isolated != null) return isolated;
		// 携带模式：设置改写到引擎目录（详见 portableRelativeTo）
		// ⚠ 必须放在 @:privateAccess **之前**：那个标记只作用于紧随其后的 return 表达式，
		//   插在中间会让 FlxSave.validate 的私有访问授权落到本段代码上（编译报
		//   "Cannot access private field validate"）。
		var portable:String = portableSavePath();
		if (portable != null) return portable;
		#end
		@:privateAccess
		return #if (flixel < "5.0.0") folder #else FlxG.stage.application.meta.get('company')
			+ '/'
			+ FlxSave.validate(FlxG.stage.application.meta.get('file')) #end;
	}

	// ================= 携带模式（Portable Mode） =================
	//
	// 目标：设置/键位/高分/回放跟着引擎目录走，整套拷到 U 盘上插到别的电脑也能用。
	//
	// 为什么不能直接传绝对路径给 FlxSave：
	//   openfl/net/SharedObject.hx:881 把落点写死成
	//       System.applicationStorageDirectory + "/" + localPath + "/"
	//   localPath 永远是相对 `applicationStorageDirectory`（macOS 上是
	//   ~/Library/Application Support/）的片段，传绝对路径会被当成相对路径拼上去。
	//   但它**不对 localPath 做规范化**（只规范化 name），所以 `../` 会被文件系统
	//   原样解析 —— 于是只能用「上溯到根 + 目标绝对路径」的相对写法绕过去。
	//
	// 上溯层数在运行时算（数 applicationStorageDirectory 的路径段数），
	// 所以 U 盘挂载点变化、换机器都能自动重算。

	/** 携带模式标记文件（放在 .app 旁边）。存在 = 携带模式开启。 */
	static inline var PORTABLE_MARKER:String = 'portable';

	/** 便携目录名（放在 .app 旁边）。 */
	static inline var PORTABLE_DIR:String = 'MeteoricPortable';

	/** .app 所在目录（即「引擎目录」，录像输出也用这个基准）。 */
	public static function appDirectory():String
	{
		#if (sys && !android)
		try
		{
			// applicationDirectory 在 macOS 上是 <app>/Contents/MacOS/，
			// 往两级上才是「.app 所在目录」，和录像输出口径保持一致。
			var d:String = lime.system.System.applicationDirectory;
			if (d == null || d.length == 0) return './';
			if (d.charAt(d.length - 1) != '/' && d.charAt(d.length - 1) != '\\') d += '/';
			var s:String = new String(haxe.io.Path.directory(haxe.io.Path.directory(d)));
			if (s.length == 0) return './';
			return (s.charAt(s.length - 1) == '/' || s.charAt(s.length - 1) == '\\') ? s : s + '/';
		}
		catch (e:Dynamic) {}
		#end
		return './';
	}

	/** 携带模式标记文件的绝对路径。 */
	public static function portableMarkerPath():String
	{
		return appDirectory() + PORTABLE_MARKER;
	}

	/** 是否处于携带模式（标记文件存在）。 */
	public static function isPortable():Bool
	{
		#if (sys && !android)
		try
		{

			return sys.FileSystem.exists(portableMarkerPath());
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}

	/** 打开/关闭携带模式（写/删标记文件）。返回切换后的状态。 */
	public static function setPortable(on:Bool):Bool
	{
		#if (sys && !android)
		try
		{
			var p:String = portableMarkerPath();
			if (on)
			{
				if (!sys.FileSystem.exists(p))
					sys.io.File.saveContent(p, 'Meteoric Engine 携带模式：删除本文件即可恢复正常存档路径。');
				return true;
			}
			if (sys.FileSystem.exists(p)) sys.FileSystem.deleteFile(p);
			return false;
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}

	/** 便携目录（.app 旁边的 MeteoricPortable/）。 */
	public static function portableDir():String
	{
		return appDirectory() + PORTABLE_DIR + '/';
	}

	/**
	 * 把绝对路径转成「从 applicationStorageDirectory 上溯到根」的相对写法。
	 * 例：storage=~/Library/Application Support/，target=/Volumes/USB/M/MeteoricPortable/
	 *   → "../../../../Volumes/USB/M/MeteoricPortable"
	 */
	public static function portableRelativeTo(target:String):String
	{
		if (target == null || target.length == 0) return null;
		var storage:String = lime.system.System.applicationStorageDirectory;
		if (storage == null || storage.length == 0) return null;
		// 段数 = 去掉首尾斜杠后按 '/' 切开的个数；上溯这么多层正好回到根
		var t:String = storage;
		while (t.length > 0 && (t.charAt(0) == '/' || t.charAt(0) == '\\')) t = t.substr(1);
		while (t.length > 0 && (t.charAt(t.length - 1) == '/' || t.charAt(t.length - 1) == '\\')) t = t.substr(0, t.length - 1);
		var depth:Int = 0;
		for (_ in t.split('/')) depth++;

		var up:StringBuf = new StringBuf();
		for (_ in 0...depth) up.add('../');

		var dst:String = target;
		while (dst.length > 0 && (dst.charAt(0) == '/' || dst.charAt(0) == '\\')) dst = dst.substr(1);
		return up.toString() + dst;
	}

	/**
	 * 测试隔离存档目录（环境变量 `METEORIC_SAVE_DIR`），未设置时返回 null。
	 *
	 * 用途：bot 冒烟 / 自动化回归跑在独立目录，`funkin.sol` / `controls_v3.sol` 全部写到那里，
	 * **绝不触碰玩家真实存档**。
	 *
	 * ⚠ 2026-10-29 的血债，别重犯：
	 *   以前的流程是「跑测试前备份 → 跑完用备份 cp 回去」。备份是**前一天**做的，
	 *   于是每跑一轮就把用户在这之后改的设置**全部回滚一次**，半天跑七轮 = 冲掉七次，
	 *   直接把人家存档设置搞没了。
	 *   有了这个开关，测试**根本不需要**「备份 / 恢复」这套危险动作：
	 *   `METEORIC_SAVE_DIR=/tmp/meteoric-test ./Meteoric` 即可，真实存档一个字节都不会被写。
	 *
	 * ⚠ **必须传绝对路径**（`FlxSave.bind` → `FlxSharedObject.getLocal(name, path)`，
	 *   相对路径在那里会失败、把整个启动挂住；绝对路径实测可用）。
	 * ⚠ 但实际落盘位置是 `storageDirectory + 你给的绝对路径`，即
	 *   `METEORIC_SAVE_DIR=/tmp/meteoric-test` 会写到
	 *   `~/Library/Application Support/tmp/meteoric-test/`。
	 *   反正**不会落进 `Bonus-XK/Meteoric/`**，隔离目的达到；只是路径不直观，心里有数即可。
	 */
	public static function testSavePath():String
	{
		#if (sys && !android)
		var env:String = null;
		try
		{
			env = Sys.getEnv('METEORIC_SAVE_DIR');
		}
		catch (e:Dynamic) {}
		if (env == null || env.length == 0) return null;
		// 相对路径补成绝对路径 —— **绝不能返回 null**：那会回退到真实存档，
		// 等于隔离失效（宁可路径丑一点，也不能碰用户的档）。
		if (env.charAt(0) != '/')
		{
			try
			{
				env = sys.FileSystem.fullPath(env);
			}
			catch (e:Dynamic) {}
			if (env == null || env.charAt(0) != '/') return null;
		}
		try
		{
			sys.FileSystem.createDirectory(env);
		}
		catch (e:Dynamic) {}
		return env;
		#else
		return null;
		#end
	}

	/** 携带模式下的存档目录（相对写法，可直接给 FlxSave.bind）；非携带模式返回 null。 */
	public static function portableSavePath():String
	{
		if (!isPortable()) return null;
		var dir:String = portableDir();
		try
		{

			sys.FileSystem.createDirectory(dir);
		}
		catch (e:Dynamic) {}
		return portableRelativeTo(dir);
	}
}
