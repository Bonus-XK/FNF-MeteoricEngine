package backend;

/**
 * 构建期 git 信息（commit 数 / 短 hash / 分支名 / 未提交标记）。
 *
 * 值由 **compile-mac.sh 在构建时用 git 取出**，写进 GitInfoData.hx 编译进二进制，
 * 运行时零开销、零依赖（不 fork 进程，也不需要用户机器上有 git）。
 *
 * 为什么不走 Haxe 宏（Codename Engine 的 GitCommitMacro 就是宏方案）：
 *   本项目有全局自动导入的 source/import.hx，里面有 `import llua.*`，
 *   而 llua 在宏上下文引用 cpp.RawPointer —— Haxe 明令禁止
 *   （"You cannot access the cpp package while in a macro"）。
 *   只要 import.hx 在，**任何宏类都会编译失败**（实测：加宏后 typecheck 直接挂，
 *   报错链一路指到 linc_luajit/llua/State.hx）。所以改成构建脚本生成数据文件。
 *
 * 构建机没有 git / 不是 git 仓库时，脚本写入占位值，
 * 这里全部回退为 "-"/0 —— 绝不会让构建失败。
 */
class GitInfo
{
	/** 当前 commit 数（git rev-list HEAD --count）；未知为 0。 */
	public static inline function commitNumber():Int
		return GitInfoData.commitNumber;

	/** 当前 commit 短 hash，如 "d37e324"；未知为 "-"。 */
	public static inline function commitHash():String
		return GitInfoData.commitHash;

	/** 当前分支名，如 "master"；未知为 "-"。 */
	public static inline function branchName():String
		return GitInfoData.branchName;

	/** 是否有未提交改动；未知为 false。 */
	public static inline function dirty():Bool
		return GitInfoData.dirty;

	/** 一行摘要，如 "#612 d37e324 master*"；* 表示有未提交改动。全未知时返回 "-"。 */
	public static function summary():String
	{
		if (GitInfoData.commitHash == '-' && GitInfoData.commitNumber == 0) return '-';
		var s:String = '#' + commitNumber() + ' ' + commitHash();
		if (GitInfoData.branchName != '-') s += ' ' + GitInfoData.branchName;
		if (GitInfoData.dirty) s += '*';
		return s;
	}
}