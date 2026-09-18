package cne;

#if (MODS_ALLOWED && sys && HSCRIPT_ALLOWED)
import backend.Mods;
import backend.Paths;
import flixel.FlxBasic;
import flixel.FlxSprite;
import psychlua.HScript;
import states.PlayState;
import states.stages.CneXmlStage;
import sys.FileSystem;

using StringTools;

/**
 * CNE 歌曲脚本兼容层。
 *
 * 权威依据（CNE 源码 + SMA 实测）：
 *  - CNE 歌曲脚本位置：`songs/<song>/scripts/*.hx`（本 mod 是
 *    `mods/SMA/songs/really-happy/scripts/REALLYFUCKINGJOYOUS.hx`），生命周期回调为
 *    `create()` / `onSongStart()` / `stepHit()` / `beatHit()`。
 *  - Meteoric 已有 HScript（SScript）运行时，回调名是 Psych 的
 *    `onCreate` / `onSongStart` / `onStepHit` / `onBeatHit`（见 `PlayState.stepHit/beatHit`）。
 *    所以本类做两件事：① 注入 CNE 专用 globals；② 把 CNE 回调名 alias 到 Psych 回调名。
 *  - CNE 脚本里用到的对象/函数（SMA 实测）：
 *      `stage.stageSprites["sprite_3"]`、`gf`/`dad`/`boyfriend`、`camGame`/`camHUD`、
 *      `FunkinSprite`、`FlxSprite`、`FlxTween`/`FlxEase`/`FlxColor`/`FlxG`、`Paths.getFrames`、
 *      `Conductor.stepCrochet`、`insert()`。其中角色/相机/基础类已由 `PlayState.initHScript`
 *      注入，本类补 CNE 独有的 `stage` / `FunkinSprite` / `insert`。
 *
 * 只在「CNE 模组兼容」开启时被 `PlayState.create` 调用；关闭时零加载、零开销。
 */
class CneScriptCompat
{
	/** 该曲的 CNE 脚本完整路径（无则空数组）。 */
	public static function songScripts(songDir:String):Array<String>
	{
		var out:Array<String> = [];
		if (!CneModCompat.isEnabled() || songDir == null || songDir.length == 0) return out;

		var mod:String = (Mods.currentModDirectory != null) ? Mods.currentModDirectory : '';
		var dir:String = Paths.mods((mod.length > 0 ? mod + '/' : '') + 'songs/' + songDir + '/scripts');
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return out;

		var files:Array<String> = null;
		try files = FileSystem.readDirectory(dir) catch (e:Dynamic) { files = []; }
		files.sort(function(a:String, b:String):Int return Reflect.compare(a.toLowerCase(), b.toLowerCase()));
		for (f in files)
		{
			if (f == null || !f.toLowerCase().endsWith('.hx')) continue;
			var p:String = dir + '/' + f;
			if (FileSystem.exists(p) && !FileSystem.isDirectory(p)) out.push(p);
		}
		return out;
	}

	/** 注入 CNE 歌曲脚本专用 globals（角色/相机/基础类由 `initHScript` 已注入）。 */
	public static function makeGlobals(playState:PlayState):Map<String, Dynamic>
	{
		var globals:Map<String, Dynamic> = new Map();
		// CNE 的 FunkinSprite：真实子类（含协变 makeGraphic），否则 SScript 类型检查会拒绝
		// `var fadeThing:FunkinSprite = new FunkinSprite().makeGraphic(...)`。
		globals.set('FunkinSprite', cne.FunkinSprite);
		globals.set('stage', makeStageProxy());
		globals.set('insert', function(index:Int, obj:FlxBasic):Void {
			if (playState != null && obj != null) playState.insert(index, obj);
		});
		globals.set('add', function(obj:FlxBasic):Void {
			if (playState != null && obj != null) playState.add(obj);
		});
		globals.set('remove', function(obj:FlxBasic, ?splice:Bool = false):Void {
			if (playState != null && obj != null) playState.remove(obj, splice);
		});
		return globals;
	}

	/** `stage` 代理：CNE 脚本只用到 `stage.stageSprites[名字]`。 */
	static function makeStageProxy():Dynamic
	{
		var sprites:Map<String, FlxSprite> = new Map();
		if (CneXmlStage.current != null && CneXmlStage.current.stageSprites != null)
			sprites = CneXmlStage.current.stageSprites;
		return {stageSprites: sprites};
	}

	/** 把 CNE 回调名 alias 到 Psych 回调名（只在脚本确实定义 CNE 名、且未定义 Psych 名时）。 */
	public static function applyCallbacks(script:HScript):Void
	{
		if (script == null) return;

		if (script.exists('create') && !script.exists('onCreate'))
			script.set('onCreate', function() return callScript(script, 'create', []));
		if (script.exists('createPost') && !script.exists('onCreatePost'))
			script.set('onCreatePost', function() return callScript(script, 'createPost', []));
		// Psych 的 `callOnScripts('onStepHit')` 不传参数，只 `setOnScripts('curStep', ...)`；
		// CNE 的 `stepHit(curStep)` 需要参数，所以这里从脚本变量取 curStep/curBeat。
		if (script.exists('stepHit') && !script.exists('onStepHit'))
			script.set('onStepHit', function(?step:Int):Dynamic {
				var s:Dynamic = (step != null) ? step : script.get('curStep');
				return callScript(script, 'stepHit', [s]);
			});
		if (script.exists('beatHit') && !script.exists('onBeatHit'))
			script.set('onBeatHit', function(?beat:Int):Dynamic {
				var b:Dynamic = (beat != null) ? beat : script.get('curBeat');
				return callScript(script, 'beatHit', [b]);
			});
	}

	/** 调用脚本函数并解包 SScript 的 `ScriptCall`（让 callOnHScript 能拿到真正的返回值/Stop 常量）。 */
	static function callScript(script:HScript, name:String, args:Array<Dynamic>):Dynamic
	{
		var call:Dynamic = script.call(name, args);
		if (call == null) return null;
		var ok:Dynamic = Reflect.field(call, 'succeeded');
		if (ok == true) return Reflect.field(call, 'returnValue');
		#if meteoric_debug
		var ex:Dynamic = Reflect.field(call, 'exceptions');
		trace('[DBG-CNE] ' + name + ' failed: ' + Std.string(ex));
		#end
		return null;
	}

	/** 加载该曲的全部 CNE 歌曲脚本；返回加载数量。 */
	public static function loadSongScripts(playState:PlayState, songDir:String):Int
	{
		if (playState == null) return 0;
		var files:Array<String> = songScripts(songDir);
		if (files.length == 0) return 0;

		var globals:Map<String, Dynamic> = makeGlobals(playState);
		var count:Int = 0;
		for (f in files)
		{
			CneModCompat.log('CNE song script: ' + f);
			playState.initHScript(f, globals, true);
			count++;
		}
		CneModCompat.log('CNE song scripts loaded: ' + count + ' (' + songDir + ')');
		return count;
	}
}
#else
/**
 * 未开启 HSCRIPT_ALLOWED / MODS_ALLOWED 的构建：空壳，保证 `cne.CneScriptCompat` 名字可引用；
 * 真正的调用点也被同样的 `#if` 包住，不会执行到这里。
 */
class CneScriptCompat
{
}
#end
