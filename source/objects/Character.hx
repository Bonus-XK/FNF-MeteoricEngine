package objects;

import animateatlas.AtlasFrameMaker;
#if flxanimate
import flxanimate.PsychFlxAnimate;
#end

import flixel.util.FlxSort;

#if MODS_ALLOWED
import sys.io.File;
import sys.FileSystem;
#end
import openfl.utils.AssetType;
import openfl.utils.Assets;
import tjson.TJSON as Json;

import backend.Song;
import backend.Section;
import states.stages.objects.TankmenBG;

typedef CharacterFile = {
	var animations:Array<AnimArray>;
	var image:String;
	var scale:Float;
	var sing_duration:Float;
	var healthicon:String;

	var position:Array<Float>;
	var camera_position:Array<Float>;

	var flip_x:Bool;
	var no_antialiasing:Bool;
	var healthbar_colors:Array<Int>;
	// Psych 0.7.3 字段
	var vocals_file:String;
	@:optional var _editor_isPlayer:Null<Bool>;
}

typedef AnimArray = {
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

class Character extends FlxSprite
{
	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

	public var colorTween:FlxTween;
	public var holdTimer:Float = 0;
	var _lastSing:Bool = false; // 【视觉修复】玩家侧 sing→idle 兜底：记录上一帧是否处于 sing（播完被清空也能恢复）
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var animationNotes:Array<Dynamic> = [];
	public var stunned:Bool = false;
	public var singDuration:Float = 4; //Multiplier of how long a character holds the sing pose
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false; //Character use "danceLeft" and "danceRight" instead of "idle"
	public var skipDance:Bool = false;

	public var healthIcon:String = 'face';
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];

	// Atlas（Adobe Animate 2020 spritemap1）支持：与 Psych 0.7 一致，FlxAnimate 运行时渲染
	#if flxanimate
	public var isAnimateAtlas:Bool = false;
	public var atlas:PsychFlxAnimate;
	public var lastPlayedAnimName:String = '';
	#end

	public var hasMissAnimations:Bool = false;

	//Used on Character Editor
	public var imageFile:String = '';
	public var jsonScale:Float = 1;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var healthColorArray:Array<Int> = [255, 0, 0];
	public var vocalsFile:String = ''; //Psych 0.7.3 split vocals：角色专属人声音轨（Voices-Player/Voices-Opponent）

	public static var DEFAULT_CHARACTER:String = 'bf'; //In case a character is missing, it will use BF on its place
	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false)
	{
		super(x, y);

		animOffsets = new Map<String, Array<Dynamic>>();
		curCharacter = character;
		this.isPlayer = isPlayer;
		var library:String = null;
		switch (curCharacter)
		{
			//case 'your character name in case you want to hardcode them instead':

			default:
				var characterPath:String = 'characters/' + curCharacter + '.json';

				#if MODS_ALLOWED
				var path:String = Paths.modFolders(characterPath);
				if (!FileSystem.exists(path)) {
					path = Paths.getPreloadPath(characterPath);
				}

				if (!FileSystem.exists(path))
				#else
				var path:String = Paths.getPreloadPath(characterPath);
				if (!Assets.exists(path))
				#end
				{
					path = Paths.getPreloadPath('characters/' + DEFAULT_CHARACTER + '.json'); //If a character couldn't be found, change him to BF just to prevent a crash
				}

				#if MODS_ALLOWED
				var rawJson = File.getContent(path);
				#else
				var rawJson = Assets.getText(path);
				#end

				var json:CharacterFile = cast Json.parse(rawJson);
				var useAtlas:Bool = false;

				#if MODS_ALLOWED
				var modAnimToFind:String = Paths.modFolders('images/' + json.image + '/Animation.json');
				var animToFind:String = Paths.getPath('images/' + json.image + '/Animation.json', TEXT);
				if (FileSystem.exists(modAnimToFind) || FileSystem.exists(animToFind) || Assets.exists(animToFind))
				#else
				if (Assets.exists(Paths.getPath('images/' + json.image + '/Animation.json', TEXT)))
				#end
					useAtlas = true;

				// 2020 格式（spritemap1.json 存在）→ FlxAnimate（Psych 0.7 官方方案）；
				// 旧格式（spritemap.json）→ animateatlas（原有路径）
				#if flxanimate
				var is2020Atlas:Bool = false;
				#if MODS_ALLOWED
				is2020Atlas = FileSystem.exists(Paths.modFolders('images/' + json.image + '/spritemap1.json'));
				if (!is2020Atlas)
				{
					// 与 useAtlas 检测同款：getPath 返回文件系统路径（shared/内置），用 FileSystem 检查
					var sp1Find:String = Paths.getPath('images/' + json.image + '/spritemap1.json', TEXT);
					is2020Atlas = FileSystem.exists(sp1Find) || Assets.exists(sp1Find);
				}
				#else
				is2020Atlas = Assets.exists(Paths.getPath('images/' + json.image + '/spritemap1.json', TEXT));
				#end
				isAnimateAtlas = useAtlas && is2020Atlas;
				#end

				if(!useAtlas)
					frames = Paths.getMultiAtlas(json.image.split(',')); //Psych 1.0.4：多图集角色（pico-playable 等）
				#if flxanimate
				else if (isAnimateAtlas)
				{
					atlas = new PsychFlxAnimate();
					atlas.showPivot = false;
					try
					{
						Paths.loadAnimateAtlas(atlas, json.image);
					}
					catch (e:Dynamic)
					{
						trace('Could not load atlas ' + json.image + ': ' + Std.string(e));
					}
				}
				#end
				else
					frames = AtlasFrameMaker.construct(json.image);

				imageFile = json.image;
				vocalsFile = json.vocals_file != null ? json.vocals_file : '';
				if(json.scale != 1) {
					jsonScale = json.scale;
					setGraphicSize(Std.int(width * jsonScale));
					updateHitbox();
				}

				// positioning
				positionArray = json.position;
				cameraPosition = json.camera_position;

				// data
				healthIcon = json.healthicon;
				singDuration = json.sing_duration;
				flipX = (json.flip_x == true);

				if(json.healthbar_colors != null && json.healthbar_colors.length > 2)
					healthColorArray = json.healthbar_colors;

				// antialiasing
				noAntialiasing = (json.no_antialiasing == true);
				antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

				// animations
				animationsArray = json.animations;
				if(animationsArray != null && animationsArray.length > 0) {
					for (anim in animationsArray) {
						var animAnim:String = '' + anim.anim;
						var animName:String = '' + anim.name;
						var animFps:Int = anim.fps;
						var animLoop:Bool = !!anim.loop; //Bruh
						var animIndices:Array<Int> = anim.indices;
						#if flxanimate
						if (isAnimateAtlas)
						{
							// Psych 0.7：动画名 = SD 符号完整路径（addBySymbol）
							if(animIndices != null && animIndices.length > 0)
								atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, animFps, animLoop);
							else
								atlas.anim.addBySymbol(animAnim, animName, animFps, animLoop);
						}
						else
						#end
						{
							if(animIndices != null && animIndices.length > 0) {
								animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop);
							} else {
								animation.addByPrefix(animAnim, animName, animFps, animLoop);
							}
						}

						if(anim.offsets != null && anim.offsets.length > 1) {
							addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
						}
					}
				} else {
					quickAnimAdd('idle', 'BF idle dance');
				}
				#if flxanimate
				if(isAnimateAtlas) copyAtlasValues();
				#end
				//trace('Loaded file to character ' + curCharacter);
		}
		originalFlipX = flipX;

		if(animOffsets.exists('singLEFTmiss') || animOffsets.exists('singDOWNmiss') || animOffsets.exists('singUPmiss') || animOffsets.exists('singRIGHTmiss')) hasMissAnimations = true;
		recalculateDanceIdle();
		dance();

		if (isPlayer)
		{
			flipX = !flipX;

			/*// Doesn't flip for BF, since his are already in the right place???
			if (!curCharacter.startsWith('bf'))
			{
				// var animArray
				if(animation.getByName('singLEFT') != null && animation.getByName('singRIGHT') != null)
				{
					var oldRight = animation.getByName('singRIGHT').frames;
					animation.getByName('singRIGHT').frames = animation.getByName('singLEFT').frames;
					animation.getByName('singLEFT').frames = oldRight;
				}

				// IF THEY HAVE MISS ANIMATIONS??
				if (animation.getByName('singLEFTmiss') != null && animation.getByName('singRIGHTmiss') != null)
				{
					var oldMiss = animation.getByName('singRIGHTmiss').frames;
					animation.getByName('singRIGHTmiss').frames = animation.getByName('singLEFTmiss').frames;
					animation.getByName('singLEFTmiss').frames = oldMiss;
				}
			}*/
		}

		switch(curCharacter)
		{
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
		}
	}

	#if flxanimate
	override function destroy()
	{
		// 2020 图集角色：atlas 是独立字段（未 add 进场景），若不显式销毁，
		// 其 graphic（图集 FlxGraphic）useCount 永不为 0 → clearUnusedMemory 常跳过
		// → 退出对局后所有 2020 角色图集内存泄漏（PlayState→菜单 220MB 残留的根因）
		if (atlas != null)
		{
			atlas.destroy();
			atlas = null;
		}
		super.destroy();
	}
	#end

	override function update(elapsed:Float)
	{
		#if flxanimate
		if (isAnimateAtlas) atlas.update(elapsed);

		#end
		if (debugMode || isAnimationNull())
		{
			super.update(elapsed);
			return;
		}

		if(heyTimer > 0)
		{
			heyTimer -= elapsed * (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
			if(heyTimer <= 0)
			{
				var animName:String = getAnimationName();
				if(specialAnim && (animName == 'hey' || animName == 'cheer'))
				{
					specialAnim = false;
					dance();
				}
				heyTimer = 0;
			}
		}
		else if(specialAnim && isAnimationFinished())
		{
			specialAnim = false;
			dance();
		}
		else if (getAnimationName().endsWith('miss') && isAnimationFinished())
		{
			dance();
			finishAnimation();
		}

		switch(curCharacter)
		{
			case 'pico-speaker':
				if(animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0])
				{
					var noteData:Int = 1;
					if(animationNotes[0][1] > 2) noteData = 3;

					noteData += FlxG.random.int(0, 1);
					playAnim('shoot' + noteData, true);
					animationNotes.shift();
				}
				if(isAnimationFinished()) playAnim(getAnimationName(), false, false, getAnimationLength() - 3);
		}

		var bfSinging:Bool = getAnimationName().startsWith('sing');
		if (bfSinging)
		{
			holdTimer += elapsed;
			_lastSing = true;
		}
		else if(isPlayer)
		{
			holdTimer = 0;
			// 【视觉修复】播放完 sing 且已无 sing 名（含动画播完被控制器清空 curAnim 的"定格"情形）：
			// PlayState 的回块依赖 name 仍以 sing 开头，此情形下永远不触发 → BF 卡在最后 sing 帧。
			// 这里在角色自身兜底回 idle（与下方 !isPlayer 阈值同款、已被对手路径验证有效）。
			if (_lastSing)
			{
				_lastSing = false;
				if (isAnimationNull() || isAnimationFinished()) dance();
			}
		}

		var singThreshold:Float = Conductor.stepCrochet * (0.0011 / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1)) * singDuration;
		if (!isPlayer && holdTimer >= singThreshold)
		{
			dance();
			holdTimer = 0;
		}
		// 【视觉修复】玩家侧同款阈值回 idle（原只由 PlayState 块驱动；此处保证任何路径都能恢复）
		else if (isPlayer && bfSinging && holdTimer >= singThreshold)
		{
			dance();
			holdTimer = 0;
			_lastSing = false;
		}

		var curName:String = getAnimationName();
		if (isAnimationFinished() && animOffsets.exists('$curName-loop'))
			playAnim('$curName-loop');

		super.update(elapsed);
	}

	#if flxanimate
	inline public function isAnimationNull():Bool
		return !isAnimateAtlas ? (animation.curAnim == null) : (atlas.anim.curSymbol == null);

	inline public function getAnimationName():String
	{
		var name:String = '';
		if(!isAnimationNull()) name = !isAnimateAtlas ? animation.curAnim.name : lastPlayedAnimName;
		return (name != null) ? name : '';
	}

	public function isAnimationFinished():Bool
	{
		if (isAnimationNull()) return false;
		return !isAnimateAtlas ? animation.curAnim.finished : atlas.anim.finished;
	}

	public function finishAnimation():Void
	{
		if (isAnimationNull()) return;
		if (!isAnimateAtlas) animation.curAnim.finish();
		else atlas.anim.curFrame = atlas.anim.length - 1;
	}

	public function getAnimationLength():Int
	{
		if (isAnimationNull()) return 0;
		if (!isAnimateAtlas) return animation.curAnim.frames.length;
		return atlas.anim.length;
	}
	#else
	inline public function isAnimationNull():Bool
		return animation.curAnim == null;

	inline public function getAnimationName():String
	{
		var name:String = '';
		if(!isAnimationNull()) name = animation.curAnim.name;
		return (name != null) ? name : '';
	}

	public function isAnimationFinished():Bool
	{
		if (isAnimationNull()) return false;
		return animation.curAnim.finished;
	}

	public function finishAnimation():Void
	{
		if (isAnimationNull()) return;
		animation.curAnim.finish();
	}

	public function getAnimationLength():Int
	{
		if (isAnimationNull()) return 0;
		return animation.curAnim.frames.length;
	}
	#end

	public var danced:Bool = false;

	/**
	 * FOR GF DANCING SHIT
	 */
	public function dance()
	{
		_lastSing = false;
		if (!debugMode && !skipDance && !specialAnim)
		{
			if(danceIdle)
			{
				danced = !danced;

				if (danced)
					playAnim('danceRight' + idleSuffix);
				else
					playAnim('danceLeft' + idleSuffix);
			}
			else if(animOffsets.exists('idle' + idleSuffix)) {
					playAnim('idle' + idleSuffix);
			}
		}
	}

	public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void
	{
		specialAnim = false;
		#if flxanimate
		if (isAnimateAtlas)
		{
			// Force=true：atlas 动画必须从指定帧重新播放。
			// flxanimate 4.0.0 的 play() 在 Force=false 且动画未 finished 时不会重置
			// curFrame（其内部 Force 判定在 curInstance 赋值之后求值，恒 false）；
			// 典型回归：qtDance 在 create 时被 dance() 自动播放，从曲首起就推进
			// 整段长舞时间轴，等到 222 拍显形时已播到后半段（final dance），
			// playAnim('qtDance','idle') 因不重启而继续后半段 → 播完停成静态待机。
			atlas.anim.play(AnimName, true, Reversed, Frame);
			atlas.update(0); // Psych 1.0.4：play 后立即解析首帧（否则首帧延迟一帧/可能不显示）
			lastPlayedAnimName = AnimName; // flxanimate 4.0.0 无 lastPlayedAnim，自行记录
		}
		else
		#end
			animation.play(AnimName, Force, Reversed, Frame);

		var daOffset = animOffsets.get(AnimName);
		if (animOffsets.exists(AnimName))
		{
			offset.set(daOffset[0], daOffset[1]);
		}
		else
			offset.set(0, 0);

		if (curCharacter.startsWith('gf'))
		{
			if (AnimName == 'singLEFT')
			{
				danced = true;
			}
			else if (AnimName == 'singRIGHT')
			{
				danced = false;
			}

			if (AnimName == 'singUP' || AnimName == 'singDOWN')
			{
				danced = !danced;
			}
		}
	}
	
	function loadMappedAnims():Void
	{
		var noteData:Array<SwagSection> = Song.loadFromJson('picospeaker', Paths.formatToSongPath(PlayState.SONG.song)).notes;
		for (section in noteData) {
			for (songNotes in section.sectionNotes) {
				animationNotes.push(songNotes);
			}
		}
		TankmenBG.animationNotes = animationNotes;
		animationNotes.sort(sortAnims);
	}

	function sortAnims(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	public var danceEveryNumBeats:Int = 2;
	private var settingCharacterUp:Bool = true;
	public function recalculateDanceIdle() {
		var lastDanceIdle:Bool = danceIdle;
		#if flxanimate
		danceIdle = isAnimateAtlas
			? (animOffsets.exists('danceLeft' + idleSuffix) && animOffsets.exists('danceRight' + idleSuffix))
			: (animation.getByName('danceLeft' + idleSuffix) != null && animation.getByName('danceRight' + idleSuffix) != null);
		#else
		danceIdle = (animation.getByName('danceLeft' + idleSuffix) != null && animation.getByName('danceRight' + idleSuffix) != null);
		#end

		if(settingCharacterUp)
		{
			danceEveryNumBeats = (danceIdle ? 1 : 2);
		}
		else if(lastDanceIdle != danceIdle)
		{
			var calc:Float = danceEveryNumBeats;
			if(danceIdle)
				calc /= 2;
			else
				calc *= 2;

			danceEveryNumBeats = Math.round(Math.max(calc, 1));
		}
		settingCharacterUp = false;
	}

	public function addOffset(name:String, x:Float = 0, y:Float = 0)
	{
		animOffsets[name] = [x, y];
	}

	public function quickAnimAdd(name:String, anim:String)
	{
		animation.addByPrefix(name, anim, 24, false);
	}

	#if flxanimate
	/** Atlas 模式：Character 不画自己，由 atlas 代替绘制（Psych 0.7 方案） */
	public override function draw()
	{
		if (isAnimateAtlas)
		{
			copyAtlasValues();
			atlas.draw();
			return;
		}
		super.draw();
	}

	public function copyAtlasValues()
	{
		@:privateAccess
		{
			atlas.cameras = cameras;
			atlas.scrollFactor = scrollFactor;
			atlas.scale = scale;
			atlas.offset = offset;
			atlas.origin = origin;
			atlas.x = x;
			atlas.y = y;
			atlas.angle = angle;
			atlas.alpha = alpha;
			atlas.visible = visible;
			atlas.flipX = flipX;
			atlas.flipY = flipY;
			atlas.shader = shader;
			atlas.antialiasing = antialiasing;
			atlas.colorTransform = colorTransform;
			atlas.color = color;
		}
	}
	#end
}
