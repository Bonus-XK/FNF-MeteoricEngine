package scripting;

import flixel.FlxSprite;
import flixel.util.FlxAxes;

/**
 * 脚本可见的编程层 API（**实例**）。
 *
 * ## 为什么是实例而不是静态类
 *
 * release 构建开 `--dce full`：只被**脚本反射调用**、Haxe 侧无引用的方法会被裁掉，
 * 运行时反射拿到 null 方法引用 → 抛 `Null Function Pointer`。
 * `@:keep` 对 **static 方法无效**（实测：`openState` 等在产物二进制里 0 次出现），
 * 对**实例方法**有效（仓库既有先例：`backend/Paths.hx` 的 `getFrames`）。
 * 所以脚本可见的 API 全部做成实例方法 + `@:keep`，由 `Scripting.api` 单例注入。
 *
 * 脚本里用 `scripting.xxx(...)` 调用（`scripting` 注入的就是本类的单例）。
 */
class ScriptingApi
{
	/** 全局单例（注入给脚本的 `scripting` 变量）。
	 *
	 * 惰性创建：不能在类自己的静态初始化里 `new ScriptingApi()` ——
	 * Haxe 会报「does not have a constructor」（类尚未注册好构造函数就被自己实例化）。
	 */
	public static var instance:ScriptingApi = null;

	/** 取单例（首次调用时创建）。 */
	public static function getInstance():ScriptingApi
	{
		if (instance == null) instance = new ScriptingApi();
		return instance;
	}

	public function new() {}

	// ===== 界面 =====

	/**
	 * 打开一个脚本界面：整个界面由 `scripting/states/<脚本名>.hx` 写出来。
	 * @param scriptName 脚本名（不含扩展名）。
	 * @param data 传给界面的数据（脚本界面里用 `state.data` 读）。
	 */
	@:keep
	public function openState(scriptName:String, ?data:Dynamic):Void
	{
		Scripting.openState(scriptName, data);
	}

	/**
	 * 打开一个脚本子状态：盖在当前界面上，由 `scripting/states/<脚本名>.hx` 写出来。
	 * @return true = 已请求打开。
	 */
	@:keep
	public function openSubState(scriptName:String, ?data:Dynamic):Bool
	{
		return Scripting.openSubState(scriptName, data);
	}

	/** 关闭当前界面的子状态。 */
	@:keep
	public function closeSubState():Void
	{
		Scripting.closeSubState();
	}

	/** 回到主菜单（脚本界面里做「返回」用）。 */
	@:keep
	public function backToMainMenu():Void
	{
		Scripting.backToMainMenu();
	}

	// ===== 布局 =====

	/**
	 * 把精灵居中（屏幕中心）。
	 *
	 * Flixel 的 `FlxObject.screenCenter` 是 **inline** 方法，inline 方法在 hxcpp 下
	 * 没有真实函数体，**反射调用会抛 `Null Function Pointer`** —— 脚本必须走这个包装。
	 */
	@:keep
	public function center(obj:FlxSprite):Void
	{
		if (obj == null) return;
		obj.screenCenter();
	}

	/**
	 * 把精灵居中（指定轴向）。
	 *
	 * flixel 5.x 的 `screenCenter` 收的是 **FlxAxes**（不是摄像机）：`XY` = 居中，
	 * `X` = 只居中水平，`Y` = 只居中垂直。
	 */
	@:keep
	public function centerAxes(obj:FlxSprite, axes:FlxAxes):Void
	{
		if (obj == null) return;
		obj.screenCenter(axes);
	}

	// ===== 性能面 =====

	/**
	 * 性能快照（只读）。
	 *
	 * 返回的是**匿名结构体**（不是 Map —— 脚本反射拿不到 Map 的方法）：
	 * `fps`（绘制帧率）、`elapsed`（上一帧耗时）、`rssMB`（进程常驻内存，取不到时 -1）、
	 * 以及 4 个受控旋钮的当前值（`gcBreathing` / `visualFold` / `perfMode` / `runtimePack`）。
	 * 读法：`var st = scripting.getPerfStats(); trace(st.fps);`
	 */
	@:keep
	public function getPerfStats():Dynamic
	{
		return PerfControl.stats();
	}

	/**
	 * 改一个受控的性能旋钮。
	 *
	 * 白名单：`gcBreathing`(bool) / `visualFold`(int 0..3) / `perfMode`(bool) /
	 * `runtimePack`(bool)。
	 * 不在白名单里的一律拒绝（返回值 false）—— 例如**降采样相关项刻意不开放**。
	 *
	 * 生效时机：`visualFold` 只影响之后生成的音符，`runtimePack` 只影响之后加载的贴图。
	 */
	@:keep
	public function setPerfOption(name:String, value:Dynamic):Bool
	{
		var ok:Bool = PerfControl.setOption(name, value);
		if (ok) log('性能旋钮已改：' + name + ' = ' + Std.string(value));
		else logError('性能旋钮未改：' + name + '（不在白名单 / 值不可用）');
		return ok;
	}

	/**
	 * 立刻触发一次全量 GC（回收内存）。
	 *
	 * 代价：一次 20~80ms 的顿挫。
	 */
	@:keep
	public function collectGarbage():Bool
	{
		var ok:Bool = PerfControl.collectGarbage();
		if (!ok) logError('当前平台不支持手动 GC');
		return ok;
	}

	// ===== 调试 =====

	/** 打一条日志到终端（前缀 `[Scripting]`）。 */
	@:keep
	public function log(msg:String):Void
	{
		Scripting.log(msg);
	}

	/** 打一条错误日志到终端。 */
	@:keep
	public function logError(msg:String):Void
	{
		Scripting.logError(msg);
	}

	// ===== 热重载 =====

	/** 重建全局脚本组（等同 Shift+F5）。 */
	@:keep
	public function reloadGlobalScripts():Void
	{
		Scripting.reloadGlobalScripts();
	}

	/** 重建当前界面的状态脚本组（等同 F5）。 */
	@:keep
	public function reloadCurrentStateScripts():Void
	{
		Scripting.reloadCurrentStateScripts();
	}
}
