package cne;

#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
/**
 * CNE 式软编码子状态：用一个 HScript 来驱动整个子界面。
 *
 * 脚本位置：`mods/<mod>/data/states/<stateName>/LIB_<mod>.hx`（可退回 `<stateName>.hx`）。
 * 由 `backend.MusicBeatSubstate.create()` 走 `ProgrammingManager.onSubStateCreate(this)` 装载脚本。
 */
class ModSubState extends backend.MusicBeatSubstate
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
