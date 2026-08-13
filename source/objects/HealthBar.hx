package objects;

import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

class HealthBar extends FlxSpriteGroup
{
	public var leftBar:FlxSprite;
	public var rightBar:FlxSprite;
	public var bg:FlxSprite;
	public var valueFunction:Void->Float = function() return 0;
	public var percent(default, set):Float = 0;
	public var bounds:Dynamic = {min: 0, max: 1};
	public var leftToRight(default, set):Bool = true;
	public var barCenter(default, null):Float = 0;

	// you might need to change this if you want to use a custom bar
	public var barWidth(default, set):Int = 1;
	public var barHeight(default, set):Int = 1;
	public var barOffset:FlxPoint = new FlxPoint(3, 3);
	public var borderSize(default, set):Int = 0;
	public var hollowShape:Bool = false;

	public function new(x:Float, y:Float, image:String = 'healthBar', valueFunction:Void->Float = null, boundX:Float = 0, boundY:Float = 1,
			?oldVersion:Bool = false)
	{
		super(x, y);
		
		if(valueFunction != null) this.valueFunction = valueFunction;
		setBounds(boundX, boundY);
		
		bg = new FlxSprite().loadGraphic(Paths.image(image));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		barWidth = Std.int(bg.width - 6);
		barHeight = Std.int(bg.height - 6);

		leftBar = new FlxSprite().makeGraphic(Std.int(bg.width), Std.int(bg.height), FlxColor.WHITE);
		//leftBar.color = FlxColor.WHITE;
		leftBar.antialiasing = antialiasing = ClientPrefs.data.antialiasing;

		rightBar = new FlxSprite().makeGraphic(Std.int(bg.width), Std.int(bg.height), FlxColor.WHITE);
		rightBar.color = FlxColor.BLACK;
		rightBar.antialiasing = ClientPrefs.data.antialiasing;

		checkForHollowShape();

		if(oldVersion)
		{
			add(bg);
			add(leftBar);
			add(rightBar);
		}
		else
		{
			add(leftBar);
			add(rightBar);
			add(bg);
		}
		regenerateClips();
	}

	override function update(elapsed:Float) {
		var value:Null<Float> = FlxMath.remapToRange(FlxMath.bound(valueFunction(), bounds.min, bounds.max), bounds.min, bounds.max, 0, 100);
		percent = (value != null ? value : 0);
		super.update(elapsed);
	}
	
	public function setBounds(min:Float, max:Float)
	{
		bounds.min = min;
		bounds.max = max;
	}

	public function setColors(left:FlxColor, right:FlxColor)
	{
		leftBar.color = left;
		rightBar.color = right;
	}

	public function updateBar()
	{
		if(leftBar == null || rightBar == null) return;

		leftBar.setPosition(bg.x, bg.y);
		rightBar.setPosition(bg.x, bg.y);

		var leftSize:Float = 0;
		if(leftToRight) leftSize = FlxMath.lerp(0, barWidth, percent / 100);
		else leftSize = FlxMath.lerp(0, barWidth, 1 - percent / 100);

		leftBar.clipRect.width = leftSize;
		leftBar.clipRect.height = barHeight;
		leftBar.clipRect.x = barOffset.x;
		leftBar.clipRect.y = barOffset.y;

		rightBar.clipRect.width = barWidth - leftSize;
		rightBar.clipRect.height = barHeight;
		rightBar.clipRect.x = barOffset.x + leftSize;
		rightBar.clipRect.y = barOffset.y;

		barCenter = leftBar.x + leftSize + barOffset.x;

		// flixel is retarded
		leftBar.clipRect = leftBar.clipRect;
		rightBar.clipRect = rightBar.clipRect;
	}

