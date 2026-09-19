package states;

import backend.WeekData;
import backend.Highscore;

import flixel.input.keyboard.FlxKey;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.group.FlxGroup;
import flixel.input.gamepad.FlxGamepad;
import tjson.TJSON as Json;

import openfl.Assets;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.Lib;
import flixel.addons.display.FlxBackdrop;

import shaders.ColorSwap;

import states.StoryMenuState;
import states.OutdatedState;
import states.MainMenuState;

#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end

typedef TitleData =
{

	titlex:Float,
	titley:Float,
	startx:Float,
	starty:Float,
	gfx:Float,
	gfy:Float,
	backgroundSprite:String,
	bpm:Int,
	endY:Float
}

class TitleState extends MusicBeatState
{
	public static var muteKeys:Array<FlxKey> = [FlxKey.ZERO];
	public static var volumeDownKeys:Array<FlxKey> = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
	public static var volumeUpKeys:Array<FlxKey> = [FlxKey.NUMPADPLUS, FlxKey.PLUS];

	public static var initialized:Bool = false;

	var blackScreen:FlxSprite;
	var credGroup:FlxGroup;
	var textGroup:FlxGroup;
	var ngSpr:FlxSprite;
	
	// titleText 的呼吸色不再用固定色对：两端都取**当前主题色**（亮 ↔ 暗），
	// 见 update() 里的 themeDark(DesignTokens.primary)。原来的 [0xFF33FFFF, 0xFF3333CC]
	// 会在非青色主题下脉动出"另一种蓝"，与主题色打架。
	var titleTextAlphas:Array<Float> = [1, .64];

	var curWacky:Array<String> = [];

	var wackyImage:FlxSprite;

	#if TITLE_SCREEN_EASTER_EGG
	var easterEggKeys:Array<String> = [
		'SHADOW', 'RIVER', 'SHUBS', 'BBPANZU'
	];
	var allowedKeys:String = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
	var easterEggKeysBuffer:String = '';
	#end

	var mustUpdate:Bool = false;
	public static var mainUpdateCheck:Bool = false;
	public static var mainNewVer:String = '';

	var titleJSON:TitleData;

	public static var updateVersion:String = '';
	/** 远端校验索引（null = 没取到）。更新界面用它判断"远端是不是真的更新"。 */
	public static var onlineVersionIndex:Null<Int> = null;

	override public function create():Void
	{
		// 维护/CI 直达入口：设 ME_LUAGRAPH_SELFTEST=1 时直接进入 Lua 图形化编辑器并跑一遍自检
		// （不设置该环境变量时完全不触发，正常启动流程与玩家侧行为不受影响）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();
		
        Lib.application.window.title = "FNF':Meteoric Engine - Intro";

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = 60;
		FlxG.keys.preventDefaultKeys = [TAB];

		curWacky = FlxG.random.getObject(getIntroTextShit());

		super.create();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());

		ClientPrefs.loadPrefs();

		// 编程层启动：注册全局脚本/热重载信号，并为 TitleState 本体装一次状态脚本。
		// 必须放在 ClientPrefs.loadPrefs() 之后：总开关与子开关都从存档读取。
		#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
		#if meteoric_debug
		Sys.println('[CNE] TitleState integration reached; force=' + Sys.getEnv('METEORIC_CNE_FORCE'));
		#end
		bridge.CneBridge.programmingInit();
		bridge.CneBridge.programmingOnStateCreate(this);
		#end

		// 【帧率档位启动诊断】仅调试构建启用（编译脚本加 -debug / METEORIC_DEBUG=1 时定义
		// `meteoric_debug`；正式发布构建不编译这段，零开销、也不刷屏）。
		// 用途：Windows 上换 lime.ndll 时，靠这一行就能区分三种情形，不必再盲试——
		//   ① 档位=无上限 且 探测=无 → 补丁版 ndll 没被认出来（文件身份不匹配）
		//   ② 档位不是无上限        → 存档里还没选该档位（设置项问题）
		//   ③ 显示 100000 却仍卡住   → 引擎/原生确实到不了那个帧率
		#if (windows && meteoric_debug)
		Sys.println('[FRAMERATE] 档位=' + ClientPrefs.data.framerateMode
			+ ' 墙钟补丁探测=' + (ClientPrefs.hasWallclockFrameLoop() ? '有' : '无')
			+ ' 无上限档取值=' + ClientPrefs.unlimitedFramerateValue()
			+ ' update=' + FlxG.updateFramerate + ' draw=' + FlxG.drawFramerate);
		#end

