package luagraph;

import flixel.util.FlxColor;
import backend.DesignTokens;

/** 一个参数槽的定义。 */
class PDef
{
	public var name:String;
	public var label:String;
	public var kind:GKind;
	public var def:String;
	public var hint:String;

	public function new(name:String, label:String, kind:GKind, def:String = '', hint:String = '')
	{
		this.name = name;
		this.label = label;
		this.kind = kind;
		this.def = def;
		this.hint = hint;
	}
}
