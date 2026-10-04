package backend;

import haxe.Json;
import openfl.utils.Assets;
import openfl.utils.AssetType;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Meteoric 多语言运行时（语言包 = JSON，key = 稳定英文标识）
 *
 * 设计约束（与 skills/meteoric-system 一致）：
 *  - key 是**稳定英文标识**（如 `ui.pause`），与任何语言的文案解耦。
 *    改中文文案不会改 key，社区作者的翻译不会因为引擎改措辞而失效。
 *  - 引擎原中文文案整体搬进 `assets/languages/zh.json`（= 迁移前的逐字内容，
 *    保证中文玩家零视觉回归）；`assets/languages/en.json` 为英文。
 *  - 玩家/社区投放：把 `xx.json` 放进 `Resources/languages/`（macOS **不要**塞进
 *    .app 包内 —— 会破坏代码签名），或作为 mod 的 `languages/xx.json` 覆盖。
 *    定位逻辑唯一入口 = `Paths.langFile()`。
 *
 * 回退链：`当前语言 → en → zh → key 本身`。
 *  社区语言漏翻时显示英文（通用可读）而不是中文；en/zh 本身完整，
 *  所以只有「社区语言 + key 根本不存在」才会漏到最后的 key 兜底（可见即可发现）。
 *
 * 全静态类。界面在**创建时**调用 `Lang.t(...)` 取文本，
 * 不要在 update() 里反复查表（见 meteoric-mobile 性能红线）。
 */
/**
 * 一个语言包的可展示信息。
 *
 * 放在模块级（class 外）而不是类内：类内 typedef 在 lime/hxcpp 的解析路径下会被拒
 * （"Unexpected typedef"），模块级是全版本通吃的写法。外部通过 `Lang.LangInfo` 引用。
 */
typedef LangInfo =
{
	/** 语言代码，文件名即代码，如 `zh` / `en` / `pt-BR` */
	var code:String;
	/** 英文说明名（给开发者看） */
	var name:String;
	/** 自称名（给母语玩家看，下拉框优先显示这个） */
	var nativeName:String;
	/** 实际读到的文件路径（诊断用） */
	var path:String;
	/** true = 引擎内置，false = 玩家投放 / mod 提供 */
	var builtin:Bool;
}

class Lang
{
	/** 默认语言（旧存档没有 language 字段时用它，= 迁移前的中文行为） */
	public static final DEFAULT_LANG:String = 'zh';

	/** 回退语言：社区语言缺 key 时的第一兜底 */
	public static final FALLBACK_LANG:String = 'en';

	/** 语言文件里保留的元信息键（下拉框显示名用），不参与 t() 查询 */
	public static final META_KEY:String = '_meta';

	/** 当前生效的语言代码 */
	public static var current(default, null):String = DEFAULT_LANG;

	private static var _map:Map<String, String> = null;
	/** 回退链（不含当前语言），按优先级排列 */
	private static var _chain:Array<Map<String, String>> = null;
	private static var _infos:Array<LangInfo> = null;
	private static var _byCode:Map<String, LangInfo> = null;

	private static var _rawCache:Map<String, String> = null;
	private static var _zhCache:Map<String, String> = null;
	private static var langListeners:Array<Void->Void> = [];

	// ------------------------------------------------------------------ 生命周期

	/** 语言变更监听（与 DesignTokens.addThemeListener 同一套模式）。
	 *  注册方**必须**在销毁时 removeLangListener 摘掉，否则会回调到已销毁的对象。 */
	public static function addLangListener(fn:Void->Void):Void
	{
		if (fn == null) return;
		if (!langListeners.contains(fn)) langListeners.push(fn);
	}

	public static function removeLangListener(fn:Void->Void):Void
	{
		if (fn == null) return;
		langListeners.remove(fn);
	}

