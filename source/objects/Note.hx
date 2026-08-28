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

// H-Slice 风格轻量音符数据：加载期只建结构体（不建 FlxSprite 对象），
// 进入游戏后按需通过 NoteGroup 对象池实例化成 Note。
// noteData 位打包：1-8 位 = 轨道；9 = mustHit；10 = isHold；11 = isHoldEnd；12 = gfNote；
// 13 = altAnim；14 = noAnim&noMissAnim；15 = blockHit；16 = ignoreNote
// 类型化类（非匿名结构）：hxcpp 下字段为静态访问，避免 anon 动态字段表（Anon::__Field）
// 在 GC/线程场景被回收导致 UAF（安卓 Blazin 进曲 SIGSEGV 根因）。
// 字段默认值语义与原 @:optional 一致：未赋值=null/false（调用处已有 null 判断）。
// ============================================================================
// ↓↓↓ 旧实现（直接字段版 CastNote）：平行数组代理出问题时，删除下方"新实现"
//     类，恢复本注释块即可 100% 回退（字段名/读写点完全一致，无需改任何调用处）
// ============================================================================
/*
class CastNote
{
	public var strumTime:Float;
	public var noteData:Int;
	public var chartSeq:Int;          // 谱面唯一序号（回放录制/匹配）；Lua 动态音符为 -1
	public var density:Float;         // 堆叠合并计数：同一(时间,轨道)合并为一个音符代表的箭头数
	public var holdLength:Float;
	public var noteType:String;
	public var multSpeed:Float;       // 每音符滚动倍速（默认 1）
	public var cmpSpam:Array<Dynamic>;// H-Slice 挤压音符扩展 [剩余数, 密度]（展开为连续同轨音符）
	public var offs:Array<Float>;     // 堆叠合并展开：本组内每个箭头相对基准时间的偏移（ms）
									//（后台压缩为一条 CastNote；生成时按偏移展开为 N 个视觉箭头，
									//  画面与未压缩时逐像素一致）
	// 舞台脚本（PhillyStreets/PhillyBlazin 等）会直接改这些字段；必须初始化默认值
	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var blockHit:Bool = false;
	// 脚本可改的旋转属性（对齐 PE 0.6.3/0.7.3 的 Note：模组常用 unspawnNotes[i].angle = x 旋转箭头）
	public var angle:Float = 0;        // 固定旋转角度（0 = 未设置，出生后走滚动方向公式）
	public var offsetAngle:Float = 0;  // 附加角度（每帧公式：angle = 方向-90 + strumAngle + offsetAngle）

	public function new()
	{
		strumTime = 0;
		noteData = 0;
		chartSeq = -1;
		density = 1;
		holdLength = 0;
		noteType = null;
		multSpeed = 1;
		cmpSpam = null;
		offs = null;
	}
}
*/
// ============================================================================
// 新实现（Meteoric Fix 续：Flocc 级 400MB 内存目标）：单索引对象 + 静态平行数组。
// 每个 CastNote 实例只携带一个槽位号 idx（对象 ~24-32B），14 个字段全部经
// getter/setter 代理读到/写入共享平行数组 —— 2.26M 音符从 ~330MB 降到 ~70MB。
// API 完全不变：unspawnNotes[i].strumTime/.angle/etc（引擎内部、Lua、HScript、
// Reflect 访问）全部照常工作；唯一代价是每字段一次静态数组访问。
// 生命周期：buildChartNotes() 开始时 resetPacked()（谱面生产者唯一入口）；
// 游玩期 spawnOne 展开的临时子音符追加槽位，随下一曲重置。
// ============================================================================
class CastNote
{
	public static var __slotCount:Int = 0;
	static var __strumTime:Array<Float> = [];
	static var __noteData:Array<Int> = [];
	static var __chartSeq:Array<Int> = [];
	static var __density:Array<Float> = [];
	static var __holdLength:Array<Float> = [];
	static var __noteType:Array<String> = [];
	static var __multSpeed:Array<Float> = [];
	static var __cmpSpam:Array<Dynamic> = [];    // 元素 = Array<Dynamic> | null
	static var __offs:Array<Dynamic> = [];       // 元素 = Array<Float> | null
	static var __noAnimation:Array<Bool> = [];
	static var __noMissAnimation:Array<Bool> = [];
	static var __blockHit:Array<Bool> = [];
	static var __angle:Array<Float> = [];
	static var __offsetAngle:Array<Float> = [];

	// 新谱面开始构建时调用：清空上一曲的全部平行数组（旧 CastNote 对象随 unspawnNotes
	// 一并丢弃；任何旧引用（spamNotes 等）在 KillNotes/create 已清空，不会读到新数据）
	public static function resetPacked():Void
	{
		__slotCount = 0;
		__strumTime = []; __noteData = []; __chartSeq = []; __density = []; __holdLength = [];
		__noteType = []; __multSpeed = []; __cmpSpam = []; __offs = [];
		__noAnimation = []; __noMissAnimation = []; __blockHit = [];
		__angle = []; __offsetAngle = [];
	}

