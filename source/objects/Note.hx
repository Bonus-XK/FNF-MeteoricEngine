package objects;

// If you want to make a custom note type, you should search for:
// "function set_noteType"

import backend.NoteTypesConfig;
import backend.StageData;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;
import objects.StrumNote;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.graphics.frames.FlxFramesCollection;
import flixel.math.FlxRect;
import flixel.util.FlxSpriteUtil;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.geom.Matrix;
import openfl.utils.ByteArray;
import openfl.utils.Assets as OpenFlAssets;

#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

typedef EventNote = {
	strumTime:Float,
	event:String,
	value1:String,
	value2:String
}

typedef NoteSplashData = {
	disabled:Bool,
	texture:String,
	useGlobalShader:Bool, //breaks r/g/b/a but makes it copy default colors for your custom note
	useRGBShader:Bool,
	antialiasing:Bool,
	r:FlxColor,
	g:FlxColor,
	b:FlxColor,
	a:Float
}

class Note extends FlxSprite
{
	public var strumTime:Float = 0;
	public var mustPress:Bool = false;
	public var noteData:Int = 0;
	public var chartSeq:Int = -1; // 谱面中的唯一序号（回放录制/匹配用，Lua 动态生成的音符为 -1）
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;
	public var wasGoodHit:Bool = false;
	public var ignoreNote:Bool = false;
	public var hitByOpponent:Bool = false;
	public var noteWasHit:Bool = false;
	public var prevNote:Note;
	public var nextNote:Note;

	public var spawned:Bool = false;

	public var parent:Note;
	public var blockHit:Bool = false; // only works for player

	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	public var noteType(default, set):String = null;

	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';

	public var rgbShader:RGBShaderReference;
	public static var globalRgbShaders:Array<RGBPalette> = [];
	public var inEditor:Bool = false;

	public var animSuffix:String = '';
	public var gfNote:Bool = false;
	public var earlyHitMult:Float = 1;
	public var lateHitMult:Float = 1;
	public var lowPriority:Bool = false;

	public static var SUSTAIN_SIZE:Int = 44;
	public static var swagWidth:Float = 160 * 0.7;
	public static var colArray:Array<String> = ['purple', 'blue', 'green', 'red'];
	// 提前渲染的贴图种类：0 箭头 / 1 长条体 / 2 长条尾
	public static inline var BAKE_NOTE:Int = 0;
	public static inline var BAKE_HOLD:Int = 1;
	public static inline var BAKE_HOLDEND:Int = 2;
	// Phigros 玩法表演块：无长条=黄色，带长条=青色
	public static var phigrosPerformColor:FlxColor = 0xFFFFE600;
	public static var phigrosPerformHoldColor:FlxColor = 0xFF00E5FF;

	public static var defaultNoteSkin(default, never):String = 'noteSkins/NOTE_assets';

	// 大谱面优化：同一音符皮肤只解析一次图集/贴图，全部音符共享
	static var noteFramesCache:Map<String, FlxAtlasFrames> = [];
	static var phigrosGraphicCache:Map<String, FlxGraphic> = [];
	// 烘焙专用 CPU 位图/图集缓存（cacheOnGPU 开启时引擎位图不可读，需从资产库重新读取一次并复用）
	static var bakeBitmapCache:Map<String, BitmapData> = [];
	static var bakeAtlasCache:Map<String, FlxAtlasFrames> = [];
	// 提前渲染：加载曲目时烘焙好的音符静态贴图（键 = 加载路径|列|种类|颜色），游戏中直接复用
	static var bakedNoteGraphics:Map<String, FlxGraphic> = [];
	// loadPath → 箭头帧渲染宽（烘焙长条居中补偿用）
	static var bakedArrowRenderWidth:Map<String, Float> = [];
	// 最近一次烘焙对应的谱面指纹（皮肤/颜色/音符类型任一变化都会重新烘焙）
	static var bakedChartSignature:String = null;
	// 自动游玩预演：加载时按谱面预演一遍 botplay，记录每轨道玩家侧音符（含长条段）的命中时刻
	static var botplayLanes:Array<Array<Float>> = null;
	static var botplaySignature:String = null;

	static function __init__()
	{
		Paths.addMemoryCleanCallback(clearNoteCaches);
	}

	// 全局清缓存时调用：丢弃引用了已销毁图形的缓存
	public static function clearNoteCaches()
	{
		noteFramesCache = [];
		phigrosGraphicCache = [];
		bakeBitmapCache = [];
		bakeAtlasCache = [];
	}

