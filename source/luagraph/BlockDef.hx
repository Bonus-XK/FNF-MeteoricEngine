package luagraph;

import flixel.util.FlxColor;
import backend.DesignTokens;

/**
 * 一块积木的定义。
 * lua 模板语法：
 *   {p:参数名} —— 参数替换（KText/KTag 会加引号转义，其余原样）
 *   $BODY$     —— body 子序列（缩进后插入）
 *   $ELSE$     —— elseBody 子序列
 * 全部函数名/参数序均逐条核对自 source/psychlua/functions/*.hx 的 add_callback 注册原文。
 */
class BlockDef
{
	public var id:String;
	public var cat:String;
	public var label:String;
	public var lua:String;
	public var params:Array<PDef>;
	public var hat:Bool = false;
	public var body:Bool = false;
	public var alt:Bool = false;
	public var desc:String = '';

	public function new(id:String, cat:String, label:String, lua:String, params:Array<PDef>, ?hat:Bool = false, ?body:Bool = false, ?alt:Bool = false, ?desc:String = '')
	{
		this.id = id;
		this.cat = cat;
		this.label = label;
		this.lua = lua;
		this.params = params == null ? [] : params;
		this.hat = hat;
		this.body = body;
		this.alt = alt;
		this.desc = desc == null ? '' : desc;
	}

	public function param(name:String):PDef
	{
		for (p in params)
			if (p.name == name) return p;
		return null;
	}

	/** 参数默认值（用于新建积木时填槽）。 */
	public function defaultParams():Map<String, String>
	{
		var m:Map<String, String> = new Map();
		for (p in params) m.set(p.name, p.def);
		return m;
	}
}
