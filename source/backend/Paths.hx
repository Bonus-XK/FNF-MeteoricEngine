package backend;

import animateatlas.AtlasFrameMaker;

import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;

import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.system.System;
import openfl.geom.Rectangle;

import lime.utils.Assets;
import lime.media.AudioBuffer;
import lime.media.vorbis.VorbisFile;
import flash.media.Sound;

#if sys
import sys.io.File;
import sys.FileSystem;
#end
import tjson.TJSON as Json;


#if MODS_ALLOWED
import backend.Mods;
#end

class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT = "mp4";

	public static function excludeAsset(key:String) {
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static var dumpExclusions:Array<String> =
	[
		'assets/music/freakyMenu.$SOUND_EXT',
		'assets/shared/music/breakfast.$SOUND_EXT',
		'assets/shared/music/tea-time.$SOUND_EXT',
	];

	// 内存清理回调：全局清缓存时通知各模块丢弃引用了已销毁图形的缓存（如音符贴图缓存）
	// 用函数惰性初始化，避免跨模块静态初始化顺序问题（Note.__init__ 可能先于本字段初始化执行）
	static var memoryCleanCallbacks:Array<Void->Void> = null;
	public static function addMemoryCleanCallback(cb:Void->Void)
	{
		if (memoryCleanCallbacks == null) memoryCleanCallbacks = [];
		memoryCleanCallbacks.push(cb);
	}
	static function dispatchMemoryClean()
	{
		if (memoryCleanCallbacks == null) return;
		for (cb in memoryCleanCallbacks)
			cb();
	}

	/// haya I love you for the base cache dump I took to the max
	public static function clearUnusedMemory(?doGC:Bool = true) {
		// clear non local assets in the tracked assets list
		for (key in currentTrackedAssets.keys()) {
			// 运行时密排列条目共享图集位图：绝不能随单条目销毁（会毁掉整张共享图集）
			if (packedEntries.exists(key)) continue;
			// if it is not currently contained within the used local assets
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key)) {
				var obj = currentTrackedAssets.get(key);
				@:privateAccess
				if (obj != null) {
					// 安全守卫：仍在被场上精灵引用的贴图绝不销毁（销毁后这些精灵会直接变透明/空白）
					if (obj.useCount > 0) {
						if (!localTrackedAssets.contains(key)) localTrackedAssets.push(key); // 视为本局仍在用，跳过本次清理（去重）
						continue;
					}
					// remove the key from all cache maps
					FlxG.bitmap._cache.remove(key);
					openfl.Assets.cache.removeBitmapData(key);
					currentTrackedAssets.remove(key);

					// and get rid of the object
					obj.persist = false; // make sure the garbage collector actually clears it up
					obj.destroyOnNoUse = true;
					obj.destroy();
				}
			}
		}

		// run the garbage collector for good measure lmfao
		if (doGC) System.gc();
		dispatchMemoryClean();
	}

	// define the locally tracked assets
	public static var localTrackedAssets:Array<String> = [];
	public static function clearStoredMemory(?cleanUnused:Bool = false) {
		// clear anything not in the tracked assets list
		@:privateAccess
		for (key in FlxG.bitmap._cache.keys())
		{
			var obj = FlxG.bitmap._cache.get(key);
			if (obj != null && !currentTrackedAssets.exists(key)) {
				// 安全守卫：仍在被精灵引用的贴图绝不销毁（如 HealthBar 的 makeGraphic 填充、
				// FlxText 字体字形、虚拟按键贴图等非 Paths 追踪资源）
				if (obj.useCount > 0) continue;
				openfl.Assets.cache.removeBitmapData(key);
				FlxG.bitmap._cache.remove(key);
				obj.destroy();
			}
		}

		// clear all sounds that are cached
		var removedSoundKeys:Array<String> = [];
		for (key in currentTrackedSounds.keys()) {
			if (!localTrackedAssets.contains(key)
			&& !dumpExclusions.contains(key) && key != null) {
				//trace('test: ' + dumpExclusions, key);
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
				removedSoundKeys.push(key);
			}
		}
		// 流式歌曲音频（Inst/Voices）：仅对"本次真正从缓存移除"的 Sound 退役其 VorbisFile 句柄
		// （当前曲的流式条目在 localTrackedAssets 中，必须保留）。句柄延迟一轮才 clear() ——
		// 旧播放通道（SoundChannel→AudioSource）在那时必已 stop/dispose，绝不在流读取中被释放。
		for (key in removedSoundKeys)
			if (streamedVorbis.exists(key))
			{
				retiredVorbis.push(streamedVorbis.get(key));
				streamedVorbis.remove(key);
			}
		// flags everything to be cleared out next unused memory clear
		localTrackedAssets = [];
		#if !html5 openfl.Assets.cache.clear("songs"); #end
		dispatchMemoryClean();
	}

	// ===== Meteoric：主线程维护（周期清理 / 分片异步解码 / 运行时密排列）=====
	// 所有功能均在主线程执行（工作线程分配 hxcpp GC 对象会与主线程 GC 并发破坏堆，
	// 见 LoadingState/discord 注释），因此“异步”= 每帧分片解码（不阻塞、无线程）。

	static var _periodicCleanAcc:Float = 0;
	static inline var PERIODIC_CLEAN_INTERVAL:Float = 60;

	/** 每帧从 MusicBeatState.update 调用：分片解码 + 每 60s 清理未用贴图/声音 */
	public static function tickMaintenance(elapsed:Float):Void
	{
		tickImageDecode(2);
		_periodicCleanAcc += elapsed;
		if (_periodicCleanAcc >= PERIODIC_CLEAN_INTERVAL)
		{
			_periodicCleanAcc = 0;
			cleanUnusedAssetsPeriodic();
		}
	}

	/** 周期清理：仅释放 useCount=0 且不在 localTrackedAssets 的贴图 + 未用声音（当前状态资源受保护） */
	public static function cleanUnusedAssetsPeriodic():Void
	{
		// 贴图：与 clearUnusedMemory 同守卫，但不强制 System.gc（游玩中做 GC 会卡帧）
		clearUnusedMemory(false);
		// 声音：不清 localTrackedAssets（当前曲/界面资源保留），只清无引用条目
		var removedSoundKeys:Array<String> = [];
		for (key in currentTrackedSounds.keys())
		{
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key) && key != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
				removedSoundKeys.push(key);
			}
		}
		for (key in removedSoundKeys)
			if (streamedVorbis.exists(key))
			{
				retiredVorbis.push(streamedVorbis.get(key));
				streamedVorbis.remove(key);
			}
		dispatchMemoryClean();
	}

	// ---- 异步图片加载（主线程分片）：解码结果进 pendingBitmaps，image() 消费 ----
	static var imageDecodeQueue:Array<String> = [];
	static var imageDecodeQueued:Map<String, Bool> = [];
	/** 请求异步解码一张图（已缓存/已排队/已解码则忽略） */
	public static function requestImageDecode(file:String):Void
	{
		if (file == null || file.length < 1) return;
		if (currentTrackedAssets.exists(file)) return;
		if (pendingBitmaps.exists(file)) return;
		if (imageDecodeQueued.exists(file)) return;
		imageDecodeQueued.set(file, true);
		imageDecodeQueue.push(file);
	}
	/** 每帧最多解码 maxPerFrame 张（主线程分片，不阻塞） */
	static function tickImageDecode(maxPerFrame:Int):Void
	{
		var n:Int = 0;
		while (imageDecodeQueue.length > 0 && n < maxPerFrame)
		{
			var file:String = imageDecodeQueue.shift();
			imageDecodeQueued.remove(file);
			if (currentTrackedAssets.exists(file) || pendingBitmaps.exists(file)) continue;
			try
			{
				var bmp:BitmapData = BitmapData.fromFile(file);
				if (bmp != null)
				{
					if (pendingBitmaps.exists(file))
						bmp.dispose();
					else
						pendingBitmaps.set(file, bmp);
				}
			}
			catch (e:Dynamic) {}
			n++;
		}
	}

	// ===== 内存明细导出（诊断用）=====
	// 已达成目标后移除；如后续需要，可用当前 diff 恢复或重新加回。

	// ---- 运行时贴图密排列（小贴图 → 运行时图集，减少纹理数/绘制批次）----
	// 范围：仅非图集、≤160px、且消费方经 imageFrame 绘制（FlxSprite.loadGraphic）的贴图；
	// 排除 icons/（HealthIcon 用 graphic.width 分割）、pixelUI/（StrumNote 分割）、
	// 音符皮肤与角色/图集（调用方 allowPack=false 或前缀排除）。
	static inline var PACK_MAX_SIZE:Int = 160;
	static inline var PACK_ATLAS_SIZE:Int = 1024;
	static var packAtlases:Array<FlxGraphic> = [];
	static var packCursorX:Int = 0;
	static var packCursorY:Int = 0;
	static var packShelfH:Int = 0;
	static var packedEntries:Map<String, Bool> = [];

	static function shouldPackSmall(key:String, w:Int, h:Int, allowPack:Bool):Bool
	{
		if (!allowPack) return false;
		if (!ClientPrefs.data.runtimePack) return false;
		if (ClientPrefs.data.cacheOnGPU) return false;
		if (w < 8 || h < 8 || w > PACK_MAX_SIZE || h > PACK_MAX_SIZE) return false;
		var lk:String = key.toLowerCase();
		if (lk.indexOf('icons/') == 0 || lk.indexOf('pixelui/') == 0) return false;
		if (lk.indexOf('noteskin') != -1 || lk.indexOf('character') != -1) return false;
		return true;
	}

	static function packedGraphicFromAtlas(atlasBitmap:BitmapData, file:String, rect:FlxRect):FlxGraphic
	{
		// Cache=false：不注册进 FlxG.bitmap._cache（共享位图，绝不随单条目销毁）；
		// 由调用方放入 currentTrackedAssets，清理函数对 packed 条目一律跳过。
		var g:FlxGraphic = FlxGraphic.fromBitmapData(atlasBitmap, false, file, false);
		g.persist = true;
		g.destroyOnNoUse = false;
		@:privateAccess
		{
			var img = g.imageFrame;
			var fr = img.frames[0];
			fr.frame = FlxRect.get(rect.x, rect.y, rect.width, rect.height);
			fr.sourceSize.set(rect.width, rect.height);
			fr.offset.set(0, 0);
		}
		packedEntries.set(file, true);
		return g;
	}

	static function packImageIntoAtlas(bitmap:BitmapData, file:String):FlxGraphic
	{
		var w:Int = bitmap.width, h:Int = bitmap.height;
		while (true)
		{
			var cur:BitmapData = (packAtlases.length > 0) ? packAtlases[packAtlases.length - 1].bitmap : null;
			if (cur != null)
			{
				// 当前行放得下 → 直接放
				if (packCursorX + w <= cur.width && packCursorY + h <= cur.height)
				{
					cur.draw(bitmap, new openfl.geom.Matrix(1, 0, 0, 1, packCursorX, packCursorY));
					var g:FlxGraphic = packedGraphicFromAtlas(cur, file, FlxRect.get(packCursorX, packCursorY, w, h));
					packCursorX += w;
					if (h > packShelfH) packShelfH = h;
					return g;
				}
				// 换行
				if (packCursorY + packShelfH + h <= cur.height)
				{
					packCursorY += packShelfH;
					packCursorX = 0;
					packShelfH = 0;
					continue;
				}
			}
			// 新建图集
			var atlasBitmap:BitmapData = new BitmapData(PACK_ATLAS_SIZE, PACK_ATLAS_SIZE, true, 0);
			var owner:FlxGraphic = FlxGraphic.fromBitmapData(atlasBitmap, false, 'runtimePackAtlas' + packAtlases.length, false);
			owner.persist = true;
			owner.destroyOnNoUse = false;
			packAtlases.push(owner);
			packCursorX = 0;
			packCursorY = 0;
			packShelfH = 0;
		}
		return null;
	}

	static public var currentLevel:String;
	static public function setCurrentLevel(name:String)
	{
		currentLevel = name.toLowerCase();
	}

	// lime 资产 id 兜底：lime manifest 的资产 id 是 URL 编码形态（assets%2Fshared%2Fimages%2F...），
	// OpenFlAssets.exists 用解码形态 id 查询永远不匹配，这里顺带尝试 URL 编码形态
	static function tryResolveAsset(path:String, ?type:AssetType):String
	{
		if (OpenFlAssets.exists(path, type)) return path;
		var colonAt:Int = path.indexOf(':');
		if (colonAt > 0)
		{
			var plain:String = path.substr(colonAt + 1);
			if (plain != path && OpenFlAssets.exists(plain, type)) return plain;
		}
		// lime manifest 实际注册的 id 形态：路径中的 '/' 被编码为 %2F
		var encoded:String = StringTools.replace(plainOrSelf(path), '/', '%2F');
		if (encoded != path && OpenFlAssets.exists(encoded, type)) return encoded;
		return null;
	}

	inline static function plainOrSelf(path:String):String
	{
		var colonAt:Int = path.indexOf(':');
		return colonAt > 0 ? path.substr(colonAt + 1) : path;
	}

	public static function getPath(file:String, ?type:AssetType = TEXT, ?library:Null<String> = null, ?modsAllowed:Bool = false):String
	{
		#if MODS_ALLOWED
		if(modsAllowed)
		{
			var modded:String = modFolders(file);
			if(FileSystem.exists(modded)) return modded;
		}
		#end

		if (library != null)
			return getLibraryPath(file, library);

		if (currentLevel != null)
		{
			// 运行时 cwd = 资源目录（macOS 上 SDLApplication chdir 到 Contents/Resources）：
			// 文件系统存在性检查是唯一可靠的资源定位方式（OpenFlAssets.exists 的 id 形态不匹配）。
			#if sys
			if(currentLevel != 'shared')
			{
				var weekFsPath:String = 'assets/$currentLevel/$file';
				if (FileSystem.exists(weekFsPath))
					return weekFsPath;
			}
			#end

			var levelPath:String = '';
			if(currentLevel != 'shared') {
				levelPath = getLibraryPathForce(file, 'week_assets', currentLevel);
				levelPath = tryResolveAsset(levelPath, type);
				if (levelPath != null)
					return levelPath;
			}
		}

		// shared 库：无条件尝试文件系统路径（不依赖 currentLevel——
		// 音符预生成可能发生在 setCurrentLevel 之前，例如 mod stage 下 stageDir 为空）
		#if sys
		var sharedFsPath:String = 'assets/shared/$file';
		if (FileSystem.exists(sharedFsPath))
			return sharedFsPath;
		#end
		{
			var levelPath:String = getLibraryPathForce(file, "shared");
			levelPath = tryResolveAsset(levelPath, type);
			if (levelPath != null)
				return levelPath;
		}

		return getPreloadPath(file);
	}

	static public function getLibraryPath(file:String, library = "preload")
	{
		if (library == "preload" || library == "default") return getPreloadPath(file);
		var path:String = getLibraryPathForce(file, library);
		var resolved:String = tryResolveAsset(path);
		return resolved != null ? resolved : path;
	}

	inline static function getLibraryPathForce(file:String, library:String, ?level:String)
	{
		if(level == null) level = library;
		var returnPath = '$library:assets/$level/$file';
		return returnPath;
	}

	inline public static function getPreloadPath(file:String = '')
	{
		#if android
		// 外部存储存在同名文件时优先使用（用户可替换/追加资源，无需重打包）
		var ext = backend.AndroidStorage.root() + '/assets/' + file;
		if (FileSystem.exists(ext))
			return ext;
		#end
		return 'assets/$file';
	}

	inline static public function txt(key:String, ?library:String)
	{
		return getPath('data/$key.txt', TEXT, library);
	}

	inline static public function xml(key:String, ?library:String)
	{
		return getPath('data/$key.xml', TEXT, library);
	}

	inline static public function json(key:String, ?library:String)
	{
		return getPath('data/$key.json', TEXT, library);
	}

	inline static public function shaderFragment(key:String, ?library:String)
	{
		return getPath('shaders/$key.frag', TEXT, library);
	}
	inline static public function shaderVertex(key:String, ?library:String)
	{
		return getPath('shaders/$key.vert', TEXT, library);
	}
	inline static public function lua(key:String, ?library:String)
	{
		return getPath('$key.lua', TEXT, library);
	}

	static public function video(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if(FileSystem.exists(file)) {
			return file;
		}
		#end
		var external:String = getPreloadPath('videos/$key.$VIDEO_EXT');
		if(FileSystem.exists(external)) return external;
		return 'assets/videos/$key.$VIDEO_EXT';
	}

	static public function sound(key:String, ?library:String):Sound
	{
		var sound:Sound = returnSound('sounds', key, library);
		return sound;
	}

	inline static public function soundRandom(key:String, min:Int, max:Int, ?library:String)
	{
		return sound(key + FlxG.random.int(min, max), library);
	}

	inline static public function music(key:String, ?library:String):Sound
	{
		var file:Sound = returnSound('music', key, library);
		return file;
	}

	inline static public function voices(song:String, postfix:String = null):Any
	{
		#if html5
		return 'songs:assets/songs/${formatToSongPath(song)}/Voices.$SOUND_EXT';
		#else
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if(postfix != null) songKey += '-' + postfix;
		var voices = returnSound('songs', songKey);
		return voices;
		#end
	}

	inline static public function inst(song:String):Any
	{
		#if html5
		return 'songs:assets/songs/${formatToSongPath(song)}/Inst.$SOUND_EXT';
		#else
		var songKey:String = '${formatToSongPath(song)}/Inst';
		var inst = returnSound('songs', songKey);
		return inst;
		#end
	}

	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	// 后台线程预解码完成的贴图（LoadingState 并行解码人物等大图），主线程 image() 消费并转入正式缓存
	public static var pendingBitmaps:Map<String, BitmapData> = [];

	// 清空未消费的预解码贴图（防止大图残留内存）
	public static function clearPendingBitmaps()
	{
		for (bmp in pendingBitmaps)
			if (bmp != null) bmp.dispose();
		pendingBitmaps = [];
	}

	// 强制全新加载：完全绕过 currentTrackedAssets 缓存（模组重启后缓存可能持有销毁/失效状态——
	// bitmap 非空但帧集合/GPU 资源已死，CPU 参数无法挽救缓存命中）。返回全新的 CPU 位图对象。
	static public function imageFresh(key:String, ?library:String = null):FlxGraphic
	{
		var file:String = null;
		#if MODS_ALLOWED
		file = modsImages(key);
		if (file == null || !FileSystem.exists(file))
		#end
			file = getPath('images/$key.png', IMAGE, library);
		try
		{
			if (OpenFlAssets.exists(file, IMAGE))
			{
				var bd:BitmapData = OpenFlAssets.getBitmapData(file);
				if (bd != null) return FlxGraphic.fromBitmapData(bd);
			}
			if (FileSystem.exists(file))
			{
				var bd2:BitmapData = BitmapData.fromFile(file);
				if (bd2 != null) return FlxGraphic.fromBitmapData(bd2);
			}
		}
		catch (e:Dynamic) {}
		return null;
	}

	static public function image(key:String, ?library:String = null, ?allowGPU:Bool = true, ?allowScale:Bool = true, ?scaleTo:Float = -1, ?allowPack:Bool = true):FlxGraphic
	{
		var bitmap:BitmapData = null;
		var file:String = null;

		#if MODS_ALLOWED
		file = modsImages(key);
		if (currentTrackedAssets.exists(file))
		{
			var cached:FlxGraphic = currentTrackedAssets.get(file);
			// 模组卸载/内存清理后位图可能已被销毁（destroy 会置空 bitmap）：失效则移除缓存并重新加载
			// 注意：不能用 bitmap.readable 判活——cacheOnGPU 的有效位图不可读会被误判失效导致图标消失
			if (cached != null && cached.bitmap != null)
			{
				if (!localTrackedAssets.contains(file)) localTrackedAssets.push(file); // 去重：高频 mod 调用不再膨胀数组
				return cached;
			}
			currentTrackedAssets.remove(file);
		}
		else if (pendingBitmaps.exists(file))
		{
			bitmap = pendingBitmaps.get(file);
			pendingBitmaps.remove(file);
		}
		else if (FileSystem.exists(file))
			bitmap = BitmapData.fromFile(file);
		else
		#end
		{
			file = getPath('images/$key.png', IMAGE, library);
			if (currentTrackedAssets.exists(file))
			{
				var cached:FlxGraphic = currentTrackedAssets.get(file);
				if (cached != null && cached.bitmap != null)
				{
					if (!localTrackedAssets.contains(file)) localTrackedAssets.push(file); // 去重
					return cached;
				}
				currentTrackedAssets.remove(file);
			}
			else if (pendingBitmaps.exists(file))
			{
				bitmap = pendingBitmaps.get(file);
				pendingBitmaps.remove(file);
			}
			else if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);
			else if (FileSystem.exists(file))
				bitmap = BitmapData.fromFile(file);
			// 兜底：lime 库前缀 id（shared:assets/shared/...）解析失败时，
			// 尝试无前缀完整路径（manifest 的 id 是不带前缀的 assets/shared/images/...）
			if (bitmap == null)
			{
				var plainId:String = file;
				var colonAt:Int = plainId.indexOf(':');
				if (colonAt > 0) plainId = plainId.substr(colonAt + 1);
				if (plainId != file && OpenFlAssets.exists(plainId, IMAGE))
					bitmap = OpenFlAssets.getBitmapData(plainId);
			}
		}

		if (bitmap != null)
		{
			if (!localTrackedAssets.contains(file)) localTrackedAssets.push(file); // 去重
			// 图集降采样（Meteoric Fix 续）：>2048px 大图缩到 ClientPrefs.data.textureScale（桌面默认 50%）。
			// 各图集消费者（flxanimate 2020 spritemap / sparrow XML）同步缩放帧坐标；旧格式
			// AtlasFrameMaker 走 BitmapData.fromFile 不经此处（保持原分辨率，零回归）。
			var texScale:Float = (scaleTo >= 0) ? scaleTo : ClientPrefs.data.textureScale;
			if (allowScale && texScale < 1 && bitmap.width > 4000)
			{
				try
				{
					var nw:Int = Std.int(bitmap.width * texScale);
					var nh:Int = Std.int(bitmap.height * texScale);
					if (nw > 0 && nh > 0)
					{
						var scaled:BitmapData = new BitmapData(nw, nh, bitmap.transparent, 0);
						scaled.draw(bitmap, new openfl.geom.Matrix(texScale, 0, 0, texScale, 0, 0), null, null, null, false);
						// 移除资源缓存中的原图，避免 CPU 双份
						try { OpenFlAssets.cache.removeBitmapData(file); } catch (e:Dynamic) {}
						bitmap = scaled;
					}
				}
				catch (e:Dynamic) {}
			}
			// 独立背景图降采样（Meteoric 内存优化）：非图集（allowPack=true 表明该图不经
			// 帧坐标消费）、>1600px 的大图按 backgroundScale 缩放（整体位图缩放，无帧坐标问题）
			if (allowPack && allowScale && ClientPrefs.data.backgroundScale < 1 && bitmap.width > 1600)
			{
				try
				{
					var bs:Float = ClientPrefs.data.backgroundScale;
					var nw:Int = Std.int(bitmap.width * bs);
					var nh:Int = Std.int(bitmap.height * bs);
					if (nw > 0 && nh > 0)
					{
						var scaled:BitmapData = new BitmapData(nw, nh, bitmap.transparent, 0);
						scaled.draw(bitmap, new openfl.geom.Matrix(bs, 0, 0, bs, 0, 0), null, null, null, false);
						try { OpenFlAssets.cache.removeBitmapData(file); } catch (e:Dynamic) {}
						bitmap = scaled;
					}
				}
				catch (e:Dynamic) {}
			}
			if (allowGPU && ClientPrefs.data.cacheOnGPU)
			{
				// context3D 未就绪（加载界面早期）时 GPU 上传会失败 → 回退 CPU 位图，避免贴图加载失败
				try
				{
					var texture:RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmap.width, bitmap.height, BGRA, true);
					texture.uploadFromBitmapData(bitmap);
					bitmap.image.data = null;
					bitmap.dispose();
					bitmap.disposeImage();
					bitmap = BitmapData.fromTexture(texture);
				}
				catch (e:Dynamic)
				{
					// GPU 不可用，保持 CPU 位图
				}
			}
			// 运行时贴图密排列：小贴图打包进共享图集（减少纹理/绘制批次；消费方须经 imageFrame 绘制）
			if (shouldPackSmall(file, bitmap.width, bitmap.height, allowPack))
			{
				var packed:FlxGraphic = packImageIntoAtlas(bitmap, file);
				if (packed != null)
				{
					currentTrackedAssets.set(file, packed);
					return packed;
				}
			}
			var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, file);
			newGraphic.persist = true;
			newGraphic.destroyOnNoUse = false;
			currentTrackedAssets.set(file, newGraphic);
			return newGraphic;
		}

		trace('oh no its returning null NOOOO ($file)');
		return null;
	}

	static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		#if sys
		#if MODS_ALLOWED
		if (!ignoreMods && FileSystem.exists(modFolders(key)))
			return File.getContent(modFolders(key));
		#end

		// 运行时 cwd = 资源目录（macOS chdir 到 Resources）：文件系统直接读取最可靠
		if (currentLevel != null)
		{
			if(currentLevel != 'shared') {
				var weekFs:String = 'assets/$currentLevel/$key';
				if (FileSystem.exists(weekFs))
					return File.getContent(weekFs);
			}
		}

		// shared 库：无条件尝试（不依赖 currentLevel 是否已设置）
		var sharedFs:String = 'assets/shared/$key';
		if (FileSystem.exists(sharedFs))
			return File.getContent(sharedFs);

		if (FileSystem.exists(getPreloadPath(key)))
			return File.getContent(getPreloadPath(key));
		#end
		var path:String = getPath(key, TEXT);
		#if sys
		if (FileSystem.exists(path))
			return File.getContent(path);
		#end
		if(OpenFlAssets.exists(path, TEXT)) return Assets.getText(path);
		// 兜底：URL 编码形态 id（lime manifest 实际注册形态：'/' → %2F）
		var colonTxt:Int = path.indexOf(':');
		var plainTxt:String = colonTxt > 0 ? path.substr(colonTxt + 1) : path;
		var encodedTxt:String = StringTools.replace(plainTxt, '/', '%2F');
		if (encodedTxt != path && OpenFlAssets.exists(encodedTxt, TEXT)) return Assets.getText(encodedTxt);
		return null;
	}

	inline static public function font(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsFont(key);
		if(FileSystem.exists(file)) {
			return file;
		}
		#end
		return 'assets/fonts/$key';
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?library:String = null)
	{
		#if MODS_ALLOWED
		if(!ignoreMods)
		{
			for(mod in Mods.getGlobalMods())
				if (FileSystem.exists(mods('$mod/$key')))
					return true;

			if (FileSystem.exists(mods(Mods.currentModDirectory + '/' + key)) || FileSystem.exists(mods(key)))
				return true;
		}
		#end

		if(FileSystem.exists(getPath(key, type, library, false)) || OpenFlAssets.exists(getPath(key, type, library, false))) {
			return true;
		}
		return false;
	}

	// Psych 1.0.4：多图集角色（image 字段逗号分隔，如 pico-playable）合并为一个 FlxAtlasFrames
	// （flixel 5.x 无 addAtlas，用 pushFrame 手动合并）
	static public function getMultiAtlas(keys:Array<String>, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var parentFrames:FlxAtlasFrames = Paths.getAtlas(keys[0].trim());
		if(keys.length > 1)
		{
			var combined:FlxAtlasFrames = new FlxAtlasFrames(parentFrames.parent);
			for (frame in parentFrames.frames) combined.pushFrame(frame);
			for (i in 1...keys.length)
			{
				var extraFrames:FlxAtlasFrames = Paths.getAtlas(keys[i].trim(), parentFolder);
				if(extraFrames != null)
					for (frame in extraFrames.frames) combined.pushFrame(frame);
			}
			return combined;
		}
		return parentFrames;
	}

	// less optimized but automatic handling
	static public function getAtlas(key:String, ?library:String = null):FlxAtlasFrames
	{
		var useMod:Bool = false;
		// allowPack=false：图集加载器绝不参与运行时密排列（帧坐标基于原图，打包会破坏 UV/空指针）
		var imageLoaded:FlxGraphic = image(key, library, true, true, -1, false);

		var myXml:Dynamic = getPath('images/$key.xml', TEXT, library, true);
		if(OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end )
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromSparrow(imageLoaded, (useMod ? File.getContent(myXml) : atlasData(myXml)));
			#else
			return FlxAtlasFrames.fromSparrow(imageLoaded, atlasData(myXml));
			#end
		}
		else
		{
			// Aseprite .JSON / TexturePacker 图集支持（Psych 0.7.3 兼容）
			var myJson:Dynamic = getPath('images/$key.json', TEXT, library, true);
			if(OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end )
			{
				#if MODS_ALLOWED
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (useMod ? File.getContent(myJson) : atlasData(myJson)));
				#else
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, atlasData(myJson));
				#end
			}
		}
		return getPackerAtlas(key, library);
	}

	// Aseprite .JSON 图集（显式调用，供角色编辑器等使用）
	inline static public function getAsepriteAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		// allowPack=false：图集加载器绝不参与运行时密排列
		var imageLoaded:FlxGraphic = image(key, library, allowGPU, true, -1, false);
		#if MODS_ALLOWED
		var jsonExists:Bool = false;

		var json:String = modsImagesJson(key);
		if(FileSystem.exists(json)) jsonExists = true;

		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (jsonExists ? File.getContent(json) : atlasData(getPath('images/$key.json', library))));
		#else
		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, atlasData(getPath('images/$key.json', library)));
		#end
	}

	// 返回图集描述内容：文件系统里存在的路径直接读内容，内部资源路径原样交给 openfl Assets
	inline static function atlasData(path:String):String
	{
		return FileSystem.exists(path) ? File.getContent(path) : path;
	}

	// sparrow 图集帧坐标同步缩放（配合 Paths.image 降采样；texScale=1 时 no-op）
	static function scaleSparrowFrames(frames:FlxAtlasFrames):Void
	{
		var texScale:Float = ClientPrefs.data.textureScale;
		if (texScale >= 1 || frames == null || frames.frames == null) return;
		for (f in frames.frames)
		{
			if (f.frame != null)
			{
				f.frame.x *= texScale;
				f.frame.y *= texScale;
				f.frame.width *= texScale;
				f.frame.height *= texScale;
			}
			if (f.sourceSize != null) { f.sourceSize.x *= texScale; f.sourceSize.y *= texScale; }
			if (f.offset != null) { f.offset.x *= texScale; f.offset.y *= texScale; }
		}
	}

	inline static public function getSparrowAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, null, allowGPU, true, -1, false); // allowPack=false：图集贴图不参与密排列
		var xmlExists:Bool = false;

		var xml:String = modsXml(key);
		if(FileSystem.exists(xml)) {
			xmlExists = true;
		}

		var spFrames:FlxAtlasFrames = FlxAtlasFrames.fromSparrow((imageLoaded != null ? imageLoaded : image(key, library, allowGPU, true, -1, false)), (xmlExists ? File.getContent(xml) : atlasData(getPath('images/$key.xml', library))));
		scaleSparrowFrames(spFrames);
		return spFrames;
		#else
		var spFrames:FlxAtlasFrames = FlxAtlasFrames.fromSparrow(image(key, library, allowGPU, true, -1, false), atlasData(getPath('images/$key.xml', library)));
		scaleSparrowFrames(spFrames);
		return spFrames;
		#end
	}

	inline static public function getPackerAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, null, allowGPU, true, -1, false); // allowPack=false：图集贴图不参与密排列
		var txtExists:Bool = false;
		
		var txt:String = modsTxt(key);
		if(FileSystem.exists(txt)) {
			txtExists = true;
		}

		return FlxAtlasFrames.fromSpriteSheetPacker((imageLoaded != null ? imageLoaded : image(key, library, allowGPU, true, -1, false)), (txtExists ? File.getContent(txt) : atlasData(getPath('images/$key.txt', library))));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(image(key, library, allowGPU, true, -1, false), atlasData(getPath('images/$key.txt', library)));
		#end
	}

	inline static public function formatToSongPath(path:String) {
		var invalidChars = ~/[~&\\;:<>#]/;
		var hideChars = ~/[.,'"%?!]/;

		var path = invalidChars.split(path.replace(' ', '-')).join("-");
		return hideChars.split(path).join("").toLowerCase();
	}

	public static var currentTrackedSounds:Map<String, Sound> = [];

	// ===== 歌曲音频流式（Meteoric Fix 续：Flocc 级 1GB → 400MB 的硬件侧一步）=====
	// Inst/Voices 不再整首解码驻留 PCM（~20-40MB/首），改 Vorbis 流式 + OpenAL 3×48KB 环形缓冲
	// （~150KB 常驻，声卡/设备侧混音）。仅桌面（lime_vorbis 原生 CFFI 已启用）；
	// 移动端沿用全量解码管线，保持既有稳定性。
	static var streamedVorbis:Map<String, VorbisFile> = new Map();     // 本次会话仍在用的流句柄
	static var retiredVorbis:Array<VorbisFile> = [];                    // 延迟一轮释放的流句柄
	static function clearRetiredVorbis():Void
	{
		for (vf in retiredVorbis)
			try vf.clear() catch (e:Dynamic) {}
		retiredVorbis = [];
	}

	// 歌曲音频流式加载：VorbisFile + AudioBuffer.fromVorbisFile → Sound（流式缓冲）。
	// 任何一步失败自动回退 Sound.fromFile 全量解码（行为与旧版一致，绝不崩）。
	public static function streamSongAudio(filePath:String):Sound
	{
		#if desktop
		clearRetiredVorbis();
		try
		{
			var vf:VorbisFile = VorbisFile.fromFile(filePath);
			if (vf != null)
			{
				var buffer:AudioBuffer = AudioBuffer.fromVorbisFile(vf);
				if (buffer != null)
				{
					var snd:Sound = Sound.fromAudioBuffer(buffer);
					if (snd != null)
					{
						streamedVorbis.set(filePath, vf);
						return snd;
					}
				}
			}
			trace('[Audio] 流式加载不可用，回退全量解码：' + filePath);
		}
		catch (e:Dynamic)
		{
			trace('[Audio] 流式加载失败，回退全量解码：' + filePath + ' (' + e + ')');
		}
		#end
		return Sound.fromFile(filePath);
	}

	public static function returnSound(path:String, key:String, ?library:String) {
		#if MODS_ALLOWED
		var file:String = modsSounds(path, key);
		if(FileSystem.exists(file)) {
			if(!currentTrackedSounds.exists(file)) {
				currentTrackedSounds.set(file, (path == 'songs') ? streamSongAudio(file) : Sound.fromFile(file));
			}
			localTrackedAssets.push(key);
			return currentTrackedSounds.get(file);
		}
		#end
		// I hate this so god damn much
		var gottenPath:String = getPath('$path/$key.$SOUND_EXT', SOUND, library);
		gottenPath = gottenPath.substring(gottenPath.indexOf(':') + 1, gottenPath.length);
		// trace(gottenPath);
		if(!currentTrackedSounds.exists(gottenPath))
		{
			var fileToLoad:String = gottenPath;
			if(!haxe.io.Path.isAbsolute(fileToLoad)) fileToLoad = './' + fileToLoad;
			if(FileSystem.exists(fileToLoad))
			{
				currentTrackedSounds.set(gottenPath, (path == 'songs') ? streamSongAudio(fileToLoad) : Sound.fromFile(fileToLoad));
			}
			else
			{
			var folder:String = '';
			if(path == 'songs') folder = 'songs:';

			var assetId:String = folder + getPath('$path/$key.$SOUND_EXT', SOUND, library);
			if(OpenFlAssets.exists(assetId, SOUND))
				currentTrackedSounds.set(gottenPath, OpenFlAssets.getSound(assetId));
			else
			{
				// 文件与资源都不存在（模组缺人声等）：返回空声音，避免播放阶段崩溃
				trace('MISSING SOUND: $assetId');
				currentTrackedSounds.set(gottenPath, new Sound());
			}
			}
		}
		if (!localTrackedAssets.contains(gottenPath)) localTrackedAssets.push(gottenPath); // 去重
		return currentTrackedSounds.get(gottenPath);
	}

	#if MODS_ALLOWED
	static public function mods(key:String = '') {
		var p:String = #if android backend.AndroidStorage.root() + '/mods/' + key #else 'mods/' + key #end;
		// 兼容模组大小写命名（icon-Oswald.png 等）：原样找不到时尝试全小写
		if(!FileSystem.exists(p)) {
			var lower:String = #if android backend.AndroidStorage.root() + '/mods/' + key.toLowerCase() #else 'mods/' + key.toLowerCase() #end;
			if(FileSystem.exists(lower)) return lower;
		}
		return p;
	}

	inline static public function modsFont(key:String) {
		return modFolders('fonts/' + key);
	}

	inline static public function modsJson(key:String) {
		return modFolders('data/' + key + '.json');
	}

	inline static public function modsVideo(key:String) {
		return modFolders('videos/' + key + '.' + VIDEO_EXT);
	}

	static public function modsSounds(path:String, key:String) {
		var p:String = modFolders(path + '/' + key + '.' + SOUND_EXT);
		if(!FileSystem.exists(p)) {
			// 兼容模组小写命名（inst.ogg / voices.ogg）
			var p2:String = modFolders(path + '/' + key.toLowerCase() + '.' + SOUND_EXT);
			if(FileSystem.exists(p2)) return p2;
		}
		return p;
	}

	inline static public function modsImages(key:String) {
		return modFolders('images/' + key + '.png');
	}

	inline static public function modsImagesJson(key:String) {
		return modFolders('images/' + key + '.json');
	}

	inline static public function modsXml(key:String) {
		return modFolders('images/' + key + '.xml');
	}

	inline static public function modsTxt(key:String) {
		return modFolders('images/' + key + '.txt');
	}

	/* Goes unused for now

	inline static public function modsShaderFragment(key:String, ?library:String)
	{
		return modFolders('shaders/'+key+'.frag');
	}
	inline static public function modsShaderVertex(key:String, ?library:String)
	{
		return modFolders('shaders/'+key+'.vert');
	}
	inline static public function modsAchievements(key:String) {
		return modFolders('achievements/' + key + '.json');
	}*/

	static public function modFolders(key:String) {
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) {
			var fileToCheck:String = mods(Mods.currentModDirectory + '/' + key);
			if(FileSystem.exists(fileToCheck)) {
				return fileToCheck;
			}
		}

		for(mod in Mods.getGlobalMods()){
			var fileToCheck:String = mods(mod + '/' + key);
			if(FileSystem.exists(fileToCheck))
				return fileToCheck;
		}
		return mods(key);
	}
	#end

	#if flxanimate
	/** Psych 0.7 兼容：FlxAnimate 加载（支持 mods 文件系统，走 loadAtlasEx 内容加载） */
	public static function loadAnimateAtlas(spr:flxanimate.PsychFlxAnimate, folderOrImg:Dynamic, spriteJson:Dynamic = null, animationJson:Dynamic = null)
	{
		var changedAnimJson = false;
		var changedAtlasJson = false;
		var changedImage = false;

		if(spriteJson != null)
		{
			changedAtlasJson = true;
			spriteJson = File.getContent(spriteJson);
		}

		if(animationJson != null)
		{
			changedAnimJson = true;
			animationJson = File.getContent(animationJson);
		}

		if(Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;
			for (i in 0...10)
			{
				var st:String = '$i';
				if(i == 0) st = '';

				if(!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$st.json');
					if(spriteJson != null)
					{
						changedImage = true;
						changedAtlasJson = true;
						// ATLAS 格式（spritemap1：flxanimate 2020 图集）不参与降采样：
						// 该渲染器的 limb 尺寸取自帧 rect（w/h），Animation.json 的 M3D/TRP
						// 亦未随位图缩放；位图+坐标同时×0.5 会使角色缩小且肢体错位。
						// 保持原分辨率，视觉零回归（影响仅 qt-dance/bf-qt 等大图集的内存）。
						var atlasFormat:Bool = Std.isOfType(spriteJson, String)
							&& StringTools.contains(cast spriteJson, '"ATLAS"');
						var useScale:Float = atlasFormat ? 1.0 : ClientPrefs.data.characterTextureScale;
						folderOrImg = image('$originalPath/spritemap$st', null, true, true, useScale, false); // allowPack=false：图集贴图不参与密排列
						break;
					}
				}
				else if(FileSystem.exists('images/$originalPath/spritemap$st.png'))
				{
					changedImage = true;
					folderOrImg = 'images/$originalPath/spritemap$st.png';
					break;
				}
			}

			if(!changedImage)
			{
				changedImage = true;
				folderOrImg = image(originalPath);
			}

			if(!changedAnimJson)
			{
				changedAnimJson = true;
				animationJson = getTextFromFile('images/$originalPath/Animation.json');
			}
		}

		// 角色图集降采样（Meteoric Fix 续）：图片已缩（scaleTo=characterTextureScale），
		// spritemap JSON 帧坐标同步 ×同一比例（仅非 ATLAS 格式；ATLAS 已保持原分辨率）
		var atlasBypass:Bool = spriteJson != null && Std.isOfType(spriteJson, String)
			&& StringTools.contains(cast spriteJson, '"ATLAS"');
		var charScale:Float = atlasBypass ? 1.0 : ClientPrefs.data.characterTextureScale;
		if (charScale < 1 && spriteJson != null && Std.isOfType(spriteJson, String))
		{
			try
			{
				var parsed:Dynamic = haxe.Json.parse(cast spriteJson);
				scaleAtlasJson(parsed, charScale);
				spriteJson = haxe.Json.stringify(parsed);
			}
			catch (e:Dynamic) {}
		}

		spr.loadAtlasEx(folderOrImg, spriteJson, animationJson);
	}

	// 2020/旧版 spritemap JSON 帧坐标缩放（frame/spriteSourceSize/sourceSize）
	static function scaleAtlasJson(d:Dynamic, s:Float):Void
	{
		if (d == null) return;

		var frames:Dynamic = Reflect.field(d, 'frames');
		if (frames == null) return;
		var apply:Dynamic->Void = function(fr:Dynamic)
		{
			var frame:Dynamic = Reflect.field(fr, 'frame');
			if (frame != null)
			{
				Reflect.setField(frame, 'x', Std.int(Reflect.field(frame, 'x') * s));
				Reflect.setField(frame, 'y', Std.int(Reflect.field(frame, 'y') * s));
				Reflect.setField(frame, 'w', Math.max(1, Std.int(Reflect.field(frame, 'w') * s)));
				Reflect.setField(frame, 'h', Math.max(1, Std.int(Reflect.field(frame, 'h') * s)));
			}
			var sss:Dynamic = Reflect.field(fr, 'spriteSourceSize');
			if (sss != null)
			{
				Reflect.setField(sss, 'x', Std.int(Reflect.field(sss, 'x') * s));
				Reflect.setField(sss, 'y', Std.int(Reflect.field(sss, 'y') * s));
				Reflect.setField(sss, 'w', Math.max(1, Std.int(Reflect.field(sss, 'w') * s)));
				Reflect.setField(sss, 'h', Math.max(1, Std.int(Reflect.field(sss, 'h') * s)));
			}
			var src:Dynamic = Reflect.field(fr, 'sourceSize');
			if (src != null)
			{
				Reflect.setField(src, 'w', Math.max(1, Std.int(Reflect.field(src, 'w') * s)));
				Reflect.setField(src, 'h', Math.max(1, Std.int(Reflect.field(src, 'h') * s)));
			}
		};
		if (Std.isOfType(frames, Array))
			for (fr in (cast frames : Array<Dynamic>)) apply(fr);
		else
			for (k in Reflect.fields(frames)) apply(Reflect.field(frames, k));
	}
	#end
}
