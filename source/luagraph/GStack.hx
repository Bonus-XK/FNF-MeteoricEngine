package luagraph;

import haxe.Json;

/** 一条执行栈 = 一个事件帽块 + 其下的积木序列。 */
class GStack
{
	public var event:String;
	public var blocks:Array<GBlock> = [];

	public function new(event:String)
	{
		this.event = event;
	}

	public function clone():GStack
	{
		var s:GStack = new GStack(event);
		for (b in blocks) s.blocks.push(b.clone());
		return s;
	}

	public function toJson():Dynamic
	{
		var b:Array<Dynamic> = [];
		for (c in blocks) b.push(c.toJson());
		return {event: event, blocks: b};
	}

	public static function fromJson(d:Dynamic):GStack
	{
		var ev:String = JsonModel.str(Reflect.field(d, 'event'), 'onCreate');
		var s:GStack = new GStack(ev.length > 0 ? ev : 'onCreate');
		for (c in JsonModel.arr(Reflect.field(d, 'blocks'))) s.blocks.push(GBlock.fromJson(c));
		return s;
	}
}
