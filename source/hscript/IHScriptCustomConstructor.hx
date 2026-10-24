package hscript;

/**
 * Meteoric: 壳实例的自定义构造接口（移植自 hscript-improved）。
 */
interface IHScriptCustomConstructor {
	public function hnew(args:Array<Dynamic>):Dynamic;
}
