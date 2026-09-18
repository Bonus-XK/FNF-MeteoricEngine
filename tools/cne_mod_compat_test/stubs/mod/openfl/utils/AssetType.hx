package openfl.utils;

/**
 * 测试替身：与 OpenFL 9.x `openfl/utils/AssetType.hx` 的 enum abstract 形状一致
 * （`CneModCompat.iconUsable` 只用到 `IMAGE`，这里列全是为了后续扩大替身时不再改文件）。
 */
#if (haxe_ver >= 4.0) enum #else @:enum #end abstract AssetType(String)
{
	public var BINARY = "BINARY";
	public var FONT = "FONT";
	public var IMAGE = "IMAGE";
	public var MOVIE_CLIP = "MOVIE_CLIP";
	public var MUSIC = "MUSIC";
	public var SOUND = "SOUND";
	public var TEMPLATE = "TEMPLATE";
	public var TEXT = "TEXT";
	public var XML = "XML";
}
