package cne;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
/**
 * CNE 式软编码状态：用一个 HScript 来驱动整个界面。
 *
 * 脚本位置：`mods/<mod>/data/states/<stateName>/LIB_<mod>.hx`（可退回 `<stateName>.hx`）。
 * 构造后由 `backend.MusicBeatState.create()` 走 `ProgrammingManager.onStateCreate(this)` 装载脚本。
 *
 * 与 CNE 的差异：脚本内用 `state` 访问宿主（SScript 不允许改写 `this`）；
 * `data` 通过 `ModState.lastData` 在同类状态间保持，语义与 CNE 一致。
 */
class ModState extends backend.MusicBeatState
{
	public static var lastName:String = null;
	public static var lastData:Dynamic = null;

	public var data:Dynamic = null;

	public function new(stateName:String, ?data:Dynamic)
	{
		super();

		if (stateName != null && stateName != lastName)
		{
			lastName = stateName;
			lastData = null;
		}
		if (data != null) lastData = data;

		this.data = lastData;
		this.cneScriptName = lastName;
	}
}
#end