	public var idx:Int;

	public function new()
	{
		idx = __slotCount++;
		ensure(idx);
	}

	// 槽位预填充默认值：保证任何"先读后写"都不会读到未初始化内存（写前读会得到构造函数默认值）
	static inline function ensure(i:Int):Void
	{
		while (__strumTime.length <= i)
		{
			__strumTime.push(0);
			__noteData.push(0);
			__chartSeq.push(-1);
			__density.push(1);
			__holdLength.push(0);
			__noteType.push(null);
			__multSpeed.push(1);
			__cmpSpam.push(null);
			__offs.push(null);
			__noAnimation.push(false);
			__noMissAnimation.push(false);
			__blockHit.push(false);
			__angle.push(0);
			__offsetAngle.push(0);
		}
	}

	public var strumTime(get, set):Float;
	inline function get_strumTime():Float return __strumTime[idx];
	inline function set_strumTime(v:Float):Float return __strumTime[idx] = v;

	public var noteData(get, set):Int;
	inline function get_noteData():Int return __noteData[idx];
	inline function set_noteData(v:Int):Int return __noteData[idx] = v;

	public var chartSeq(get, set):Int;
	inline function get_chartSeq():Int return __chartSeq[idx];
	inline function set_chartSeq(v:Int):Int return __chartSeq[idx] = v;

	public var density(get, set):Float;
	inline function get_density():Float return __density[idx];
	inline function set_density(v:Float):Float return __density[idx] = v;

	public var holdLength(get, set):Float;
	inline function get_holdLength():Float return __holdLength[idx];
	inline function set_holdLength(v:Float):Float return __holdLength[idx] = v;

	public var noteType(get, set):String;
	inline function get_noteType():String return __noteType[idx];
	inline function set_noteType(v:String):String return __noteType[idx] = v;

	public var multSpeed(get, set):Float;
	inline function get_multSpeed():Float return __multSpeed[idx];
	inline function set_multSpeed(v:Float):Float return __multSpeed[idx] = v;

	public var cmpSpam(get, set):Array<Dynamic>;
	inline function get_cmpSpam():Array<Dynamic> return __cmpSpam[idx];
	inline function set_cmpSpam(v:Array<Dynamic>):Array<Dynamic> return __cmpSpam[idx] = v;

	public var offs(get, set):Array<Float>;
	inline function get_offs():Array<Float> return __offs[idx];
	inline function set_offs(v:Array<Float>):Array<Float> return __offs[idx] = v;

	public var noAnimation(get, set):Bool;
	inline function get_noAnimation():Bool return __noAnimation[idx];
	inline function set_noAnimation(v:Bool):Bool return __noAnimation[idx] = v;

	public var noMissAnimation(get, set):Bool;
	inline function get_noMissAnimation():Bool return __noMissAnimation[idx];
	inline function set_noMissAnimation(v:Bool):Bool return __noMissAnimation[idx] = v;

	public var blockHit(get, set):Bool;
	inline function get_blockHit():Bool return __blockHit[idx];
	inline function set_blockHit(v:Bool):Bool return __blockHit[idx] = v;

	public var angle(get, set):Float;
	inline function get_angle():Float return __angle[idx];
	inline function set_angle(v:Float):Float return __angle[idx] = v;

	public var offsetAngle(get, set):Float;
	inline function get_offsetAngle():Float return __offsetAngle[idx];
	inline function set_offsetAngle(v:Float):Float return __offsetAngle[idx] = v;
}

class SpamNoteData
{
	public var remaining:Float;
	public var density:Float;
	public var seedNote:CastNote; // 原始种子（每次展开后 strumTime 递增）
	public function new(remaining:Float, density:Float, seedNote:CastNote)
	{
		this.remaining = remaining;
		this.density = density;
		this.seedNote = seedNote;
	}
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
	public var density:Float = 1; // 堆叠合并计数（H-Slice 性能移植）
	public var botQueued:Bool = false; // 本帧已入自动命中队列（击杀延时保护，防入队后被同帧击杀丢弃）
	public var botSched:Bool = false;  // 已在排期队列（生成即登记、待弹出）：排期等待期间免受回收窗击杀
	public var isSustainEnds:Bool = false; // 长条尾段（也是唯一"holdend"贴图段）
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

	// 脚本可修改 Angle（对齐 PE 0.6.3 行为；0.7.3/1.0.4 的 followStrumNote 每帧重算会覆盖脚本写入）：
	// 外部/脚本写入 angle 时自动关闭 copyAngle 接管旋转；引擎内部写入
	// （recycleNote 复生复位 / followStrumNote 每帧公式）经 _engineAngleWrite 标记绕过，
	// 保证 0.7.3 滚动方向公式与复生复位不受任何影响。
	var _engineAngleWrite:Bool = false;

	override public function set_angle(Value:Float):Float
	{
		var wasCopy:Bool = copyAngle;
		var ret:Float = super.set_angle(Value);
		if (!_engineAngleWrite && wasCopy)
			copyAngle = false; // 脚本设定 → 接管旋转：followStrumNote 不再每帧覆盖
		return ret;
	}

