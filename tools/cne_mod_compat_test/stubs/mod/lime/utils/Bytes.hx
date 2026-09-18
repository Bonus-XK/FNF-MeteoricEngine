package lime.utils;

/**
 * 测试替身：仅为让仓库 `backend/ZipReader.hx` 的 deflate 分支通过类型检查。
 * 本测试的 zip 用 `zip -0`（stored）生成，**不会**走到 deflate 分支；
 * 真实引擎构建使用 lime 的原生 zlib 实现（非本替身）。
 */
class Bytes
{
	var b:haxe.io.Bytes;

	public function new(b:haxe.io.Bytes)
	{
		this.b = b;
	}

	public static function fromBytes(b:haxe.io.Bytes):Bytes
	{
		return new Bytes(b);
	}

	public function decompress(algorithm:Dynamic):haxe.io.Bytes
	{
		throw 'test stub: deflate branch not exercised';
	}
}
