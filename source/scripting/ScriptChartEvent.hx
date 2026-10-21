package scripting;

/**
 * 谱面事件（chart event）。
 *
 * 引擎在处理谱面事件（Camera Movement / BPM Change / Scroll Speed Change …）**之前**
 * 派发这个事件，脚本可以：
 *  - 改 `value1` / `value2` —— 改掉这个事件的参数（后续的默认处理用改后的值）；
 *  - `event.cancel()` —— 跳过这个事件的默认处理（自己接管）。
 */
class ScriptChartEvent extends ScriptEvent
{
	/** 事件名（'Camera Movement' / 'BPM Change' / …）。 */
	public var eventName:String = null;

	/** 第一个参数（引擎原值，脚本可改）。 */
	public var value1:String = null;

	/** 第二个参数（引擎原值，脚本可改）。 */
	public var value2:String = null;

	/** 事件触发的时间（ms）。 */
	public var strumTime:Float = 0;

	public function new(eventName:String = null, value1:String = null, value2:String = null, strumTime:Float = 0)
	{
		super();
		this.eventName = eventName;
		this.value1 = value1;
		this.value2 = value2;
		this.strumTime = strumTime;
	}
}
