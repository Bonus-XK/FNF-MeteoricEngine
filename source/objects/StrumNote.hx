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
		
		// Extra Keys：laneColors 12 轨越界兜底（lane 4-11 用独立自定义色）
		var arr:Array<FlxColor> = ExtraKeys.laneColors(leData, PlayState.isPixelStage);
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

		// ===== Leather 风格箭头（keys>4 自动启用）：ui skins 图集 + 方向名帧 =====
		// static 帧 = maniaDirections 表方向名小写 + " static"；
		// press/confirm 帧 = maniaAnimationDirections 表 + " press"/" confirm"。
		// 布局缩放 = 帧宽 × 0.7 × (1 − maniaSize[kc])（laneScale 已含）。
		if (PlayState.isPixelStage == false && ExtraKeys.usingLeatherSkin())
		{
			var lTex:String = 'ui skins/default/arrows/default';
			frames = Paths.getSparrowAtlas(lTex);
			if (frames == null || frames.frames == null || frames.frames.length < 1)
			{
				trace('[StrumNote] Leather atlas failed: ' + lTex + ' → fallback default skin');
				texture = 'noteSkins/NOTE_assets';
			}
			else
			{
				texture = lTex;
				antialiasing = ClientPrefs.data.antialiasing;
				var dirFrame:String = ExtraKeys.arrowDirFrame(noteData); // maniaDirections（static）
				var dirAnim:String = ExtraKeys.noteAnimPrefix(noteData); // maniaAnimationDirections（press/confirm）
				animation.addByPrefix('static', dirFrame + ' static');
				animation.addByPrefix('pressed', dirAnim + ' press', 24, false);
				animation.addByPrefix('confirm', dirAnim + ' confirm', 24, false);
				// ⚠ 用固定帧宽 157（Leather 图集帧尺寸），不用动态 width：
				// reloadNote 会被 texture setter 触发多次，动态 width 会二次缩放（91→52 越缩越小）
				setGraphicSize(Std.int(157 * 0.7 * ExtraKeys.laneScale));
				updateHitbox();
				if (lastAnim != null) playAnim(lastAnim, true);
				return;
			}
		}

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
						// Extra Keys：lane ≥ 4 统一用本 lane 调色板（帧列仍是循环复用的 0-3 列）
						var lanePalPx:Array<FlxColor> = ExtraKeys.laneColors(noteData, true);
						for (fi in 4...20) // 跳过第 0 行(static 帧 0-3)
						{
							var col:Int = fi % 4;
							var row:Int = Std.int(fi / 4);
							if (arrPx == null || arrPx.length <= col) continue;
							var pal:Array<FlxColor> = (noteData >= 4) ? lanePalPx : arrPx[col];
							var rect:Rectangle = new Rectangle(col * fwPx, row * fhPx, fwPx, fhPx);
							var fb:BitmapData = new BitmapData(fwPx, fhPx, true, 0x00000000);
							fb.copyPixels(pb, rect, new Point(0, 0));
							objects.Note.applyRGBToBitmap(fb, pal[0], pal[1], pal[2]);
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
			// 无 shader（移动端/关 shaders）：仅对"按下/击中帧"（* press / * confirm）逐帧做
			// CPU 矩阵染色（与音符烘焙同算法）；静态帧（arrow*）保持素材原色（灰蓝毛胚，
			// 同桌面 RGB 路径的 static 行为）——彩色动画帧（green/blue/purple/red 音符素材）保持原样。
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
						// Extra Keys：lane ≥ 4 的帧全是循环复用的 0-3 方向帧，按帧名取列色会串到
						// lane 0-3 的调色板 —— 统一改用本 lane 自己的调色板
						var lanePal:Array<FlxColor> = ExtraKeys.laneColors(noteData, PlayState.isPixelStage);
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
							var pal:Array<FlxColor> = (noteData >= 4) ? lanePal : arr[col];
							objects.Note.applyRGBToBitmap(frBmp, pal[0], pal[1], pal[2]);
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
			setGraphicSize(Std.int(width * 0.7 * ExtraKeys.laneScale));

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
		// Extra Keys：布局统一走 ExtraKeys.laneX（keys==4 逐项复现旧常量路径，
		// 含中滚对手 310 / lane>1 加宽屏的旧手调值；keys>4 用泛化居中布局）
		x = ExtraKeys.laneX(x, player == 1, noteData);
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
		// 【视觉修复·判定线】静态帧保持素材原色（灰蓝毛胚），仅按下/击中走 RGB 列色——
		// 与 Psych 0.7.3 / PE 0.6.3 / 原版 FNF 一致。v4 曾把 static 也纳入 RGB 着色，
		// 但默认 NOTE_assets 静态帧是灰蓝色调（实测中心像素 RGB(135,163,173)，非白色），
		// 经 RGB 通道加权后输出粉白/浅青/浅绿/浅粉，即用户反馈的"判定线变色"；
		// 真正"五颜六色"来自 NoteSplash 贴图（已改用 063 预染色皮肤，见 NoteSplash.hx）。
		if(useRGBShader) rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
		// 无 shader（移动端）：静态/按下/确认帧的贴图已由 reloadNote 逐帧矩阵染色
		// （arrow* / * press / * confirm 均染为列色），此处不再叠加 color ——
		// 叠加会与染色帧相乘 → 二次上色发黑/怪异（此前"按下发黑"的根因）。
	}
}
