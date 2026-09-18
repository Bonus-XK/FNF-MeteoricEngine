package lime.utils;

/** 测试替身：只提供 ZipReader 引用的常量。 */
abstract CompressionAlgorithm(String)
{
	public static inline var DEFLATE:CompressionAlgorithm = cast "DEFLATE";
}
