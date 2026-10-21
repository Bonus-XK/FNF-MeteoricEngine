package scripting;

/**
 * 音符事件（生成 / 命中 / 漏接）。
 *
 * 字段都是 public var，脚本可以直接改：
 *  - `note` —— 涉及的音符对象（生成事件里已经创建好；命中/漏接事件里是那根被判定��音符）。
 *  - `noteData` —— 轨道号（0..3 玩家、4..7 对手）。
 *  - `mustPress` —— 是否要玩家按。
 *  - `sustain` —— 是否长条尾段。
 *  - `rating` —— 判定结果（命中事件里为引擎给出的评级；脚本可改）。
 *  - `hitHealth` —— 本次命中的血量变化（脚本可改）。
 *  - `score` —— 本次命中的分数（脚本可改）。
 */
class ScriptNoteEvent extends ScriptEvent
{
	/** 涉及的音符对象。 */
	public var note:Dynamic = null;

	/** 轨道号（0..3 玩家 / 4..7 对手）。 */
	public var noteData:Int = 0;

	/** 是否要玩家按。 */
	public var mustPress:Bool = true;

	/** 是否长条尾段。 */
	public var sustain:Bool = false;

	/** 判定结果（'Sick' / 'Good' / 'Bad' / 'Shit' / 'Miss'）。 */
	public var rating:String = null;

	/** 本次命中的血量变化。 */
	public var hitHealth:Float = 0;

	/** 本次命中的分数。 */
	public var score:Int = 0;

	/** 事件类型：'creation' / 'hit' / 'miss'。 */
	public var kind:String = 'creation';

	public function new(kind:String = 'creation', note:Dynamic = null)
	{
		super();
		this.kind = kind;
		this.note = note;
	}
}
