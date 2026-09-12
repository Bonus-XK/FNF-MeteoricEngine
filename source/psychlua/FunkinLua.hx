package psychlua;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import openfl.Lib;
import openfl.utils.Assets;
import openfl.display.BitmapData;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.addons.transition.FlxTransitionableState;

#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import cutscenes.DialogueBoxPsych;

import objects.StrumNote;
import objects.Note;
import objects.NoteSplash;
import objects.Character;

import states.MainMenuState;
import states.StoryMenuState;
import states.FreeplayState;

import substates.PauseSubState;
import substates.GameOverSubstate;

import psychlua.LuaUtils;
import psychlua.LuaUtils.LuaTweenOptions;
import psychlua.functions.ScriptGlobals;
import psychlua.functions.ScriptCommands;
import psychlua.functions.ScriptTweens;
import psychlua.functions.NoteTweens;
import psychlua.functions.ObjectCommands;
import psychlua.functions.CharacterCommands;
import psychlua.functions.CameraCommands;
import psychlua.functions.ScoreCommands;
import psychlua.functions.PlayCommands;
import psychlua.functions.DialogueCommands;
import psychlua.functions.SoundCommands;
import psychlua.functions.MiscCommands;
#if (HSCRIPT_ALLOWED && SScript >= "3.0.0")
import psychlua.HScript;
#end
import psychlua.DebugLuaText;
import psychlua.ModchartSprite;

class FunkinLua {
	public static var Function_Stop:Dynamic = "##PSYCHLUA_FUNCTIONSTOP";
	public static var Function_Continue:Dynamic = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static var Function_StopLua:Dynamic = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static var Function_StopHScript:Dynamic = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static var Function_StopAll:Dynamic = "##PSYCHLUA_FUNCTIONSTOPALL";

	#if LUA_ALLOWED
	public var lua:State = null;
	#end
	public var camTarget:FlxCamera;
	public var scriptName:String = '';
	public var closed:Bool = false;
	// import 导入库系统：记录已导入/正在导入的库路径（防重复执行与循环导入）
	public var importedScripts:Array<String> = [];
	private var importingScripts:Array<String> = [];

	#if (HSCRIPT_ALLOWED && SScript >= "3.0.0")
	public var hscript:HScript = null;
	#end
	
	public var callbacks:Map<String, Dynamic> = new Map<String, Dynamic>();
	public static var customFunctions:Map<String, Dynamic> = new Map<String, Dynamic>();

	public function new(scriptName:String) {
		#if LUA_ALLOWED
		// 回放模式：仅放行舞台脚本（背景显示需要），其余脚本不加载
		// （避免脚本修改 note/strum 的显示 alpha/visible/坐标/颜色等导致回放箭头异常）
		if (PlayState.instance != null && PlayState.instance.replayMode
			&& (scriptName == null || scriptName.indexOf('/stages/') == -1))
			return;

		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		// Lua class 系统（class + 继承）
		LuaClass.register(lua);

		//trace('Lua version: ' + Lua.version());
		//trace("LuaJIT version: " + Lua.versionJIT());

		//LuaL.dostring(lua, CLENSE);

		this.scriptName = scriptName;
		var game:PlayState = PlayState.instance;
		game.luaArray.push(this);

		// 全局变量初始化（阶段 A 拆分：psychlua/functions/ScriptGlobals.hx）
		ScriptGlobals.implement(this);


		// 由 HScript.hx 等注入的自定义回调统一注册
		for (name => func in customFunctions)
		{
			if(func != null)
				Lua_helper.add_callback(lua, name, func);
		}

		#if desktop DiscordClient.addLuaCallbacks(lua); #end
		#if (HSCRIPT_ALLOWED && SScript >= "3.0.0") HScript.implement(this); #end

		// ==== 阶段 A 功能域模块（注册顺序 = 拆分前源码顺序，保证同名回调覆盖语义一致）====
		ScriptCommands.implement(this);      // 脚本生命周期 / 跨脚本通信 / 图形帧加载
		ScriptTweens.implement(this);        // 通用 tween
		NoteTweens.implement(this);          // 音符 / 轨道 tween
		ObjectCommands.implement(this);      // 舞台对象：sprite、层级、动画、位置尺寸
		CharacterCommands.implement(this);   // 角色 / 预加载
		CameraCommands.implement(this);      // 摄像机
		ScoreCommands.implement(this);       // 分数 / 命中 / 血量 / 评级 / 条颜色
		PlayCommands.implement(this);        // 歌曲流程 / 事件 / 指针坐标
		DialogueCommands.implement(this);    // 对话 / 视频
		SoundCommands.implement(this);       // 声音
		MiscCommands.implement(this);        // 颜色工具 / 输入探测 / 定时器 / 调试 / 本脚本控制

		// ==== 与拆分前同序的既有模块 ====
		ReflectionFunctions.implement(this);
		#if flxanimate FlxAnimateFunctions.implement(this); #end
		TextFunctions.implement(this);
		ExtraFunctions.implement(this);
		CustomSubstate.implement(this);
		ShaderFunctions.implement(this);
		DeprecatedFunctions.implement(this);

		try{
			var result:Dynamic = LuaL.dofile(lua, scriptName);
			var resultStr:String = Lua.tostring(lua, result);
			if(resultStr != null && result != 0) {
				trace(resultStr);
				#if windows
				lime.app.Application.current.window.alert(resultStr, 'Error on lua script!');
				#else
				luaTrace('$scriptName\n$resultStr', true, false, FlxColor.RED);
				#end
				lua = null;
				return;
			}
		} catch(e:Dynamic) {
			trace(e);
			return;
		}
		trace('lua file loaded succesfully:' + scriptName);

		call('onCreate', []);
		#end
	}

