package scripting;

import backend.MusicBeatSubstate;

/**
 * 脚本定义的子状态：整个子界面由一个 HScript 写出来。
 *
 * 用法（从脚本里）：
 * ```
 * scripting.openSubState('MyPanel', {score = 100});
 * ```
 * 脚本文件位置：`mods/<mod>/scripting/states/MyPanel.hx`。
 *
 * 与 `ScriptState` 的差别：它是**子状态**（盖在当前界面上），宿主是
 * `backend.MusicBeatSubstate`；脚本里同样用 `state.add(...)` 加控件、
 * `state.data` 读传入的数据。
 */
class ScriptSubState extends MusicBeatSubstate implements IScriptScreen
{
	public var scriptName:String;

	public var data:Dynamic;

	public function new(scriptName:String = null, ?data:Dynamic)
	{
		super();
		this.scriptName = scriptName;
		this.data = data;
	}
}
