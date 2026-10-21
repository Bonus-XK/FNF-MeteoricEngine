package scripting;

import backend.ClientPrefs;
import backend.Mods;
import backend.Paths;
import flixel.FlxG;
import flixel.input.FlxInput.FlxInputState;
import flixel.input.keyboard.FlxKey;
import psychlua.HScript;
import sys.FileSystem;

#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
/**
 * Meteoric 脚本系统（编程层）总入口。
 *
 * 目标：让 mod 作者**不碰引擎源码**也能改玩法 / 界面 —— 用 HScript 写脚本，
 * 改一行按 F5 即生效，不必重开游戏。
 *
 * ## 脚本放哪（mod 内）
 *
 * ```
 * mods/<mod>/scripting/global/ 下的 .hx    全局常驻脚本（跨所有界面）
 * mods/<mod>/scripting/states/<名字>.hx    状态脚本（覆盖某个 State / SubState）
 * ```
 *
 * 状态脚本的文件名 = 目标界面的类名短名（`MainMenuState` / `PauseSubState` …）。
 *
 * ## 脚本能拿到什么
 *
 * - `psychlua.HScript` 的 187 个预设全局（引擎类：`PlayState` `Paths` `FlxSprite` `Character` …、
 *   Flixel 类、`sys` 文件系统、`Reflect` / `Type` 反射）—— 与既有 mods 脚本同一套 API。
 * - 额外注入：`state`（当前 State）、`game`（PlayState 实例）、`scripting`（本层入口）。
 *
 * ## 回调
 *
 * - 生命周期：`create()` / `update(elapsed)` / `postUpdate(elapsed)` / `beatHit(beat)` /
 *   `stepHit(step)` / `destroy()`。
 * - 引擎级（仅全局脚本）：`preUpdate` / `postUpdate` / `preStateSwitch` / `postStateSwitch` /
 *   `preDraw` / `postDraw` / `focusGained` / `focusLost` / `gameResized(w,h)` /
 *   `preGameStart` / `postGameStart`。
 *
 * ## 设计纪律（勿破）
 *
 *  - 总开关 `ClientPrefs.data.scriptingEnabled` 关闭时，下面每个入口都**立即 return**，
 *    引擎行为与本层落地前逐字节一致（零行为变化）。
 *  - 热重载是「**原地重建脚本组**」，不是 `FlxG.resetState()`：宿主 state 与它的视觉对象
 *    都不重建。旧脚本先收 `destroy` 回调，新脚本再收 `create` —— 所以脚本必须在 `destroy`
 *    里清理自己创建的对象。
 *  - 新脚本组**先构建、成功才替换旧组**；构建失败（文件被删 / 全部解析失败）保留旧组并打日志，
 *    避免一次写错文件就让整个界面的脚本消失。
 *  - 与既有 `mods/<mod>/scripts/` 下的 `.lua` / `.hx`（Psych 风格游玩脚本）是**两条独立的线**：
 *    本层只读 `mods/<mod>/scripting/` 下的脚本，绝不重复加载旧脚本。
 */
class Scripting
{
	/** 是否已经注册过引擎信号（只注册一次）。 */
	public static var initialized:Bool = false;

	/** 全局常驻脚本组（跨界面存活）。未开启时为 null。 */
	public static var globalGroup:ScriptGroup = null;

	/** 上一次绑定宿主变量时的 State（变了才重绑，避免每帧写变量表）。 */
	static var lastBoundState:Dynamic = null;

	// ==================== 开关 ====================

	/** 总开关：编程层总闸。 */
	public static function isEnabled():Bool
	{
		return ClientPrefs.data != null && ClientPrefs.data.scriptingEnabled;
	}

	/** 全局常驻脚本。 */
	public static function globalScriptsEnabled():Bool
	{
		return isEnabled() && ClientPrefs.data != null && ClientPrefs.data.scriptingGlobalScripts;
	}

	/** 状态脚本（覆盖某个 State / SubState）。 */
	public static function stateScriptsEnabled():Bool
	{
		return isEnabled() && ClientPrefs.data != null && ClientPrefs.data.scriptingStateScripts;
	}

	/** 热重载（F5 / Shift+F5）。 */
	public static function hotReloadEnabled():Bool
	{
		return isEnabled() && ClientPrefs.data != null && ClientPrefs.data.scriptingHotReload;
	}

	/** 事件层（可取消事件）。 */
	public static function eventsEnabled():Bool
	{
		return isEnabled() && ClientPrefs.data != null && ClientPrefs.data.scriptingEvents;
	}

	// ==================== 生命周期 ====================

