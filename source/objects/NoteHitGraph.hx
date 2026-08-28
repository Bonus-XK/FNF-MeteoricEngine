package objects;

import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.Shape;

/**
 * KE（Kade Engine 1.8）结算界面「命中判定散点图」的 Meteoric 移植版。
 *
 * 横轴 = 音符时间（strumTime / 曲长），纵轴 = 命中偏移（+ 早到 → 顶部 / - 晚到 → 底部），
 * 中间 4 条判定窗口横线（±45/±90/±135/±166ms，KE 配色：绿/红/深红/暗红），
 * 每颗主音符按评级画 1 个彩色点（marvelous/sick 青、good 绿、bad 红、shit 深红、miss 暗红）。
 * 绘制一次即静态，直接返回可 add 的 FlxSprite（位图已按 1:1 像素硬边渲染）。
 */
typedef NoteHitEntry =
{
	t:Float, // 音符 strumTime（ms）
	d:Float, // 命中偏移（ms）：+ 早到 / - 晚到；miss 用外沿窗口（视为晚到）
	r:String // 评级：marvelous / sick / good / bad / shit / miss
}

class NoteHitGraph
{
	// KE 判定窗口（ms）：与 45/90/135/166 窗口线一一对应
	public static var WINDOW_MS:Array<Float> = [45, 90, 135, 166];
	static var WINDOW_COLORS:Array<Int> = [0xFF00FF00, 0xFFFF0000, 0xFF8B0000, 0xFF580000];

	/** 纵轴半程（ms）：超出 ±166 的偏移（如 miss 贴边）仍收敛在图内 */
	public static var MAX_ABS:Float = 200;

	/**
	 * 构建散点图 FlxSprite（尺寸 = width×height，透明底，可直接 add）。
	 * @param entries 本局判定历史（NoteHitEntry）
	 * @param songLength 曲长（ms），0 时横轴按最后一条音符时间归一
	 */
	public static function build(width:Int, height:Int, entries:Array<NoteHitEntry>, songLength:Float):FlxSprite
	{
		var bm:BitmapData = new BitmapData(width, height, true, 0x00000000);
		var shape:Shape = new Shape();
		var g = shape.graphics;

		var xPad:Float = 3;
		var yPad:Float = 3;
		var w:Float = width - xPad * 2;
		var h:Float = height - yPad * 2;

		// ---- 坐标映射（+ 早到 → 顶部；- 晚到 → 底部） ----
		var lastT:Float = 0;
		for (e in entries) if (e.t > lastT) lastT = e.t;
		var span:Float = (songLength > 0) ? songLength : lastT;

		function xOf(t:Float):Float
		{
			if (span <= 0) return xPad;
			return xPad + FlxMath.bound(t / span, 0, 1) * w;
		}
		function yOf(d:Float):Float
		{
			var v:Float = FlxMath.bound(d / MAX_ABS, -1, 1);
			return yPad + (1 - (v + 1) / 2) * h;
		}

		// ---- 判定窗口横线（KE 配色，先画线再画点） ----
		for (i in 0...WINDOW_MS.length)
		{
			var ms:Float = WINDOW_MS[i];
			var c:Int = WINDOW_COLORS[i];
			g.lineStyle(1, c, 0.42);
			g.moveTo(xPad, yOf(ms));
			g.lineTo(width - xPad, yOf(ms));
			g.moveTo(xPad, yOf(-ms));
			g.lineTo(width - xPad, yOf(-ms));
		}

		// ---- 0ms 中线 ----
		g.lineStyle(1, 0xFFFFFFFF, 0.22);
		g.moveTo(xPad, yOf(0));
		g.lineTo(width - xPad, yOf(0));

		// ---- 左轴 / 底轴 ----
		g.lineStyle(1, 0xFFFFFFFF, 0.5);
		g.moveTo(xPad, yPad);
		g.lineTo(xPad, height - yPad);
		g.moveTo(xPad, height - yPad);
		g.lineTo(width - xPad, height - yPad);

		// ---- 散点（4×4，按判定着色） ----
		g.lineStyle(1, 0xFFFFFFFF, 1);
		for (e in entries)
		{
			var c:Int = switch (e.r)
			{
				case 'marvelous' | 'sick': 0xFF00FFFF;
				case 'good': 0xFF00FF00;
				case 'bad': 0xFFFF0000;
				case 'shit': 0xFF8B0000;
				case 'miss': 0xFF580000;
				default: 0xFFFFFFFF;
			}
			g.beginFill(c);
			g.drawRect(xOf(e.t) - 2, yOf(e.d) - 2, 4, 4);
			g.endFill();
		}

		bm.draw(shape);

		var spr:FlxSprite = new FlxSprite();
		spr.pixels = bm;
		spr.antialiasing = false; // 1:1 位图，硬边显示
		spr.updateHitbox();
		return spr;
	}
}
