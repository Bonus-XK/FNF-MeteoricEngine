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
		var is2020Format:Bool = Paths.fileExists('images/$key/spritemap1.json', TEXT);
		if (is2020Format)
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

		// 2020 格式的图集文件叫 spritemap1.png（不是 spritemap.png），按格式选
		var graphic:FlxGraphic = getFlxGraphic('$key/' + (is2020Format ? 'spritemap1' : 'spritemap'));
		if (graphic == null)
		{
			// 图集缺失兜底：占位图避免 Null Object Reference 崩溃（角色会显示品红块，便于发现）
			trace('AtlasFrameMaker: missing spritemap graphic for "' + key + '"');
			var placeholder:BitmapData = new BitmapData(1, 1, true, 0xFFFF00FF);
			graphic = FlxGraphic.fromBitmapData(placeholder, false, key + '/spritemap');
		}

		var ss:SpriteAnimationLibrary = new SpriteAnimationLibrary(animationData, atlasData, graphic.bitmap);

		frameCollection = new FlxFramesCollection(graphic, FlxFrameCollectionType.IMAGE);
		if (is2020Format)
		{
			// 2020 格式：动画名 = SD 符号完整路径（Character 配置按 SD.SN 请求，如 "export/BF idle dance"；
			// 帧标签（tags 层 N）是短名，与配置不匹配会导致动画空白/角色不动）
			var raw:Dynamic = Json.parse(Paths.getTextFromFile('images/$key/Animation.json').replace("\uFEFF", ""));
			var sdNames:Array<String> = [];
			if (raw.SD != null && raw.SD.S != null)
			{
				var sdS:Array<Dynamic> = cast raw.SD.S;
				for (s in sdS)
				{
					if (s.SN != null && !sdNames.contains(s.SN)) sdNames.push(s.SN);
				}
			}
			trace('Creating: ' + sdNames);
			for (sn in sdNames)
			{
				var t2:SpriteMovieClip = ss.createAnimation(noAntialiasing, sn);
				if (t2 == null) continue;
				var frames = getSymbolFrames(t2, sn);
				for (f in frames) frameCollection.pushFrame(f);
			}
		}
		else
		{
			var t:SpriteMovieClip = ss.createAnimation(noAntialiasing);
			if(_excludeArray == null)
			{
				_excludeArray = t.getFrameLabels();
				//trace('creating all anims');
			}
			trace('Creating: ' + _excludeArray);

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
											// 符号实例没有位图：必须为 null，否则 setBitmap('') 会查不到 sprite 而崩溃
											bitmap: null,
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
								else
								{
									// Adobe Animate 2020+ 的位图元素（ASI = Atlas Sprite Instance）：
									// {"ASI": {"N": 精灵名, "M3D": [4x4 矩阵]}} —— 平移在 M3D[12]/[13]（m30/m31）
									// 转成旧格式的 ATLAS_SPRITE_instance，preprocessSymbolData 会再转成符号位图
									var asi:Dynamic = e.ASI;
									if (asi != null)
									{
										var posX:Float = 0;
										var posY:Float = 0;
										var m3d:Dynamic = asi.M3D;
										if (m3d != null && m3d.length >= 14)
										{
											posX = m3d[12];
											posY = m3d[13];
										}
										elements.push({
											ATLAS_SPRITE_instance: {
												name: asi.N != null ? asi.N : '',
												Position: { x: Std.int(posX), y: Std.int(posY) }
											}
										});
									}
								}
							}
						}
						frames.push({
							name: f.N != null ? Std.string(f.N) : null, // 帧标签（tags 层的动画名，如 "dance left"）
							index: f.I != null ? Std.int(f.I) : 0,
							duration: f.DU != null ? Std.int(f.DU) : 1,
							elements: elements
						});
					}
				}
				layers.push({
					Layer_name: l.LN != null ? l.LN : '',
					Frames: frames,
					// 必须为 null：SpriteSymbol 构造时若 FrameMap != null 会误判为"已构建缓存"而跳过构建，
					// 导致 getFrameData 永远查不到帧数据（角色渲染全空/黑块）
					FrameMap: null
				});
			}
		}
		// Animate 层序是"前→后"，渲染端需要"后→前"（与旧格式一致，由 preprocessSymbolData 反转）
		return {
			sortedForRender: false,
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
	{		var sizeInfo:Rectangle = new Rectangle(0, 0);
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
				// 画布必须包含负坐标内容（角色锚点在脚底时头部位于负区）：
				// 原逻辑用 width+x 会把负区裁掉导致帧全空/黑块
				var offX:Float = sizeInfo.x < 0 ? -sizeInfo.x : 0;
				var offY:Float = sizeInfo.y < 0 ? -sizeInfo.y : 0;
				var bitmapShit:BitmapData = new BitmapData(Std.int(sizeInfo.width + offX), Std.int(sizeInfo.height + offY), true, 0);
				if (ClientPrefs.data.cacheOnGPU)
				{
					var texture:openfl.display3D.textures.RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmapShit.width, bitmapShit.height, BGRA, true);
					texture.uploadFromBitmapData(bitmapShit);
					bitmapShit.image.data = null;
					bitmapShit.dispose();
					bitmapShit.disposeImage();
					bitmapShit = BitmapData.fromTexture(texture);
				}
				bitmapShit.draw(t, new openfl.geom.Matrix(1, 0, 0, 1, offX, offY), null, null, null, true);
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

	/**
	 * 2020 格式：渲染一个 SD 符号的全部帧（动画名 = 符号完整路径 SD.SN）。
	 * 统一画布：动画期间角色移动/部件变化会使各帧 bounds 不同，若每帧单独建画布，
	 * 内容在帧内位置会跳动（表现为"滑铲"）。这里先扫一遍取整个动画的统一边界，
	 * 所有帧用同一画布 + 同一平移，帧间内容相对位置固定。
	 */
	static function getSymbolFrames(t:SpriteMovieClip, symbolName:String):Array<FlxFrame>
	{
		var daFramez:Array<FlxFrame> = [];
		var numFrames:Int = t.numFrames;

		// 1) 统一边界（整个动画的最小/最大范围）
		var minX:Float = 0;
		var minY:Float = 0;
		var maxX:Float = 0;
		var maxY:Float = 0;
		for (i in 0...numFrames)
		{
			t.currentFrame = i;
			var sb:Rectangle = t.getBounds(t);
			if (i == 0)
			{
				minX = sb.x; minY = sb.y;
				maxX = sb.x + sb.width; maxY = sb.y + sb.height;
			}
			else
			{
				if (sb.x < minX) minX = sb.x;
				if (sb.y < minY) minY = sb.y;
				if (sb.x + sb.width > maxX) maxX = sb.x + sb.width;
				if (sb.y + sb.height > maxY) maxY = sb.y + sb.height;
			}
		}
		var canvasW:Int = Std.int(maxX - minX);
		var canvasH:Int = Std.int(maxY - minY);
		if (canvasW < 1) canvasW = 1;
		if (canvasH < 1) canvasH = 1;
		var offX:Float = minX < 0 ? -minX : 0;
		var offY:Float = minY < 0 ? -minY : 0;

		// 2) 每帧用统一画布 + 统一平移绘制
		var bitMapArray:Array<BitmapData> = [];
		for (i in 0...numFrames)
		{
			t.currentFrame = i;
			var bitmapShit:BitmapData = new BitmapData(canvasW, canvasH, true, 0);
			bitmapShit.draw(t, new openfl.geom.Matrix(1, 0, 0, 1, offX, offY), null, null, null, true);


			if (ClientPrefs.data.cacheOnGPU)
			{
				var texture:openfl.display3D.textures.RectangleTexture = FlxG.stage.context3D.createRectangleTexture(canvasW, canvasH, BGRA, true);
				texture.uploadFromBitmapData(bitmapShit);
				bitmapShit.image.data = null;
				bitmapShit.dispose();
				bitmapShit.disposeImage();
				bitmapShit = BitmapData.fromTexture(texture);
			}
			bitMapArray.push(bitmapShit);
		}

		for (i in 0...bitMapArray.length)
		{
			var b = FlxGraphic.fromBitmapData(bitMapArray[i]);
			var theFrame = new FlxFrame(b);
			theFrame.parent = b;
			theFrame.name = symbolName + i;
			theFrame.sourceSize.set(canvasW, canvasH);
			theFrame.frame = new FlxRect(0, 0, canvasW, canvasH);
			// 帧内容相对 sprite 原点的固定偏移（负 = 内容在锚点左上；全动画统一，不会跳动）
			theFrame.offset.set(-offX, -offY);
			daFramez.push(theFrame);
		}
		return daFramez;
	}
}
