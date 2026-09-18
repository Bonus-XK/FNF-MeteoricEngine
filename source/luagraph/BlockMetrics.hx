package luagraph;

import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import backend.DesignTokens;
import backend.Paths;

/** 测量结果（宽度/高度/两个容器高度），用于布局两遍法：先量后画。 */
typedef BlockMetrics =
{
	var w:Float;
	var h:Float;
	var bodyH:Float;
	var elseH:Float;
	var headerH:Float;
}
