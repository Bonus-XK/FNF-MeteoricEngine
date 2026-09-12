package psychlua;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
import openfl.utils.Assets;
import backend.ClientPrefs;
import backend.CoolUtil;
import backend.MusicBeatState;
import backend.Paths;
import backend.Mods;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxTimer;
import states.PlayState;
import psychlua.functions.MenuCommands;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * 界面脚本系统（自定义界面端口）：
 * 每个界面可加载 menus/<界面名>.lua，脚本可修改/新增界面文字、读写界面属性、调用界面方法，
 * 并通过 onCreate / onUpdate / onDestroy 等回调参与界面生命周期。
 * 与 FunkinLua（游玩脚本）互相独立，不依赖 PlayState 上下文。
 */
class MenuScript
{
	public var lua:State = null;
	public var scriptName:String = '';
	public var state:Dynamic = null;
	public var closed:Bool = false;
	public var importedScripts:Array<String> = []; // import 导入库系统：已导入库记录
	public var importingScripts:Array<String> = [];
	public var scriptObjects:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	public var scriptTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var scriptTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var scriptSounds:Map<String, FlxSound> = new Map<String, FlxSound>();

	public function new(state:Dynamic, scriptName:String)
	{
		this.state = state;
		this.scriptName = scriptName;

		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		// Lua class 系统（class + 继承）
		LuaClass.register(lua);

		// 基础环境变量
		set('scriptName', scriptName);
		set('stateName', Type.getClassName(Type.getClass(state)));
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);
		set('currentModDirectory', Mods.currentModDirectory);
		set('buildTarget', FunkinLua.getBuildTarget());
		set('version', Main.meVersion);
		set('luaDebugMode', false);

		// ---- 文字与对象定制 API ----		// ==== 阶段 D：界面脚本回调改为注册表模式（psychlua/functions/MenuCommands.hx）====
		MenuCommands.implement(this);

		// 加载并执行脚本文件
		var content:String = getScriptContent(scriptName);
		if(content == null || content.length < 1)
		{
			luaTrace('Failed to load script: ' + scriptName);
			Lua.close(lua);
			lua = null;
			return;
		}

		var status:Int = LuaL.dostring(lua, content);
		if(status != Lua.LUA_OK)
		{
			luaTrace(getErrorMessage(status));
			Lua.close(lua);
			lua = null;
			return;
		}
		trace('UI script loaded successfully: ' + scriptName);

		call('onCreate', []);
	}

	public function call(func:String, args:Array<Dynamic>):Dynamic
	{
		if(closed) return FunkinLua.Function_Continue;

		try
		{
			if(lua == null) return FunkinLua.Function_Continue;

			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);
			if(type != Lua.LUA_TFUNCTION)
			{
				Lua.pop(lua, 1);
				return FunkinLua.Function_Continue;
			}

			if(args == null) args = [];
			for(arg in args) if(!Convert.toLua(lua, arg)) Lua.pushnil(lua); // [Meteoric 修复] 失败补压 nil
			var status:Int = Lua.pcall(lua, args.length, 1, 0);

			if(status != Lua.LUA_OK)
			{
				luaTrace('ERROR (' + func + '): ' + getErrorMessage(status));
				return FunkinLua.Function_Continue;
			}

			var result:Dynamic = cast Convert.fromLua(lua, -1);
			Lua.pop(lua, 1);
			return result;
		}
		catch(e:Dynamic)
		{
			trace(e);
		}
		return FunkinLua.Function_Continue;
	}

	public function set(variable:String, data:Dynamic)
	{
		if(lua == null) return;
		if(!Convert.toLua(lua, data)) Lua.pushnil(lua); // [Meteoric 修复] 失败补压 nil，保持栈平衡
		Lua.setglobal(lua, variable);
	}

	public function update(elapsed:Float)
	{
		// 每帧更新鼠标位置变量，脚本里可直接读 mouseX / mouseY
		set('mouseX', FlxG.mouse.x);
		set('mouseY', FlxG.mouse.y);
		call('onUpdate', [elapsed]);
	}

	public function destroy()
	{
		call('onDestroy', []);
		closed = true;
		if(lua != null)
		{
			Lua.close(lua);
			lua = null;
		}
		for(tween in scriptTweens) tween.cancel();
		scriptTweens = [];
		for(timer in scriptTimers) timer.cancel();
		scriptTimers = [];
		for(sound in scriptSounds) sound.stop();
		scriptSounds = [];
		for(obj in scriptObjects)
		{
			state.remove(obj);
			obj.destroy();
		}
		scriptObjects = [];
	}

	public function getEaseFunction(ease:String):flixel.tweens.EaseFunction
	{
		var fn:Dynamic = Reflect.field(FlxEase, ease);
		if(fn == null)
		{
			luaTrace('Unknown ease "' + ease + '", using linear');
			fn = FlxEase.linear;
		}
		return cast fn;
	}

	public function cancelTweenInternal(name:String):Bool
	{
		if(scriptTweens.exists(name))
		{
			scriptTweens.get(name).cancel();
			scriptTweens.remove(name);
			return true;
		}
		return false;
	}

	public function luaTrace(text:String)
	{
		trace('[UI Script ' + scriptName + '] ' + text);
	}

	// 注册界面脚本专属回调（名字与游玩脚本错开，避免全局回调冲突）
	public function addLocalCallback(name:String, myFunction:Dynamic)
	{
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, myFunction);
	}

	private var callbacks:Map<String, Dynamic> = new Map<String, Dynamic>();

	public function findObject(objName:String):Dynamic
	{
		if(scriptObjects.exists(objName)) return scriptObjects.get(objName);
		return Reflect.field(state, objName);
	}

	function getScriptContent(path:String):String
	{
		#if MODS_ALLOWED
		if(FileSystem.exists(path)) return File.getContent(path);
		#else
		if(Assets.exists(path)) return Assets.getText(path);
		#end
		return null;
	}

	function getErrorMessage(status:Int):String
	{
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);
		if(v != null) v = v.trim();
		if(v == null || v == "")
		{
			switch(status)
			{
				case Lua.LUA_ERRRUN: return "Runtime Error";
				case Lua.LUA_ERRMEM: return "Memory Allocation Error";
				case Lua.LUA_ERRERR: return "Critical Error";
			}
			return "Unknown Error";
		}
		return v;
	}

	/**
	 * 查找界面脚本路径：menus/<name>.lua
	 * 依次查找当前 mod 目录、全局 mods、mods 根目录、preload 资源；也支持绝对路径。
	 */
	public static function findScriptPath(name:String):String
	{
		if(name == null || name.length < 1) return null;
		if(!name.endsWith('.lua')) name += '.lua';

		#if MODS_ALLOWED
		if(name.startsWith('/') && FileSystem.exists(name))
			return name;
		#end

		var file:String = 'menus/' + name;
		var preloadPath:String = Paths.getPreloadPath(file);
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(file);
		if(FileSystem.exists(path)) return path;
		if(FileSystem.exists(preloadPath)) return preloadPath;
		#else
		if(Assets.exists(preloadPath)) return preloadPath;
		#end
		return null;
	}
}
#end