	// 获取/构建共享的 Phigros 表演图形（圆角矩形，绘制一次，全部音符复用）
	static function getPhigrosGraphic(key:String, w:Int, h:Int, radius:Float, col:FlxColor, ?inner:Bool = false):FlxGraphic
	{
		var graphic:FlxGraphic = phigrosGraphicCache.get(key);
		if (graphic == null)
		{
			var tmp:FlxSprite = new FlxSprite().makeGraphic(w, h, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(tmp, 0, 0, w, h, radius, radius, col);
			if (inner)
				FlxSpriteUtil.drawRoundRect(tmp, 6, 6, w - 12, h - 12, 9, 9, 0x38FFFFFF);
			graphic = tmp.graphic;
			graphic.persist = true;
			graphic.destroyOnNoUse = false;
			phigrosGraphicCache.set(key, graphic);
		}
		return graphic;
	}

	// 懒加载：大部分音符（尤其大谱面未击打音符）不需要特效数据，构造时不分配
	public var noteSplashData(get, never):NoteSplashData;
	var _noteSplashData:NoteSplashData = null;
	var splashSkin:String = null;

	function get_noteSplashData():NoteSplashData
	{
		if (_noteSplashData == null)
		{
			_noteSplashData = {
				disabled: false,
				texture: splashSkin,
				antialiasing: !PlayState.isPixelStage,
				useGlobalShader: false,
				useRGBShader: (PlayState.SONG != null) ? !(PlayState.SONG.disableNoteRGB == true) : true,
				r: -1,
				g: -1,
				b: -1,
				a: ClientPrefs.data.splashAlpha
			};
		}
		return _noteSplashData;
	}

	// 懒加载：只有带长条的箭头才需要 tail
	public var tail(get, never):Array<Note>;
	var _tail:Array<Note> = null;
	function get_tail():Array<Note>
	{
		if (_tail == null) _tail = [];
		return _tail;
	}

	// 懒加载：自定义音符类型才需要 extraData
	public var extraData(get, never):Map<String, Dynamic>;
	var _extraData:Map<String, Dynamic> = null;
	function get_extraData():Map<String, Dynamic>
	{
		if (_extraData == null) _extraData = new Map<String, Dynamic>();
		return _extraData;
	}

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var offsetAngle:Float = 0;
	public var multAlpha:Float = 1;
	public var multSpeed(default, set):Float = 1;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;

	public var hitHealth:Float = 0.023;
	public var missHealth:Float = 0.0475;
	public var rating:String = 'unknown';
	public var ratingMod:Float = 0; //9 = unknown, 0.25 = shit, 0.5 = bad, 0.75 = good, 1 = sick
	public var ratingDisabled:Bool = false;

	public var texture(default, set):String = null;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var hitCausesMiss:Bool = false;
	public var distance:Float = 2000; //plan on doing scroll directions soon -bb
	public var bakedKind:Int = -1; // 提前渲染：-1 未烘焙 / 0 箭头 / 1 长条体 / 2 长条尾
	var bakedKey:String = null; // 烘焙贴图键缓存（构造函数算一次，类型未改色时复用，避免每音符重复拼接字符串）
	var bakedLoadPath:String = null;
	var bakedR:FlxColor = 0;
	var bakedG:FlxColor = 0;
	var bakedB:FlxColor = 0;
	var _dirCos:Float = 1; // 轨道方向三角函数缓存（堆叠大谱面避免每音符每帧重复计算）
	var _dirSin:Float = 0;
	var _dirCached:Float = -99999;

	// 加载阶段烘焙好的静态贴图：整场共用同一张 FlxGraphic，loadGraphic 注册进每音符的图集并拷贝帧
	inline function useBakedGraphic(baked:FlxGraphic, kind:Int):Void
	{
		loadGraphic(baked, true, Std.int(baked.width), Std.int(baked.height));
		bakedKind = kind;
	}

	public var hitsoundDisabled:Bool = false;
	public var hitsoundChartEditor:Bool = true;
	public var hitsound:String = 'hitsound';

	private function set_multSpeed(value:Float):Float {
		resizeByRatio(value / multSpeed);
		multSpeed = value;
		//trace('fuck cock');
		return value;
	}

	public function resizeByRatio(ratio:Float) //haha funny twitter shit
	{
		if(isSustainNote && bakedKind == BAKE_HOLD)
		{
			scale.y *= ratio;
			updateHitbox();
			return;
		}
		if(isSustainNote && animation.curAnim != null && !animation.curAnim.name.endsWith('end'))
		{
			scale.y *= ratio;
			updateHitbox();
		}
	}

	private function set_texture(value:String):String {
		if(texture != value) reloadNote(value);

		texture = value;
		return value;
	}

	public function defaultRGB()
	{
		var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[noteData];
		if(PlayState.isPixelStage) arr = ClientPrefs.data.arrowRGBPixel[noteData];

		if (noteData > -1 && noteData <= arr.length)
		{
			rgbShader.r = arr[0];
			rgbShader.g = arr[1];
			rgbShader.b = arr[2];
		}
	}

	private function set_noteType(value:String):String {
		splashSkin = PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes';
		defaultRGB();

		if(noteData > -1 && noteType != value) {
			switch(value) {
				case 'Hurt Note':
					ignoreNote = mustPress;
					//reloadNote('HURTNOTE_assets');
					//this used to change the note texture to HURTNOTE_assets.png,
					//but i've changed it to something more optimized with the implementation of RGBPalette:

					// note colors
					rgbShader.r = 0xFF101010;
					rgbShader.g = 0xFFFF0000;
					rgbShader.b = 0xFF990022;

					// splash data and colors
					noteSplashData.r = 0xFFFF0000;
					noteSplashData.g = 0xFF101010;
					noteSplashData.texture = 'noteSplashes/noteSplashes-electric';

					// gameplay data
					lowPriority = true;
					missHealth = isSustainNote ? 0.25 : 0.1;
					hitCausesMiss = true;
					hitsound = 'cancelMenu';
					hitsoundChartEditor = false;
				case 'Alt Animation':
					animSuffix = '-alt';
				case 'No Animation':
					noAnimation = true;
					noMissAnimation = true;
				case 'GF Sing':
					gfNote = true;
			}
			if (value != null && value.length > 1) NoteTypesConfig.applyNoteTypeData(this, value);
			if (hitsound != 'hitsound' && ClientPrefs.data.hitsoundVolume > 0) Paths.sound(hitsound); //precache new sound for being idiot-proof
			noteType = value;
			tryUseBakedGraphic(); // 提前渲染：类型颜色/贴图生效后，换用对应的烘焙静态贴图
		}
		return value;
	}

	public function new(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?inEditor:Bool = false, ?createdFrom:Dynamic = null)
	{
		super();

		antialiasing = ClientPrefs.data.antialiasing;
		if(createdFrom == null) createdFrom = PlayState.instance;

		if (prevNote == null)
			prevNote = this;

		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.inEditor = inEditor;
		this.moves = false;

		x += (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;
		this.strumTime = strumTime;
		if(!inEditor) this.strumTime += ClientPrefs.data.noteOffset;

		this.noteData = noteData;

		if(noteData > -1) {
			texture = '';
			rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(noteData));
			if(ClientPrefs.data.phigrosStyle) rgbShader.enabled = false; // Phigros 方块颜色直接绘制，不受 RGB 着色
			else if(PlayState.SONG != null && PlayState.SONG.disableNoteRGB) rgbShader.enabled = false;
			else if (bakedKind >= 0) rgbShader.enabled = false; // 提前渲染：颜色已烘焙进贴图，不再叠加 RGB 着色器（叠加会钳制成白色）

			x += swagWidth * (noteData);
			if(!isSustainNote && noteData < colArray.length) { //Doing this 'if' check to fix the warnings on Senpai songs
				var animToPlay:String = '';
				animToPlay = colArray[noteData % colArray.length];
				if (bakedKind < 0) {
					animation.play(animToPlay + 'Scroll');
				}
			}
		}

		if(prevNote != null)
			prevNote.nextNote = this;

		if (isSustainNote && prevNote != null)
		{
			alpha = 0.6;
			multAlpha = 0.6;
			hitsoundDisabled = true;
			if(ClientPrefs.data.downScroll) flipY = true;

			var alignOffset:Float = 0;
			if (bakedKind >= 0)
			{
				// 烘焙长条贴图宽度 = 长条帧宽（50），而原版机制靠“图集第一帧=箭头帧（154）”产生居中补偿；
				// 提前渲染跳过了图集，这里显式补上 (箭头渲染宽 - 长条渲染宽) / 2 使长条与箭头同轴居中
				var arrowW:Float = bakedArrowRenderWidth.get(getNoteSkinLoadPath(texture, '', PlayState.isPixelStage, true));
				if (arrowW > 0) alignOffset = (arrowW - width) / 2;
			}
			offsetX += width / 2;
			copyAngle = false;

			if (bakedKind < 0) animation.play(colArray[noteData % colArray.length] + 'holdend');

			updateHitbox();

			offsetX -= width / 2;
			offsetX += alignOffset;

			if (PlayState.isPixelStage)
				offsetX += 30;

			if (prevNote.isSustainNote)
			{
				if (prevNote.bakedKind >= 0)
					prevNote.useBakedSustainBody(); // 提前渲染：长条尾 → 长条体贴图
				else
					prevNote.animation.play(colArray[prevNote.noteData % colArray.length] + 'hold');

				prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.05;
				if(createdFrom != null && createdFrom.songSpeed != null) prevNote.scale.y *= createdFrom.songSpeed;

				if(PlayState.isPixelStage) {
					prevNote.scale.y *= 1.19;
					prevNote.scale.y *= (6 / height); //Auto adjust note size
				}
				prevNote.updateHitbox();
				// prevNote.setGraphicSize();
			}

			if(PlayState.isPixelStage)
			{
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
			earlyHitMult = 0;
		}
		else if(!isSustainNote)
		{
			// 普通烘焙音符在 reloadNote 里已做过居中（像素舞台没有，保持原逻辑）
			if (bakedKind < 0 || PlayState.isPixelStage)
			{
				centerOffsets();
				centerOrigin();
			}
		}
		x += offsetX;
	}

	public static function initializeGlobalRGBShader(noteData:Int)
	{
		if(globalRgbShaders[noteData] == null)
		{
			var newRGB:RGBPalette = new RGBPalette();
			globalRgbShaders[noteData] = newRGB;

			var arr:Array<FlxColor> = (!PlayState.isPixelStage) ? ClientPrefs.data.arrowRGB[noteData] : ClientPrefs.data.arrowRGBPixel[noteData];
			if (noteData > -1 && noteData <= arr.length)
			{
				newRGB.r = arr[0];
				newRGB.g = arr[1];
				newRGB.b = arr[2];
			}
		}
		return globalRgbShaders[noteData];
	}

	var _lastNoteOffX:Float = 0;
	static var _lastValidChecked:String; //optimization
	public var originalHeight:Float = 6;
	public var correctionOffset:Float = 0; //dont mess with this
	public function reloadNote(texture:String = '', postfix:String = '') {
		if (ClientPrefs.data.phigrosStyle)
		{
			loadPhigrosNote();
			return;
		}
		if(texture == null) texture = '';
		if(postfix == null) postfix = '';

		// 实际加载路径（含像素前缀 / ENDS 后缀 / 自定义皮肤后缀），烘焙与正式加载共用同一解析
		var loadPath:String = getNoteSkinLoadPathCached(texture, postfix, PlayState.isPixelStage, isSustainNote);

		var animName:String = null;
		if(animation.curAnim != null) {
			animName = animation.curAnim.name;
		}

		var lastScaleY:Float = scale.y;

		// 提前渲染：命中加载阶段烘焙好的静态贴图 → 跳过图集解析/动画/RGB 着色器（大谱面堆叠下渲染开销最低）
		if (ClientPrefs.data.preRenderNotes && !inEditor && noteData > -1)
		{
			var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
			var arr:Array<FlxColor> = (loadPath.startsWith('pixelUI/') ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB)[noteData];
			bakedLoadPath = loadPath;
			bakedR = arr[0];
			bakedG = arr[1];
			bakedB = arr[2];
			bakedKey = getBakedNoteKey(loadPath, noteData, isSustainNote ? BAKE_HOLDEND : BAKE_NOTE, bakedR, bakedG, bakedB, useRGB);
			var baked:FlxGraphic = bakedNoteGraphics.get(bakedKey);
			if (baked != null)
			{
				useBakedGraphic(baked, isSustainNote ? BAKE_HOLDEND : BAKE_NOTE);
				if (rgbShader != null) rgbShader.enabled = false; // 颜色已烘焙进贴图，关闭 RGB 着色器防叠加变白
				antialiasing = PlayState.isPixelStage ? false : ClientPrefs.data.antialiasing;
				if (PlayState.isPixelStage)
				{
					setGraphicSize(Std.int(width * PlayState.daPixelZoom));
					if (isSustainNote)
					{
						offsetX += _lastNoteOffX;
						_lastNoteOffX = (width - 7) * (PlayState.daPixelZoom / 2);
						offsetX -= _lastNoteOffX;
					}
				}
				else
				{
					setGraphicSize(Std.int(width * 0.7));
					if (!isSustainNote)
					{
						centerOffsets();
						centerOrigin();
					}
				}
				if (isSustainNote) scale.y = lastScaleY;
				updateHitbox();
				return;
			}
			else
			{
				bakedKind = -1;
			}
		}

		if(PlayState.isPixelStage) {
			if(isSustainNote) {
				var graphic = Paths.image(loadPath);
				loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 2));
				originalHeight = graphic.height / 2;
			} else {
				var graphic = Paths.image(loadPath);
				loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			}
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));
			loadPixelNoteAnims();
			antialiasing = false;

