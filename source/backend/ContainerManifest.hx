package backend;

/**
 * 容器清单结果（`container.json` 解析产物）。
 *
 * 一类型一文件：Haxe 一个文件只有一个顶层类型会提升为模块名，
 * 纯 typedef 文件不提升 —— 所以每个需要被 import 的类型都必须独立成文件（编译期实证）。
 * 解析逻辑见 `backend.ContainerManifestParser`，字段结构见 `backend.ContainerManifestData`。
 */
typedef ContainerManifest =
{
	/** 清单文件是否存在。 */
	var exists:Bool;
	/** 原始解析结果（可能为 null）。 */
	var raw:ContainerManifestData;
	/** 面向玩家的错误说明（null = 无问题）。 */
	var problem:String;
}
