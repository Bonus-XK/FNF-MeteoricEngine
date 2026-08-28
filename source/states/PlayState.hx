package states;

// If you want to add your stage to the game, copy states/stages/Template.hx,
// and put your stage code there, then, on PlayState, search for
// "switch (curStage)", and add your stage to that list.

// If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
// "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
// "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
// "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
// "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for

import backend.Achievements;
import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Section;
import backend.Rating;
import backend.Replay;
import backend.CrashHandler;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.display.FlxTiledSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.Lib;
import tjson.TJSON as Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.ResultsSubState;
import substates.GameOverSubstate;

#if !flash 
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if VIDEOS_ALLOWED 
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideo as VideoHandler;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoHandler as VideoHandler;
#elseif (hxCodec == "2.6.0") import VideoHandler;
#else import vlc.MP4Handler as VideoHandler; #end
#end

import objects.Note.EventNote;
import objects.Note.CastNote;
import objects.Note.SpamNoteData;
import objects.NoteHitGraph.NoteHitEntry;
import objects.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.FunkinLua;
import psychlua.LuaUtils;
#if HSCRIPT_ALLOWED
import psychlua.HScript;
#end
#end

#if (SScript >= "3.0.0")
import tea.SScript;
#end

typedef PreGenResult = {
	notes:Array<CastNote>,
	noteTypes:Array<String>,
	totalNotes:Int,
	botLaneCounts:Array<Int>
}