	private static function notifyLangListeners():Void
	{
		if (langListeners.length < 1) return;
		// 复制一份再遍历：回调内部可能注册/注销监听
		var snapshot:Array<Void->Void> = langListeners.copy();
		for (fn in snapshot)
		{
			if (fn == null) continue;
			try fn() catch (e:Dynamic) {} // 单个监听者出错不能连带界面崩掉
		}
	}

	/**
	 * 启动时调用一次。必须在 `ClientPrefs.loadPrefs()` 之后（要读存档里的 language）。
	 *
	 * @param lang 传 null / 空串时用 DEFAULT_LANG。
	 */
	public static function init(?lang:String):Void
	{
		refreshAvailable();
		load(lang);
	}

	/**
	 * 切换语言。找不到该语言包时回落到 DEFAULT_LANG，**不抛异常** ——
	 * 语言包缺失属于「玩家自己装的不全」，不该让引擎起不来。
	 *
	 * @return 实际生效的语言代码（= Lang.current）
	 */
	public static function load(lang:String):String
	{
		var code:String = (lang == null || lang.length == 0) ? DEFAULT_LANG : lang;

		var m:Map<String, String> = readLang(code);
		if (m == null)
		{
			if (code == DEFAULT_LANG)
			{
				// 内置 zh 也读不到：置空表，t() 一路回落到 key（界面显示 key，可诊断）
				if (current == code) return current; // 已经是它了，不必再通知
				_map = new Map<String, String>();
				current = code;
				_rebuildChain();
				notifyLangListeners();
				return current;
			}
			return load(DEFAULT_LANG);
		}

		if (current == code && _map != null) return current; // 无变化不打扰界面
		_map = m;
		current = code;
		_rebuildChain();
		notifyLangListeners();
		return current;
	}

	private static function _rebuildChain():Void
	{
		_chain = [];
		// 先 en 再 zh；与当前语言重复的跳过，避免同一张表查两遍
		for (code in [FALLBACK_LANG, DEFAULT_LANG])
		{
			if (code == current) continue;
			var m:Map<String, String> = readLang(code);
			if (m != null) _chain.push(m);
		}
	}

	// ------------------------------------------------------------------ 查询

	/**
	 * 取译文。**这是界面唯一应该调用的入口。**
	 *
	 * @param key  稳定英文标识
	 * @param args 可选的格式化参数（数组，按顺序替换文案里的 `%s` / `%v` 占位符）；
	 *             不传时原样返回（含占位符），由调用方自己拼。
	 */
	public static function t(key:String, ?args:Array<Dynamic>):String
	{
		if (key == null) return '';

		var s:String = null;
		if (_map != null) s = _map.get(key);
		if (s == null)
		{
			if (_chain != null)
			{
				for (m in _chain)
				{
					s = m.get(key);
					if (s != null) break;
				}
			}
		}
		// 全部未命中 → 返回 key 本身：宁可显示一个可搜索的英文标识，
		// 也不要静默显示空串（空串在界面上无法定位是哪条缺失）。
		if (s == null) s = key;

		if (args != null && args.length > 0)
		{
			// 顺序把 %s / %v 替换成参数（每遇一个占位符吃掉一个参数）
			var out = new StringBuf();
			var ai = 0;
			var i = 0;
			while (i < s.length)
			{
				if (ai < args.length && i + 1 < s.length
					&& s.charAt(i) == '%' && (s.charAt(i + 1) == 's' || s.charAt(i + 1) == 'v'))
				{
					out.add(Std.string(args[ai++]));
					i += 2;
				}
				else
				{
					out.add(s.charAt(i));
					i++;
				}
			}
			s = out.toString();
		}
		return s;
	}

