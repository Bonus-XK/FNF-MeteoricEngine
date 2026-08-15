package animateatlas;
import flixel.util.FlxDestroyUtil;
import openfl.geom.Rectangle;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import openfl.Assets;
import tjson.TJSON as Json;
import openfl.display.BitmapData;
import animateatlas.JSONData.AtlasData;
import animateatlas.JSONData.AnimationData;
import animateatlas.JSONData.SymbolData;
import animateatlas.JSONData.SymbolTimelineData;
import animateatlas.JSONData.LayerData;
import animateatlas.JSONData.LayerFrameData;
import animateatlas.JSONData.ElementData;
import animateatlas.JSONData.Matrix3DData;
import animateatlas.HelperEnums.LoopMode;
import animateatlas.HelperEnums.SymbolType;
import animateatlas.displayobject.SpriteAnimationLibrary;
import animateatlas.displayobject.SpriteMovieClip;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.frames.FlxFrame;

#if html5
import js.html.FileSystem;
import js.html.File;
#else
import sys.FileSystem;
import sys.io.File;
#end

class AtlasFrameMaker extends FlxFramesCollection
{
	//public static var widthoffset:Int = 0;
	//public static var heightoffset:Int = 0;
	//public static var excludeArray:Array<String>;
	/**
	
	* Creates Frames from TextureAtlas(very early and broken ok) Originally made for FNF HD by Smokey and Rozebud
	*
	* @param   key                 The file path.
	* @param   _excludeArray       Use this to only create selected animations. Keep null to create all of them.
	*
	*/

	public static function construct(key:String,?_excludeArray:Array<String> = null, ?noAntialiasing:Bool = false):FlxFramesCollection
	{
		// widthoffset = _widthoffset;
		// heightoffset = _heightoffset;

		var frameCollection:FlxFramesCollection;
		var frameArray:Array<Array<FlxFrame>> = [];

		var animationData:AnimationData;
		var atlasData:AtlasData;
		if (Paths.fileExists('images/$key/spritemap1.json', TEXT))
		{
			// Adobe Animate 2020+ 的 spritemap1 格式：做一次结构转换后再交给原有解析器
			animationData = parseNewAnimation(key);
			atlasData = Json.parse(Paths.getTextFromFile('images/$key/spritemap1.json').replace("\uFEFF", ""));
		}
		else
		{
			animationData = Json.parse(Paths.getTextFromFile('images/$key/Animation.json'));
			atlasData = Json.parse(Paths.getTextFromFile('images/$key/spritemap.json').replace("\uFEFF", ""));
		}

		var graphic:FlxGraphic = getFlxGraphic('$key/spritemap');
		//var graphic:FlxGraphic = Paths.image('$key/spritemap');

		var ss:SpriteAnimationLibrary = new SpriteAnimationLibrary(animationData, atlasData, graphic.bitmap);
		var t:SpriteMovieClip = ss.createAnimation(noAntialiasing);
		if(_excludeArray == null)
		{
			_excludeArray = t.getFrameLabels();
			//trace('creating all anims');
		}
		trace('Creating: ' + _excludeArray);

		frameCollection = new FlxFramesCollection(graphic, FlxFrameCollectionType.IMAGE);
		for(x in _excludeArray)
		{
			frameArray.push(getFramesArray(t, x));
		}

		for(x in frameArray)
		{
			for(y in x)
			{
				frameCollection.pushFrame(y);
			}
		}

		// clear memory
		graphic.bitmap.dispose();
		graphic.bitmap.disposeImage();
		graphic.destroy();
		return frameCollection;
	}

	// ---------- Adobe Animate 2020 (spritemap1) 兼容转换 ----------
	static function parseNewAnimation(key:String):AnimationData
	{
		var raw:Dynamic = Json.parse(Paths.getTextFromFile('images/$key/Animation.json').replace("\uFEFF", ""));
		var framerate:Int = 24;
		if (raw.MD != null && raw.MD.FRT != null) framerate = Std.int(raw.MD.FRT);

		var dictSymbols:Array<Dynamic> = [];
		if (raw.SD != null && raw.SD.S != null)
		{
			var sdS:Array<Dynamic> = cast raw.SD.S;
			for (s in sdS)
				dictSymbols.push(convertNewSymbol(s));
		}

		var animSymbol:SymbolData = convertNewSymbol(raw.AN);
		return cast {
			metadata: { framerate: framerate },
			SYMBOL_DICTIONARY: { Symbols: dictSymbols },
			ANIMATION: animSymbol
		};
	}

	static function convertNewSymbol(s:Dynamic):SymbolData
	{
		return {
			SYMBOL_name: s.SN,
			TIMELINE: convertNewTimeline(s.TL)
		};
	}