	public function regenerateClips()
	{
		if(leftBar != null)
		{
			leftBar.setGraphicSize(Std.int(bg.width), Std.int(bg.height));
			leftBar.updateHitbox();
			leftBar.clipRect = new FlxRect(0, 0, Std.int(bg.width), Std.int(bg.height));
		}
		if(rightBar != null)
		{
			rightBar.setGraphicSize(Std.int(bg.width), Std.int(bg.height));
			rightBar.updateHitbox();
			rightBar.clipRect = new FlxRect(0, 0, Std.int(bg.width), Std.int(bg.height));
		}
		updateBar();
	}

	private function set_percent(value:Float)
	{
		var doUpdate:Bool = false;
		if(value != percent) doUpdate = true;
		percent = value;

		if(doUpdate) updateBar();
		return value;
	}

	private function set_leftToRight(value:Bool)
	{
		leftToRight = value;
		updateBar();
		return value;
	}

	private function set_barWidth(value:Int)
	{
		barWidth = value;
		regenerateClips();
		return value;
	}

	private function set_barHeight(value:Int)
	{
		barHeight = value;
		regenerateClips();
		return value;
	}

	// ---- Psych 0.6.3 (FlxBar) 兼容 API，供 0.6.3 及以下的旧模组脚本使用 ----

	// FlxBar 的 setRange，旧模组（Haxe）可能调用
	public function setRange(min:Float, max:Float)
	{
		setBounds(min, max);
	}

	// 0.6.3 的 healthBar.createFilledBar(emptyColor, fillColor)：
	// emptyColor 为未填充侧（对手）颜色，fillColor 为填充侧（玩家）颜色
	public function createFilledBar(empty:FlxColor, fill:FlxColor, showBorder:Bool = false, border:FlxColor = FlxColor.WHITE, borderSize:Int = 1)
	{
		setColors(empty, fill);
		this.borderSize = showBorder ? borderSize : 0;
		updateBar();
	}

	public var reversed(get, set):Bool;

	function get_reversed()
	{
		return !leftToRight;
	}

	function set_reversed(value:Bool)
	{
		leftToRight = !value;
		return value;
	}

	public var fillDirection(get, set):String;

	function get_fillDirection()
	{
		return leftToRight ? 'LEFT_TO_RIGHT' : 'RIGHT_TO_LEFT';
	}

	function set_fillDirection(value:String)
	{
		leftToRight = (value == 'LEFT_TO_RIGHT');
		return value;
	}

	// FlxBar 的圆角分割数，旧模组可能设置，此实现不需要分割所以无实际作用
	public var numDivisions:Int = 0;

	public var min(get, set):Float;
	public var max(get, set):Float;
	public var range(get, null):Float;
	public var value(get, set):Float;

	function get_min()
	{
		return bounds.min;
	}

	function set_min(newMin:Float)
	{
		bounds.min = newMin;
		return newMin;
	}

	function get_max()
	{
		return bounds.max;
	}

	function set_max(newMax:Float)
	{
		bounds.max = newMax;
		return newMax;
	}

	function get_range()
	{
		return bounds.max - bounds.min;
	}

	function get_value()
	{
		return valueFunction();
	}

	function set_value(newValue:Float)
	{
		percent = (newValue - bounds.min) / (bounds.max - bounds.min) * 100;
		return newValue;
	}

	private function set_borderSize(value:Int)
	{
		if(value != borderSize)
		{
			borderSize = value;
			if(!hollowShape)
			{
				barWidth = Std.int(bg.width - 6 - borderSize * 2);
				barHeight = Std.int(bg.height - 6 - borderSize * 2);
				barOffset.x = 3 + borderSize;
				barOffset.y = 3 + borderSize;
			}
		}
		return value;
	}

