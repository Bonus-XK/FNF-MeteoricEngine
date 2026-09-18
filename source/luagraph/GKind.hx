package luagraph;

import flixel.util.FlxColor;
import backend.DesignTokens;

/** 参数槽的取值类型（决定占位文本、编辑方式与生成时的转义规则）。 */
enum GKind
{
	KEnum(options:Array<String>); // 下拉选择
	KNum;                         // 数字（步进/输入）
	KText;                        // 文本（生成时加引号并转义；可中文）
	KExpr;                        // Lua 表达式/条件（原样输出，不加引号）
	KVar;                         // 变量名（下拉已有变量 + 可自由填写）
	KTag;                         // 对象标签（生成时加引号并清洗非法字符）
}
