package ex;

/** Meteoric：import 时指向尚未创建静态代理的 mod 类。 */
class ModClassRef
{
	public var name(default, null):String;

	public function new(name:String)
	{
		this.name = name;
	}
}
