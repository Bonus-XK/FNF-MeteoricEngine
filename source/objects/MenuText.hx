package objects;

import flixel.math.FlxPoint;

class MenuText extends FlxText
{
	public var isMenuItem:Bool = false;
	public var targetY:Int = 0;
	public var changeX:Bool = true;
	public var changeY:Bool = true;
	public var distancePerItem:FlxPoint = new FlxPoint(20, 120);
	public var startPosition:FlxPoint = new FlxPoint(0, 0);

	public function new(x:Float, y:Float, text:String = "", ?bold:Bool = true, ?size:Int = 32)
	{
		super(x, y, 0, text, size);
		this.bold = bold;
		this.startPosition.x = x;
		this.startPosition.y = y;
		this.setFormat(Paths.font("future.ttf"), size, FlxColor.WHITE, "left", FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		this.borderSize = 2.4;
		this.antialiasing = ClientPrefs.data.antialiasing;
	}

	override function update(elapsed:Float)
	{
		if (isMenuItem)
		{
			var lerpVal:Float = FlxMath.bound(elapsed * 9.6, 0, 1);
			if(changeX)
				x = FlxMath.lerp(x, (targetY * distancePerItem.x) + startPosition.x, lerpVal);
			if(changeY)
				y = FlxMath.lerp(y, (targetY * 1.3 * distancePerItem.y) + startPosition.y, lerpVal);
		}
		super.update(elapsed);
	}

	public function snapToPosition()
	{
		if (isMenuItem)
		{
			if(changeX)
				x = (targetY * distancePerItem.x) + startPosition.x;
			if(changeY)
				y = (targetY * 1.3 * distancePerItem.y) + startPosition.y;
		}
	}

	public function setScale(newX:Float, newY:Null<Float> = null)
	{
		scale.x = newX;
		if(newY == null) newY = newX;
		scale.y = newY;
	}

	public function setAlignmentFromString(align:String)
	{
		switch(align.toLowerCase().trim())
		{
			case 'right':
				alignment = "right";
			case 'center' | 'centered':
				alignment = "center";
			default:
				alignment = "left";
		}
	}
}