		if(ClientPrefs.data.checkForUpdates && !closedState) {
			// 更新检查为异步回调（haxe.Http 不阻塞主线程），主线程发起、回调回主线程执行。
			// 不包后台线程：线程化会让回调里的字符串解析/分配在子线程执行，
			// 与主线程 GC 并发会破坏 hxcpp 堆 → SIGILL/SIGSEGV 无日志闪退（加载期崩溃同源）。
			#if sys
			try {
				checkForUpdates();
			} catch (e:Dynamic) {
				trace('update check crashed: $e');
			}
			#else
			checkForUpdates();
			#end
		}

		Highscore.load();

		// IGNORE THIS!!!
		titleJSON = Json.parse(Paths.getTextFromFile('images/gfDanceTitle.json'));

		#if TITLE_SCREEN_EASTER_EGG
		if (FlxG.save.data.psychDevsEasterEgg == null) FlxG.save.data.psychDevsEasterEgg = ''; //Crash prevention
		switch(FlxG.save.data.psychDevsEasterEgg.toUpperCase())
		{
			case 'SHADOW':
				titleJSON.gfx += 210;
				titleJSON.gfy += 40;
			case 'RIVER':
				titleJSON.gfx += 180;
				titleJSON.gfy += 40;
			case 'SHUBS':
				titleJSON.gfx += 160;
				titleJSON.gfy -= 10;
			case 'BBPANZU':
				titleJSON.gfx += 45;
				titleJSON.gfy += 100;
		}
		#end

		if(!initialized)
		{
			if(FlxG.save.data != null && FlxG.save.data.fullscreen)
			{
				FlxG.fullscreen = FlxG.save.data.fullscreen;
				//trace('LOADED FULLSCREEN SETTING!!');
			}
			persistentUpdate = true;
			persistentDraw = true;
		}

		if (FlxG.save.data.weekCompleted != null)
		{
			StoryMenuState.weekCompleted = FlxG.save.data.weekCompleted;
		}

		FlxG.mouse.visible = false;
		#if FREEPLAY
		MusicBeatState.switchState(new states.FreeplayState());
		#elseif CHARTING
		bridge.EditorBridge.openChartEditor();
		#else
		if(FlxG.save.data.flashing == null && !FlashingState.leftState) {
			MusicBeatState.switchState(new FlashingState());
		} else {
			if (initialized)
			{
				startIntro();

				// ── 返回路径（含从多版本容器返回）必须在这里补回标题音乐 ──
				// 根因：`FlxG.resetGame()` → `FlxGame.switchState()` → `FlxG.sound.destroy()`
				// 会把 `FlxG.sound.music` 置为 null（标题音乐没设 persist，会被销毁）；
				// 而**唯一**启动标题音乐的地方是 `beatHit()` 里的 `case 1: playMusic(...)`
				// （靠 sickBeats 从 1 开始计数）。没音乐 ⇒ `Conductor.songPosition` 永远 0
				// ⇒ `curStep` 永不递增 ⇒ `beatHit()` 永不触发 ⇒ sickBeats 永远是 0 —— 死锁。
				// 2026-09-11 实测：返回后 40 秒内 `musicNull=true`、`songPos` 冻在 3797、
				// `curStep/curBeat` 冻在 25/6，而 `frame` 持续增长（更新循环本身是好的）。
				// 这里直接判定并补播，音乐一响整条链自解，不动首次启动的既有流程。
				if (FlxG.sound.music == null)
				{
					FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
					FlxG.sound.music.fadeIn(4, 0, 0.7);
				}
			}
			else
			{
				new FlxTimer().start(1, function(tmr:FlxTimer)
				{
					startIntro();
				});
			}
		}
		#end

