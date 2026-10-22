package scripting;

import backend.MusicBeatState;

/**
 * 脚本定义的状态：整个界面由一个 HScript 写出来。
 *
 * 用法（从脚本里）：
 * ```
 * scripting.openState('MyScreen');                       // 打开脚本界面
 * scripting.openState('MyScreen', {level = 3});          // 带数据
 * ```
 * 脚本文件位置：`mods/<mod>/scripting/states/MyScreen.hx`。
 *
 * 脚本里能做什么：
 *  - `state` —— 宿主（就是本对象）：`state.add(sprite)` 把控件加进界面；
 *  - `state.data` / 注入的 `data` —— 打开时传入的数据；
 *  - `create()` / `update(elapsed)` / `beatHit(beat)` / `stepHit(step)` / `destroy()` 回调。
 *
 * 宿主在 `MusicBeatState.create()` 末尾装载脚本，因此脚本的 `create()` 在界面
 * 初始化过程中执行；控件直接 `state.add(...)` 即可（Flixel 的 state 自行绘制成员，
 * 不需要先上舞台）。
 */
class ScriptState extends MusicBeatState implements IScriptScreen
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
