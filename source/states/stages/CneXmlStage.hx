package states.stages;

import flixel.FlxSprite;
import flixel.FlxG;
import openfl.utils.AssetType;

/**
 * CNE 舞台的图层装载（`mods/<mod>/data/stages/<名>.xml` 的 `<sprite>` 元素）。
 *
 * 为什么需要它：CNE 把背景图层写在舞台 XML 里（`<stage folder=".." zoom="..">` +
 * `<sprite sprite="street2" x=".." y=".." scale="..">`），而 Psych 的 `StageFile`
 * **没有**数据驱动的图层字段（只有角色站位/相机偏移），图层历来由 `stage` 类硬编码。
 * 所以：站位/缩放走 `cne.CneModCompat.stageFile()`（喂给 `StageData.getStageFile`），
 * 图层走本类；两者都只在「CNE 模组兼容」开启且该 mod 真提供舞台 XML 时生效。
 *
 * 贴图解析顺序（对齐 CNE `Paths.image` 的宽松解析）：
 *   `images/<folder>/<sprite>.png` → `images/<sprite>.png` → `images/stages/<sprite>.png`
 * （SMA 的 street2 就是 `folder="/"` + `sprite="street2"` → `images/street2.png`）
 */
class CneXmlStage extends BaseStage
{
	/** 当前活动的 CNE 舞台实例（CNE 歌曲脚本 `stage.stageSprites[...]` 用；无 CNE 舞台时为 null）。 */
	public static var current:CneXmlStage = null;
	/** XML `<sprite name="...">` → 实际 FlxSprite（CNE 脚本按名字取图层）。 */
	public var stageSprites:Map<String, FlxSprite> = new Map();

	public function new(stageName:String)
	{
		super();
		current = this;

		var nodes:Array<Dynamic> = cne.CneModCompat.stageSpriteNodes(stageName);
		for (n in nodes)
		{
			var sprite:String = (n.sprite != null) ? Std.string(n.sprite) : '';
			if (sprite.length == 0) continue;

			var key:String = resolveKey(Std.string(n.folder), sprite);
			if (key == null) continue;

			var bg:BGSprite = new BGSprite(key, n.x, n.y, n.scrollX, n.scrollY);
			if (n.scaleX != 1 || n.scaleY != 1)
			{
				bg.scale.set(n.scaleX, n.scaleY);
				bg.updateHitbox();
			}
			if (n.alpha != 1) bg.alpha = n.alpha;
			if (n.flipX) bg.flipX = true;
			bg.antialiasing = ClientPrefs.data.antialiasing && (n.antialiasing == true);
			add(bg);

			var nodeName:String = (n.name != null) ? Std.string(n.name) : '';
			if (nodeName.length > 0) stageSprites.set(nodeName, bg);
		}
	}

	override function destroy():Void
	{
		if (current == this) current = null;
		stageSprites.clear();
		super.destroy();
	}

	static function resolveKey(folder:String, sprite:String):String
	{
		var candidates:Array<String> = [];
		if (folder != null && folder.length > 0) candidates.push(folder + '/' + sprite);
		candidates.push(sprite);
		candidates.push('stages/' + sprite);

		for (c in candidates)
		{
			if (Paths.fileExists('images/' + c + '.png', IMAGE)) return c;
			var xmlAtlas:String = Paths.modFolders('images/' + c + '.xml');
			if (sys.FileSystem.exists(xmlAtlas)) return c;
		}
		return null;
	}
}
