package luagraph;

import haxe.Json;

/** 一块积木：类型 id + 参数表 + 两个可选子序列（body / elseBody）。 */
class GBlock
{
	public var type:String;
	public var params:Map<String, String> = new Map();
	public var body:Array<GBlock> = [];
	public var elseBody:Array<GBlock> = [];

	public function new(type:String)
	{
		this.type = type;
	}

	public function get(name:String, ?def:String = ''):String
	{
		if (params.exists(name))
		{
			var v:String = params.get(name);
			if (v != null) return v;
		}
		return def == null ? '' : def;
	}

	public function set(name:String, value:String):Void
	{
		params.set(name, value == null ? '' : value);
	}

	public function clone():GBlock
	{
		var b:GBlock = new GBlock(type);
		for (k in params.keys()) b.params.set(k, params.get(k));
		for (c in body) b.body.push(c.clone());
		for (c in elseBody) b.elseBody.push(c.clone());
		return b;
	}

	public function count():Int
	{
		var n:Int = 1;
		for (c in body) n += c.count();
		for (c in elseBody) n += c.count();
		return n;
	}

	public function toJson():Dynamic
	{
		var p:Dynamic = {};
		for (k in params.keys()) Reflect.setField(p, k, params.get(k));
		var b:Array<Dynamic> = [];
		for (c in body) b.push(c.toJson());
		var e:Array<Dynamic> = [];
		for (c in elseBody) e.push(c.toJson());
		return {type: type, params: p, body: b, elseBody: e};
	}

	public static function fromJson(d:Dynamic):GBlock
	{
		var type:String = JsonModel.str(Reflect.field(d, 'type'), '');
		if (type.length == 0) throw '积木数据缺少 type 字段';
		var b:GBlock = new GBlock(type);
		var p:Dynamic = Reflect.field(d, 'params');
		if (p != null && Reflect.isObject(p))
		{
			for (f in Reflect.fields(p))
				b.set(f, JsonModel.str(Reflect.field(p, f), ''));
		}
		for (c in JsonModel.arr(Reflect.field(d, 'body'))) b.body.push(GBlock.fromJson(c));
		for (c in JsonModel.arr(Reflect.field(d, 'elseBody'))) b.elseBody.push(GBlock.fromJson(c));
		return b;
	}
}
