package cne;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
import backend.ClientPrefs;
import backend.Mods;
import backend.MusicBeatState;
import backend.MusicBeatSubstate;
import backend.Paths;
import flixel.FlxG;
import flixel.input.FlxInput.FlxInputState;
import flixel.input.keyboard.FlxKey;

/**
 * CNE 式 HScript 编程层（编程分区总开关的唯一执行入口）。
 *
 * 能力：
 *  - 状态脚本：`mods/<mod>/data/states/<界面类名>/LIB_<mod>.hx`（可退回 `<界面类名>.hx`）；
 *  - 全局脚本：`mods/<mod>/data/global/LIB_<mod>.hx`；
 *  - `ModState` / `ModSubState`：用 HScript 写完整界面；
 *  - 热重载：F5 原地重建当前界面的脚本组；Shift+F5 重建全局脚本组。
 *
 * 设计纪律（勿破）：
 *  - 总开关 `ClientPrefs.data.cneScripting` 关闭时，所有入口立即 return；
 *    `MusicBeatState` / `MusicBeatSubstate` 里新增的调用点必须保持“判空 + 判总开关”的短路。
 *  - 热重载是“原地重建脚本组”，不是 `FlxG.resetState()`：宿主 state 与其视觉对象不重建；
 *    旧脚本先收 `destroy` 回调，新脚本再收 `create`，因此脚本必须在 `destroy` 里清理自己创建的对象。
 *  - 新脚本组先构建、构建成功才替换旧组；构建失败（文件被删/全部解析失败）保留旧组并打日志。
 */
class ProgrammingManager
{
	static final SCRIPT_EXTS:Array<String> = ['.hx', '.hscript', '.hsc', '.hxs'];

	static var initialized:Bool = false;
	static var globalScripts:ScriptPack = null;
	static var lastModSignature:String = "";
	static var lastBeat:Int = -1;
	static var lastStep:Int = -1;

	/** 启动一次：注册全局信号并装入全局脚本。由 TitleState.create 在 ClientPrefs.loadPrefs() 之后调用。 */
	public static function init():Void
	{
		if (initialized) return;
		initialized = true;
		FlxG.signals.postUpdate.add(onPostUpdate);
		FlxG.signals.postStateSwitch.add(onPostStateSwitch);
		FlxG.signals.preStateSwitch.add(onPreStateSwitch);
		lastModSignature = modSignature();
		StateRedirects.reload();
		reloadGlobalScripts();
		log('programming layer initialized');
	}

	public static function isEnabled():Bool
	{
		// 调试构建专用：METEORIC_CNE_FORCE=1 时无视存档总开关，便于无 UI 的自动化冒烟。
		#if meteoric_debug
		if (Sys.getEnv('METEORIC_CNE_FORCE') == '1') return true;
		#end
		return ClientPrefs.data != null && ClientPrefs.data.cneScripting;
	}

	/** 界面重定向开关：存档子开关；调试构建下 METEORIC_CNE_REDIRECT_FORCE=1 强制打开。 */
	public static function redirectsEnabled():Bool
	{
		#if meteoric_debug
		if (Sys.getEnv('METEORIC_CNE_REDIRECT_FORCE') == '1') return true;
		#end
		return isEnabled() && ClientPrefs.data != null && ClientPrefs.data.cneStateRedirects;
	}

	/** 日志开关：存档里的 cneScriptLogs；调试构建下 METEORIC_CNE_FORCE=1 也强制打开。 */
	public static function logsEnabled():Bool
	{
		#if meteoric_debug
		if (Sys.getEnv('METEORIC_CNE_FORCE') == '1') return true;
		#end
		return ClientPrefs.data != null && ClientPrefs.data.cneScriptLogs;
	}

	public static function log(msg:String):Void
	{
		if (logsEnabled()) Sys.println('[CNE] ' + msg);
	}

	// ==================== 状态脚本 ====================

	public static function onStateCreate(state:MusicBeatState):Void
	{
		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneStateScripts) return;
		if (state == null || state.cneScripts != null) return;

