package cne;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
import backend.ClientPrefs;
import backend.Mods;
import backend.Paths;

using StringTools;

/**
 * CNE 式界面重定向表：读取每个启用 mod 的 `mods/<mod>/flags.ini`。
 *
 * 支持的段（与 CNE `Flags.loadFromData` 的 `StateRedirects` 语义对齐）：
 *
 * ```ini
 * [StateRedirects]
 * MainMenuState = DemoState
 *
 * [StateRedirects.force]
 * MainMenuState = AnotherDemoState
 * ```
 *
 * - `[StateRedirects]`：**先到先得**（第一个 mod 的设置生效，后续 mod 不覆盖）。
 * - `[StateRedirects.force]`：**后到覆盖**（最后一个 mod 的设置生效），并在合并时压过普通段。
 * - 值的两种形态：
 *   - Haxe 类全名（`Type.resolveClass` 能解析）→ 实例化该类；
 *   - 其它字符串 → 交给 `cne.ModState(value)`，按 `data/states/<value>/LIB_<mod>.hx` 找脚本。
 *
 * 默认关闭：只有设置 → 编程 → 界面重定向（`ClientPrefs.data.cneStateRedirects`）打开时才生效。
 */
class StateRedirects
{
	public static var redirects:Map<String, String> = [];
	static var forceRedirects:Map<String, String> = [];
	static var loaded:Bool = false;

	public static function reload():Void
	{
		redirects = [];
		forceRedirects = [];
		for (mod in activeMods())
		{
			// 两个来源都读：
			//  - `flags.ini`：Meteoric 侧约定的通用标志位文件；
			//  - `data/config/modpack.ini`：**CNE 的正式约定**（CNE `backend/system/Flags.hx:405`
			//    从该文件读 flags，mod 作者在 `[StateRedirects]` 里写重定向，例如 saturday_morning_alive）。
			for (file in ['flags.ini', 'data/config/modpack.ini'])
			{
				var path:String = Paths.mods('$mod/$file');
				if (sys.FileSystem.exists(path)) parse(path);
			}
		}
		for (k => v in forceRedirects) redirects.set(k, v);
		loaded = true;
	}

	static function parse(path:String):Void
	{
		var content:String = null;
		try { content = sys.io.File.getContent(path); } catch (e:Dynamic) { return; }
		if (content == null) return;

		var section:String = '';
		for (raw in content.split('\n'))
		{
			var line:String = raw.trim();
			if (line.length == 0 || line.startsWith(';') || line.startsWith('#')) continue;
			if (line.startsWith('[') && line.endsWith(']'))
			{
				section = line.substr(1, line.length - 2).trim().toLowerCase();
				continue;
			}
			var eq:Int = line.indexOf('=');
			if (eq <= 0) continue;
			var key:String = line.substr(0, eq).trim();
			var value:String = stripQuotes(line.substr(eq + 1).trim());
			if (key.length == 0 || value.length == 0) continue;

			switch (section)
			{
				case 'stateredirects':
					if (!redirects.exists(key)) redirects.set(key, value);
				case 'stateredirects.force':
					forceRedirects.set(key, value);
				default:
			}
		}
	}

	/** INI 值去引号：CNE 的 modpack.ini 写成 `TitleState="SewerSlideMain"`。 */
	static function stripQuotes(v:String):String
	{
		if (v == null || v.length < 2) return v;
		var first:String = v.charAt(0);
		var last:String = v.charAt(v.length - 1);
		if ((first == '"' && last == '"') || (first == '\'' && last == '\''))
			return v.substr(1, v.length - 2).trim();
		return v;
	}

	/** 取重定向目标；同时解析链式指向并防环（最多 8 跳）。 */
	public static function resolve(stateName:String):String
	{
		if (!loaded) reload();
		var target:String = redirects.get(stateName);
		var depth:Int = 0;
		while (target != null && target != stateName && depth < 8)
		{
			var next:String = redirects.get(target);
			if (next == null) break;
			target = next;
			depth++;
		}
		return target == stateName ? null : target;
	}

	static function activeMods():Array<String>
	{
		if (ClientPrefs.data == null) return [];
		return Mods.parseList().enabled;
	}
}
#end