	/**
	 * 启动编程层：注册引擎级信号 + 装载全局脚本。
	 * 由 TitleState.create 调用（此时存档已加载）。
	 */
	public static function init():Void
	{
		if (initialized) return;
		initialized = true;

		FlxG.signals.preUpdate.add(onPreUpdate);
		FlxG.signals.postUpdate.add(onPostUpdate);
		FlxG.signals.preStateSwitch.add(onPreStateSwitch);
		FlxG.signals.postStateSwitch.add(onPostStateSwitch);
		FlxG.signals.preDraw.add(onPreDraw);
		FlxG.signals.postDraw.add(onPostDraw);
		FlxG.signals.focusGained.add(onFocusGained);
		FlxG.signals.focusLost.add(onFocusLost);
		FlxG.signals.gameResized.add(onGameResized);
		FlxG.signals.preGameStart.add(onPreGameStart);
		FlxG.signals.postGameStart.add(onPostGameStart);

		reloadGlobalScripts();

		// 补装载当前界面的状态脚本：
		// MusicBeatState.create() 里已经调过一次 onStateCreate，但那一刻存档还没加载
		//（TitleState 是先 super.create() 才 loadPrefs），开关读不到 → 那次是空转。
		var st = FlxG.state;
		if (st != null && Std.isOfType(st, MusicBeatState)) onStateCreate(cast st);

		log('编程层已启动');
	}

	// ===== 状态脚本 =====

	/** 状态创建：装载该 State 的状态脚本。 */
	public static function onStateCreate(state:MusicBeatState):Void
	{
		if (!stateScriptsEnabled()) return;
		if (state == null) return;
		if (state.scriptingGroup != null) return;

		var group:ScriptGroup = buildStateGroup(state, stateNameOf(state));
		if (group != null && group.hasScripts())
		{
			state.scriptingGroup = group;
			group.bindVars();
			group.call('create');
			log('状态脚本已装载：' + stateNameOf(state) + '（' + group.scripts.length + ' 个）');
		}
		else if (group != null)
		{
			group.destroy();
		}
	}

	/** 子状态创建：装载该 SubState 的状态脚本。 */
	public static function onSubStateCreate(state:MusicBeatSubstate):Void
	{
		if (!stateScriptsEnabled()) return;
		if (state == null) return;
		if (state.scriptingGroup != null) return;

		var group:ScriptGroup = buildStateGroup(state, stateNameOf(state));
		if (group != null && group.hasScripts())
		{
			state.scriptingGroup = group;
			group.bindVars();
			group.call('create');
			log('子状态脚本已装载：' + stateNameOf(state) + '（' + group.scripts.length + ' 个）');
		}
		else if (group != null)
		{
			group.destroy();
		}
	}

	/** 状态每帧更新。 */
	public static function onStateUpdate(state:MusicBeatState, elapsed:Float):Void
	{
		if (!stateScriptsEnabled()) return;
		if (state == null || state.scriptingGroup == null) return;
		state.scriptingGroup.call('update', [elapsed]);
	}

	/** 子状态每帧更新。 */
	public static function onSubStateUpdate(state:MusicBeatSubstate, elapsed:Float):Void
	{
		if (!stateScriptsEnabled()) return;
		if (state == null || state.scriptingGroup == null) return;
		state.scriptingGroup.call('update', [elapsed]);
	}

	/** 状态销毁：脚本收 destroy 回调。 */
	public static function onStateDestroy(state:MusicBeatState):Void
	{
		if (state == null || state.scriptingGroup == null) return;
		state.scriptingGroup.destroy();
		state.scriptingGroup = null;
	}

	/** 子状态销毁：脚本收 destroy 回调。 */
	public static function onSubStateDestroy(state:MusicBeatSubstate):Void
	{
		if (state == null || state.scriptingGroup == null) return;
		state.scriptingGroup.destroy();
		state.scriptingGroup = null;
	}

	/** 步进（全局脚本 + 状态脚本都收 stepHit）。 */
	public static function onStepHit(step:Int):Void
	{
		if (!isEnabled()) return;
		if (globalGroup != null) globalGroup.call('stepHit', [step]);
		var state:MusicBeatState = currentState();
		if (state != null && state.scriptingGroup != null) state.scriptingGroup.call('stepHit', [step]);
	}

	/** 节拍（全局脚本 + 状态脚本都收 beatHit）。 */
	public static function onBeatHit(beat:Int):Void
	{
		if (!isEnabled()) return;
		if (globalGroup != null) globalGroup.call('beatHit', [beat]);
		var state:MusicBeatState = currentState();
		if (state != null && state.scriptingGroup != null) state.scriptingGroup.call('beatHit', [beat]);
	}

	// ==================== 引擎级信号 ====================

