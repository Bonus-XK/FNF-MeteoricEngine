package backend;

/**
 * 容器清单（`mods/_containers/<容器名>/container.json`）的字段结构。
 *
 * 一类型一文件（Haxe 模块规则）。解析逻辑在 `backend.ContainerManifestParser`。
 */
typedef ContainerManifestData =
{
	/** 主程序：bundle 内相对路径（推荐）、绝对路径，或 .app 目录名。留空则自动探测。 */
	@:optional var app:String;
	/** 显示名（缺省用目录名）。 */
	@:optional var displayName:String;
	/** 版本号（纯展示）。 */
	@:optional var version:String;
	/** 目标引擎标识，如 "psych-0.6.3"（纯展示）。 */
	@:optional var engine:String;
	@:optional var author:String;
	@:optional var description:String;
	/** 资源 staging 清单：{ "dir": "相对容器的源目录", "to": "目标引擎的相对落点" } */
	@:optional var resources:Array<ContainerResourceSpec>;
	/** 退出方式："terminate"（SIGTERM，默认）/ "kill"（SIGKILL） */
	@:optional var exitMode:String;
	/** 挂起宿主进程（SIGSTOP）；默认 true。 */
	@:optional var suspendHost:Bool;
	/** 目标引擎窗口出现前的等待秒数（到点即挂起宿主），默认 1.4。 */
	@:optional var waitSeconds:Float;
	/** 追加给目标引擎的环境变量。 */
	@:optional var env:Dynamic;
	/** 保留字段。 */
	@:optional var extra:Dynamic;
}
