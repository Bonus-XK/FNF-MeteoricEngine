package objects;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;

class StrumNote extends FlxSprite
{
	public var rgbShader:RGBShaderReference;
	public var resetAnim:Float = 0;
	private var noteData:Int = 0;
	public var direction:Float = 90;//plan on doing scroll directions soon -bb
	public var downScroll:Bool = false;//plan on doing scroll directions soon -bb
	public var sustainReduce:Bool = true;
	private var player:Int;
	
	public var texture(default, set):String = null;
	private function set_texture(value:String):String {
		if(texture != value) {
			texture = value;
			reloadNote();
		}
		return value;
	}

	public var useRGBShader:Bool = true;
	public function new(x:Float, y:Float, leData:Int, player:Int) {
		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(leData));
		rgbShader.enabled = false;
		if(PlayState.SONG != null && PlayState.SONG.disableNoteRGB) useRGBShader = false;
		if(ClientPrefs.data.psych063Mode || !ClientPrefs.data.shaders) useRGBShader = false;
		#if mobile
		useRGBShader = false; // 安卓 GPU：RGB 着色器输出全黑，强制用贴图原色
		#end
		
		var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[leData];
		if(PlayState.isPixelStage) arr = ClientPrefs.data.arrowRGBPixel[leData];
		
		if(leData <= arr.length)
		{
			@:bypassAccessor
			{
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}

		noteData = leData;
		this.player = player;
		this.noteData = leData;
		super(x, y);

		var skin:String = null;
		if(PlayState.SONG != null && PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1) skin = PlayState.SONG.arrowSkin;
		else skin = Note.defaultNoteSkin;

		// Psych 0.6.3 兼容：自动补 noteSkins/ 前缀
		if(skin.indexOf('/') < 0 && !Paths.fileExists('images/' + skin + '.png', IMAGE)
			&& Paths.fileExists('images/noteSkins/' + skin + '.png', IMAGE))
			skin = 'noteSkins/' + skin;

		var customSkin:String = skin + Note.getNoteSkinPostfix();
		if(Paths.fileExists('images/$customSkin.png', IMAGE)) skin = customSkin;

		texture = skin; //Load texture and anims
		scrollFactor.set();
	}

	public function reloadNote()
	{
		var lastAnim:String = null;
		if(animation.curAnim != null) lastAnim = animation.curAnim.name;

		if(PlayState.isPixelStage)
		{
			loadGraphic(Paths.image('pixelUI/' + texture));
			width = width / 4;
			height = height / 5;
			loadGraphic(Paths.image('pixelUI/' + texture), true, Math.floor(width), Math.floor(height));

			antialiasing = false;
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));

			// 像素版"按下/击中"染色（与黄版同款渲染方式）：像素贴图 4 列(方向)×5 行
			// （0 行=static 不动；1-2 行=pressed；3-4 行=confirm），仅对按下/击中行按列
			// 矩阵染色（arrowRGBPixel），静态保持素材原色。
			if (!useRGBShader)
			{
				try
				{
					var pb:BitmapData = frames != null && frames.parent != null ? frames.parent.bitmap : null;
					if (pb == null || !pb.readable)
						pb = objects.Note.getBakeBitmapData('pixelUI/' + texture);
					if (pb != null && pb.readable)
					{
						var fwPx:Int = Std.int(width);
						var fhPx:Int = Std.int(height);
						var tintedPx:BitmapData = pb.clone();
						var arrPx:Array<Array<FlxColor>> = ClientPrefs.data.arrowRGBPixel;
						for (fi in 4...20) // 跳过第 0 行(static 帧 0-3)
						{
							var col:Int = fi % 4;
							var row:Int = Std.int(fi / 4);
							if (arrPx == null || arrPx.length <= col) continue;
							var rect:Rectangle = new Rectangle(col * fwPx, row * fhPx, fwPx, fhPx);
							var fb:BitmapData = new BitmapData(fwPx, fhPx, true, 0x00000000);
							fb.copyPixels(pb, rect, new Point(0, 0));
							objects.Note.applyRGBToBitmap(fb, arrPx[col][0], arrPx[col][1], arrPx[col][2]);
							tintedPx.copyPixels(fb, fb.rect, new Point(col * fwPx, row * fhPx));
						}
						var gPx:FlxGraphic = FlxGraphic.fromBitmapData(tintedPx, false, null, false);
						gPx.persist = true;
						loadGraphic(gPx, true, fwPx, fhPx); // 帧索引布局不变(row*4+col)
						setGraphicSize(Std.int(width * PlayState.daPixelZoom));
					}
				}
				catch (e:Dynamic) {}
			}

