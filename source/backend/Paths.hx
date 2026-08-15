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
			// if it is not currently contained within the used local assets
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key)) {
				var obj = currentTrackedAssets.get(key);
				@:privateAccess
				if (obj != null) {
					// 安全守卫：仍在被场上精灵引用的贴图绝不销毁（销毁后这些精灵会直接变透明/空白）
					if (obj.useCount > 0) {
						localTrackedAssets.push(key); // 视为本局仍在用，跳过本次清理
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
		for (key in currentTrackedSounds.keys()) {
			if (!localTrackedAssets.contains(key)
			&& !dumpExclusions.contains(key) && key != null) {
				//trace('test: ' + dumpExclusions, key);
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
			}
		}
		// flags everything to be cleared out next unused memory clear
		localTrackedAssets = [];
		#if !html5 openfl.Assets.cache.clear("songs"); #end
		dispatchMemoryClean();
	}

	static public var currentLevel:String;
	static public function setCurrentLevel(name:String)
	{
		currentLevel = name.toLowerCase();
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
			var levelPath:String = '';
			if(currentLevel != 'shared') {
				levelPath = getLibraryPathForce(file, 'week_assets', currentLevel);
				if (OpenFlAssets.exists(levelPath, type))
					return levelPath;
			}

			levelPath = getLibraryPathForce(file, "shared");
			if (OpenFlAssets.exists(levelPath, type))
				return levelPath;
		}

		return getPreloadPath(file);
	}

	static public function getLibraryPath(file:String, library = "preload")
	{
		return if (library == "preload" || library == "default") getPreloadPath(file); else getLibraryPathForce(file, library);
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

	inline static public function voices(song:String):Any
	{
		#if html5
		return 'songs:assets/songs/${formatToSongPath(song)}/Voices.$SOUND_EXT';
		#else
		var songKey:String = '${formatToSongPath(song)}/Voices';
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

	static public function image(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		var bitmap:BitmapData = null;
		var file:String = null;

		#if MODS_ALLOWED
		file = modsImages(key);
		if (currentTrackedAssets.exists(file))
		{
			localTrackedAssets.push(file);
			return currentTrackedAssets.get(file);
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
				localTrackedAssets.push(file);
				return currentTrackedAssets.get(file);
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
		}

		if (bitmap != null)
		{
			localTrackedAssets.push(file);
			if (allowGPU && ClientPrefs.data.cacheOnGPU)
			{
				var texture:RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmap.width, bitmap.height, BGRA, true);
				texture.uploadFromBitmapData(bitmap);
				bitmap.image.data = null;
				bitmap.dispose();
				bitmap.disposeImage();
				bitmap = BitmapData.fromTexture(texture);
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

		if (FileSystem.exists(getPreloadPath(key)))
			return File.getContent(getPreloadPath(key));

		if (currentLevel != null)
		{
			var levelPath:String = '';
			if(currentLevel != 'shared') {
				levelPath = getLibraryPathForce(key, 'week_assets', currentLevel);
				if (FileSystem.exists(levelPath))
					return File.getContent(levelPath);
			}

			levelPath = getLibraryPathForce(key, 'shared');
			if (FileSystem.exists(levelPath))
				return File.getContent(levelPath);
		}
		#end
		var path:String = getPath(key, TEXT);
		if(OpenFlAssets.exists(path, TEXT)) return Assets.getText(path);
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

	// less optimized but automatic handling
	static public function getAtlas(key:String, ?library:String = null):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		if(FileSystem.exists(modsXml(key)) || FileSystem.exists(getPath('images/$key.xml', library)) || OpenFlAssets.exists(getPath('images/$key.xml', library), TEXT))
		#else
		if(FileSystem.exists(getPath('images/$key.xml', library)) || OpenFlAssets.exists(getPath('images/$key.xml', library)))
		#end
		{
			return getSparrowAtlas(key, library);
		}
		return getPackerAtlas(key, library);
	}

	// 返回图集描述内容：文件系统里存在的路径直接读内容，内部资源路径原样交给 openfl Assets
	inline static function atlasData(path:String):String
	{
		return FileSystem.exists(path) ? File.getContent(path) : path;
	}

	inline static public function getSparrowAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, allowGPU);
		var xmlExists:Bool = false;

		var xml:String = modsXml(key);
		if(FileSystem.exists(xml)) {
			xmlExists = true;
		}

		return FlxAtlasFrames.fromSparrow((imageLoaded != null ? imageLoaded : image(key, library, allowGPU)), (xmlExists ? File.getContent(xml) : atlasData(getPath('images/$key.xml', library))));
		#else
		return FlxAtlasFrames.fromSparrow(image(key, library, allowGPU), atlasData(getPath('images/$key.xml', library)));
		#end
	}

	inline static public function getPackerAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, allowGPU);
		var txtExists:Bool = false;
		
		var txt:String = modsTxt(key);
		if(FileSystem.exists(txt)) {
			txtExists = true;
		}

		return FlxAtlasFrames.fromSpriteSheetPacker((imageLoaded != null ? imageLoaded : image(key, library, allowGPU)), (txtExists ? File.getContent(txt) : atlasData(getPath('images/$key.txt', library))));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(image(key, library, allowGPU), atlasData(getPath('images/$key.txt', library)));
		#end
	}

	inline static public function formatToSongPath(path:String) {
		var invalidChars = ~/[~&\\;:<>#]/;
		var hideChars = ~/[.,'"%?!]/;

		var path = invalidChars.split(path.replace(' ', '-')).join("-");
		return hideChars.split(path).join("").toLowerCase();
	}

	public static var currentTrackedSounds:Map<String, Sound> = [];
	public static function returnSound(path:String, key:String, ?library:String) {
		#if MODS_ALLOWED
		var file:String = modsSounds(path, key);
		if(FileSystem.exists(file)) {
			if(!currentTrackedSounds.exists(file)) {
				currentTrackedSounds.set(file, Sound.fromFile(file));
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
				currentTrackedSounds.set(gottenPath, Sound.fromFile(fileToLoad));
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
		localTrackedAssets.push(gottenPath);
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
}