			if(isSustainNote) {
				offsetX += _lastNoteOffX;
				_lastNoteOffX = (width - 7) * (PlayState.daPixelZoom / 2);
				offsetX -= _lastNoteOffX;
			}
		} else {
			// 同一皮肤只解析一次图集（XML 读盘 + 帧构建），大谱面下避免重复 6 万次
			var atlas:FlxAtlasFrames = noteFramesCache.get(loadPath);
			if (atlas == null)
			{
				atlas = Paths.getSparrowAtlas(loadPath);
				noteFramesCache.set(loadPath, atlas);
			}
			frames = atlas;
			loadNoteAnims();
			if(!isSustainNote)
			{
				centerOffsets();
				centerOrigin();
			}
		}

		if(isSustainNote) {
			scale.y = lastScaleY;
		}
		updateHitbox();

		if(animName != null)
			animation.play(animName, true);
	}

	// Phigros 玩法渲染：不加载箭头贴图，直接绘制彩色圆角方块 / 长条
	function loadPhigrosNote():Void
	{
		// RGB 着色会覆盖方块颜色，Phigros 玩法下直接禁用
		if (rgbShader != null) rgbShader.enabled = false;

		if (isSustainNote)
		{
			// 初始高度 = SUSTAIN_SIZE(44)：与 Psych 段拉伸逻辑（stepCrochet 比例）自洽
			// 表演块长条为青色（宽度与主表演块一致），玩家长条为轨道 note 颜色
			var w:Int = mustPress ? 24 : 56;
			var h:Int = SUSTAIN_SIZE;
			var col:FlxColor = mustPress ? getPhigrosColor() : phigrosPerformHoldColor;
			loadGraphic(getPhigrosGraphic('sustain|' + col, w, h, 8, col));
			alpha = 0.6;
			multAlpha = 0.6;
		}
		else if (!mustPress)
		{
			// 表演块：横向细条（与判定线同高 5px，宽度与长条一致），默认黄色（带长条时由 generateNotes 重绘为青色）
			var w:Int = 56;
			var h:Int = 5;
			loadGraphic(getPhigrosGraphic('perform|' + phigrosPerformColor, w, h, 2.5, phigrosPerformColor));
			centerOffsets();
			centerOrigin();
		}
		else
		{
			var w:Int = 56;
			var h:Int = 56;
			loadGraphic(getPhigrosGraphic('note|' + getPhigrosColor(), w, h, 14, getPhigrosColor(), true));
			centerOffsets();
			centerOrigin();
		}
		updateHitbox();
	}

	// 表演块带长条时调用：主块重绘为青色长条型
	public function repaintPhigrosPerform(hasHold:Bool):Void
	{
		if (isSustainNote || mustPress) return;
		var w:Int = 56;
		var h:Int = 5;
		var col:FlxColor = hasHold ? phigrosPerformHoldColor : phigrosPerformColor;
		loadGraphic(getPhigrosGraphic('perform|' + col, w, h, 2.5, col));
		centerOffsets();
		centerOrigin();
		updateHitbox();
	}

	inline function getPhigrosColor():FlxColor
	{
		// 玩家与对手表演块统一使用设置中的 note 颜色（arrowRGB 主色）
		var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[noteData % ClientPrefs.data.arrowRGB.length];
		return arr[0];
	}

	public static function getNoteSkinPostfix()
	{
		var skin:String = '';
		if(ClientPrefs.data.noteSkin != ClientPrefs.defaultData.noteSkin)
			skin = '-' + ClientPrefs.data.noteSkin.trim().toLowerCase().replace(' ', '_');
		return skin;
	}

	// 音符皮肤最终加载路径（含像素前缀 / ENDS 后缀 / 自定义皮肤后缀），烘焙与正式加载共用同一解析
	static function getNoteSkinLoadPath(texture:String, postfix:String = '', pixelStage:Bool = false, isSustain:Bool = false):String
	{
		var skin:String = texture + postfix;
		if(texture.length < 1) {
			skin = PlayState.SONG != null ? PlayState.SONG.arrowSkin : null;
			if(skin == null || skin.length < 1)
				skin = defaultNoteSkin + postfix;
		}

		var skinPostfix:String = getNoteSkinPostfix();
		var customSkin:String = skin + skinPostfix;
		var pathPrefix:String = pixelStage ? 'pixelUI/' : '';
		if(customSkin == _lastValidChecked || Paths.fileExists('images/' + pathPrefix + customSkin + '.png', IMAGE))
			_lastValidChecked = customSkin;
		else
			skinPostfix = '';
		// 像素长条用 ENDS 图集（pixelUI 下存在）；普通长条与箭头共用同一图集（内含 hold piece/end 帧）
		return pathPrefix + skin + (pixelStage && isSustain ? 'ENDS' : '') + skinPostfix;
	}

	// 同谱面内所有音符的皮肤路径完全一致：缓存最近一次结果，避免每音符重复拼接字符串
	static var _lpTex:String = null;
	static var _lpPost:String = null;
	static var _lpPixel:Bool = false;
	static var _lpSustain:Bool = false;
	static var _lpPath:String = null;
	static function getNoteSkinLoadPathCached(texture:String, postfix:String, pixelStage:Bool, isSustain:Bool):String
	{
		if (texture == _lpTex && postfix == _lpPost && pixelStage == _lpPixel && isSustain == _lpSustain && _lpPath != null)
			return _lpPath;
		_lpTex = texture;
		_lpPost = postfix;
		_lpPixel = pixelStage;
		_lpSustain = isSustain;
		return _lpPath = getNoteSkinLoadPath(texture, postfix, pixelStage, isSustain);
	}

	// 烘焙贴图键：加载路径|列|种类|颜色（disableNoteRGB 时固定为 raw，不做着色）
	static function getBakedNoteKey(loadPath:String, col:Int, kind:Int, r:FlxColor, g:FlxColor, b:FlxColor, useRGB:Bool):String
	{
		return loadPath + '|' + col + '|' + kind + '|' + (useRGB ? (r + ':' + g + ':' + b) : 'raw');
	}

	// 按默认箭头颜色查找烘焙贴图（音符构造函数里 RGB 着色器尚未创建时使用）
	static function getBakedNoteGraphic(loadPath:String, col:Int, kind:Int):FlxGraphic
	{
		var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
		var arr:Array<FlxColor> = (loadPath.startsWith('pixelUI/') ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB)[col];
		var key:String = getBakedNoteKey(loadPath, col, kind, arr[0], arr[1], arr[2], useRGB);
		var g:FlxGraphic = bakedNoteGraphics.get(key);
		return g;
	}

	// 自定义音符类型设置完贴图/颜色后调用：把当前音符换成对应烘焙贴图
	public function tryUseBakedGraphic():Void
	{
		if (!ClientPrefs.data.preRenderNotes || inEditor || rgbShader == null || noteData < 0) return;
		var pixelStage:Bool = PlayState.isPixelStage;
		var loadPath:String = bakedLoadPath != null ? bakedLoadPath : getNoteSkinLoadPathCached(texture, '', pixelStage, isSustainNote);
		var kind:Int = bakedKind >= 0 ? bakedKind : (isSustainNote ? BAKE_HOLDEND : BAKE_NOTE);
		var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
		var key:String = (bakedKey != null && rgbShader.r == bakedR && rgbShader.g == bakedG && rgbShader.b == bakedB)
			? bakedKey
			: getBakedNoteKey(loadPath, noteData, kind, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
		var baked:FlxGraphic = bakedNoteGraphics.get(key);
		if (baked == null) return;
		// 构造函数里 reloadNote 已加载同一张烘焙贴图（默认颜色键一致）→ 直接跳过重复加载
		if (graphic == baked)
		{
			bakedKind = kind;
			return;
		}
		useBakedGraphic(baked, kind);
		rgbShader.enabled = false; // 颜色已烘焙进贴图，关闭 RGB 着色器防叠加变白
		antialiasing = pixelStage ? false : ClientPrefs.data.antialiasing;
		updateHitbox();
	}

	// 长条体的下一段生成时：把上一段从“长条尾”换成“长条体”烘焙贴图
	public function useBakedSustainBody():Void
	{
		if (bakedKind != BAKE_HOLDEND || rgbShader == null) return;
		var loadPath:String = getNoteSkinLoadPath(texture, '', PlayState.isPixelStage, true);
		var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
		var baked:FlxGraphic = bakedNoteGraphics.get(getBakedNoteKey(loadPath, noteData, BAKE_HOLD, rgbShader.r, rgbShader.g, rgbShader.b, useRGB));
		if (baked == null) return;
		useBakedGraphic(baked, BAKE_HOLD);
		rgbShader.enabled = false; // 颜色已烘焙进贴图，关闭 RGB 着色器防叠加变白
	}

	// 舞台是否为像素风（与 PlayState 的 stageUI 判定逻辑一致）
	static function getChartPixelStage():Bool
	{
		if (PlayState.SONG == null) return false;
		var stage:String = PlayState.SONG.stage;
		if (stage == null || stage.length < 1) stage = StageData.vanillaSongStage(PlayState.SONG.song);
		var stageFile:backend.StageFile = StageData.getStageFile(stage);
		if (stageFile == null) return false;
		if (stageFile.stageUI != null && stageFile.stageUI.trim().length > 0)
			return stageFile.stageUI == 'pixel';
		return stageFile.isPixelStage == true;
	}

	// 当前谱面 + 设置的烘焙指纹：皮肤、颜色、音符类型、像素舞台任一变化都会触发重新烘焙
	static function currentChartSignature():String
	{
		var pixelStage:Bool = getChartPixelStage();
		var types:Array<String> = [];
		if (PlayState.SONG.notes != null)
		{
			for (section in PlayState.SONG.notes)
			{
				if (section.sectionNotes == null) continue;
				for (note in section.sectionNotes)
				{
					var t:String = Std.string(note[3]);
					if (!types.contains(t)) types.push(t);
				}
			}
		}
		types.sort(Reflect.compare);

		var skin:String = (PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 0) ? PlayState.SONG.arrowSkin : defaultNoteSkin;
		var sig:String = PlayState.SONG.song + '|' + (pixelStage ? 'p' : 'n') + '|' + skin + '|' + ClientPrefs.data.noteSkin + '|'
			+ types.join(',') + '|' + (PlayState.SONG.disableNoteRGB == true ? 'rgb0' : 'rgb1') + '|';
		var colors:Array<Array<FlxColor>> = pixelStage ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB;
		for (c in colors)
			for (v in c)
				sig += v + ',';
		return sig;
	}

	// 该谱面的烘焙是否已全部完成（完成时可跳过加载界面快速进入）
	public static function chartBakesReady():Bool
	{
		if (PlayState.SONG == null) return false;
		if (ClientPrefs.data.phigrosStyle) return true; // Phigros 音符本来就是静态贴图，无需烘焙
		return bakedChartSignature != null && bakedChartSignature == currentChartSignature()
			&& botplaySignature != null && botplaySignature == currentChartSignature();
	}

	// 加载曲目时调用：扫描谱面用到的音符类型，烘焙所有可能出现的音符贴图
	public static function preRenderChartNotes():Void
	{
		if (PlayState.SONG == null) return;
		if (ClientPrefs.data.phigrosStyle)
		{
			bakedChartSignature = currentChartSignature();
			return;
		}

		var pixelStage:Bool = getChartPixelStage();

		// 收集谱面用到的 noteType（含默认类型）
		var types:Array<String> = [''];
		if (PlayState.SONG.notes != null)
		{
			for (section in PlayState.SONG.notes)
			{
				if (section.sectionNotes == null) continue;
				for (note in section.sectionNotes)
				{
					var t:String = Std.string(note[3]);
					if (t == 'null') t = '';
					if (!types.contains(t)) types.push(t);
				}
			}
		}

		// 探针解析期间临时对齐 PlayState.stageUI（进入 PlayState 前它还是默认值），
		// 确保像素色组（arrowRGBPixel）与皮肤路径（pixelUI/ 前缀）和游戏内解析完全一致
		var oldUI:String = PlayState.stageUI;
		PlayState.stageUI = pixelStage ? 'pixel' : 'normal';
		try
		{
			for (type in types)
			{
				for (col in 0...4)
				{
					// 用一次性探针音符解析该类型最终的皮肤与颜色（与正式生成完全同一路径）
					var probe:Note = new Note(0, col, null, false, true);
					if (type != null && type.length > 0) probe.noteType = type;

					var useRGB:Bool = !(PlayState.SONG.disableNoteRGB == true);
					var rr:FlxColor = (useRGB && probe.rgbShader != null) ? probe.rgbShader.r : 0;
					var gg:FlxColor = (useRGB && probe.rgbShader != null) ? probe.rgbShader.g : 0;
					var bb:FlxColor = (useRGB && probe.rgbShader != null) ? probe.rgbShader.b : 0;

					for (kind in 0...3)
					{
						var kindPath:String = pixelStage ? getNoteSkinLoadPath(probe.texture, '', true, kind != BAKE_NOTE) : getNoteSkinLoadPath(probe.texture, '', false, false);
						bakeNoteAppearance(kindPath, pixelStage, col, kind, rr, gg, bb, useRGB);
					}
					probe.destroy();
				}
			}
		}
		catch (e:Dynamic)
		{
			PlayState.stageUI = oldUI;
			throw e;
		}

		preRenderBotplay();
		bakedChartSignature = currentChartSignature();
	}

	// 自动游玩预演：加载时预先模拟整张谱面的自动游玩，记录每个玩家侧音符（含长条段）的命中时刻。
	// 运行时机器人不再逐帧试探判定窗口，音符到达预演时刻即命中，堆叠箭头再多也只需一次比较。
	static function preRenderBotplay():Void
	{
		botplayLanes = [[], [], [], []];
		if (PlayState.SONG != null && PlayState.SONG.notes != null)
		{
			// 与 PlayState.generateChartNotes 完全相同的遍历顺序与长条细分规则
			var stepCrochet:Float = ((60 / PlayState.SONG.bpm) * 1000) / 4;
			for (section in PlayState.SONG.notes)
			{
				if (section.sectionNotes == null) continue;
				var mustHitSection:Bool = section.mustHitSection;
				for (songNotes in section.sectionNotes)
				{
					var daStrumTime:Float = songNotes[0];
					var daNoteData:Int = Std.int(songNotes[1] % 4);
					if (daNoteData < 0 || daNoteData > 3) continue;
					var gottaHitNote:Bool = mustHitSection;
					if (songNotes[1] > 3) gottaHitNote = !mustHitSection;
					if (!gottaHitNote) continue;

					botplayLanes[daNoteData].push(daStrumTime);
					var floorSus:Int = Math.floor(songNotes[2] / stepCrochet);
					if (floorSus > 0)
						for (susNote in 0...floorSus + 1)
							botplayLanes[daNoteData].push(daStrumTime + stepCrochet * susNote);
				}
			}
		}
		botplaySignature = currentChartSignature();
	}

	// 取当前谱面的自动游玩预演计划（null = 未预演/不可用，运行时回退实时判定）
	public static function getBotplayPlan():Array<Array<Float>>
	{
		if (!ClientPrefs.data.preRenderNotes || ClientPrefs.data.phigrosStyle) return null;
		if (PlayState.SONG == null || botplaySignature == null || botplaySignature != currentChartSignature()) return null;
		return botplayLanes;
	}

	// 烘焙单个音符外观：皮肤帧 + RGB 颜色 → 静态贴图（每种外观只做一次，此后所有音符共用）
	static function bakeNoteAppearance(loadPath:String, pixelStage:Bool, col:Int, kind:Int, r:FlxColor, g:FlxColor, b:FlxColor, useRGB:Bool):FlxGraphic
	{
		var key:String = getBakedNoteKey(loadPath, col, kind, r, g, b, useRGB);
		var existing:FlxGraphic = bakedNoteGraphics.get(key);
		if (existing != null) return existing;

		var bitmap:BitmapData = null;
		if (pixelStage)
		{
			var sheet:BitmapData = getBakeBitmapData(loadPath);
			if (sheet == null) return null;
			var fw:Int = Math.floor(sheet.width / 4);
			var rows:Int = (kind == BAKE_HOLD || kind == BAKE_HOLDEND) ? 2 : 5;
			var fh:Int = Math.floor(sheet.height / rows);
			var row:Int = kind == BAKE_HOLD ? 0 : 1;
			bitmap = new BitmapData(fw, fh, true, FlxColor.TRANSPARENT);
			bitmap.copyPixels(sheet, new Rectangle(col * fw, row * fh, fw, fh), new Point(0, 0));
		}
		else
		{
			var atlas:FlxAtlasFrames = null;
			try
			{
				atlas = Paths.getSparrowAtlas(loadPath);
			}
			catch (e:Dynamic)
			{
				atlas = null;
			}
			// cacheOnGPU 开启时引擎会把图集换成 GPU 纹理（readable=false），
			// copyPixels 对不可读位图会静默失败 → 重新从资产库读取 CPU 位图构建烘焙用图集
			if (atlas == null || atlas.parent == null || atlas.parent.bitmap == null || !atlas.parent.bitmap.readable)
				atlas = getBakeAtlas(loadPath);
			if (atlas == null) return null;
			var prefix:String = kind == BAKE_NOTE ? colArray[col] + '0'
				: colArray[col] + (kind == BAKE_HOLD ? ' hold piece' : ' hold end');
			var frame:FlxFrame = null;
			for (f in atlas.frames)
			{
				if (f.name != null && f.name.startsWith(prefix)) { frame = f; break; }
			}
			if (frame == null) return null;
			bitmap = bakeAtlasFrame(frame);
			if (kind == BAKE_NOTE && col == 0)
				bakedArrowRenderWidth.set(loadPath, Std.int(bitmap.width * 0.7));
		}

		if (useRGB) applyRGBToBitmap(bitmap, r, g, b);

		// 不入 FlxG.bitmap 缓存：由本类静态引用持有，全局清缓存（PlayState.create 等）不会销毁
		var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, null, false);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		bakedNoteGraphics.set(key, graphic);
		return graphic;
	}

	// 烘焙专用 CPU 位图：优先复用 Paths.image 缓存；若已是 GPU 纹理（不可读），从资产库重新读取
	static function getBakeBitmapData(loadPath:String):BitmapData
	{
		var cached:BitmapData = bakeBitmapCache.get(loadPath);
		if (cached != null) return cached;
		var bmp:BitmapData = null;
		#if MODS_ALLOWED
		// 模组贴图：按磁盘实际文件名读取（资产库 ID 区分大小写，且谱面引用的皮肤名可能与文件名大小写不一致）
		var modFile:String = findModFile('images/' + loadPath + '.png');
		if (modFile != null)
			bmp = BitmapData.fromFile(modFile);
		#end
		if (bmp == null)
		{
			var g:FlxGraphic = Paths.image(loadPath, null, false);
			if (g != null && g.bitmap != null && g.bitmap.readable) bmp = g.bitmap;
		}
		if (bmp == null)
		{
			var file:String = Paths.getPath('images/' + loadPath + '.png', IMAGE, null, false);
			if (OpenFlAssets.exists(file, IMAGE)) bmp = OpenFlAssets.getBitmapData(file);
		}
		if (bmp != null) bakeBitmapCache.set(loadPath, bmp);
		return bmp;
	}

	// 烘焙专用图集：从磁盘/资产库重新读取 CPU 位图，避免 GPU 纹理不可读导致帧提取为空
	static function getBakeAtlas(loadPath:String):FlxAtlasFrames
	{
		var cached:FlxAtlasFrames = bakeAtlasCache.get(loadPath);
		if (cached != null) return cached;
		var bmp:BitmapData = getBakeBitmapData(loadPath);
		if (bmp == null) return null;
		var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bmp, false, null, false);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		var xml:String = null;
		#if MODS_ALLOWED
		// 与 PNG 相同的大小写兜底：mod 图集 XML 也从磁盘实际文件名读取
		var modXml:String = findModFile('images/' + loadPath + '.xml');
		if (modXml != null) xml = File.getContent(modXml);
		#end
		if (xml == null) xml = Paths.getTextFromFile('images/' + loadPath + '.xml');
		if (xml == null || xml.length < 1) return null;
		var atlas:FlxAtlasFrames = FlxAtlasFrames.fromSparrow(graphic, xml);
		bakeAtlasCache.set(loadPath, atlas);
		return atlas;
	}

	#if MODS_ALLOWED
	// 大小写不敏感地逐级解析路径（APFS 大小写敏感卷上，谱面引用的皮肤名可能与实际文件名大小写不同）
	static function resolveModFileCaseInsensitive(path:String):String
	{
		if (FileSystem.exists(path)) return path;
		var parts:Array<String> = path.split('/');
		if (parts.length < 1) return null;
		var cur:String = parts.shift();
		for (part in parts)
		{
			if (!FileSystem.exists(cur) || !FileSystem.isDirectory(cur)) return null;
			var lower:String = part.toLowerCase();
			var match:String = null;
			for (entry in FileSystem.readDirectory(cur))
			{
				if (entry.toLowerCase() == lower) { match = entry; break; }
			}
			if (match == null) return null;
			cur = cur + '/' + match;
		}
		return cur;
	}

	// 与 Paths.modFolders 相同的查找顺序（当前 mod → 全局 mod → 根目录），带大小写兜底
	static function findModFile(relPath:String):String
	{
		var candidates:Array<String> = [];
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			candidates.push(Paths.mods(Mods.currentModDirectory + '/' + relPath));
		for (mod in Mods.getGlobalMods())
			candidates.push(Paths.mods(mod + '/' + relPath));
		candidates.push(Paths.mods(relPath));
		for (c in candidates)
		{
			var resolved:String = resolveModFileCaseInsensitive(c);
			if (resolved != null) return resolved;
		}
		return null;
	}
	#end

	// 把图集帧复制成独立位图：保持 sourceSize 尺寸与 offset，与原渲染完全一致
	static function bakeAtlasFrame(frame:FlxFrame):BitmapData
	{
		var sw:Int = Std.int(frame.sourceSize.x);
		var sh:Int = Std.int(frame.sourceSize.y);
		var out:BitmapData = new BitmapData(sw, sh, true, FlxColor.TRANSPARENT);

		var fw:Int = Std.int(frame.frame.width);
		var fh:Int = Std.int(frame.frame.height);
		var srcRect:Rectangle = new Rectangle(frame.frame.x, frame.frame.y, fw, fh);

		if (frame.angle == FlxFrameAngle.ANGLE_NEG_90)
		{
			// 图集内旋转帧：先水平拷出，再顺时针转回显示方向
			var tmp:BitmapData = new BitmapData(fw, fh, true, FlxColor.TRANSPARENT);
			tmp.copyPixels(frame.parent.bitmap, srcRect, new Point(0, 0));
			var rotated:BitmapData = rotateBitmapClockwise(tmp);
			tmp.dispose();
			out.copyPixels(rotated, new Rectangle(0, 0, rotated.width, rotated.height), new Point(frame.offset.x, frame.offset.y));
			rotated.dispose();
		}
		else
		{
			out.copyPixels(frame.parent.bitmap, srcRect, new Point(frame.offset.x, frame.offset.y));
		}
		return out;
	}

	// 顺时针旋转 90°（图集 ANGLE_NEG_90 旋转帧还原用）
	static function rotateBitmapClockwise(src:BitmapData):BitmapData
	{
		var dst:BitmapData = new BitmapData(src.height, src.width, true, FlxColor.TRANSPARENT);
		var m:Matrix = new Matrix();
		m.rotate(Math.PI / 2);
		m.translate(src.height - 1, 0);
		dst.draw(src, m);
		return dst;
	}

	// CPU 端复刻 RGBPalette 着色器：newColor.rgb = color.r * r + color.g * g + color.b * b
	//（r/g/b 为 vec3 颜色矩阵，按输出通道组织：newR = srcR*rR + srcG*gR + srcB*bR）
	static function applyRGBToBitmap(bmp:BitmapData, r:FlxColor, g:FlxColor, b:FlxColor):Void
	{
		var pixels:ByteArray = bmp.getPixels(bmp.rect);
		pixels.position = 0;
		// getPixels 返回 ARGB32（大端序）：i=A, i+1=R, i+2=G, i+3=B（与 GPU 纹理一致，预乘 alpha）
		var rR:Float = r.redFloat, rG:Float = r.greenFloat, rB:Float = r.blueFloat;
		var gR:Float = g.redFloat, gG:Float = g.greenFloat, gB:Float = g.blueFloat;
		var bR:Float = b.redFloat, bG:Float = b.greenFloat, bB:Float = b.blueFloat;

		var i:Int = 0;
		var len:Int = pixels.length;
		while (i < len)
		{
			if (pixels[i] > 0) // alpha 为 0 的像素不着色（与着色器行为一致）
			{
				var sr:Float = pixels[i + 1] / 255;
				var sg:Float = pixels[i + 2] / 255;
				var sb:Float = pixels[i + 3] / 255;
				pixels[i + 1] = Std.int(Math.min(sr * rR + sg * gR + sb * bR, 1) * 255);
				pixels[i + 2] = Std.int(Math.min(sr * rG + sg * gG + sb * bG, 1) * 255);
				pixels[i + 3] = Std.int(Math.min(sr * rB + sg * gB + sb * bB, 1) * 255);
			}
			i += 4;
		}
		pixels.position = 0;
		bmp.setPixels(bmp.rect, pixels);
	}

	function loadNoteAnims() {
		if (isSustainNote)
		{
			animation.addByPrefix('purpleholdend', 'pruple end hold', 24, true); // this fixes some retarded typo from the original note .FLA
			animation.addByPrefix(colArray[noteData] + 'holdend', colArray[noteData] + ' hold end', 24, true);
			animation.addByPrefix(colArray[noteData] + 'hold', colArray[noteData] + ' hold piece', 24, true);
		}
		else animation.addByPrefix(colArray[noteData] + 'Scroll', colArray[noteData] + '0');

		setGraphicSize(Std.int(width * 0.7));
		updateHitbox();
	}

	function loadPixelNoteAnims() {
		if(isSustainNote)
		{
			animation.add(colArray[noteData] + 'holdend', [noteData + 4], 24, true);
			animation.add(colArray[noteData] + 'hold', [noteData], 24, true);
		} else animation.add(colArray[noteData] + 'Scroll', [noteData + 4], 24, true);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (PlayState.instance != null && PlayState.instance.rewinding)
			return; // 回溯中：不更新命中窗口/超时状态，箭头纯视觉倒流

		if (mustPress)
		{
			if (PlayState.instance != null && PlayState.instance.cpuControlled && PlayState.instance.botplayPlan != null)
			{
				// 自动游玩预演模式：命中时刻在加载预演时已确定，无需逐帧计算判定窗口
				canBeHit = false;
			}
			else if (ClientPrefs.data.noteJudgment == 'KE 判定')
				// KE 判定：提前窗口更短（0.5x），更容易在晚到一侧命中
				canBeHit = (strumTime > Conductor.songPosition - (Conductor.safeZoneOffset * lateHitMult) &&
							strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * 0.5 * earlyHitMult));
			else
				canBeHit = (strumTime > Conductor.songPosition - (Conductor.safeZoneOffset * lateHitMult) &&
							strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * earlyHitMult));

			if (strumTime < Conductor.songPosition - Conductor.safeZoneOffset && !wasGoodHit)
				tooLate = true;
		}
		else
		{
			canBeHit = false;

			if (strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * earlyHitMult))
			{
				if((isSustainNote && prevNote.wasGoodHit) || strumTime <= Conductor.songPosition)
					wasGoodHit = true;
			}
		}

		if (tooLate && !inEditor)
		{
			if (alpha > 0.3)
				alpha = 0.3;
		}
	}

	override public function destroy()
	{
		super.destroy();
		_lastValidChecked = '';
	}

	public function followStrumNote(myStrum:StrumNote, fakeCrochet:Float, songSpeed:Float = 1)
	{
		var strumX:Float = myStrum.x;
		var strumY:Float = myStrum.y;
		var strumAngle:Float = myStrum.angle;
		var strumAlpha:Float = myStrum.alpha;
		var strumDirection:Float = myStrum.direction;

		distance = (0.45 * (Conductor.songPosition - strumTime) * songSpeed * multSpeed);
		if (!myStrum.downScroll) distance *= -1;

		if (strumDirection != _dirCached)
		{
			_dirCached = strumDirection;
			var angleRad:Float = strumDirection * 0.017453292; // PI/180 precalculated
			_dirCos = Math.cos(angleRad);
			_dirSin = Math.sin(angleRad);
		}
		if (copyAngle)
			angle = strumDirection - 90 + strumAngle + offsetAngle;

		if(copyAlpha)
			alpha = strumAlpha * multAlpha;

		if(copyX)
			x = strumX + offsetX + _dirCos * distance;

		if(copyY)
		{
			y = strumY + offsetY + correctionOffset + _dirSin * distance;
			if(myStrum.downScroll && isSustainNote)
			{
				if(PlayState.isPixelStage)
					y -= PlayState.daPixelZoom * 9.5;
				y -= (frameHeight * scale.y) - (Note.swagWidth / 2);
			}
		}
	}

	public function clipToStrumNote(myStrum:StrumNote)
	{
		var center:Float = myStrum.y + offsetY + Note.swagWidth / 2;
		if(isSustainNote && (mustPress || !ignoreNote) &&
			(!mustPress || (wasGoodHit || (prevNote.wasGoodHit && !canBeHit))))
		{
			var swagRect:FlxRect = clipRect;
			if(swagRect == null) swagRect = new FlxRect(0, 0, frameWidth, frameHeight);

			if (myStrum.downScroll)
			{
				if(y - offset.y * scale.y + height >= center)
				{
					swagRect.width = frameWidth;
					swagRect.height = (center - y) / scale.y;
					swagRect.y = frameHeight - swagRect.height;
				}
			}
			else if (y + offset.y * scale.y <= center)
			{
				swagRect.y = (center - y) / scale.y;
				swagRect.width = width / scale.x;
				swagRect.height = (height / scale.y) - swagRect.y;
			}
			clipRect = swagRect;
		}
	}
}
