package states;
import backend.Lang;

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
import backend.CameraHudDomain;
import backend.EventDomain;
import backend.IconBop;
import backend.NoteChartDomain;
import backend.PopupAnim;
import backend.Song;
import backend.Section;
import backend.PackedChart;
import backend.PerfProbe;
import backend.Rating;
import backend.Replay;
import backend.CrashHandler;
import backend.TurboDensity;
import backend.TurboDensity.TurboZone;

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
import openfl.utils.AssetType;
import openfl.events.Event;
import openfl.events.FocusEvent;
import openfl.events.KeyboardEvent;
import openfl.Lib;
import tjson.TJSON as Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;

import substates.PauseSubState;
import substates.GameOverTheme;
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

#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
import scripting.ScriptLifecycleEvent;
import scripting.ScriptNoteEvent;
import scripting.ScriptRatingEvent;
import scripting.Scripting;
#end

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
import backend.ReplayDomain;
import backend.InputDomain;
import backend.HostDomain;
#end

typedef PreGenResult = {
	notes:Array<CastNote>,
	noteTypes:Array<String>,
	totalNotes:Int,
	botLaneCounts:Array<Int>,
	botplayLanes:Array<Array<Float>> // 与 botLaneCounts 同口径的自动游玩计划（null=无需计划）
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

	// 联机模式（Meteoric Online）已整体移除：原 isOnlineMode / onlineIsHost /
	// onlineMyNick / onlineOppNick / onlineHoldCountdown / onlineHostChar / onlineClientChar
	// 及其对手 HUD（addOnlineHUD）全部删除，主菜单「联机」入口保留显示但不可点。

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

	/**
	 * 本局**峰值** NPS（最近 1 秒内命中最多的那一秒）。
	 *
	 * `npsDisplay` 是滚动 1 秒窗口的当前值（`_npsTimer` 每满 1 秒把 `_npsCount`
	 * 滚进去并清零，见 `backend/HostDomain.hx`），它只反映「此刻」的读谱速度 ——
	 * 遇到间奏或长条就会掉回 0，看不出玩家真实的爆发力。
	 * 本字段记历史峰值，结算页与 Score 栏的 `{maxnps}` 槽用它。
	 *
	 * 与 `npsDisplay` 同一口径：不含长条尾击，按 `density` 计（挤在一起的一簇算多个），
	 * 所以它就是「那一秒里你敲了多少下」。
	 */
	public var maxNpsDisplay:Int = 0;

	var _npsCount:Int = 0;
	var _npsTimer:Float = 0;

	// 延迟 GC（Meteoric Fix 续）：进曲 0.5s 后触发一次 System.gc()，回收被剥离的
	// 谱面 DOM/解析暂存（开局 876→660MB 的 216MB 差值来源）。
	// 40 帧回归已定位为 CastNote 代理的 Dynamic 分发（已改静态类型），GC 本身无罪；
	// 若本构建 FPS 仍掉，下一轮把 GC 移到暂停/曲终或彻底移除。
	var _deferredGC:Bool = false;
	var _deferredGCTime:Float = 0;

	// ===== 每帧脚本广播值缓存（HostDomain.update 的 scriptSetProps 值去重用） =====
	// 六个引擎值没变就不重复进脚本引擎；任何脚本数组变化（加载/中途 loadScript）
	// 时 scriptEpoch 自增 → 下一帧全量重推一次，新脚本/onCreate 能读到全部初值。
	// 字段只服务这条路径，随实例销毁一并失效（快开 restart 不销毁实例 → 缓存继续成立）。
	public var scriptEpoch:Int = 0;
	var _ssCDecStep:Float = 0;
	var _ssCDecBeat:Float = 0;
	var _ssHealth:Float = 0;
	var _ssEnding:Bool = false;
	var _ssCurBeat:Int = 0;
	var _ssCamForced:Bool = false;
	var _ssReady:Bool = false;
	var _ssEpoch:Int = -1;

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

	// 【性能】脚本调用默认参数复用：每帧 callOnScripts/setOnScripts 会走到这里，
	// 原来每次都 new [] / [Function_Continue]（空脚本时纯浪费）；两数组只读共享安全
	static var _noExclusions:Array<String> = [];
	static var _noExcludeValues:Array<Dynamic> = [psychlua.FunkinLua.Function_Continue];
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel";

	/** 当前歌曲谱面（= 全局歌曲数据总线）。
	 *  ⚠ **所有权契约（引擎源码内）**：唯一写入入口是下面的 `setSong()`；除本类方法体外，
	 *  任何引擎文件都不得再对 `SONG` 直接赋值。
	 *  收敛前：4 个文件、11 处直接赋值横跨「加载器 / 谱面编辑器 / 暂停重开换难度 / 本类缓存恢复」，
	 *  任何一次改动都无法推理"此刻的 SONG 是谁装的"。
	 *
	 *  ⚠ **契约范围 = 引擎源码**：字段保持 `public`。脚本侧可写路径确实存在 ——
	 *  HScript 侧 `HScript.hx:94` 的 `set('PlayState', PlayState)` 让 `PlayState.SONG = x` 在脚本里语法有效；
	 *  Lua 侧走 `setPropertyFromClass('PlayState','SONG',…)` 反射。
	 *  **但本仓库语料内未见任何写 SONG 的脚本实例**（这一点与 `Conductor.songPosition` 不同，后者有 2 处实例）——
	 *  故"脚本会写 SONG"属**结构性成立、未被实例佐证**。无论是否被使用，**不得**为让"唯一写点"好看而私有化
	 *  （会破坏 mod 兼容）。脚本侧写入不受本契约约束，也不被本契约覆盖。 */
	public static var SONG:SwagSong = null;

	/** 装载/替换当前歌曲谱面（引擎内唯一写点）。
	 *  调用者角色：加载器（装载谱面）、谱面编辑器（开关歌曲/自动存档恢复/换曲）、
	 *  暂停重开（换难度重新解析）、本类自身（缓存命中后恢复完整 DOM）。
	 *  **不加 `inline`**：本方法不在热路径（11 处调用全发生在装载/换曲/重开/缓存恢复），
	 *  保持普通静态方法可确保 hxcpp 方法表与脚本侧 `callMethodFromClass('PlayState','setSong')` 都真实存在
	 *  （`inline` 目标不保证生成物理方法体，属未验证风险）。
	 *  `@:keep` 保证 `-dce full` 下不被裁剪。引擎内调用点仅多一次静态调用，无实质开销。 */
	@:keep public static function setSong(song:SwagSong):Void
	{
		SONG = song;
	}
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

	// SONG 逐音符 DOM 是否已被剥离（releaseSongChartDom 把每 section 的 sectionNotes 置空数组）。
	// 按真实数据判定：任一 section 仍有音符数组/内容 → 未剥离；全部为空数组 → 已剥离。
	static function isSongChartStripped(s:SwagSong):Bool return NoteChartDomain.isSongChartStripped(s);

	// 加载方（LoadingState/PauseSubState）替换 SONG 时必须先登记身份，剥离才有恢复依据
	public static function registerChartSource(chartJson:String, folder:String, songName:String):Void
	{
		chartJsonInput = chartJson;
		chartFolder = folder;
		chartSongName = songName;
		chartDataStripped = false;
	}

	// SONG 的逐音符数组被剥离后，任何需要完整谱面的入口（重开/回溯/编谱）先从此恢复
	static function reloadChartSourceIfNeeded():Void NoteChartDomain.reloadChartSourceIfNeeded();

	// create 尾 / 重开收尾共用：剥离 SONG 逐音符 DOM + 淘汰大谱面缓存副本
	// （Flocc 级：两份 DOM 全释放后，游玩稳态只剩 CastNote + 音频 + 基线，≈400MB）
	static function releaseSongChartDom():Void NoteChartDomain.releaseSongChartDom();

	public var spawnTime:Float = 2000;

	// ===== H-Slice 移植：音符生成游标 / 快速跳谱 / 挤压音符展开 =====
	public var currentSpawnId:Int = 0;          // unspawnNotes 生成游标（不再 indexOf/splice，O(n²)→O(n)）
	// 【性能】已消费 CastNote 引用释放游标（配合 releaseConsumedNotes，摊还 O(1)/音符）
	public var lastSpawnGc:Int = 0;
	var lastNoteSpawnPos:Float = -9999;         // 上次 noteSpawn 时的歌曲位置（跳变检测用）
	static inline var VISUAL_BUDGET:Int = 1800; // 场上视觉精灵预算（采样展开的全局上限）
	static inline var JUMP_DETECT_MS:Float = 1000; // 单帧前进超过该值视为"真实跳时间"，才允许 bulkSkip
	// 超密集谱面自动降级阈值：原始音符总数 ≥ 该值（如 Obsolescence-spam 11,829,376 颗）时，
	// 无视 skipGhostNotes 强制开启堆叠合并（ghostDensity 仍尊重用户设置）。
	// 已验证的 2.26M 音符级上限谱面不触发，行为与旧版完全一致。
	static inline var DENSE_FORCE_MERGE:Int = 4000000;
	// 【500 帧补丁】超密集谱（raw≥DENSE_FORCE_MERGE）自动启用高性能渲染管线：
	//   densePerfMode  → Note 走 perfMode 同款 quad 合批 + 强制 PE 0.6.3 原生贴图（NOTE_assets-063）+ 关 RGB、
	//                    不叠平涂色（烘焙色×平涂色双重着色会出现用户反馈的"阴间"配色）
	//   perfLimitNotes → 场上上限生效值（只透传用户值；density 加权，绝不自动抬升）
	//   perfHideOverlapped → 重叠隐藏生效值（只透传用户值；曾自动 10px，用户实测隐藏真实箭头/长条头，已撤销）
	public static var densePerfMode:Bool = false;
	public static var spamNotes:Array<SpamNoteData> = []; // 运行时展开的挤压音符队列
	// 重叠隐藏（hideOverlapped）：每轨道上一可见音符的间距与 sus 状态
	var laneLDist:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
	var laneSusPrev:Array<Bool> = [false, false, false, false, false, false, false, false];
	// 【500 帧补丁】实际生效的场上上限 / 重叠隐藏间距（只透传用户值，不自动修改、不写存档）
	var perfLimitNotes:Int = 0;
	var perfHideOverlapped:Float = 0;
	// 【密集对象硬上限】仅 densePerfMode 生效（用户已拍板）：战场上精灵对象数的硬上限。
	// 与 perfLimitNotes 无关——后者走 countLiving() 的 density 加权计数（一簇可达数百，
	// 直接用作对象上限会破坏判定）；这里按 NoteGroup.aliveObjectCount 的真实精灵数计数。
	static inline var DENSE_OBJ_CAP:Int = 800;
	// 达上限时延迟进场窗口：距判定线仍 > 该值的箭头先不生成（不消失、可判定、可打，
	// 只是进场更贴线），窗口内（快到线）即使超限也放行，保证判定零影响。
	// 取 60ms=自动游玩击杀窗（6ms）的 10 倍：延迟进场必然早于排期命中弹出，无竞态；
	// 同时把"超限放行"的溢出控制在 ~70 颗（而非 200ms 时的 ~240 颗），
	// 使实际场上稳定在 DENSE_OBJ_CAP+~70，逼近用户拍板的 800 预期。
	static inline var DENSE_OBJ_LATE_MS:Float = 60;
	var perfObjCap:Int = 0;
	// 【CrashHandler 落盘去重】stage 标记每曲只记一次（首次生成/首次命中）：
	// noteSpawn:start 原条件 currentSpawnId==0 在空段每帧成立 → 每帧 File.saveContent
	// （实测空段 1000 帧 → 每秒 ~1000 次磁盘写，前 16 秒 1000→800 帧的直接来源）；
	// popUpScore:start 原实现每命中落盘一次（密集团灭每秒数千次）。两处均按
	// CrashHandler.mark 注释意图（"首次命中约 10 次/曲"）收敛为每曲一次。
	var _stageMarkSpawn:Bool = false;
	var _stageMarkPop:Bool = false;
	// 【密集谱·安静命中档】RecalculateRating 节流时间戳（密集自动游玩每 250ms 结算一次评级/分数）
	var _lastRatingRecalc:Float = -999;
	// 【视觉/性能】密集谱自动游玩溅射节流：每轨最近的溅射时间（ms），250ms 内不再触发
	var lastSplashLane:Array<Float> = [-99999, -99999, -99999, -99999];

	public var vocals:FlxSound;
	public var opponentVocals:FlxSound; //Split vocals：对手专属人声（Voices-Opponent.ogg）
	public var inst:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:NoteGroup;
	// 安卓走"直建 Note 对象"最稳定管线（8月17 实测可用）；桌面走 CastNote 轻量管线
		#if false
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
	// 血条溢出图标飞出的“显示级”血量百分比（100~1000）：由本帧未钳制血量（音符数量×density 驱动的
	// 回血）换算，爆发后快速回落 100；仅供 {health} 显示与图标飞出距离缩放，不改变真实血量上限
	public var healthDisplayPct:Float = 100;
	// 本帧堆叠命中（density≥2）上报的显示爆发%（goodNoteHit 写入，GameHUD.update 结算后清零）
	public var pendingFlySpikePct:Float = 0;
	public var combo:Int = 0;
	// KE 结算界面：本局最高连击（命中后取峰值；Miss 重置 combo 不影响该值）
	public var maxCombo:haxe.Int64 = 0;

	// PF 移植：全 SICK/Marvelous（零失误、无低评）时 Combo 文字使用金色贴图
	public var allSicks:Bool = true;

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

	// 联机对局运行时状态（onlineOpp* / onlineMyStats / onlineFinished /
	// onlineTimeSyncTimer / onlineWaitTimer）已随联机整体移除。
	public var onlineWaitingResults:Bool = false;
	public var onlineRemoteResume:Bool = false; // 远程 RESUME 恢复时不再回发 RESUME

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

	// ===== 【Turbo·数据级批量结算】移植自 Seiun 最新版 fastSkipPastNotes =====
	// 聚合区（TurboDensity.buildZones）：连续 ≥4000NPS 且无长条的 tap 区间，区内走
	// 真实 Note 物化 + 对象上限（视觉完整）；区外 + 过载时，视距内半带的音符**不建 Sprite
	// 直接数据层结算**（计分/命中/血量按 density 加权，判定恒为满分），物化预算集中到外半带。
	var _bulkDrainedLast:Int = 0;      // 上一帧数据级结算条数（≥128 触发 30 帧过载滞回）
	var _overloadFrames:Int = 0;       // 过载滞回帧数（掉帧自动追赶；正常自动清零）
	var _settleAnimDone:Array<Bool> = [false, false, false, false]; // 结算 strum 高亮每帧每轨一次
	var turboZones:Array<TurboZone> = []; // dense 谱聚合区（空 = 不启用）
	var turboZoneCursor:Int = 0;

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
	/**
	 * 镜头缓动强度（每秒增益率）。
	 *
	 * 公式保持原引擎的形状：`followLerp = elapsed * SEC / (FlxG.updateFramerate / 60)`，
	 * 分母把「真实经过时间」折算成「60fps 等效帧数」，因此**帧率无关**
	 * （60 / 120 / 480 / 1000 / 4000 / 12000 fps 收敛时间实测一致，偏差 <10%）。
	 * 唯一改动是 SEC：原为写死的 `2.4`（≈1.22s 才走完 95%，观感上接近瞬移），
	 * 现由设置档位提供，见 `ClientPrefs.camSmoothPresets`。
	 *
	 * ⚠ 分母**必须**保留 `FlxG.updateFramerate`（「无上限」档 = 100000 哨兵）：
	 * 它使 `followLerp` 恒落在 1e-5 ~ 1e-7 量级，安全低于 flixel 的硬阈值
	 *   `if (followLerp >= 60 / FlxG.updateFramerate) scroll.copyFrom(_scrollTarget); // 无缓动`
	 * （阈值 = 60/100000 = 0.0006）。若把分母改成写死的 60，60fps 下 followLerp 会升到
	 * 1e-3 量级而**越过阈值**，退回「无缓动」瞬移——这一处改不得。
	 */
	private function cameraSmoothSpeed():Float
	{
		return CameraHudDomain.cameraSmoothSpeed(this);
	}


	public var songScore:haxe.Int64 = 0;
	public var songHits:haxe.Int64 = 0;
	public var songMisses:haxe.Int64 = 0;
	public var usedAutoplay:Bool = false;   // 本局是否用过自动游玩（用于判断成绩是否有效）
	public var destroyedNotes:Int = 0;        // 销毁模式：音符到判定线即销毁的累计数（含长条段/堆叠 density）
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
	// scoreTxt 已应用的 setFormat 参数签名（与 CameraHudDomain.updateScore 配合，避免每次重复 setFormat）
	var _scoreTxtFmtKey:String = '';

	public static var campaignScore:haxe.Int64 = 0;
	public static var campaignMisses:haxe.Int64 = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
		public var songLength:Float = 0;
	// 谱面无可用音频（song/目录名不匹配或文件缺失）时置真：songLength 按谱面末尾兜底，
	// update 中按歌曲位置触发 finishSong（空音频的 music.onComplete 永不触发 → 0:00 卡结算）
	public var silentChartAudio:Bool = false;
	// 谱面末尾时间（ms）：generateChartNotes 生成期记录（最后音符 strumTime+holdLength+收尾余量），
	// startSong 用它兜底 songLength —— 音频缺失/流式 length=0 时歌曲仍按谱面走完并结算
	public var chartEndTimeMs:Float = 0;
	// finishSong 防重入（哑谱自动结算与空音频 onComplete 可能先后双触发；noteOffset 延迟窗口内
	// 每帧自动结算也会重复排队 finishTimer → 双 endSong/双转场）
	public var finishingSong:Bool = false;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

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
		trace('[PLAY create] ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');
		// JS Engine 移植：GC 开关（true=允许 GC=系统默认；false=关闭 GC 消除尖峰，内存可能上升）
		#if cpp
		cpp.vm.Gc.enable(ClientPrefs.data.enableGC);
		#end

		// 上一局结束时 SONG 的逐音符数组可能已被剥离：先恢复完整谱面，
		// 下面的回放指纹/生成逻辑都依赖完整 DOM
		reloadChartSourceIfNeeded();
		trace('[PLAY create] reloadChart ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		//trace('Playback Rate: ' + playbackRate);
		// 进曲目即丢弃上一局的运行时音符图集缓存：其 FlxGraphic 随上次退出被内存清理销毁，
		// 跨曲目复用会拿到 bitmap=null 的图集导致绘制崩溃（FlxDrawQuadsItem Null Object Reference）
		objects.Note.clearRuntimeAtlasCache();
		Paths.clearStoredMemory();
		trace('[PLAY create] clearMem ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		ClientPrefs.resetHideHud(); // 每次进入对局都恢复用户真实的 hideHud，防止 Mod 残留

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');
		fullComboFunction = fullComboUpdate;

		// ===== Extra Keys：本曲键数真源（SONG.keys，缺省 4 = 完全旧行为）=====
		ExtraKeys.setSongKeys(SONG != null ? SONG.keys : 4);
		keysArray = ExtraKeys.actionNames();
		#if meteoric_debug
		trace('[XK2] create song=' + (SONG != null ? SONG.song : 'null')
			+ ' rawKeys=' + (SONG != null ? Std.string(Reflect.field(SONG, 'keys')) : 'null')
			+ ' songKeys=' + ExtraKeys.songKeys + ' gap=' + ExtraKeys.laneGap
			+ ' width=' + FlxG.width + ' actions=' + keysArray.length);
		#end
		// per-lane 运行时状态按键数定长（字段初始化器是 4K 默认值）
		lastSplashLane = ExtraKeys.farPastLanes();
		botBatchAnimDone = ExtraKeys.falseLanes();
		botBatchSplashDone = ExtraKeys.falseLanes();
		_settleAnimDone = ExtraKeys.falseLanes();

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
				replayHeld = ExtraKeys.falseLanes();
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
			setSong(Song.loadFromJson('tutorial'));

		// 游玩期会剥离 SONG.notes 逐音符数组（省内存）；回放指纹必须在剥离前记录，
		// 结算写档（endSong）直接复用此值，不再重扫 sectionNotes
		recordedChartFingerprint = Replay.chartFingerprint(SONG);

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		storyDifficultyText = Difficulty.getString();

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if(SONG.stage == null || SONG.stage.length < 1) {
			SONG.stage = StageData.vanillaSongStage(songName);
		}
		curStage = SONG.stage;
		// JS Engine 移植：只显示 HUD（charsAndBG）——保留真实 stage 数据（UI/像素/相机/缩放不变），
		// 仅跳过舞台实例化与舞台脚本，角色组整组不可见（GPU 不再绘制角色/舞台/雨滤镜等）
		// TuoboLoad=2（极简）复用这条既有通路：不构造舞台、不构造角色、不加载它们的图集，
		// 进曲只剩判定线/音符/HUD。效果与 hudOnly 一致，但由极速加载开关驱动。
		var showBgChars:Bool = !ClientPrefs.data.hudOnly && ClientPrefs.tuoboLoadLevel() < 2; // hudOnly=false=完整画面（默认）

		var stageData:StageFile = StageData.getStageFile(curStage);
		if(stageData == null) { //Stage couldn't be found, create a dummy stage for preventing a crash
			stageData = StageData.dummy();
		}
		trace('[PLAY create] stageFile ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

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

		PerfProbe.mark('stage: begin ' + curStage);
		trace('[Stage] create stage: ' + curStage + ' | replayMode=' + replayMode + ' | isPixelStage=' + isPixelStage);

		if (showBgChars)
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
			default:
		}
		PerfProbe.mark('stage: constructed');
		trace('[PLAY create] stageDone ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

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

		trace('[PLAY create] globalScripts ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		// TuoboLoad=2（极简）：跳过 gf 构造。
		// 为什么必须单独处理 gf：showBgChars 只挡住了**舞台**构造
		//（`if (showBgChars) switch(curStage)`），角色构造在本 if 之外**无条件执行**——
		// 所以 hudOnly 只是"隐藏不显示"，角色图集照样解码+上传，一毫秒都省不下。
		// 实测：gf 的 GF_assets.png（8000×6000→192MB 纹理）单项吃掉 create 的 601ms，
		// 而 gf 的全部下游引用（camPos 偏移 / 跳舞 / 复位，见 892/900/1313/2674）
		// 都已有 `gf != null` 判断，跳过是安全的。
		// dad / boyfriend 不跳：HUD 依赖它们的 healthIcon / healthColorArray
		//（3331/3343/3438/3772），且两者合计仅 ~290ms，不是主要矛盾。
		if (!stageData.hide_girlfriend && ClientPrefs.tuoboLoadLevel() < 2)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
		gf = new Character(0, 0, SONG.gfVersion);

			startCharacterPos(gf);
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
			gfMap.set(SONG.gfVersion, gf); // 快速重开恢复默认角色用
			startCharacterScripts(gf.curCharacter);
			trace('[PLAY create] gfDone ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');
		}

		// 联机角色选择：本端映射（我=BF，对方=Dad）——双端均为标准单机布局：
		// 自己（右侧 BF 位）唱自己选的半边，对方（左侧 Dad 位）唱对方选的半边。
		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);
		dadMap.set(SONG.player2, dad); // 快速重开恢复默认角色用
		startCharacterScripts(dad.curCharacter);
		trace('[PLAY create] dadDone ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		boyfriendMap.set(SONG.player1, boyfriend); // 快速重开恢复默认角色用
		startCharacterScripts(boyfriend.curCharacter);
		trace('[PLAY create] bfDone ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		// JS Engine 移植：只显示 HUD——角色组整组不可见（含子级角色，渲染裁剪在组层完成；
		// 角色对象保留，脚本/血条颜色/相机跟随不受影响）
		if (!showBgChars)
		{
			gfGroup.visible = false;
			dadGroup.visible = false;
			boyfriendGroup.visible = false;
		}

		// 暴露角色/摄像机引用给脚本（Psych 0.7.3 setSpecialObject 等价物；必须在 stage 脚本加载前设置）
		setOnScripts('dad', dad);
		setOnScripts('boyfriend', boyfriend);
		setOnScripts('gf', gf);
		setOnScripts('camGame', camGame);

		// Meteoric 资源同名脚本：角色（scripting/characters/<curCharacter>.hx）。
		// 必须在 dad/boyfriend/gf 字段赋值后加载，脚本的 onCreate 才能拿到完整引用。
		#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
		scripting.ResourceScripts.loadCharacters(this);
		#end

		// STAGE SCRIPTS（在角色创建后加载，使 onCreate 可访问 dad/boyfriend/gf）
		// JS Engine 移植：只显示 HUD 时跳过舞台脚本（舞台已不渲染，脚本多为视觉/相机效果）
		if (showBgChars)
		{
		#if LUA_ALLOWED
			startLuasNamed('stages/' + curStage + '.lua');
		#end

		#if HSCRIPT_ALLOWED
			startHScriptsNamed('stages/' + curStage + '.hx');
		#end

		#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
			scripting.ResourceScripts.loadStage(this, curStage);
		#end
		}

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

		Conductor.setPosition(-5000);

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
		trace('[PLAY create] generateSong ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		// ===== 联机真双人：客户端镜像（自己唱 player2/Dad 半边）=====
		// 双端屏幕均为标准单机布局：自己（右侧 BF 位）= 自己选的半边，对方（左侧 Dad 位）= 对方选的半边。
		// 客户端实际打的是谱面 player2（Dad）半边：翻转 mustPress 后它跟随自己的右侧判定条（playerStrums），
		// player1（BF）半边则成为对侧、显示在左侧判定条（opponentStrums）——箭头位置不变，只有谱面内容互换。

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
		PerfProbe.mark('before createPost');
		stagesFunc(function(stage:BaseStage) stage.createPost());
		PerfProbe.mark('after createPost');
		trace('[PLAY create] createPost ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		moveCameraSection();
		PerfProbe.mark('after moveCameraSection');

		// ===== HUD/UI 子系统（GameHUD）：时间条/血条/图标/分数/歌曲名/标签的创建、
		// 每帧更新与可见性权威全部集中于此，PlayState 只保留玩法逻辑 =====
		hud = new GameHUD(this);
		hud.build();
		PerfProbe.mark('after GameHUD.build');
		trace('[PLAY create] hudBuild ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');
		// 小图标跳动：清空上一局的每帧状态（hop 位移 / squash 相位 / 交替奇偶 / 上一档位），
		// 必须在 hud.build() 之后、第一次 GameHUD.update 之前 —— 否则重进曲目会带着旧位移起跳。
		IconBop.reset();
		Lib.application.window.title = Lang.tOr('win.playing', "FNF':Meteoric Engine - Playing: ") + curSong + (replayMode ? Lang.tOr('win.playingReplay', ' [回放]') : '');

		strumLineNotes.cameras = [camHUD];
		grpNoteSplashes.cameras = [camHUD];
		notes.cameras = [camHUD];

		// 联机对局：追加右侧对手按键条 + 对手信息面板

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

		// Meteoric 资源同名脚本：音符类型 / 事件（每个类型只加载一次；必须在数组清空前）。
		#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
		scripting.ResourceScripts.loadNoteTypesAndEvents(this, noteTypes, eventsPushed);
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

		// Meteoric 全曲 / 单曲脚本（scripting/songs/*.hx 与 scripting/songs/<歌曲名>/*.hx）。
		// 与上面 Psych 风格的 data/<歌曲名>/ 脚本是两条独立的线：目录不同，互不重复。
		#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
		if (!replayMode)
			scripting.SongScripts.load(this, songName, chartFolder);
		#end

		// 大纹理显存预提交 + CPU 副本释放（SeiunEngine GfxPolicy 移植）：
		// 把本局所有 ≥2048px 的大图集在这一刻推上显存并丢掉 CPU 副本 ——
		// 之后游玩中不再有任何纹理上传（消除进曲后头几秒的卡顿），CPU 内存立减一份。
		// 默认关闭（ClientPrefs.data.gfxCpuRelease=false）时是纯 no-op，零行为变化。
		backend.GfxPolicy.onPlayStateCreate(SONG != null && SONG.song != null ? SONG.song : 'unknown');
		backend.GfxPolicy.preloadWarm();

		// SeiunEngine 同款：create 末尾强制一次完整 GC + 堆压缩。
		// 加载期产生的巨量临时对象（谱面解析、帧构造）若不在这里收走，
		// 第一次游玩中的分配会连带触发一次大 GC → 明显卡顿。
		// 仅在功能开启时执行，且 GC 开关为 true 才动（尊重 enableGC=false 的用户）。
		#if cpp
		if (backend.GfxPolicy.enabledInline() && ClientPrefs.data.enableGC)
		{
			cpp.vm.Gc.run(true);
			cpp.vm.Gc.compact();
		}
		#end

		trace('[PLAY create] end ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');
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

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		#if mobile
		FlxG.stage.addEventListener(Event.DEACTIVATE, onStageDeactivate);
		FlxG.stage.addEventListener(Event.ACTIVATE, onStageActivate);
		FlxG.stage.addEventListener(FocusEvent.FOCUS_IN, onStageActivate);
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
	public function syncGameplaySettings():Void HostDomain.syncGameplaySettings(this);

	public function addTextToDebug(text:String, color:FlxColor) {
		HostDomain.addTextToDebug(this, text, color);
	}
	
	public function updateHUDVisibility() {
		CameraHudDomain.updateHUDVisibility(this);
	}

	/**
	 * HUD 权威校验：每帧把 HUD 元素可见性强制恢复为设置值。
	 * 无论谁（Lua/Hscript/Mod/遗留代码）把 healthBar/图标/分数直接改成不可见，
	 * 下一帧都会被拉回 —— 彻底解决“游玩中 UI 突然消失”（只剩箭头和时间条）问题。
	 */
	public function enforceHUD() CameraHudDomain.enforceHUD(this);

	public function reloadHealthBarColors() CameraHudDomain.reloadHealthBarColors(this);

	public function addCharacterToList(newCharacter:String, type:Int) HostDomain.addCharacterToList(this, newCharacter, type);

	function startCharacterScripts(name:String) HostDomain.startCharacterScripts(this, name);

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		return HostDomain.getLuaObject(this, tag, text);
	}

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		HostDomain.startCharacterPos(this, char, gfCheck);
	}

	public function startVideo(name:String, ?onComplete:Void->Void = null) HostDomain.startVideo(this, name, onComplete);

	function startAndEnd()
	{
		HostDomain.startAndEnd(this);
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

	function cacheCountdown() EventDomain.cacheCountdown(this);

	public function startCountdown()
	{
		trace('[PLAY startCountdown] called, skipCountdown=' + skipCountdown + ' startOnTime=' + startOnTime);
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
			CrashHandler.mark('countdown:arrows-done');
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
				// Extra Keys：兼容字段只有 X0..X3（Psych 0.7 遗留），lane ≥ 4 只暴露给脚本全局，
				// 不能 Reflect.setProperty 到不存在的实例字段（hxcpp 会炸）
				if (i < 4) {
					Reflect.setProperty(this, 'defaultPlayerStrumX' + i, playerStrums.members[i].x);
					Reflect.setProperty(this, 'defaultPlayerStrumY' + i, playerStrums.members[i].y);
				}
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				if (i < 4) {
					Reflect.setProperty(this, 'defaultOpponentStrumX' + i, opponentStrums.members[i].x);
					Reflect.setProperty(this, 'defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				}
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.setPosition(-Conductor.crochet * 5);
			CrashHandler.mark('countdown:timer-armed');
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
				if (!ClientPrefs.data.hudOnly && gf != null && tmr.loopsLeft % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith("sing") && !gf.stunned)
					gf.dance();
				if (!ClientPrefs.data.hudOnly && boyfriend != null && tmr.loopsLeft % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
					boyfriend.dance();
				if (!ClientPrefs.data.hudOnly && dad != null && tmr.loopsLeft % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
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

	public function clearNotesBefore(time:Float) NoteChartDomain.clearNotesBefore(this, time);

	public function updateScore(miss:Bool = false) CameraHudDomain.updateScore(this, miss);

	// 是否含 CJK 汉字（用于 scoreTxt 中文字体自动切换）
	function containsChinese(s:String):Bool
	{
		return HostDomain.containsChinese(this, s);
	}

	// Score 栏文本：用 ClientPrefs.scoreTxtFormat 自定义格式 + 变量替换
	// 可用变量：
	//   {score} 分数 | {misses} Miss数 | {rank} 评级 | {accuracy} 准度(纯数字，%自己加)
	//   {nps} 每秒音符数 | {fc} FC状态 | {combo} 连击 | {health} 血量百分比
	function buildScoreText():String return CameraHudDomain.buildScoreText(this);

	public function setSongTime(time:Float) HostDomain.setSongTime(this, time);

	public function startNextDialogue() EventDomain.startNextDialogue(this);

	public function skipDialogue() EventDomain.skipDialogue(this);

	function startSong():Void HostDomain.startSong(this);

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
			// 【Obsolescence-spam 关键修复】谱面目录名（chartFolder）与 JSON 的 song 字段
			// 不一致时（如 data/Obsolescence-spam/ 内 song="Obsolescence"），按 song 名找
			// 音频必然 MISSING → 空 Sound（length=0）→ songLength=0 → HUD 恒 0:00 且
			// music.onComplete 永不触发 → 卡结算。先按 song 名加载，空则回退 chartFolder
			// （与 Freeplay 试听/LoadingState 预加载路径一致：songs/<目录>/Inst.ogg）。
			var altFolder:String = chartFolder;
			var altReady:Bool = (altFolder != null && altFolder.length > 0
				&& Paths.formatToSongPath(songData.song) != altFolder);

			var vocalsLoaded:Bool = false;
			var oppVocalsLoaded:Bool = false;

			if (songData.needsVoices)
			{
				// Split vocals：Voices-Player/Voices-Opponent 存在才加载，否则回退旧版 Voices.ogg。
				// 不能用返回值判空（Paths.returnSound 找不到文件时返回空 Sound 而非 null）。
				var playerFile:String = (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile;
				if (Song.voicesFileExists(songData.song, playerFile))
				{
					vocals.loadEmbedded(Paths.voices(songData.song, playerFile));
					vocalsLoaded = true;
				}
				else if (Song.voicesFileExists(songData.song))
				{
					vocals.loadEmbedded(Paths.voices(songData.song));
					vocalsLoaded = true;
				}

				var oppFile:String = (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile;
				if (Song.voicesFileExists(songData.song, oppFile))
				{
					opponentVocals.loadEmbedded(Paths.voices(songData.song, oppFile));
					oppVocalsLoaded = true;
				}

				// 目录名兜底：song 字段与目录不一致时人声同样按目录找（同上修复）
				if (altReady)
				{
					if (!vocalsLoaded && Song.voicesFileExists(altFolder, playerFile))
					{
						vocals.loadEmbedded(Paths.voices(altFolder, playerFile));
						vocalsLoaded = true;
					}
					if (!vocalsLoaded && Song.voicesFileExists(altFolder))
					{
						vocals.loadEmbedded(Paths.voices(altFolder));
						vocalsLoaded = true;
					}
					if (!oppVocalsLoaded && Song.voicesFileExists(altFolder, oppFile))
					{
						opponentVocals.loadEmbedded(Paths.voices(altFolder, oppFile));
						oppVocalsLoaded = true;
					}
				}
			}

			vocals.pitch = playbackRate;
			opponentVocals.pitch = playbackRate;

			var instSound:Dynamic = Paths.inst(songData.song);
			if ((instSound == null || instSound.length <= 0) && altReady)
			{
				var altInst:Dynamic = Paths.inst(altFolder);
				if (altInst != null && altInst.length > 0)
				{
					instSound = altInst;
					trace('[Audio] song 名与谱面目录不一致，已改用目录音频：' + altFolder);
				}
			}
			// 仍无可用音频（chart-only 哑谱）：标记静音，startSong 按谱面末尾兜底 songLength，
			// update 按歌曲位置补触发 finishSong（空音频 onComplete 永不触发 → 0:00 卡结算）
			silentChartAudio = (instSound == null || instSound.length <= 0);
			inst = new FlxSound().loadEmbedded(instSound);
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
			silentChartAudio = true;
			#if android
			try { extension.androidtools.widget.Toast.makeText(Lang.tOr('play.audioLoadFailedToast', '音频加载失败，本局静音'), 0); } catch (e2:Dynamic) {}
			#end
		}
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);
		FlxG.sound.list.add(inst);
		trace('[PLAY create] audioLoaded ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');

		notes = new NoteGroup();
		add(notes);
		generateChartNotes(true);
		trace('[PLAY create] chartNotes ' + Std.int(haxe.Timer.stamp()*1000) + 'ms');
	}

	// 根据内存中的谱面数据生成音符与事件。
	// loadPhase=true 为首次加载：读取 events 文件并触发事件预加载回调（与原来行为一致）；
	// loadPhase=false 为快速重开：直接复用加载时缓存好的事件数据，不读盘、不重复触发脚本/舞台回调。
	// ===== 提前生成（LoadingState 空闲期构建整张谱面，create 时直接消费，大谱面省去 500ms+） =====
	public static var preGenNotes:Array<CastNote> = null;
	static var preGenNoteTypes:Array<String> = null;
	/** Turbo 聚合区预生成结果（preGenerateChart 后台算好，generateChartNotes 直接消费） */
	static var preGenTurboZones:Array<backend.TurboZone> = null;
	static var preGenTotalNotes:Int = 0;
	static var preGenBotLaneCounts:Array<Int> = null;
	static var preGenSong:String = null;

	// 供 LoadingState 预渲染消费：预生成收集好的 noteType 列表（null=未生成，由 Note 回退全谱扫描）
	public static function getPreGenNoteTypes():Array<String> return preGenNoteTypes;

	// 长条重构（Meteoric Fix 续）：段 chartSeq 基址 = 箭头总数。
	// 与旧分配 100% 一致（箭头 0..N-1，段 N..按谱面顺序），旧回放兼容。
	static var _segmentSeqBase:Int = 0;

	// 加载界面空闲期调用：构建整张谱面的音符对象（含长条段），返回是否成功。
	// 与 create 期生成完全同一套参数（stageUI / BPM / songSpeed / playbackRate），失败时回退创建期生成。
	public static function preGenerateChart():Bool
	{
		#if false
		return false; // 安卓：使用 create 期直建 Note 管线（8月17 实测可用），禁用预生成
		#end
		if (SONG == null) return false;
		var songPath:String = Paths.formatToSongPath(SONG.song);
		// 每次加载都重建：上一轮预生成一定已被 create 消费；残留数据直接覆盖，防止跨曲/跨难度误用
		preGenNotes = null;
		preGenSong = null;
		preGenTurboZones = null;

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
			// Meteoric Fix（Obsolescence-spam / 1180 万音符级）：直接在共享 SONG 上构建，
			// 不再整谱深拷贝。Song.copySong 会对每颗音符 note.copy()：11.8M 级谱面额外增加
			// ~1GB 峰值与上亿次小对象分配（加载期 OOM/GC 崩溃主因之一）。
			// buildChartNotes 对 song 只读；clearSections=false → 不清空 SONG.sectionNotes，
			// 共享数据保持完整（重解析/快速重开/回溯依赖它）；剥离仍由 create 尾 releaseSongChartDom 统一执行。
			CrashHandler.mark('PlayState.preGen:start');
			var res:PreGenResult = buildChartNotes(SONG, Note.getBotplayPlan(), false,
				{ songSpeed: songSpeed }, ClientPrefs.getGameplaySetting('songspeed'), false);
			CrashHandler.mark('PlayState.preGen:build-done');
			res.notes.sort(sortByTime);
			preGenNotes = res.notes;
			preGenNoteTypes = res.noteTypes;
			preGenTotalNotes = res.totalNotes;
			preGenBotLaneCounts = res.botLaneCounts;
			preGenSong = songPath;
			ok = true;
			// botplay 计划随预生成一次成型（绝对列号规则），取代 preRenderBotplay 的二次全谱扫描
			if (res.botplayLanes != null)
				Note.storeBotplayPlan(res.botplayLanes);
			// Turbo 聚合区预生成：chartFingerprint + buildZones 是 O(n) 全遍历，
			// 19.2 亿音符级谱面在主线程要 600ms+。这里用同一份 preGenNotes 在后台算好，
			// create 的 generateChartNotes 直接消费（见 preGenTurboZones）。
			preGenTurboZones = null;
			// 仅密集谱需要 turboZones（generateChartNotes 只在 densePerfMode 时消费）
			if (densePerfMode)
			try
			{
				var meta:Dynamic = {
					song: SONG.song,
					mod: (backend.Mods.currentModDirectory != null ? backend.Mods.currentModDirectory : ''),
					notes: preGenNotes != null ? preGenNotes.length : 0,
					fingerprint: backend.TurboDensity.chartFingerprint(preGenNotes)
				};
				var tPath:String = backend.TurboDensity.cachePath(SONG.song, meta.mod, preGenNotes);
				var tCached:Array<backend.TurboZone> = backend.TurboDensity.loadCache(tPath, meta);
				if (tCached != null)
					preGenTurboZones = tCached;
				else
				{
					preGenTurboZones = backend.TurboDensity.buildZones(preGenNotes);
					backend.TurboDensity.saveCache(tPath, preGenTurboZones, meta);
				}
			}
			catch (eTurbo:Dynamic)
			{
				preGenTurboZones = null; // 失败则 create 期回退原有 initTurboZones 逻辑
			}
			CrashHandler.mark('PlayState.preGen:done');
		}
		catch (e:Dynamic)
		{
			preGenNotes = null;
			preGenNoteTypes = null;      // 防残留上一曲类型（预渲染直接消费该字段）
			preGenTurboZones = null;
			preGenTotalNotes = 0;
			preGenBotLaneCounts = null;
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
		// ===== Extra Keys：本曲键数真源（布局/烘焙/预演都依赖它，必须最先写入）=====
		ExtraKeys.setSongKeys(ExtraKeys.resolveKeys(song != null ? song.keys : 4));
		var songKeys:Int = ExtraKeys.songKeys;
		// 平行数组代理（Meteoric Fix 续）：本函数是 CastNote 的唯一生产者入口，
		// 每曲构建前重置上一曲的全部槽位数据（旧对象随 unspawnNotes 丢弃）
		CastNote.resetPacked();
		var noteTypes:Array<String> = [];
		var totalNotes:Int = 0;
		var botLaneCounts:Array<Int> = botplayPlan != null ? ExtraKeys.zeroLanes() : null;
		// botplay 计划并入本遍历（不再由 preRenderBotplay 二次全谱扫描）：与 botLaneCounts
		// 严格同口径（含密度倍数与长条段），保证 generateChartNotes 的校验恒等。
		// 仅在 preRenderNotes 开启（需要计划）时构建，省 11.8M 级谱面的 {{ }} 内存。
		var botplayLanes:Array<Array<Float>> = null;
		if (botplayPlan != null)
		{
			botplayLanes = [];
			for (i in 0...songKeys) botplayLanes.push([]);
		}

		var arrows:Array<CastNote> = [];
		var unspawnNotes:Array<CastNote> = [];
		var chartSeqCounter:Int = 0;

		var stepCrochet:Float = ((60 / song.bpm) * 1000) / 4;

		// ===== 超大字谱面：packed 快路径 =====
		// Song.loadPackedChart 已用音符级流式扫描完成**堆叠合并**，产出 packedNotes
		// （PackedChart 簇数组），此时 sectionNotes 为空 —— 逐音符 DOM 从未被构造。
		// 这里只做「簇 → CastNote」的转换，**绝不能再合并一次**（簇已是合并结果）。
		// 内存：驻留量与原始音符总数无关，只随「簇数 + 簇内 offs 总数」增长。
		if (song.packedNotes != null)
		{
			PerfProbe.mark('buildChartNotes: packed begin');
			var pr = buildFromPacked(song, botplayPlan, stepCrochet);
			PerfProbe.mark('buildChartNotes: packed done');
			return pr;
		}
		// 超密集谱面自动降级（Obsolescence-spam 1180 万音符级）：原始音符总数 ≥ DENSE_FORCE_MERGE 时
		// 无视 skipGhostNotes 强制开启堆叠合并；ghostDensity（计数/丢弃）仍尊重用户设置。
		// 否则合并关闭时 11.8M 颗音符合生成 11.8M 条 CastNote（加载期 OOM 且运行时 26 万 NPS/轨
		// 的墙逐颗物化精灵爆表）。仅数小节长度，11.8M 级谱面约 0.X ms，可忽略。
		var rawNoteCount:Int = 0;
		if (song.notes != null)
			for (sec in song.notes)
				if (sec != null && sec.sectionNotes != null)
					rawNoteCount += sec.sectionNotes.length;
		var forceDenseMerge:Bool = rawNoteCount >= DENSE_FORCE_MERGE;
		// 【500 帧补丁】密集谱标记：预生成与创建期兜底都经本函数，此处一次性判定即可覆盖全部路径
		densePerfMode = forceDenseMerge;
		if (forceDenseMerge && !ClientPrefs.data.skipGhostNotes)
			trace('[DenseChart] rawNotes=' + rawNoteCount + ' 触发超密集谱面自动合并（skipGhostNotes 被强制开启）');
		var ghostRange:Float = ClientPrefs.data.ghostRange;
		// 每簇保留的偏移样本数上限（0 = 全量，行为与旧版完全一致）
		var boundedKeep:Int = (ClientPrefs.data.boundedOffs) ? Std.int(ClientPrefs.data.boundedOffsKeep) : 0;
		var doGhostMerge:Bool = ClientPrefs.data.skipGhostNotes || forceDenseMerge;
		var ghostDensity:Bool = ClientPrefs.data.ghostDensity;
		var lastLaneArrow:Array<CastNote> = [];
		for (i in 0...songKeys) lastLaneArrow.push(null);

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
				// Extra Keys：绝对列号协议泛化（col < keys 玩家 / lane = col % keys；keys=4 与旧版等价）
				var rawCol:Int = Std.int(songNotes[1]);
				var daNoteData:Int = ExtraKeys.laneOf(rawCol);
				if (daNoteData < 0 || daNoteData >= songKeys) continue;
				// Psych 1.0.4 格式：列号直接决定方向（<keys 玩家、>=keys 对手），不再用 mustHitSection 翻转
				var gottaHitNote:Bool = (rawCol < songKeys);

				// ===== 堆叠合并（H-Slice 移植）：同轨 ±ghostRange 内的幽灵箭头合并为 density =====
				if (doGhostMerge)
				{
					var merged:CastNote = lastLaneArrow[daNoteData];
					if (merged != null && Math.abs(daStrumTime - merged.strumTime) <= ghostRange
						&& ((merged.noteData & (1 << 8)) != 0) == gottaHitNote)
					{
						if (ghostDensity) merged.density += 1;
						// 后台压缩 + 表面不压缩：记录该箭头相对基准的时间偏移，生成时按偏移展开回 N 个视觉箭头
						// 【有界偏移】生成期最多读 clusterVisCap（≤12）个，所以只保留前 KEEP 个
						// + 末个（lastOffset），真实数量记在 offsKeep。内存从 O(音符数) 降为 O(簇数×KEEP)，
						// 计分不受影响（density 仍是簇总颗数）。boundedOffs 关闭时行为与旧版完全一致。
						var off:Float = daStrumTime - merged.strumTime;
						merged.offsKeep++;
						merged.lastOffset = off;
						if (merged.offs == null) merged.offs = [];
						if (boundedKeep <= 0 || merged.offs.length < boundedKeep) merged.offs.push(off);
						if (gottaHitNote)
						{
							totalNotes++;
							if (botLaneCounts != null) botLaneCounts[daNoteData]++;
							// 合并簇内的每颗原始音符都入计划（绝对列号规则，与判定一致）
							if (botplayLanes != null) botplayLanes[daNoteData].push(daStrumTime);
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
				swagNote.offsKeep = 0;
				swagNote.lastOffset = 0;
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
					typeStr = bridge.EditorBridge.noteTypeList()[noteType]; //Backward compatibility + Week 7 charts
				// 固化拷贝：来自 JSON DOM 的字符串在 GC 后可能悬垂（安卓 hxcpp 实测），
				// 非空类型仍生成全新字符串；空类型共享常量——11.8M 音符级谱面省去
				// 每颗一次 ''+'' 分配与对应 GC 压力（Obsolescence-spam 加载提速点之一）。
				swagNote.noteType = (typeStr == '' ? '' : ('' + typeStr));

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
					if (botplayLanes != null) botplayLanes[daNoteData].push(daStrumTime);
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
				// 计划与 botLaneCounts 严格同口径：长条段按密度倍数入计划（校验恒等，
				// 判定时每段与 raw 音符一一对应；无长条谱面此分支零开销）
				if (botplayLanes != null && floorSus > 0)
				{
					var planLane:Int = swagNote.noteData & 255;
					var reps:Int = Std.int(swagNote.density);
					for (r in 0...reps)
						for (susNote in 0...floorSus + 1)
							botplayLanes[planLane].push(swagNote.strumTime + stepCrochet * susNote);
				}
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

		return { notes: unspawnNotes, noteTypes: noteTypes, totalNotes: totalNotes, botLaneCounts: botLaneCounts, botplayLanes: botplayLanes };
	}

	// ========================================================================
	// packed 快路径：把已合并的音符簇转成 CastNote
	// ========================================================================
	// 与主路径的语义对应关系（逐条对齐 buildChartNotes 的主循环）：
	//   - chartSeq：簇的 chartSeq 直接沿用（扫描期已按谱面顺序分配）
	//   - density ：簇代表的原始箭头数（一击记整簇，与 density 计分一致）
	//   - offs    ：簇内偏移数组，挂到 CastNote.offs 供生成期视觉展开
	//   - gfNote / noteType / multSpeed：扫描期已写入簇，直接搬运
	//   - 长条    ：与主路径同口径计入 botLaneCounts / botplayLanes
	// ⚠ 主路径的 DENSE_FORCE_MERGE 强制合并在扫描期已由 doMerge 覆盖，此处不再合并；
	//   但 densePerfMode（密集自动档）判定必须补上——见下方 packedRawF。
	static function buildFromPacked(song:SwagSong, botplayPlan:Array<Array<Float>>, stepCrochet:Float):PreGenResult
	{
		CastNote.resetPacked();
		var clusters:Array<PackedChart> = song.packedNotes;
		var noteTypes:Array<String> = [];
		// ⚠ 用 Float 累加：66 Part 组合实测 mustHit 总数 ≈ 1,923,457,370，已逼近 Int32 上限
		//   2,147,483,647；再多两个 Part 就会溢出成负数，而 totalNotes 是 HUD「Hits: x / y」
		//   与命中倍率判定的基准，负数会让判定全部失效。返回前夹到 Int 范围内。
		var totalNotesF:Float = 0;
		// 【密集谱判定补位】packed 路径此前**从未赋值 densePerfMode**（设计缺口，经
		// 36 亿谱面实测确认：dense=0、cap=0，密集栈全部护栏对墙谱整层失效）。此处按
		// 与主路径同口径重建「原始音符总数」：单簇取 max(density, offsKeep+1) ——
		// ghostDensity=1 时 density=簇内原始数；=0 时 density=1 而 offsKeep 记录合并数；
		// 缓存加载路径 offsKeep←density（PackedCache.load），≥4M 的墙谱两种口径都过阈值。
		// Float 累加防 Int32 溢出（66 Part 实测 Σ ≈ 38.5 亿 > 2^31）。
		var packedRawF:Float = 0;
		var botLaneCounts:Array<Int> = botplayPlan != null ? ExtraKeys.zeroLanes() : null;
		var botplayLanes:Array<Array<Float>> = null;
		if (botplayPlan != null)
		{
			botplayLanes = [];
			for (i in 0...ExtraKeys.songKeys) botplayLanes.push([]);
		}
		var unspawnNotes:Array<CastNote> = [];

		for (c in clusters)
		{
			var n = new CastNote();
			n.strumTime = c.t;
			var mustHit:Bool = c.mustHit;
			// noteData 位布局与主路径一致：低 8 位轨道 + 1<<8 mustHit + 1<<11 gfNote
			n.noteData = c.lane | (mustHit ? (1 << 8) : 0);
			if (c.gfNote) n.noteData |= 1 << 11;
			n.density = c.density;
			n.chartSeq = c.chartSeq;
			n.holdLength = c.holdLength;
			n.multSpeed = c.multSpeed;
			n.noAnimation = false;
			n.noMissAnimation = false;
			n.blockHit = false;
			n.noteType = c.noteType;
			n.offs = c.offs;
			n.offsKeep = c.offsKeep;
			n.lastOffset = c.lastOffset;

			if (c.offsKeep + 1 > c.density) packedRawF += c.offsKeep + 1;
			else packedRawF += c.density;

			if (c.noteType != null && !noteTypes.contains(c.noteType)) noteTypes.push(c.noteType);

			unspawnNotes.push(n);

			if (mustHit)
			{
				totalNotesF += c.density;
				if (botLaneCounts != null) botLaneCounts[c.lane] += c.density;
				if (botplayLanes != null) botplayLanes[c.lane].push(c.t);
			}

			// 长条分段：与主路径同口径（含密度倍数）
			var floorSus:Int = Math.floor((c.holdLength / stepCrochet));
			if (botLaneCounts != null && mustHit && floorSus > 0)
				botLaneCounts[c.lane] += Std.int((floorSus + 1) * c.density);
			if (botplayLanes != null && floorSus > 0)
			{
				for (r in 0...c.density)
					for (susNote in 0...floorSus + 1)
						botplayLanes[c.lane].push(c.t + stepCrochet * susNote);
			}
		}

		unspawnNotes.sort(sortByTime);
		_segmentSeqBase = unspawnNotes.length;

		var totalNotes:Int = (totalNotesF > 2147483000) ? 2147483000 : Std.int(totalNotesF);

		// 【密集自动档·补位赋值】与主路径 `densePerfMode = forceDenseMerge` 同口径：
		// 原始音符总数 ≥ DENSE_FORCE_MERGE 才启用（已验证的 2.26M 级 packed 谱面不触发，
		// 行为与旧版一致）；每次进入本函数都显式赋值，杜绝静态量跨曲残留。
		densePerfMode = packedRawF >= DENSE_FORCE_MERGE;
		if (densePerfMode)
			trace('[DenseChart] packed raw≈' + Std.int(Math.min(packedRawF, 2147483000))
				+ ' 触发密集自动档（对象上限/对象池/自适应预算/安静命中生效）');

		trace('[PACKEDBUILD] clusters=' + clusters.length + ' totalNotes=' + totalNotes
			+ ' sections=' + (song.packedSectionCount != null ? song.packedSectionCount : -1));

		// 【内存遥测】packed 构建完成快照：dense 标志的真实态 + raw≈（Σ 每簇原始数的 Float 观测值）
		// + botplayLanes 条目数（buildFromPacked 按「箭头数×段数」展开，
		// preRenderNotes 开启时是 O(原始音符数) 的潜在内存炸弹，墙簇 density 190 万起步）。
		var _laneEntries:Int = 0;
		if (botplayLanes != null)
			for (l in 0...botplayLanes.length)
				if (botplayLanes[l] != null) _laneEntries += botplayLanes[l].length;
		PerfProbe.mark('packedbuild: done clusters=' + clusters.length
			+ ' raw=' + Std.int(Math.min(packedRawF, 2147483000))
			+ ' dense=' + densePerfMode + ' lanes=' + (botplayLanes == null ? 'off' : Std.string(_laneEntries)));

		return {
			notes: unspawnNotes,
			noteTypes: noteTypes,
			totalNotes: totalNotes,
			botLaneCounts: botLaneCounts,
			botplayLanes: botplayLanes
		};
	}

	// 谱面生成期即拼接完整脚本路径（create 后期才拼接会读到 GC 后悬垂的字符串）
	inline function rebuildNoteTypePaths():Void NoteChartDomain.rebuildNoteTypePaths(this);

	private function generateChartNotes(loadPhase:Bool):Void NoteChartDomain.generateChartNotes(this, loadPhase);

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) EventDomain.eventPushed(this, event);

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		EventDomain.eventPushedUnique(this, event);
	}

	function eventEarlyTrigger(event:EventNote):Float return EventDomain.eventEarlyTrigger(this, event);

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int) EventDomain.makeEvent(this, event, i);

	public var skipArrowStartTween:Bool = false; //for lua

	// ---- 自定义界面：HUD 布局偏移 ----
	public function hudGetOffset(id:String):Array<Float> return CameraHudDomain.hudGetOffset(this, id);

	// 重置某个 HUD 元素到默认位置（偏移清零并立即重排）
	public function hudResetElement(id:String) CameraHudDomain.hudResetElement(this, id);

	// 按保存的偏移重算所有 HUD 元素位置（默认位置 + 偏移），自定义界面拖动/重置时使用
	public function repositionHUD() CameraHudDomain.repositionHUD(this);

	private function generateStaticArrows(player:Int):Void CameraHudDomain.generateStaticArrows(this, player);

	override function openSubState(SubState:FlxSubState)
	{
		HostDomain.openSubState(this, SubState);
	}

	@:noCompletion public function meteoSuper_openSubState(SubState:FlxSubState) return super.openSubState(SubState);

	override function closeSubState()
	{
		HostDomain.closeSubState(this);
	}

	@:noCompletion public function meteoSuper_closeSubState() return super.closeSubState();

	override public function onFocus():Void
	{
		HostDomain.onFocus(this);
	}

	@:noCompletion public function meteoSuper_onFocus() return super.onFocus();

	override public function onFocusLost():Void
	{
		HostDomain.onFocusLost(this);
	}

	@:noCompletion public function meteoSuper_onFocusLost() return super.onFocusLost();

	function resyncVocals():Void HostDomain.resyncVocals(this);

	public var paused:Bool = false;
	// Meteoric：后台音频冻结标记（退后台时暂停 music/vocals/opponentVocals，回前台恢复）
	var _bgAudioFrozen:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;

	// ===== H-Slice 移植：音符生成系统（生成游标 O(n) / 快速跳谱 / 挤压音符展开 / 可见性裁剪） =====

	inline function spawnWindowFor(target:CastNote):Float
	{
		return HostDomain.spawnWindowFor(this, target);
	}

	// 【Turbo】聚合区分析（含侧车缓存）：100ms 分箱 ≥4000NPS、无长条、≥500ms 的连续区间。
	// 缓存指纹 = song|mod|数量|chartFingerprint，落盘 crash/turbo_cache/<md5>.bin。
	function initTurboZones():Void HostDomain.initTurboZones(this);

	// 【Turbo】当前 unspawn 游标是否处于聚合区（游标单调前进，O(1) 摊销）
	inline function isTurboAggregateIndex(index:Int):Bool
	{
		return HostDomain.isTurboAggregateIndex(this, index);
	}

	// 【Turbo】数据级结算（不建 Sprite）：口径与 goodNoteHit/popUpScore 的 botplay 路径一致——
	// 判定恒为 ratingsData[0]（botplay diff=0 → Marvelous/Sick），按密度加权；长条不在此结算。
	function settleCastHit(target:CastNote, hitMult:Int):Void NoteChartDomain.settleCastHit(this, target, hitMult);

	// 【性能】释放已消费的 CastNote 引用：桌面游标模式下，currentSpawnId 左侧的
	// 对象已不可能再被读取（二分/顺序读取均从 currentSpawnId 起步），置 null 让
	// GC 逐段回收，避免 22 万级谱面全程持有已消费对象（GC 尖峰/内存大头之一）。
	// 每累计 2048 条清扫一次，摊还 O(1)/音符；游标回退（重开）时自动对齐。
	function releaseConsumedNotes():Void NoteChartDomain.releaseConsumedNotes(this);

	function noteSpawn():Void NoteChartDomain.noteSpawn(this);

	var clusterVisCap:Int = 12; // 每簇视觉采样上限（noteSpawn 每 500ms 按窗口密度动态调整）
	var lastVisBudgetCalc:Float = -99999;
	var botSchedule:Array<Note> = []; // 生成即排期的自动命中队列（不依赖 alive-loop）
	var _oppHitSeqs:Map<Int, Bool> = null; // 【500 帧补丁】对手命中兄弟视觉副本批扫集合（一整帧只扫一次成员表）
	var lastSchedulePos:Float = -99999;
	var botBatchSeenSeq:Map<Int, Bool> = new Map<Int, Bool>(); // 批内计分去重（同 chartSeq 只记一次）

	/** 实例化一个音符（对象池复用）并触发 onSpawnNote 回调。
	 *  堆叠合并组（offs != null）在此展开：后台一条 CastNote，画面与原版一致（N 个独立视觉箭头）。 */
	// ===== 长条重构：箭头出生时一次性构建整根尾巴 =====
	// 段 Note 由构造函数创建（prevNote 逐段链接 → 自动切 hold/链式拉伸/holdend 圆润收尾），
	// 与安卓直建管线同款；登记 note.tail（Lua 接口）与 seqNote 静态链（判定/回放）。
	// 安卓：unspawnNotes 为 Note 实体数组（无 CastNote 代理），参数用 Dynamic
		#if false
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
			// Extra Keys：位打包低 8 位 = lane（旧 `& 3` 会把 lane≥4 截断成 0-3）
			var seg:Note = new Note(target.strumTime + stepCrochet * i, target.noteData & 255,
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
		#if false
	function spawnOneWithTail(target:Dynamic):Note
	#else
	function spawnOneWithTail(target:CastNote):Note
	#end
	{
		return HostDomain.spawnOneWithTail(this, target);
	}

	// 桌面：静态类型参数，CastNote 平行数组代理的字段访问全部走内联 getter；
	// 安卓保留 Dynamic（unspawnNotes 为 Note 实体数组，字段集不同）
		#if false
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
		var offsKeep:Int = target.offsKeep;      // 簇内真实合并数量
		var lastOff:Float = target.lastOffset;   // 簇内最后一个偏移
		base.offs = null;
		base.offsKeep = 0;
		base.lastOffset = 0;
		// 基准保持 density=簇总颗数（计分）；采样副本 density=1 且不参与判定
		var lastNote:Note = spawnOne(base);
		// 长条重构：基准箭头（含 holdLength）的尾巴挂在 base 上（最后一个视觉副本不是锚点）
		if (base.holdLength > 0 && base.chartSeq >= 0)
			spawnHoldTail(lastNote, base);

		// 均匀采样：保留首、尾与等距中间点（视觉跨度/密度与原版一致）；
		// maxVis 由 noteSpawn 按"2s 窗口簇数"动态预算（场上精灵总额控制）
		var maxVis:Int = clusterVisCap; // 动态视觉预算（见 noteSpawn）
		if (maxVis < 1) maxVis = 12;
		// 【视觉折叠】visualFold > 0 时按比例缩减每簇视觉采样数（只影响视觉副本，不参与判定）
		if (ClientPrefs.data.visualFold > 0)
		{
			maxVis = Std.int(maxVis * ClientPrefs.visualFoldFactor());
			if (maxVis < 1) maxVis = 1; // 至少保留 1 个视觉副本
		}

		// 【有界偏移还原·O(maxVis)】boundedOffs 开启时 offs 只存了前 KEEP 个（+ lastOff），
		// 真实数量记在 offsKeep —— 多 Part 组合谱里单个簇可达 **190 万颗**（66 Part 同刻叠加；
		// 实测 stupid-griefer 尾段 980 个簇的 density 和 = 18.94 亿）。
		// 旧实现为了采样 ≤maxVis 个点，先把尾部线性插值**整段展开**成 Array 再采样：
		//   span = offsKeep - (offs.length - 1) ≈ 190 万 → 每簇一次性 push 190 万个元素，
		//   随后 offs.concat(tail) 再整体复制一份；980 个这样的簇 ≈ 数十 GB 分配。
		// 实测后果：尾段彻底卡死（用户反馈「尾杀段很卡」），这些簇走不到命中路径，
		//   可击中数量只剩轻簇的 2,931 万（应为 19.23 亿，差 65 倍）。
		// 现改为按采样下标**反算**偏移值：前半段直接取存下来的，越界段走尾部闭式线性插值，
		// 复杂度 O(maxVis)。同一 idx 的取值与旧实现逐点等价 —— 普通谱面（tailSpan 本就很小）
		// 走的仍是同一分支，行为与旧版完全一致。
		var picks:Array<Float> = [];
		if (offs.length > 0)   // offs 为空时旧版 full=[] → 不展开任何视觉副本，保持一致
		{
			var total:Int = (offsKeep > offs.length) ? offsKeep : offs.length;
			var tailSpan:Int = (total > offs.length) ? (total - (offs.length - 1)) : 0;
			var firstTail:Float = offs[offs.length - 1];
			var denom:Float = (tailSpan > 1) ? (tailSpan - 1) : 1;

			// idx ∈ [0, total) → 该位置的偏移；idx ≥ offs.length 时落到尾部插值段
			var offsetAt = function(idx:Int):Float {
				if (idx < 0) idx = 0;
				if (idx < offs.length) return offs[idx];
				if (tailSpan <= 0) return firstTail;
				var j:Int = idx - (offs.length - 1);
				if (j > tailSpan - 1) j = tailSpan - 1;
				return firstTail + (lastOff - firstTail) * (j / denom);
			};

			if (total > maxVis - 1)
			{
				var step:Float = (total - 1) / (maxVis - 1);
				for (i in 0...maxVis)
				{
					var idx:Int = Std.int(i * step);
					if (idx >= total) idx = total - 1;
					picks.push(offsetAt(idx));
				}
			}
			else
			{
				// 采样点覆盖不了全部 → 全部铺开（尾部本来就短，tailSpan ≤ maxVis-1）
				picks = offs;
				if (tailSpan > 0)
				{
					picks = offs.copy();
					for (j in 0...tailSpan) picks.push(firstTail + (lastOff - firstTail) * (j / denom));
				}
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

		#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
		// Meteoric 脚本系统：音符创建事件 —— 脚本可改这根音符（类型 / 贴图 / 血量 / 判定 …）；
		// event.cancel() = 这根音符不参与判定与计分（仍然显示，但不打、不计分）。
		if (Scripting.eventsEnabled())
		{
			var ev:ScriptNoteEvent = new ScriptNoteEvent('creation', dunceNote);
			ev.noteData = dunceNote.noteData;
			ev.mustPress = dunceNote.mustPress;
			ev.sustain = dunceNote.isSustainNote;
			if (Scripting.dispatch('onNoteCreation', ev))
			{
				dunceNote.ignoreNote = true;
				dunceNote.blockHit = true;
			}
		}
		#end

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
		var hide:Float = perfHideOverlapped;
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
	function spamSpawn():Void NoteChartDomain.spamSpawn(this);

	override public function update(elapsed:Float)
	{
		// 大纹理 CPU 副本的周期性兜底释放（默认关闭时 no-op）
		backend.GfxPolicy.onPlayUpdate(elapsed);
		HostDomain.update(this, elapsed);
		// Render Mode 抓帧（内部按 targetFPS 节流）。放在 update 末尾是刻意的：
		// Flixel 的绘制发生在 ENTER_FRAME 的 update 之后，所以此刻帧缓冲里是**上一帧**
		// 已完成的画面 —— 恒定滞后一帧（60fps 下 16ms），音画对齐见 VideoRecorder.start 注释。
		backend.VideoRecorder.update(haxe.Timer.stamp());
	}

	@:noCompletion public function meteoSuper_update(elapsed:Float) return super.update(elapsed);

	#if METEORIC_PROFILE
	/** 绘制总耗时探针：看到 PlayState 的 render 段占整帧多少（不在 update 内）。 */
	override public function draw():Void
	{
		var _dT0:Float = backend.MeteoricProfile.tickNow();
		super.draw();
		backend.MeteoricProfile.phaseAdd('draw', backend.MeteoricProfile.tickNow() - _dT0);
	}
	#end

	#if mobile
	/** 游玩中按返回键 / 左上角 X：暂停游戏而不是退出（菜单里仍是退出到桌面） */
	override public function onAndroidBack():Bool
	{
		return HostDomain.onAndroidBack(this);
	}
	#end

	public function openPauseMenu(fromRemote:Bool = false) HostDomain.openPauseMenu(this, fromRemote);

	function openChartEditor() NoteChartDomain.openChartEditor(this);

	function openCharacterEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		bridge.EditorBridge.openCharacterEditor(SONG.player2);
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead)
		{
			#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
			// Meteoric 脚本系统：死亡事件 —— event.cancel() = 不死。
			// 取消时把血量拉回 0 以上（否则下一帧的死亡检查会再次触发，形成死循环）。
			if (Scripting.eventsEnabled())
			{
				var ev:ScriptLifecycleEvent = new ScriptLifecycleEvent('gameOver');
				ev.health = health;
				if (Scripting.dispatch('onGameOver', ev))
				{
					health = ev.health > 0 ? ev.health : 0.01;
					return false; // 返回 false = 没死（调用方据此走「未死亡」分支）
				}
			}
			#end

			// 联机：不死于 GameOver，直接进入双端成绩对比（先发送本方 FINISH）

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

				// 结算主题：由 stage 显式提供（BaseStage.getGameOverTheme），随调用点一次性传入
				// —— stage 不再直接写 GameOverSubstate 的全局字段。
				// 求值时点：旧实现在 stage create() 期间写全局，现在改为**进入结算时**求值；
				// 引擎内两者之间无可观察读取者（四字段只在本类构造/更新期被读），
				// 唯一可观察差异是脚本侧若在死亡前读这些字段会看到谱面/默认值。
				// 多 stage 场景按创建序合并（后者覆盖非 null 字段）= 旧实现「后写者胜」；
				// 注意拷贝而非直接引用返回值，避免污染 stage 自己持有的主题对象。
				var goTheme:GameOverTheme = null;
				stagesFunc(function(stage:BaseStage) {
					var t = stage.getGameOverTheme();
					if (t == null) return;
					if (goTheme == null) {
						goTheme = {
							characterName: t.characterName,
							deathSoundName: t.deathSoundName,
							loopSoundName: t.loopSoundName,
							endSoundName: t.endSoundName
						};
						return;
					}
					if (t.characterName != null) goTheme.characterName = t.characterName;
					if (t.deathSoundName != null) goTheme.deathSoundName = t.deathSoundName;
					if (t.loopSoundName != null) goTheme.loopSoundName = t.loopSoundName;
					if (t.endSoundName != null) goTheme.endSoundName = t.endSoundName;
				});

				// Psych 1.0.4：deathDelay > 0 时延迟打开 Game Over（Weekend 1 Blazin 用 0.15s）
				if (GameOverSubstate.deathDelay > 0)
				{
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
					{
						openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x - boyfriend.positionArray[0], boyfriend.getScreenPosition().y - boyfriend.positionArray[1], camFollow.x, camFollow.y, goTheme));
						gameOverTimer = null;
					});
				}
				else
					openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x - boyfriend.positionArray[0], boyfriend.getScreenPosition().y - boyfriend.positionArray[1], camFollow.x, camFollow.y, goTheme));

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() NoteChartDomain.checkEventNote(this);

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		EventDomain.triggerEvent(this, eventName, value1, value2, strumTime);
	}

	public function moveCameraSection(?sec:Null<Int>):Void CameraHudDomain.moveCameraSection(this, sec);

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool) CameraHudDomain.moveCamera(this, isDad);

	public function tweenCamIn() CameraHudDomain.tweenCamIn(this);

	public function finishSong(?ignoreNoteOffset:Bool = false):Void HostDomain.finishSong(this, ignoreNoteOffset);


	public var transitioning = false;
	var _pausedSelfHealFrames:Int = 0; // 暂停自愈延迟帧(防误判正常关闭,见update注释)
	public function endSong():Bool return HostDomain.endSong(this);

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
		HostDomain.achievementEnd(this);
	}
	#end

	public function KillNotes() NoteChartDomain.KillNotes(this);

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
		healthDisplayPct = health / 2 * 100; // 与真实血量同步（health=1 → 50%）
		pendingFlySpikePct = 0;
		songScore = 0;
		songHits = 0;
		songMisses = 0;
		judgementHistory = []; // KE 散点图：重开清空本局判定记录
		totalPlayed = 0;
		totalNotesHit = 0;
		combo = 0;
		npsDisplay = 0;
		maxNpsDisplay = 0;
		_npsCount = 0;
		_npsTimer = 0;
		maxCombo = 0; // 结算界面：最高连击随重开清零
		allSicks = true; // 金色 Combo：重开复位
		songPercent = 0;
		usedAutoplay = cpuControlled || replayMode;
		usedGodMode = false; // 上帝模式正常记分
		destroyedNotes = 0; // 销毁模式本局统计清零
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
		replayHeld = ExtraKeys.falseLanes();
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
		#if false
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
		#if false
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
		finishingSong = false;
		canPause = true;
		canReset = true;
		inCutscene = false;
		skipCountdown = false;
		skipArrowStartTween = false;
		generatedMusic = false;
		updateTime = (ClientPrefs.data.timeBarType != '禁用');
		startOnTime = 0;
		Conductor.setPosition(0);
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
		if (!ClientPrefs.data.hudOnly)
		{
			if (boyfriend != null) { boyfriend.specialAnim = false; boyfriend.stunned = false; boyfriend.holdTimer = 0; boyfriend.dance(); }
			if (dad != null) { dad.specialAnim = false; dad.stunned = false; dad.holdTimer = 0; dad.dance(); }
			if (gf != null) { gf.specialAnim = false; gf.stunned = false; gf.holdTimer = 0; gf.dance(); }
		}

		// 相机复位
		camZooming = false;
		FlxG.camera.zoom = defaultCamZoom;
		camHUD.zoom = 1;
		moveCameraSection(0);

		RecalculateRating();

		Lib.application.window.title = Lang.tOr('win.playing', "FNF':Meteoric Engine - Playing: ") + curSong;
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
	function ensureCharactersAlive():Void HostDomain.ensureCharactersAlive(this);

	// 快速重开：参照完整重开（resetState → create）重新加载默认角色
	private function reloadDefaultCharacters():Void HostDomain.reloadDefaultCharacters(this);

	private function destroyAllCharacters():Void HostDomain.destroyAllCharacters(this);

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

	public var totalPlayed:haxe.Int64 = 0;
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

	private function cachePopUpScore() CameraHudDomain.cachePopUpScore(this);

	// KE 判定评级（Kade Engine）：45/90/135ms 窗口，提前/晚到分开判断，随安全帧缩放
	private function judgeRatingKE(note:Note):Rating return CameraHudDomain.judgeRatingKE(this, note);

	// 评级/连击弹窗贴图存在性缓存：同一实例（同一首歌）内皮肤与文件不变，
	// 避免每次命中都打文件系统（Paths.fileExists 每次含多次 exists 探测 + 字符串分配）。
	var _popupAssetExists:Map<String, Bool> = [];
	function popupAssetExists(imgPath:String):Bool
	{
		if (!_popupAssetExists.exists(imgPath))
			_popupAssetExists.set(imgPath, Paths.fileExists('images/' + imgPath + '.png', IMAGE));
		return _popupAssetExists.get(imgPath);
	}

	private function popUpScore(note:Note = null, ?cappedMult:Int = null):Void
	{
		// 【密集谱·安静命中档】densePerfMode + 自动游玩/回放：跳过纯视觉与低频刷新开销；
		// 计分/命中/评级计数/溅射节流均不受影响（本函数前半段照常执行）。
		var quietHit:Bool = PlayState.densePerfMode && (cpuControlled || replayMode)
			&& ClientPrefs.data.botMode != 'destroy'; // 销毁模式即使密集也保留命中计数弹窗（密集批下每批只弹一次，见 botBatchScoreShown）
		// 首次命中才落盘（原实现每命中 mark → 每命中一次磁盘写，密集团灭段每秒数千次）
		if (!_stageMarkPop)
		{
			_stageMarkPop = true;
			CrashHandler.mark('popUpScore:start');
		}
		// botplay 命中时间由其排期时刻定义（=音符自身 strumTime），帧延迟不影响评级
		var noteDiff:Float = cpuControlled ? 0 : Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		vocals.volume = 1;

		var placement:Float =  FlxG.width * 0.35;
		var rating:FlxSprite = null;
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
		// PF 移植：非 Marvelous/Sick 判定即退出“全 Sick”金色 Combo
		if (daRating.name != 'marvelous' && daRating.name != 'sick') allSicks = false;
		// KE 结算散点图：记录主音符命中偏移（+ 早到 / - 晚到；自动游玩不记录）
		if (!cpuControlled && !note.isSustainNote && note.rating != null && note.rating.length > 0)
			judgementHistory.push({t: note.strumTime, d: note.strumTime - Conductor.songPosition, r: note.rating});
		score = daRating.score * scoreMult;

		if(daRating.noteSplash && !note.noteSplashData.disabled && !(cpuControlled && botHitBatch && botBatchSplashDone[note.noteData])
			&& !(ClientPrefs.data.botMode == 'destroy' && cpuControlled)) // 销毁模式只弹数字，不产生 rating/溅射
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
			// 【密集谱自动游玩·评级/分数节流】RecalculateRating 每命中执行 7×setOnScripts +
			// callOnScripts('onRecalculateRating') + updateScore（分数文本字符串重建），
			// 是 notes 阶段 300us+ 的主体；密集自动游玩改为每 250ms 结算一次
			// （HUD 仍有 4Hz 刷新；endSong 的 RecalculateRating 保证结算值精确，不受节流影响）。
			if (!quietHit || haxe.Timer.stamp() - _lastRatingRecalc >= 0.25)
			{
				_lastRatingRecalc = haxe.Timer.stamp();
				RecalculateRating(false);
			}
		}

		// 自动游玩批处理：堆叠命中只显示一次评分（其余仅计分），避免一帧内创建大量评分/连击精灵
		if (cpuControlled && botHitBatch)
		{
			if (botBatchScoreShown) return;
			botBatchScoreShown = true;
		}

		// JS Engine 移植：自动游玩省资源（lessBotLag）——已记分/评级/溅射，跳过全部弹窗精灵创建
		if (cpuControlled && ClientPrefs.data.lessBotLag) return;
		// 【密集谱自动游玩·强制免弹窗】与 lessBotLag 同效（仅视觉，计分/评级/溅射均已完成）：
		// 密集批每帧数百命中，弹窗精灵+FlxTween 每秒创建数百个——GC 关闭时 destroy 只断引用
		// 不回收内存，长期游玩内存线性上涨，且每帧都有弹窗创建/补间开销（直方图 2~5ms 长尾
		// 即大命中批帧）；密集档直接等同 lessBotLag。手动游玩不受影响。
		if (quietHit) return;
		// JS Engine 移植：评分/连击弹窗开关（默认=当前行为）
		var showRatingPop:Bool = showRating && ClientPrefs.data.ratingPopups
			&& !(ClientPrefs.data.botMode == 'destroy' && cpuControlled); // 销毁模式：只保留数字计数弹窗，不弹 Sick/评级条
		var showComboPop:Bool = showCombo && ClientPrefs.data.comboPopups;
		var showComboNumPop:Bool = showComboNum && ClientPrefs.data.comboPopups;

		// Meteoric 脚本系统：评级事件 —— 脚本可换评级贴图 / 关掉评级弹窗。
		// 放在提前 return **之前**：脚本才有机会强制显示评级（ev.visible = true）。
		// 覆盖变量在 #if 外声明：非脚本平台它恒为 null，行为与改动前完全一致。
		var ratingImgOverride:String = null;
		#if (MODS_ALLOWED && HSCRIPT_ALLOWED && sys)
		if (Scripting.eventsEnabled())
		{
			var ev:ScriptRatingEvent = new ScriptRatingEvent(daRating.image, daRating.name, combo);
			if (Scripting.dispatch('onRatingShown', ev))
			{
				showRatingPop = false;
			}
			else
			{
				ratingImgOverride = ev.ratingImage;
				showRatingPop = ev.visible;
			}
		}
		#end

		if (!showRatingPop && !showComboPop) return;

		// 弹窗弹出方式（见 backend.PopupAnim）：classic = 上游原抛物线，
		// 其余三种由 PopupAnim 接管运动与销毁（本函数后续据此分流）。
		var popupStyle:String = ClientPrefs.data.popupStyle;
		var popupCustom:Bool = PopupAnim.isCustom(popupStyle);
		var popupDur:Float = ClientPrefs.data.popupDuration;

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		if (showRatingPop)
		{
			rating = new FlxSprite();
			var ratingImg:String = ratingImgOverride != null ? ratingImgOverride : daRating.image;
			// Marvelous 无像素版贴图，像素关卡回退 sick
			if (ratingImg == 'marvelous' && PlayState.isPixelStage) ratingImg = 'sick';
			// PF 移植：Early/Late 指示器——偏早/偏晚命中优先用 -early/-late 评级图，
			// 缺失（如 Marvelous / 自定义皮肤）回退基础图
			var daTiming:String = (note.strumTime < Conductor.songPosition) ? '-late' : '-early';
			var ratingPath:String = uiPrefix + ratingImg + daTiming + uiSuffix;
			if (popupAssetExists(ratingPath))
				rating.loadGraphic(Paths.image(ratingPath));
			else
				rating.loadGraphic(Paths.image(uiPrefix + ratingImg + uiSuffix));
			rating.cameras = [camHUD];
			rating.screenCenter();
			rating.x = placement - 40;
			rating.y -= 60;
			rating.acceleration.y = 550 * playbackRate * playbackRate;
			rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
			rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
			rating.visible = (!ClientPrefs.data.hideHud && showRatingPop);
			rating.x += ClientPrefs.data.comboOffset[0];
			rating.y -= ClientPrefs.data.comboOffset[1];
			rating.antialiasing = antialias;
		}

		// PF 移植：全 SICK/Marvelous 时 Combo 文字用金色贴图，缺失回退普通 combo
		var comboSpr:FlxSprite = null;
		if (showComboPop)
		{
			var comboPath:String = uiPrefix + 'combo' + (allSicks ? '-golden' : '') + uiSuffix;
			comboSpr = new FlxSprite();
			if (popupAssetExists(comboPath))
				comboSpr.loadGraphic(Paths.image(comboPath));
			else
				comboSpr.loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
			comboSpr.cameras = [camHUD];
			comboSpr.screenCenter();
			comboSpr.x = placement;
			comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			comboSpr.visible = (!ClientPrefs.data.hideHud && showComboPop);
			comboSpr.x += ClientPrefs.data.comboOffset[0];
			comboSpr.y -= ClientPrefs.data.comboOffset[1];
			comboSpr.antialiasing = antialias;
			comboSpr.y += 60;
			comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
		}

		if (showRatingPop)
			insert(members.indexOf(strumLineNotes), rating);
		
		if (showRatingPop && !ClientPrefs.data.comboStacking)
		{
			if (lastRating != null) lastRating.kill();
			lastRating = rating;
		}

		if (!PlayState.isPixelStage)
		{
			if (rating != null) rating.setGraphicSize(Std.int(rating.width * 0.7));
			if (comboSpr != null) comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			if (rating != null) rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			if (comboSpr != null) comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		if (comboSpr != null) comboSpr.updateHitbox();
		if (rating != null) rating.updateHitbox();

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
		if (showComboPop)
		{
			insert(members.indexOf(strumLineNotes), comboSpr);
		}
		if (showComboPop && !ClientPrefs.data.comboStacking)
		{
			if (lastCombo != null) lastCombo.kill();
			lastCombo = comboSpr;
		}
		if (showComboNumPop && lastScore != null)
		{
			while (lastScore.length > 0)
			{
				lastScore[0].kill();
				lastScore.remove(lastScore[0]);
			}
		}
		// 数字弹窗独立于 Combo 词：词受 showComboPop 控制，数字受 showComboNumPop 控制。
		// （v1.1.2 曾把数字循环误包进恒为 false 的 showComboPop，导致连击数字完全不显示）
		if (showComboNumPop)
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
			if(showComboNumPop)
				insert(members.indexOf(strumLineNotes), numScore);

			if (popupCustom)
			{
				PopupAnim.play(numScore, popupStyle, playbackRate, popupDur);
			}
			else
			{
				FlxTween.tween(numScore, {alpha: 0}, 0.2 * popupDur / playbackRate, {
					onComplete: function(tween:FlxTween)
					{
						numScore.destroy();
					},
					startDelay: Conductor.crochet * 0.002 / playbackRate
				});
			}

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;
		}
		// 修复：Combo 词的水平位置不再被“数字最大 x”覆盖回默认——保留方向键 Rank 偏移
		if (comboSpr != null) comboSpr.x = xThing + 50 + ClientPrefs.data.comboOffset[0];

		// 淡出与销毁：classic 走上游原链（rating 由 comboSpr 的 onComplete 一并销毁）；
		// 其余风格交给 backend.PopupAnim —— 它接管运动 + 淡出 + 销毁，这里不要再叠 alpha 补间。
		if (popupCustom)
		{
			PopupAnim.play(rating, popupStyle, playbackRate, popupDur);
			PopupAnim.play(comboSpr, popupStyle, playbackRate, popupDur);
		}
		else if (comboSpr != null)
		{
			if (rating != null)
				FlxTween.tween(rating, {alpha: 0}, 0.2 * popupDur / playbackRate, {
					startDelay: Conductor.crochet * 0.001 / playbackRate
				});

			FlxTween.tween(comboSpr, {alpha: 0}, 0.2 * popupDur / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					comboSpr.destroy();
					if (rating != null) rating.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});
		}
		else if (rating != null)
		{
			FlxTween.tween(rating, {alpha: 0}, 0.2 * popupDur / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					rating.destroy();
				},
				startDelay: Conductor.crochet * 0.001 / playbackRate
			});
		}
	}

	public var strumsBlocked:Array<Bool> = [];
	#if mobile
	/** 后台化时自动暂停：返回键/侧滑返回/Home 键都会先把游戏切到后台 */
	private function onStageDeactivate(event:Event):Void EventDomain.onStageDeactivate(this, event);

	/** 回前台：恢复被后台冻结的音频（游戏仍处于暂停菜单，不自动继续游戏） */
	private function onStageActivate(event:Event):Void EventDomain.onStageActivate(this, event);

	private function freezeBackgroundAudio():Void
	{
		HostDomain.freezeBackgroundAudio(this);
	}

	private function restoreBackgroundAudio():Void
	{
		HostDomain.restoreBackgroundAudio(this);
	}
	#end

	private function onKeyPress(event:KeyboardEvent):Void
	{
		InputDomain.onKeyPress(this, event);
	}

	private function keyPressed(key:Int) InputDomain.keyPressed(this, key);

	public static function sortHitNotes(a:Note, b:Note):Int return NoteChartDomain.sortHitNotes(a, b);

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		InputDomain.onKeyRelease(this, event);
	}

	private function keyReleased(key:Int) InputDomain.keyReleased(this, key);

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int return EventDomain.getKeyFromEvent(arr, key);

	// Hold notes
	private function keysCheck():Void InputDomain.keysCheck(this);

	/** 回放 v2：按录制时间注入按键按下/抬起（走正常判定路径），并处理长按子段命中 */
	private function updateReplayInputs():Void ReplayDomain.updateReplayInputs(this);

	/** 回放 v2：暂停菜单跳时间后，把按键游标对齐到新时间点 */
	public function resetReplayToTime(t:Float):Void
	{
		ReplayDomain.resetReplayToTime(this, t);
	}

	function noteMiss(daNote:Note):Void NoteChartDomain.noteMiss(this, daNote);

	function noteMissPress(direction:Int = 1, force:Bool = false):Void NoteChartDomain.noteMissPress(this, direction, force);

	function noteMissCommon(direction:Int, note:Note = null) NoteChartDomain.noteMissCommon(this, direction, note);

	function opponentNoteHit(note:Note):Void NoteChartDomain.opponentNoteHit(this, note);

	// 自动游玩批处理：统一命中本帧收集的音符，堆叠时合并副作用
	function recordReplayEvent(seq:Int, t:Float, d:Int, r:String):Void
	{
		EventDomain.recordReplayEvent(this, seq, t, d, r);
	}

	function processBotHits():Void NoteChartDomain.processBotHits(this);

	function goodNoteHit(note:Note):Void NoteChartDomain.goodNoteHit(this, note);

	public function spawnNoteSplashOnNote(note:Note) NoteChartDomain.spawnNoteSplashOnNote(this, note);

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null) NoteChartDomain.spawnNoteSplash(this, x, y, data, note);

	override function destroy() {
		#if LUA_ALLOWED
		for (i in 0...luaArray.length) {
			var lua:FunkinLua = luaArray[0];
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		psychlua.ObjectBridge.clearRegistry(); // Lua 对象桥句柄注册表随脚本一起释放
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
		FlxG.stage.removeEventListener(FocusEvent.FOCUS_IN, onStageActivate);
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
		HostDomain.clampGameplayTotals(this);
	}

	var offRatingProbe:Int = 0; // 非顶格评级采样计数（前 40 条，零持续开销）

	public static function cancelMusicFadeTween() {
		HostDomain.cancelMusicFadeTween();
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		NoteChartDomain.stepHit(this);
	}

	@:noCompletion public function meteoSuper_stepHit() return super.stepHit();

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		NoteChartDomain.beatHit(this);
	}

	@:noCompletion public function meteoSuper_beatHit() return super.beatHit();

	override function sectionHit()
	{
		NoteChartDomain.sectionHit(this);
	}

	@:noCompletion public function meteoSuper_sectionHit() return super.sectionHit();

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String):Bool return HostDomain.startLuasNamed(this, luaFile);
	#end
	
	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String):Bool return HostDomain.startHScriptsNamed(this, scriptFile);

	public function initHScript(file:String, ?extraVars:Map<String, Dynamic>) HostDomain.initHScript(this, file, extraVars);
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		return HostDomain.callOnScripts(this, funcToCall, args, ignoreStops, exclusions, excludeValues);
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		return HostDomain.callOnLuas(this, funcToCall, args, ignoreStops, exclusions, excludeValues);
	}
	
	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		return HostDomain.callOnHScript(this, funcToCall, args, ignoreStops, exclusions, excludeValues);
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		HostDomain.setOnScripts(this, variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		HostDomain.setOnLuas(this, variable, arg, exclusions);
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		HostDomain.setOnHScript(this, variable, arg, exclusions);
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) NoteChartDomain.strumPlayAnim(this, isDad, id, time);

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false) CameraHudDomain.RecalculateRating(this, badHit);

	function fullComboUpdate() CameraHudDomain.fullComboUpdate(this);

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null):String return HostDomain.checkForAchievement(this, achievesToCheck);
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	// Psych 0.7.3 兼容：mod（FunkinMix 等）的 runHaxeCode 用 game.FlxRuntimeShaderMap 缓存运行时 shader 实例
	public var FlxRuntimeShaderMap:Map<String, FlxRuntimeShader> = new Map<String, FlxRuntimeShader>();
	public function createRuntimeShader(name:String):FlxRuntimeShader return HostDomain.createRuntimeShader(this, name);

	public function initLuaShader(name:String, ?glslVersion:Int = 120):Bool return HostDomain.initLuaShader(this, name, glslVersion);
	#end

	// 联机（Meteoric Online）已整体移除：addOnlineHUD 对手面板 + 全部 OnlineDomain 转发桩函数均已删除。

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
	// 血条溢出图标飞出（iconFlyOverflow）：超出 100% 瞬间的向外冲量（负=沿填充方向滑出条外），
	// 随后被 100% 上限慢速拉回 —— 100% 上限原样保留，图标只是“飞出去再被拉回来”。
	// iconFlyTarget = 目标推出距离（只增不减，新爆发顶替旧目标）；iconFlyOff = 实际位移（向目标靠拢）
	var iconFlyTarget:Float = 0;
	var iconFlyOff:Float = 0;

	// 判定计数侧边栏：文本与着色缓存 —— 数值未变时跳过 setTextFormat，
	// 避免 OpenFL 每帧强制整段文字重排 + 纹理重传（高帧率下的主要隐藏开销）
	var lastJudgementTxt:String = '';
	var judgementCyan:openfl.text.TextFormat;
	var judgementLightRed:openfl.text.TextFormat;
	// 判定计数整数签名缓存（值未变化时连字符串构建都跳过）
	var _lastJudgHits:Int = -1;
	var _lastJudgCombo:Int = -1;
	var _lastJudgMisses:Int = -1;
	var _lastJudgMv:Int = -1;
	var _lastJudgSick:Int = -1;
	var _lastJudgGood:Int = -1;
	var _lastJudgBad:Int = -1;
	var _lastJudgShit:Int = -1;
	var _lastJudgTotal:Int = -1;
	var _lastJudgMarv:Bool = false;

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
		songTxt.text = st.curSong + " (" + st.storyDifficultyText + ") " + Lang.tOr('play.watermarkSuffix', "| 流星引擎 v") + Main.meVersion;

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

		// 行着色格式：复用同一实例（原实现每次 update 都 new 两个 TextFormat）
		judgementCyan = new openfl.text.TextFormat('VCR OSD Mono', 16, 0xFF00FFFF);
		judgementLightRed = new openfl.text.TextFormat('VCR OSD Mono', 16, 0xFFFF7777);

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
		// 小图标跳动回弹（backend/IconBop 单一实现点：样式 / 回弹曲线 / 切档清理都在那边）。
		// ⚠ 必须在本函数按 `150 * scale.x` 重算图标 x 的**之前**调用，否则缩放与 x 会错开一帧。
		// baseY 取 `healthBar.y - 75`，与 CameraHudDomain.hudRelayout 的定位口径一致（跳跃档在此之上叠加位移）。
		IconBop.update(iconP1, iconP2, elapsed, st.playbackRate, st.healthBar.y - 75);

		// botplay 标签呼吸
		if (botplayTxt != null && botplayTxt.visible)
		{
			st.botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * st.botplaySine) / 180);
		}

		// 图标强绑定血量条：x 跟随 barCenter，y 跟随血量条
		var iconOffset:Int = 26;
		// 血条溢出图标飞出（JS 引擎同款方向，不删 100% 上限）：血量超限（由 note 数量×density 驱动的
		// 回血）时，把“未钳制血量”换算成显示百分比（封顶 1000%）、目标推出距离按该比例设置，血量立刻
		// 钳回 2；随后目标慢速回归 0（飞回慢），图标实际位移向目标靠拢（开平滑血量=与血条同速平滑飞出/回）
		if (ClientPrefs.data.iconFlyOverflow)
		{
			var flyApplied:Bool = false;
			if (st.health > 2)
			{
				var spikePct:Float = Math.min(st.health / 2 * 100, 1000);
				st.healthDisplayPct = Math.max(st.healthDisplayPct, spikePct);
				// 目标推出距离按显示% 缩放；只增不减（新的更大爆发顶替旧目标）
				iconFlyTarget = Math.min(iconFlyTarget, -healthBar.barWidth * 0.6 * (spikePct / 100));
				st.health = 2; // 100% 上限原版保留
				flyApplied = true;
			}
			// 小型堆叠（density≥2）命中上报：即使没顶破 100% 也触发飞出，幅度 = 该堆叠提供的血量%
			if (st.pendingFlySpikePct > 0)
			{
				var stackPct:Float = Math.min(st.pendingFlySpikePct, 1000);
				st.healthDisplayPct = Math.max(st.healthDisplayPct, stackPct);
				iconFlyTarget = Math.min(iconFlyTarget, -healthBar.barWidth * 0.6 * (stackPct / 100));
				st.pendingFlySpikePct = 0;
				flyApplied = true;
			}
			if (flyApplied) st.updateScore(); // 立即刷新文本：让爆发值当帧可见（命中路径的 updateScore 早于本函数）
			// 飞回更快：目标以 rate 4.0 快速归零（τ≈0.25s）—— 爆发结束后约 0.8s 基本回位
			iconFlyTarget = FlxMath.lerp(iconFlyTarget, 0, FlxMath.bound(elapsed * 4.0 * st.playbackRate, 0, 1));
			// 实际位移向目标靠拢（飞出）rate 6.0：τ≈0.17s，600% 仍能清晰冲出条面再回
			// 越过条面再出屏（平滑血量/非平滑均走此平滑追赶，速度一致）
			iconFlyOff = FlxMath.lerp(iconFlyOff, iconFlyTarget, FlxMath.bound(elapsed * 6.0 * st.playbackRate, 0, 1));
			// 显示数字回落与图标节奏一致（τ≈0.83s）；基准 = 真实血量百分比
			var realPct:Float = st.health / 2 * 100;
			st.healthDisplayPct = FlxMath.lerp(st.healthDisplayPct, realPct, FlxMath.bound(elapsed * 1.2 * st.playbackRate, 0, 1));
		}
		else
		{
			iconFlyOff = 0;
			iconFlyTarget = 0;
			st.healthDisplayPct = st.health / 2 * 100;
		}
		// 跳动中心改为「中上」后，横向居中由 `origin` 自己完成，x 不再需要按 scale 补偿。
		// 旧公式里的 `+ (150*scale.x - 150)/2`（P1）与 `- (150*scale.x)/2`（P2）是按
		// 「支点 = 左上角」写的，且两式符号相反 —— P2 恰好居中、P1 却整体往右窜 ~17px。
		iconP1.x = healthBar.barCenter - iconOffset + iconFlyOff;
		iconP2.x = healthBar.barCenter - 75 - iconOffset * 2 + iconFlyOff;
		// 胜利小图标（OSEngine/FNF PR#138 语义）：3 帧 = [0 正常 / 1 劣势 / 2 胜利]，2 帧兼容旧图标
		iconP1.animation.curAnim.curFrame = iconFrame(iconP1, healthBar.percent, true);
		iconP2.animation.curAnim.curFrame = iconFrame(iconP2, healthBar.percent, false);

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

	/** 图标帧选择：3 帧 = [0 正常 / 1 劣势 / 2 胜利]；2 帧只到劣势。玩家与敌方互为镜像。 */
	static function iconFrame(icon:HealthIcon, percent:Float, isPlayer:Bool):Int
	{
		if (icon.iconFrames >= 3)
			return switch (isPlayer)
			{
				case true:  (percent < 20) ? 1 : ((percent > 80) ? 2 : 0);
				default:    (percent > 80) ? 1 : ((percent < 20) ? 2 : 0);
			}
		return isPlayer ? ((percent < 20) ? 1 : 0) : ((percent > 80) ? 1 : 0);
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

		// 可见性权威：隐藏时提前返回，不做任何字符串构建 / 文本操作（省每帧开销）
		var jcOff:Array<Float> = st.hudGetOffset('judgementTxt');
		judgementField.x = 10 + jcOff[0];
		judgementField.y = FlxG.height / 2 - 65 + jcOff[1];
		judgementField.visible = !ClientPrefs.data.hideHud && ClientPrefs.data.showJudgementCounter;
		if (!judgementField.visible) return;

		// —— 内容缓存：命中数/连击/评级没变时，text 与着色都无需重写。
		//    原实现每帧无条件 setTextFormat×3（OpenFL 每次都会置 __dirty/__layoutDirty，
		//    触发整段文字重排 + 纹理重传）——这是高帧率下 PlayState 的主要隐藏开销。 ——
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
		var hitsDisp:Int = I64.toIntSafe(st.songHits);
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

		// 【性能】整数签名比对：全部数值未变化时直接返回，连字符串都不构建
		// （判定计数每帧被调用，原实现每帧 new StringBuf + 8 段拼接）
		if (hitsDisp == _lastJudgHits && comboDisp == _lastJudgCombo && st.songMisses == _lastJudgMisses
			&& mv == _lastJudgMv && sick == _lastJudgSick && good == _lastJudgGood
			&& bad == _lastJudgBad && shit == _lastJudgShit
			&& st.totalNotes == _lastJudgTotal && ClientPrefs.data.marvelousJudgement == _lastJudgMarv)
			return;
		_lastJudgHits = hitsDisp; _lastJudgCombo = comboDisp; _lastJudgMisses = I64.toIntSafe(st.songMisses);
		_lastJudgMv = mv; _lastJudgSick = sick; _lastJudgGood = good; _lastJudgBad = bad; _lastJudgShit = shit;
		_lastJudgTotal = st.totalNotes; _lastJudgMarv = ClientPrefs.data.marvelousJudgement;

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

		// 文本未变化：直接返回（每帧构建一次字符串足够便宜，重排/上传才是大头）
		if (txt == lastJudgementTxt) return;
		lastJudgementTxt = txt;
		judgementField.text = txt;

		// 行着色：Hits / Combo 青色，Misses 浅红（openfl TextField 原生范围着色；
		// TextFormat 实例复用，不再每帧 new）
		var line2:Int = txt.indexOf('\n');
		if (line2 > 0) judgementField.setTextFormat(judgementCyan, 0, line2); // Hits
		var line3:Int = txt.indexOf('\n', line2 + 1);
		if (line3 > line2) judgementField.setTextFormat(judgementCyan, line2 + 1, line3); // Combo
		var lastStart:Int = txt.lastIndexOf('\n') + 1;
		if (lastStart > 0 && lastStart < txt.length)
			judgementField.setTextFormat(judgementLightRed, lastStart, txt.length); // Misses
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

		// 小图标跳动：清空每帧状态（跳跃档可能正停在半空、挤压档相位未走完）。
		// reset() 会把 lastStyle 置空 → 下一次 IconBop.update 走切档分支，
		// 顺带把图标强制归位（scale 1 / angle 0 / y 回基准），重开不会有残留姿态。
		IconBop.reset();
	}
}
