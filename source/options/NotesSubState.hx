package options;

/**
 * 「箭头配色」整屏子状态（暂停内嵌路径 + 兼容既有引用）。
 *
 * 画布本体已抽到 `NotesPane`：单界面设置（OptionsState 的侧栏分区）与暂停内嵌运行**同一份代码**，
 * 只是几何基准不同（内容区 rect / 整屏）。本类只负责"整屏几何 + 关闭语义"。
 */
class NotesSubState extends MusicBeatSubstate
{
	var pane:NotesPane;

	public function new()
	{
		super();

		pane = new NotesPane(null); // null = 整屏画布：几何与改造前逐像素一致
		pane.onExit = function() close();
		add(pane);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
