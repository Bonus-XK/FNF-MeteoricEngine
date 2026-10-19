package backend;

/**
 * 构建期 git 信息的**数据载体**。
 *
 * ⚠ 本文件由 compile-mac.sh 在构建时自动改写，请不要手改 —— 手改会在下次构建被覆盖。
 *   入库的是占位值，这样没有构建脚本参与的裸 clone 也能编译通过（只是显示 "-"）。
 *
 * 实际取值见 backend.GitInfo。
 */
class GitInfoData
{
	public static var commitNumber:Int = 125;
	public static var commitHash:String = "172f802";
	public static var branchName:String = "master";
	public static var dirty:Bool = true;
}