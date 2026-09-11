package backend;

/**
 * 单条资源 staging 规则（`container.json` 的 `resources` 数组元素）。
 *
 * 一类型一文件（Haxe 模块规则）。
 */
typedef ContainerResourceSpec =
{
	/** 相对容器根目录的源路径。 */
	var dir:String;
	/** 目标引擎资源根下的落点（缺省与 dir 同名）。 */
	@:optional var to:String;
	/** true = 只复制单个文件而不是整目录。 */
	@:optional var file:Bool;
}
