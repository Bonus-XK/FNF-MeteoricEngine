package scripting;

#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
import backend.ClientPrefs;
import backend.Paths;
import objects.Character;
import sys.FileSystem;

/**
 * 资源同名脚本（`scripting/stages|characters|notes|events/`）。
 *
 * 目录约定（全部相对 **启用中的 mod**）：
 * ```
 * mods/<mod>/scripting/stages/<舞台名>.hx       # PlayState.curStage
 * mods/<mod>/scripting/characters/<角色名>.hx   # Character.curCharacter
 * mods/<mod>/scripting/notes/<音符类型>.hx      # 谱面里用到的 noteType
 * mods/<mod>/scripting/events/<事件名>.hx       # 谱面里用到的事件名
 * ```
 *
 * 与 Psych 风格的 `stages/<名>.hx`、`characters/<名>.hx`、
 * `custom_notetypes/<名>.hx`、`custom_events/<名>.hx` 是**两套独立目录**：
 * 两套都放会各加载一次。本机制放在 `scripting/` 下，由 Meteoric 脚本层统一管理。
 *
 * 加载粒度：每个资源名**只加载一次**（不是每个音符/每次事件各加载一次）。
 * 音符数量大，逐实例加载会拖垮进曲；需要逐音符逻辑请用音符类型脚本 + 共享状态。
 *
 * 注入变量：
 *  - 舞台：`stage`（本局第一个舞台实例）；
 *  - 角色：`character`（该角色实例；同名角色只加载一次，指向首个实例）；
 *  - 音符类型：`noteType`（字符串）；
 *  - 事件：`eventName`（字符串）。
 * 其余变量与既有游玩脚本一致（`game` / `dad` / `boyfriend` / `gf` / `camGame` …）。
 *
 * 开关：`ClientPrefs.data.scriptingResourceScripts`（总开关关闭时整体无效）。
 * 回放模式不加载（`initHScript` 的 replayMode 拦截）。
 */
class ResourceScripts
{
	/** 当前是否应加载资源脚本。 */
	public static function enabled():Bool
	{
		return Scripting.isEnabled() && ClientPrefs.data != null && ClientPrefs.data.scriptingResourceScripts;
	}

	/** 加载本局舞台脚本（`scripting/stages/<curStage>.hx`）。 */
	public static function loadStage(ps:PlayState, stageName:String):Void
	{
		if (ps == null || !enabled()) return;
		if (ps.stages == null || ps.stages.length == 0) return;

		var path:String = resolve('stages', stageName);
		if (path == null) return;
		ps.initHScript(path, oneVar('stage', ps.stages[0]));
		trace('[Scripting] resource script loaded: stages/' + stageName);
	}

	/** 加载本局 gf / dad / bf 的角色脚本（按 `curCharacter` 去重）。 */
	public static function loadCharacters(ps:PlayState):Void
	{
		if (ps == null || !enabled()) return;

		var seen:Map<String, Bool> = new Map();
		loadCharacter(ps, ps.gf, seen);
		loadCharacter(ps, ps.dad, seen);
		loadCharacter(ps, ps.boyfriend, seen);
	}

	static function loadCharacter(ps:PlayState, character:Character, seen:Map<String, Bool>):Void
	{
		if (character == null || character.curCharacter == null || character.curCharacter.length == 0) return;
		var name:String = character.curCharacter;
		if (seen.exists(name)) return;
		seen.set(name, true);

		var path:String = resolve('characters', name);
		if (path == null) return;
		ps.initHScript(path, oneVar('character', character));
		trace('[Scripting] resource script loaded: characters/' + name);
	}

	/**
	 * 加载谱面里用到的音符类型 / 事件脚本（每类型一次）。
	 *
	 * `noteTypes` / `eventsPushed` 是 PlayState 的私有字段，由调用方传入
	 * （不为此新增公开访问器）。
	 */
	public static function loadNoteTypesAndEvents(ps:PlayState, noteTypes:Array<String>, eventsPushed:Array<String>):Void
	{
		if (ps == null || !enabled()) return;

		if (noteTypes != null)
		{
			var seenNotes:Map<String, Bool> = new Map();
			for (nt in noteTypes)
			{
				if (nt == null || nt.length == 0 || seenNotes.exists(nt)) continue;
				seenNotes.set(nt, true);
				var path:String = resolve('notes', nt);
				if (path != null)
				{
					ps.initHScript(path, oneVar('noteType', nt));
					trace('[Scripting] resource script loaded: notes/' + nt);
				}
			}
		}

		if (eventsPushed != null)
		{
			var seenEvents:Map<String, Bool> = new Map();
			for (ev in eventsPushed)
			{
				if (ev == null || ev.length == 0 || seenEvents.exists(ev)) continue;
				seenEvents.set(ev, true);
				var path:String = resolve('events', ev);
				if (path != null)
				{
					ps.initHScript(path, oneVar('eventName', ev));
					trace('[Scripting] resource script loaded: events/' + ev);
				}
			}
		}
	}

	/** 解析 `scripting/<kind>/<name>.hx`：按 mod 覆盖顺序取第一个存在的文件。 */
	static function resolve(kind:String, name:String):String
	{
		if (kind == null || name == null || name.length == 0) return null;
		// 资源名来自谱面/角色配置，按文件名使用；拒绝路径分隔符与 .. 防止越界。
		if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf('..') >= 0) return null;

		var path:String = Paths.modFolders('scripting/' + kind + '/' + name + '.hx');
		if (path != null && FileSystem.exists(path)) return path;
		return null;
	}

	/** 单变量注入表（显式 Map<String, Dynamic>，避免 Map 键值类型不变性报错）。 */
	static function oneVar(key:String, value:Dynamic):Map<String, Dynamic>
	{
		var v:Map<String, Dynamic> = new Map();
		v.set(key, value);
		return v;
	}
}
#end
