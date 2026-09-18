package luagraph;

import haxe.Json;

/**
 * 一张图形化脚本图（= 未来的一份 .lua + 一份 .luagraph.json）。
 *
 * 路径约定（编辑器内部用于定位积木）：
 *   blockPath = [栈下标, 积木下标, 分支(0=body/1=elseBody), 积木下标, ...]  —— 偶数长度，最后一项是积木下标
 *   containerPath = blockPath 去掉最后一项（奇数长度），指向"某个序列数组"
 */
class GDoc
{
	public static inline var FORMAT_VERSION:Int = 1;

	public var version:Int = FORMAT_VERSION;
	public var name:String = 'new_script';
	public var mod:String = '';
	public var vars:Array<GVar> = [];
	public var stacks:Array<GStack> = [];
	public var custom:String = '';

	public function new() {}

	// ---------- 统计 ----------
	public function blockCount():Int
	{
		var n:Int = 0;
		for (s in stacks)
			for (b in s.blocks) n += b.count();
		return n;
	}

	public function isEmpty():Bool
	{
		for (s in stacks)
			if (s.blocks.length > 0) return false;
		return true;
	}

	public function findVar(name:String):GVar
	{
		for (v in vars)
			if (v.name == name) return v;
		return null;
	}

	// ---------- 深拷贝 ----------
	public function clone():GDoc
	{
		var d:GDoc = new GDoc();
		d.version = version;
		d.name = name;
		d.mod = mod;
		d.custom = custom;
		for (v in vars) d.vars.push(v.clone());
		for (s in stacks) d.stacks.push(s.clone());
		return d;
	}

	// ---------- 序列化 ----------
	public function toJson():Dynamic
	{
		var vs:Array<Dynamic> = [];
		for (v in vars) vs.push(v.toJson());
		var ss:Array<Dynamic> = [];
		for (s in stacks) ss.push(s.toJson());
		return {version: version, name: name, mod: mod, vars: vs, stacks: ss, custom: custom};
	}

	public function toJsonString():String
	{
		return Json.stringify(toJson(), null, '  ');
	}

	public static function fromJson(d:Dynamic):GDoc
	{
		if (d == null || !Reflect.isObject(d)) throw '图文件不是合法的 JSON 对象';
		var doc:GDoc = new GDoc();
		var ver:Int = JsonModel.int(Reflect.field(d, 'version'), FORMAT_VERSION);
		if (ver > FORMAT_VERSION) throw '图文件版本（' + ver + '）高于当前编辑器支持的版本（' + FORMAT_VERSION + '），请升级引擎后再打开';
		doc.version = ver;
		doc.name = JsonModel.str(Reflect.field(d, 'name'), 'new_script');
		doc.mod = JsonModel.str(Reflect.field(d, 'mod'), '');
		doc.custom = JsonModel.str(Reflect.field(d, 'custom'), '');
		for (v in JsonModel.arr(Reflect.field(d, 'vars'))) doc.vars.push(GVar.fromJson(v));
		for (s in JsonModel.arr(Reflect.field(d, 'stacks'))) doc.stacks.push(GStack.fromJson(s));
		if (doc.stacks.length == 0) doc.stacks.push(new GStack('onCreate'));
		return doc;
	}

	public static function parse(text:String):GDoc
	{
		var d:Dynamic = null;
		try
		{
			d = Json.parse(text);
		}
		catch (e:Dynamic)
		{
			throw '图文件不是合法 JSON：' + Std.string(e);
		}
		return fromJson(d);
	}

	// ---------- 路径工具 ----------
	public static function containerOf(doc:GDoc, containerPath:Array<Int>):Array<GBlock>
	{
		if (containerPath.length == 0 || doc.stacks.length == 0) return [];
		var si:Int = containerPath[0];
		if (si < 0 || si >= doc.stacks.length) return [];
		var arr:Array<GBlock> = doc.stacks[si].blocks;
		var i:Int = 1;
		while (i + 1 < containerPath.length)
		{
			var bi:Int = containerPath[i];
			var br:Int = containerPath[i + 1];
			if (bi < 0 || bi >= arr.length) return [];
			arr = (br == 1) ? arr[bi].elseBody : arr[bi].body;
			i += 2;
		}
		return arr;
	}

	public static function blockAt(doc:GDoc, blockPath:Array<Int>):GBlock
	{
		if (blockPath.length == 0 || blockPath.length % 2 != 0) return null;
		if (doc.stacks.length == 0) return null;
		var si:Int = blockPath[0];
		if (si < 0 || si >= doc.stacks.length) return null;
		var arr:Array<GBlock> = doc.stacks[si].blocks;
		var b:GBlock = null;
		var i:Int = 1;
		while (i < blockPath.length)
		{
			var bi:Int = blockPath[i];
			if (bi < 0 || bi >= arr.length) return null;
			b = arr[bi];
			if (i + 1 < blockPath.length)
			{
				var br:Int = blockPath[i + 1];
				arr = (br == 1) ? b.elseBody : b.body;
			}
			i += 2;
		}
		return b;
	}

	/**
	 * 安全删除：给定 blockPath，从父序列里摘掉。
	 * @return 被摘掉的积木（供"剪切"复用），失败返回 null
	 */
	public static function detach(doc:GDoc, blockPath:Array<Int>):GBlock
	{
		if (blockPath.length < 2 || blockPath.length % 2 != 0) return null;
		var parent:Array<Int> = blockPath.slice(0, blockPath.length - 1);
		var arr:Array<GBlock> = containerOf(doc, parent);
		var idx:Int = blockPath[blockPath.length - 1];
		if (idx < 0 || idx >= arr.length) return null;
		return arr.splice(idx, 1)[0];
	}

	/** 扁平化：按布局顺序列出全部积木的 blockPath（用于键盘上下选择）。 */
	public function flattenPaths():Array<Array<Int>>
	{
		var out:Array<Array<Int>> = [];
		for (si in 0...stacks.length)
			collectPaths(stacks[si].blocks, [si], out);
		return out;
	}

	static function collectPaths(arr:Array<GBlock>, prefix:Array<Int>, out:Array<Array<Int>>):Void
	{
		for (i in 0...arr.length)
		{
			var here:Array<Int> = prefix.concat([i]);
			out.push(here);
			collectPaths(arr[i].body, here.concat([0]), out);
			collectPaths(arr[i].elseBody, here.concat([1]), out);
		}
	}
}
