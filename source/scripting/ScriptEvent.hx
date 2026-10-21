package scripting;

/**
 * 脚本事件（可取消）。
 *
 * 引擎在关键决策点派发一个事件，脚本可以：
 *  - **改写事件字段**（改数值 / 换贴图 / 改参数）—— 事件字段是 public var，直接赋值即可；
 *  - `event.cancel()` —— **阻止引擎的默认行为**（这一段逻辑由脚本自己接管）；
 *  - `event.cancel(true)` —— 阻止默认行为，但**继续**广播给后续脚本
 *    （默认 `cancel()` 会中断广播：后面的脚本收不到这个事件）。
 *
 * 与既有 `callOnScripts('onXxx')` 回调的关系：那一套是 Psych 风格的**通知**，
 * 本类是「**可拦截、可改参**」的决策点，两套并存、互不覆盖（契约只增不减）。
 *
 * 事件只在总开关 + 事件分项开关都打开时才派发；关闭时引擎里那几行直接跳过，
 * 行为与改动前完全一致。
 */
class ScriptEvent
{
	/** 是否已取消引擎的默认行为。 */
	public var cancelled(default, null):Bool = false;

	/** 取消默认行为后，是否仍继续广播给后续脚本。 */
	public var continueCalls(default, null):Bool = false;

	/**
	 * 脚本自由数据袋：脚本之间传数据用（引擎不读这个字段）。
	 * 例：`event.data = {myLevel = 3};`
	 */
	public var data:Dynamic = null;

	public function new() {}

	/**
	 * 取消引擎的默认行为。
	 * @param continueCalls true = 仍然广播给后续脚本；false（默认）= 中断广播。
	 */
	public function cancel(continueCalls:Bool = false):Void
	{
		cancelled = true;
		this.continueCalls = continueCalls;
	}

	/** `cancel` 的别名，语义更贴近「阻止默认行为」。 */
	public function preventDefault(continueCalls:Bool = false):Void
	{
		cancel(continueCalls);
	}

	/** 事件是否已被取消（引擎侧判断用，等价于读 `cancelled`）。 */
	public inline function isCancelled():Bool
		return cancelled;
}