	/**
	 * 取译文，缺 key 时回落到**调用点给的中文原文**。
	 *
	 * 这是迁移期的关键 API：新接管的文案一律用 `tOr`，于是
	 *  - 已进语言包 → 按语言显示；
	 *  - 还没进语言包 → 显示代码里原有的中文，与迁移前**逐字一致**（零视觉回归）。
	 *
	 * 等某个 key 补进 zh.json / en.json 后就自动切换，不需要再改代码。
	 *
	 * @param key      稳定英文标识
	 * @param fallback 缺译文时显示的原文
	 * @param args     可选格式化参数（数组，按顺序替换 `%s` / `%v`）
	 */
	public static function tOr(key:String, fallback:String, ?args:Array<Dynamic>):String
	{
		if (key == null) return fallback;
		var s:String = null;
		if (_map != null) s = _map.get(key);
		if (s == null && _chain != null)
		{
			for (m in _chain)
			{
				s = m.get(key);
				if (s != null) break;
			}
		}
		// 没译文 → 用原文（而不是 key）：迁移期保证界面显示与改动前完全一致
		if (s == null) return (fallback != null) ? fallback : key;
		return t(key, args);
	}

	/** 该 key 在当前语言（或回退链）里是否有译文 —— 给「缺翻译」体检用 */
	public static function has(key:String):Bool
	{
		if (_map != null && _map.exists(key)) return true;
		if (_chain != null)
		{
			for (m in _chain)
				if (m.exists(key)) return true;
		}
		return false;
	}

	/** 当前语言包里缺失、但 zh 里有的 key 列表（社区语言补翻用的清单） */
	public static function missingKeys():Array<String>
	{
		var out:Array<String> = [];
		if (current == DEFAULT_LANG || _map == null || _zhCache == null) return out;
		for (k in _zhCache.keys())
			if (!_map.exists(k)) out.push(k);
		out.sort(function(a:String, b:String):Int {
			return a < b ? -1 : (a > b ? 1 : 0);
		});
		return out;
	}

	// ------------------------------------------------------------------ 语言清单

	/** 可选语言列表（设置下拉框数据源）；内置项在前，其余按语言代码序 */
	public static function available():Array<LangInfo>
	{
		if (_infos == null) refreshAvailable();
		return _infos;
	}

	/** 语言代码列表（存/读存档用） */
	public static function codes():Array<String>
	{
		var out:Array<String> = [];
		for (i in available()) out.push(i.code);
		return out;
	}

	/** 下拉框显示名：优先自称名 */
	public static function displayName(code:String):String
	{
		var info:LangInfo = info(code);
		if (info == null) return code;
		return (info.nativeName != null && info.nativeName.length > 0) ? info.nativeName : info.name;
	}

	public static function info(code:String):LangInfo
	{
		if (_byCode == null) refreshAvailable();
		return _byCode.get(code);
	}

	/**
	 * 重新扫描可用语言。mod 启用/停用、语言包增删后要调。
	 * 内置只认 zh / en（打包在 assets/languages），其余靠运行时目录扫描
	 * （html5 无文件系统 → 只能看到内置两种，这是平台限制不是缺陷）。
	 */
	public static function refreshAvailable():Void
	{
		_infos = [];
		_byCode = new Map<String, LangInfo>();

		// 内置优先（保证 zh / en 永远在列表里，且排在前面）
		for (code in [DEFAULT_LANG, FALLBACK_LANG])
		{
			var p:String = 'assets/languages/' + code + '.json';
			if (!_canRead(p)) continue;
			var info:LangInfo = _makeInfo(code, p, true);
			if (info != null)
			{
				_infos.push(info);
				_byCode.set(code, info);
			}
		}

		// 运行时目录：玩家投放 + mod 提供
		var dirs:Array<String> = [Paths.languagesDir(), Paths.mods('languages')];
		for (dir in dirs)
		{
			if (dir == null) continue;
			for (f in _listDir(dir))
			{
				if (f == null || f.length < 6 || f.substr(-5) != '.json') continue;
				var code = f.substr(0, f.length - 5);
				if (code.length == 0 || _byCode.exists(code)) continue; // 内置/先扫到的不被覆盖
				var info = _makeInfo(code, dir + '/' + f, false);
				if (info != null)
				{
					_infos.push(info);
					_byCode.set(code, info);
				}
			}
		}

		// 非内置项按代码序（稳定排序，builtin 组内保持 zh → en 的插入顺序）
		var userPart:Array<LangInfo> = [];
		var builtinPart:Array<LangInfo> = [];
		for (i in _infos)
		{
			if (i.builtin) builtinPart.push(i); else userPart.push(i);
		}
		userPart.sort(function(a, b) return a.code < b.code ? -1 : (a.code > b.code ? 1 : 0));
		_infos = builtinPart.concat(userPart);
	}

