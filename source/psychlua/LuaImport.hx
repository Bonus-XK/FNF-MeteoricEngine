package psychlua;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import openfl.utils.Assets;
import backend.Paths;
import flixel.util.FlxColor;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * 通用 Lua 导入库系统（import）：
 * 在当前 Lua 状态中执行一次目标库文件，其全局函数/变量立即对调用方脚本可用。
 * 支持相对路径（相对调用方脚本目录）、mods/preload 搜索、防重复导入与循环导入防护。
 * 由 FunkinLua（游玩脚本）与 MenuScript（界面脚本）共用。
 */
class LuaImport
{
	public static function findImportPath(luaFile:String, baseScript:String):String
	{
		var lastSlash:Int = Std.int(Math.max(baseScript.lastIndexOf('/'), baseScript.lastIndexOf('\\')));
		if(lastSlash > 0)
		{
			var relativePath:String = baseScript.substr(0, lastSlash + 1) + luaFile;
			#if MODS_ALLOWED
			if(FileSystem.exists(relativePath))
				return relativePath;
			#else
			if(Assets.exists(relativePath))
				return relativePath;
			#end
		}

		#if MODS_ALLOWED
		if(luaFile.startsWith('/') && FileSystem.exists(luaFile))
			return luaFile;
		#end

		return findScript(luaFile);
	}

	public static function findScript(scriptFile:String, ext:String = '.lua'):String
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

	/**
	 * 执行导入。baseScript 为调用方脚本路径（相对路径解析基准），
	 * importedScripts / importingScripts 分别记录已导入与正在导入的库。
	 * 返回是否成功（已导入/循环导入视为成功，不重复执行）。
	 */
	public static function importLibrary(lua:State, luaFile:String, baseScript:String, importedScripts:Array<String>, importingScripts:Array<String>, ?onError:String->Void = null, ?onSuccess:String->Void = null):Bool
	{
		if(lua == null) return false;

		if(luaFile == null || luaFile.length < 1)
		{
			if(onError != null) onError('import: No file specified!');
			return false;
		}
		if(!luaFile.endsWith('.lua')) luaFile += '.lua';

		var path:String = findImportPath(luaFile, baseScript);
		if(path == null)
		{
			if(onError != null) onError('import: Script "' + luaFile + '" doesn\'t exist!');
			return false;
		}

		// 已导入或正在导入（循环导入）直接返回
		if(importedScripts.contains(path) || importingScripts.contains(path))
			return true;

		var content:String = null;
		#if MODS_ALLOWED
		if(FileSystem.exists(path))
			content = File.getContent(path);
		#else
		if(Assets.exists(path))
			content = Assets.getText(path);
		#end
		if(content == null || content.length < 1)
		{
			if(onError != null) onError('import: Failed to read "' + path + '"!');
			return false;
		}

		importingScripts.push(path);
		var status:Int = LuaL.dostring(lua, content);
		importingScripts.remove(path);

		if(status != Lua.LUA_OK)
		{
			var error:String = Lua.tostring(lua, -1);
			Lua.pop(lua, 1);
			if(error == null || error.length < 1) error = 'Unknown Error';
			if(onError != null) onError('import: Error in "' + path + '": ' + error);
			return false;
		}

		importedScripts.push(path);
		if(onSuccess != null) onSuccess('import: Loaded "' + path + '"');
		return true;
	}
}
#end
