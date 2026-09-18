package luagraph;

import haxe.Json;

/** 脚本级变量（生成到文件顶部的 local 声明）。 */
class GVar
{
	public var name:String;
	public var value:String;

	public function new(name:String, value:String = '0')
	{
		this.name = name;
		this.value = value;
	}

	public function clone():GVar return new GVar(name, value);
	public function toJson():Dynamic return {name: name, value: value};

	public static function fromJson(d:Dynamic):GVar
	{
		return new GVar(JsonModel.str(Reflect.field(d, 'name'), 'var'), JsonModel.str(Reflect.field(d, 'value'), '0'));
	}
}
