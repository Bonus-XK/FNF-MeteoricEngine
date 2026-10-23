package ex;

/**
 * Meteoric：每个 HScript 实例一份的 mod 类提供器。
 *
 * 类描述符是全局的；静态成员代理按脚本隔离，避免两个脚本的静态变量互相污染。
 */
interface ModClassProvider
{
	/** 把短名 / 全名解析成注册表中的全名；找不到时返回 null。 */
	public function resolveClassName(name:String):String;

	/** 取得（并缓存）该类的静态成员代理；找不到时返回 null。 */
	public function getClassProxy(name:String):ScriptClass;
}