class PlayState extends MusicBeatState
{
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['D', 0.6], //From 0% to 19%
		['C', 0.7], //From 20% to 39%
		['B', 0.8], //From 40% to 49%
		['A', 0.9], //From 50% to 59%
		['A.', 0.93], //From 60% to 68%
		['A:', 0.95], //69%
		['AA', 0.96], //From 70% to 79%
		['AA.', 0.97], //From 80% to 89%
		['AA:', 0.98], //From 90% to 99%
		['AAA', 0.983], 
		['AAA.', 0.987], 
		['AAA:', 0.99], 
		['AAAA.', 0.993], 
		['AAAA:', 0.997], 
		['AAAAA', 0.999], 
		['S', 1]
	];

	//event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();
	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();
	
	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	// Psych 0.7 兼容：舞台脚本用 game.backdropSprites 记录 FlxBackdrop（FunkinMix Dogma 等）
	public var backdropSprites:Map<String, Dynamic> = new Map<String, Dynamic>();
	#end

	#if LUA_ALLOWED
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var modchartSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	// NPS 统计：每秒收到并判定的音符数（不含长条），供 FPS 计数器显示
	public var npsDisplay:Int = 0;
	var _npsCount:Int = 0;
	var _npsTimer:Float = 0;

	// 延迟 GC（Meteoric Fix 续）：进曲 0.5s 后触发一次 System.gc()，回收被剥离的
	// 谱面 DOM/解析暂存（开局 876→660MB 的 216MB 差值来源）。
	// 40 帧回归已定位为 CastNote 代理的 Dynamic 分发（已改静态类型），GC 本身无罪；
	// 若本构建 FPS 仍掉，下一轮把 GC 移到暂停/曲终或彻底移除。
	var _deferredGC:Bool = false;
	var _deferredGCTime:Float = 0;

	// 结算拆卸锁（Meteoric Fix 续）：endSong 拆卸人物/判定线后置位；
	// update() 立即早退（结算转场/关闭回调的窗口期 PlayState 仍会被驱动，
	// 访问已销毁对象即 NRE）。重试/回退重开重建完成后复位。
	var _visualsTorn:Bool = false;

	public var playbackRate(default, set):Float = 1;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI:String = "normal";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel";

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	// ===== 游玩期谱面 DOM 释放（Meteoric Fix 续）=====
	// 桌面进曲后，chartCache 仍持有完整谱面 DOM（LRU 2）；PlayState.SONG 是第二份。
	// 大谱面游玩时把 SONG 的逐音符数组剥离（保留 section 元数据），重开/回溯/开编谱前
	// 用下面记录的身份从缓存恢复，玩法零影响、内存最高可省数百 MB。
	public static var chartJsonInput:String = null; // 谱面 json 输入（含难度后缀，如 bopeebo-hard）
	public static var chartFolder:String = null;    // 谱面目录（与 loadFromJson 第二参一致）
	static var chartSongName:String = null;         // 原始歌曲名（SONG.song 原样值，身份校验用）
	static var chartDataStripped:Bool = false;      // 当前 SONG 的逐音符数组是否已被剥离
	static var recordedChartFingerprint:String = '';// create 期（剥离前）记录的回放指纹，结算写档用

	// 加载方（LoadingState/PauseSubState）替换 SONG 时必须先登记身份，剥离才有恢复依据
	public static function registerChartSource(chartJson:String, folder:String, songName:String):Void
	{
		chartJsonInput = chartJson;
		chartFolder = folder;
		chartSongName = songName;
		chartDataStripped = false;
	}

	// SONG 的逐音符数组被剥离后，任何需要完整谱面的入口（重开/回溯/编谱）先从此恢复
	static function reloadChartSourceIfNeeded():Void
	{
		if (!chartDataStripped) return;
		if (SONG == null || chartJsonInput == null || chartSongName != SONG.song)
		{
			// 无登记身份或对象与身份不一致（如 tutorial 兜底）：放弃剥离，避免误恢复
			chartDataStripped = false;
			return;
		}
		try
		{
			var fresh:SwagSong = Song.loadFromJson(chartJsonInput, chartFolder);
			if (fresh != null)
			{
				// 保留引擎运行期派生的字段：School.setDefaultGF('gf-pixel')/vanillaSongStage 等只在
				// 首次 create 时写入 SONG（roses.json 等基础谱面本身没有这些字段）。重开从 JSON
				// 重新解析出的 fresh 会丢失它们 → GF 变普通贴图 + 位置错（快速重开 GF 瞬移 bug）。
				if (fresh.stage == null || fresh.stage.length < 1)
					fresh.stage = SONG.stage;
				if (fresh.gfVersion == null || fresh.gfVersion.length < 1)
					fresh.gfVersion = SONG.gfVersion;
				SONG = fresh; // 缓存命中（或重新解析）→ 完整 DOM 回归；后续 generateChartNotes 正常消费
			}
			else
			{
				trace('[Memory] 谱面恢复失败（缓存/文件缺失）：' + chartJsonInput);
				chartDataStripped = false;
			}
		}
		catch (e:Dynamic)
		{
			trace('[Memory] 谱面恢复异常：' + e);
			// 保留剥离标记：下次重开再试（文件丢失属极端异常，不再额外清空）
		}
	}

	// create 尾 / 重开收尾共用：剥离 SONG 逐音符 DOM + 淘汰大谱面缓存副本
	// （Flocc 级：两份 DOM 全释放后，游玩稳态只剩 CastNote + 音频 + 基线，≈400MB）
	static function releaseSongChartDom():Void
	{
		#if desktop
		if (SONG != null && chartJsonInput != null && chartSongName == SONG.song)
		{
			if (!chartDataStripped)
			{
				Song.stripSectionNotes(SONG);
				chartDataStripped = true;
			}
			Song.evictLargeChartFromCache(chartJsonInput, chartFolder);
		}
		#end
	}

	public var spawnTime:Float = 2000;

	// ===== H-Slice 移植：音符生成游标 / 快速跳谱 / 挤压音符展开 =====
	public var currentSpawnId:Int = 0;          // unspawnNotes 生成游标（不再 indexOf/splice，O(n²)→O(n)）
	var lastNoteSpawnPos:Float = -9999;         // 上次 noteSpawn 时的歌曲位置（跳变检测用）
	static inline var VISUAL_BUDGET:Int = 1800; // 场上视觉精灵预算（采样展开的全局上限）
	static inline var JUMP_DETECT_MS:Float = 1000; // 单帧前进超过该值视为"真实跳时间"，才允许 bulkSkip
	public static var spamNotes:Array<SpamNoteData> = []; // 运行时展开的挤压音符队列
	// 重叠隐藏（hideOverlapped）：每轨道上一可见音符的间距与 sus 状态
	var laneLDist:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
	var laneSusPrev:Array<Bool> = [false, false, false, false, false, false, false, false];

	public var vocals:FlxSound;
	public var opponentVocals:FlxSound; //Split vocals：对手专属人声（Voices-Opponent.ogg）
	public var inst:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:NoteGroup;
	// 安卓走"直建 Note 对象"最稳定管线（8月17 实测可用）；桌面走 CastNote 轻量管线
	#if android
	public var unspawnNotes:Array<Note> = [];
	#else
	public var unspawnNotes:Array<CastNote> = [];
	#end
	public var eventNotes:Array<EventNote> = [];
	public var cachedEventsData:Array<Dynamic> = null;   // 谱面 events 文件数据缓存（快速重开用，避免重复读盘）
	public var cachedEventNotes:Array<EventNote> = [];   // 已修正偏移与提前触发的事件缓存（快速重开用）

	public var camFollow:FlxObject;
	public var camFollowPos:FlxObject; // 0.6.3 模组兼容：与 camFollow 同一对象（旧模组 Lua 用 camFollowPos 控制相机）
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote>;
	public var opponentStrums:FlxTypedGroup<StrumNote>;
	public var playerStrums:FlxTypedGroup<StrumNote>;

	// Psych 0.6.3 兼容：默认箭头位置（供 Lua 直接 getProperty/setProperty）
	public var defaultPlayerStrumX0:Float = 0;
	public var defaultPlayerStrumY0:Float = 0;
	public var defaultPlayerStrumX1:Float = 0;
	public var defaultPlayerStrumY1:Float = 0;
	public var defaultPlayerStrumX2:Float = 0;
	public var defaultPlayerStrumY2:Float = 0;
	public var defaultPlayerStrumX3:Float = 0;
	public var defaultPlayerStrumY3:Float = 0;
	public var defaultOpponentStrumX0:Float = 0;
	public var defaultOpponentStrumY0:Float = 0;
	public var defaultOpponentStrumX1:Float = 0;
	public var defaultOpponentStrumY1:Float = 0;
	public var defaultOpponentStrumX2:Float = 0;
	public var defaultOpponentStrumY2:Float = 0;
	public var defaultOpponentStrumX3:Float = 0;
	public var defaultOpponentStrumY3:Float = 0;
	public var hudLayout:Map<String, Array<Float>>; // 自定义界面：HUD 元素相对默认位置的偏移 [x, y]
	public var isPhigrosStyle:Bool = false;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;
	public var holdCoverHandler:NoteHoldCoverHandler = null; // 原生长条按压覆盖（QT 模组 NoteHoldCover.lua 移植）

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	public var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health:Float = 1;
	public var smoothHealth:Float = 1;
	public var combo:Int = 0;
	// KE 结算界面：本局最高连击（命中后取峰值；Miss 重置 combo 不影响该值）
	public var maxCombo:Int = 0;

	public var healthBar:HealthBar;
	public var healthBarBG:AttachedSprite;
	public var timeBar:TimeBar;
	public var timeBarBG:AttachedSprite;
	public var healthBarOverlay:FlxTiledSprite;
	public var timeBarOverlay:FlxTiledSprite;
	var healthOverlayDir:Int = -1; // 血量阴影滚动方向：-1 向左（回血） / +1 向右（掉血）
	var lastHpPercent:Float = 50;
	public var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();
	public var fullComboFunction:Void->Void = null;

	// KE 结算散点图：本局逐音符判定记录 {t=音符时间, d=命中偏移(+早/-晚), r=评级}（仅内存，不进回放文件）
	public var judgementHistory:Array<NoteHitEntry> = [];

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	public var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;
	// 自动游玩预演：加载时预演生成的命中计划（每轨道命中时刻），null = 未预演（回退实时判定）
	public var botplayPlan:Array<Array<Float>> = null;
	var botLaneCounts:Array<Int> = [0, 0, 0, 0];
	// 自动游玩批处理：同帧堆叠命中先收集再统一处理，副作用（音效/粒子/动画/评分）合并，避免一帧内爆发
	var botHitQueue:Array<Note> = [];
	var botHitBatch:Bool = false;
	// 上一帧音频位置（毫秒）：用于实测自动游玩每帧前进量，精确计算命中提前量
	var lastBotSongPos:Float = 0;
	var botBatchAnimDone:Array<Bool> = [false, false, false, false];
	var botBatchSplashDone:Array<Bool> = [false, false, false, false];
	var botBatchHitsoundDone:Bool = false;
	var botBatchScoreShown:Bool = false;

	public var botplaySine:Float = 0;
	/** HUD/UI 子系统（重构）：负责全部 HUD 元素的创建、每帧更新与可见性权威 */
	public var hud:GameHUD;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var usedAutoplay:Bool = false;   // 本局是否用过自动游玩（用于判断成绩是否有效）
	public var usedGodMode:Bool = false;    // 本局是否用过上帝模式（用于判断成绩是否有效）

	public var replayMode:Bool = false;             // 本局是否为回放
	public static var queuedReplay:Replay = null;   // 待进入的回放数据（结算/选歌界面设置）
	public static var carryReplay:Replay = null;    // 暂停/死亡/重开时保留的回放数据（完整重开经 create 重新消费）
	public static var autoOpenPause:Bool = false;   // 从全屏设置页返回：重载曲目后自动挂起在暂停菜单
	var recordingReplay:Bool = false;               // 本局是否在录制
	var currentReplay:Replay = null;                // 本局录制数据
	var replayHitSeqs:Map<Int, String> = null;      // 回放：应命中的音符（chartSeq -> 事件类型/评分）
	var replayRatingSeqs:Map<Int, String> = null;   // 回放：评分查找（chartSeq -> 评分名）
	var replayPressMisses:Array<ReplayEvent> = [];  // 回放：空按事件（按时间升序，旧版回放用）
	var replayPressPtr:Int = 0;                     // 回放：空按事件游标
	var replayInputs:Array<ReplayInput> = [];       // 回放 v2：按键事件流（按下/抬起）
	var replayInputPtr:Int = 0;                     // 回放 v2：按键事件游标
	var replayHeld:Array<Bool> = [false, false, false, false]; // 回放 v2：当前按住的轨道
	var replayV2:Bool = false;                      // 回放 v2：输入级回放（含按键事件）
	var replayInjecting:Bool = false;               // 回放 v2：正在注入按键（放行 keyPressed/keyReleased）
	public var scoreTxt:FlxText;
	public var songTxt:FlxText;
	public var judgementField:openfl.text.TextField; // 判定计数侧边栏
	public var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
		public var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if desktop
	// Discord RPC variables
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end
	// 曲目难度文本（HUD 与标题栏显示用，桌面与非桌面都保留）
	public var storyDifficultyText:String = "";

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	public var luaArray:Array<FunkinLua> = [];
	#if LUA_ALLOWED
	private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;

	public var precacheList:Map<String, String> = new Map<String, String>();
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	/** 游玩中按返回键 / 左上角 X 后，在 update 末尾统一转成暂停（不退出游戏） */
	private var androidBackQueued:Bool = false;

	override public function create()
	{
		// 上一局结束时 SONG 的逐音符数组可能已被剥离：先恢复完整谱面，
		// 下面的回放指纹/生成逻辑都依赖完整 DOM
		reloadChartSourceIfNeeded();

		//trace('Playback Rate: ' + playbackRate);
		// 进曲目即丢弃上一局的运行时音符图集缓存：其 FlxGraphic 随上次退出被内存清理销毁，
		// 跨曲目复用会拿到 bitmap=null 的图集导致绘制崩溃（FlxDrawQuadsItem Null Object Reference）
		objects.Note.clearRuntimeAtlasCache();
		Paths.clearStoredMemory();

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		ClientPrefs.resetHideHud(); // 每次进入对局都恢复用户真实的 hideHud，防止 Mod 残留

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');
		fullComboFunction = fullComboUpdate;

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		usedAutoplay = cpuControlled;
		usedGodMode = false; // 上帝模式（practice）正常记分，只是不会死

		// ---- 回放模式：存在待回放数据时本局按录制内容重放 ----
		replayMode = queuedReplay != null;
		if (replayMode)
		{
			currentReplay = queuedReplay;
			queuedReplay = null;
			if (currentReplay.fingerprint.length > 0 && currentReplay.fingerprint != Replay.chartFingerprint(SONG))
			{
				// 谱面与录制时不一致，回放作废，退回普通游玩
				trace('[Replay] 谱面指纹不匹配，回放取消');
				replayMode = false;
				currentReplay = null;
			}
			if (replayMode)
			{
				currentReplay.buildDerived();
				replayHitSeqs = currentReplay.hitSeqs;
				replayRatingSeqs = currentReplay.ratingSeqs;
				replayPressMisses = currentReplay.pressMisses;
				replayPressPtr = 0;
				replayInputs = currentReplay.inputs != null ? currentReplay.inputs : [];
				replayInputPtr = 0;
				replayHeld = [false, false, false, false];
				replayV2 = currentReplay.isInputReplay;
				usedAutoplay = true; // 回放成绩不计入排行
				startOnTime = 0;     // 回放必须从头开始
			}
		}
		carryReplay = replayMode ? currentReplay : null;
		recordingReplay = !replayMode && !chartingMode && !cpuControlled && startOnTime <= 0;
		if (recordingReplay)
			currentReplay = new Replay(SONG.song, Difficulty.getString(storyDifficulty));
		else if (!replayMode)
			currentReplay = null;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();

		FlxG.cameras.setDefaultDrawTarget(camGame, true);
		CustomFadeTransition.nextCamera = camOther;

		persistentUpdate = true;
		persistentDraw = true;

		if (SONG == null)
			SONG = Song.loadFromJson('tutorial');

		// 游玩期会剥离 SONG.notes 逐音符数组（省内存）；回放指纹必须在剥离前记录，
		// 结算写档（endSong）直接复用此值，不再重扫 sectionNotes
		recordedChartFingerprint = Replay.chartFingerprint(SONG);

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		storyDifficultyText = Difficulty.getString();

		#if desktop
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if(SONG.stage == null || SONG.stage.length < 1) {
			SONG.stage = StageData.vanillaSongStage(songName);
		}
		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		if(stageData == null) { //Stage couldn't be found, create a dummy stage for preventing a crash
			stageData = StageData.dummy();
		}

		defaultCamZoom = stageData.defaultZoom;

		// Meteoric：allow-high-dpi 下窗口按物理分辨率双线性放大，pixel 舞台（Week6 等）箭头/像素
		// 会被柔化发糊；把 stage 质量切到 LOW（最近邻采样）保持硬边像素，非 pixel 舞台维持 HIGH。
		try
		{
			openfl.Lib.current.stage.quality = isPixelStage ? openfl.display.StageQuality.LOW : openfl.display.StageQuality.HIGH;
		}
		catch (e:Dynamic) {}

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else {
			if (stageData.isPixelStage)
				stageUI = "pixel";
		}
		trace('PlayState.stageUI=' + stageUI + ' stage=' + curStage);
		
		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		trace('[Stage] create stage: ' + curStage + ' | replayMode=' + replayMode + ' | isPixelStage=' + isPixelStage);

		switch (curStage)
		{
			case 'stage': new states.stages.StageWeek1(); //Week 1
			case 'spooky': new states.stages.Spooky(); //Week 2
			case 'philly': new states.stages.Philly(); //Week 3
			case 'limo': new states.stages.Limo(); //Week 4
			case 'mall': new states.stages.Mall(); //Week 5 - Cocoa, Eggnog
			case 'mallEvil': new states.stages.MallEvil(); //Week 5 - Winter Horrorland
			case 'school': new states.stages.School(); //Week 6 - Senpai, Roses
			case 'schoolEvil': new states.stages.SchoolEvil(); //Week 6 - Thorns
			case 'tank': new states.stages.Tank(); //Week 7 - Ugh, Guns, Stress
			case 'phillyStreets': new states.stages.PhillyStreets(); //Weekend 1 - Darnell, Lit Up, 2Hot
			case 'phillyBlazin': new states.stages.PhillyBlazin(); //Weekend 1 - Blazin
		}

		if(isPixelStage) {
			introSoundsSuffix = '-pixel';
		}

		add(gfGroup);
		add(dadGroup);
		add(boyfriendGroup);

		#if LUA_ALLOWED
		luaDebugGroup = new FlxTypedGroup<DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		// "GLOBAL" SCRIPTS（回放模式不加载，见 FunkinLua.new / initHScript 的 replayMode 拦截）
		#if LUA_ALLOWED
		if (!replayMode)
		{
			var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'scripts/');
			for (folder in foldersToCheck)
				for (file in FileSystem.readDirectory(folder))
				{
					if(file.toLowerCase().endsWith('.lua'))
						new FunkinLua(folder + file);
					if(file.toLowerCase().endsWith('.hx'))
						initHScript(folder + file);
				}
		}
		#end

		if (!stageData.hide_girlfriend)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
		gf = new Character(0, 0, SONG.gfVersion);
	
			startCharacterPos(gf);
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
			gfMap.set(SONG.gfVersion, gf); // 快速重开恢复默认角色用
			startCharacterScripts(gf.curCharacter);
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);
		dadMap.set(SONG.player2, dad); // 快速重开恢复默认角色用
		startCharacterScripts(dad.curCharacter);

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		boyfriendMap.set(SONG.player1, boyfriend); // 快速重开恢复默认角色用
		startCharacterScripts(boyfriend.curCharacter);

		// 暴露角色/摄像机引用给脚本（Psych 0.7.3 setSpecialObject 等价物；必须在 stage 脚本加载前设置）
		setOnScripts('dad', dad);
		setOnScripts('boyfriend', boyfriend);
		setOnScripts('gf', gf);
		setOnScripts('camGame', camGame);

		// STAGE SCRIPTS（在角色创建后加载，使 onCreate 可访问 dad/boyfriend/gf）
		#if LUA_ALLOWED
		startLuasNamed('stages/' + curStage + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		startHScriptsNamed('stages/' + curStage + '.hx');
		#end

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}

		Conductor.songPosition = -5000;

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		add(strumLineNotes);
		add(grpNoteSplashes);

		if(ClientPrefs.data.timeBarType == '歌曲名称')
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		var splash:NoteSplash = new NoteSplash(100, 100);
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		opponentStrums = new FlxTypedGroup<StrumNote>();
		playerStrums = new FlxTypedGroup<StrumNote>();

		generateSong(SONG.song);

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();
				
		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		// 0.6.3 模组兼容：camFollowPos 与 camFollow 同一对象（旧版模组 Lua 读写 camFollowPos 控制相机）
		camFollowPos = camFollow;
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);

		// 场景 createPost（Psych 1.0.4 时序：camFollow/generateSong 之后，场景可安全访问 camFollow/unspawnNotes）
		stagesFunc(function(stage:BaseStage) stage.createPost());

		moveCameraSection();

		// ===== HUD/UI 子系统（GameHUD）：时间条/血条/图标/分数/歌曲名/标签的创建、
		// 每帧更新与可见性权威全部集中于此，PlayState 只保留玩法逻辑 =====
		hud = new GameHUD(this);
		hud.build();
		Lib.application.window.title = "FNF':Meteoric Engine - Playing: " + curSong + (replayMode ? ' [回放]' : '');

		strumLineNotes.cameras = [camHUD];
		grpNoteSplashes.cameras = [camHUD];
		notes.cameras = [camHUD];

		// 原生长条按压覆盖（QT 模组 NoteHoldCover.lua 移植）：
		// 模组自带同名全局脚本时跳过原生创建，避免双份覆盖层；
		// pixel 阶段模组自带 pixelNoteSplash 图集损坏（XML 指向缺失的 spritesheet.png），不启用。
		holdCoverHandler = null;
		if (ClientPrefs.data.holdCover && !isPixelStage)
		{
			var hasModNoteHoldCover:Bool = false;
			#if LUA_ALLOWED
			for (luaScript in luaArray)
				if (luaScript != null && luaScript.scriptName.toLowerCase().endsWith('noteholdcover.lua'))
				{
					hasModNoteHoldCover = true;
					break;
				}
			#end
			if (!hasModNoteHoldCover)
			{
				holdCoverHandler = new NoteHoldCoverHandler();
				holdCoverHandler.cameras = [camHUD];
				add(holdCoverHandler);
				trace('[NoteHoldCover] 原生覆盖层已启用');
			}
			else
				trace('[NoteHoldCover] 检测到模组自带 NoteHoldCover.lua，跳过原生覆盖层（避免重复）');
		}


		startingSong = true;
		
		#if LUA_ALLOWED
		// 路径在谱面生成期（buildChartNotes）已拼好并共享；此处零字符串拼接。
		// （create 后期 GC 可能已回收来自谱面 JSON 的原始字符串——晚期拼接会读到悬垂串崩掉）
		for (ntLua in noteTypeLuaPaths)
			startLuasNamed(ntLua);

		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (ntHx in noteTypeHxPaths)
			startHScriptsNamed(ntHx);

		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;
		eventsPushed = null;

		if(eventNotes.length > 1)
		{
			for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}
		cachedEventNotes = eventNotes.copy();

		// SONG SPECIFIC SCRIPTS（回放模式不加载，见 FunkinLua.new / initHScript 的 replayMode 拦截）
		#if LUA_ALLOWED
		if (!replayMode)
		{
			var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'data/' + songName + '/');
			for (folder in foldersToCheck)
				for (file in FileSystem.readDirectory(folder))
				{
					if(file.toLowerCase().endsWith('.lua'))
						new FunkinLua(folder + file);
					if(file.toLowerCase().endsWith('.hx'))
						initHScript(folder + file);
				}
		}
		#end

		startCallback();
		RecalculateRating();

		//PRECACHING MISS SOUNDS BECAUSE I THINK THEY CAN LAG PEOPLE AND FUCK THEM UP IDK HOW HAXE WORKS
		if(ClientPrefs.data.hitsoundVolume > 0) precacheList.set('hitsound', 'sound');
		precacheList.set('missnote1', 'sound');
		precacheList.set('missnote2', 'sound');
		precacheList.set('missnote3', 'sound');

		if (PauseSubState.songName != null) {
			precacheList.set(PauseSubState.songName, 'music');
		} else if(ClientPrefs.data.pauseMusic != '无') {
			precacheList.set(Paths.formatToSongPath(ClientPrefs.data.pauseMusic), 'music');
		}

		precacheList.set('alphabet', 'image');
		resetRPC();

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		#if mobile
		FlxG.stage.addEventListener(Event.DEACTIVATE, onStageDeactivate);
		FlxG.stage.addEventListener(Event.ACTIVATE, onStageActivate);
		#end
		callOnScripts('onCreatePost');


		// 原生长条按压覆盖：模组自带 NoteHoldCover.lua 且用户关闭开关时，熄灭其脚本开关
		// （脚本自身用 UpdateBFHoldCover/UpdateDadHoldCover 门控，置 false 后其回调不再显示覆盖层，
		// 保证设置项对"模组自带脚本"同样生效）
		#if LUA_ALLOWED
		if (!ClientPrefs.data.holdCover)
		{
			for (luaScript in luaArray)
				if (luaScript != null && luaScript.scriptName.toLowerCase().endsWith('noteholdcover.lua'))
				{
					luaScript.set('UpdateBFHoldCover', false);
					luaScript.set('UpdateDadHoldCover', false);
				}
		}
		#end

		cacheCountdown();
		cachePopUpScore();
		
		for (key => type in precacheList)
		{
			//trace('Key $key is type $type');
			switch(type)
			{
				case 'image':
					Paths.image(key);
				case 'sound':
					Paths.sound(key);
				case 'music':
					Paths.music(key);
			}
		}

		// precacheList 仅在 create 内使用：用完即清，避免长曲期间残留键表
		precacheList.clear();

		super.create();
		#if mobile
		add(new objects.MobileControls());
		#end
		// 大谱面下不做同步 GC（音符对象全部存活，GC 会阻塞主线程），交给后续帧自然回收
		Paths.clearUnusedMemory(false);
		// 预解码贴图里未被本局消费的（如未出场角色）在此释放，避免残留大图
		Paths.clearPendingBitmaps();

		// 桌面内存大关：create 全部生成/脚本/HUD 完成后，SONG 逐音符 DOM 已无运行时消费方
		// （section 元数据保留；重开/回溯/编谱前由 reloadChartSourceIfNeeded 恢复）
		// 大谱面（Flocc 级）同时淘汰 chartCache 副本 —— 游玩期不保留任何完整谱面 DOM
		releaseSongChartDom();

		// 进曲 0.5s 后强制回收 DOM/解析暂存（倒计时期间，无音符生成）
		_deferredGC = true;
		_deferredGCTime = 0;
		CrashHandler.mark('PlayState.create:done');

		CustomFadeTransition.nextCamera = camOther;
		if(eventNotes.length < 1) checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				// unspawnNotes 为轻量 CastNote（H-Slice 移植）：长条高度在生成时按当前 songSpeed 计算
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		if(generatedMusic)
		{
			if(vocals != null) vocals.pitch = value;
			if(opponentVocals != null) opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				// unspawnNotes 为轻量 CastNote（H-Slice 移植）：长条高度在生成时按当前 songSpeed 计算
			}
		}
		playbackRate = value;
		FlxAnimationController.globalSpeed = value;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		setOnScripts('playbackRate', playbackRate);
		return value;
	}

	// 游玩设置改动后即时同步到当前局（暂停菜单里打开设置时调用）
	public function syncGameplaySettings():Void
	{
		var oldPractice:Bool = practiceMode;
		var oldBotplay:Bool = cpuControlled;

		playbackRate = ClientPrefs.getGameplaySetting('songspeed');
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');

		if (cpuControlled) usedAutoplay = true;

		if (practiceMode != oldPractice || cpuControlled != oldBotplay)
			changedDifficulty = true;

		if (botplayTxt != null)
		{
			botplayTxt.visible = cpuControlled || replayMode;
			botplayTxt.alpha = 1;
			botplaySine = 0;
		}

	}

	public function addTextToDebug(text:String, color:FlxColor) {
		#if LUA_ALLOWED
		var newText:DebugLuaText = luaDebugGroup.recycle(DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);
		#end
	}
	
	public function updateHUDVisibility() {
		var hide:Bool = ClientPrefs.data.hideHud;
		if (healthBar != null) healthBar.visible = !hide;
		if (healthBarOverlay != null) healthBarOverlay.visible = !hide && ClientPrefs.data.healthBarOverlay && !ClientPrefs.data.oldHealthBar;
		if (iconP1 != null) iconP1.visible = !hide;
		if (iconP2 != null) iconP2.visible = !hide;
		if (scoreTxt != null) scoreTxt.visible = !hide;
		if (timeBarOverlay != null) timeBarOverlay.visible = timeBar != null && timeBar.visible && !hide;
	}

	/**
	 * HUD 权威校验：每帧把 HUD 元素可见性强制恢复为设置值。
	 * 无论谁（Lua/Hscript/Mod/遗留代码）把 healthBar/图标/分数直接改成不可见，
	 * 下一帧都会被拉回 —— 彻底解决“游玩中 UI 突然消失”（只剩箭头和时间条）问题。
	 */
	public function enforceHUD() {
		// 已收敛到 GameHUD.enforce()（每帧可见性权威）
		if (hud != null) hud.enforce();
	}

	public function reloadHealthBarColors() {
		if (hud != null) hud.reloadHealthBarColors();
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/' + name + '.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getPreloadPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getPreloadPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		{
			scriptFile = Paths.getPreloadPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}
		
		if(doPush)
		{
			if(SScript.global.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		#if LUA_ALLOWED
		if(modchartSprites.exists(tag)) return modchartSprites.get(tag);
		if(text && modchartTexts.exists(tag)) return modchartTexts.get(tag);
		if(variables.exists(tag)) return variables.get(tag);
		#end
		return null;
	}

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public function startVideo(name:String, ?onComplete:Void->Void = null)
	{
		#if VIDEOS_ALLOWED
		inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			if(onComplete != null) onComplete();
			else startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				if(onComplete != null) onComplete();
				else startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				if(onComplete != null) onComplete();
				else startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		return;
		#end
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			precacheList.set('dialogue', 'sound');
			precacheList.set('dialogueClose', 'sound');
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;
	var gameOverTimer:FlxTimer = null; //Psych 1.0.4：deathDelay 延迟打开 Game Over 用

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);
		
		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown()
	{
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != FunkinLua.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			if (!keepStrumsOnRestart)
			{
				generateStaticArrows(0);
				generateStaticArrows(1);
			}
			keepStrumsOnRestart = false;
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
				Reflect.setProperty(this, 'defaultPlayerStrumX' + i, playerStrums.members[i].x);
				Reflect.setProperty(this, 'defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				Reflect.setProperty(this, 'defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				Reflect.setProperty(this, 'defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted', null);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				if (gf != null && tmr.loopsLeft % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith("sing") && !gf.stunned)
					gf.dance();
				if (boyfriend != null && tmr.loopsLeft % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
					boyfriend.dance();
				if (dad != null && tmr.loopsLeft % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
					dad.dance();

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				notes.forEachAlive(function(note:Note) {
					if(ClientPrefs.data.opponentStrums || note.mustPress)
					{
						note.copyAlpha = false;
						note.alpha = note.multAlpha;
						if(ClientPrefs.data.middleScroll && !note.mustPress)
							note.alpha *= 0.35;
					}
				});

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(notes), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		// H-Slice 移植：CastNote 数组用生成游标二分跳进（O(log n)），不再逐条 remove/销毁
		var firstId:Int = currentSpawnId;
		var lastId:Int = unspawnNotes.length;
		while (firstId < lastId)
		{
			var middleId:Int = (firstId + lastId) >>> 1;
			if (unspawnNotes[middleId].strumTime - 350 < time)
				firstId = middleId + 1;
			else
				lastId = middleId;
		}
		currentSpawnId = firstId;

		// 已生成的音符同样静默回收（与旧行为一致：不判 miss、不溅射）
		var i:Int = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote != null && daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				notes.invalidateNote(daNote);
			}
			--i;
		}
	}

	public function updateScore(miss:Bool = false)
	{
		if(totalPlayed != 0)
		{
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
		}

		scoreTxt.text = buildScoreText();

		// 字体：文本含中文 → 自动用 future（含中文字形）；否则用设置里的字体
		var fontPath:String;
		if (containsChinese(scoreTxt.text))
			fontPath = Paths.font('future.ttf');
		else if (ClientPrefs.data.scoreTxtFont == 'Bahnschrift')
			fontPath = Paths.font('bahnschrift.ttf');
		else
			fontPath = Paths.font('vcr.ttf');

		var txtColor:FlxColor = FlxColor.WHITE;
		if (health <= 0.4) txtColor = FlxColor.RED;
		else if (health >= 1.55) txtColor = FlxColor.LIME;

		scoreTxt.setFormat(fontPath, 15, txtColor, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.borderSize = 1.25;
		callOnScripts('onUpdateScore', [miss]);
	}

	// 是否含 CJK 汉字（用于 scoreTxt 中文字体自动切换）
	function containsChinese(s:String):Bool
	{
		if (s == null || s == '') return false;
		for (i in 0...s.length)
		{
			var c:Int = s.charCodeAt(i);
			if (c >= 0x4E00 && c <= 0x9FFF) return true;
		}
		return false;
	}

	// Score 栏文本：用 ClientPrefs.scoreTxtFormat 自定义格式 + 变量替换
	// 可用变量：
	//   {score} 分数 | {misses} Miss数 | {rank} 评级 | {accuracy} 准度(纯数字，%自己加)
	//   {nps} 每秒音符数 | {fc} FC状态 | {combo} 连击 | {health} 血量百分比
	function buildScoreText():String
	{
		var fmt:String = ClientPrefs.data.scoreTxtFormat;
		// 兼容旧“显示NPS”开关：开启且格式里没写 {nps} 时，自动在 {fc} 后追加
		if (ClientPrefs.data.showNPS && fmt.indexOf('{nps}') == -1)
			fmt = StringTools.replace(fmt, '{fc}', '{fc} | NPS: {nps}');

		var acc:String = Std.string(CoolUtil.floorDecimal(ratingPercent * 100, 2));
		// health 范围 0~2（默认 1 = 50%），换算成 0%~100%
		var healthPct:String = Std.string(Math.round(health / 2 * 100)) + '%';
		return fmt
			.replace('{score}', Std.string(songScore))
			.replace('{misses}', Std.string(songMisses))
			.replace('{rank}', ratingName)
			.replace('{accuracy}', acc)
			.replace('{nps}', Std.string(npsDisplay))
			.replace('{fc}', ratingFC)
			.replace('{combo}', Std.string(combo))
			.replace('{health}', healthPct);
	}

	public function setSongTime(time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time;
		FlxG.sound.music.pitch = playbackRate;
		FlxG.sound.music.play();

		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = time;
			opponentVocals.time = time;
			vocals.pitch = playbackRate;
			opponentVocals.pitch = playbackRate;
		}
		vocals.play();
		opponentVocals.play();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void
	{
		startingSong = false;

		@:privateAccess FlxG.sound.playMusic(inst._sound, 1, false);
		FlxG.sound.music.pitch = playbackRate;
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		stagesFunc(function(stage:BaseStage) stage.startSong()); //Psych 1.0.4：场景 startSong 钩子（Weekend 1）

		if(startOnTime > 0) setSongTime(startOnTime - 500);
		startOnTime = 0;
		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if desktop
		// Updating Discord Rich Presence (with Time Left)
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');
		CrashHandler.mark('PlayState.startSong:music-playing');
	}

	var debugNum:Int = 0;
	private var noteTypes:Array<String> = [];
	private var noteTypeLuaPaths:Array<String> = [];
	private var noteTypeHxPaths:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private function generateSong(dataPath:String):Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try
		{
			if (songData.needsVoices)
			{
				// Split vocals：Voices-Player/Voices-Opponent 存在才加载，否则回退旧版 Voices.ogg。
				// 不能用返回值判空（Paths.returnSound 找不到文件时返回空 Sound 而非 null）。
				var playerFile:String = (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile;
				if (Song.voicesFileExists(songData.song, playerFile))
					vocals.loadEmbedded(Paths.voices(songData.song, playerFile));
				else if (Song.voicesFileExists(songData.song))
					vocals.loadEmbedded(Paths.voices(songData.song));

				var oppFile:String = (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile;
				if (Song.voicesFileExists(songData.song, oppFile))
					opponentVocals.loadEmbedded(Paths.voices(songData.song, oppFile));
			}

			vocals.pitch = playbackRate;
			opponentVocals.pitch = playbackRate;

			inst = new FlxSound().loadEmbedded(Paths.inst(songData.song));
		}
		catch (e:Dynamic)
		{
			// 音频加载失败（文件损坏 / 解码器异常 / 设备音频后端异常）：
			// 降级为静音继续游玩，绝不让音频问题拖垮整局。
			// （此前无保护：异常会撞上 CrashHandler 的安卓缺陷 → 无弹窗、无日志闪退）
			trace('[Audio] 歌曲音频加载失败，降级静音继续：' + Std.string(e));
			try { vocals.loadEmbedded(new openfl.media.Sound()); } catch (e2:Dynamic) {}
			try { opponentVocals.loadEmbedded(new openfl.media.Sound()); } catch (e2:Dynamic) {}
			if (inst == null)
				try { inst = new FlxSound().loadEmbedded(new openfl.media.Sound()); } catch (e2:Dynamic) {}
			#if android
			try { extension.androidtools.widget.Toast.makeText('音频加载失败，本局静音', 0); } catch (e2:Dynamic) {}
			#end
		}
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);
		FlxG.sound.list.add(inst);

		notes = new NoteGroup();
		add(notes);

		generateChartNotes(true);
	}

	// 根据内存中的谱面数据生成音符与事件。
	// loadPhase=true 为首次加载：读取 events 文件并触发事件预加载回调（与原来行为一致）；
	// loadPhase=false 为快速重开：直接复用加载时缓存好的事件数据，不读盘、不重复触发脚本/舞台回调。
	// ===== 提前生成（LoadingState 空闲期构建整张谱面，create 时直接消费，大谱面省去 500ms+） =====
	public static var preGenNotes:Array<CastNote> = null;
	static var preGenNoteTypes:Array<String> = null;
	static var preGenTotalNotes:Int = 0;
	static var preGenBotLaneCounts:Array<Int> = null;
	static var preGenSong:String = null;

	// 长条重构（Meteoric Fix 续）：段 chartSeq 基址 = 箭头总数。
	// 与旧分配 100% 一致（箭头 0..N-1，段 N..按谱面顺序），旧回放兼容。
	static var _segmentSeqBase:Int = 0;

	// 加载界面空闲期调用：构建整张谱面的音符对象（含长条段），返回是否成功。
	// 与 create 期生成完全同一套参数（stageUI / BPM / songSpeed / playbackRate），失败时回退创建期生成。
	public static function preGenerateChart():Bool
	{
		#if android
		return false; // 安卓：使用 create 期直建 Note 管线（8月17 实测可用），禁用预生成
		#end
		if (SONG == null) return false;
		var songPath:String = Paths.formatToSongPath(SONG.song);
		// 每次加载都重建：上一轮预生成一定已被 create 消费；残留数据直接覆盖，防止跨曲/跨难度误用
		preGenNotes = null;
		preGenSong = null;

		var oldUI:String = stageUI;
		var stageName:String = SONG.stage;
		if (stageName == null || stageName.length < 1) stageName = StageData.vanillaSongStage(songPath);
		var stageData:StageFile = StageData.getStageFile(stageName);
		if (stageData == null) stageData = StageData.dummy();
		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else if (stageData.isPixelStage)
			stageUI = "pixel";

		var oldBpm:Float = Conductor.bpm;
		Conductor.bpm = SONG.bpm;
		var ok:Bool = false;
		try
		{
			var songSpeed:Float = SONG.speed;
			switch(ClientPrefs.getGameplaySetting('scrolltype'))
			{
				case "multiplicative":
					songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
				case "constant":
					songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
			}
			// 在深拷贝上构建：buildChartNotes 会清空 source 的 sectionNotes（内存大关），
			// 必须作用于副本，保证共享 SONG 数据完整（重解析/快速重开/回溯依赖它）
			var buildSrc:SwagSong = Song.copySong(SONG);
			var res:PreGenResult = buildChartNotes(buildSrc, Note.getBotplayPlan(), false,
				{ songSpeed: songSpeed }, ClientPrefs.getGameplaySetting('songspeed'), true);
			res.notes.sort(sortByTime);
			preGenNotes = res.notes;
			preGenNoteTypes = res.noteTypes;
			preGenTotalNotes = res.totalNotes;
			preGenBotLaneCounts = res.botLaneCounts;
			preGenSong = songPath;
			ok = true;
		}
		catch (e:Dynamic)
		{
			preGenNotes = null;
			preGenSong = null;
		}
		stageUI = oldUI;
		Conductor.bpm = oldBpm;
		return ok;
	}

	// 与 generateChartNotes 完全相同的音符遍历逻辑（不处理事件），供加载期预生成与创建期兜底共用
	// H-Slice 移植：只生成轻量 CastNote 结构（位打包 + 堆叠 density 合并），不创建 FlxSprite 对象；
	// 15 万级谱面的解析从"建 15 万个重对象"降为"建约 1.5 万条结构体"，解析卡顿的主要来源被移除。
	static function buildChartNotes(song:SwagSong, botplayPlan:Array<Array<Float>>, isPhigrosStyle:Bool,
			createdFrom:Dynamic, playbackRate:Float, clearSections:Bool = false):PreGenResult
	{
		// 平行数组代理（Meteoric Fix 续）：本函数是 CastNote 的唯一生产者入口，
		// 每曲构建前重置上一曲的全部槽位数据（旧对象随 unspawnNotes 丢弃）
		CastNote.resetPacked();
		var noteTypes:Array<String> = [];
		var totalNotes:Int = 0;
		var botLaneCounts:Array<Int> = botplayPlan != null ? [0, 0, 0, 0] : null;

		var arrows:Array<CastNote> = [];
		var unspawnNotes:Array<CastNote> = [];
		var chartSeqCounter:Int = 0;

		var stepCrochet:Float = ((60 / song.bpm) * 1000) / 4;
		var ghostRange:Float = ClientPrefs.data.ghostRange;
		var doGhostMerge:Bool = ClientPrefs.data.skipGhostNotes;
		var ghostDensity:Bool = ClientPrefs.data.ghostDensity;
		var lastLaneArrow:Array<CastNote> = [null, null, null, null];

		// H-Slice 挤压音符字段读取：note[3]/note[4] 为数组或 *.cmpSpam 对象时返回 [剩余数, 密度]
		function extractSpamData(note:Array<Dynamic>):Array<Float>
		{
			for (slot in [3, 4])
			{
				var field:Dynamic = note[slot];
				if (Std.isOfType(field, Array)) return cast field;
				if (field != null && Reflect.hasField(field, 'cmpSpam'))
				{
					var bd:Dynamic = Reflect.field(field, 'cmpSpam');
					if (Std.isOfType(bd, Array)) return cast bd;
				}
			}
			return null;
		}

		for (section in song.notes)
		{
			if (section.sectionNotes == null) continue;
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % 4);
				if (daNoteData < 0 || daNoteData > 3) continue;
				// Psych 1.0.4 格式：列号直接决定方向（<4 玩家、>=4 对手），不再用 mustHitSection 翻转
				var gottaHitNote:Bool = (songNotes[1] < 4);

				// ===== 堆叠合并（H-Slice 移植）：同轨 ±ghostRange 内的幽灵箭头合并为 density =====
				if (doGhostMerge)
				{
					var merged:CastNote = lastLaneArrow[daNoteData];
					if (merged != null && Math.abs(daStrumTime - merged.strumTime) <= ghostRange
						&& ((merged.noteData & (1 << 8)) != 0) == gottaHitNote)
					{
						if (ghostDensity) merged.density += 1;
						// 后台压缩 + 表面不压缩：记录该箭头相对基准的时间偏移，生成时按偏移展开回 N 个视觉箭头
						if (merged.offs == null) merged.offs = [];
						merged.offs.push(daStrumTime - merged.strumTime);
						if (gottaHitNote)
						{
							totalNotes++;
							if (botLaneCounts != null) botLaneCounts[daNoteData]++;
						}
						if (merged.holdLength < songNotes[2])
							merged.holdLength = songNotes[2];
						continue;
					}
				}
				var swagNote:CastNote = new CastNote();
				swagNote.strumTime = daStrumTime;
				swagNote.noteData = daNoteData;
				swagNote.chartSeq = chartSeqCounter++;
				swagNote.density = 1;
				swagNote.holdLength = songNotes[2] != null ? songNotes[2] : 0;
				swagNote.noteType = null;
				swagNote.multSpeed = 1;
				swagNote.cmpSpam = null;
				swagNote.offs = null;
				swagNote.noAnimation = false;
				swagNote.noMissAnimation = false;
				swagNote.blockHit = false;
				if (gottaHitNote) swagNote.noteData |= 1 << 8; // mustHit
				// Psych 1.0.4 gfNote 判定：gf 段落中，与 mustHitSection 同方向的列由 GF 演奏
				if (section.gfSection == true && gottaHitNote == section.mustHitSection)
					swagNote.noteData |= 1 << 11; // gfNote

				var noteType:Dynamic = songNotes[3];
				var typeStr:String = '';
				if (Std.isOfType(noteType, String))
					typeStr = noteType;
				else if (noteType != null)
					typeStr = ChartingState.noteTypeList[noteType]; //Backward compatibility + Week 7 charts
				// 固化拷贝：来自 JSON DOM 的字符串在 GC 后可能悬垂（安卓 hxcpp 实测），
				// 这里生成全新字符串对象并立即被 noteTypes/类字段引用
				swagNote.noteType = ('' + typeStr);

				if (typeStr == 'Alt Animation') swagNote.noteData |= 1 << 12; // altAnim
				if (typeStr == 'No Animation') swagNote.noteData |= 1 << 13; // noAnim & noMissAnim

				// 挤压音符探测门禁：仅在非标准（note[3] 非字符串）时做 Reflect 检查——
				// 标准谱面 2.26M 音符省去每颗 2 次 hasField（约 4 秒解析时间）
				if (!isPhigrosStyle && !Std.isOfType(songNotes[3], String))
				{
					var burst:Array<Float> = extractSpamData(cast songNotes);
					if (burst != null) swagNote.cmpSpam = burst;
				}

				arrows.push(swagNote);
				lastLaneArrow[daNoteData] = swagNote;

				if (gottaHitNote)
				{
					totalNotes += Std.int(swagNote.density);
					if (botLaneCounts != null) botLaneCounts[daNoteData] += Std.int(swagNote.density);
				}

				if (!noteTypes.contains(typeStr)) noteTypes.push('' + typeStr);
			}
		}

		// 长条分段：与旧实现赋值顺序一致（箭头 chartSeq 之后紧跟其子段），保证链与回放兼容
		for (swagNote in arrows)
		{
			unspawnNotes.push(swagNote);

			var susLength:Float = swagNote.holdLength;
			if (Math.isNaN(susLength)) susLength = 0.0;
			swagNote.holdLength = susLength;
			susLength /= stepCrochet;
			var floorSus:Int = Math.floor(susLength);
			if (botplayPlan != null && (swagNote.noteData & (1 << 8)) != 0)
			{
				if (floorSus > 0) botLaneCounts[swagNote.noteData & 255] += Std.int((floorSus + 1) * swagNote.density);
			}
			// ===== 长条重构（Meteoric Fix 续）：不再生成独立段的 CastNote =====
			// 尾巴在箭头出生时由 PlayState.spawnHoldTail 一次性用构造函数建好：
			// 几何（居中/宽度/链式拉伸/holdend 圆润收尾）100% 确定；Lua 接口
			// note.tail / note.parent / isSustainNote / isSustainEnds / sustainLength 保留。
			// chartSeq 顺序保持不变（箭头 0..N-1，段 N..按谱面顺序），旧回放兼容。
		}
		// 段序号基址 = 箭头总数（与旧 chartSeq 分配 100% 一致：箭头先编号，段随后按谱面顺序）
		_segmentSeqBase = unspawnNotes.length;

		unspawnNotes.sort(sortByTime);

		// 内存大关：只有对【副本】构建时才允许清空（clearSections=true）；
		// 共享的 PlayState.SONG/谱面缓存永不在此被清空（否则重解析=0 音符空轨道）。
		if (clearSections && song.notes != null)
			for (sec in song.notes)
				if (sec != null) sec.sectionNotes = null;

		return { notes: unspawnNotes, noteTypes: noteTypes, totalNotes: totalNotes, botLaneCounts: botLaneCounts };
	}

	// 谱面生成期即拼接完整脚本路径（create 后期才拼接会读到 GC 后悬垂的字符串）
	inline function rebuildNoteTypePaths():Void
	{
		noteTypeLuaPaths = [];
		noteTypeHxPaths = [];
		for (nt in noteTypes)
		{
			if (nt == null || nt.length < 1) continue;
			var path:String = 'custom_notetypes/' + nt;
			noteTypeLuaPaths.push(path + '.lua');
			noteTypeHxPaths.push(path + '.hx');
		}
	}

	private function generateChartNotes(loadPhase:Bool):Void
	{
		// 重开/回溯路径可能带着被剥离的 SONG：先恢复完整逐音符 DOM 再生成
		reloadChartSourceIfNeeded();
		// 生成完成后标记 done（原生崩溃时日志簿显示最终到达的阶段）
		totalNotes = 0;
		botplayPlan = Note.getBotplayPlan();
		if (botplayPlan != null) botLaneCounts = [0, 0, 0, 0];
		var songData = SONG;
		noteTypes = [];
		noteTypeLuaPaths = [];
		noteTypeHxPaths = [];
		eventsPushed = [];
		var chartSeqCounter:Int = 0;

		var noteData:Array<SwagSection> = songData.notes;

		if (loadPhase)
		{
			if (cachedEventsData == null)
			{
				var file:String = Paths.json(songName + '/events');
				#if MODS_ALLOWED
				if (FileSystem.exists(Paths.modsJson(songName + '/events')) || FileSystem.exists(file)) {
				#else
				if (OpenFlAssets.exists(file)) {
				#end
					cachedEventsData = Song.loadFromJson('events', songName).events;
				}
				else {
					cachedEventsData = [];
				}
			}
			for (event in cachedEventsData) //Event Notes
				for (i in 0...event[1].length)
					makeEvent(event, i);
		}
		else
		{
			for (event in cachedEventNotes)
				eventNotes.push(event);
		}

		#if android
		// ===== 安卓最稳定管线：备份式直建 Note 对象（8月17 实机验证可用）=====
		// 不使用 CastNote/对象池/回收；音符在生成期直接创建，noteSpawn 按时间插入。
		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var daNoteData:Int = Std.int(songNotes[1] % 4);
				// Psych 1.0.4 格式：列号直接决定方向（<4 玩家、>=4 对手）。
				// 谱面在加载时已由 convertToPsychV1 转成该格式（mustHitSection 已烘焙进列号），
				// 与桌面 buildChartNotes 语义一致；旧逻辑再加 mustHitSection 翻转会把
				// 对手段（mustHitSection=false + 列 4-7）翻成玩家 → 对手箭头全跑到玩家侧。
				var gottaHitNote:Bool = (songNotes[1] < 4);

				var oldNote:Note;
				if (unspawnNotes.length > 0)
					oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
				else
					oldNote = null;

				var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote, false, false, null);
				swagNote.chartSeq = chartSeqCounter++;
				swagNote.mustPress = gottaHitNote;
				swagNote.sustainLength = songNotes[2];
				swagNote.gfNote = (section.gfSection == true && songNotes[1] < 4);
				swagNote.noteType = songNotes[3];
				if (!Std.isOfType(songNotes[3], String)) swagNote.noteType = ChartingState.noteTypeList[songNotes[3]];

				swagNote.scrollFactor.set();

				var susLength:Float = swagNote.sustainLength;
				susLength = susLength / Conductor.stepCrochet;
				unspawnNotes.push(swagNote);

				var floorSus:Int = Math.floor(susLength);
				if (botplayPlan != null && gottaHitNote)
				{
					botLaneCounts[daNoteData]++;
					if (floorSus > 0) botLaneCounts[daNoteData] += floorSus + 1;
				}
				if (floorSus > 0)
				{
					for (susNote in 0...floorSus + 1)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
						var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote), daNoteData, oldNote, true, false, null);
						sustainNote.chartSeq = chartSeqCounter++;
						sustainNote.mustPress = gottaHitNote;
						sustainNote.gfNote = (section.gfSection == true && songNotes[1] < 4);
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						swagNote.tail.push(sustainNote);
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);

						sustainNote.correctionOffset = swagNote.height / 2;
						if (!PlayState.isPixelStage)
						{
							if (oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
								oldNote.scale.y /= playbackRate;
								oldNote.updateHitbox();
							}
							if (ClientPrefs.data.downScroll && !isPhigrosStyle)
								sustainNote.correctionOffset = 0;
						}
						else if (oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.updateHitbox();
						}

						if (sustainNote.mustPress) sustainNote.x += FlxG.width / 2;
						else if (ClientPrefs.data.middleScroll)
						{
							sustainNote.x += 310;
							if (daNoteData > 1) sustainNote.x += FlxG.width / 2 + 25;
						}
					}
				}

				if (swagNote.mustPress) swagNote.x += FlxG.width / 2;
				else if (ClientPrefs.data.middleScroll)
				{
					swagNote.x += 310;
					if (daNoteData > 1) swagNote.x += FlxG.width / 2 + 25;
				}

				if (!noteTypes.contains(swagNote.noteType)) noteTypes.push(swagNote.noteType);
				if (gottaHitNote) totalNotes++;
			}
		}
		#else
		var consumedPreGen:Bool = loadPhase && preGenNotes != null && preGenSong == Paths.formatToSongPath(SONG.song);
		if (consumedPreGen)
		{
			// 消费加载期预生成的音符（已排序、已含 chartSeq 链）
			unspawnNotes = preGenNotes;
			preGenNotes = null;
			preGenSong = null;
			noteTypes = preGenNoteTypes;
			preGenNoteTypes = null;
			rebuildNoteTypePaths();
			totalNotes = preGenTotalNotes;
			if (botplayPlan != null) botLaneCounts = preGenBotLaneCounts;
			preGenBotLaneCounts = null;
		}
		else
		{
			// 兜底：预生成不可用（快速重开/预生成失败）时生成轻量 CastNote（与预生成同一路径）。
			// 同样在副本上构建：共享 SONG 的 sectionNotes 必须保持完整（本函数会被
			// 快速重开/回溯再次调用，清空共享数据会导致后续重解析产出 0 音符）
			var buildSrc2:SwagSong = Song.copySong(SONG);
			var res:PreGenResult = buildChartNotes(buildSrc2, botplayPlan, isPhigrosStyle,
				{ songSpeed: songSpeed }, playbackRate, true);
			unspawnNotes = res.notes;
			noteTypes = res.noteTypes;
			rebuildNoteTypePaths();
			totalNotes = res.totalNotes;
			if (botplayPlan != null) botLaneCounts = res.botLaneCounts;
		}
		#end
		if (loadPhase)
		{
			for (event in songData.events) //Event Notes
				for (i in 0...event[1].length)
					makeEvent(event, i);
		}

		if (botplayPlan != null)
		{
			// 校验预演与正式生成完全一致（同一遍历逻辑下必然一致；不一致时回退实时判定，防止错位）
			for (lane in 0...4)
				if (botLaneCounts[lane] != botplayPlan[lane].length)
				{
					botplayPlan = null;
					break;
				}
		}
		#if android
		unspawnNotes.sort(sortByTime);
		#else
		if (!consumedPreGen) unspawnNotes.sort(sortByTime);
		#end
		generatedMusic = true;
		CrashHandler.mark('PlayState.generateChartNotes:done');
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);
			
			case 'Play Sound':
				precacheList.set(event.value1, 'sound');
				Paths.sound(event.value1);
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != FunkinLua.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua

	// ---- 自定义界面：HUD 布局偏移 ----
	public function hudGetOffset(id:String):Array<Float>
	{
		// 防御：旧存档/异常数据下 hudLayout 可能是 null 或 haxe.Json 还原的匿名对象
		// （Map 经 JSON 往返后 .exists()/.get() 会抛 Null Object Reference）——
		// 任何异常都回退默认 [0,0]，绝不因布局数据拖垮整局
		var layout:Dynamic = ClientPrefs.data.hudLayout;
		if (layout != null)
		{
			try
			{
				if (layout.exists(id)) return cast layout.get(id);
			}
			catch (e:Dynamic) {}
		}
		var arr:Array<Float> = [0, 0];
		if (layout != null)
		{
			try { layout.set(id, arr); } catch (e:Dynamic) {}
		}
		return arr;
	}

	// 重置某个 HUD 元素到默认位置（偏移清零并立即重排）
	public function hudResetElement(id:String)
	{
		try { ClientPrefs.data.hudLayout.set(id, [0, 0]); } catch (e:Dynamic) {}
		repositionHUD();
	}

	// 按保存的偏移重算所有 HUD 元素位置（默认位置 + 偏移），自定义界面拖动/重置时使用
	public function repositionHUD()
	{
		if (strumLineNotes == null) return;

		// 音符 / Phigros 判定线
		var noteOff:Array<Float> = hudGetOffset('note');
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = (ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50);
		for (i in 0...strumLineNotes.members.length)
		{
			var strum:StrumNote = strumLineNotes.members[i];
			var px:Float = strumLineX + (i * Note.swagWidth) + noteOff[0];
			if (i < 4 && ClientPrefs.data.middleScroll)
			{
				px += 310;
				if (i > 1) px += FlxG.width / 2 + 25;
			}
			strum.x = px;
			strum.y = strumLineY + noteOff[1];
		}
		// 时间条（含时间文字、Autoplay 提示）
		if (timeBar != null)
		{
			var timeOff:Array<Float> = hudGetOffset('timeBar');
			var tbY:Float = 19;
			if (ClientPrefs.data.downScroll) tbY = FlxG.height - 44 - 25;
			timeBar.y = tbY + timeOff[1];
			timeBar.screenCenter(X);
			timeBar.x += timeOff[0];

			if (timeBarOverlay != null) { timeBarOverlay.x = timeBar.x; timeBarOverlay.y = timeBar.y; }
			if (timeTxt != null)
			{
				var txtBase:Float = 25 + (ClientPrefs.data.timeBarType == '歌曲名称' ? 3 : 0);
				timeTxt.x = STRUM_X + (FlxG.width / 2) - 248 + timeOff[0];
				timeTxt.y = timeBar.y + txtBase;
				if (ClientPrefs.data.downScroll) timeTxt.y = FlxG.height - 44 + timeOff[1];
			}
			if (botplayTxt != null)
			{
				botplayTxt.y = timeBar.y + 55;
				if (ClientPrefs.data.downScroll) botplayTxt.y = timeBar.y - 78;
			}
		}

		// 血量条（含图标、阴影）
		if (healthBar != null)
		{
			var hpOff:Array<Float> = hudGetOffset('healthBar');
			var hbY:Float = FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11) + hpOff[1];
			healthBar.y = hbY;
			healthBar.screenCenter(X);
			healthBar.x += hpOff[0];

			if (healthBarOverlay != null) { healthBarOverlay.x = healthBar.x; healthBarOverlay.y = healthBar.y; }
			// 图标强绑定血量条（y 跟随，x 由 update 按 barCenter 计算）
			if (iconP1 != null) iconP1.y = healthBar.y - 75;
			if (iconP2 != null) iconP2.y = healthBar.y - 75;
		}

		// 计分文字：以默认血量条位置为基准，与血量条当前偏移解耦
		var defaultHpY:Float = FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11);
		var scoreY:Float = ClientPrefs.data.downScroll ? 5 : defaultHpY + 55;
		var scoreOff:Array<Float> = hudGetOffset('score');
		if (scoreTxt != null)
		{
			scoreTxt.x = scoreOff[0];
			scoreTxt.y = scoreY + scoreOff[1];
		}

		// 左下角水印：独立定位
		var wmOff:Array<Float> = hudGetOffset('watermark');
		if (songTxt != null)
		{
			songTxt.x = 12 + wmOff[0];
			songTxt.y = scoreY + wmOff[1];
		}

		// 判定计数侧边栏：位置由 GameHUD.updateJudgementTxt 每帧管理（openfl TextField）

	}

	private function generateStaticArrows(player:Int):Void
	{
		var hudNoteOff:Array<Float> = hudGetOffset('note');
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = (ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50);
		strumLineX += hudNoteOff[0];
		strumLineY += hudNoteOff[1];
		for (i in 0...4)
		{
			// FlxG.log.add(i);
			var targetAlpha:Float = 1;
			if (player < 1)
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween)
			{
				//babyArrow.y -= 10;
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (player == 1)
				playerStrums.add(babyArrow);
			else
			{
				if(ClientPrefs.data.middleScroll)
				{
					babyArrow.x += 310;
					if(i > 1) { //Up and Right
						babyArrow.x += FlxG.width / 2 + 25;
					}
				}
				opponentStrums.add(babyArrow);
			}

			strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}

			if (startTimer != null && !startTimer.finished) startTimer.active = false;
			if (finishTimer != null && !finishTimer.finished) finishTimer.active = false;
			if (songSpeedTween != null) songSpeedTween.active = false;

			var chars:Array<Character> = [boyfriend, gf, dad];
			for (char in chars)
				if(char != null && char.colorTween != null)
					char.colorTween.active = false;

			#if LUA_ALLOWED
			for (tween in modchartTweens) tween.active = false;
			for (timer in modchartTimers) timer.active = false;
			#end
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong)
			{
				resyncVocals();
			}

			if (startTimer != null && !startTimer.finished) startTimer.active = true;
			if (finishTimer != null && !finishTimer.finished) finishTimer.active = true;
			if (songSpeedTween != null) songSpeedTween.active = true;

			var chars:Array<Character> = [boyfriend, gf, dad];
			for (char in chars)
				if(char != null && char.colorTween != null)
					char.colorTween.active = true;

			#if LUA_ALLOWED
			for (tween in modchartTweens) tween.active = true;
			for (timer in modchartTimers) timer.active = true;
			#end

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);

			#if mobile
			// 恢复游戏触控板
			if (objects.MobileControls.instance != null)
			{
				objects.MobileControls.instance.visible = true;
			}
			#end
		}

		super.closeSubState();
	}

	override public function onFocus():Void
	{
		if (health > 0 && !paused) resetRPC(Conductor.songPosition > 0.0);
		// Meteoric：从后台回到前台时恢复被冻结的音频（游戏仍停留在暂停菜单，等玩家手动返回）
		#if mobile
		restoreBackgroundAudio();
		#end
		super.onFocus();
	}

	override public function onFocusLost():Void
	{
		#if desktop
		if (health > 0 && !paused) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end

		#if mobile
		// 退到后台时立即暂停，避免“看似暂停实际还在运行”
		if (startedCountdown && !endingSong && !paused && canPause)
			openPauseMenu();
		#end

		super.onFocusLost();
	}

	// Updating Discord Rich Presence.
	function resetRPC(?cond:Bool = false)
	{
		#if desktop
		if (cond)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.play();
		FlxG.sound.music.pitch = playbackRate;
		Conductor.songPosition = FlxG.sound.music.time;
		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = Conductor.songPosition;
			opponentVocals.time = Conductor.songPosition;
			vocals.pitch = playbackRate;
			opponentVocals.pitch = playbackRate;
		}
		vocals.play();
		opponentVocals.play();
	}

	public var paused:Bool = false;
	// Meteoric：后台音频冻结标记（退后台时暂停 music/vocals/opponentVocals，回前台恢复）
	var _bgAudioFrozen:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;

	// ===== H-Slice 移植：音符生成系统（生成游标 O(n) / 快速跳谱 / 挤压音符展开 / 可见性裁剪） =====

	inline function spawnWindowFor(target:CastNote):Float
	{
		var t:Float = spawnTime * playbackRate;
		if (songSpeed < 1) t /= songSpeed;
		if (target.multSpeed < 1) t /= target.multSpeed;
		return t;
	}

	function noteSpawn():Void
	{
		#if android
		// ===== 安卓：备份式按时间插入（直建 Note 管线配套）=====
		if (unspawnNotes.length > 0)
		{
			var time:Float = spawnTime * playbackRate;
			if (songSpeed < 1) time /= songSpeed;
			if (unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;
			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				dunceNote.spawned = true;
				callOnLuas('onSpawnNote', [notes.members.indexOf(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				callOnHScript('onSpawnNote', [dunceNote]);
				unspawnNotes.splice(0, 1);
			}
		}
		return;
		#end
		if (currentSpawnId >= unspawnNotes.length)
		{
			spamSpawn();
			if (ClientPrefs.data.fastSort) notes.fasterSort();
			return;
		}

		var fixedPosition:Float = Conductor.songPosition - ClientPrefs.data.noteOffset;
		// 快速跳谱（bulkSkip）：只允许在"真实时间跳变"（单帧前进 > JUMP_DELTA 或显式跳时间）时
		// 静默消费已过音符；正常逐帧（含轻度卡顿 GC 掉帧）一律不消费——音符永远按窗口逐帧生成，
		// 杜绝"一小段箭头随机消失、结算总数对不上"的问题。
		if (ClientPrefs.data.bulkSkip && ClientPrefs.data.optimizeSpawnNote
			&& (Conductor.songPosition - lastNoteSpawnPos > JUMP_DETECT_MS))
		{
			var skipped:Int = 0;
			var firstId:Int = currentSpawnId;
			var lastId:Int = unspawnNotes.length;
			while (firstId < lastId)
			{
				var middleId:Int = (firstId + lastId) >>> 1;
				if (unspawnNotes[middleId].strumTime <= Conductor.songPosition)
					firstId = middleId + 1;
				else
					lastId = middleId;
			}
			skipped = firstId - currentSpawnId;
			if (skipped > 0)
				trace('[BULKSKIP] consumed=' + skipped + ' at pos=' + Std.int(Conductor.songPosition)
					+ ' delta=' + Std.int(Conductor.songPosition - lastNoteSpawnPos) + 'ms');
			currentSpawnId = firstId;
		}

		var limitCount:Int = 0;
		var limitNotes:Int = ClientPrefs.data.limitNotes;
		if (limitNotes > 0) limitCount = notes.countLiving();

		// 全局视觉预算（每 500ms 统计一次，不再逐帧走查 4096 条）
		if (Conductor.songPosition - lastVisBudgetCalc > 500)
		{
			lastVisBudgetCalc = Conductor.songPosition;
			var castsInWin:Int = 0;
			var walk:Int = currentSpawnId;
			var probeEnd:Float = fixedPosition + spawnTime * 2;
			while (walk < unspawnNotes.length && castsInWin < 4096)
			{
				if (unspawnNotes[walk].strumTime > probeEnd) break;
				castsInWin++;
				walk++;
			}
			if (castsInWin > 0)
			{
				clusterVisCap = Std.int(VISUAL_BUDGET / castsInWin);
				if (clusterVisCap > 12) clusterVisCap = 12;
				if (clusterVisCap < 3) clusterVisCap = 3;
			}
			else clusterVisCap = 12;
		}

		if (currentSpawnId == 0) CrashHandler.mark('PlayState.noteSpawn:start');

		var spawnBudget:Int = ClientPrefs.data.limitNotes > 0 ? limitNotes + 512 : 8192;

		var processed:Int = 0;
		while (currentSpawnId < unspawnNotes.length && processed < spawnBudget)
		{
			if (limitNotes > 0 && limitCount >= limitNotes) break;
			// 桌面：静态类型访问 CastNote 平行数组代理（getter 内联，不走 Dynamic __Field 分发；
			// 安卓保持 Dynamic：unspawnNotes 是 Note 实体数组）
			#if android
			var target:Dynamic = unspawnNotes[currentSpawnId];
			#else
			var target:CastNote = unspawnNotes[currentSpawnId];
			#end
			if (target.strumTime - fixedPosition > spawnWindowFor(target)) break;

			// 挤压音符（H-Slice 谱面字段 cmpSpam）：运行时展开，不预建
			if (target.cmpSpam != null)
			{
				spamNotes.push(new SpamNoteData(
					Std.isOfType(target.cmpSpam[0], Float) ? target.cmpSpam[0] : Std.parseFloat(Std.string(target.cmpSpam[0])),
					Std.isOfType(target.cmpSpam[1], Float) ? target.cmpSpam[1] : Std.parseFloat(Std.string(target.cmpSpam[1])),
					target));
				target.cmpSpam = null;
				spamSpawn();
				limitCount = limitNotes > 0 ? notes.countLiving() : limitCount;
			}
			else
			{
				spawnOneWithTail(target);
				processed++;
				limitCount++;
			}
			currentSpawnId++;
		}

		lastNoteSpawnPos = Conductor.songPosition;

		// ===== 排期命中（架构修复）：到点直接入队，规避 alive-loop 哨兵饿死 =====
		if (cpuControlled && botplayPlan == null && botSchedule.length > 0)
		{
			// 用上帧实测帧步长补偿：密集段帧间隔大（50-180ms），按实时延迟提前入队 → 评级落在 Sick 中心
			lastSchedulePos = Conductor.songPosition;
			// 命中时刻弹出：音符到达判定线（strumTime）当帧入队并命中销毁（+1ms 对齐帧边界）。
			// 击杀竞态已由 botSched 排期保护杜绝，不再需要提前弹出——
			// 提前弹出会让音符在到达判定线之前就被击毁（视觉穿帮）
			var sp:Float = Conductor.songPosition + 1;
			var wi:Int = 0;
			while (wi < botSchedule.length)
			{
				var sn2:Note = botSchedule[wi];
				if (sn2 == null || !sn2.exists || sn2.wasGoodHit)
				{
					// swap-pop：O(1) 出队（splice 是 O(n)，密集段每帧上千次出队会卡死主线程）
					if (sn2 != null) sn2.botSched = false;
					botSchedule[wi] = botSchedule[botSchedule.length - 1];
					botSchedule.pop();
					continue;
				}
				if (sn2.botQueued)
				{
					// alive-loop 已抢先入队：只出队不重复推
					sn2.botSched = false;
					botSchedule[wi] = botSchedule[botSchedule.length - 1];
					botSchedule.pop();
					continue;
				}
				if (sn2.strumTime <= sp && !sn2.blockHit && !sn2.ignoreNote)
				{
					sn2.botQueued = true;
					sn2.botSched = false;
					botHitQueue.push(sn2);
					botSchedule[wi] = botSchedule[botSchedule.length - 1];
					botSchedule.pop();
					continue;
				}
				wi++;
			}
			// 安全上限：全曲基准峰值 ~17k；超过即概率性丢到期——宁可保留绝不丢（每颗被入队/击杀后即出队）
			if (botSchedule.length > 131072)
				botSchedule.splice(0, botSchedule.length - 131072);
		}

	}

	var clusterVisCap:Int = 12; // 每簇视觉采样上限（noteSpawn 每 500ms 按窗口密度动态调整）
	var lastVisBudgetCalc:Float = -99999;
	var botSchedule:Array<Note> = []; // 生成即排期的自动命中队列（不依赖 alive-loop）
	var lastSchedulePos:Float = -99999;
	var botBatchSeenSeq:Map<Int, Bool> = new Map<Int, Bool>(); // 批内计分去重（同 chartSeq 只记一次）

	/** 实例化一个音符（对象池复用）并触发 onSpawnNote 回调。
	 *  堆叠合并组（offs != null）在此展开：后台一条 CastNote，画面与原版一致（N 个独立视觉箭头）。 */
	// ===== 长条重构：箭头出生时一次性构建整根尾巴 =====
	// 段 Note 由构造函数创建（prevNote 逐段链接 → 自动切 hold/链式拉伸/holdend 圆润收尾），
	// 与安卓直建管线同款；登记 note.tail（Lua 接口）与 seqNote 静态链（判定/回放）。
	// 安卓：unspawnNotes 为 Note 实体数组（无 CastNote 代理），参数用 Dynamic
	#if android
	function spawnHoldTail(arrow:Note, target:Dynamic):Void
	#else
	function spawnHoldTail(arrow:Note, target:CastNote):Void
	#end
	{
		var holdLen:Float = target.holdLength;
		if (Math.isNaN(holdLen) || holdLen <= 0) return;
		var stepCrochet:Float = ((60 / SONG.bpm) * 1000) / 4;
		var floorSus:Int = Math.floor(holdLen / stepCrochet);
		if (floorSus < 0) floorSus = 0;

		var prev:Note = arrow;
		var segCount:Int = floorSus + 1;
		for (i in 0...segCount)
		{
			var seg:Note = new Note(target.strumTime + stepCrochet * i, target.noteData & 3,
				prev, true, false, PlayState.instance);
			// 字段（与安卓 generateChartNotes 直建路径同款）
			seg.chartSeq = _segmentSeqBase++;
			seg.mustPress = (target.noteData & (1 << 8)) != 0;
			seg.gfNote = (target.noteData & (1 << 11)) != 0;
			seg.isSustainEnds = (i == segCount - 1);
			seg.animSuffix = (target.noteData & (1 << 12)) != 0 ? "-alt" : "";
			seg.noAnimation = seg.noMissAnimation = (target.noteData & (1 << 13)) != 0;
			seg.blockHit = (target.noteData & (1 << 14)) != 0;
			seg.ignoreNote = (target.noteData & (1 << 15)) != 0;
			seg.sustainLength = 0; // 段自身无长度；尾巴长度由箭头 holdLength 表达
			var ct:String = target.noteType != null ? target.noteType : '';
			if (ct != null && ct.length > 0) seg.noteType = ct;
			seg.scrollFactor.set();
			seg.correctionOffset = seg.height / 2;
			if (ClientPrefs.data.downScroll && !PlayState.isPixelStage)
				seg.correctionOffset = 0;
			// 尾段强制圆润收尾 + 复位高度（构造链可能已把它切成 hold 主体帧）
			if (seg.isSustainEnds)
			{
				seg.animation.play(Note.colArray[seg.noteData % Note.colArray.length] + 'holdend');
				seg.scale.y = 1;
				seg.updateHitbox();
			}
			// Lua 接口：note.tail / note.parent（懒加载 getter，池化箭头天然干净）
			arrow.tail.push(seg);
			seg.parent = arrow;
			// 池化安全判定链：静态表登记
			if (seg.chartSeq >= 0)
			{
				if (seg.chartSeq >= Note.seqNote.length) Note.seqNote.resize(seg.chartSeq + 1);
				Note.seqNote[seg.chartSeq] = seg;
			}
			prev = seg;
			notes.addNoteObject(seg);
		}
	}

	// 真箭头出生入口：spawn 视觉后整根尾巴（视觉复制/挤压展开不走此入口）
	// 安卓：unspawnNotes 为 Note 实体数组（无 CastNote 代理），参数用 Dynamic
	#if android
	function spawnOneWithTail(target:Dynamic):Note
	#else
	function spawnOneWithTail(target:CastNote):Note
	#end
	{
		var hadOffs:Bool = target.offs != null; // 合并簇：尾巴已在上方 offs 分支挂到 base
		var n:Note = spawnOne(target);
		if (!hadOffs && target.holdLength > 0 && target.chartSeq >= 0)
			spawnHoldTail(n, target);
		return n;
	}

	// 桌面：静态类型参数，CastNote 平行数组代理的字段访问全部走内联 getter；
	// 安卓保留 Dynamic（unspawnNotes 为 Note 实体数组，字段集不同）
	#if android
	function spawnOne(target:Dynamic):Note
	#else
	function spawnOne(target:CastNote):Note
	#end
	{
				// ===== 表面不压缩 + 渲染可控：合并簇=1 条 CastNote（后台已压缩），
	// 展开为 up to MAX_CLUSTER_VISUALS 颗**均匀采样**的视觉箭头（覆盖 0→全跨度，视觉密度与原版一致），
	// 基准音符 density=簇总颗数（一击记整簇×N），采样副本 ignoreNote+blockHit（纯视觉不参与判定）。
	// 效果：1.2ms 级流段（522BPM）场上精灵数 ↓2.5 倍，渲染不再崩，且整簇密集箭头"可打满"。
	// 注意：offs 数组被长条子段共享（offs = swagNote.offs），绝不能清空/销毁它——只断开自身引用
	if (target.offs != null && target.offs.length > 0)
	{
		var offs:Array<Float> = target.offs;
		var base:CastNote = target;
		base.offs = null;
		// 基准保持 density=簇总颗数（计分）；采样副本 density=1 且不参与判定
		var lastNote:Note = spawnOne(base);
		// 长条重构：基准箭头（含 holdLength）的尾巴挂在 base 上（最后一个视觉副本不是锚点）
		if (base.holdLength > 0 && base.chartSeq >= 0)
			spawnHoldTail(lastNote, base);

		// 均匀采样：保留首、尾与等距中间点（视觉跨度/密度与原版一致）；
		// maxVis 由 noteSpawn 按"2s 窗口簇数"动态预算（场上精灵总额控制）
		var picks:Array<Float> = offs;
		var maxVis:Int = clusterVisCap; // 动态视觉预算（见 noteSpawn）
		if (maxVis < 1) maxVis = 12;
		if (offs.length > maxVis - 1)
		{
			picks = [];
			var step:Float = (offs.length - 1) / (maxVis - 1);
			for (i in 0...maxVis)
			{
				var idx:Int = Std.int(i * step);
				if (idx >= offs.length) idx = offs.length - 1;
				picks.push(offs[idx]);
			}
		}
		for (i in 0...picks.length)
		{
			var sub:CastNote = new CastNote();
			sub.strumTime = base.strumTime + picks[i];
			sub.noteData = base.noteData;
			sub.chartSeq = base.chartSeq;
			sub.density = 1;
			sub.holdLength = base.holdLength;
			sub.noteType = base.noteType;
			sub.multSpeed = base.multSpeed;
			sub.cmpSpam = null;
			sub.offs = null;
			sub.noAnimation = true;     // 纯视觉：不做角色动画
			sub.noMissAnimation = true;
			sub.blockHit = true;         // 不参与按键判定（防 keysCheck 误命中）
			lastNote = spawnOne(sub);
			lastNote.ignoreNote = true; // 不计分/不 Miss/不触发命中
		}
		return lastNote;
	}

		var dunceNote:Note = notes.spawnNote(target);

		// botplay 命中排期（架构修复）：生成即登记，到时间由 noteSpawn 直接入队，
		// 不依赖 alive-loop 逐帧访问（密集段下 forEachAlive 因击杀移除会饿死入队哨兵）
		if (PlayState.instance != null && PlayState.instance.cpuControlled
			&& dunceNote.mustPress && !dunceNote.ignoreNote && !dunceNote.blockHit
			&& PlayState.instance.botplayPlan == null && ClientPrefs.data.botplayScheduledHits)
		{
			dunceNote.botSched = true; // 排期登记：待弹出期间免回收窗击杀（弹出一旦完成由 botQueued 接管保护）
			botSchedule.push(dunceNote);
		}

		var lane:Int = dunceNote.noteData + (dunceNote.mustPress ? 4 : 0);


		// 重叠隐藏（hideOverlapped > 0）：与同轨上一可见音符间距过近时隐藏（渲染裁剪）
		var hide:Float = ClientPrefs.data.hideOverlapped;
		if (hide > 0)
		{
			var d:Float = 0.45 * (Conductor.songPosition - dunceNote.strumTime) * songSpeed;
			var nowSus:Bool = dunceNote.isSustainNote;
			dunceNote.visible = laneSusPrev[lane] != nowSus || Math.abs(d - laneLDist[lane]) >= hide;
			if (dunceNote.visible)
			{
				laneLDist[lane] = d;
				laneSusPrev[lane] = nowSus;
			}
		}
		else dunceNote.visible = true;

		if (ClientPrefs.data.spawnNoteEvent)
		{
			callOnLuas('onSpawnNote', [currentSpawnId, dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
			callOnHScript('onSpawnNote', [dunceNote]);
		}
		return dunceNote;
	}

	/** 挤压音符运行时展开：连续同轨音符按 (15000/BPM)/density 间隔批量生成 */
	function spamSpawn():Void
	{
		if (spamNotes.length < 1) return;
		var fixedPosition:Float = Conductor.songPosition - ClientPrefs.data.noteOffset;
		var spawnBPM:Float = SONG != null ? SONG.bpm : 100;

		for (spam in spamNotes)
		{
			var noteInterval:Float = (15000 / spawnBPM) / spam.density;
			var guard:Int = 0;
			var isDisplay:Bool = true;

			// 先跳到当前时间（起点已过则整段快进，不逐颗生成）
			while (isDisplay && spam.remaining > 0 && guard < 8192)
			{
				guard++;
				if (spam.seedNote.strumTime < fixedPosition - noteInterval)
				{
					// 完全在出生窗口之前：按整批跳进，不生成
					var bulk:Int = Math.floor((fixedPosition - spawnWindowFor(spam.seedNote) - spam.seedNote.strumTime) / noteInterval);
					if (bulk > 0)
					{
						if (bulk > spam.remaining) bulk = Std.int(spam.remaining);
						spam.seedNote.strumTime += bulk * noteInterval;
						spam.remaining -= bulk;
						if (spam.remaining <= 0) { break; }
					}
				}
				if (spam.seedNote.strumTime - fixedPosition > spawnWindowFor(spam.seedNote)) { isDisplay = false; break; }
				spawnOne(spam.seedNote);
				if (ClientPrefs.data.limitNotes > 0 && notes.countLiving() >= ClientPrefs.data.limitNotes) break;
				spam.remaining--;
				spam.seedNote.strumTime += noteInterval;
			}
			if (spam.remaining <= 0) spamNotes.remove(spam);
		}
	}

	override public function update(elapsed:Float)
	{
		/*if (FlxG.keys.justPressed.NINE)
		{
			iconP1.swapOldIcon();
		}*/

		// 拆卸锁：endSong 结算拆卸后（转场/关闭回调窗口期）不再驱动本 State，
		// 否则会访问已销毁的人物/判定线（Null Object Reference）
		if (_visualsTorn)
			return;

		callOnScripts('onUpdate', [elapsed]);

		// 原生长条按压覆盖：每帧同步判定线位置
		if (holdCoverHandler != null)
			holdCoverHandler.syncPositions(playerStrums, opponentStrums);

		// 角色自愈：mod 脚本 / createInstance / 事件竞态可能把 dad/boyfriend/gf 置空
		// （blissful-erect 接箭头闪退现场）——按谱面默认配置逐个重建缺失角色，绝不闪退
		ensureCharactersAlive();

		// 延迟 GC（一次）：进曲 0.5s 后回收已剥离的谱面 DOM/解析暂存（倒计时期间，无音符生成）
		if (_deferredGC)
		{
			_deferredGCTime += elapsed;
			if (_deferredGCTime >= 0.5)
			{
				_deferredGC = false;
				#if desktop
				openfl.system.System.gc();
				#end
			}
		}

		// NPS 滚动窗口：每满 1 秒把计数滚到显示值并清零，同时刷新 Score 栏
		_npsTimer += elapsed;
		if (_npsTimer >= 1)
		{
			npsDisplay = _npsCount;
			_npsCount = 0;
			_npsTimer -= 1;
			if (ClientPrefs.data.showNPS && !endingSong && scoreTxt != null) updateScore();
		}

		// ===== HUD 权威校验（每帧） =====
		// 1) hideHud 被 Mod/脚本临时改掉 → 立即恢复用户真实设置；
		// 2) healthBar/图标/分数等 visible 被任何代码（Lua/Hscript/遗留逻辑）直接改掉
		//    → 每帧强制拉回设置值。从根上杜绝“游玩中 UI 突然消失”。
		// 注意：此函数只在非暂停/非结算（persistentUpdate=true）时执行，
		// 不会干扰暂停界面、结算界面自身的显隐逻辑。
		enforceHUD();

		// 自愈：paused 卡死但没有打开任何子界面（如 PauseSubState 构造中途异常、
		// Lua 拦截 onPause 后遗留）时解锁，避免“暂停界面显示不出来”却把游戏冻结住。
		if (paused && subState == null && !isDead && !chartingMode)
		{
			_pausedSelfHealFrames++;
			if (_pausedSelfHealFrames >= 3)
			{
				_pausedSelfHealFrames = 0;
				paused = false;
			}
		}
		else _pausedSelfHealFrames = 0;

		FlxG.camera.followLerp = 0;
		if(!inCutscene && !paused) {
			FlxG.camera.followLerp = FlxMath.bound(elapsed * 2.4 * cameraSpeed * playbackRate / (FlxG.updateFramerate / 60), 0, 1);
			// 防御：mod 脚本/事件/竞态可能把 boyfriend 置空（blissful-erect 接箭头闪退现场），
			// 待机块永不因角色缺失而崩
			if(!startingSong && !endingSong && boyfriend != null && boyfriend.getAnimationName().startsWith('idle')) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}

		var healthLerp:Float = FlxMath.lerp(smoothHealth, health, FlxMath.bound(elapsed * 9 * playbackRate, 0, 1));
		smoothHealth = healthLerp;

		super.update(elapsed);

		// 快速重开回溯：时间倒流（箭头随 songPosition 回退而飞回）
		if (rewinding)
		{
			rewindElapsed += elapsed;
			if (rewindElapsed >= rewindDuration)
			{
				rewinding = false;
				Conductor.songPosition = 0;
				trace('[Rewind] FINISH, elapsed=' + rewindElapsed);
				finishRestart();
			}
			else
			{
				// 变速回溯：一开始快、越接近终点越慢（cubicOut）；
				// 终点 = 场上清空的位置（最早音符飞出出生窗口后），收尾正好落在最后几个箭头上
				var rewindProgress:Float = rewindElapsed / rewindDuration;
				Conductor.songPosition = FlxMath.lerp(rewindFromPos, rewindEndPos, FlxEase.cubeOut(rewindProgress));

				// 回溯中：箭头退回到“出生窗口”之外后回收，场上只保留正在倒流的箭头
				var rewindWindow:Float = spawnTime * playbackRate;
				if (songSpeed < 1) rewindWindow /= songSpeed;
				var noteIdx:Int = notes.members.length - 1;
				while (noteIdx >= 0)
				{
					var rewindNote:Note = notes.members[noteIdx];
					if (rewindNote != null && rewindNote.alive)
					{
						var noteWindow:Float = rewindWindow;
						if (rewindNote.multSpeed < 1) noteWindow /= rewindNote.multSpeed;
						if (rewindNote.strumTime - Conductor.songPosition > noteWindow)
						{
							rewindNote.active = false;
							rewindNote.visible = false;
							notes.invalidateNote(rewindNote);
						}
					}
					noteIdx--;
				}

				// 场上已没有可见箭头时提前结束回溯，不再空转浪费等待时间
				if (notes.length == 0)
				{
					rewinding = false;
					Conductor.songPosition = 0;
					trace('[Rewind] FINISH (field empty), elapsed=' + rewindElapsed);
					finishRestart();
				}
			}
		}

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		// 每帧刷新动态 PlayState 值（Psych 0.7.3 setSpecialObject 等价物）
		setOnScripts('health', health);
		setOnScripts('endingSong', endingSong);
		setOnScripts('curBeat', curBeat);
		setOnScripts('isCameraOnForcedPos', isCameraOnForcedPos);

		// HUD 每帧更新（图标跳动/跟随/阴影滚动/botplay 呼吸/可见性权威）全部收敛到 GameHUD
		if (hud != null) hud.update(elapsed);

		if ((controls.PAUSE || androidBackQueued) && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != FunkinLua.Function_Stop) {
				openPauseMenu();
			}
		}
		androidBackQueued = false;

		if (controls.justPressed('debug_1') && !endingSong && !inCutscene)
			openChartEditor();

		if (controls.justPressed('debug_2') && !endingSong && !inCutscene)
			openCharacterEditor();
		
		if (startedCountdown && !paused && !rewinding)
			Conductor.songPosition += FlxG.elapsed * 1000 * playbackRate;

		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= 0)
			{
		
				startSong();
			}
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(ClientPrefs.data.timeBarType == '已过时间') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			if(ClientPrefs.data.timeBarType != '歌曲名称')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
		}

		if (camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, FlxMath.bound(1 - (elapsed * 3.125 * camZoomingDecay * playbackRate), 0, 1));
			camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, FlxMath.bound(1 - (elapsed * 3.125 * camZoomingDecay * playbackRate), 0, 1));
		}

		// Watch calls removed for performance

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
		{
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		noteSpawn();

		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!rewinding && !cpuControlled && !replayMode) {
					keysCheck();
				} else {
					// 回放 v2：按录制时间注入按键（走正常判定路径），并处理长按子段
					if (replayMode && replayV2) updateReplayInputs();
					if (boyfriend != null && boyfriend.getAnimationName().startsWith('sing') && !boyfriend.getAnimationName().endsWith('miss') && boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 / FlxG.sound.music.pitch) * boyfriend.singDuration) {
						boyfriend.dance();
						//boyfriend.animation.curAnim.finish();
					}
				}

				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						var songPos:Float = Conductor.songPosition;
						// 自动游玩命中提前量：实测本帧音频前进量的一半（帧轮询下偏差最小），
						// 上限 20ms×倍速，防止卡顿帧后提前量过大导致提前命中掉出 Sick 窗口（45ms）
						var songDelta:Float = songPos - lastBotSongPos;
						lastBotSongPos = songPos;
						var botAdvance:Float = Math.min(Math.max(songDelta, 1000 / FlxG.drawFramerate) * 0.5, 20 * playbackRate);
						notes.forEachAlive(function(daNote:Note)
						{
							var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
							if(!daNote.mustPress) strumGroup = opponentStrums;

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							if (strum == null)
							{
								// 防御 + 现场诊断：strum 缺失时跳过本音符（不整局崩溃），并打印现场
								trace('[STRUM NULL] seq=' + daNote.chartSeq + ' d=' + daNote.noteData
									+ ' must=' + daNote.mustPress + ' pLen=' + playerStrums.length
									+ ' oLen=' + opponentStrums.length + ' pos=' + Std.int(Conductor.songPosition)
									+ ' step=' + curStep + ' gen=' + generatedMusic + ' keepping=' + keepStrumsOnRestart);
								return;
							}
							daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

							// 视觉副本（blockHit+ignoreNote）快捷路径：只跟随/长条裁剪/超时消亡，不做判定（大优化）
							if (daNote.blockHit && daNote.ignoreNote)
							{
								// 长条副本同样需要判定键裁剪（否则滑过判定线后仍延伸不消失）
								if (daNote.isSustainNote && strum != null && strum.sustainReduce)
								{
									daNote.wasGoodHit = true; // 副本纯视觉：满足裁剪条件
									daNote.clipToStrumNote(strum);
								}
								if (!rewinding && songPos - daNote.strumTime > (cpuControlled ? ClientPrefs.data.botplayKillWindow : noteKillOffset))
									notes.invalidateNote(daNote);
								return;
							}

							if(daNote.mustPress)
							{
								if(!rewinding && (cpuControlled || replayMode) && !daNote.blockHit && !daNote.wasGoodHit
									&& (replayMode || !daNote.botQueued)) // 自动游玩命中：排期与 alive-loop 双路互斥（botQueued 防重）
								{
									var shouldHit:Bool = false;
									if (replayMode && !replayV2)
									{
										// 旧版回放（v1，无按键流）：按录制命中记录合成命中，
										// 未记录的箭头自然滑过并触发 miss，与原局表现一致。
										// 注意：v2（含按键流）不走这里——自动命中会在 strumTime 一到就抢先把
										// 音符打掉，之后注入的真实按键（晚按）找不到可命中音符会变成 ghost miss，
										// 导致回放 Miss 数膨胀（2 → 10）。v2 完全靠 updateReplayInputs 按键注入，
										// 同时间同按键必然命中同一音符，与实玩 1:1 复刻。
										if (replayHitSeqs != null && daNote.chartSeq >= 0 && replayHitSeqs.exists(daNote.chartSeq)
											&& !daNote.tooLate && songPos + botAdvance >= daNote.strumTime)
											shouldHit = true;
									}
									else if (!replayMode && ((botplayPlan != null && !daNote.tooLate && songPos + botAdvance >= daNote.strumTime)
										|| (botplayPlan == null && daNote.canBeHit && (daNote.isSustainNote || songPos + botAdvance >= daNote.strumTime))))
										shouldHit = true;

									if (shouldHit)
									{
										// 本帧命中的音符先收集，forEachAlive 结束后统一批处理
										// （堆叠命中时合并音效/粒子/动画/评分等副作用，避免单帧爆发卡顿）
										daNote.botQueued = true; // 免杀保护：本帧不再被超时击杀
										daNote.botSched = false;
										botHitQueue.push(daNote);
									}
								}
							}
							// 对手箭头：到达判定线即触发命中（旧条件是 wasGoodHit——对手音符从未被置位，
							// 导致对手箭头永远不会被 opponentNoteHit 回收，直接飞过判定线）
							else if (!rewinding && !daNote.hitByOpponent && !daNote.ignoreNote
								&& !daNote.isSustainNote && songPos - daNote.strumTime >= 0)
							{
								opponentNoteHit(daNote);
								// 对手簇视觉副本同步销毁（与玩家侧 processBotHits 一致）：
								// 副本只靠回收窗击杀会飞过判定线，巨堆叠段肉眼即"整簇飞走"
								if (daNote.chartSeq >= 0)
								{
									var omi:Int = notes.members.length - 1;
									while (omi >= 0)
									{
										var osib:Note = notes.members[omi];
										if (osib != null && osib != daNote && osib.blockHit && osib.ignoreNote && osib.chartSeq == daNote.chartSeq)
											notes.invalidateNote(osib);
										omi--;
									}
								}
							}

							if(daNote.isSustainNote && strum != null && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							// （已入自动命中队列的音符本帧免杀：逾期 1 帧由 processBotHits 记账，杜绝"入队后被击杀丢弃"）
							// 自动游玩：未命中者极小窗口即回收（柱子顶端贴判定线裁齐，不残留 +52ms 残影）
							if (!rewinding && !daNote.botQueued && !(cpuControlled && daNote.botSched) && songPos - daNote.strumTime > (cpuControlled ? ClientPrefs.data.botplayKillWindow : noteKillOffset))
							{
								if (daNote.mustPress && !cpuControlled &&!daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit)
								&& (ClientPrefs.data.noteJudgment != 'KE 判定' || !daNote.isSustainNote))
									noteMiss(daNote);

								daNote.active = false;
								daNote.visible = false;

								notes.invalidateNote(daNote);
							}
						});
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
					processBotHits();
				}

				// 回放（旧版）：按录制时间触发空按（无对应音符的按键），与原局按键时机一致。
				// 回放 v2 的空按由按键注入自然复现，这里跳过避免重复 Miss。
				if (replayMode && !replayV2 && !rewinding && !paused && !endingSong && startedCountdown)
				{
					while (replayPressPtr < replayPressMisses.length && Conductor.songPosition >= replayPressMisses[replayPressPtr].t)
					{
						var pm:ReplayEvent = replayPressMisses[replayPressPtr++];
						noteMissPress(pm.d);
					}
				}
			}
			checkEventNote();
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		setOnScripts('cameraX', camFollow.x);
		setOnScripts('cameraY', camFollow.y);
		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);
	}

	#if mobile
	/** 游玩中按返回键 / 左上角 X：暂停游戏而不是退出（菜单里仍是退出到桌面） */
	override public function onAndroidBack():Bool
	{
		androidBackQueued = true;
		return true;
	}
	#end

	function openPauseMenu()
	{
		// 防重入：后台/失焦/按键可能在同一帧多次触发，避免打开多个暂停界面
		if (paused) return;

		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;
		// 侧边栏（stage 级 TextField）不随 flixel 暂停，需手动隐藏，恢复后 updateJudgementTxt 自动显示
		if (hud != null && hud.judgementField != null) hud.judgementField.visible = false;

		// 1 / 1000 chance for Gitaroo Man easter egg
		/*if (FlxG.random.bool(0.1))
		{
			// gitaroo man easter egg
			cancelMusicFadeTween();
			MusicBeatState.switchState(new GitarooPause());
		}
		else {*/
		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		#if mobile
		// 暂停时隐藏游戏触控板，避免暂停界面还显示游戏方向键
		if (objects.MobileControls.instance != null)
		{
			objects.MobileControls.instance.visible = false;
		}
		#end
		// 防“暂停键判定两次”：此时 flixel 输入还未被 onStateSwitch 重置，
		// 捕获打开暂停的按键是否仍按住 → 传给暂停菜单锁定确认，直到该键物理松开
		var pauseKeyHeld:Bool = FlxG.keys.anyPressed(PauseSubState.getPauseKeys());
		openSubState(new PauseSubState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y, pauseKeyHeld));
		//}

		#if desktop
		DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function openChartEditor()
	{
		// 编谱需要完整谱面：若游玩期已剥离 SONG.notes，先从缓存恢复
		reloadChartSourceIfNeeded();
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		chartingMode = true;

		#if desktop
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end
		
		MusicBeatState.switchState(new ChartingState());
	}

	function openCharacterEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		#if desktop DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != FunkinLua.Function_Stop) {
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;

				vocals.stop();
				opponentVocals.stop();
				FlxG.sound.music.stop();

				persistentUpdate = false;
				persistentDraw = false;
				#if LUA_ALLOWED
				for (tween in modchartTweens) {
					tween.active = true;
				}
				for (timer in modchartTimers) {
					timer.active = true;
				}
				#end

				// Psych 1.0.4：deathDelay > 0 时延迟打开 Game Over（Weekend 1 Blazin 用 0.15s）
				if (GameOverSubstate.deathDelay > 0)
				{
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
					{
						openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x - boyfriend.positionArray[0], boyfriend.getScreenPosition().y - boyfriend.positionArray[1], camFollow.x, camFollow.y));
						gameOverTimer = null;
					});
				}
				else
					openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x - boyfriend.positionArray[0], boyfriend.getScreenPosition().y - boyfriend.positionArray[1], camFollow.x, camFollow.y));

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if desktop
				// Game Over doesn't get his own variable because it's only used here
				DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() {
		if (rewinding) return; // 回溯中不触发谱面事件
		while(eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if(eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(boyfriend != null && boyfriend.curCharacter != value2) {
							if(!boyfriendMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = boyfriend.alpha;
							boyfriend.alpha = 0.00001;
							// 防御：角色添加失败（图集缺失等）时保持现角色，绝不把 boyfriend 置 null
							var newB:Character = boyfriendMap.get(value2);
							if (newB == null) newB = boyfriend;
							boyfriend = newB;
							boyfriend.alpha = lastAlpha;
							iconP1.changeIcon(boyfriend.healthIcon);
						}
						if (boyfriend != null) setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						if(dad != null && dad.curCharacter != value2) {
							if(!dadMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
							var lastAlpha:Float = dad.alpha;
							dad.alpha = 0.00001;
							var newD:Character = dadMap.get(value2);
							if (newD == null) newD = dad; // 防御同上
							dad = newD;
							if(!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf') {
								if(wasGf && gf != null) {
									gf.visible = true;
								}
							} else if(gf != null) {
								gf.visible = false;
							}
							dad.alpha = lastAlpha;
							iconP2.changeIcon(dad.healthIcon);
						}
						if (dad != null) setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								var newG:Character = gfMap.get(value2);
								if (newG == null) newG = gf; // 防御同上
								gf = newG;
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}
				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(this, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
				}
			
			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}
		
		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	public function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			tweenCamIn();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		callOnScripts('onMoveCamera', [isDad ? 'dad' : 'boyfriend']);
	}

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		FlxG.sound.music.volume = 0;
		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();
		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	var _pausedSelfHealFrames:Int = 0; // 暂停自愈延迟帧(防误判正常关闭,见update注释)
	public function endSong()
	{

		//Should kill you if you tried to cheat
		if(!startingSong) {
			notes.forEach(function(daNote:Note) {
				// 只扣未命中的玩家音符（命中者不扣——自动游玩打完不再死）
				if(daNote.mustPress && !daNote.wasGoodHit && !daNote.ignoreNote
					&& daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			});
			// unspawnNotes 为游标数组（后台压缩后整场保留），只统计"尚未生成"的音符，
			// 否则曲末会把整张谱面（数万条）全部扣血——曲目完毕立马死亡
			for (i in currentSpawnId...unspawnNotes.length) {
				if(unspawnNotes[i].strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		clampGameplayTotals();
		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		// 曲终释放（Meteoric Fix 续）：最后音符已全部生成，unspawnNotes + CastNote 平行数组
		// 成为死重（约 250MB）。结算界面不再需要它们；重开/回溯/换难度/编谱/回放全部经
		// reloadChartSourceIfNeeded（快扫重解析）恢复，回放指纹已有 create 期存档。
		// 无条件释放（不设 currentSpawnId 守卫）：谱面尾部可能比音频长（最后音符未生成完
		// 也照样进结算），守卫会让释放静默失效；重开路径本就会重解析，无一致性风险。
		unspawnNotes = [];
		spamNotes = [];
		CastNote.resetPacked();
		// seqNote/seqHit 链快照（~20MB 引用）一并释放：曲终无判定，重开/回溯重建
		Note.seqNote = [];
		Note.seqHit = [];
		CrashHandler.mark('PlayState.endSong');

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		if(achievementObj != null)
			return false;
		else if(!replayMode)
		{
			var noMissWeek:String = WeekData.getWeekFileName() + '_nomiss';
			var achieve:String = checkForAchievement([noMissWeek, 'r_ubad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger']);
			if(achieve != null) {
				startAchievement(achieve);
				return false;
			}
		}
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != FunkinLua.Function_Stop && !transitioning)
		{
			playbackRate = 1;

			// 本局完成：保存回放文件（自动游玩/回放/编谱不录制）
			var replayForResults:Replay = null;
			if (recordingReplay && currentReplay != null && !usedAutoplay)
			{
				// 游玩期 SONG.notes 已被剥离，指纹用 create 期记录值（内容与完整谱面一致）
				currentReplay.fingerprint = recordedChartFingerprint;
				currentReplay.score = songScore;
				currentReplay.misses = songMisses;
				currentReplay.percent = Math.isNaN(ratingPercent) ? 0 : ratingPercent;
				currentReplay.save();
				replayForResults = currentReplay;
				recordingReplay = false;
			}

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			// 无限轮回：曲目完成后不进入结算，时间回溯后重新开始（不保存分数）
			if (ClientPrefs.getGameplaySetting('infiniteloop', false))
			{
				restartSongWithoutReload(true);
				return false;
			}

			#if !switch
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			if(!usedAutoplay)
				Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent);
			#end

			// ===== 结算前释放游玩视觉（Meteoric Fix 续：结算时只留场景，人物/判定线/音符移除）=====
			// 原生贴图（人物/判定线/音符）在此真正归还 OS；结算背景保持原版黑底。
			// 重试/回放会重建（finishRestart → generateStaticArrows + reloadDefaultCharacters
			// + generateChartNotes；resetState → 全新 create）。
			#if desktop
			// 1. 音符/seq 链（unspawnNotes 已在 endSong 前段释放，这里清理存活音符与池）
			KillNotes();
			// 2. 判定线（与 finishRestart 同一套拆法）
			while (strumLineNotes.length > 0)
			{
				var strum:StrumNote = strumLineNotes.members[0];
				strumLineNotes.remove(strum, true);
				strum.destroy();
			}
			playerStrums.clear();
			opponentStrums.clear();
			// 3. 人物（BF/Dad/GF 大贴图）
			destroyAllCharacters();
			// 4. 清空本局贴图租约并释放 useCount=0 的贴图（人物/判定线/音符等）
			Paths.localTrackedAssets = [];
			Paths.clearUnusedMemory(false);
			// 5. 上锁：本 State 更新立即暂停（结算转场/关闭回调的窗口期仍会被驱动）
			_visualsTorn = true;
			#end

			persistentUpdate = false;
			// 结算时隐藏 HUD 判定侧边栏（stage 级 TextField 不随 flixel 状态隐没；
			// 此处 _visualsTorn 已上锁，updateJudgementTxt 不再运行——必须在此一次隐藏，
			// 结算关闭后 updateJudgementTxt 恢复运行会自动按设置重新显示）
			if (hud != null && hud.judgementField != null) hud.judgementField.visible = false;
			var resultsSubState:ResultsSubState = new ResultsSubState(replayForResults != null);
			resultsSubState.closeCallback = function() {
				persistentUpdate = true;
				if (resultsSubState.resultAction == 'retry')
				{
					if (ClientPrefs.data.restartNoChartReload)
						restartSongWithoutReload();
					else
					{
						FlxTransitionableState.skipNextTransIn = true;
						FlxTransitionableState.skipNextTransOut = true;
						MusicBeatState.resetState();
					}
				}
				else if (resultsSubState.resultAction == 'replay')
				{
					if (replayForResults != null)
					{
						// 回放本局：原地重开并进入回放模式
						// 防止 Mod 脚本遗留 hideHud=true 导致回放时 HUD 消失
						ClientPrefs.resetHideHud();
						PlayState.queuedReplay = replayForResults;
						FlxTransitionableState.skipNextTransIn = true;
						FlxTransitionableState.skipNextTransOut = true;
						MusicBeatState.resetState();
						return;
					}
					proceedAfterEndSong();
				}
				else
				{
					proceedAfterEndSong();
				}
			};
			openSubState(resultsSubState);
			return false;
		}
		return true;
	}

	function proceedAfterEndSong():Void
	{
		if (transitioning) return;
		transitioning = true;

		if (isStoryMode)
		{
			campaignScore += songScore;
			campaignMisses += songMisses;

			storyPlaylist.remove(storyPlaylist[0]);

			if (storyPlaylist.length <= 0)
			{
				Mods.loadTopMod();
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				#if desktop DiscordClient.resetClientID(); #end

				cancelMusicFadeTween();
				if(FlxTransitionableState.skipNextTransIn) {
					CustomFadeTransition.nextCamera = null;
				}
				MusicBeatState.switchState(new StoryMenuState());

				// if ()
				if(!usedAutoplay) {
					StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
					Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

					FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
					FlxG.save.flush();
				}
				changedDifficulty = false;
			}
			else
			{
				var difficulty:String = Difficulty.getFilePath();
				var nextSong:String = Paths.formatToSongPath(PlayState.storyPlaylist[0]);

				trace('LOADING NEXT SONG');
				trace(nextSong + difficulty);

				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
				prevCamFollow = camFollow;

				if (!LoadingState.loadSongAndSwitchState(new PlayState(), nextSong, nextSong + difficulty, nextSong, true, new StoryMenuState()))
				{
					Mods.loadTopMod();
					MusicBeatState.switchState(new StoryMenuState());
					return;
				}

				FlxG.sound.music.stop();

				cancelMusicFadeTween();
			}
		}
		else
		{
			trace('WENT BACK TO FREEPLAY??');
			Mods.loadTopMod();
			#if desktop DiscordClient.resetClientID(); #end

			cancelMusicFadeTween();
			if(FlxTransitionableState.skipNextTransIn) {
				CustomFadeTransition.nextCamera = null;
			}
			MusicBeatState.switchState(new FreeplayState());
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			changedDifficulty = false;
		}
	}
	#if ACHIEVEMENTS_ALLOWED
	var achievementObj:AchievementPopup = null;
	function startAchievement(achieve:String) {
		achievementObj = new AchievementPopup(achieve, camOther);
		achievementObj.onFinish = achievementEnd;
		add(achievementObj);
		trace('Giving achievement ' + achieve);
	}
	function achievementEnd():Void
	{
		achievementObj = null;
		if(endingSong && !inCutscene) {
			endSong();
		}
	}
	#end

	public function KillNotes() {
		botHitQueue.resize(0); // 丢弃待批处理的命中，避免引用已销毁音符
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			notes.invalidateNote(daNote); // 池化回收（替代直接 destroy）
		}
		unspawnNotes = [];
		currentSpawnId = 0;
		spamNotes = [];
		Note.seqNote = [];
		Note.seqHit = [];
		eventNotes = [];
	}

	// 快速重开：不重新加载谱面、不重建整个状态，直接在当前状态上重置并从头开始本曲
	public function restartSongWithoutReload(?forceRewind:Bool = false):Void
	{
		if (rewinding) return; // 回溯中禁止重复重开

		// 取消进行中的计时器与补间
		if (startTimer != null) { startTimer.cancel(); startTimer = null; }
		if (finishTimer != null) { finishTimer.cancel(); finishTimer = null; }
		if (songSpeedTween != null) { songSpeedTween.cancel(); songSpeedTween = null; }
		if (cameraTwn != null) { cameraTwn.cancel(); cameraTwn = null; }

		// 清掉残留的倒计时贴图
		if (countdownReady != null) { remove(countdownReady); countdownReady.destroy(); countdownReady = null; }
		if (countdownSet != null) { remove(countdownSet); countdownSet.destroy(); countdownSet = null; }
		if (countdownGo != null) { remove(countdownGo); countdownGo.destroy(); countdownGo = null; }

		// 停止音频（音符/谱面数据保留在内存中）
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		if (vocals != null) vocals.stop();
		if (opponentVocals != null) opponentVocals.stop();

		// 重置本局数据
		ClientPrefs.resetHideHud();
		health = 1;
		smoothHealth = 1;
		songScore = 0;
		songHits = 0;
		songMisses = 0;
		judgementHistory = []; // KE 散点图：重开清空本局判定记录
		totalPlayed = 0;
		totalNotesHit = 0;
		combo = 0;
		maxCombo = 0; // 结算界面：最高连击随重开清零
		songPercent = 0;
		usedAutoplay = cpuControlled || replayMode;
		usedGodMode = false; // 上帝模式正常记分
		for (rating in ratingsData) rating.hits = 0;
		ratingName = '?';
		ratingPercent = 0;
		ratingFC = '';
		keysPressed = [];
		strumsBlocked = [];
		boyfriendIdleTime = 0;
		boyfriendIdled = false;

		// 重开：录制从头开始（回放数据保持，按键/空按游标与按住状态复位）
		replayPressPtr = 0;
		replayInputPtr = 0;
		replayHeld = [false, false, false, false];
		replayInjecting = false;
		if (recordingReplay && !replayMode)
			currentReplay = new Replay(SONG.song, Difficulty.getString(storyDifficulty));

		// 快速重开回溯：屏幕上的箭头像时间倒流一样飞回起点，再重新开始。
		// 回放模式跳过回溯视觉（回放数据按时间轴注入，回溯会打乱游标），直接干净重开。
		if (!replayMode && (ClientPrefs.data.rewindOnRestart || forceRewind) && Conductor.songPosition > rewindMinPosition)
		{
			trace('[Rewind] START from ' + Conductor.songPosition + 'ms, pref=' + ClientPrefs.data.rewindOnRestart);
			rewinding = true;
			rewindFromPos = Conductor.songPosition;
			rewindElapsed = 0;
			canPause = false;
			canReset = false;
			keepStrumsOnRestart = true; // 判定线全程在场，回溯结束后不重新绘制

			// 回溯视觉：把整张谱面的箭头全部重新生成并“复活”，
			// 随着 songPosition 倒流，这些箭头（包括已经打过的）会像录像倒带一样飞回去
			KillNotes();
			generateChartNotes(false);
			currentSpawnId = 0;
			while (currentSpawnId < unspawnNotes.length)
			{
				// 安卓：unspawnNotes 是已构造好的 Note 实体，必须与 noteSpawn 一致直接入组；
				// 不能走 spawnOneWithTail → notes.spawnNote(target:CastNote)（hxcpp 会把
				// Dynamic 转类形参置 null，导致 recycleNote 读 target.offsetAngle 时空指针 NRE）
				#if android
				var rewindNote:Note = unspawnNotes[currentSpawnId++];
				notes.insert(0, rewindNote);
				rewindNote.spawned = true;
				callOnLuas('onSpawnNote', [notes.members.indexOf(rewindNote), rewindNote.noteData, rewindNote.noteType, rewindNote.isSustainNote, rewindNote.strumTime]);
				callOnHScript('onSpawnNote', [rewindNote]);
				#else
				var rewindNote:Note = spawnOneWithTail(unspawnNotes[currentSpawnId++]);
				#end
				rewindNote.visible = true;
				rewindNote.active = true;
				rewindNote.canBeHit = false;
				rewindNote.wasGoodHit = false;
				rewindNote.tooLate = false;
				rewindNote.ignoreNote = false;
				rewindNote.alpha = 1;
			}
			#if android
			unspawnNotes = []; // 安卓 noteSpawn 按 [0]+splice 消费，回溯期腾空防止回溯帧重复插入
			#end

			// 回溯终点：最早音符飞出“出生窗口”的位置（保证场上清空），不低于 -rewindOvershoot
			rewindEndPos = -rewindOvershoot;
			var earliestStrum:Float = 99999999;
			for (rewindNote in notes.members)
				if (rewindNote != null && rewindNote.strumTime < earliestStrum)
					earliestStrum = rewindNote.strumTime;
			if (earliestStrum < 99999999)
			{
				var endWindow:Float = spawnTime * playbackRate;
				if (songSpeed < 1) endWindow /= songSpeed;
				rewindEndPos = earliestStrum - endWindow - 50;
				if (rewindEndPos < -rewindOvershoot) rewindEndPos = -rewindOvershoot;
			}
			// 回溯时长按距离自动计算：距离越远回溯越久
			rewindDuration = FlxMath.bound((rewindFromPos - rewindEndPos) / rewindSpeedMs, rewindMinDuration, rewindMaxDuration);
			// 若结算拆卸过（_visualsTorn）：回溯前必须重建判定线与人物，
			// 否则驱动倒流的第一帧就撞到 null（boyfriend.animation → NRE，4# 结算重试崩溃现场）。
			// 正常回溯（无限轮回/游戏中回退，未拆卸）保持原路径不动。
			if (_visualsTorn)
			{
				generateStaticArrows(0);
				generateStaticArrows(1);
				keepStrumsOnRestart = false; // 判定线已重建：后续 finishRestart/startCountdown 走常规重建
				reloadDefaultCharacters();
				_visualsTorn = false;
			}
			return; // update() 中的回溯逻辑会驱动倒流，结束后调用 finishRestart()
		}
		trace('[Rewind] SKIP (pref=' + ClientPrefs.data.rewindOnRestart + ', pos=' + Conductor.songPosition + ')');
		finishRestart();
	}

	private function finishRestart():Void
	{
		// 清空旧的音符、事件与判定条
		KillNotes();
		if (keepStrumsOnRestart)
		{
			// 回溯重开：判定线箭头全程在场，直接复位为静态，不重新绘制
			for (strum in strumLineNotes.members)
				if (strum != null) strum.playAnim('static', true);
		}
		else
		{
			while (strumLineNotes.length > 0)
			{
				var strum:StrumNote = strumLineNotes.members[0];
				strumLineNotes.remove(strum, true);
				strum.destroy();
			}
			playerStrums.clear();
			opponentStrums.clear();
		}

		// 重置流程标志
		startingSong = true;
		startedCountdown = false;
		endingSong = false;
		canPause = true;
		canReset = true;
		inCutscene = false;
		skipCountdown = false;
		skipArrowStartTween = false;
		generatedMusic = false;
		updateTime = (ClientPrefs.data.timeBarType != '禁用');
		startOnTime = 0;
		Conductor.songPosition = 0;
		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		// 回溯/重开完成后，时间条与时间文字立即归零，避免残留回溯结束瞬间的旧进度
		if (hud != null) hud.resetForRestart();

		// 重置拍点/步点缓存，避免重开后 beatHit 被旧值跳过（角色因此不动）
		lastStepHit = -1;
		lastBeatHit = -1;
		resetBPMChangeCache();

		// 根据内存中的谱面重新生成音符（不重新读盘）
		generateChartNotes(false);

		// 重开收尾：generateChartNotes 已恢复并消费完整 DOM，这里再次剥离 + 淘汰缓存副本，
		// 否则快速重开/回退重开后 SONG 与 chartCache 会重新常驻两份大谱面 DOM
		releaseSongChartDom();

		// 重开同样消费过一块新解析的 DOM：延迟 GC 再触发一次回收
		_deferredGC = true;
		_deferredGCTime = 0;

		// 重新加载谱面默认角色（参照不开启快速重开时的完整重开逻辑）
		reloadDefaultCharacters();

		// Meteoric：快速重开时重置舞台侧状态（bgGirls 表情等，防止事件重放颠倒）
		stagesFunc(function(stage:BaseStage) stage.resetForRestart());

		// 角色回到待机
		if (boyfriend != null) { boyfriend.specialAnim = false; boyfriend.stunned = false; boyfriend.holdTimer = 0; boyfriend.dance(); }
		if (dad != null) { dad.specialAnim = false; dad.stunned = false; dad.holdTimer = 0; dad.dance(); }
		if (gf != null) { gf.specialAnim = false; gf.stunned = false; gf.holdTimer = 0; gf.dance(); }

		// 相机复位
		camZooming = false;
		FlxG.camera.zoom = defaultCamZoom;
		camHUD.zoom = 1;
		moveCameraSection(0);

		RecalculateRating();
		#if desktop
		resetRPC();
		#end

		Lib.application.window.title = "FNF':Meteoric Engine - Playing: " + curSong;
		// 重建完成（音符/判定线/人物全部就绪），解锁 update
		_visualsTorn = false;
		// 从全屏设置页（自定义界面/调整延迟与Combo）返回：重载后的曲目先挂起在暂停菜单，
		// 玩家"返回游戏"后才开始倒计时（避免暂停期间倒计时/音乐在后台继续跑）
		if (autoOpenPause)
		{
			autoOpenPause = false;
			var autoPause:PauseSubState = new PauseSubState(0, 0);
			autoPause.closeCallback = function() {
				if (PlayState.instance != null && !PlayState.instance.startedCountdown)
					PlayState.instance.startCountdown();
			};
			paused = true;
			openSubState(autoPause);
		}
		else
			startCountdown();
	}

	// 角色自愈：mod 脚本 / createInstance / 事件竞态可能把 dad/boyfriend/gf 置空
	// （blissful-erect 接箭头闪退现场——update 若干处直接访问 boyfriend.animation）。
	// 每帧按谱面默认配置重建缺失角色（map 优先，缓存缺失才 new），绝不因角色缺失闪退。
	function ensureCharactersAlive():Void
	{
		#if desktop
		if (SONG == null) return;
		if (boyfriend == null)
		{
			var cName:String = (SONG.player1 != null && SONG.player1.length > 0) ? SONG.player1 : 'bf';
			try
			{
				boyfriend = boyfriendMap.get(cName);
				if (boyfriend == null)
				{
					boyfriend = new Character(0, 0, cName, true);
					boyfriendMap.set(cName, boyfriend);
				}
				if (!boyfriendGroup.members.contains(boyfriend))
				{
					startCharacterPos(boyfriend);
					boyfriendGroup.add(boyfriend);
					startCharacterScripts(boyfriend.curCharacter);
				}
			}
			catch (e:Dynamic) { trace('[角色自愈] boyfriend 重建失败：' + e); }
		}
		if (dad == null)
		{
			var cName:String = (SONG.player2 != null && SONG.player2.length > 0) ? SONG.player2 : 'dad';
			try
			{
				dad = dadMap.get(cName);
				if (dad == null)
				{
					dad = new Character(0, 0, cName);
					dadMap.set(cName, dad);
				}
				if (!dadGroup.members.contains(dad))
				{
					startCharacterPos(dad, true);
					dadGroup.add(dad);
					startCharacterScripts(dad.curCharacter);
				}
			}
			catch (e:Dynamic) { trace('[角色自愈] dad 重建失败：' + e); }
		}
		if (gf == null)
		{
			var cName:String = (SONG.gfVersion != null && SONG.gfVersion.length > 0) ? SONG.gfVersion : 'gf';
			try
			{
				gf = gfMap.get(cName);
				if (gf == null)
				{
					gf = new Character(0, 0, cName);
					gfMap.set(cName, gf);
				}
				if (!gfGroup.members.contains(gf))
				{
					startCharacterPos(gf);
					gf.scrollFactor.set(0.95, 0.95);
					gfGroup.add(gf);
					startCharacterScripts(gf.curCharacter);
				}
			}
			catch (e:Dynamic) { trace('[角色自愈] gf 重建失败：' + e); }
		}
		#end
	}

	// 快速重开：参照完整重开（resetState → create）重新加载默认角色
	private function reloadDefaultCharacters():Void
	{
		// 销毁旧角色实例并清空缓存（角色脚本通过 PlayState 动态访问角色，不受影响）
		destroyAllCharacters();

		// 重新创建默认角色（与 create() 逻辑一致：全新对象、正确位置与状态）
		var stageData:StageFile = StageData.getStageFile(curStage);
		if (stageData == null) stageData = StageData.dummy();
		if (!stageData.hide_girlfriend)
		{
			if (SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf';
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
			gfMap.set(SONG.gfVersion, gf);
			startCharacterScripts(gf.curCharacter);
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);
		dadMap.set(SONG.player2, dad);
		startCharacterScripts(dad.curCharacter);

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		boyfriendMap.set(SONG.player1, boyfriend);
		startCharacterScripts(boyfriend.curCharacter);

		if (dad.curCharacter.startsWith('gf'))
		{
			dad.setPosition(GF_X, GF_Y);
			if (gf != null) gf.visible = false;
		}

		// 重新预加载 Event 会切换到的角色（与完整重开的 eventPushed 预加载一致）
		if (cachedEventNotes != null)
		{
			for (event in cachedEventNotes)
			{
				if (event.event != 'Change Character' || event.value1 == null) continue;
				var charType:Int = 0;
				switch(event.value1.toLowerCase().trim())
				{
					case 'gf' | 'girlfriend': charType = 2;
					case 'dad' | 'opponent': charType = 1;
					default:
						charType = Std.parseInt(event.value1);
						if (Math.isNaN(charType)) charType = 0;
				}
				addCharacterToList(event.value2, charType);
			}
		}

		iconP1.changeIcon(boyfriend.healthIcon);
		iconP2.changeIcon(dad.healthIcon);
		setOnScripts('boyfriendName', boyfriend.curCharacter);
		setOnScripts('dadName', dad.curCharacter);
		if (gf != null) setOnScripts('gfName', gf.curCharacter);
		reloadHealthBarColors();
	}

	private function destroyAllCharacters():Void
	{
		for (group in [boyfriendGroup, dadGroup, gfGroup])
		{
			if (group == null) continue;
			for (member in group.members.copy())
			{
				if (member == null || !Std.isOfType(member, Character)) continue;
				group.remove(member, true);
				cast(member, Character).destroy();
			}
		}
		boyfriendMap.clear();
		dadMap.clear();
		gfMap.clear();
	}

	// 快速重开回溯：当前是否处于时间倒流阶段
	public var rewinding:Bool = false;
	public var keepStrumsOnRestart:Bool = false; // 回溯重开后保留现有判定线，不重新绘制
	public var rewindFromPos:Float = 0;
	public var rewindElapsed:Float = 0;
	public var rewindDuration:Float = 1.0;   // 回溯动画时长（秒），重开时按回溯距离自动计算
	public var rewindMinPosition:Float = 1000; // 歌曲位置低于该毫秒数时不回溯，直接重开
	public var rewindOvershoot:Float = 5000;   // 回溯终点下探上限：最远回溯到 -5000 毫秒（安全兜底）
	public var rewindEndPos:Float = 0;         // 回溯终点（毫秒），由最早音符飞出“出生窗口”的位置自动计算
	public var rewindSpeedMs:Float = 15000;    // 回溯平均速度（毫秒歌曲时间/秒），越大越快
	public var rewindMinDuration:Float = 0.7;  // 回溯时长下限（秒）
	public var rewindMaxDuration:Float = 4.0;  // 回溯时长上限（秒）

	public var totalPlayed:Int = 0;
	public var totalNotes:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;

	// stores the last judgement object
	var lastRating:FlxSprite;
	// stores the last combo sprite object
	var lastCombo:FlxSprite;
	// stores the last combo score objects in an array
	var lastScore:Array<FlxSprite> = [];

	private function cachePopUpScore()
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		for (rating in ratingsData)
			Paths.image(uiPrefix + rating.image + uiSuffix);
		for (i in 0...10)
			Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	// KE 判定评级（Kade Engine）：45/90/135ms 窗口，提前/晚到分开判断，随安全帧缩放
	private function judgeRatingKE(note:Note):Rating
	{
		// botplay 命中时刻由其排期时刻定义（=音符自身 strumTime），帧延迟/批量弹出不影响评级
		var signedDiff:Float = cpuControlled ? 0 : (note.strumTime - Conductor.songPosition);
		var timeScale:Float = Conductor.safeZoneOffset / 166;
		var off:Int = ClientPrefs.data.marvelousJudgement ? 1 : 0;

		// Marvelous：比 Sick 更严（窗口 = Sick 的一半）
		if (off == 1 && Math.abs(signedDiff) <= ratingsData[0].hitWindow * timeScale)
			return ratingsData[0];

		if (signedDiff > 135 * timeScale) return ratingsData[off + 3]; // way early
		if (signedDiff > 90 * timeScale) return ratingsData[off + 2]; // early
		if (signedDiff > 45 * timeScale) return ratingsData[off + 1]; // kinda there
		if (signedDiff < -45 * timeScale) return ratingsData[off + 1]; // little late
		if (signedDiff < -90 * timeScale) return ratingsData[off + 2]; // late
		if (signedDiff < -135 * timeScale) return ratingsData[off + 3]; // late as fuck
		return ratingsData[off]; // sick（marvelous 窗口外）
	}

	private function popUpScore(note:Note = null, ?cappedMult:Int = null):Void
	{
		CrashHandler.mark('popUpScore:start');
		// botplay 命中时间由其排期时刻定义（=音符自身 strumTime），帧延迟不影响评级
		var noteDiff:Float = cpuControlled ? 0 : Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		vocals.volume = 1;

		var placement:Float =  FlxG.width * 0.35;
		var rating:FlxSprite = new FlxSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = null;
		if (replayMode && replayRatingSeqs != null && note.chartSeq >= 0 && replayRatingSeqs.exists(note.chartSeq))
		{
			// 回放：评分直接取录制时本局的真实判定，完整复刻原局准确率
			var replayRating:String = replayRatingSeqs.get(note.chartSeq);
			for (r in ratingsData)
				if (r.name == replayRating) { daRating = r; break; }
		}
		if (daRating == null)
		{
			daRating = (ClientPrefs.data.noteJudgment == 'KE 判定') ? judgeRatingKE(note) : Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
			// 非顶格评级采样（前 40 条，之后零开销）
			if (daRating.name != 'marvelous' && daRating.name != 'sick' && offRatingProbe < 40)
			{
				offRatingProbe++;
				trace('[OFFRATE] n=' + offRatingProbe + ' name=' + daRating.name
					+ ' strum=' + Std.int(note.strumTime) + ' pos=' + Std.int(Conductor.songPosition)
					+ ' diff=' + Std.int(note.strumTime - Conductor.songPosition)
					+ ' ctrl=' + cpuControlled + ' seq=' + note.chartSeq);
			}
		}

		var scoreMult:Int = (cappedMult != null) ? cappedMult : Std.int(note.density);
		if (cappedMult == null && scoreMult < 1) scoreMult = 1; // 未传封顶值（如 Miss 弹窗）走原 density 语义
		totalNotesHit += daRating.ratingMod * scoreMult;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits += scoreMult;
		note.rating = daRating.name;
		// KE 结算散点图：记录主音符命中偏移（+ 早到 / - 晚到；自动游玩不记录）
		if (!cpuControlled && !note.isSustainNote && note.rating != null && note.rating.length > 0)
			judgementHistory.push({t: note.strumTime, d: note.strumTime - Conductor.songPosition, r: note.rating});
		score = daRating.score * scoreMult;

		if(daRating.noteSplash && !note.noteSplashData.disabled && !(cpuControlled && botHitBatch && botBatchSplashDone[note.noteData]))
		{
			spawnNoteSplashOnNote(note);
			if (cpuControlled && botHitBatch) botBatchSplashDone[note.noteData] = true;
		}

		// 上帝模式（practice）同样正常记分/记命中/评准确率（只是不会死）
		songScore += score;
		if(!note.ratingDisabled)
		{
			songHits += scoreMult;
			totalPlayed += scoreMult;
			RecalculateRating(false);
		}

		// 自动游玩批处理：堆叠命中只显示一次评分（其余仅计分），避免一帧内创建大量评分/连击精灵
		if (cpuControlled && botHitBatch)
		{
			if (botBatchScoreShown) return;
			botBatchScoreShown = true;
		}

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		var ratingImg:String = daRating.image;
		// Marvelous 无像素版贴图，像素关卡回退 sick
		if (ratingImg == 'marvelous' && PlayState.isPixelStage) ratingImg = 'sick';
		rating.loadGraphic(Paths.image(uiPrefix + ratingImg + uiSuffix));
		rating.cameras = [camHUD];
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		rating.acceleration.y = 550 * playbackRate * playbackRate;
		rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
		rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.x += ClientPrefs.data.comboOffset[0];
		rating.y -= ClientPrefs.data.comboOffset[1];
		rating.antialiasing = antialias;

		var comboSpr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
		comboSpr.cameras = [camHUD];
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
		comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
		comboSpr.visible = (!ClientPrefs.data.hideHud && showCombo);
		comboSpr.x += ClientPrefs.data.comboOffset[0];
		comboSpr.y -= ClientPrefs.data.comboOffset[1];
		comboSpr.antialiasing = antialias;
		comboSpr.y += 60;
		comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;

		insert(members.indexOf(strumLineNotes), rating);
		
		if (!ClientPrefs.data.comboStacking)
		{
			if (lastRating != null) lastRating.kill();
			lastRating = rating;
		}

		if (!PlayState.isPixelStage)
		{
			rating.setGraphicSize(Std.int(rating.width * 0.7));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		var seperatedScore:Array<Int> = [];

		// 任意位数分解：原逻辑千位封顶，连击超过 9999 会显示错乱（10000 显示成 0000）
		var tempCombo:Int = combo;
		while (tempCombo > 0)
		{
			seperatedScore.push(tempCombo % 10);
			tempCombo = Std.int(tempCombo / 10);
		}
		if (seperatedScore.length == 0) seperatedScore.push(0);
		while (seperatedScore.length < 3) seperatedScore.push(0); // 不足 3 位补零，保持原布局
		seperatedScore.reverse();

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (showCombo)
		{
			insert(members.indexOf(strumLineNotes), comboSpr);
		}
		if (!ClientPrefs.data.comboStacking)
		{
			if (lastCombo != null) lastCombo.kill();
			lastCombo = comboSpr;
		}
		if (lastScore != null)
		{
			while (lastScore.length > 0)
			{
				lastScore[0].kill();
				lastScore.remove(lastScore[0]);
			}
		}
		for (i in seperatedScore)
		{
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
			numScore.cameras = [camHUD];
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + ClientPrefs.data.comboOffset[2];
			numScore.y += 80 - ClientPrefs.data.comboOffset[3];
			
			if (!ClientPrefs.data.comboStacking)
				lastScore.push(numScore);

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			//if (combo >= 10 || combo == 0)
			if(showComboNum)
				insert(members.indexOf(strumLineNotes), numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					numScore.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;
		}
		comboSpr.x = xThing + 50;
		FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
			startDelay: Conductor.crochet * 0.001 / playbackRate
		});

		FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / playbackRate, {
			onComplete: function(tween:FlxTween)
			{
				comboSpr.destroy();
				rating.destroy();
			},
			startDelay: Conductor.crochet * 0.002 / playbackRate
		});
	}

	public var strumsBlocked:Array<Bool> = [];
	#if mobile
	/** 后台化时自动暂停：返回键/侧滑返回/Home 键都会先把游戏切到后台 */
	private function onStageDeactivate(event:Event):Void
	{
		trace('[PAUSE] onStageDeactivate started=' + startedCountdown + ' paused=' + paused + ' canPause=' + canPause);
		if (startedCountdown && !endingSong)
		{
			if (!paused && canPause)
			{
				trace('[PAUSE] openPauseMenu from deactivate');
				openPauseMenu();
			}
			// Meteoric：退后台=冻结游戏——音频位置一并暂停（仅开暂停菜单音乐仍会继续响）
			freezeBackgroundAudio();
		}
	}

	/** 回前台：恢复被后台冻结的音频（游戏仍处于暂停菜单，不自动继续游戏） */
	private function onStageActivate(event:Event):Void
	{
		restoreBackgroundAudio();
	}

	private function freezeBackgroundAudio():Void
	{
		if (_bgAudioFrozen) return;
		_bgAudioFrozen = true;
		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		if (vocals != null) vocals.pause();
		if (opponentVocals != null) opponentVocals.pause();
	}

	private function restoreBackgroundAudio():Void
	{
		if (!_bgAudioFrozen) return;
		_bgAudioFrozen = false;
		// 若玩家仍处于暂停菜单（未返回游戏），保持静音；真正恢复由 closeSubState/resyncVocals 负责
		if (paused) return;
		if (FlxG.sound.music != null) FlxG.sound.music.play();
		if (vocals != null) vocals.play();
		if (opponentVocals != null) opponentVocals.play();
	}
	#end

	private function onKeyPress(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if (!controls.controllerMode && FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
	}

	private function keyPressed(key:Int)
	{
		if (!cpuControlled && !paused && !rewinding && key > -1 && startedCountdown && (!replayMode || replayInjecting))
		{
			// 回放录制：记录按键按下事件（重放时按时间注入，走同样的判定路径）
			if (recordingReplay && currentReplay != null)
				currentReplay.recordInput(Conductor.songPosition, key, false);
			var mashPenalty:Bool = false;

			if(notes.length > 0 && !boyfriend.stunned && generatedMusic && !endingSong)
			{
				//more accurate hit time for the ratings?
				var lastTime:Float = Conductor.songPosition;
				if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time;

				var canMiss:Bool = !ClientPrefs.data.ghostTapping;

				// KE 判定：防乱按（Kade Engine 规则）——按下按键数超过可命中音符数时直接扣分
				if (ClientPrefs.data.noteJudgment == 'KE 判定')
				{
					var hasHittable:Bool = false;
					notes.forEachAlive(function(daNote:Note)
					{
						if (daNote.noteData == key && daNote.canBeHit && daNote.mustPress && !daNote.tooLate &&
							!daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
							hasHittable = true;
					});

					if (hasHittable)
					{
						var hittableCount:Int = 0;
						notes.forEachAlive(function(daNote:Note)
						{
							if (daNote.canBeHit && daNote.mustPress && !daNote.tooLate)
								hittableCount++;
						});

						var pressedCount:Int = 0;
						for (i in 0...keysArray.length)
							if (strumsBlocked[i] != true && controls.pressed(keysArray[i]))
								pressedCount++;

						// 只有一个音符时可多容忍一个按键，其余情况不能超过可命中音符数
						var allowedPresses:Int = (hittableCount == 1) ? hittableCount + 1 : hittableCount;
						if (pressedCount > allowedPresses)
						{
							mashPenalty = true;
							songScore -= 25;
							FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
							playerStrums.forEach(function(spr:StrumNote)
							{
								if (spr != null && spr.animation.curAnim.name != 'static')
								{
									spr.playAnim('static');
									spr.resetAnim = 0;
								}
							});
						}
					}
				}

				if (!mashPenalty)
				{
					// heavily based on my own code LOL if it aint broke dont fix it
					var pressNotes:Array<Note> = [];
					var notesStopped:Bool = false;
					var sortedNotesList:Array<Note> = [];
					notes.forEachAlive(function(daNote:Note)
					{
						if (strumsBlocked[daNote.noteData] != true && daNote.canBeHit && daNote.mustPress &&
							!daNote.tooLate && !daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
						{
							if(daNote.noteData == key) sortedNotesList.push(daNote);
							canMiss = true;
						}
					});
					sortedNotesList.sort(sortHitNotes);

					if (sortedNotesList.length > 0) {
						for (epicNote in sortedNotesList)
						{
							for (doubleNote in pressNotes) {
								if (Math.abs(doubleNote.strumTime - epicNote.strumTime) < 1) {
									notes.invalidateNote(doubleNote);
								} else
									notesStopped = true;
							}

							// eee jack detection before was not super good
							if (!notesStopped) {
								goodNoteHit(epicNote);
								pressNotes.push(epicNote);
							}

						}
					}
					else {
						callOnScripts('onGhostTap', [key]);
						if (canMiss && !boyfriend.stunned)
						{
							// 回放录制：记录这次会真正触发 Miss 的空按（幽灵点击开启且非 KE 时不记）
							if (recordingReplay && currentReplay != null
								&& (ClientPrefs.data.noteJudgment == 'KE 判定' || !ClientPrefs.data.ghostTapping))
								recordReplayEvent(-1, Conductor.songPosition, key, 'mp');
							// KE 判定防乱按：旁边有可命中音符时，按到没有音符的列也强制 Miss（等同关闭幽灵点击）
							if (ClientPrefs.data.noteJudgment == 'KE 判定')
								noteMissPress(key, true);
							else
								noteMissPress(key);
						}
					}

					// I dunno what you need this for but here you go
					//									- Shubs

					// Shubs, this is for the "Just the Two of Us" achievement lol
					//									- Shadow Mario
					if(!keysPressed.contains(key)) keysPressed.push(key);
				}

				//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
				Conductor.songPosition = lastTime;
			}

			var spr:StrumNote = playerStrums.members[key];
			if(strumsBlocked[key] != true && spr != null && !mashPenalty && spr.animation.curAnim.name != 'confirm')
			{
				spr.playAnim('pressed');
				spr.resetAnim = 0;
			}
			callOnScripts('onKeyPress', [key]);
		}
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	private function keyReleased(key:Int)
	{
		if(!cpuControlled && startedCountdown && !paused && (!replayMode || replayInjecting))
		{
			// 回放录制：记录按键抬起事件
			if (recordingReplay && currentReplay != null)
				currentReplay.recordInput(Conductor.songPosition, key, true);
			var spr:StrumNote = playerStrums.members[key];
			if(spr != null)
			{
				spr.playAnim('static');
				spr.resetAnim = 0;
			}
			callOnScripts('onKeyRelease', [key]);
		}
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// Hold notes
	private function keysCheck():Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in keysArray)
		{
			holdArray.push(controls.pressed(key));
			pressArray.push(controls.justPressed(key));
			releaseArray.push(controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !boyfriend.stunned && generatedMusic)
		{
			// rewritten inputs???
			if(notes.length > 0)
			{
				notes.forEachAlive(function(daNote:Note)
				{
					// hold note functions
					if (strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && holdArray[daNote.noteData] && daNote.canBeHit
					&& daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit) {
						if (ClientPrefs.data.noteJudgment == 'KE 判定')
						{
							// KE 判定：长条不参与判定，按住时子段仅做视觉消除
							daNote.wasGoodHit = true;
							if (recordingReplay && currentReplay != null)
								currentReplay.addEvent(daNote.chartSeq, daNote.strumTime, daNote.noteData, 'sus');
							daNote.active = false;
							daNote.visible = false;
							notes.invalidateNote(daNote);
						}
						else goodNoteHit(daNote);
					}
				});
			}

			if (holdArray.contains(true) && !endingSong) {
				#if ACHIEVEMENTS_ALLOWED
				var achieve:String = checkForAchievement(['oversinging']);
				if (achieve != null) {
					startAchievement(achieve);
				}
				#end
			}
			else if (boyfriend != null && boyfriend.getAnimationName().startsWith('sing') && !boyfriend.getAnimationName().endsWith('miss') && boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 / FlxG.sound.music.pitch) * boyfriend.singDuration)
			{
				boyfriend.dance();
				//boyfriend.animation.curAnim.finish();
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	/** 回放 v2：按录制时间注入按键按下/抬起（走正常判定路径），并处理长按子段命中 */
	private function updateReplayInputs():Void
	{
		if (!startedCountdown || paused || rewinding || endingSong || inCutscene) return;

		// 注入到点按键事件：按下走 keyPressed（真实判定），抬起走 keyReleased（strum 复位）
		replayInjecting = true;
		while (replayInputPtr < replayInputs.length && Conductor.songPosition >= replayInputs[replayInputPtr].t)
		{
			var ev:ReplayInput = replayInputs[replayInputPtr++];
			if (ev.d < 0 || ev.d > 3) continue;
			if (ev.u)
			{
				replayHeld[ev.d] = false;
				keyReleased(ev.d);
			}
			else
			{
				replayHeld[ev.d] = true;
				keyPressed(ev.d);
			}
		}
		replayInjecting = false;

		// 长按：与 keysCheck 的 HOLD 段一致（按住期间长条子段逐个命中/消除）
		if (generatedMusic && notes.length > 0 && !boyfriend.stunned)
		{
			var anyHold:Bool = false;
			for (i in 0...4)
				if (replayHeld[i]) { anyHold = true; break; }
			if (anyHold)
			{
				notes.forEachAlive(function(daNote:Note)
				{
					if (strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && replayHeld[daNote.noteData]
						&& daNote.canBeHit && daNote.mustPress && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit)
					{
						if (ClientPrefs.data.noteJudgment == 'KE 判定')
						{
							// KE 判定：长条不参与判定，按住时子段仅做视觉消除
							daNote.wasGoodHit = true;
							daNote.active = false;
							daNote.visible = false;
							notes.invalidateNote(daNote);
						}
						else goodNoteHit(daNote);
					}
				});
			}
		}
	}

	/** 回放 v2：暂停菜单跳时间后，把按键游标对齐到新时间点 */
	public function resetReplayToTime(t:Float):Void
	{
		replayInputPtr = 0;
		while (replayInputPtr < replayInputs.length && replayInputs[replayInputPtr].t < t)
			replayInputPtr++;
		replayHeld = [false, false, false, false];
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote)); //Psych 1.0.4：场景 miss 回调（Weekend 1）
		// NPS 统计：漏掉的音符也计入“收到”（堆叠合并按 density 计）
		if (!daNote.isSustainNote) _npsCount += Std.int(daNote.density);
		// Dupe note remove：只移除"谱面原始重复"（charter 在同一个时间刻度上放了多颗完全相同音符）。
		// 展开簇内同时间箭头（同 chartSeq）不在此列——否则整簇被静默杀掉不计数，结算总数对不上。
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData
				&& daNote.isSustainNote == note.isSustainNote
				&& Math.abs(daNote.strumTime - note.strumTime) < 1
				&& note.chartSeq != daNote.chartSeq) {
				notes.invalidateNote(note);
			}
		});
		
		noteMissCommon(daNote.noteData, daNote);
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('noteMiss', [daNote]);
	}

	function noteMissPress(direction:Int = 1, force:Bool = false):Void //You pressed a key when there was no notes to press for this key
	{
		stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction)); //Psych 1.0.4：场景误触回调（Weekend 1）
		if(ClientPrefs.data.ghostTapping && !force) return; //fuck it

		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// KE 结算散点图：主音符 Miss 记录（贴外沿窗口 = 视为最晚；空按/长条子段不记）
		if (note != null && !note.isSustainNote && !cpuControlled)
		{
			var outer:Float = (ratingsData != null && ratingsData.length > 0) ? ratingsData[ratingsData.length - 1].hitWindow : 166;
			if (outer <= 0) outer = 166;
			judgementHistory.push({t: note.strumTime, d: outer, r: 'miss'});
		}

		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;
		health -= subtract * healthLoss;

		if(instakillOnMiss)
		{
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}
		combo = 0;

		var missMult:Int = note != null ? Std.int(note.density) : 1; // H-Slice 移植：堆叠合并按 density 计 Miss
		if (missMult < 1) missMult = 1;
		songScore -= 10 * missMult;
		if(!endingSong) songMisses += missMult;
		totalPlayed += missMult;
		RecalculateRating(true);

		// play character anims
		var char:Character = boyfriend;
		if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;
		
		if(char != null && char.hasMissAnimations)
		{
			var suffix:String = '';
			if(note != null) suffix = note.animSuffix;

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + suffix;
			char.playAnim(animToPlay, true);
			
			if(char != gf && combo > 5 && gf != null && gf.animOffsets.exists('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		vocals.volume = 0;
		opponentVocals.volume = 0;
	}

	function opponentNoteHit(note:Note):Void
	{
		stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note)); //Psych 1.0.4：场景命中回调（Weekend 1）
		if (Paths.formatToSongPath(SONG.song) != 'tutorial')
			camZooming = true;

		if(note.noteType == 'Hey!' && dad.animOffsets.exists('hey')) {
			dad.playAnim('hey', true);
			dad.specialAnim = true;
			dad.heyTimer = 0.6;
		} else if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (SONG.notes[curSection] != null)
			{
				if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection) {
					altAnim = '-alt';
				}
			}

			var char:Character = dad;
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + altAnim;
			if(note.gfNote) {
				char = gf;
			}

			if(char != null)
			{
				char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if (SONG.needsVoices && opponentVocals.length <= 0)
			vocals.volume = 1;

		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;

		var result:Dynamic = callOnLuas('opponentNoteHit', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('opponentNoteHit', [note]);

		// 原生长条按压覆盖（模组 opponentNoteHit 回调同点触发，轨偏移 +4）
		if (holdCoverHandler != null && note.isSustainNote)
			holdCoverHandler.onHit(4 + Std.int(Math.abs(note.noteData)));

		if (!note.isSustainNote)
		{
			// 对方推条：开启后对手命中箭头会像玩家一样加血（推条向对方侧移动），但最低保留一点血量，不会被推死
			if (ClientPrefs.getGameplaySetting('opponentpush') == true)
				health -= Math.min(note.hitHealth * healthLoss, Math.max(0, health - 0.01));
			notes.invalidateNote(note);
		}
	}

	// 自动游玩批处理：统一命中本帧收集的音符，堆叠时合并副作用
	function recordReplayEvent(seq:Int, t:Float, d:Int, r:String):Void
	{
		if (recordingReplay && currentReplay != null && !cpuControlled && !replayMode)
			currentReplay.addEvent(seq, t, d, r);
	}

	function processBotHits():Void
	{
		if (botHitQueue.length == 0) return;
		if (rewinding) { botHitQueue.resize(0); return; }
		botHitBatch = true;
		botBatchSeenSeq = new Map<Int, Bool>(); // 批内按 chartSeq 去重：同帧池化复活对象不二次计分
		for (note in botHitQueue)
		{
			if (note == null || !note.alive || note.blockHit) continue;
			if (note.chartSeq >= 0)
			{
				if (botBatchSeenSeq.exists(note.chartSeq)) continue;
				botBatchSeenSeq.set(note.chartSeq, true);
			}
			// 基准命中：同簇视觉副本一并销毁（否则副本滞留判定线形成"每轨一坨"）。
			// 倒序遍历：invalidateNote 会 splice 组数组，正序遍历会跳项（副本漏杀→飞过判定线）
			if (!note.isSustainNote && note.chartSeq >= 0)
			{
				var mi:Int = notes.members.length - 1;
				while (mi >= 0)
				{
					var sib:Note = notes.members[mi];
					if (sib != null && sib != note && sib.blockHit && sib.ignoreNote && sib.chartSeq == note.chartSeq)
						notes.invalidateNote(sib);
					mi--;
				}
			}
			if (ClientPrefs.data.noteJudgment == 'KE 判定' && note.isSustainNote)
			{
				// KE 判定：长条不参与判定，子段仅做视觉消除
				note.wasGoodHit = true;
				note.active = false;
				note.visible = false;
				notes.invalidateNote(note);
				continue;
			}
			goodNoteHit(note);
			if (!note.wasGoodHit) note.wasGoodHit = true; // ignore/伤害音符：只消费一次，避免下帧重复收集
			// 批处理下 goodNoteHit 只回收批内第一颗（其余在 botBatchScoreShown 早退）——
			// 这里对仍存活的命中音符统一视觉回收：命中即灭，杜绝"击中但飞过判定线"
			if (!note.isSustainNote && note.alive)
			{
				note.active = false;
				note.visible = false;
				notes.invalidateNote(note);
			}
		}
		botHitBatch = false;
		botHitQueue.resize(0);
		botBatchAnimDone = [false, false, false, false];
		botBatchSplashDone = [false, false, false, false];
		botBatchHitsoundDone = false;
		botBatchScoreShown = false;
	}

	function goodNoteHit(note:Note):Void
	{
		stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note)); //Psych 1.0.4：场景命中回调（Weekend 1）
		if (!note.wasGoodHit)
		{
			var hitMult:Int = Std.int(note.density); // H-Slice 移植：堆叠合并按 density 计分/加血
			if (hitMult < 1) hitMult = 1;
			// 计数权威封顶：命中/连击/评级/分数累计不得超过总音符数（批次去重噪声等超额在此截断），
			// 结算时 Combo/Marvelous/…/分数恰好等于总音符数（1,130,083 级谱面 = totalNotes）
			if (totalNotes > 0)
			{
				if (songHits >= totalNotes) hitMult = 0;
				else if (songHits + hitMult > totalNotes) hitMult = Std.int(totalNotes - songHits);
			}
			// NPS 统计：每个音符（含长条）只计一次，只计独立音符（堆叠合并按 density 计）
			if (!note.isSustainNote) _npsCount += hitMult;
			if(cpuControlled && (note.ignoreNote || note.hitCausesMiss)) return;

			note.wasGoodHit = true;
			// 回放录制：长条子段命中（Psych 判定按住时的子段逐个记录）
			if (recordingReplay && !cpuControlled && currentReplay != null && note.isSustainNote)
				currentReplay.addEvent(note.chartSeq, note.strumTime, note.noteData, 'sus');
			if (ClientPrefs.data.hitsoundVolume > 0 && !note.hitsoundDisabled && !(botHitBatch && botBatchHitsoundDone))
			{
				FlxG.sound.play(Paths.sound(note.hitsound), ClientPrefs.data.hitsoundVolume);
				if (botHitBatch) botBatchHitsoundDone = true;
			}

			if(note.hitCausesMiss) {
				// 回放录制：伤害音符的命中（回放时同样走命中→受伤流程）
				if (recordingReplay && !cpuControlled && currentReplay != null && !note.isSustainNote)
					currentReplay.addEvent(note.chartSeq, note.strumTime, note.noteData, 'hurt');
				noteMiss(note);
				if(!note.noteSplashData.disabled && !note.isSustainNote) {
					spawnNoteSplashOnNote(note);
				}

				if(!note.noMissAnimation)
				{
					switch(note.noteType) {
						case 'Hurt Note': //Hurt note
							if(boyfriend.animation.getByName('hurt') != null) {
								boyfriend.playAnim('hurt', true);
								boyfriend.specialAnim = true;
							}
					}
				}

				if (!note.isSustainNote)
				{
					notes.invalidateNote(note);
				}
				return;
			}

			if (!note.isSustainNote)
			{
				combo += hitMult;
				if (combo > maxCombo) maxCombo = combo; // 最高连击追踪
				popUpScore(note, hitMult); // 传入已封顶的 density：计分/评级/命中同源封顶
				// 回放录制：主音符命中（评分取本局真实判定结果）
				if (recordingReplay && !cpuControlled && currentReplay != null)
					currentReplay.addEvent(note.chartSeq, note.strumTime, note.noteData, note.rating);
			}
			health += note.hitHealth * healthGain * hitMult;
			// Bad 及以下评分扣一点点血
			if (!note.isSustainNote && (note.rating == 'bad' || note.rating == 'shit'))
				health -= 0.02 * healthLoss * hitMult;

			if(!note.noAnimation && !(botHitBatch && botBatchAnimDone[note.noteData])) {
				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))];

				var char:Character = boyfriend;
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = gf;
					animCheck = 'cheer';
				}
				
				if(char != null)
				{
					char.playAnim(animToPlay + note.animSuffix, true);
					char.holdTimer = 0;
					
					if(note.noteType == 'Hey!') {
						if(char.animOffsets.exists(animCheck)) {
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
				if (botHitBatch) botBatchAnimDone[note.noteData] = true;
			}

			if(!cpuControlled && !replayMode)
			{
				// 手动命中：strum 高亮由松键（keyReleased -> static）熄灭
				var spr = playerStrums.members[note.noteData];
				if(spr != null) spr.playAnim('confirm', true);
			}
			else if (!(botHitBatch && botBatchAnimDone[note.noteData]))
				// 自动游玩/回放：confirm 高亮带复位计时，避免判定后常亮
				strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			vocals.volume = 1;

			var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
			var leData:Int = Math.round(Math.abs(note.noteData));
			var leType:String = note.noteType;
			
			var result:Dynamic = callOnLuas('goodNoteHit', [notes.members.indexOf(note), leData, leType, isSus]);
			if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('goodNoteHit', [note]);

			// 原生长条按压覆盖（模组 goodNoteHit 回调同点触发）
			if (holdCoverHandler != null && note.isSustainNote)
				holdCoverHandler.onHit(Std.int(Math.abs(note.noteData)));

			if (!note.isSustainNote)
			{
				notes.invalidateNote(note);
			}
		}
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerStrums.members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note);
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		#if LUA_ALLOWED
		for (i in 0...luaArray.length) {
			var lua:FunkinLua = luaArray[0];
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				script.call('onDestroy');
				script.destroy();
			}

		while (hscriptArray.length > 0)
			hscriptArray.pop();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		#if mobile
		FlxG.stage.removeEventListener(Event.DEACTIVATE, onStageDeactivate);
		FlxG.stage.removeEventListener(Event.ACTIVATE, onStageActivate);
		#end
		FlxAnimationController.globalSpeed = 1;
		FlxG.sound.music.pitch = 1;
		Note.globalRgbShaders = [];
		Note.seqNote = [];
		Note.seqHit = [];
		spamNotes = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		// 离开对局后清掉待重开的回放数据，避免影响后续普通对局
		carryReplay = null;
		instance = null;
		holdCoverHandler = null;
		if (hud != null && hud.judgementField != null && hud.judgementField.parent != null)
			FlxG.stage.removeChild(hud.judgementField);
		super.destroy();

		// 完成或退出曲目后自动清理 RAM
		// （快速重开 restartSongWithoutReload 不销毁本 State，不受影响）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		Paths.clearPendingBitmaps(); // 收尾：释放未被消费的预解码贴图（异步分片可能仍未消费完）
	}

	// 结算权威钳制：命中/进行数不超总音符（池化复用与批处理的帧级噪声不污染结算面板）
	public function clampGameplayTotals():Void
	{
		if (totalNotes > 0 && songHits > totalNotes)
			songHits = totalNotes;
		if (totalNotes > 0 && totalPlayed > totalNotes)
			totalPlayed = totalNotes;
		if (totalNotes > 0 && totalNotesHit > totalNotes)
			totalNotesHit = totalNotes;
	}

	var offRatingProbe:Int = 0; // 非顶格评级采样计数（前 40 条，零持续开销）

	public static function cancelMusicFadeTween() {
		if(FlxG.sound.music.fadeTween != null) {
			FlxG.sound.music.fadeTween.cancel();
		}
		FlxG.sound.music.fadeTween = null;
	}

	var lastStepHit:Int = -1;
	// 判定时序诊断：music.time 与 songPosition 的偏差（SDL3 音频时序漂移会导致判定窗口错位）
	static var _lastDriftTraceStep:Int = -9999;
	override function stepHit()
	{
		if (rewinding) return; // 回溯期间不触发步点回调，避免重开音频

		if(FlxG.sound.music.time >= -ClientPrefs.data.noteOffset)
		{
			var drift:Float = FlxG.sound.music.time - (Conductor.songPosition - Conductor.offset);
			if (Math.abs(drift) > (20 * playbackRate)
				|| (SONG.needsVoices && Math.abs(vocals.time - (Conductor.songPosition - Conductor.offset)) > (20 * playbackRate))
				|| (SONG.needsVoices && opponentVocals.length > 0 && Math.abs(opponentVocals.time - (Conductor.songPosition - Conductor.offset)) > (20 * playbackRate)))
			{
				resyncVocals();
			}
			// 节流诊断：每 48 步（约 12 拍 @120BPM）打印一次时序偏差
			if (curStep - _lastDriftTraceStep >= 48)
			{
				_lastDriftTraceStep = curStep;
				trace('[TIMING] step=' + curStep + ' music=' + Std.int(FlxG.sound.music.time) + ' songPos=' + Std.int(Conductor.songPosition) + ' drift=' + Std.int(drift) + 'ms fps=' + Std.int(FlxG.drawFramerate));
			}
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if (rewinding) return; // 回溯期间不触发拍点回调（角色/图标保持静止）

		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

	if(ClientPrefs.data.sbIconBop){
		if (curBeat % gfSpeed == 0) {
			if (curBeat % (gfSpeed * 2) == 0) {
				iconP1.scale.set(0.8, 0.8);
				iconP2.scale.set(1.2, 1.3);
				
				iconP1.angle = -15;
				iconP2.angle = 15;
			} else {
				iconP2.scale.set(0.8, 0.8);
				iconP1.scale.set(1.2, 1.3);
				
				iconP2.angle = -15;
				iconP1.angle = 15;
			}
		}
	}

		if (ClientPrefs.data.keIconBop)
		{
			// KE 引擎图标跳动：每拍放大 30px（相当于 scale + 30/frameWidth），随后在 update 中按时间缩回
			iconP1.scale.x += 30 / iconP1.frameWidth;
			iconP1.scale.y = iconP1.scale.x;
			iconP1.updateHitbox();
			iconP1.origin.set(0, 0); // Kade 风格：以左上角为缩放中心，放大时向右下扩展
			iconP2.scale.x += 30 / iconP2.frameWidth;
			iconP2.scale.y = iconP2.scale.x;
			iconP2.updateHitbox();
			iconP2.origin.set(0, 0);
		}
		else
		{
			iconP1.scale.set(1.2, 1.2);
			iconP2.scale.set(1.2, 1.2);

			iconP1.updateHitbox();
			iconP2.updateHitbox();
		}

		if (gf != null && curBeat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && curBeat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && curBeat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	override function sectionHit()
	{
		if (rewinding) return; // 回溯中不移动镜头、不改 BPM
		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
			{
				FlxG.camera.zoom += 0.015 * camZoomingMult;
				camHUD.zoom += 0.03 * camZoomingMult;
			}

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();
		
		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getPreloadPath(luaFile);
		
		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getPreloadPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;
	
			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end
	
	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getPreloadPath(scriptFile);
		
		if(FileSystem.exists(scriptToLoad))
		{
			if (SScript.global.exists(scriptToLoad)) return false;
	
			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		// 回放模式不加载 HScript（与 Lua 同理：避免脚本修改箭头显示影响回放）
		if (replayMode) return;
		try
		{
			// Psych 0.7.3 兼容：读取 .hx 内容并预处理（var x:Map = [] → new Map()），以代码串交给 SScript
			var scriptCode:String = file;
			#if sys
			try
			{
				if (sys.FileSystem.exists(file))
					scriptCode = HScript.preprocessScript(sys.io.File.getContent(file));
			}
			catch (e:Dynamic) {}
			#end
			var newScript:HScript = new HScript(null, scriptCode);
			// 66mod 等 Psych 0.7 模组对话脚本需要 songName / startDialogue
			newScript.set('songName', songName);
			newScript.set('startDialogue', function(dialogue:Dynamic) startDialogue(dialogue));
			// Psych 0.7.3 setSpecialObject 等价物：onCreate 阶段即可访问角色/摄像机（setOnScripts 只推给已加载脚本，stage 脚本加载时拿不到）
			newScript.set('dad', dad);
			newScript.set('boyfriend', boyfriend);
			newScript.set('gf', gf);
			newScript.set('camGame', camGame);
			// 兼容 66mod 舞台脚本（home.hx 等直接访问 camFollow/camHUD）
			newScript.set('camFollow', camFollow);
			newScript.set('camHUD', camHUD);
			@:privateAccess
			if(newScript.parsingExceptions != null && newScript.parsingExceptions.length > 0)
			{
				@:privateAccess
				for (e in newScript.parsingExceptions)
					if(e != null)
						addTextToDebug('ERROR ON LOADING ($file): ${e.message.substr(0, e.message.indexOf('\n'))}', FlxColor.RED);
				newScript.destroy();
				return;
			}

			hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
						if (e != null)
						{
							var errMsg:String = e.message != null ? e.message : Std.string(e);
							addTextToDebug('ERROR ($file: onCreate) - ${errMsg.substr(0, errMsg.indexOf('\n'))}', FlxColor.RED);
						}

					newScript.destroy();
					hscriptArray.remove(newScript);
					trace('failed to initialize sscript interp!!! ($file)');
				}
				else trace('initialized sscript interp successfully: $file');
			}
			
		}
		catch(e)
		{
			addTextToDebug('ERROR ($file) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
			var newScript:HScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				hscriptArray.remove(newScript);
			}
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [psychlua.FunkinLua.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = FunkinLua.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [FunkinLua.Function_Continue];

		var len:Int = luaArray.length;
		var i:Int = 0;
		while(i < len)
		{
			var script:FunkinLua = luaArray[i];
			if(exclusions.contains(script.scriptName))
			{
				i++;
				continue;
			}

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == FunkinLua.Function_StopLua || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}
			
			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(!script.closed) i++;
			else len--;
		}
		#end
		return returnVal;
	}
	
	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(psychlua.FunkinLua.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len)
		{
			var script:HScript = hscriptArray[i];
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try
			{
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
						FunkinLua.luaTrace('ERROR (${script.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), true, false, FlxColor.RED);
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == FunkinLua.Function_StopHScript || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}
					
					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != FunkinLua.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce -Ghost
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
	}

	function fullComboUpdate()
	{
		if(songMisses < 1)
		{
			ratingFC = 'FC';
		}else if (songMisses < 10){
			ratingFC = 'SDCB';
		}else{
			ratingFC = 'Clear';
		}
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null):String
	{
		if(chartingMode) return null;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		for (i in 0...achievesToCheck.length) {
			var achievementName:String = achievesToCheck[i];
			if(!Achievements.isAchievementUnlocked(achievementName) && !cpuControlled && Achievements.getAchievementIndex(achievementName) > -1) {
				var unlock:Bool = false;
				if (achievementName == WeekData.getWeekFileName() + '_nomiss') // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
				{
					if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
						&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
						unlock = true;
				}
				else
				{
					switch(achievementName)
					{
						case 'ur_bad':
							unlock = (ratingPercent < 0.2 && !practiceMode);

						case 'ur_good':
							unlock = (ratingPercent >= 1 && !usedPractice);

						case 'roadkill_enthusiast':
							unlock = (Achievements.henchmenDeath >= 50);

						case 'oversinging':
							unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

						case 'hype':
							unlock = (!boyfriendIdled && !usedPractice);

						case 'two_keys':
							unlock = (!usedPractice && keysPressed.length <= 2);

						case 'toastie':
							unlock = (/*ClientPrefs.data.framerate <= 60 &&*/ !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

						case 'debugger':
							unlock = (Paths.formatToSongPath(SONG.song) == 'test' && !usedPractice);
					}
				}

				if(unlock) {
					Achievements.unlockAchievement(achievementName);
					return achievementName;
				}
			}
		}
		return null;
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	// Psych 0.7.3 兼容：mod（FunkinMix 等）的 runHaxeCode 用 game.FlxRuntimeShaderMap 缓存运行时 shader 实例
	public var FlxRuntimeShaderMap:Map<String, FlxRuntimeShader> = new Map<String, FlxRuntimeShader>();
	public function createRuntimeShader(name:String):FlxRuntimeShader
	{
		if(!ClientPrefs.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!runtimeShaders.exists(name) && !initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		backend.CrashHandler.logEvent('createRuntimeShader: ' + name);
		var arr:Array<String> = runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));

		for(mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));
		
		for (folder in foldersToCheck)
		{
			if(FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if(FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else frag = null;

				if(FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else vert = null;

				if(found)
				{
					runtimeShaders.set(name, [frag, vert]);
					//trace('Found shader $name!');
					return true;
				}
			}
		}
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}
	#end
}

/**
 * ============================================================
 * GameHUD —— PlayState 的 HUD/UI 子系统（重构版）
 * ============================================================
 * 从 PlayState 中抽离的全部 HUD 职责集中于此：
 *   1. 创建：血条/血量阴影/图标/分数/歌曲名/时间条/时间文字/自动游玩标签
 *   2. 每帧更新：图标跳动回缩、图标跟随血量条、血量/时间阴影滚动、botplay 呼吸
 *   3. 可见性权威 enforce()：每帧把 HUD 可见性强制恢复为设置值，
 *      无论 Lua/Hscript/Mod/遗留代码把哪个元素 visible 改掉，下一帧都拉回 ——
 *      根治“游玩中 UI 突然消失（只剩箭头和时间条）”问题。
 * 兼容性：所有元素仍通过 PlayState 的 public 字段暴露（healthBar/iconP1/scoreTxt…），
 * Lua/Hscript 的 getProperty/setProperty 完全不受影响。
 */
class GameHUD
{
	public var healthBar:HealthBar;
	public var healthBarOverlay:FlxTiledSprite;
	public var healthBarBG:AttachedSprite;
	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var scoreTxt:FlxText;
	public var songTxt:FlxText;
	public var timeBar:TimeBar;
	public var timeBarOverlay:FlxTiledSprite;
	public var timeTxt:FlxText;
	public var timeBarBG:AttachedSprite;
	public var botplayTxt:FlxText;
	public var judgementField:openfl.text.TextField; // 判定计数侧边栏（openfl 直接渲染，部分着色）

	var st:PlayState;            // 宿主对局
	var lastHpPercent:Float = 50;
	var healthOverlayDir:Int = -1; // 血量阴影滚动方向：-1 向左（回血） / +1 向右（掉血）

	public function new(st:PlayState)
	{
		this.st = st;
	}

	// ==================== 创建 ====================

	public function build():Void
	{
		var showTime:Bool = (ClientPrefs.data.timeBarType != '禁用');
		st.hudLayout = ClientPrefs.data.hudLayout;

		// ---- 时间条（上）+ 时间文字（下） ----
		var hudTimeOff:Array<Float> = st.hudGetOffset('timeBar');
		var timeBarY:Float = 19;
		if (ClientPrefs.data.downScroll && !st.isPhigrosStyle) timeBarY = FlxG.height - 44;
		timeBarY += hudTimeOff[1];

		timeBar = new TimeBar(0, timeBarY, function() return st.songPercent, 0, 1, ClientPrefs.data.newTimeBarStyle);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.x += hudTimeOff[0];
		if (ClientPrefs.data.newTimeBarStyle)
		{
			var fillColor:FlxColor = FlxColor.fromRGB(st.dad.healthColorArray[0], st.dad.healthColorArray[1], st.dad.healthColorArray[2]);
			if (fillColor.red + fillColor.green + fillColor.blue < 120) fillColor = 0xFF00FFFF;
			timeBar.leftBar.color = fillColor;
			timeBar.rightBar.color = 0xFF000000;
		}
		else
		{
			// Psych 0.6.3 兼容：贴图模式（timeBar.png）的填充默认为 0.6.3 的青色；
			// 设置中开启"时间条颜色跟随对方"后，使用对方角色血量条颜色（过暗/过亮时兜底青色）
			var fillColor:FlxColor = 0xFF00FFFF;
			if (ClientPrefs.data.timeBarOpponentColors && st.dad != null)
			{
				fillColor = FlxColor.fromRGB(st.dad.healthColorArray[0], st.dad.healthColorArray[1], st.dad.healthColorArray[2]);
				if (fillColor.red + fillColor.green + fillColor.blue < 120 || fillColor.red + fillColor.green + fillColor.blue > 660)
					fillColor = 0xFF00FFFF;
			}
			timeBar.leftBar.color = fillColor;
			timeBar.rightBar.color = 0xFF000000;
		}
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		st.add(timeBar);

		timeBarOverlay = new FlxTiledSprite(Paths.image('healthBarOverlay'), Std.int(timeBar.bg.width), Std.int(timeBar.bg.height));
		timeBarOverlay.x = timeBar.x;
		timeBarOverlay.y = timeBar.y;
		timeBarOverlay.scrollFactor.set();
		timeBarOverlay.color = FlxColor.BLACK;
		timeBarOverlay.alpha = 0;
		timeBarOverlay.visible = showTime && !ClientPrefs.data.hideHud;
		timeBarOverlay.antialiasing = ClientPrefs.data.antialiasing;
		st.add(timeBarOverlay);

		timeTxt = new FlxText(PlayState.STRUM_X + (FlxG.width / 2) - 248 + hudTimeOff[0], timeBarY + 25, 400, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 25, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = st.updateTime = showTime;
		// downScroll 时调换：时间条贴底，时间文字移到时间条上方
		if (ClientPrefs.data.downScroll && !st.isPhigrosStyle) timeTxt.y = timeBarY - 25;
		if (ClientPrefs.data.timeBarType == '歌曲名称') timeTxt.text = PlayState.SONG.song;

		timeBarBG = new AttachedSprite('timeBar');
		timeBarBG.x = timeBar.x;
		timeBarBG.y = timeBar.y;
		timeBarBG.scrollFactor.set();
		timeBarBG.alpha = 0;
		timeBarBG.visible = false;
		timeBarBG.color = FlxColor.BLACK;
		timeBarBG.xAdd = -4;
		timeBarBG.yAdd = -4;
		timeBarBG.sprTracker = timeBar;
		st.add(timeBarBG);
		st.add(timeTxt);

		if (ClientPrefs.data.timeBarType == '歌曲名称')
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		// ---- 血量条 + 图标 + 分数 + 歌曲名 + 自动游玩标签 ----
		var hudHpOff:Array<Float> = st.hudGetOffset('healthBar');
		var defaultHpY:Float = FlxG.height * (!ClientPrefs.data.downScroll || st.isPhigrosStyle ? 0.89 : 0.11);
		healthBar = new HealthBar(0, defaultHpY + hudHpOff[1], 'healthBar',
			function() return (ClientPrefs.data.smoothHealth) ? st.smoothHealth : st.health, 0, 2,
			ClientPrefs.data.oldHealthBar || ClientPrefs.data.newHealthBar);
		healthBar.screenCenter(X);
		healthBar.x += hudHpOff[0];
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();

		healthBarBG = new AttachedSprite('healthBar');
		healthBarBG.y = healthBar.y;
		healthBarBG.screenCenter(X);
		healthBarBG.scrollFactor.set();
		healthBarBG.visible = false;
		healthBarBG.xAdd = -4;
		healthBarBG.yAdd = -4;
		healthBarBG.sprTracker = healthBar;
		st.add(healthBarBG);

		st.add(healthBar);

		healthBarOverlay = new FlxTiledSprite(Paths.image('healthBarOverlay'), Std.int(healthBar.bg.width), Std.int(healthBar.bg.height));
		healthBarOverlay.y = healthBar.y;
		healthBarOverlay.scrollFactor.set();
		healthBarOverlay.visible = (!ClientPrefs.data.hideHud && ClientPrefs.data.healthBarOverlay && !ClientPrefs.data.oldHealthBar && !ClientPrefs.data.newHealthBar);
		healthBarOverlay.color = FlxColor.BLACK;
		healthBarOverlay.blend = MULTIPLY;
		healthBarOverlay.x = healthBar.x;
		healthBarOverlay.alpha = ClientPrefs.data.healthBarAlpha;
		healthBarOverlay.antialiasing = ClientPrefs.data.antialiasing;
		st.add(healthBarOverlay);
		if (ClientPrefs.data.downScroll && !st.isPhigrosStyle) healthBarOverlay.y = healthBar.y;
		if (ClientPrefs.data.oldHealthBar || ClientPrefs.data.newHealthBar) healthBarOverlay.visible = false;

		iconP1 = new HealthIcon(st.boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		st.add(iconP1);

		iconP2 = new HealthIcon(st.dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		st.add(iconP2);

		var hudScoreOff:Array<Float> = st.hudGetOffset('score');
		var scoreY:Float = (ClientPrefs.data.downScroll ? 5 : defaultHpY + 55);
		scoreTxt = new FlxText(hudScoreOff[0], scoreY + hudScoreOff[1], FlxG.width, "", 20);
		if (ClientPrefs.data.scoreTxtFont == "Bahnschrift")
		{
			scoreTxt.setFormat(Paths.font("bahnschrift.ttf"), 15, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			scoreTxt.borderSize = 1.25;
		}
		if (ClientPrefs.data.scoreTxtFont == "默认")
		{
			scoreTxt.setFormat(Paths.font("vcr.ttf"), 15, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			scoreTxt.borderSize = 1.25;
		}
		scoreTxt.scrollFactor.set();
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		st.add(scoreTxt);

		var hudWmOff:Array<Float> = st.hudGetOffset('watermark');
		songTxt = new FlxText(12 + hudWmOff[0], scoreY + hudWmOff[1], 0, "", 12);
		songTxt.setFormat(Paths.font("future.ttf"), 15, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		songTxt.scrollFactor.set();
		songTxt.borderSize = 1;
		songTxt.visible = (!ClientPrefs.data.hideHud && !ClientPrefs.data.hideWatermark);
		st.add(songTxt);
		songTxt.text = st.curSong + " (" + st.storyDifficultyText + ") " + "| 流星引擎 v" + Main.meVersion;

		botplayTxt = new FlxText(400, timeBar.y + 55, FlxG.width - 800, st.replayMode ? "REPLAY" : "AutoPlay", 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = st.cpuControlled || st.replayMode;
		st.add(botplayTxt);
		if (ClientPrefs.data.downScroll && !st.isPhigrosStyle) botplayTxt.y = timeBar.y - 78;

		// ---- 判定计数侧边栏（openfl TextField 直接渲染，支持部分着色；默认左侧中间） ----
		var jcOff:Array<Float> = st.hudGetOffset('judgementTxt');
		judgementField = new openfl.text.TextField();
		judgementField.multiline = true;
		judgementField.wordWrap = false;
		judgementField.selectable = false;
		judgementField.width = 260;
		judgementField.height = 220;
		judgementField.defaultTextFormat = new openfl.text.TextFormat('VCR OSD Mono', 16, 0xFFFFFFFF);
		judgementField.x = 10 + jcOff[0];
		judgementField.y = FlxG.height / 2 - 65 + jcOff[1];
		judgementField.visible = !ClientPrefs.data.hideHud && ClientPrefs.data.showJudgementCounter;
		FlxG.stage.addChild(judgementField);
		st.judgementField = judgementField;

		// ---- 相机归属 ----
		healthBar.cameras = [st.camHUD];
		healthBarBG.cameras = [st.camHUD];
		healthBarOverlay.cameras = [st.camHUD];
		timeBarOverlay.cameras = [st.camHUD];
		iconP1.cameras = [st.camHUD];
		iconP2.cameras = [st.camHUD];
		scoreTxt.cameras = [st.camHUD];
		songTxt.cameras = [st.camOther];
		botplayTxt.cameras = [st.camHUD];
		timeBar.cameras = [st.camHUD];
		timeBarBG.cameras = [st.camHUD];
		timeTxt.cameras = [st.camHUD];

		// 同步到 PlayState 公开字段（Lua/Hscript getProperty/setProperty 兼容）
		st.healthBar = healthBar;
		st.healthBarBG = healthBarBG;
		st.healthBarOverlay = healthBarOverlay;
		st.timeBar = timeBar;
		st.timeBarBG = timeBarBG;
		st.timeBarOverlay = timeBarOverlay;
		st.timeTxt = timeTxt;
		st.iconP1 = iconP1;
		st.iconP2 = iconP2;
		st.scoreTxt = scoreTxt;
		st.songTxt = songTxt;
		st.botplayTxt = botplayTxt;

		enforce();
	}

	// ==================== 每帧更新 ====================

	public function update(elapsed:Float):Void
	{
		// 图标角度回正（SB 图标跳动）
		if (ClientPrefs.data.sbIconBop)
		{
			var speed:Float = 1;
			if (iconP1.angle >= 0)
			{
				speed *= st.playbackRate;
				if (iconP1.angle != 0) iconP1.angle -= speed;
			}
			else if (iconP1.angle != 0) iconP1.angle += speed;

			if (iconP2.angle >= 0)
			{
				if (iconP2.angle != 0) iconP2.angle -= speed;
			}
			else if (iconP2.angle != 0) iconP2.angle += speed;
		}

		// botplay 标签呼吸
		if (botplayTxt != null && botplayTxt.visible)
		{
			st.botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * st.botplaySine) / 180);
		}

		// 图标跳动回缩
		if (ClientPrefs.data.keIconBop)
		{
			var keDecay:Float = Math.pow(0.5, elapsed * 60 * st.playbackRate);
			var keMultP1:Float = 1 + (iconP1.scale.x - 1) * keDecay;
			iconP1.scale.set(keMultP1, keMultP1);
			iconP1.updateHitbox();
			iconP1.origin.set(0, 0);
			var keMultP2:Float = 1 + (iconP2.scale.x - 1) * keDecay;
			iconP2.scale.set(keMultP2, keMultP2);
			iconP2.updateHitbox();
			iconP2.origin.set(0, 0);
		}
		else
		{
			var iconDecay:Float = FlxMath.bound(1 - (elapsed * 9 * st.playbackRate), 0, 1);
			var multP1:Float = FlxMath.lerp(1, iconP1.scale.x, iconDecay);
			iconP1.scale.set(multP1, multP1);
			iconP1.updateHitbox();
			var multP2:Float = FlxMath.lerp(1, iconP2.scale.x, iconDecay);
			iconP2.scale.set(multP2, multP2);
			iconP2.updateHitbox();
		}

		// 图标强绑定血量条：x 跟随 barCenter，y 跟随血量条
		var iconOffset:Int = 26;
		if (st.health > 2) st.health = 2;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0;
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0;

		// 血量阴影滚动：方向随推条方向（回血向左、掉血向右）
		var hpDelta:Float = healthBar.percent - lastHpPercent;
		if (hpDelta >= 0.01) healthOverlayDir = -1;
		else if (hpDelta <= -0.01) healthOverlayDir = 1;
		lastHpPercent = healthBar.percent;

		if (healthBarOverlay.visible)
			healthBarOverlay.scrollX += healthOverlayDir * 22 * elapsed;

		// 时间条阴影：固定向右滚动，透明度跟随时间条淡入
		if (timeBarOverlay != null && timeBarOverlay.visible)
		{
			timeBarOverlay.alpha = timeBar.alpha * 0.5;
			timeBarOverlay.scrollX += 22 * elapsed;
		}

		// 判定计数侧边栏
		updateJudgementTxt();

		// 可见性权威：每帧拉回设置值
		enforce();
	}

	function updateJudgementTxt():Void
	{
		if (judgementField == null) return;

		// 结算界面打开时隐藏 HUD 判定侧边栏（stage 级 TextField 不随 flixel 状态隐没，
		// 且与结算界面的判定统计重复）；关闭后由下方可见性逻辑自动恢复
		if (st != null && st.subState != null && Std.isOfType(st.subState, ResultsSubState))
		{
			judgementField.visible = false;
			return;
		}

		var mv:Int = 0, sick:Int = 0, good:Int = 0, bad:Int = 0, shit:Int = 0;
		if (st.ratingsData != null)
		{
			for (r in st.ratingsData)
			{
				switch (r.name)
				{
					case 'marvelous': mv = r.hits;
					case 'sick': sick = r.hits;
					case 'good': good = r.hits;
					case 'bad': bad = r.hits;
					case 'shit': shit = r.hits;
				}
			}
		}

		// 行内容（Marvelous 判定未开启时不包含 Marvelous 行，其余行紧凑排列）
		// 命中数按结算页口径钳制（与 clampGameplayTotals 同源），并同步显示总音符数
		var hitsDisp:Int = st.songHits;
		if (st.totalNotes > 0 && hitsDisp > st.totalNotes) hitsDisp = st.totalNotes;
		// 评级计数与 Combo 同源（density 累加），把批次去重噪声一并钳到命中数以内：
		// 从最高评级开始扣减超量，保证 Marvelous+…+Shit == Hits、Combo ≤ Hits
		var ratingSum:Int = mv + sick + good + bad + shit;
		if (hitsDisp > 0 && ratingSum > hitsDisp)
		{
			var excess:Int = ratingSum - hitsDisp;
			if (mv >= excess) mv -= excess;
			else { excess -= mv; mv = 0;
				if (sick >= excess) sick -= excess;
				else { excess -= sick; sick = 0;
					if (good >= excess) good -= excess;
					else { excess -= good; good = 0;
						if (bad >= excess) bad -= excess;
						else { excess -= bad; bad = 0; shit = Std.int(Math.max(0, shit - excess)); }
					}
				}
			}
		}
		var comboDisp:Int = st.combo;
		if (hitsDisp > 0 && comboDisp > hitsDisp) comboDisp = hitsDisp;
		var buf = new StringBuf();
		buf.add('Hits: ' + hitsDisp + (st.totalNotes > 0 ? ' / ' + st.totalNotes : ''));
		buf.add('\nCombo: ' + comboDisp);
		if (ClientPrefs.data.marvelousJudgement) buf.add('\nMarvelous: ' + mv);
		buf.add('\nSick: ' + sick);
		buf.add('\nGood: ' + good);
		buf.add('\nBad: ' + bad);
		buf.add('\nShit: ' + shit);
		buf.add('\nMisses: ' + st.songMisses);
		var txt:String = buf.toString();

		var jcOff:Array<Float> = st.hudGetOffset('judgementTxt');
		judgementField.x = 10 + jcOff[0];
		judgementField.y = FlxG.height / 2 - 65 + jcOff[1];
		judgementField.visible = !ClientPrefs.data.hideHud && ClientPrefs.data.showJudgementCounter;
		if (!judgementField.visible) return;

		judgementField.text = txt;

		// 行着色：Hits / Combo 青色，Misses 浅红（openfl TextField 原生范围着色）
		var cyan:openfl.text.TextFormat = new openfl.text.TextFormat('VCR OSD Mono', 16, 0xFF00FFFF);
		var lightRed:openfl.text.TextFormat = new openfl.text.TextFormat('VCR OSD Mono', 16, 0xFFFF7777);

		var line2:Int = txt.indexOf('\n');
		if (line2 > 0) judgementField.setTextFormat(cyan, 0, line2); // Hits
		var line3:Int = txt.indexOf('\n', line2 + 1);
		if (line3 > line2) judgementField.setTextFormat(cyan, line2 + 1, line3); // Combo
		var lastStart:Int = txt.lastIndexOf('\n') + 1;
		if (lastStart > 0 && lastStart < txt.length)
			judgementField.setTextFormat(lightRed, lastStart, txt.length); // Misses
	}

	// ==================== 可见性权威 ====================

	/**
	 * 每帧把 HUD 元素可见性强制恢复为设置值。
	 * 无论谁（Lua/Hscript/Mod/遗留代码）把 healthBar/图标/分数/歌曲名/标签
	 * 直接改成不可见，下一帧都会被拉回 —— 根治“游玩中 UI 突然消失”。
	 */
	public function enforce():Void
	{
		if (ClientPrefs.data.hideHud != ClientPrefs.savedHideHud)
			ClientPrefs.data.hideHud = ClientPrefs.savedHideHud;

		var hide:Bool = ClientPrefs.data.hideHud;
		var minimal:Bool = ClientPrefs.data.minimalHealthBar;
		if (healthBar != null)
		{
			healthBar.visible = !hide;
			healthBar.setNewStyle(ClientPrefs.data.newHealthBar);
		}
		if (healthBarOverlay != null) healthBarOverlay.visible = !hide && ClientPrefs.data.healthBarOverlay && !ClientPrefs.data.oldHealthBar && !ClientPrefs.data.newHealthBar && !minimal;
		if (iconP1 != null) iconP1.visible = !hide && !minimal;
		if (iconP2 != null) iconP2.visible = !hide && !minimal;
		if (scoreTxt != null) scoreTxt.visible = !hide;
		if (timeBarOverlay != null) timeBarOverlay.visible = timeBar != null && timeBar.visible && !hide;
		if (botplayTxt != null) botplayTxt.visible = (st.cpuControlled || st.replayMode) && !st.endingSong;
		if (songTxt != null) songTxt.visible = !hide && !ClientPrefs.data.hideWatermark;
		if (judgementField != null) judgementField.visible = !hide && ClientPrefs.data.showJudgementCounter;

		// 极简血条：血条移到 Score 栏位置，scoreTxt 垂直居中嵌入血条（无图标、无阴影）
		if (minimal && healthBar != null && scoreTxt != null)
		{
			// downScroll 时 Score 栏置顶，极简血条跟随置顶
			var scoreY:Float = (ClientPrefs.data.downScroll ? 5 : FlxG.height * 0.89 + 55) + st.hudGetOffset('score')[1];
			healthBar.y = scoreY;
			healthBar.screenCenter(X);
			healthBar.x += st.hudGetOffset('healthBar')[0];
			scoreTxt.y = healthBar.y + (healthBar.height - scoreTxt.height) / 2;
		}
	}

	// ==================== 其他 ====================

	public function reloadHealthBarColors():Void
	{
		healthBar.setColors(FlxColor.fromRGB(st.dad.healthColorArray[0], st.dad.healthColorArray[1], st.dad.healthColorArray[2]),
			FlxColor.fromRGB(st.boyfriend.healthColorArray[0], st.boyfriend.healthColorArray[1], st.boyfriend.healthColorArray[2]));
	}

	/** 快速重开/回溯完成后：时间条与时间文字复位（渐入归零） */
	public function resetForRestart():Void
	{
		st.songPercent = 0;
		if (timeTxt != null && ClientPrefs.data.timeBarType != '歌曲名称')
		{
			var restartSeconds:Int = 0;
			if (ClientPrefs.data.timeBarType == '剩余时间')
				restartSeconds = Std.int(Math.max(0, st.songLength) / 1000);
			timeTxt.text = FlxStringUtil.formatTime(restartSeconds, false);
		}
		timeBar.visible = st.updateTime;
		timeTxt.visible = st.updateTime;
		timeBar.alpha = 0;
		timeTxt.alpha = 0;
	}
}
