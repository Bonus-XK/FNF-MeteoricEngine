package backend;

/**
 * 滚轮限速工具（Freeplay 同款流畅滚动体验）：
 *  - 单次事件最多跳 2 格（快速滚轮一次 delta 可能 ±3~±10，防止一次滚飞）
 *  - 70ms 最小跳格间隔（连续快速滚动自动放慢到 ~14 格/秒，避免每格全量 UI 重活卡顿）
 *
 * 用法（各列表界面）：
 *   var ws = new WheelScroll();  // 字段，create 时初始化
 *   // wheel 处理处：
 *   var step:Int = ws.process(FlxG.mouse.wheel);
 *   if (step != 0) { 音效; changeSelection(step); }
 */
class WheelScroll
{
	public static inline var MIN_INTERVAL_MS:Int = 70;
	public static inline var MAX_STEPS:Int = 2;

	var lastStepTime:Int = 0;

	public function new() {}

	/** 处理一次滚轮事件；返回应跳的格数（带方向，0 = 被限速忽略） */
	public function process(wheelDelta:Float):Int
	{
		if (wheelDelta == 0) return 0;
		var now:Int = Std.int(haxe.Timer.stamp() * 1000);
		if (now < lastStepTime + MIN_INTERVAL_MS) return 0;
		lastStepTime = now;

		var steps:Int = Std.int(Math.abs(wheelDelta));
		if (steps < 1) steps = 1;
		if (steps > MAX_STEPS) steps = MAX_STEPS;
		return (wheelDelta > 0 ? -1 : 1) * steps;
	}
}