	static function onPreUpdate():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('preUpdate', [FlxG.elapsed]);
	}

	static function onPostUpdate():Void
	{
		if (!isEnabled()) return;

		// State 换了才重绑宿主变量（每帧写变量表没必要）。
		if (globalGroup != null && lastBoundState != FlxG.state)
		{
			lastBoundState = FlxG.state;
			globalGroup.bindVars();
		}

		if (globalGroup != null)
		{
			globalGroup.call('update', [FlxG.elapsed]);
			globalGroup.call('postUpdate', [FlxG.elapsed]);
		}

		// 热重载放在 postUpdate：preUpdate 在 updateInput() **之前**派发，
		// 那一刻 FlxG.keys 还是上一帧的陈旧值（见 source/flixel/FlxGame.hx 的 update 顺序）。
		if (hotReloadEnabled()) checkHotReload();
	}

	static function onPreStateSwitch():Void
	{
		if (!isEnabled()) return;

		// 状态脚本也收 preStateSwitch：此时它属于**即将被销毁的旧界面**，组还在。
		var old:MusicBeatState = currentState();
		var stateTarget:Dynamic = null;
		if (old != null && old.scriptingGroup != null) stateTarget = old.scriptingGroup.callResult('preStateSwitch', []);

		if (globalGroup == null) return;
		var target:Dynamic = globalGroup.callResult('preStateSwitch', []);
		if (target == null) target = stateTarget;
		if (target == null) return;
		redirectState(target);
	}

	/**
	 * 改写本次界面跳转的目标。
	 *
	 * 脚本在 `preStateSwitch` 里 **return 一个界面名** 即可改跳转目标：
	 *  - `'MainMenuState'` → 引擎内建界面（按 `states.<名>` 解析）；
	 *  - `'options.OptionsState'` → 带包名的完整类名；
	 *  - 解析不到 → 打日志并保持原目标（不改变引擎行为）。
	 */
	static function redirectState(target:Dynamic):Void
	{
		if (target == null) return;
		var name:String = Std.string(target).trim();
		if (name.length == 0) return;

		var cls:Dynamic = Type.resolveClass(name);
		if (cls == null) cls = Type.resolveClass('states.' + name);
		if (cls == null)
		{
			logError('状态跳转失败：找不到界面类 ' + name);
			return;
		}
		try
		{
			@:privateAccess FlxG.game._requestedState = Type.createInstance(cls, []);
			log('状态跳转：已改写目标为 ' + name);
		}
		catch (e:Dynamic)
		{
			logError('状态跳转失败：' + name + ' —— ' + Std.string(e));
		}
	}

	static function onPostStateSwitch():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('postStateSwitch', []);
	}

	static function onPreDraw():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('preDraw', []);
	}

	static function onPostDraw():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('postDraw', []);
	}

	static function onFocusGained():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('focusGained', []);
	}

	static function onFocusLost():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('focusLost', []);
	}

	static function onGameResized(width:Int, height:Int):Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('gameResized', [width, height]);
	}

	static function onPreGameStart():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('preGameStart', []);
	}

	static function onPostGameStart():Void
	{
		if (!isEnabled() || globalGroup == null) return;
		globalGroup.call('postGameStart', []);
	}

	// ==================== 热重载 ====================

	/**
	 * F5 = 重建**当前界面**的状态脚本组；Shift+F5 = 重建**全局**脚本组。
	 *
	 * 重建是「先构建新组、成功才替换旧组」：构建失败保留旧组，
	 * 避免一次写错文件就让整个界面的脚本消失。
	 */
	static function checkHotReload():Void
	{
		if (FlxG.keys == null) return;
		if (!FlxG.keys.checkStatus(FlxKey.F5, FlxInputState.JUST_PRESSED)) return;

		if (FlxG.keys.checkStatus(FlxKey.SHIFT, FlxInputState.PRESSED))
		{
			reloadGlobalScripts();
		}
		else
		{
			reloadCurrentStateScripts();
		}
	}

	/** 重建全局脚本组。 */
	public static function reloadGlobalScripts():Void
	{
		if (!globalScriptsEnabled()) return;

		var next:ScriptGroup = buildGlobalGroup();
		if (next == null || !next.hasScripts())
		{
			// 没有可用脚本：保留旧组（可能是文件被删了，也可能是本来就一个都没有）。
			if (next != null) next.destroy();
			if (globalGroup != null) log('全局脚本重载：无脚本，保留旧组');
			return;
		}

		var old:ScriptGroup = globalGroup;
		globalGroup = next;
		lastBoundState = FlxG.state;
		next.bindVars();
		next.call('create');
		if (old != null) old.destroy();
		log('全局脚本已重载（' + next.scripts.length + ' 个）');
	}

	/** 重建当前界面的状态脚本组。 */
	public static function reloadCurrentStateScripts():Void
	{
		if (!stateScriptsEnabled()) return;

		var state:MusicBeatState = currentState();
		if (state == null || state.scriptingGroup == null)
		{
			log('状态脚本重载：当前界面没有状态脚本');
			return;
		}

		var next:ScriptGroup = buildStateGroup(state, stateNameOf(state));
		if (next == null || !next.hasScripts())
		{
			if (next != null) next.destroy();
			log('状态脚本重载：无脚本，保留旧组');
			return;
		}

		var old:ScriptGroup = state.scriptingGroup;
		state.scriptingGroup = next;
		next.bindVars();
		next.call('create');
		if (old != null) old.destroy();
		log('状态脚本已重载：' + stateNameOf(state));
	}

	// ==================== 事件层 ====================

	/**
	 * 派发一个可取消事件给全局脚本与当前状态脚本。
	 *
	 * @return true = 事件被某个脚本取消（引擎应跳过默认行为）；false = 未取消。
	 */
	public static function dispatch(eventName:String, event:ScriptEvent):Bool
	{
		if (!eventsEnabled()) return false;
		if (event == null) return false;

		if (globalGroup != null) dispatchToGroup(globalGroup, eventName, event);
		var state:MusicBeatState = currentState();
		if (state != null && state.scriptingGroup != null) dispatchToGroup(state.scriptingGroup, eventName, event);

		return event.cancelled;
	}

	static function dispatchToGroup(group:ScriptGroup, eventName:String, event:ScriptEvent):Void
	{
		for (script in group.scripts)
		{
			if (script == null || !script.active) continue;
			if (event.cancelled && !event.continueCalls) return;
			var fn:Dynamic = script.get(eventName);
			if (fn == null || !Reflect.isFunction(fn)) continue;
			try
			{
				var result = script.call(eventName, [event]);
				if (result != null && !result.succeeded && result.exceptions != null && result.exceptions.length > 0)
					logError(eventName + ' 出错：' + ScriptGroup.firstLine(result.exceptions[0]));
			}
			catch (e:Dynamic)
			{
				logError(eventName + ' 抛出异常：' + Std.string(e));
			}
		}
	}

	// ==================== 构建 ====================

	/** 构建全局脚本组：各启用 mod 的 `scripting/global/` 目录下的 .hx。 */
	static function buildGlobalGroup():ScriptGroup
	{
		var group:ScriptGroup = new ScriptGroup(null);
		for (mod in activeMods())
		{
			var dir:String = Paths.mods(mod + '/scripting/global');
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) continue;
			var files:Array<String> = null;
			try files = FileSystem.readDirectory(dir) catch (e:Dynamic) files = [];
			if (files == null) continue;
			files.sort(function(a:String, b:String):Int return Reflect.compare(a.toLowerCase(), b.toLowerCase()));
			for (f in files)
			{
				if (f == null || !f.toLowerCase().endsWith('.hx')) continue;
				group.addPath(dir + '/' + f);
			}
		}
		return group;
	}

	/** 构建状态脚本组：各启用 mod 的 `scripting/states/<名字>.hx`。 */
	static function buildStateGroup(host:Dynamic, shortName:String):ScriptGroup
	{
		if (shortName == null || shortName.length == 0) return null;
		var group:ScriptGroup = new ScriptGroup(host);
		for (mod in activeMods())
		{
			var path:String = Paths.mods(mod + '/scripting/states/' + shortName + '.hx');
			group.addPath(path);
		}
		return group;
	}

	/** 当前启用中的 mod 目录名列表。 */
	static function activeMods():Array<String>
	{
		if (ClientPrefs.data == null) return [];
		try
		{
			return Mods.parseList().enabled;
		}
		catch (e:Dynamic)
		{
			return [];
		}
	}

	/** 当前 State（若是 MusicBeatState）。 */
	static function currentState():MusicBeatState
	{
		var s = FlxG.state;
		if (s == null) return null;
		return Std.isOfType(s, MusicBeatState) ? cast s : null;
	}

	/** 类名短名（`states.MainMenuState` → `MainMenuState`）。 */
	static function stateNameOf(state:Dynamic):String
	{
		if (state == null) return null;
		var cn:String = Type.getClassName(Type.getClass(state));
		if (cn == null) return null;
		var short:Null<String> = cn.split('.').pop();
		return short;
	}

	// ==================== 日志 ====================

	/** 普通日志（终端可见）。 */
	public static function log(msg:String):Void
	{
		Sys.println('[Scripting] ' + msg);
	}

	/** 错误日志（终端可见）。 */
	public static function logError(msg:String):Void
	{
		Sys.println('[Scripting][错误] ' + msg);
	}
}
#end