			animation.add('green', [6]);
			animation.add('red', [7]);
			animation.add('blue', [5]);
			animation.add('purple', [4]);
			switch (Math.abs(noteData) % 4)
			{
				case 0:
					animation.add('static', [0]);
					animation.add('pressed', [4, 8], 12, false);
					animation.add('confirm', [12, 16], 24, false);
				case 1:
					animation.add('static', [1]);
					animation.add('pressed', [5, 9], 12, false);
					animation.add('confirm', [13, 17], 24, false);
				case 2:
					animation.add('static', [2]);
					animation.add('pressed', [6, 10], 12, false);
					animation.add('confirm', [14, 18], 12, false);
				case 3:
					animation.add('static', [3]);
					animation.add('pressed', [7, 11], 12, false);
					animation.add('confirm', [15, 19], 24, false);
			}
		}
		else
		{
			frames = Paths.getSparrowAtlas(texture);
			// 防御：图集解析失败（资源缺失/缓存失效）时回退默认音符皮肤，再不行用 1px 占位
			// —— 绝不因空 frames 崩溃（Tacotorial Normal 曾在此空指针）
			if (frames == null || frames.frames == null || frames.frames.length < 1)
			{
				trace('[StrumNote] sparrow atlas failed: ' + texture + ', fallback to default skin');
				if (texture != 'noteSkins/NOTE_assets')
				{
					frames = Paths.getSparrowAtlas('noteSkins/NOTE_assets');
				}
				if (frames == null || frames.frames == null || frames.frames.length < 1)
				{
					makeGraphic(4, 4, 0xFF000000);
					animation.add('static', [0]);
					animation.add('pressed', [0], 12, false);
					animation.add('confirm', [0], 24, false);
					return;
				}
				texture = 'noteSkins/NOTE_assets';
			}
			// 无 shader（移动端/关 shaders）：仅对"灰毛胚帧"（arrow* static / * press / * confirm）逐帧做
			// CPU 矩阵染色（与音符烘焙同算法）→ 静态/按下/确认均显示该列箭头色；
			// 彩色动画帧（green/blue/purple/red 音符素材）保持原样。
			if (!useRGBShader)
			{
				try
				{
					if (frames != null && frames.parent != null && frames.parent.bitmap != null)
					{
						var src:BitmapData = frames.parent.bitmap;
						if (!src.readable)
							src = objects.Note.getBakeBitmapData('images/' + texture);
						if (src != null && src.readable)
						{
							var tinted:BitmapData = src.clone();
							var arr:Array<Array<FlxColor>> = (PlayState.isPixelStage ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB);
							for (fr in frames.frames)
							{
								var nm:String = fr.name;
								if (nm == null) continue;
								var ln:String = nm.toLowerCase();
								if (ln.startsWith('green') || ln.startsWith('blue') || ln.startsWith('purple') || ln.startsWith('red')) continue; // 彩色动画帧不动
								if (ln.startsWith('arrow')) continue; // 未按下(静态)恢复素材原色渲染;染色仅作用于 press/confirm 帧
								var col:Int = -1;
								if (ln.indexOf('left') >= 0) col = 0;
								else if (ln.indexOf('down') >= 0) col = 1;
								else if (ln.indexOf('up') >= 0) col = 2;
								else if (ln.indexOf('right') >= 0) col = 3;
								if (col < 0 || arr == null || arr.length <= col) continue;
								// FlxFrame.frame 是 UV 矩形（x/y + right/bottom 编码于 width/height）
								var frc:flixel.math.FlxRect = fr.frame;
								var rect:Rectangle = new Rectangle(frc.x, frc.y, frc.width, frc.height);
								var frBmp:BitmapData = new BitmapData(Std.int(rect.width), Std.int(rect.height), true, 0x00000000);
								frBmp.copyPixels(src, rect, new Point(0, 0));
								objects.Note.applyRGBToBitmap(frBmp, arr[col][0], arr[col][1], arr[col][2]);
								tinted.copyPixels(frBmp, frBmp.rect, new Point(rect.x, rect.y));
							}
							var g:FlxGraphic = FlxGraphic.fromBitmapData(tinted, false, null, false);
							g.persist = true;
							var xmlData:String = backend.Paths.getTextFromFile('images/' + texture + '.xml');
							if (xmlData != null && xmlData.length > 0)
							{
								frames = FlxAtlasFrames.fromSparrow(g, xmlData);
							}
						}
					}
				}
				catch (e:Dynamic) {}
			}
			animation.addByPrefix('green', 'arrowUP');
			animation.addByPrefix('blue', 'arrowDOWN');
			animation.addByPrefix('purple', 'arrowLEFT');
			animation.addByPrefix('red', 'arrowRIGHT');

			antialiasing = ClientPrefs.data.antialiasing;
			setGraphicSize(Std.int(width * 0.7));

			switch (Math.abs(noteData) % 4)
			{
				case 0:
					animation.addByPrefix('static', 'arrowLEFT');
					animation.addByPrefix('pressed', 'left press', 24, false);
					animation.addByPrefix('confirm', 'left confirm', 24, false);
				case 1:
					animation.addByPrefix('static', 'arrowDOWN');
					animation.addByPrefix('pressed', 'down press', 24, false);
					animation.addByPrefix('confirm', 'down confirm', 24, false);
				case 2:
					animation.addByPrefix('static', 'arrowUP');
					animation.addByPrefix('pressed', 'up press', 24, false);
					animation.addByPrefix('confirm', 'up confirm', 24, false);
				case 3:
					animation.addByPrefix('static', 'arrowRIGHT');
					animation.addByPrefix('pressed', 'right press', 24, false);
					animation.addByPrefix('confirm', 'right confirm', 24, false);
			}
		}
		updateHitbox();


		if(lastAnim != null)
		{
			playAnim(lastAnim, true);
		}
	}

	public function postAddedToGroup() {
		playAnim('static');
		x += Note.swagWidth * noteData;
		x += 50;
		x += ((FlxG.width / 2) * player);
		ID = noteData;
	}

	override function update(elapsed:Float) {
		if(resetAnim > 0) {
			resetAnim -= elapsed;
			if(resetAnim <= 0) {
				playAnim('static');
				resetAnim = 0;
			}
		}
		super.update(elapsed);
	}

	public function playAnim(anim:String, ?force:Bool = false) {
		animation.play(anim, force);
		if(animation.curAnim != null)
		{
			centerOffsets();
			centerOrigin();
		}
		if(useRGBShader) rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
		// 无 shader（移动端）：静态/按下/确认帧的贴图已由 reloadNote 逐帧矩阵染色
		// （arrow* / * press / * confirm 均染为列色），此处不再叠加 color ——
		// 叠加会与染色帧相乘 → 二次上色发黑/怪异（此前"按下发黑"的根因）。
	}
}