	static function convertNewTimeline(tl:Dynamic):SymbolTimelineData
	{
		var layers:Array<LayerData> = [];
		if (tl != null && tl.L != null)
		{
			var tlL:Array<Dynamic> = cast tl.L;
			for (l in tlL)
			{
				var frames:Array<LayerFrameData> = [];
				if (l.FR != null)
				{
					var lFR:Array<Dynamic> = cast l.FR;
					for (f in lFR)
					{
						var elements:Array<ElementData> = [];
						if (f.E != null)
						{
							var fE:Array<Dynamic> = cast f.E;
							for (e in fE)
							{
								var si:Dynamic = e.SI;
								if (si != null)
								{
									elements.push({
										SYMBOL_Instance: {
											SYMBOL_name: si.SN,
											Instance_Name: si.IN != null ? si.IN : '',
											bitmap: { name: '', Position: { x: 0, y: 0 } },
											symbolType: mapSymbolType(si.ST),
											firstFrame: si.FF != null ? Std.int(si.FF) : 0,
											loop: mapLoopMode(si.LP),
											transformationPoint: {
												x: si.TRP != null ? Std.int(si.TRP.x) : 0,
												y: si.TRP != null ? Std.int(si.TRP.y) : 0
											},
											Matrix3D: matrixFromArray(si.M3D)
										}
									});
								}
							}
						}
						frames.push({
							index: f.I != null ? Std.int(f.I) : 0,
							duration: f.DU != null ? Std.int(f.DU) : 1,
							elements: elements
						});
					}
				}
				layers.push({
					Layer_name: l.LN != null ? l.LN : '',
					Frames: frames,
					FrameMap: new Map<Int, LayerFrameData>()
				});
			}
		}
		return {
			sortedForRender: true,
			LAYERS: layers
		};
	}

	static function mapSymbolType(v:Dynamic):String
	{
		if (v == null) return SymbolType.GRAPHIC;
		switch (Std.string(v).toUpperCase())
		{
			case 'M': return SymbolType.MOVIE_CLIP;
			case 'B': return SymbolType.BUTTON;
			default: return SymbolType.GRAPHIC;
		}
	}

	static function mapLoopMode(v:Dynamic):String
	{
		if (v == null) return LoopMode.LOOP;
		switch (Std.string(v).toUpperCase())
		{
			case 'PP': return LoopMode.PLAY_ONCE;
			case 'SF': return LoopMode.SINGLE_FRAME;
			default: return LoopMode.LOOP;
		}
	}

	static function matrixFromArray(arr:Dynamic):Matrix3DData
	{
		if (arr == null || arr.length < 16)
		{
			return {
				m00: 1, m01: 0, m02: 0, m03: 0,
				m10: 0, m11: 1, m12: 0, m13: 0,
				m20: 0, m21: 0, m22: 1, m23: 0,
				m30: 0, m31: 0, m32: 0, m33: 1
			};
		}
		return {
			m00: arr[0], m01: arr[1], m02: arr[2], m03: arr[3],
			m10: arr[4], m11: arr[5], m12: arr[6], m13: arr[7],
			m20: arr[8], m21: arr[9], m22: arr[10], m23: arr[11],
			m30: arr[12], m31: arr[13], m32: arr[14], m33: arr[15]
		};
	}

	static function getFlxGraphic(key:String)
	{
		var bitmap:BitmapData = null;
		var file:String = null;

		#if MODS_ALLOWED
		file = Paths.modsImages(key);
		if (FileSystem.exists(file))
			bitmap = BitmapData.fromFile(file);
		else
		#end
		{
			file = Paths.getPath('images/$key.png', IMAGE);
			if (Assets.exists(file, IMAGE))
				bitmap = Assets.getBitmapData(file);
		}

		if (bitmap != null) return FlxGraphic.fromBitmapData(bitmap, false, file);
		return null;
	}

	@:noCompletion static function getFramesArray(t:SpriteMovieClip,animation:String):Array<FlxFrame>
	{
		var sizeInfo:Rectangle = new Rectangle(0, 0);
		t.currentLabel = animation;
		var bitMapArray:Array<BitmapData> = [];
		var daFramez:Array<FlxFrame> = [];
		var firstPass = true;
		var frameSize:FlxPoint = new FlxPoint(0, 0);

		for (i in t.getFrame(animation)...t.numFrames)
		{
			t.currentFrame = i;
			if (t.currentLabel == animation)
			{
				sizeInfo = t.getBounds(t);
				var bitmapShit:BitmapData = new BitmapData(Std.int(sizeInfo.width + sizeInfo.x), Std.int(sizeInfo.height + sizeInfo.y), true, 0);
				if (ClientPrefs.data.cacheOnGPU)
				{
					var texture:openfl.display3D.textures.RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmapShit.width, bitmapShit.height, BGRA, true);
					texture.uploadFromBitmapData(bitmapShit);
					bitmapShit.image.data = null;
					bitmapShit.dispose();
					bitmapShit.disposeImage();
					bitmapShit = BitmapData.fromTexture(texture);
				}
				bitmapShit.draw(t, null, null, null, null, true);
				bitMapArray.push(bitmapShit);

				if (firstPass)
				{
					frameSize.set(bitmapShit.width,bitmapShit.height);
					firstPass = false;
				}
			}
			else break;
		}
		
		for (i in 0...bitMapArray.length)
		{
			var b = FlxGraphic.fromBitmapData(bitMapArray[i]);
			var theFrame = new FlxFrame(b);
			theFrame.parent = b;
			theFrame.name = animation + i;
			theFrame.sourceSize.set(frameSize.x,frameSize.y);
			theFrame.frame = new FlxRect(0, 0, bitMapArray[i].width, bitMapArray[i].height);
			daFramez.push(theFrame);
			//trace(daFramez);
		}
		return daFramez;
	}
}
