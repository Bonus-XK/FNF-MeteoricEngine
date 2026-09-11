package backend;

/**
 * 容器会话阶段（`ContainerSession` 状态机用）。
 *
 * 一类型一文件（Haxe 模块规则）：enum 与 class 分开，保证 `backend.Phase`
 * 与 `backend.ContainerSession` 都能被独立解析。
 */
enum abstract Phase(String)
{
	/** 空闲（无会话）。 */
	var Idle = 'idle';
	/** 已拉起 wrapper，等待目标引擎窗口出现。 */
	var Launching = 'launching';
	/** 正在让位（宿主窗口缩成 1×1）。 */
	var Hiding = 'hiding';
	/** 正在挂起宿主（kill -STOP）。 */
	var Stopping = 'stopping';
	/** 目标引擎独占中（宿主通常处于 SIGSTOP）。 */
	var Running = 'running';
	/** 目标引擎已退出，正在收尾复位。 */
	var Returning = 'returning';
}
