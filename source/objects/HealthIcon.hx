package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isOldIcon:Bool = false;
	private var isPlayer:Bool = false;
	private var char:String = '';

	/** 图标帧数：2 = 正常/掉血（旧版），3 = 正常/掉血/胜利（OSEngine/FNF PR#138 胜利小图标） */
	public var iconFrames:Int = 2;

	public function new(char:String = 'bf', isPlayer:Bool = false, ?allowGPU:Bool = true)
	{
		super();
		isOldIcon = (char == 'bf-old');
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);
	}

	// Psych 0.6.3 兼容：在 bf 与 bf-old 图标之间切换（旧模组可能调用）
	public function swapOldIcon() {
		if(isOldIcon = !isOldIcon) changeIcon('bf-old');
		else changeIcon('bf');
	}

	/** 图集帧数：450 宽 = 3 帧（胜利小图标），其余按 2 帧处理 */
	public static function sheetFrameCount(graphicWidth:Int):Int
	{
		var n:Int = Std.int(Math.floor(graphicWidth / 150));
		return (n >= 3) ? 3 : 2;
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = true) {
		if(this.char != char) {
			var name:String = 'icons/' + char;
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon
			
			var graphic = Paths.image(name, allowGPU);
			iconFrames = sheetFrameCount(graphic.width);
			loadGraphic(graphic, true, Math.floor(graphic.width / iconFrames), Math.floor(graphic.height));
			iconOffsets[0] = (width - 150) / iconFrames;
			iconOffsets[1] = (height - 150) / 2;
			updateHitbox();

			animation.add(char, [for (i in 0...iconFrames) i], 0, false, isPlayer);
			animation.play(char);
			this.char = char;

			if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	override function updateHitbox()
	{
		super.updateHitbox();
		offset.x = iconOffsets[0];
		offset.y = iconOffsets[1];
	}

	public function getCharacter():String {
		return char;
	}
}
