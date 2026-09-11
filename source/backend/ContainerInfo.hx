package backend;

import backend.ContainerManifest;

/**
 * 单个容器的完整描述（界面直接消费）。
 *
 * 独立成模块（而不是挂在 ContainerStore 里面）的原因：Haxe 的模块解析只把
 * **与文件同名的类型** 暴露为顶层模块路径，`backend.ContainerStore.ContainerInfo`
 * 这种“模块内二级类型”在跨文件 import 时会 `Type not found`（编译期实证）。
 * 因此每个需要在别处 import 的类型都必须有自己的文件。
 */
typedef ContainerInfo =
{
	/** 目录名（唯一 ID，持久化用）。 */
	var folder:String;
	/** 容器根目录（绝对路径）。 */
	var path:String;
	/** 显示名。 */
	var displayName:String;
	/** 版本号（可空串）。 */
	var version:String;
	/** 目标引擎标识（可空串）。 */
	var engine:String;
	/** 作者（可空串）。 */
	var author:String;
	/** 描述（可空串）。 */
	var description:String;
	/** 目标引擎主程序绝对路径（可空 = 未就绪）。 */
	var appPath:String;
	/** 解析后的清单（可为 null）。 */
	var manifest:ContainerManifest;
	/** 问题说明（null = 可启动）。 */
	var problem:String;
}
