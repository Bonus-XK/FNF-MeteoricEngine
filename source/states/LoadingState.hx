package states;

import lime.app.Promise;
import lime.app.Future;

import flixel.FlxState;
import flixel.text.FlxText;
import flixel.addons.transition.FlxTransitionableState;

import objects.TimeBar;
import objects.Note;

import haxe.Json;

import openfl.media.Sound;
import openfl.utils.Assets;
import openfl.display.BitmapData;
import lime.utils.Assets as LimeAssets;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;

import backend.StageData;
import backend.Song;

import haxe.io.Path;

#if sys
import sys.thread.Thread;
import sys.FileSystem;
import sys.io.File;
import lime.media.AudioBuffer;
import lime.system.ThreadPool;
import lime.system.WorkOutput;
#end

class LoadingState extends MusicBeatState
{
	// 最小展示时间：只用来防止加载界面一闪而过，内容就绪后立即进入游戏
	inline static var MIN_TIME = 0.05;

	// Browsers will load create(), you can make your song load a custom directory there
	// If you're compiling to desktop (or something that doesn't use NO_PRELOAD_ALL), search for getNextState instead
	// I'd recommend doing it on both actually lol
	
	// TO DO: Make this easier
	
	var target:FlxState;
	var stopMusic = false;
	var directory:String;
	var callbacks:MultiCallback;

	// 待加载谱面信息（选歌时由 loadSongAndSwitchState 设置，加载完成后清空）
	public static var pendingSongName:String = null;
	public static var pendingChartJson:String = null;
	public static var pendingChartFolder:String = null;
	public static var pendingReturnState:FlxState = null;
	static var chartLoadId:Int = 0;

	// 选歌确认时提前启动的预载（与切场景并行，缩短加载时间）
	#if sys
	static var preloadChartThread:Thread = null;
	static var preloadThreadJson:String = null;
	static var chartMainThread:Thread = null;

	// 音频并行解码：自带线程池，Inst/Voices 同时解码，绕开 lime 单线程的文件池
	static var audioPool:ThreadPool = null;
	static var audioPreloads:Map<String, Bool> = [];
	static var audioPreloadCallbacks:Map<String, Void->Void> = [];

	// 人物等大图并行解码：与音频池互不干扰，解码完成的 BitmapData 交给 Paths.pendingBitmaps 供主线程消费
	static var imagePool:ThreadPool = null;
	static var charPreloads:Array<String> = [];
	static var charPreloadCallbacks:Map<String, Void->Void> = [];
	#end

	#if sys
	var chartThread:Thread = null;
	#end
	var introComplete:Void->Void = null;
	var introFired:Bool = false;
	var loadElapsed:Float = 0;
	var chartDone:Void->Void = null;
	var chartMessage:SwagSong = null;
	var loadFailed:Bool = false;
	var chartError:String = null;
	var chartLoaded:Bool = false;

	var songTitleText:FlxText;
	var diffText:FlxText;
	var loadBar:TimeBar;
	var percentText:FlxText;
	var loadProgress:Float = 0;
	var statusText:FlxText;
	var errorText:FlxText;
	var dotsTimer:Float = 0;
	var dotsCount:Int = 0;

	function new(target:FlxState, stopMusic:Bool, directory:String)
	{
		super();
		this.target = target;
		this.stopMusic = stopMusic;
		this.directory = directory;
	}

	override function create()
	{
		// 加载界面不调用 MusicBeatState.create()，这里单独清理（先清理再加载，避免误删）
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory(false); // 加载途中不做 System.gc()，避免卡住主线程

		// ---- 背景（与主界面一致）----
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		var topLine:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, 4, 0xFF33E0FF);
		topLine.alpha = 0.85;
		add(topLine);

		// ---- 歌名 + 难度 ----
		var displayName:String = prettyName(pendingSongName != null ? pendingSongName : (PlayState.SONG != null ? Paths.formatToSongPath(PlayState.SONG.song) : ''));
		songTitleText = new FlxText(0, 250, FlxG.width, displayName, 48);
		songTitleText.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		songTitleText.scrollFactor.set();
		add(songTitleText);

