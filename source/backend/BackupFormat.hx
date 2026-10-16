package backend;

/**
 * 备份文件格式。
 *
 * 独立成文件是因为 Haxe 的 enum / enum abstract **都不能嵌套在类里**，
 * 而备份逻辑集中在 SaveMover 里、界面在 BackupSubState，两边都要用。
 */
enum BackupFormat
{
	/** zip 原始文件包：可勾选打包项，最通用（能直接打开看里面是什么）。 */
	ZIP;

	/**
	 * 自定义二进制：魔数 MSB1 + 版本 + flags + 分项（名字/长度/负载）。
	 * 分项自带长度前缀，还原时可跳过不认识的项；参照 Seiun Engine 的 .SEB 思路，
	 * 但魔数与结构是我们自己的。
	 */
	BINARY;

	/** 结构化 JSON：只含设置/键位等，体积最小、人可读，跨版本最稳。 */
	JSON;
}