		// 【自动化冒烟：直达指定曲目】仅调试构建编译。用途：没有 UI/键盘自动化权限时，
		// 用环境变量把游戏直接送进某首歌，验证「模组装入 → 谱面/音频/人物加载」整条链路。
		//   METEORIC_TEST_SONG="happy|happy-hard|happy|2"   曲名|谱面名|目录名|难度索引
		// 必须放在 create() **末尾**：跳过 Highscore.load() 等既有初始化会让 PlayState
		// 在记分/周目状态缺失下崩溃（实测 2026-09-18 12:24 的 SEGV 就是提前 return 造成）。
		#if (meteoric_debug && sys)
		var testSong:String = Sys.getEnv('METEORIC_TEST_SONG');
		if (testSong != null && testSong.length > 0)
		{
			var parts:Array<String> = testSong.split('|');
			var tName:String = parts[0];
			var tJson:String = (parts.length > 1 && parts[1].length > 0) ? parts[1] : parts[0];
			var tFolder:String = (parts.length > 2 && parts[2].length > 0) ? parts[2] : parts[0];
			var tDiff:Null<Int> = (parts.length > 3) ? Std.parseInt(parts[3]) : 2;
			if (tDiff == null) tDiff = 2;
			Difficulty.resetList();
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = tDiff;
			Sys.println('[TEST] jump to song: ' + tName + ' | json=' + tJson + ' | folder=' + tFolder + ' | diff=' + tDiff
				+ ' | chart=' + Std.string(backend.Song.resolveChartPath(tJson, tFolder)));
			LoadingState.loadSongAndSwitchState(new PlayState(), Paths.formatToSongPath(tName), tJson, tFolder, true, new states.FreeplayState());
		}
		#end
	}

	function checkForUpdates()
	{
		var http = new haxe.Http("https://api.gitproxy.dev/github.com/Bonus-XK/FNF-MeteoricEngine/raw/refs/heads/master/gitVersion.txt");
		http.cnxTimeout = 4;

		http.onData = function (data:String)
		{
			var lines:Array<String> = data.split('\n');
			updateVersion = lines.length > 0 ? lines[0].trim() : '';
			var onlineIndex:Null<Int> = lines.length > 1 ? Std.parseInt(lines[1].trim()) : null;
			trace('version online: ' + updateVersion + ', online index: ' + onlineIndex + ', your index: ' + Main.meVersionIndex);
			mainNewVer = updateVersion;
			onlineVersionIndex = onlineIndex;
			// 【判定】只有远端索引**大于**本地才提示更新。
			// 曾用 `!= 比较` → 本地版本比远端新时（例如新版本已构建、gitVersion.txt 还没推上去）
			// 也会弹「发现新版本」，而且右栏画的是那个更旧的远端号，出现"最新版本 1.1.2 < 当前 1.1.3"。
			if (onlineIndex != null && onlineIndex > Main.meVersionIndex) {
				trace('versions arent matching!');
				mustUpdate = true;
				mainUpdateCheck = mustUpdate;
			}
			else if (onlineIndex != null && onlineIndex < Main.meVersionIndex) {
				trace('local build is ahead of published index (' + Main.meVersionIndex + ' > ' + onlineIndex + ') — no update prompt');
			}
		}

		http.onError = function (error) {
			trace('update check failed (gitproxy): $error, retrying direct...');
			var http2 = new haxe.Http("https://raw.githubusercontent.com/Bonus-XK/FNF-MeteoricEngine/master/gitVersion.txt");
			http2.cnxTimeout = 4;
			http2.onData = http.onData;
			http2.onError = function (error2) {
				trace('update check failed (direct): $error2');
			};
			http2.request();
		}

		http.request();
	}

	var logoBl:FlxSprite;
	var gfDance:FlxSprite;
	var danceLeft:Bool = false;
	var titleText:FlxSprite;
	var swagShader:ColorSwap = null;

	function startIntro()
	{
		if (!initialized)
		{
			if(FlxG.sound.music == null) {
				FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
			}
		}

		Conductor.bpm = titleJSON.bpm;
		persistentUpdate = true;

		var bg:FlxSprite = new FlxSprite();
		bg.antialiasing = ClientPrefs.data.antialiasing;

		if (titleJSON.backgroundSprite != null && titleJSON.backgroundSprite.length > 0 && titleJSON.backgroundSprite != "none"){
			bg.loadGraphic(Paths.image(titleJSON.backgroundSprite));
		}else{
			bg.makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		}

		// bg.setGraphicSize(Std.int(bg.width * 0.6));
		// bg.updateHitbox();
		add(bg);

		logoBl = new FlxSprite(titleJSON.titlex, titleJSON.titley);
		logoBl.frames = Paths.getSparrowAtlas('logoBumpin');
		logoBl.antialiasing = ClientPrefs.data.antialiasing;

		logoBl.animation.addByPrefix('bump', 'logo bumpin', 24, false);
		logoBl.animation.play('bump');
		logoBl.updateHitbox();
		// logoBl.screenCenter();
		// logoBl.color = FlxColor.BLACK;

		if(ClientPrefs.data.shaders) swagShader = new ColorSwap();
		gfDance = new FlxSprite(titleJSON.gfx, titleJSON.gfy);
		gfDance.antialiasing = ClientPrefs.data.antialiasing;

		var easterEgg:String = FlxG.save.data.psychDevsEasterEgg;
		if(easterEgg == null) easterEgg = ''; //html5 fix

		switch(easterEgg.toUpperCase())
		{
			// IGNORE THESE, GO DOWN A BIT
			#if TITLE_SCREEN_EASTER_EGG
			case 'SHADOW':
				gfDance.frames = Paths.getSparrowAtlas('ShadowBump');
				gfDance.animation.addByPrefix('danceLeft', 'Shadow Title Bump', 24);
				gfDance.animation.addByPrefix('danceRight', 'Shadow Title Bump', 24);
			case 'RIVER':
				gfDance.frames = Paths.getSparrowAtlas('RiverBump');
				gfDance.animation.addByIndices('danceLeft', 'River Title Bump', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], "", 24, false);
				gfDance.animation.addByIndices('danceRight', 'River Title Bump', [29, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], "", 24, false);
			case 'SHUBS':
				gfDance.frames = Paths.getSparrowAtlas('ShubBump');
				gfDance.animation.addByPrefix('danceLeft', 'Shubs Title Bump', 24, false);
				gfDance.animation.addByPrefix('danceRight', 'Shubs Title Bump', 24, false);
			case 'BBPANZU':
				gfDance.frames = Paths.getSparrowAtlas('BBBump');
				gfDance.animation.addByIndices('danceLeft', 'BB Title Bump', [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27], "", 24, false);
				gfDance.animation.addByIndices('danceRight', 'BB Title Bump', [27, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "", 24, false);
			#end

			default:
			//EDIT THIS ONE IF YOU'RE MAKING A SOURCE CODE MOD!!!!
			//EDIT THIS ONE IF YOU'RE MAKING A SOURCE CODE MOD!!!!
			//EDIT THIS ONE IF YOU'RE MAKING A SOURCE CODE MOD!!!!
				gfDance.frames = Paths.getSparrowAtlas('gfDanceTitle');
				gfDance.animation.addByIndices('danceLeft', 'gfDance', [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], "", 24, false);
				gfDance.animation.addByIndices('danceRight', 'gfDance', [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29], "", 24, false);
		}

		add(gfDance);
		add(logoBl);
		if(swagShader != null)
		{
			gfDance.shader = swagShader.shader;
			logoBl.shader = swagShader.shader;
		}

		titleText = new FlxSprite(titleJSON.startx, titleJSON.starty);
		titleText.frames = Paths.getSparrowAtlas('titleEnter');
		var animFrames:Array<FlxFrame> = [];
		@:privateAccess {
			titleText.animation.findByPrefix(animFrames, "ENTER IDLE");
			titleText.animation.findByPrefix(animFrames, "ENTER FREEZE");
		}
		
		if (animFrames.length > 0) {
			newTitle = true;
			
			titleText.animation.addByPrefix('idle', "ENTER IDLE", 24);
			titleText.animation.addByPrefix('press', ClientPrefs.data.flashing ? "ENTER PRESSED" : "ENTER FREEZE", 24);
		}
		else {
			newTitle = false;
			
			titleText.animation.addByPrefix('idle', "Press Enter to Begin", 24);
			titleText.animation.addByPrefix('press', "ENTER PRESSED", 24);
		}
		
		titleText.animation.play('idle');
		titleText.updateHitbox();
		// titleText.screenCenter(X);
		add(titleText);

		var logo:FlxSprite = new FlxSprite();
		// 强制 CPU 位图（allowGPU=false）：模组清理后 GPU 纹理缓存可能处于失效态（非空但不可用），
		// CPU 位图路径不经过 GPU 纹理，规避 FlxImageFrame 空引用崩溃
		var logoGraphic:FlxGraphic = Paths.imageFresh('logo');
		if (logoGraphic != null && logoGraphic.bitmap != null)
			logo.loadGraphic(logoGraphic);
		logo.antialiasing = ClientPrefs.data.antialiasing;
		logo.screenCenter();
		// add(logo);

		// FlxTween.tween(logoBl, {y: logoBl.y + 50}, 0.6, {ease: FlxEase.quadInOut, type: PINGPONG});
		// FlxTween.tween(logo, {y: logoBl.y + 50}, 0.6, {ease: FlxEase.quadInOut, type: PINGPONG, startDelay: 0.1});

		credGroup = new FlxGroup();
		add(credGroup);
		textGroup = new FlxGroup();

		blackScreen = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		credGroup.add(blackScreen);

		// 模组卸载/内存清理后贴图可能丢失：缺失或位图失效时不加载图形（保留空 sprite，不崩溃、不显示）
		ngSpr = new FlxSprite(0, FlxG.height * 0.50);
		var ngGraphic:FlxGraphic = Paths.imageFresh('newgrounds_logo'); // 强制全新加载（规避模组重启后的缓存失效态）
		if (ngGraphic != null && ngGraphic.bitmap != null)
			ngSpr.loadGraphic(ngGraphic);
		add(ngSpr);
		ngSpr.visible = false;
		ngSpr.alpha = 0;
		ngSpr.setGraphicSize(Std.int(ngSpr.width * 0.8));
		ngSpr.updateHitbox();
		ngSpr.screenCenter(X);
		ngSpr.antialiasing = ClientPrefs.data.antialiasing;

		if (initialized)
			skipIntro();
		else
			initialized = true;
	}

	function getIntroTextShit():Array<Array<String>>
	{
		#if MODS_ALLOWED
		var firstArray:Array<String> = Mods.mergeAllTextsNamed('data/introText.txt', Paths.getPreloadPath());
		#else
		var fullText:String = Assets.getText(Paths.txt('introText'));
		var firstArray:Array<String> = fullText.split('\n');
		#end
		var swagGoodArray:Array<Array<String>> = [];

		for (i in firstArray)
		{
			swagGoodArray.push(i.split('--'));
		}

		return swagGoodArray;
	}

	var transitioning:Bool = false;
	private static var playJingle:Bool = false;
	
	var newTitle:Bool = false;
	var titleTimer:Float = 0;

	var selfTestChecked:Bool = false;

	override function update(elapsed:Float)
	{
		// 维护/CI 直达入口：第一个 update 帧才切状态
		// （flixel 在某个 State 的 create() 期间切换状态不安全 —— 实测 SIGSEGV，栈里 create 从未进入）
		// 不设置 ME_LUAGRAPH_SELFTEST 时完全不触发，玩家侧行为不受影响
		if (!selfTestChecked)
		{
			selfTestChecked = true;
			if (bridge.LuaGraphBridge.selfTestRequested())
			{
				bridge.LuaGraphBridge.openEditor();
				return;
			}
		}

		if (FlxG.sound.music != null)
			Conductor.syncToMusic();
		// FlxG.watch.addQuick('amp', FlxG.sound.music.amplitude);

		var pressedEnter:Bool = FlxG.keys.justPressed.ENTER || controls.ACCEPT || FlxG.mouse.justPressed;

		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				pressedEnter = true;
			}
		}
		#end

		var gamepad:FlxGamepad = FlxG.gamepads.lastActive;

		if (gamepad != null)
		{
			if (gamepad.justPressed.START)
				pressedEnter = true;

			#if switch
			if (gamepad.justPressed.B)
				pressedEnter = true;
			#end
		}
		
		if (newTitle) {
			titleTimer += FlxMath.bound(elapsed, 0, 1);
			if (titleTimer > 2) titleTimer -= 2;
		}

		// EASTER EGG

		if (initialized && !transitioning && skippedIntro)
		{
			if (newTitle && !pressedEnter)
			{
				var timer:Float = titleTimer;
				if (timer >= 1)
					timer = (-timer) + 2;
				
				timer = FlxEase.quadInOut(timer);
				
				titleText.color = FlxColor.interpolate(DesignTokens.primary, themeDark(DesignTokens.primary), timer);
				titleText.alpha = FlxMath.lerp(titleTextAlphas[0], titleTextAlphas[1], timer);
			}
			
			if(pressedEnter)
			{
				titleText.color = FlxColor.WHITE;
				titleText.alpha = 1;
				
				if(titleText != null) titleText.animation.play('press');

				FlxG.camera.flash(ClientPrefs.data.flashing ? FlxColor.WHITE : 0x4CFFFFFF, 1);
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);

				transitioning = true;
				// FlxG.sound.music.stop();

				new FlxTimer().start(1, function(tmr:FlxTimer)
				{
					// updateNotify = 玩家在更新界面选了「不再提示」（或 设置→效果→更新提示 里关掉）：
					// 更新检查照旧进行，只是不再弹更新界面，直接进主菜单。
					if (mustUpdate && ClientPrefs.data.updateNotify) {
						MusicBeatState.switchState(new OutdatedState());
					} else {
						MusicBeatState.switchState(new MainMenuState());
					}
					closedState = true;
				});
				// FlxG.sound.play(Paths.music('titleShoot'), 0.7);
			}
			#if TITLE_SCREEN_EASTER_EGG
			else if (FlxG.keys.firstJustPressed() != FlxKey.NONE)
			{
				var keyPressed:FlxKey = FlxG.keys.firstJustPressed();
				var keyName:String = Std.string(keyPressed);
				if(allowedKeys.contains(keyName)) {
					easterEggKeysBuffer += keyName;
					if(easterEggKeysBuffer.length >= 32) easterEggKeysBuffer = easterEggKeysBuffer.substring(1);
					//trace('Test! Allowed Key pressed!!! Buffer: ' + easterEggKeysBuffer);

					for (wordRaw in easterEggKeys)
					{
						var word:String = wordRaw.toUpperCase(); //just for being sure you're doing it right
						if (easterEggKeysBuffer.contains(word))
						{
							//trace('YOOO! ' + word);
							if (FlxG.save.data.psychDevsEasterEgg == word)
								FlxG.save.data.psychDevsEasterEgg = '';
							else
								FlxG.save.data.psychDevsEasterEgg = word;
							FlxG.save.flush();

							FlxG.sound.play(Paths.sound('ToggleJingle'));

							var black:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
							black.alpha = 0;
							add(black);

							FlxTween.tween(black, {alpha: 1}, 1, {onComplete:
								function(twn:FlxTween) {
									MusicBeatState.switchState(new TitleState());
								}
							});
							FlxG.sound.music.fadeOut();
							if(FreeplayState.vocals != null)
							{
								FreeplayState.vocals.fadeOut();
							}
							closedState = true;
							transitioning = true;
							playJingle = true;
							easterEggKeysBuffer = '';
							break;
						}
					}
				}
			}
			#end
		}

		if (initialized && pressedEnter && !skippedIntro)
		{
			skipIntro();
		}

		if(swagShader != null)
		{
			if(controls.UI_LEFT) swagShader.hue -= elapsed * 0.1;
			if(controls.UI_RIGHT) swagShader.hue += elapsed * 0.1;
		}

		super.update(elapsed);
	}

	/**
	 * 由当前主题色派生"暗端"：向黑插值 55%（α 保留主色原值）。
	 * 用于 titleText 的呼吸脉动（亮主题色 ↔ 暗主题色），替代原先写死的深蓝 0xFF3333CC。
	 */
	function themeDark(primary:FlxColor):FlxColor
	{
		var mixed:Null<FlxColor> = FlxColor.interpolate(primary, (FlxColor.BLACK : FlxColor), 0.55);
		var c:FlxColor = (mixed == null) ? primary : mixed;
		return (c & 0x00FFFFFF) | (primary & 0xFF000000); // 保留主色 α，只改 RGB
	}

	// 开屏文字：逐行淡入上滑（大字标题用主题色高亮，普通文字白色，信息行灰色）
	function createCoolText(textArray:Array<String>, ?offset:Float = 0, ?size:Int = 30, ?color:Int = 0xFFFFFFFF)
	{
		for (i in 0...textArray.length)
		{
			var money:MenuText = new MenuText(0, 0, textArray[i], true, size);
			money.setFormat(Paths.font('future.ttf'), size, color, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			money.screenCenter(X);
			money.y += (i * 66) + 180 + offset;
			money.alpha = 0;
			money.y += 30;
			if(credGroup != null && textGroup != null) {
				credGroup.add(money);
				textGroup.add(money);
			}
			FlxTween.tween(money, {y: money.y - 30, alpha: 1}, 0.5, {ease: FlxEase.cubeOut, startDelay: i * 0.12});
		}
	}

	function addMoreText(text:String, ?offset:Float = 0, ?size:Int = 30, ?color:Int = 0xFFFFFFFF)
	{
		if(textGroup != null && credGroup != null) {
			var coolText:MenuText = new MenuText(0, 0, text, true, size);
			coolText.setFormat(Paths.font('future.ttf'), size, color, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			coolText.screenCenter(X);
			coolText.y += (textGroup.length * 66) + 180 + offset;
			coolText.alpha = 0;
			coolText.y += 30;
			credGroup.add(coolText);
			textGroup.add(coolText);
			FlxTween.tween(coolText, {y: coolText.y - 30, alpha: 1}, 0.5, {ease: FlxEase.cubeOut});
		}
	}

	// 开屏文字：淡出上滑后销毁，避免下一段文字出现时堆叠
	function deleteCoolText()
	{
		var oldTexts:Array<Dynamic> = textGroup.members.copy();
		textGroup.clear();
		for (txt in oldTexts)
		{
			if(txt == null || txt.destroyed) continue;
			credGroup.remove(txt, true);
			FlxTween.tween(txt, {alpha: 0, y: txt.y - 15}, 0.35, {ease: FlxEase.cubeIn, onComplete: function(twn:FlxTween) {
				if(txt != null && !txt.destroyed) txt.destroy();
			}});
		}
	}

	private var sickBeats:Int = 0; //Basically curBeat but won't be skipped if you hold the tab or resize the screen
	public static var closedState:Bool = false;
	override function beatHit()
	{
		super.beatHit();

		if(logoBl != null)
			logoBl.animation.play('bump', true);

		if(gfDance != null) {
			danceLeft = !danceLeft;
			if (danceLeft)
				gfDance.animation.play('danceRight');
			else
				gfDance.animation.play('danceLeft');
		}

		if(!closedState) {
			sickBeats++;
			switch (sickBeats)
			{
				case 1:
					FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
					FlxG.sound.music.fadeIn(4, 0, 0.7);
				case 2:
					createCoolText(['Meteoric Engine'], 40, 64, DesignTokens.primary);
				case 3:
					addMoreText('by Real-bonuX', 40, 26, 0xFFFFFFFF);
				case 4:
					addMoreText('版本 ' + Main.meVersion, 40, 22, 0xFF9A9A9A);
				case 5:
					deleteCoolText();
				case 6:
					createCoolText(['基于 Psych Engine 0.7.1h'], 30, 24, 0xFFAAAAAA);
				case 8:
					addMoreText('特别鸣谢', 30, 24, 0xFFAAAAAA);
					ngSpr.visible = true;
					ngSpr.alpha = 0;
					FlxTween.tween(ngSpr, {alpha: 1}, 0.4, {ease: FlxEase.cubeOut});
				case 9:
					deleteCoolText();
					ngSpr.visible = false;
				case 10:
					createCoolText([curWacky[0]], 60, 34, 0xFFFFFFFF);
				case 12:
					// 蓝色系文字统一跟随主题色（运行时读取，禁止 static final 冻结取值）
					addMoreText(curWacky[1], 60, 34, DesignTokens.primary);
				case 13:
					deleteCoolText();
				case 14:
					createCoolText(['Friday'], 60, 44, 0xFFFFFFFF);
				case 15:
					addMoreText('Night', 60, 44, DesignTokens.primary);
				case 16:
					addMoreText("Funkin'", 60, 44, 0xFFFFFFFF);
				case 17:
					skipIntro();
			}
		}
	}

	var skippedIntro:Bool = false;
	var increaseVolume:Bool = false;
	function skipIntro():Void
	{
		if (!skippedIntro)
		{
			// JS Engine 式 FNF 标志飞入：logo 从 titley（屏幕外下方）1.4s expoInOut 飞到 endY，
			// 同时带 ±4° 轻微摇摆（quartInOut 乒乓），返回/首次跳过 intro 时都会触发
			if (logoBl != null)
			{
				FlxTween.tween(logoBl, {y: titleJSON.endY}, 1.4, {ease: FlxEase.expoInOut});
				logoBl.angle = -4;
				FlxTween.angle(logoBl, -4, 4, 2, {ease: FlxEase.quartInOut, type: PINGPONG});
			}

			if (playJingle) //Ignore deez
			{
				var easteregg:String = FlxG.save.data.psychDevsEasterEgg;
				if (easteregg == null) easteregg = '';
				easteregg = easteregg.toUpperCase();

				var sound:FlxSound = null;
				switch(easteregg)
				{
					case 'RIVER':
						sound = FlxG.sound.play(Paths.sound('JingleRiver'));
					case 'SHUBS':
						sound = FlxG.sound.play(Paths.sound('JingleShubs'));
					case 'SHADOW':
						FlxG.sound.play(Paths.sound('JingleShadow'));
					case 'BBPANZU':
						sound = FlxG.sound.play(Paths.sound('JingleBB'));

					default: //Go back to normal ugly ass boring GF
						remove(ngSpr);
						remove(credGroup);
						FlxG.camera.flash(FlxColor.WHITE, 2);
						skippedIntro = true;
						playJingle = false;

						FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
						FlxG.sound.music.fadeIn(4, 0, 0.7);
						return;
				}

				transitioning = true;
				if(easteregg == 'SHADOW')
				{
					new FlxTimer().start(3.2, function(tmr:FlxTimer)
					{
						remove(ngSpr);
						remove(credGroup);
						FlxG.camera.flash(FlxColor.WHITE, 0.6);
						transitioning = false;
					});
				}
				else
				{
					remove(ngSpr);
					remove(credGroup);
					FlxG.camera.flash(FlxColor.WHITE, 3);
					sound.onComplete = function() {
						FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
						FlxG.sound.music.fadeIn(4, 0, 0.7);
						transitioning = false;
					};
				}
				playJingle = false;
			}
			else //Default! Edit this one!!
			{
				remove(ngSpr);
				remove(credGroup);
				FlxG.camera.flash(FlxColor.WHITE, 4);

				var easteregg:String = FlxG.save.data.psychDevsEasterEgg;
				if (easteregg == null) easteregg = '';
				easteregg = easteregg.toUpperCase();
				#if TITLE_SCREEN_EASTER_EGG
				if(easteregg == 'SHADOW')
				{
					FlxG.sound.music.fadeOut();
					if(FreeplayState.vocals != null)
					{
						FreeplayState.vocals.fadeOut();
					}
				}
				#end
			}
			skippedIntro = true;
		}
	}
}
