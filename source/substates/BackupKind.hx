package substates;

/**
 * 备份页里一行的交互类型。
 *
 * 独立成文件是因为 Haxe 的 enum / enum abstract 都不能嵌套在类里。
 */
enum BackupKind
{
	/** 勾选项：左右键切换，返回值显示 ☑ / ☐。 */
	TOGGLE;

	/** 动作项：Enter 执行（导出 / 还原）。 */
	ACTION;

	/** 只读信息行：不可交互，仅显示。 */
	INFO;
}