	public static var SUSTAIN_SIZE:Int = 44;
	public static var swagWidth:Float = 160 * 0.7;
	public static var colArray:Array<String> = ['purple', 'blue', 'green', 'red'];
	// H-Slice 移植：池化音符的 prevNote/nextNote 链重建
	// seqNote[chartSeq] = 存活池中对应序号音符；seqHit[chartSeq] = 已回池音符的 wasGoodHit 快照
	//（长条子段"上一段是否命中"在上一段被杀/回池后仍能读取，保证链式判定语义不变）
	public static var seqNote:Array<Note> = [];
	public static var seqHit:Array<Bool> = [];
	// 提前渲染的贴图种类：0 箭头 / 1 长条体 / 2 长条尾
	public static inline var BAKE_NOTE:Int = 0;
	public static inline var BAKE_HOLD:Int = 1;
	public static inline var BAKE_HOLDEND:Int = 2;
	public static var defaultNoteSkin(default, never):String = 'noteSkins/NOTE_assets';

	// 大谱面优化：同一音符皮肤只解析一次图集/贴图，全部音符共享
	static var noteFramesCache:Map<String, FlxAtlasFrames> = [];
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
		bakeBitmapCache = [];
		bakeAtlasCache = [];
		bakedNoteGraphics = [];
		bakedArrowRenderWidth = [];
	}

	// 进曲目时调用：只清运行时图集缓存（其 FlxGraphic 由 Paths 追踪，跨曲目可能被内存清理销毁），
	// 烘焙贴图缓存（bakedNoteGraphics，graphic 独立持有）保留复用
	public static function clearRuntimeAtlasCache()
	{
		noteFramesCache = [];
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
			if(PlayState.SONG != null && PlayState.SONG.disableNoteRGB) rgbShader.enabled = false;
			else if(ClientPrefs.data.psych063Mode || !ClientPrefs.data.shaders) rgbShader.enabled = false; // 0.6.3 兼容/关着色器时避免 RGB 渲染成黑
			#if mobile
			else rgbShader.enabled = false; // 安卓 GPU：RGB 着色器输出全黑（箭头不可见），强制用贴图原色/烘焙色
			#else
			else if (bakedKind >= 0) rgbShader.enabled = false; // 提前渲染：颜色已烘焙进贴图，不再叠加 RGB 着色器（叠加会钳制成白色）
			else
			{
				// Normal（白色箭头贴图）启用 RGB 着色器染色，解决箭头颜色发白；
				// Chips 等自带颜色的皮肤保持贴图原色（再叠 shader 会变色）
				var skinPath:String = getNoteSkinLoadPathCached(texture, '', PlayState.isPixelStage, isSustainNote);
				rgbShader.enabled = (skinPath.indexOf('chip') < 0);
			}
			#end

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
		// 安卓：RGB 着色器在部分 GPU/GLES 驱动上输出全黑，强制走 CPU 烘焙保证箭头颜色
		var bakeNotes:Bool = ClientPrefs.data.preRenderNotes && !ClientPrefs.data.psych063Mode;
		#if mobile
		if (!ClientPrefs.data.psych063Mode) bakeNotes = true;
		#end
		if (bakeNotes && !inEditor && noteData > -1)
		{
			var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
			var arr:Array<FlxColor> = (loadPath.startsWith('pixelUI/') ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB)[noteData];
			bakedLoadPath = loadPath;
			bakedR = arr[0];
			bakedG = arr[1];
			bakedB = arr[2];
			bakedKey = getBakedNoteKey(loadPath, noteData, isSustainNote ? BAKE_HOLDEND : BAKE_NOTE, bakedR, bakedG, bakedB, useRGB);
			var baked:FlxGraphic = bakedNoteGraphics.get(bakedKey);
			#if mobile
			if (baked == null)
			{
				// 移动端懒烘焙：首次遇到该外观时现算（每种外观只算一次，此后全部复用）
				var pixelStage:Bool = PlayState.isPixelStage;
				bakeNoteAppearance(loadPath, pixelStage, noteData, isSustainNote ? BAKE_HOLDEND : BAKE_NOTE, bakedR, bakedG, bakedB, useRGB);
				bakeNoteAppearance(loadPath, pixelStage, noteData, isSustainNote ? BAKE_NOTE : BAKE_HOLDEND, bakedR, bakedG, bakedB, useRGB);
				bakeNoteAppearance(loadPath, pixelStage, noteData, BAKE_HOLD, bakedR, bakedG, bakedB, useRGB);
				baked = bakedNoteGraphics.get(bakedKey);
			}
			#end
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
			// 大内存压力下图集可能被缓存层逐出（graphic 非 persist）：强制重读一次再兜底
			if (atlas == null || atlas.parent == null || atlas.parent.bitmap == null)
			{
				try
				{
					atlas = Paths.getSparrowAtlas(loadPath, null, true);
					if (atlas != null) noteFramesCache.set(loadPath, atlas);
				}
				catch (e:Dynamic) { atlas = null; }
			}
			if (atlas == null)
			{
				// 防御：图集加载失败（贴图/XML 缺失）时用纯色占位，避免 frames=null 绘制崩溃
				// （FlxDrawQuadsItem Null Object Reference）。贴图路径修好后正常路径不触发。
				trace('NOTE FALLBACK solid: ' + loadPath);
				loadGraphic(FlxGraphic.fromBitmapData(new BitmapData(Std.int(swagWidth), Std.int(swagWidth), false, 0xFF606060)));
				updateHitbox();
			}
			else
			{
				frames = atlas;
				loadNoteAnims();
				if(!isSustainNote)
				{
					centerOffsets();
					centerOrigin();
				}
			}
		}

		if(isSustainNote) {
			scale.y = lastScaleY;
		}
		updateHitbox();

		if(animName != null)
			animation.play(animName, true);
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

		// Psych 0.6.3 兼容：旧模组常用 "NOTE_assets" 这种不带 noteSkins/ 前缀的路径，
		// 如果根目录不存在但 noteSkins/ 下存在，就自动补上前缀，避免加载失败变成 Haxe 图标
		if (skin.indexOf('/') < 0 && !Paths.fileExists('images/' + skin + '.png', IMAGE)
			&& Paths.fileExists('images/noteSkins/' + skin + '.png', IMAGE))
			skin = 'noteSkins/' + skin;

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
		var bakeNotes:Bool = ClientPrefs.data.preRenderNotes && !ClientPrefs.data.psych063Mode;
		#if mobile
		if (!ClientPrefs.data.psych063Mode) bakeNotes = true;
		#end
		if (!bakeNotes || inEditor || rgbShader == null || noteData < 0) return;
		var pixelStage:Bool = PlayState.isPixelStage;
		var loadPath:String = bakedLoadPath != null ? bakedLoadPath : getNoteSkinLoadPathCached(texture, '', pixelStage, isSustainNote);
		var kind:Int = bakedKind >= 0 ? bakedKind : (isSustainNote ? BAKE_HOLDEND : BAKE_NOTE);
		var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
		var key:String = (bakedKey != null && rgbShader.r == bakedR && rgbShader.g == bakedG && rgbShader.b == bakedB)
			? bakedKey
			: getBakedNoteKey(loadPath, noteData, kind, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
		var baked:FlxGraphic = bakedNoteGraphics.get(key);
		#if mobile
		if (baked == null)
		{
			bakeNoteAppearance(loadPath, pixelStage, noteData, kind, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
			bakeNoteAppearance(loadPath, pixelStage, noteData, kind == BAKE_NOTE ? BAKE_HOLDEND : BAKE_NOTE, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
			bakeNoteAppearance(loadPath, pixelStage, noteData, BAKE_HOLD, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
			baked = bakedNoteGraphics.get(key);
		}
		#end
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
		var key:String = getBakedNoteKey(loadPath, noteData, BAKE_HOLD, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
		var baked:FlxGraphic = bakedNoteGraphics.get(key);
		#if mobile
		if (baked == null)
		{
			bakeNoteAppearance(loadPath, PlayState.isPixelStage, noteData, BAKE_HOLD, rgbShader.r, rgbShader.g, rgbShader.b, useRGB);
			baked = bakedNoteGraphics.get(key);
		}
		#end
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
		return bakedChartSignature != null && bakedChartSignature == currentChartSignature()
			&& botplaySignature != null && botplaySignature == currentChartSignature();
	}

	// 加载曲目时调用：扫描谱面用到的音符类型，烘焙所有可能出现的音符贴图
	public static function preRenderChartNotes():Void
	{
		if (PlayState.SONG == null) return;

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
		if (!ClientPrefs.data.preRenderNotes) return null;
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
			if (sheet == null) { trace('BAKE FAIL pixel: ' + loadPath); return null; }
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
			if (atlas == null) { trace('BAKE FAIL atlas: ' + loadPath); return null; }
			var prefix:String = kind == BAKE_NOTE ? colArray[col] + '0'
				: colArray[col] + (kind == BAKE_HOLD ? ' hold piece' : ' hold end');
			var frame:FlxFrame = null;
			for (f in atlas.frames)
			{
				if (f.name != null && f.name.startsWith(prefix)) { frame = f; break; }
			}
			if (frame == null)
			{
				// 素材拼写容错：NOTE_assets.xml 的紫色长条尾帧名是 "pruple end hold0000"（拼写错误），
				// 代码按 "purple hold end" 前缀找不到 → 改按“含 hold end + 含颜色名（含错误拼写 pruple）”匹配
				if (kind == BAKE_HOLDEND)
				{
					for (f in atlas.frames)
					{
						if (f.name == null) continue;
						if (f.name.indexOf('hold end') >= 0
							&& (f.name.indexOf(colArray[col]) >= 0 || f.name.toLowerCase().indexOf('pruple') >= 0))
						{ frame = f; break; }
					}
				}
			}
			if (frame == null)
			{
				// 诊断：打印图集帧名，定位帧匹配失败原因
				var sample:String = '';
				for (f in atlas.frames)
				{
					if (sample.length < 240)
						sample += (f.name != null ? f.name : 'null') + ' ';
				}
				trace('BAKE FAIL frame: ' + loadPath + ' | prefix=' + prefix + ' | n=' + atlas.frames.length + ' | ' + sample);
				return null;
			}
			bitmap = bakeAtlasFrame(frame);
			if (kind == BAKE_NOTE && col == 0)
				bakedArrowRenderWidth.set(loadPath, Std.int(bitmap.width * 0.7));
		}

		if (useRGB)
		{
			// 防御：r/g/b 颜色矩阵为全黑（0）时着色会把贴图烘成黑块 → 跳过着色保留原始贴图
			var blackMatrix:Bool = (r.redFloat + r.greenFloat + r.blueFloat <= 0.01)
				|| (g.redFloat + g.greenFloat + g.blueFloat <= 0.01)
				|| (b.redFloat + b.greenFloat + b.blueFloat <= 0.01);
			if (!blackMatrix) applyRGBToBitmap(bitmap, r, g, b);
		}

		// 不入 FlxG.bitmap 缓存：由本类静态引用持有，全局清缓存（PlayState.create 等）不会销毁
		var graphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, null, false);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		bakedNoteGraphics.set(key, graphic);
		return graphic;
	}

	// 烘焙专用 CPU 位图：优先复用 Paths.image 缓存；若已是 GPU 纹理（不可读），从资产库重新读取
	public static function getBakeBitmapData(loadPath:String):BitmapData
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
			// allowPack=false：音符皮肤会被原始尺寸分割成帧，绝不参与运行时密排列
			var g:FlxGraphic = Paths.image(loadPath, null, false, true, -1, false);
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
	public static function findModFile(relPath:String):String
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
	public static function bakeAtlasFrame(frame:FlxFrame):BitmapData
	{
		var src:BitmapData = (frame.parent != null) ? frame.parent.bitmap : null;
		return bakeAtlasFrameFromBitmap(frame, src);
	}

	// 把图集帧按目标色 CPU 烘焙染色（安卓 tile 渲染下 GL shader 不生效时的通用方案）
	public static function bakeFrameWithRGB(cf:FlxFrame, fallbackPath:String, r:FlxColor, g:FlxColor, b:FlxColor):BitmapData
	{
		var bmp:BitmapData = null;
		if (cf.parent != null && cf.parent.bitmap != null && cf.parent.bitmap.readable)
			bmp = bakeAtlasFrame(cf);
		else
			bmp = bakeAtlasFrameFromBitmap(cf, getBakeBitmapData(fallbackPath));
		if (bmp == null) return null;
		applyRGBToBitmap(bmp, r, g, b);
		return bmp;
	}

	// 与 bakeAtlasFrame 相同，但允许指定 CPU 位图来源（GPU 纹理不可读时从磁盘/资产库重读）
	public static function bakeAtlasFrameFromBitmap(frame:FlxFrame, src:BitmapData):BitmapData
	{
		if (src == null) return null;
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
			tmp.copyPixels(src, srcRect, new Point(0, 0));
			var rotated:BitmapData = rotateBitmapClockwise(tmp);
			tmp.dispose();
			out.copyPixels(rotated, new Rectangle(0, 0, rotated.width, rotated.height), new Point(frame.offset.x, frame.offset.y));
			rotated.dispose();
		}
		else
		{
			out.copyPixels(src, srcRect, new Point(frame.offset.x, frame.offset.y));
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
	public static function applyRGBToBitmap(bmp:BitmapData, r:FlxColor, g:FlxColor, b:FlxColor):Void
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
		if (PlayState.instance != null && PlayState.instance.rewinding)
			return; // 回溯中：不更新命中窗口/超时状态，箭头纯视觉倒流

		// 自动游玩捷径（H-Slice 移植）：预演模式命中由 PlayState 的 botHitQueue 统一驱动，
		// 音符不再逐帧计算判定窗口（5 万级堆叠谱面下省下整段每音符更新开销）
		if (PlayState.instance != null && PlayState.instance.cpuControlled && !PlayState.instance.replayMode
			&& PlayState.instance.botplayPlan != null)
			return;
		// 视觉副本（blockHit+ignoreNote）：纯渲染用途，无需窗口/超时计算（密集段大头）
		if (blockHit && ignoreNote && density == 1)
			return;

		super.update(elapsed);

		if (mustPress)
		{
			if (PlayState.instance != null && PlayState.instance.cpuControlled && PlayState.instance.botplayPlan != null)
			{
				// 自动游玩预演模式：命中时刻在加载预演时已确定，无需逐帧计算判定窗口
				canBeHit = false;
			}
			else if (ClientPrefs.data.noteJudgment == 'KE 判定')
				// KE 判定：命中窗口与标准判定一致（早侧 1.0x）。
				// 原实现早侧 0.5x（22.5ms）过严——玩家习惯提前 20-30ms 按，窗口外且 ghostTapping 静默，
				// 表现为"断触/接不着"。KE 的严格性体现在防乱按与评分规则，而非缩短命中窗口。
				canBeHit = (strumTime > Conductor.songPosition - (Conductor.safeZoneOffset * lateHitMult) &&
							strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * earlyHitMult));
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
				if((isSustainNote && prevChainWasGoodHit()) || strumTime <= Conductor.songPosition)
					wasGoodHit = true;
			}
		}

		if (tooLate && !inEditor)
		{
			if (alpha > 0.3)
				alpha = 0.3;
		}
	}

	// 池化链判定：上一段（chartSeq-1）若已回池，用被杀瞬间的 wasGoodHit 快照；
	// 否则读存活实例；动态音符（chartSeq<0）退回指针链。
	function prevChainWasGoodHit():Bool
	{
		if (chartSeq >= 0)
		{
			var ps:Int = chartSeq - 1;
			if (ps >= 0)
			{
				if (ps < Note.seqNote.length && Note.seqNote[ps] != null) return Note.seqNote[ps].wasGoodHit;
				if (ps < Note.seqHit.length) return Note.seqHit[ps];
				return false;
			}
		}
		return prevNote != null && prevNote.wasGoodHit;
	}

	// 池化换轨兜底：复生的对象只加载过"第一条生命"所在轨道的动画，
	// 换轨时 animation.play('blueScroll') 找不到动画会停在 frame 0（紫/左箭头）——补齐全部轨道动画。
	var _animsEnsured:Bool = false;
	function ensureAllNoteAnims():Void
	{
		if (frames == null) return;
		if (_animsEnsured) return; // 每个对象只补齐一次（池化复生不再重复 12 次 getByName）
		_animsEnsured = true;
		if (PlayState.isPixelStage)
		{
			for (col in 0...colArray.length)
			{
				if (animation.getByName(colArray[col] + 'Scroll') == null)
					animation.add(colArray[col] + 'Scroll', [col + 4], 24, true);
				if (animation.getByName(colArray[col] + 'hold') == null)
					animation.add(colArray[col] + 'hold', [col], 24, true);
				if (animation.getByName(colArray[col] + 'holdend') == null)
					animation.add(colArray[col] + 'holdend', [col + 4], 24, true);
			}
			return;
		}
		for (col in 0...colArray.length)
		{
			if (animation.getByName(colArray[col] + 'Scroll') == null)
				animation.addByPrefix(colArray[col] + 'Scroll', colArray[col] + '0', 24, true);
			if (animation.getByName(colArray[col] + 'hold') == null)
				animation.addByPrefix(colArray[col] + 'hold', colArray[col] + ' hold piece', 24, true);
			if (animation.getByName(colArray[col] + 'holdend') == null)
				animation.addByPrefix(colArray[col] + 'holdend', colArray[col] + ' hold end', 24, true);
		}
		// NOTE_assets 拼写错误的紫色长条尾帧名兜底（与 loadNoteAnims 一致）
		if (animation.getByName('purpleholdend') == null)
			animation.addByPrefix('purpleholdend', 'pruple end hold', 24, true);
	}

	// H-Slice 移植：从轻量 CastNote 实例化/复生音符（对象池回收复用，避免 15 万级谱面的对象创建/销毁）
	// 与构造函数行为一致：贴图/烘焙/居中/长条样式全部重建，且可被任意次数复用。
	public function recycleNote(target:CastNote):Note
	{
		wasGoodHit = hitByOpponent = tooLate = false;
		botQueued = false;
		botSched = false;
		canBeHit = flipY = false;
		hitCausesMiss = false;
		lowPriority = false;
		missHealth = 0.0475;
		hitsound = 'hitsound';
		hitsoundChartEditor = true;
		_noteSplashData = null;
		splashSkin = null;
		_tail = null;
		_extraData = null;
		offsetX = 0;
		offsetY = 0;
		offsetAngle = target.offsetAngle;
		multAlpha = 1;
		// 构造函数默认值：长条会被置 copyAngle=false 等，复生时必须恢复（否则箭头角度/位置不再更新）
		copyX = true;
		copyY = true;
		copyAngle = true;
		copyAlpha = true;
		_engineAngleWrite = true; // 引擎复位：不触发"脚本接管旋转"逻辑
		angle = 0;
		_engineAngleWrite = false;
		scrollFactor.set(); // 音符在 camHUD 下应为 (0,0)，与旧生成路径一致
		// invalidateNote 会置 active=false/visible=false 且 kill()（alive=false/exists=false）；
		// 复生必须复活（否则 Note.update 不执行、forEachAlive 跳过——
		// canBeHit/tooLate 永不变，音符无法命中且整组被 kill-late 削没）
		alive = true;
		active = true;
		visible = true;
		exists = true;
		spawned = true;

		// ===== 池化复用：构造函数状态归零（防止上一生命残留污染下一生命）=====
		noteWasHit = false;
		eventName = '';
		eventLength = 0;
		eventVal1 = '';
		eventVal2 = '';
		earlyHitMult = 1;
		lateHitMult = 1;
		moves = false;
		flipX = false;
		color = 0xffffff;
		blend = openfl.display.BlendMode.NORMAL;
		shader = null;
		// Meteoric：像素舞台复生必须保持 NEAREST 硬边——reloadNote 已在构造时置 false，
		// 但这里无条件重置会把它改回 ClientPrefs（默认 true=LINEAR），导致下落箭头发糊
		// （人物/舞台不经此路径所以仍硬边，正是“人物硬、箭头软”不对称的原因）。
		antialiasing = PlayState.isPixelStage ? false : ClientPrefs.data.antialiasing;

		density = (target.density > 0) ? target.density : 1;
		chartSeq = target.chartSeq;
		prevNote = null;
		nextNote = null;
		parent = null;
		bakedKind = -1;

		strumTime = target.strumTime + ClientPrefs.data.noteOffset;
		mustPress = (target.noteData & (1 << 8)) != 0;
		isSustainNote = (target.noteData & (1 << 9)) != 0;
		isSustainEnds = (target.noteData & (1 << 10)) != 0;
		gfNote = (target.noteData & (1 << 11)) != 0;
		animSuffix = (target.noteData & (1 << 12)) != 0 ? "-alt" : "";
		noAnimation = noMissAnimation = (target.noteData & (1 << 13)) != 0;
		blockHit = (target.noteData & (1 << 14)) != 0;
		ignoreNote = (target.noteData & (1 << 15)) != 0;
		noteData = target.noteData & 3;

		hitsoundDisabled = isSustainNote;

		// 舞台脚本可能直接改过 CastNote 字段（PhillyStreets/PhillyBlazin）
		if (target.noAnimation) noAnimation = true;
		if (target.noMissAnimation) noMissAnimation = true;
		if (target.blockHit) blockHit = true;

		// 贴图（图集按路径缓存只解析一次；烘焙贴图命中则零解析）。
		// 先置空 noteType 再赋值，保证复生灵体时类型设置（颜色/贴图/行为）一定重新生效
		noteType = null;
		texture = '';
		// RGB 着色器启用状态按当前设置重建（构造函数同款判定：disableNoteRGB/0.6.3 兼容/
		// 关着色器/移动端强制原色；上一生命可能把它关掉，复生后必须恢复）
		if (rgbShader != null)
		{
			var useRGB:Bool = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB == true);
			if (!useRGB || ClientPrefs.data.psych063Mode || !ClientPrefs.data.shaders)
				rgbShader.enabled = false;
			else
			{
				#if mobile
				rgbShader.enabled = false;
				#else
				var skinPath:String = getNoteSkinLoadPathCached(texture, '', PlayState.isPixelStage, isSustainNote);
				rgbShader.enabled = (skinPath.indexOf('chip') < 0);
				#end
			}
		}
		var ct:String = target.noteType != null ? target.noteType : '';
		try {
			if (ct != null && ct.length > 0) noteType = ct;
		} catch (e:Dynamic) {}

		sustainLength = target.holdLength;
		multSpeed = target.multSpeed; // set_multSpeed 同步 resize 长条

		// 长条分段样式：尾段直接用 holdend 贴图/动画；非尾段一步到位换 hold（等价于构造时逐段转换）
		ensureAllNoteAnims(); // 池化换轨：补齐全部轨道动画，避免 play 失败停在左箭头帧
		correctionOffset = 0;
		if (!isSustainNote)
		{
			if (bakedKind < 0) animation.play(colArray[noteData % colArray.length] + 'Scroll', true);
		}

		if (isSustainNote)
		{
			flipY = ClientPrefs.data.downScroll;
			alpha = multAlpha = 0.6;
			copyAngle = false; // 长条不旋转（与构造函数一致）
			if (bakedKind < 0)
				animation.play(colArray[noteData % colArray.length] + (isSustainEnds ? 'holdend' : 'hold'));
			else if (!isSustainEnds && bakedKind != BAKE_HOLD)
				useBakedSustainBody();

			// 池化几何归零（构造函数同款基准）：复用对象可能带上一生命残留——
			// 箭头生命 scale=(0.7,0.7)、像素长条 _lastNoteOffX 累积；不归零会
			// 导致长条宽度错误/偏离箭头中线（Monster 截图：“长条不在主箭头中间”）
			// 构造基准：非烘焙 scale=1；烘焙 = setGraphicSize(width*0.7)（与箭头同宽）
			if (bakedKind >= 0)
			{
				setGraphicSize(Std.int(width * 0.7));
				if (isSustainEnds) scale.y = 1; // 构造期 lastScaleY=1（新鲜对象）
			}
			else
				scale.set(1, 1);
			_lastNoteOffX = 0;

			updateHitbox();

			// 构造路径的 X 居中补偿：长条中线贴合判定键（复生对象不走构造函数，这里显式补齐）
			if (!PlayState.isPixelStage)
			{
				offsetX += width / 2;
				updateHitbox();
				offsetX -= width / 2;
				if (bakedKind >= 0)
				{
					var arrowW:Float = 0;
					if (bakedLoadPath != null)
						arrowW = Note.bakedArrowRenderWidth.get(bakedLoadPath) != null ? Note.bakedArrowRenderWidth.get(bakedLoadPath) : 0;
					else
						arrowW = Note.bakedArrowRenderWidth.get(getNoteSkinLoadPath(texture, '', PlayState.isPixelStage, true)) != null ? Note.bakedArrowRenderWidth.get(getNoteSkinLoadPath(texture, '', PlayState.isPixelStage, true)) : 0;
					if (arrowW > 0) offsetX += (arrowW - width) / 2;
				}
			}
			else
			{
				offsetX += _lastNoteOffX;
				_lastNoteOffX = (width - 7) * (PlayState.daPixelZoom / 2);
				offsetX -= _lastNoteOffX;
			}

			// 非尾段：按节拍拉伸（与构造期生成时逐段应用的公式一致）
			if (!isSustainEnds)
			{
				var h0:Float = height;
				scale.y = Conductor.stepCrochet / 100 * 1.05;
				if (PlayState.instance != null) scale.y *= PlayState.instance.songSpeed;
				if (PlayState.isPixelStage)
				{
					scale.y *= 1.19;
					scale.y *= (6 / h0);
				}
				updateHitbox();
			}
			else if (PlayState.isPixelStage)
			{
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}

			// 前段链式拉伸（构造函数 600-616 同款）：本段生成时把上一段长条拉到本段起点，
			// 否则段间出现缝隙（“断尾”）或长度错误（“尾部拉长”）。池化下 prevNote 指针
			// 在函数末尾才重建，这里用静态链 Note.seqNote[chartSeq-1]（音符按时间序生成，
			// 前段必已就位）。
			{
				var psP:Int = chartSeq - 1;
				var prevS:Note = (psP >= 0 && psP < Note.seqNote.length) ? Note.seqNote[psP] : null;
				if (prevS != null && prevS.isSustainNote)
				{
					if (prevS.bakedKind >= 0)
						prevS.useBakedSustainBody();
					else
						prevS.animation.play(colArray[prevS.noteData % colArray.length] + 'hold');
					prevS.scale.y *= Conductor.stepCrochet / 100 * 1.05;
					if (PlayState.instance != null) prevS.scale.y *= PlayState.instance.songSpeed;
					if (PlayState.isPixelStage)
					{
						prevS.scale.y *= 1.19;
						prevS.scale.y *= (6 / height);
					}
					prevS.updateHitbox();
				}
			}

			correctionOffset = height / 2;
			if (ClientPrefs.data.downScroll && !PlayState.isPixelStage)
				correctionOffset = 0;
			// 构造函数同款：长条早侧窗口放宽为零（避免复用残留 1.0）
			earlyHitMult = 0;
		}
		else
		{
			alpha = multAlpha = 1;
			// 箭头复生：重置缩放（长条生命残留 scale.y≈2 → 箭头被上下拉伸）
			if (PlayState.isPixelStage) scale.set(PlayState.daPixelZoom, PlayState.daPixelZoom);
			else scale.set(0.7, 0.7);
			updateHitbox();
		}
		clipRect = null;

		// 脚本对未出生音符设定的固定角度（unspawnNotes[i].angle）带进 Note：
		// set_angle 会自动把 copyAngle 置 false → 脚本角度接管旋转，不再被每帧公式覆盖
		if (target.angle != 0)
			angle = target.angle;

		// prevNote/nextNote 链：按 chartSeq 重建（池化后旧 prev 对象已被复用，必须走静态表）
		var ps:Int = chartSeq - 1;
		if (chartSeq >= 0)
		{
			if (ps >= 0 && ps < Note.seqNote.length)
			{
				prevNote = Note.seqNote[ps];
				if (prevNote != null) prevNote.nextNote = this;
			}
			if (chartSeq >= Note.seqNote.length) Note.seqNote.resize(chartSeq + 1);
			Note.seqNote[chartSeq] = this;
		}
		return this;
	}

	// 池化专用：音符被杀/回池时调用（同步链静态表与快照，阻止新增生命污染旧链）
	public function invalidatePooled():Void
	{
		if (chartSeq >= 0 && chartSeq < Note.seqNote.length)
		{
			if (Note.seqNote[chartSeq] == this)
			{
				if (chartSeq >= Note.seqHit.length) Note.seqHit.resize(chartSeq + 1);
				Note.seqHit[chartSeq] = wasGoodHit;
				Note.seqNote[chartSeq] = null;
			}
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
		{
			// 引擎每帧公式：经标记写入，避免 set_angle 把 copyAngle 关掉（关掉后公式自身失效）
			_engineAngleWrite = true;
			angle = strumDirection - 90 + strumAngle + offsetAngle;
			_engineAngleWrite = false;
		}

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
		// 池化安全：prevNote 指针可能为 null/已被复用（链上段被回收），改用静态链查询
		if(isSustainNote && (mustPress || !ignoreNote) &&
			(!mustPress || (wasGoodHit || (prevChainWasGoodHit() && !canBeHit))))
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