	//main
	public var lastCalledFunction:String = '';
	public static var lastCalledScript:FunkinLua = null;

	// LuaJIT 嵌套 pcall 防护（Meteoric Fix 续）：
	// lldb 实测栈——外层 Lua 回调执行中，Haxe 侧再次 callOnScripts → 嵌套 lua_pcall
	// → lj_state_growstack → lj_alloc_realloc 堆损坏 → SIGSEGV（blissful-erect 命中瞬间）。
	// Lua 回调执行期间的一切 Lua 再入调用直接跳过（返回 Function_Continue），消除嵌套 pcall。
	public static var luaCallDepth:Int = 0;

	public function call(func:String, args:Array<Dynamic>):Dynamic {
		#if LUA_ALLOWED
		if(closed) return Function_Continue;
		if (luaCallDepth > 0) return Function_Continue; // 重入防护：跳过嵌套调用

		luaCallDepth++;
		var callResult:Dynamic = Function_Continue;
		lastCalledFunction = func;
		lastCalledScript = this;
		try {
			if(lua != null)
			{
				Lua.getglobal(lua, func);
				var type:Int = Lua.type(lua, -1);

				if (type != Lua.LUA_TFUNCTION) {
					if (type > Lua.LUA_TNIL)
						luaTrace("ERROR (" + func + "): attempt to call a " + LuaUtils.typeToString(type) + " value", false, false, FlxColor.RED);

					Lua.pop(lua, 1);
				}
				else
				{
					for (arg in args) if(!Convert.toLua(lua, arg)) Lua.pushnil(lua); // [Meteoric 修复] 失败补压 nil，保持 pcall 实参数量一致
					var status:Int = Lua.pcall(lua, args.length, 1, 0);

					// Checks if it's not successful, then show a error.
					if (status != Lua.LUA_OK) {
						var error:String = getErrorMessage(status);
						luaTrace("ERROR (" + func + "): " + error, false, false, FlxColor.RED);
					}
					else
					{
						// If successful, pass and then return the result.
						var result:Dynamic = cast Convert.fromLua(lua, -1);
						if (result == null) result = Function_Continue;
						callResult = result;

						Lua.pop(lua, 1);
						if(closed) stop();
					}
				}
			}
		}
		catch (e:Dynamic) {
			trace(e);
		}
		luaCallDepth--;
		return callResult;
		#end
		return Function_Continue;
	}
	
	public function set(variable:String, data:Dynamic) {
		#if LUA_ALLOWED
		if(lua == null) {
			return;
		}

		// [Meteoric 修复] 不支持的类型经 Convert.toLua 失败时不压栈：
		// 必须补压 nil，否则 setglobal 会弹掉栈上的错误槽位（栈下溢 → LuaJIT 堆损坏）
		if(!Convert.toLua(lua, data)) Lua.pushnil(lua);
		Lua.setglobal(lua, variable);
		#end
	}

