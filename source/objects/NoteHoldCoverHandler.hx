package objects;

import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFramesCollection;
import backend.Paths;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;

/**
 * NoteHoldCover 原生移植（QT Rewired 模组 scripts/NoteHoldCover.lua 的引擎内实现）。
 *
 * 行为对齐（normalConfig）：
 *  - 8 个精灵：玩家 4 轨 + 对手 4 轨，跟随各自判定线（偏移 -100,-100），HUD 相机；
 *  - 命中长条（sustain）→ 显示并循环播放 'holding'，空按计数清零；
 *  - 空按计数达到 endDelay(10) 帧 → 播放一次 'holdEnd'，0.3 秒后隐藏；
 *  - 动画名与模组完全一致：holdCoverStart{Color} / holdCover{Color} / holdCoverEnd{Color}。
 *
 * 与模组的差异（有意的取舍）：
 *  - 模组的 pixel 分支引用 pixelNoteSplash 图集，其 XML imagePath 指向缺失的 spritesheet.png
 *    （模组自带资源就是坏的，pixel 阶段实际无覆盖层），故本移植只对非 pixel 阶段生效；
 *  - 模组若自带 NoteHoldCover.lua，PlayState 会跳过原生创建，避免双份覆盖层。
 */
class NoteHoldCoverHandler extends FlxSpriteGroup
{
	// 空按持续帧数（模组 endDelay=10）
	public static inline var END_DELAY:Int = 10;
	// holdEnd 播完后延迟隐藏（模组 timeTillDisappear=0.3 秒）
	public static inline var HIDE_DELAY:Float = 0.3;
	// 判定线偏移（模组 normalConfig offsets px/py/ox/oy=-100）
	public static inline var POS_OFFSET:Float = -100;

	static var colors:Array<String> = ['Purple', 'Blue', 'Green', 'Red'];

	/** Extra Keys：把整张图集按 lane 调色板 CPU 染色（覆盖层无着色器，与 StrumNote 移动端同管线） */
	static function tintAtlas(atlas:FlxAtlasFrames, loadPath:String, lane:Int):FlxAtlasFrames
	{
		try
		{
			if (atlas == null || atlas.parent == null || atlas.parent.bitmap == null || !atlas.parent.bitmap.readable)
				return atlas;
			var src:BitmapData = atlas.parent.bitmap;
			var tinted:BitmapData = src.clone();
			var pal:Array<FlxColor> = ExtraKeys.laneColors(lane, false);
			for (fr in atlas.frames)
			{
				if (fr == null || fr.frame == null) continue;
				var frc = fr.frame;
				var rect:Rectangle = new Rectangle(frc.x, frc.y, frc.width, frc.height);
				var frBmp:BitmapData = new BitmapData(Std.int(rect.width), Std.int(rect.height), true, 0x00000000);
				frBmp.copyPixels(src, rect, new Point(0, 0));
				objects.Note.applyRGBToBitmap(frBmp, pal[0], pal[1], pal[2]);
				tinted.copyPixels(frBmp, frBmp.rect, new Point(rect.x, rect.y));
			}
			var g = flixel.graphics.FlxGraphic.fromBitmapData(tinted, false, null, false);
			g.persist = true;
			var xmlData:String = Paths.getTextFromFile('images/' + loadPath + '.xml');
			if (xmlData != null && xmlData.length > 0)
				return FlxAtlasFrames.fromSparrow(g, xmlData);
		}
		catch (e:Dynamic) {}
		return atlas;
	}

	var holdSplashes:Array<FlxSprite> = [];
	var durations:Array<Int> = [];
	var hideCountdowns:Array<Float> = [];

	public function new()
	{
		super();

		// Extra Keys：精灵数 = 玩家 keys + 对手 keys，颜色按 lane%4 循环
		var total:Int = ExtraKeys.songKeys * 2;
		for (i in 0...total)
		{
			var lane:Int = i % ExtraKeys.songKeys;
			var color:String = colors[lane % colors.length];
			var spr:FlxSprite = new FlxSprite();
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas('noteHolding/holdCover' + color);
			if (atlas != null)
			{
				// Extra Keys：lane ≥ 4 循环复用 4 色覆盖层贴图 —— 覆盖层没有 RGB 着色器，
				// 必须 CPU 染成本 lane 调色板，否则长条覆盖与箭头体/溅射不同色
				if (lane >= colors.length)
					atlas = tintAtlas(atlas, 'noteHolding/holdCover' + color, lane);
				spr.frames = atlas;
				spr.animation.addByPrefix('holdStart', 'holdCoverStart' + color, 24, false);
				spr.animation.addByPrefix('holding', 'holdCover' + color, 24, true);
				spr.animation.addByPrefix('holdEnd', 'holdCoverEnd' + color, 24, false);
			}
			else
			{
				// 资源缺失兜底：1px 透明，绝不崩
				spr.makeGraphic(1, 1, 0);
			}
			spr.visible = false;
			spr.scrollFactor.set();
			spr.antialiasing = true;
			add(spr);
			holdSplashes.push(spr);
			durations.push(0);
			hideCountdowns.push(0);
		}
	}

	// 命中长条：显示 + 循环 'holding' + 清零空按计数（模组 sustainHolding）
	public function onHit(index:Int):Void
	{
		if (index < 0 || index >= holdSplashes.length) return;
		var spr:FlxSprite = holdSplashes[index];
		if (spr == null) return;
		durations[index] = 0;
		hideCountdowns[index] = 0;
		spr.visible = true;
		if (spr.animation.getByName('holding') != null)
			spr.animation.play('holding', true);
	}

	// 每帧跟随判定线位置（模组 onUpdate -> updateHoldSplashPos）
	public function syncPositions(playerStrums:FlxTypedGroup<StrumNote>, opponentStrums:FlxTypedGroup<StrumNote>):Void
	{
		// Extra Keys：前 keys 个 = 玩家各轨，后 keys 个 = 对手各轨
		var n:Int = Std.int(holdSplashes.length / 2);
		for (i in 0...n)
		{
			var strum:StrumNote = playerStrums.members[i];
			var spr:FlxSprite = holdSplashes[i];
			if (strum == null || spr == null) continue;
			spr.x = strum.x + POS_OFFSET;
			spr.y = strum.y + POS_OFFSET;
		}
		for (i in n...holdSplashes.length)
		{
			var strum:StrumNote = opponentStrums.members[i - n];
			var spr:FlxSprite = holdSplashes[i];
			if (strum == null || spr == null) continue;
			spr.x = strum.x + POS_OFFSET;
			spr.y = strum.y + POS_OFFSET;
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		for (i in 0...holdSplashes.length)
		{
			durations[i]++;
			// 模组语义：== endDelay 只触发一次（计数继续累加直到下次 onHit 清零）
			if (durations[i] == END_DELAY)
			{
				var spr:FlxSprite = holdSplashes[i];
				if (spr != null && spr.visible)
				{
					if (spr.animation.getByName('holdEnd') != null)
						spr.animation.play('holdEnd', false);
					else
						spr.visible = false;
					hideCountdowns[i] = HIDE_DELAY;
				}
			}

			if (hideCountdowns[i] > 0)
			{
				hideCountdowns[i] -= elapsed;
				if (hideCountdowns[i] <= 0)
				{
					hideCountdowns[i] = 0;
					var spr:FlxSprite = holdSplashes[i];
					if (spr != null) spr.visible = false;
				}
			}
		}
	}
}
