package options;

/**
 * 「画布分区」基类：自带绝对布局、自己处理输入的设置分区（按键设置、箭头配色…）。
 *
 * 为什么需要它：
 *  这两块画布既要能整屏运行（暂停内嵌路径 `PauseSettingsSubstate`），
 *  也要能塞进单界面设置（`OptionsState`）右侧 956×570 的内容区就地显示。
 *  共用一份代码 + 一个矩形参数（`hosted` 分支）即可，避免"两套界面慢慢漂移"。
 *
 * 与单界面宿主的契约：
 *  - `onExit`：画布内部按 BACK / 点返回时的出口（整屏 = close()；内容区 = 焦点回分区栏）；
 *  - `inputEnabled`：焦点在分区栏时宿主置 false —— 画布继续绘制但不吃键，
 *    否则 ↑↓/Esc 会被"画布内部列表"与"分区栏"同时消费（两处一起动）。
 */
class SettingsCanvas extends flixel.group.FlxGroup
{
	/** 离开画布 */
	public var onExit:Void->Void = null;
	/** 是否处理输入（false = 只绘制不吃键） */
	public var inputEnabled:Bool = true;

	public function new()
	{
		super();
	}
}