	private function checkForHollowShape():Void
	{
		if(bg == null || bg.pixels == null)
			return;

		var bitmap:BitmapData = bg.pixels;
		var w:Int = bitmap.width;
		var h:Int = bitmap.height;

		var alphaThreshold:Int = 50; // Alpha >= 50 的像素视为边框，阻止洪水填充
		var wallThreshold:Int = 250; // 阻挡填充扩展的实心墙

		var visited:openfl.Vector<Int> = new openfl.Vector<Int>(w * h, true);
		for(i in 0...visited.length) visited[i] = 0;

		var queue:Array<Int> = [];

		// 把所有边缘像素加入队列
		for(x in 0...w)
		{
			queue.push(x); // 顶行
			queue.push((h - 1) * w + x); // 底行
		}
		for(y in 1...h - 1)
		{
			queue.push(y * w); // 左列
			queue.push(y * w + (w - 1)); // 右列
		}

		var work:BitmapData = new BitmapData(w, h, true, 0x00000000);
		var idx:Int;
		var curX:Int, curY:Int;
		var pixelAlpha:Int;

		bitmap.lock();
		work.lock();

		// 第一遍：从边缘洪水填充，标记条外区域
		while(queue.length > 0)
		{
			idx = queue.pop();

			if(visited[idx] == 1) continue;

			curX = idx % w;
			curY = Std.int(idx / w);

			pixelAlpha = (bitmap.getPixel32(curX, curY) >> 24) & 0xFF;

			if(pixelAlpha >= alphaThreshold)
				continue; // 撞到边框，停止扩展

			visited[idx] = 1; // 透明/低透明：条外区域

			if(curX > 0) queue.push(idx - 1);
			if(curX < w - 1) queue.push(idx + 1);
			if(curY > 0) queue.push(idx - w);
			if(curY < h - 1) queue.push(idx + w);
		}

		// 第二遍：找到外壳内部未访问的透明区域，标记为填充区域
		var barQueue:Array<Int> = [];

		for(i in 0...w * h)
		{
			if(visited[i] == 0) // 在外壳内部
			{
				curX = i % w;
				curY = Std.int(i / w);
				pixelAlpha = (bitmap.getPixel32(curX, curY) >> 24) & 0xFF;

				if(pixelAlpha < alphaThreshold)
				{
					visited[i] = 2;
					barQueue.push(i);
				}
			}
		}

		while(barQueue.length > 0)
		{
			idx = barQueue.pop();

			curX = idx % w;
			curY = Std.int(idx / w);

			if(curX > 0 && visited[idx - 1] == 0 && (((bitmap.getPixel32(curX - 1, curY) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx - 1] = 2;
				barQueue.push(idx - 1);
			}
			if(curX < w - 1 && visited[idx + 1] == 0 && (((bitmap.getPixel32(curX + 1, curY) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx + 1] = 2;
				barQueue.push(idx + 1);
			}
			if(curY > 0 && visited[idx - w] == 0 && (((bitmap.getPixel32(curX, curY - 1) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx - w] = 2;
				barQueue.push(idx - w);
			}
			if(curY < h - 1 && visited[idx + w] == 0 && (((bitmap.getPixel32(curX, curY + 1) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx + w] = 2;
				barQueue.push(idx + w);
			}
		}

		for(x in 0...w)
		{
			for(y in 0...h)
			{
				idx = y * w + x;
				if(visited[idx] == 2)
					work.setPixel32(x, y, 0xFFFFFFFF);
				else
					work.setPixel32(x, y, 0x00000000);
			}
		}

		bitmap.unlock();
		work.unlock();

		var barBounds:Rectangle = work.getColorBoundsRect(0xFFFFFFFF, 0xFFFFFFFF, true);

		if(barBounds.width > 0 && barBounds.height > 0)
		{
			leftBar.pixels = work.clone();
			rightBar.pixels = work;
			hollowShape = true;

			barWidth = Std.int(bg.width);
			barHeight = Std.int(bg.height);
			barOffset.set(0, 0);

			leftBar.antialiasing = ClientPrefs.data.antialiasing;
			rightBar.antialiasing = ClientPrefs.data.antialiasing;
		}
		else
		{
			work.dispose();
		}
	}
}