		var diffNameText:String = pendingChartJson != null ? getDiffName(pendingChartJson, pendingSongName != null ? pendingSongName : '') : '';
		diffText = new FlxText(0, 318, FlxG.width, diffNameText, 22);
		diffText.setFormat(Paths.font('future.ttf'), 22, 0xFF33E0FF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		diffText.scrollFactor.set();
		add(diffText);

		// ---- 进度条（与游戏内时间条同款组件：黑色圆角底 + 双色填充）----
		loadBar = new TimeBar(0, 408, function() return loadProgress, 0, 1, true);
		loadBar.scrollFactor.set();
		loadBar.screenCenter(X);
		// 已走过 = 青色，未走过 = 深灰（黑色圆角底上清晰可见）
		loadBar.setColors(0xFF33E0FF, 0xFF1C2230);
		add(loadBar);

		// ---- 百分比 ----
		percentText = new FlxText(loadBar.x + Std.int(loadBar.bg.width) + 18, loadBar.y - 4, 0, '0%', 28);
		percentText.setFormat(Paths.font('future.ttf'), 28, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		percentText.scrollFactor.set();
		add(percentText);

		// ---- 状态文字 ----
		statusText = new FlxText(0, 452, FlxG.width, '', 18);
		statusText.setFormat(Paths.font('future.ttf'), 18, 0xFF3A4350, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.scrollFactor.set();
		add(statusText);

		// ---- 底部版本 ----
		var versionText:FlxText = new FlxText(0, FlxG.height - 32, FlxG.width, 'Meteoric Engine', 14);
		versionText.setFormat(Paths.font('future.ttf'), 14, 0xFF5A6472, CENTER);
		versionText.scrollFactor.set();
		add(versionText);

		// ---- 错误文字 ----
		errorText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		errorText.setFormat(Paths.font("future.ttf"), 24, 0xFFFF6B6B, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		errorText.scrollFactor.set();
		errorText.visible = false;
		add(errorText);
		
		#if sys
		// 桌面端：音频直接从文件并行解码，不需要等 songs 资源清单
		startLoading();
		if (LimeAssets.getLibrary("songs") == null)
			initSongsManifest().onComplete(function(_) {}).onError(function(_) {}); // 后台预载清单，仅作兜底
		#else
		// songs 资源库已就绪就直接开工，省掉一帧异步等待
		if (LimeAssets.getLibrary("songs") == null)
			initSongsManifest().onComplete(function(lib) startLoading()).onError(function(_) {});
		else
			startLoading();
		#end
	}

	function startLoading()
	{
		callbacks = new MultiCallback(onLoad);
		introComplete = callbacks.add("introComplete");

		// 谱面尚未解析（或正在加载的谱面与当前 SONG 不同）：放到后台线程加载，不卡主线程
		if (pendingChartJson != null && (PlayState.SONG == null || pendingSongName != PlayState.SONG.song))
		{
			chartDone = callbacks.add("chart");
			#if sys
			// 选歌时已提前开跑的线程直接复用
			startChartPreload();
			chartThread = preloadChartThread;
			preloadChartThread = null;
			if (chartThread == null)
			{
				chartError = '谱面文件不存在：' + pendingChartJson;
				onChartLoadFailed();
			}
			#else
			chartLoadId++;
			var myLoadId:Int = chartLoadId;
			var filePath:String = Song.resolveChartPath(pendingChartJson, pendingChartFolder);
			if (filePath == null)
			{
				chartError = '谱面文件不存在：' + pendingChartJson;
				onChartLoadFailed();
			}
			else
			{
				// 非桌面平台没有线程：直接在加载界面里同步解析
				try
				{
					chartMessage = Song.loadFromFile(filePath, pendingChartJson == 'events');
					onChartLoaded();
				}
				catch(e:Dynamic)
				{
					chartError = Std.string(e);
					onChartLoadFailed();
				}
			}
			#end
		}
		else chartLoaded = true;

		// 谱面已就绪（缓存命中/重开同曲）且烘焙未完成：直接在加载界面预烘焙音符贴图
		// （等 shared 库就绪再执行，否则音符贴图解析全部失败）
		if (ClientPrefs.data.preRenderNotes && PlayState.SONG != null
			&& (pendingChartJson == null || pendingSongName == PlayState.SONG.song)
			&& !Note.chartBakesReady())
		{
			var cb:Void->Void = callbacks.add('prerender');
			whenSharedReady(function() {
				Note.preRenderChartNotes();
				if (cb != null) cb();
			});
		}

		// 谱面已就绪（缓存命中/重开同曲）：加载空闲期预生成音符，进入游戏后直接复用
		if (PlayState.SONG != null && (pendingChartJson == null || pendingSongName == PlayState.SONG.song))
			whenSharedReady(function() { startPreGen(); });

		// 音频加载：后台线程并行解码，不冻结主线程，并且每个文件都计入进度
		var songToLoad:String = pendingSongName != null ? pendingSongName : (PlayState.SONG != null ? PlayState.SONG.song : null);
		if (songToLoad != null)
		{
			#if sys
			startSongPreload(songToLoad);
			registerAudioWaits(songToLoad);
			#else
			preloadSongAudioAsync(songToLoad);
			#end
		}

		checkLibrary("shared");
		if(directory != null && directory.length > 0 && directory != 'shared') {
			checkLibrary('week_assets');
		}
	}

	#if sys
	// 后台线程解析谱面（选歌确认时或加载界面里调用，主线程轮询消息）
	static function startChartPreload()
	{
		if (pendingChartJson == null) return;
		if (preloadChartThread != null && preloadThreadJson == pendingChartJson) return;

		var filePath:String = Song.resolveChartPath(pendingChartJson, pendingChartFolder);
		if (filePath == null) return;

		var isEvents:Bool = pendingChartJson == 'events';
		preloadThreadJson = pendingChartJson;
		chartLoadId++;
		var myLoadId:Int = chartLoadId;
		chartMainThread = Thread.current();
		preloadChartThread = Thread.create(function()
		{
			var result:Dynamic;
			try
			{
				result = {ok: true, loadId: myLoadId, song: Song.loadFromFile(filePath, isEvents)};
			}
			catch(e:Dynamic)
			{
				result = {ok: false, loadId: myLoadId, error: Std.string(e)};
			}
			chartMainThread.sendMessage(result);
		});
	}

	// 选歌确认时提前启动的预载：谱面线程 + 伴奏/人声并行解码
	static function startSongPreload(songName:String)
	{
		startChartPreload();
		for (file in getSongAudioFiles(songName))
			decodeSoundAsync(file);
	}

	static function getSongAudioFiles(songName:String):Array<String>
	{
		var songPath:String = Paths.formatToSongPath(songName);
		var files:Array<String> = ['assets/songs/' + songPath + '/Inst.' + Paths.SOUND_EXT];
		if (Song.voicesFileExists(songName))
			files.push('assets/songs/' + songPath + '/Voices.' + Paths.SOUND_EXT);

		#if MODS_ALLOWED
		for (i in 0...files.length)
		{
			var key:String = songPath + (i == 0 ? '/Inst' : '/Voices');
			var modsFile:String = Paths.modsSounds('songs', key);
			if (FileSystem.exists(modsFile)) files[i] = modsFile;
		}
		#end
		return files;
	}

	// 把单个音频文件提交到并行解码池（已在缓存或已在解码则跳过）
	static function decodeSoundAsync(file:String)
	{
		if (Paths.currentTrackedSounds.exists(file)) return;
		if (audioPreloads.exists(file)) return;
		if (!FileSystem.exists(file)) return;

		audioPreloads.set(file, true);
		if (audioPool == null)
		{
			audioPool = new ThreadPool(0, 2);
			audioPool.onComplete.add(audioDecodeComplete);
		}
		audioPool.run(audioDecodeWork, file);
	}

	static function audioDecodeWork(state:Dynamic, output:WorkOutput)
	{
		var file:String = Std.string(state);
		var buffer:AudioBuffer = null;
		try { buffer = AudioBuffer.fromFile(file); } catch(e:Dynamic) {}
		output.sendComplete({file: file, buffer: buffer});
	}

	// 主线程回调：解码完成 → 写入缓存并触发等待回调
	static function audioDecodeComplete(message:Dynamic)
	{
		if (message == null) return;
		var file:String = Reflect.field(message, 'file');
		var buffer:AudioBuffer = Reflect.field(message, 'buffer');
		if (file == null) return;

		audioPreloads.remove(file);
		if (buffer != null)
		{
			try
			{
				Paths.currentTrackedSounds.set(file, Sound.fromAudioBuffer(buffer));
				Paths.localTrackedAssets.push(file);
			}
			catch(e:Dynamic) {}
		}

		var cb:Void->Void = audioPreloadCallbacks.get(file);
		if (cb != null)
		{
			audioPreloadCallbacks.remove(file);
			cb();
		}
	}

	// 谱面解析完成后：并行解码 gf/dad/bf 三人的人物贴图（不阻塞主线程，PlayState 创建人物时命中缓存）
	function startCharPreload()
	{
		if (PlayState.SONG == null) return;
		var names:Array<String> = [PlayState.SONG.gfVersion, PlayState.SONG.player2, PlayState.SONG.player1];
		for (name in names)
			if (name != null && name.length > 0 && !charPreloads.contains(name))
				charPreloads.push(name);

		if (charPreloads.length < 1) return;
		if (imagePool == null)
		{
			imagePool = new ThreadPool(0, 2);
			imagePool.onComplete.add(imageDecodeComplete);
		}
		for (name in charPreloads)
		{
			// 人物贴图也算入加载进度：全部解码完成才进入游戏，避免 PlayState 里再同步解码大图
			charPreloadCallbacks.set(name, callbacks.add('img:$name'));
			imagePool.run(charDecodeWork, name);
		}
	}

	static function charDecodeWork(state:Dynamic, output:WorkOutput)
	{
		var charName:String = Std.string(state);
		var characterPath:String = 'characters/' + charName + '.json';
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(characterPath);
		if (!FileSystem.exists(path)) path = Paths.getPreloadPath(characterPath);
		#else
		var path:String = Paths.getPreloadPath(characterPath);
		#end
		if (!FileSystem.exists(path))
		{
			output.sendComplete({name: charName, file: null, bmp: null});
			return;
		}

		try
		{
			var json:Dynamic = haxe.Json.parse(File.getContent(path));
			var imgKey:String = Reflect.field(json, 'image');
			if (imgKey == null || imgKey.length < 1)
			{
				output.sendComplete({name: charName, file: null, bmp: null});
				return;
			}

			#if MODS_ALLOWED
			var file:String = Paths.modsImages(imgKey);
			if (!FileSystem.exists(file))
				file = Paths.getPath('images/' + imgKey + '.png', IMAGE);
			#else
			var file:String = Paths.getPath('images/' + imgKey + '.png', IMAGE);
			#end
			if (FileSystem.exists(file))
			{
				var bmp:BitmapData = BitmapData.fromFile(file);
				output.sendComplete({name: charName, file: file, bmp: bmp});
				return;
			}
		}
		catch(e:Dynamic) {}
		output.sendComplete({name: charName, file: null, bmp: null});
	}

	// 主线程回调：把解码完成的大图放入预载缓存，等 PlayState 消费
	static function imageDecodeComplete(message:Dynamic)
	{
		if (message == null) return;
		var name:String = Reflect.field(message, 'name');
		var file:String = Reflect.field(message, 'file');
		var bmp:BitmapData = Reflect.field(message, 'bmp');
		if (file != null && bmp != null)
		{
			// 两个角色共用同一张贴图时，后到的直接释放，避免大图残留
			if (Paths.pendingBitmaps.exists(file))
				bmp.dispose();
			else
				Paths.pendingBitmaps.set(file, bmp);
		}
		if (name != null && charPreloadCallbacks.exists(name))
		{
			var cb:Void->Void = charPreloadCallbacks.get(name);
			charPreloadCallbacks.remove(name);
			if (cb != null) cb();
		}
	}

	// 为仍在解码中的音频注册进度回调（解码完成的直接命中缓存，无需等待）
	function registerAudioWaits(songName:String)
	{
		for (file in getSongAudioFiles(songName))
		{
			if (!Paths.currentTrackedSounds.exists(file) && audioPreloads.exists(file))
				audioPreloadCallbacks.set(file, callbacks.add('song:$file'));
		}
	}
	#end

	#if !sys
	// 异步预加载歌曲音频到 Paths.currentTrackedSounds：PlayState.generateSong 会直接命中缓存，不再卡顿
	function preloadSongAudioAsync(songName:String)
	{
		var songPath:String = Paths.formatToSongPath(songName);
		preloadSoundAsync('songs', songPath + '/Inst', songName, true);
		if (Song.voicesFileExists(songName))
			preloadSoundAsync('songs', songPath + '/Voices', songName, false);
	}

	function preloadSoundAsync(path:String, key:String, songName:String, isInst:Bool)
	{
		#if MODS_ALLOWED
		// 模组音频：优先走资源清单异步加载，不在清单里则保底同步读取
		var modsFile:String = Paths.modsSounds(path, key);
		if (FileSystem.exists(modsFile))
		{
			if (!Paths.currentTrackedSounds.exists(modsFile))
			{
				if (Assets.exists(modsFile, SOUND))
				{
					var cb = callbacks.add('song:$modsFile');
					Assets.loadSound(modsFile).onComplete(function(sound)
					{
						Paths.currentTrackedSounds.set(modsFile, sound);
						Paths.localTrackedAssets.push(modsFile);
						cb();
					}).onError(function(_) { cb(); });
				}
				else
				{
					Paths.currentTrackedSounds.set(modsFile, Sound.fromFile(modsFile));
					Paths.localTrackedAssets.push(modsFile);
				}
			}
			return;
		}
		#end

		// 官方曲目：assets/songs/... 属于 songs 资源库
		var assetKey:String = 'assets/' + path + '/' + key + '.' + Paths.SOUND_EXT;
		if (Paths.currentTrackedSounds.exists(assetKey)) return;
		var assetId:String = path + ':' + assetKey;

		if (Assets.cache.hasSound(assetId))
		{
			// 已在缓存里（例如刚试听过）：直接登记，避免二次解码
			try
			{
				if (isInst) Paths.inst(songName); else Paths.voices(songName);
			}
			catch(e:Dynamic) {}
			return;
		}

		var callback = callbacks.add('song:$assetKey');
		Assets.loadSound(assetId).onComplete(function(sound)
		{
			Paths.currentTrackedSounds.set(assetKey, sound);
			Paths.localTrackedAssets.push(assetKey);
			callback();
		}).onError(function(_) { callback(); });
	}
	#end

	static function prettyName(songPath:String):String
	{
		if (songPath == null || songPath.length < 1) return '';
		var words:Array<String> = songPath.split('-');
		for (i in 0...words.length)
			if (words[i].length > 0)
				words[i] = words[i].substr(0, 1).toUpperCase() + words[i].substr(1);
		return words.join(' ');
	}

	static function getDiffName(jsonInput:String, songName:String):String
	{
		if (jsonInput == null || songName == null || jsonInput.length <= songName.length) return '普通';
		var suffix:String = jsonInput.substr(songName.length);
		return switch(suffix)
		{
			case '' | '-normal' | '-normal-': '普通';
			case '-easy': '简单';
			case '-hard': '困难';
			default: suffix.length > 1 ? suffix.substr(1) : '普通';
		};
	}

	function onChartLoaded()
	{
		PlayState.SONG = chartMessage;
		chartLoaded = true;
		clearPendingChart();
		pendingReturnState = null;

		// 主线程处理舞台目录与资源库（后台线程里不允许触碰这些状态）
		StageData.loadDirectory(PlayState.SONG);
		var stageDir:String = StageData.forceNextDirectory;
		if (stageDir != null && stageDir.length > 0)
		{
			Paths.setCurrentLevel(stageDir);
			if (stageDir != 'shared' && callbacks != null)
				checkLibrary('week_assets');
		}

		if (chartDone != null) chartDone();

		#if sys
		startCharPreload();
		#end

		// 提前渲染：主线程预烘焙所有音符贴图（进度计入加载条）
		if (ClientPrefs.data.preRenderNotes)
		{
			var cb:Void->Void = callbacks != null ? callbacks.add('prerender') : null;
			whenSharedReady(function() {
				Note.preRenderChartNotes();
				if (cb != null) cb();
			});
		}
		else
			whenSharedReady(function() {});

		// 提前生成：利用等待音频解码/角色预载的空闲期构建整张谱面的音符（大谱面省去进入后 500ms+）
		whenSharedReady(function() { startPreGen(); });
	}

	// shared 库就绪后再执行回调：音符贴图等 shared 资源依赖它，
	// 未加载完成时 OpenFlAssets.exists/getBitmapData 全部失败（懒加载库未注册）。
	// 已就绪则同步立即执行；未就绪则异步等 loadLibrary 完成（chart 与 shared 并行加载，互不阻塞）。
	static function whenSharedReady(cb:Void->Void):Void
	{
		if (Assets.getLibrary('shared') != null)
		{
			cb();
			return;
		}
		Assets.loadLibrary('shared').onComplete(function(_) { cb(); });
	}

	// 加载空闲期预生成音符（同步执行，进度计入加载条；失败自动回退创建期生成）
	function startPreGen()
	{
		var cb:Void->Void = callbacks != null ? callbacks.add('pregen') : null;
		PlayState.preGenerateChart();
		if (cb != null) cb();
	}

	function onChartLoadFailed()
	{
		clearPendingChart();
		loadFailed = true;
		errorText.text = '谱面加载失败：\n$chartError';
		errorText.screenCenter();
		errorText.visible = true;
		statusText.text = '';
	}

	static function clearPendingChart()
	{
		pendingSongName = null;
		pendingChartJson = null;
		pendingChartFolder = null;
	}

	function checkLibrary(library:String) {
		trace(Assets.hasLibrary(library));
		if (Assets.getLibrary(library) == null)
		{
			@:privateAccess
			if (!LimeAssets.libraryPaths.exists(library))
				throw "Missing library: " + library;

			var callback = callbacks.add("library:" + library);
			Assets.loadLibrary(library).onComplete(function (_) { callback(); });
		}
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		#if sys
		// 轮询后台谱面解析线程（非阻塞）
		if (chartThread != null && chartMessage == null && chartError == null)
		{
			var msg:Dynamic = Thread.readMessage(false);
			if (msg != null)
			{
				// 跳过上一个加载线程的残留消息
				if (msg.loadId != chartLoadId) return;
				chartThread = null;
				if (msg.ok == true)
				{
					chartMessage = msg.song;
					onChartLoaded();
				}
				else
				{
					chartError = Std.string(msg.error);
					onChartLoadFailed();
				}
			}
		}
		#end

		// 内容全部加载完成（只剩 introComplete 未触发）→ 不再等固定时长，立即进入
		loadElapsed += elapsed;
		if (callbacks != null && !introFired && !loadFailed && callbacks.numRemaining <= 1 && loadElapsed >= MIN_TIME)
		{
			introFired = true;
			loadProgress = 1;
			introComplete();
		}

		if (loadFailed && (FlxG.keys.justPressed.ESCAPE || controls.ACCEPT))
		{
			var ret:FlxState = pendingReturnState != null ? pendingReturnState : new FreeplayState();
			pendingReturnState = null;
			MusicBeatState.switchState(ret);
			return;
		}

		// 状态文字动态点
		dotsTimer += elapsed;
		if (dotsTimer >= 0.35)
		{
			dotsTimer = 0;
			dotsCount = (dotsCount + 1) % 4;
		}
		var dots:String = '';
		for (i in 0...dotsCount) dots += '.';
		if (!loadFailed)
			statusText.text = (chartLoaded ? '即将开始' : '正在解析谱面') + dots;

		if(callbacks != null) {
			// 加载完成后直接补满到 100%，避免渐进接近拖慢进入时机
			if (callbacks.numRemaining <= 1)
				loadProgress = 1;
			else
			{
				var targetShit:Float = FlxMath.remapToRange(callbacks.numRemaining / callbacks.length, 1, 0, 0, 1);
				loadProgress += 0.5 * (targetShit - loadProgress);
			}
			percentText.text = Std.int(loadProgress * 100) + '%';
		}
	}
	
	function onLoad()
	{
		#if sys
		charPreloads = [];
		charPreloadCallbacks = [];
		#end
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// 跳过进出加载界面的过渡动画，加载完立即进入目标状态
		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		// 必须经过 getNextState：它会根据舞台目录设置 Paths.currentLevel（资源库），
		// 否则 currentLevel 为 null 时 shared 资源库里的贴图（血量条、倒计时、判定等）全部解析失败
		MusicBeatState.switchState(getNextState(target, stopMusic));
	}
	
	static function getSongPath()
	{
		return Paths.inst(PlayState.SONG.song);
	}
	
	static function getVocalPath()
	{
		return Paths.voices(PlayState.SONG.song);
	}
	
	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false)
	{
		MusicBeatState.switchState(getNextState(target, stopMusic));
	}

	// 选歌用：记录待加载谱面并切状态。谱面文件不存在时返回 false（调用方自行提示）。
	inline static public function loadSongAndSwitchState(target:FlxState, songName:String, jsonInput:String, folder:String, stopMusic = false, ?returnState:FlxState = null):Bool
	{
		if (Song.resolveChartPath(jsonInput, folder) == null) return false;

		pendingSongName = songName;
		pendingChartJson = jsonInput;
		pendingChartFolder = folder;
		pendingReturnState = returnState;

		#if sys
		// 提前并行启动谱面解析与音频解码（与切场景同一帧开始，加载界面只需等待收尾）
		startSongPreload(songName);
		#end

		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		MusicBeatState.switchState(getNextState(target, stopMusic));
		return true;
	}
	
	static function getNextState(target:FlxState, stopMusic = false):FlxState
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		// 有待加载谱面
		if (pendingChartJson != null)
		{
			// 谱面缓存命中：直接使用解析结果
			var cached:SwagSong = Song.tryLoadFromCache(pendingChartJson, pendingChartFolder);
			if (cached != null)
			{
				PlayState.SONG = cached;
				clearPendingChart();
				// 缓存快速进入也按当前谱面舞台设置资源库，避免舞台贴图解析到 shared 而消失
				StageData.loadDirectory(PlayState.SONG);
				weekDir = StageData.forceNextDirectory;
				StageData.forceNextDirectory = null;
				if(weekDir != null && weekDir.length > 0 && weekDir != '') directory = weekDir;
				Paths.setCurrentLevel(directory);

				// 谱面与音频都已在缓存（如刚试听过）：直接进入游戏，跳过加载界面
				if (Song.songAudioCached(PlayState.SONG.song)
					&& (!ClientPrefs.data.preRenderNotes || Note.chartBakesReady()))
				{
					pendingReturnState = null;
					#if NO_PRELOAD_ALL
					if (isSoundLoaded(getSongPath()) && (!PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath())))
					#end
					{
						if (stopMusic && FlxG.sound.music != null)
							FlxG.sound.music.stop();
						return target;
					}
				}
			}
			return new LoadingState(target, stopMusic, directory);
		}

		// 无待加载谱面（如重进测试）：沿用当前谱面的舞台目录，避免资源库错设为 shared
		if((weekDir == null || weekDir.length < 1 || weekDir == '') && PlayState.SONG != null)
		{
			StageData.loadDirectory(PlayState.SONG);
			weekDir = StageData.forceNextDirectory;
			StageData.forceNextDirectory = null;
		}
		if(weekDir != null && weekDir.length > 0 && weekDir != '') directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);

