package scripting;

/**
 * 脚本界面的标记接口（脚本定义的状态 / 子状态）。
 *
 * 只做类型标记：**不声明字段**。
 * 原因：hxcpp 下「带字段的接口」会让实现类走 `__GetField` 的接口访问路径，
 * 在脚本回调里构造实现类实例会抛 `Null Function Pointer`（2026-10-22 实测）。
 * 所以字段（`scriptName` / `data`）由实现类自己声明，宿主侧用 Reflect 读。
 */
interface IScriptScreen
{
}