	private static function _makeInfo(code:String, path:String, builtin:Bool):LangInfo
	{
		var name = code;
		var native = '';
		var raw:String = readLangRaw(path);
		if (raw != null && raw.length > 0)
		{
			var j:Dynamic = try Json.parse(raw) catch (e:Dynamic) null;
			if (j != null && Reflect.hasField(j, META_KEY))
			{
				var mm:Dynamic = Reflect.field(j, META_KEY);
				if (mm != null)
				{
					if (Reflect.hasField(mm, 'name')) name = Std.string(Reflect.field(mm, 'name'));
					if (Reflect.hasField(mm, 'nativeName')) native = Std.string(Reflect.field(mm, 'nativeName'));
				}
			}
		}
		return {code: code, name: name, nativeName: native, path: path, builtin: builtin};
	}

	// ------------------------------------------------------------------ 读盘

	/** 读原始文本：先按真实文件（sys），再按打包资源（assets/...） */
	private static function readLangRaw(path:String):String
	{
		if (path == null) return null;
		if (_rawCache != null && _rawCache.exists(path)) return _rawCache.get(path);

		var txt:String = null;
		#if sys
		try
		{
			if (FileSystem.exists(path)) txt = File.getContent(path);
		}
		catch (e:Dynamic)
		{
			txt = null;
		}
		#end
		if (txt == null)
		{
			try
			{
				if (Assets.exists(path, AssetType.TEXT)) txt = Assets.getText(path);
			}
			catch (e:Dynamic)
			{
				txt = null;
			}
		}

		if (_rawCache == null) _rawCache = new Map<String, String>();
		_rawCache.set(path, txt);
		return txt;
	}

	/** 读一个语言包 → Map（`_meta` 被剔除） */
	private static function readLang(code:String):Map<String, String>
	{
		var raw:String = readLangRaw(Paths.langFile(code));
		if (raw == null || raw.length == 0) return null;

		var j:Dynamic = try Json.parse(raw) catch (e:Dynamic) null;
		if (j == null) return null;

		var out:Map<String, String> = new Map<String, String>();
		for (field in Reflect.fields(j))
		{
			if (field == META_KEY) continue;
			var v:Dynamic = Reflect.field(j, field);
			// 只接受字符串值；社区作者写错类型（数字/数组/嵌套对象）时跳过而不是崩
			if (v != null && Std.isOfType(v, String)) out.set(field, cast v);
		}

		if (code == DEFAULT_LANG) _zhCache = out;
		return out;
	}

	/** 丢弃读盘缓存（语言包在运行中被改动后调） */
	public static function clearCache():Void
	{
		_rawCache = null;
		_zhCache = null;
		_map = null;
		_chain = null;
	}

	// ------------------------------------------------------------------ 平台适配

	/** 该路径当前是否可读（真实文件或打包资源） */
	private static function _canRead(path:String):Bool
	{
		if (path == null) return false;
		#if sys
		if (FileSystem.exists(path)) return true;
		#end
		try
		{
			return Assets.exists(path, AssetType.TEXT);
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	/** 列目录（非 sys 平台返回空数组） */
	private static function _listDir(dir:String):Array<String>
	{
		#if sys
		try
		{
			if (FileSystem.exists(dir)) return FileSystem.readDirectory(dir);
		}
		catch (e:Dynamic) {}
		#end
		return [];
	}
}