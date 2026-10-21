package scripting;

/**
 * 相机事件。
 *
 * 引擎在移动相机之前派发这个事件，脚本可以：
 *  - 改 `x` / `y` —— 改掉相机跟随目标；
 *  - `event.cancel()` —— 这一次不移动相机（相机停在原处）。
 */
class ScriptCameraEvent extends ScriptEvent
{
	/** 跟随目标：'dad' / 'boyfriend' / 'gf'。 */
	public var target:String = null;

	/** 相机目标 X（脚本可改）。 */
	public var x:Float = 0;

	/** 相机目标 Y（脚本可改）。 */
	public var y:Float = 0;

	/** 相机缩放（脚本可改；null = 不改）。 */
	public var zoom:Null<Float> = null;

	public function new(target:String = null, x:Float = 0, y:Float = 0)
	{
		super();
		this.target = target;
		this.x = x;
		this.y = y;
	}
}
