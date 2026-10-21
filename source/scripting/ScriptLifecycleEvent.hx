package scripting;

/**
 * 生命周期事件（结算 / 死亡）。
 *
 * - `kind = 'songEnd'` —— 歌曲即将结算。`event.cancel()` = 不结算，停在游玩界面。
 * - `kind = 'gameOver'` —— 即将死亡。`event.cancel()` = 不死（血量会被拉回 0 以上）。
 *
 * 界面跳转不走这里：脚本在 `preStateSwitch` 里 **return 一个界面名** 即可改跳转目标
 * （见 `Scripting.redirectState`）。
 */
class ScriptLifecycleEvent extends ScriptEvent
{
	/** 事件类型：'songEnd' / 'gameOver'。 */
	public var kind:String = 'songEnd';

	/** 歌曲名（songEnd）。 */
	public var songName:String = null;

	/** 当前血量（gameOver，脚本可改；> 0 的值会作为复活后的血量）。 */
	public var health:Float = 0;

	public function new(kind:String = 'songEnd')
	{
		super();
		this.kind = kind;
	}
}
