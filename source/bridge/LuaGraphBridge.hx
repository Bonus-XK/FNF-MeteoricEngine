package bridge;

/** LuaGraph 编辑器边界（第④大类 ③）。主流程不再直接引用 luagraph/编辑器类。 */
class LuaGraphBridge
{
	/** 是否需要打开 LuaGraph 编辑器（原 TitleState 的 selfTestRequested 探测）。 */
	public static function selfTestRequested():Bool
		return states.editors.LuaGraphEditorState.selfTestRequested();

	/** 打开 LuaGraph 编辑器。 */
	public static function openEditor():Void
		backend.MusicBeatState.switchState(new states.editors.LuaGraphEditorState());
}
