package luagraph;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import backend.Mods;
import backend.Paths;

/**
 * 图/脚本落盘：mods/<当前模组>/scripts/<名字>.lua + <名字>.luagraph.json
 *
 * 安全性：
 *  - 只写当前选中模组的 scripts/ 目录（模组为空时拒绝保存），不碰引擎本体与其它模组；
 *  - 引擎的脚本扫描只认 .lua / .hx（PlayState.create 里逐文件判断），
 *    因此同目录的 .luagraph.json 不会被当成脚本加载；
 *  - 文件名做清洗，拒绝路径分隔符与 ..
 */
class LuaGraphIO
{
	public static inline var GRAPH_EXT:String = '.luagraph.json';

	/** 当前模组的 scripts/ 目录；未选择模组时返回 null。 */
	public static function modScriptsDir():String
	{
		var mod:String = Mods.currentModDirectory;
		if (mod == null || mod.length == 0) return null;
		return Paths.mods(mod + '/scripts/');
	}

	public static function hasTargetMod():Bool
	{
		return modScriptsDir() != null;
	}

	public static function sanitizeFileName(raw:String):String
	{
		var s:String = StringTools.trim(raw);
		if (s.length == 0) return 'graph_script';
		if (StringTools.endsWith(s, '.lua')) s = s.substr(0, s.length - 4);
		if (StringTools.endsWith(s, GRAPH_EXT)) s = s.substr(0, s.length - GRAPH_EXT.length);
		var out:String = '';
		for (i in 0...s.length)
		{
			var ch:String = s.charAt(i);
			if (ch == '/' || ch == '\\' || ch == ':' || ch == '*' || ch == '?' || ch == '"' || ch == '<' || ch == '>' || ch == '|') out += '_';
			else out += ch;
		}
		out = StringTools.trim(out);
		while (out.indexOf('..') >= 0) out = StringTools.replace(out, '..', '_');
		if (out.length == 0) out = 'graph_script';
		return out;
	}

	public static function luaPath(name:String):String
	{
		var dir:String = modScriptsDir();
		return dir == null ? null : dir + name + '.lua';
	}

	public static function jsonPath(name:String):String
	{
		var dir:String = modScriptsDir();
		return dir == null ? null : dir + name + GRAPH_EXT;
	}

	#if sys
	public static function ensureDir():Bool
	{
		var dir:String = modScriptsDir();
		if (dir == null) return false;
		if (!FileSystem.exists(dir))
		{
			try FileSystem.createDirectory(dir) catch (e:Dynamic) return false;
		}
		return FileSystem.exists(dir);
	}

	/** 列出该模组 scripts/ 下全部图形化脚本的基名（不含扩展名）。 */
	public static function listGraphs():Array<String>
	{
		var out:Array<String> = [];
		var dir:String = modScriptsDir();
		if (dir == null || !FileSystem.exists(dir)) return out;
		var files:Array<String> = [];
		try files = FileSystem.readDirectory(dir) catch (e:Dynamic) return out;
		for (f in files)
			if (StringTools.endsWith(f, GRAPH_EXT)) out.push(f.substr(0, f.length - GRAPH_EXT.length));
		out.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	public static function readGraph(name:String):GDoc
	{
		var p:String = jsonPath(name);
		if (p == null) throw '未选择模组';
		if (!FileSystem.exists(p)) throw '图文件不存在：' + p;
		return GDoc.parse(File.getContent(p));
	}

	/** 读取已存在的 .lua（不存在返回 null）。 */
	public static function readLua(name:String):String
	{
		var p:String = luaPath(name);
		if (p == null) return null;
		if (!FileSystem.exists(p)) return null;
		return File.getContent(p);
	}

	public static function existsLua(name:String):Bool
	{
		var p:String = luaPath(name);
		return p != null && FileSystem.exists(p);
	}

	/**
	 * 从已有 .lua 里抽出「自定义代码区」。
	 * 找到标记 → 取标记之后的内容；没有标记（手写脚本）→ 返回 null，由调用方决定是否整体搬进自定义区。
	 */
	public static function extractCustom(luaText:String):String
	{
		if (luaText == null) return null;
		var idx:Int = luaText.indexOf(LuaCodeGen.CUSTOM_BEGIN);
		if (idx < 0) return null;
		var tail:String = luaText.substr(idx + LuaCodeGen.CUSTOM_BEGIN.length);
		if (StringTools.startsWith(tail, '\r\n')) tail = tail.substr(2);
		else if (StringTools.startsWith(tail, '\n')) tail = tail.substr(1);
		return tail.rtrim();
	}

	/** 写盘：.lua 与 .luagraph.json 双写。失败抛异常（由调用方提示）。 */
	public static function saveAll(doc:GDoc, luaText:String):Void
	{
		if (!ensureDir()) throw '无法创建或访问脚本目录（是否已选择模组？）';
		var lp:String = luaPath(doc.name);
		var jp:String = jsonPath(doc.name);
		if (lp == null || jp == null) throw '未选择模组';
		File.saveContent(lp, luaText);
		File.saveContent(jp, doc.toJsonString());
	}
	#end
}
