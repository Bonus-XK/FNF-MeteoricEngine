package bridge;

/** CNE 兼容层边界（第④大类 ③）。主流程不再直接 import cne.*，一律经本类。
 *  内部用全限定名引用 cne 类 → 本类也不产生 `import cne.*`。
 *  可复核：grep -rn "import cne" source/states source/backend source/objects → 0。 */
class CneBridge
{
	public static function clearCaches():Void
		cne.CneModCompat.clearCaches();
	public static function isCneMod(folder:String):Bool
		return cne.CneModCompat.isCneMod(folder);
	public static function isEnabled():Bool
		return cne.CneModCompat.isEnabled();
	public static function hasStageXml(stage:String):Bool
		return cne.CneModCompat.hasStageXml(stage);
	public static function applyCallbacks(script:Dynamic):Void
		cne.CneScriptCompat.applyCallbacks(script);
	public static function loadSongScripts(ps:states.PlayState, songName:String):Void
		cne.CneScriptCompat.loadSongScripts(ps, songName);
	public static function programmingInit():Void
		cne.ProgrammingManager.init();
	public static function programmingOnStateCreate(state:backend.MusicBeatState):Void
		cne.ProgrammingManager.onStateCreate(state);
}