	public function stop() {
		#if LUA_ALLOWED
		PlayState.instance.luaArray.remove(this);
		closed = true;

		if(lua == null) {
			return;
		}
		Lua.close(lua);
		lua = null;
		#if (HSCRIPT_ALLOWED && SScript >= "3.0.0")
		if(hscript != null)
		{
			hscript.active = false;
			#if (SScript >= "3.0.3")
			hscript.destroy();
			#end
			hscript = null;
		}
		#end
		#end
	}

	//clone functions
	public static function getBuildTarget():String
	{
		#if windows
		return 'windows';
		#elseif linux
		return 'linux';
		#elseif mac
		return 'mac';
		#elseif html5
		return 'browser';
		#elseif android
		return 'android';
		#elseif switch
		return 'switch';
		#else
		return 'unknown';
		#end
	}

	
	public static function luaTrace(text:String, ignoreCheck:Bool = false, deprecated:Bool = false, color:FlxColor = FlxColor.WHITE) {
		#if LUA_ALLOWED
		if(ignoreCheck || getBool('luaDebugMode')) {
			if(deprecated && !getBool('luaDeprecatedWarnings')) {
				return;
			}
			PlayState.instance.addTextToDebug(text, color);
			trace(text);
		}
		#end
	}
	
	#if LUA_ALLOWED
	public static function getBool(variable:String) {
		if(lastCalledScript == null) return false;

		var lua:State = lastCalledScript.lua;
		if(lua == null) return false;

		var result:String = null;
		Lua.getglobal(lua, variable);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);

		if(result == null) {
			return false;
		}
		return (result == 'true');
	}
	#end

	// 阶段 A：psychlua.functions.* 功能域模块需要调用，故提升为 public
	public function findScript(scriptFile:String, ext:String = '.lua')
	{
		if(!scriptFile.endsWith(ext)) scriptFile += ext;
		var preloadPath:String = Paths.getPreloadPath(scriptFile);
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(scriptFile))
			return scriptFile;
		else if(FileSystem.exists(path))
			return path;
	
		if(FileSystem.exists(preloadPath))
		#else
		if(Assets.exists(preloadPath))
		#end
		{
			return preloadPath;
		}
		return null;
	}

	// 解析 import 的路径：先相对当前导入基准（主脚本或正在导入的库）目录，再走 mods/preload 搜索
	function findImportPath(luaFile:String):String
	{
		#if LUA_ALLOWED
		var baseScript:String = scriptName;
		if(importingScripts.length > 0)
			baseScript = importingScripts[importingScripts.length - 1];
		return LuaImport.findImportPath(luaFile, baseScript);
		#else
		return null;
		#end
	}

	// import 导入库：在当前 Lua 状态中执行一次目标文件，库内定义的全局函数/变量
	// 直接对调用方脚本可用；重复导入与循环导入会自动跳过，不会重复执行
	public function importLibrary(luaFile:String):Bool
	{
		#if LUA_ALLOWED
		if(lua == null || closed) return false;

		var baseScript:String = scriptName;
		if(importingScripts.length > 0)
			baseScript = importingScripts[importingScripts.length - 1];

		return LuaImport.importLibrary(lua, luaFile, baseScript, importedScripts, importingScripts,
			function(msg) luaTrace(msg, true, false, FlxColor.RED),
			function(msg) luaTrace(msg));
		#else
		return false;
		#end
	}

	public function getErrorMessage(status:Int):String {
		#if LUA_ALLOWED
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);

		if (v != null) v = v.trim();
		if (v == null || v == "") {
			switch(status) {
				case Lua.LUA_ERRRUN: return "Runtime Error";
				case Lua.LUA_ERRMEM: return "Memory Allocation Error";
				case Lua.LUA_ERRERR: return "Critical Error";
			}
			return "Unknown Error";
		}

		return v;
		#end
		return null;
	}

	public function addLocalCallback(name:String, myFunction:Dynamic)
	{
		#if LUA_ALLOWED
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, null); //just so that it gets called
		#end
	}
	
	#if (MODS_ALLOWED && !flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end
	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		backend.CrashHandler.logEvent('Lua-shader init: ' + name);
		if(runtimeShaders.exists(name))
		{
			luaTrace('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));

		for(mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));
		
		for (folder in foldersToCheck)
		{
			if(FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if(FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else frag = null;

				if(FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else vert = null;

				if(found)
				{
					runtimeShaders.set(name, [frag, vert]);
					//trace('Found shader $name!');
					return true;
				}
			}
		}
		luaTrace('Missing shader $name .frag AND .vert files!', false, false, FlxColor.RED);
		#else
		luaTrace('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}
}
