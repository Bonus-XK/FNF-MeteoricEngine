package scripting;

/**
 * 评级事件（评级弹窗）。
 *
 * 引擎在弹评级之前派发这个事件，脚本可以：
 *  - 改 `ratingImage` —— 换掉评级贴图名（'sick' / 'good' / 'bad' / 'shit' / 'marvelous' …，
 *    引擎仍会按关卡 UI 前缀与像素版后缀拼路径）；
 *  - 改 `visible` —— 不显示评级弹窗；
 *  - `event.cancel()` —— 等同于不显示评级弹窗。
 */
class ScriptRatingEvent extends ScriptEvent
{
	/** 评级贴图名（脚本可改）。 */
	public var ratingImage:String = null;

	/** 是否显示评级弹窗（脚本可改）。 */
	public var visible:Bool = true;

	/** 判定名（'Sick' / 'Good' / 'Bad' / 'Shit'）。 */
	public var ratingName:String = null;

	/** 连击数。 */
	public var combo:Int = 0;

	public function new(ratingImage:String = null, ratingName:String = null, combo:Int = 0)
	{
		super();
		this.ratingImage = ratingImage;
		this.ratingName = ratingName;
		this.combo = combo;
	}
}