		#if NO_PRELOAD_ALL
		var loaded:Bool = false;
		if (PlayState.SONG != null) {
			loaded = isSoundLoaded(getSongPath()) && (!PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath())) && isLibraryLoaded("shared") && isLibraryLoaded('week_assets');
		}
		
		if (!loaded || (ClientPrefs.data.preRenderNotes && PlayState.SONG != null && !Note.chartBakesReady()))
			return new LoadingState(target, stopMusic, directory);
		#end
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();
		
		return target;
	}
	
	#if NO_PRELOAD_ALL
	static function isSoundLoaded(path:String):Bool
	{
		trace(path);
		return Assets.cache.hasSound(path);
	}
	
	static function isLibraryLoaded(library:String):Bool
	{
		return Assets.getLibrary(library) != null;
	}
	#end
	
	override function destroy()
	{
		#if sys
		// 丢弃等待回调：解码仍在后台进行，完成后只缓存音频，不再触发已销毁的界面
		audioPreloadCallbacks = [];
		// 重置静态预载状态，避免第二次加载同一首歌时复用旧线程/旧缓存导致崩溃
		preloadChartThread = null;
		preloadThreadJson = null;
		chartMainThread = null;
		audioPreloads = [];
		charPreloads = [];
		charPreloadCallbacks = [];
		#end
		super.destroy();
		
		callbacks = null;
		chartThread = null;
	}
	
	static function initSongsManifest()
	{
		var id = "songs";
		var promise = new Promise<AssetLibrary>();

		var library = LimeAssets.getLibrary(id);

		if (library != null)
		{
			return Future.withValue(library);
		}

		var path = id;
		var rootPath = null;

		@:privateAccess
		var libraryPaths = LimeAssets.libraryPaths;
		if (libraryPaths.exists(id))
		{
			path = libraryPaths[id];
			rootPath = Path.directory(path);
		}
		else
		{
			if (StringTools.endsWith(path, ".bundle"))
			{
				rootPath = path;
				path += "/library.json";
			}
			else
			{
				rootPath = Path.directory(path);
			}
			@:privateAccess
			path = LimeAssets.__cacheBreak(path);
		}

		AssetManifest.loadFromFile(path, rootPath).onComplete(function(manifest)
		{
			if (manifest == null)
			{
				promise.error("Cannot parse asset manifest for library \"" + id + "\"");
				return;
			}

			var library = AssetLibrary.fromManifest(manifest);

			if (library == null)
			{
				promise.error("Cannot open library \"" + id + "\"");
			}
			else
			{
				@:privateAccess
				LimeAssets.libraries.set(id, library);
				library.onChange.add(LimeAssets.onChange.dispatch);
				promise.completeWith(Future.withValue(library));
			}
		}).onError(function(_)
		{
			promise.error("There is no asset library with an ID of \"" + id + "\"");
		});

		return promise.future;
	}
}

class MultiCallback
{
	public var callback:Void->Void;
	public var logId:String = null;
	public var length(default, null) = 0;
	public var numRemaining(default, null) = 0;
	
	var unfired = new Map<String, Void->Void>();
	var fired = new Array<String>();
	
	public function new (callback:Void->Void, logId:String = null)
	{
		this.callback = callback;
		this.logId = logId;
	}
	
	public function add(id = "untitled")
	{
		id = '$length:$id';
		length++;
		numRemaining++;
		var func:Void->Void = null;
		func = function ()
		{
			if (unfired.exists(id))
			{
				unfired.remove(id);
				fired.push(id);
				numRemaining--;
				
				if (logId != null)
					log('fired $id, $numRemaining remaining');
				
				if (numRemaining == 0)
				{
					if (logId != null)
						log('all callbacks fired');
					callback();
				}
			}
			else
				log('already fired $id');
		}
		unfired[id] = func;
		return func;
	}
	
	inline function log(msg):Void
	{
		if (logId != null)
			trace('$logId: $msg');
	}
	
	public function getFired() return fired.copy();
	public function getUnfired() return [for (id in unfired.keys()) id];
}
