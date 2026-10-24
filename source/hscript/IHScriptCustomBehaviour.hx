package hscript;

/**
 * Meteoric: 壳实例的动态字段读写接口（移植自 hscript-improved）。
 * _HSX 壳类 implements 此接口；hget/hset 把字段读写路由到 __interp.variables，
 * 支持 get_xxx / set_xxx 访问器模式。
 */
interface IHScriptCustomBehaviour {
	public function hset(name:String, val:Dynamic):Dynamic;
	public function hget(name:String):Dynamic;
}