		var name:String = state.cneScriptName != null ? state.cneScriptName : stateNameOf(state);
		var pack:ScriptPack = buildPack(state, 'data/states/$name', true);
		if (pack.hasScripts())
		{
			state.cneScripts = pack;
			pack.call('create');
			log('state scripts loaded: $name (' + pack.scripts.length + ')');
		}
		else
		{
			pack.destroy();
		}
	}

	public static function onStateUpdate(state:MusicBeatState, elapsed:Float):Void
	{
		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneStateScripts) return;
		if (state != null && state.cneScripts != null)
			state.cneScripts.call('update', [elapsed]);
	}

	public static function onStateStep(state:MusicBeatState, step:Int):Void
	{
		if (state != null && state.cneScripts != null)
			state.cneScripts.call('stepHit', [step]);
		onGlobalStep(step);
	}

	public static function onStateBeat(state:MusicBeatState, beat:Int):Void
	{
		if (state != null && state.cneScripts != null)
			state.cneScripts.call('beatHit', [beat]);
		onGlobalBeat(beat);
	}

	public static function onStateDestroy(state:MusicBeatState):Void
	{
		if (state != null && state.cneScripts != null)
		{
			state.cneScripts.call('destroy');
			state.cneScripts.destroy();
			state.cneScripts = null;
		}
	}

	// ==================== 子状态脚本 ====================

	public static function onSubStateCreate(state:MusicBeatSubstate):Void
	{
		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneStateScripts) return;
		if (state == null || state.cneScripts != null) return;

		var name:String = state.cneScriptName != null ? state.cneScriptName : stateNameOf(state);
		var pack:ScriptPack = buildPack(state, 'data/states/$name', true);
		if (pack.hasScripts())
		{
			state.cneScripts = pack;
			pack.call('create');
			log('substate scripts loaded: $name (' + pack.scripts.length + ')');
		}
		else
		{
			pack.destroy();
		}
	}

	public static function onSubStateUpdate(state:MusicBeatSubstate, elapsed:Float):Void
	{
		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneStateScripts) return;
		if (state != null && state.cneScripts != null)
			state.cneScripts.call('update', [elapsed]);
	}

	public static function onSubStateStep(state:MusicBeatSubstate, step:Int):Void
	{
		if (state != null && state.cneScripts != null)
			state.cneScripts.call('stepHit', [step]);
		onGlobalStep(step);
	}

	public static function onSubStateBeat(state:MusicBeatSubstate, beat:Int):Void
	{
		if (state != null && state.cneScripts != null)
			state.cneScripts.call('beatHit', [beat]);
		onGlobalBeat(beat);
	}

	public static function onSubStateDestroy(state:MusicBeatSubstate):Void
	{
		if (state != null && state.cneScripts != null)
		{
			state.cneScripts.call('destroy');
			state.cneScripts.destroy();
			state.cneScripts = null;
		}
	}

	// ==================== 全局脚本 ====================

	public static function reloadGlobalScripts():Void
	{
		if (globalScripts != null)
		{
			globalScripts.call('destroy');
			globalScripts.destroy();
			globalScripts = null;
		}
		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneGlobalScripts) return;

		var pack:ScriptPack = buildPack(null, 'data/global', false);
		if (pack.hasScripts())
		{
			globalScripts = pack;
			pack.call('create');
			log('global scripts loaded (' + pack.scripts.length + ')');
		}
		else
		{
			pack.destroy();
		}
	}

	static function onGlobalStep(step:Int):Void
	{
		if (globalScripts == null || step == lastStep) return;
		lastStep = step;
		globalScripts.call('stepHit', [step]);
	}

	static function onGlobalBeat(beat:Int):Void
	{
		if (globalScripts == null || beat == lastBeat) return;
		lastBeat = beat;
		globalScripts.call('beatHit', [beat]);
	}

	// ==================== 热重载 ====================

	/**
	 * 原地重载当前界面的脚本组（不重建 state、不重进关卡）。
	 * 新组构建失败时保留旧组，避免一次写错文件就让整个界面的脚本消失。
	 */
	public static function reloadCurrentStateScripts():Void
	{
		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneStateScripts) return;

		var s = FlxG.state;
		if (Std.isOfType(s, MusicBeatState))
		{
			reloadStateScripts(cast s);
			return;
		}
		var sub = (s == null) ? null : s.subState;
		while (sub != null)
		{
			if (Std.isOfType(sub, MusicBeatSubstate))
			{
				reloadSubStateScripts(cast sub);
				return;
			}
			sub = sub.subState;
		}
	}

	static function reloadStateScripts(state:MusicBeatState):Void
	{
		if (state == null || state.cneScripts == null) return;
		var name:String = state.cneScriptName != null ? state.cneScriptName : stateNameOf(state);
		var next:ScriptPack = buildPack(state, 'data/states/$name', true);
		if (!next.hasScripts())
		{
			next.destroy();
			log('state reload skipped (no scripts): $name');
			return;
		}
		state.cneScripts.call('destroy');
		state.cneScripts.destroy();
		state.cneScripts = next;
		next.call('create');
		log('state scripts reloaded: $name');
	}

	static function reloadSubStateScripts(state:MusicBeatSubstate):Void
	{
		if (state == null || state.cneScripts == null) return;
		var name:String = state.cneScriptName != null ? state.cneScriptName : stateNameOf(state);
		var next:ScriptPack = buildPack(state, 'data/states/$name', true);
		if (!next.hasScripts())
		{
			next.destroy();
			log('substate reload skipped (no scripts): $name');
			return;
		}
		state.cneScripts.call('destroy');
		state.cneScripts.destroy();
		state.cneScripts = next;
		next.call('create');
		log('substate scripts reloaded: $name');
	}

	// ==================== 信号 ====================

	static function onPostUpdate():Void
	{
		if (globalScripts != null)
		{
			var elapsed:Float = FlxG.elapsed;
			globalScripts.call('update', [elapsed]);
			globalScripts.call('postUpdate', [elapsed]);
		}

		if (!isEnabled() || ClientPrefs.data == null || !ClientPrefs.data.cneHotReload) return;
		var keys:Array<FlxKey> = ClientPrefs.data.cneHotReloadKeys;
		if (keys == null) return;
		for (key in keys)
		{
			if (FlxG.keys.checkStatus(key, FlxInputState.JUST_PRESSED))
			{
				if (FlxG.keys.pressed.SHIFT) reloadGlobalScripts();
				else reloadCurrentStateScripts();
				break;
			}
		}
	}

	static function onPostStateSwitch():Void
	{
		if (!isEnabled()) return;
		var sig:String = modSignature();
		if (sig != lastModSignature)
		{
			lastModSignature = sig;
			StateRedirects.reload();
			reloadGlobalScripts();
		}
	}

	static var redirecting:Bool = false;

	/**
	 * 界面重定向：在 FlxGame 把 `_requestedState` 真正换成当前 state 之前改写它。
	 * 与 CNE `GlobalScript.preStateSwitch` 同点（FlxGame 先派发 preStateSwitch，再 `_state = _requestedState`）。
	 */
	static function onPreStateSwitch():Void
	{
		if (redirecting || !redirectsEnabled()) return;

		var requested:Dynamic = @:privateAccess FlxG.game._requestedState;
		if (requested == null) return;
		var cn:String = Type.getClassName(Type.getClass(requested));
		if (cn == null) return;
		var shortName:Null<String> = cn.split('.').pop();
		if (shortName == null) return;

		var target:String = StateRedirects.resolve(shortName);
		if (target == null) return;

		redirecting = true;
		try
		{
			var cls:Dynamic = Type.resolveClass(target);
			if (cls != null)
				@:privateAccess FlxG.game._requestedState = Type.createInstance(cls, []);
			else
				@:privateAccess FlxG.game._requestedState = new cne.ModState(target);
			log('state redirected: $shortName -> $target');
		}
		catch (e:Dynamic)
		{
			log('state redirect failed: $shortName -> $target - ' + Std.string(e));
		}
		redirecting = false;
	}

	// ==================== 工具 ====================

	static function buildPack(parent:Dynamic, base:String, allowPlain:Bool):ScriptPack
	{
		var pack:ScriptPack = new ScriptPack(parent);
		for (mod in activeMods())
		{
			var path:String = findLibPath(base, mod, allowPlain);
			if (path != null) pack.addPath(path);
		}
		return pack;
	}

	static function findLibPath(base:String, mod:String, allowPlain:Bool):String
	{
		for (ext in SCRIPT_EXTS)
		{
			var p:String = Paths.mods('$mod/$base/LIB_${mod}${ext}');
			if (sys.FileSystem.exists(p)) return p;
		}
		if (allowPlain)
		{
			for (ext in SCRIPT_EXTS)
			{
				var p:String = Paths.mods('$mod/$base$ext');
				if (sys.FileSystem.exists(p)) return p;
			}
		}
		return null;
	}

	static function activeMods():Array<String>
	{
		if (ClientPrefs.data == null) return [];
		return Mods.parseList().enabled;
	}

	static function modSignature():String
	{
		if (ClientPrefs.data == null) return "";
		return activeMods().join('|');
	}

	static function stateNameOf(state:Dynamic):String
	{
		var cn:String = Type.getClassName(Type.getClass(state));
		if (cn == null) return 'State';
		var shortName:Null<String> = cn.split('.').pop();
		return shortName == null ? 'State' : shortName;
	}
}
#end
