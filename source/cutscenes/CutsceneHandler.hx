package cutscenes;

import flixel.FlxBasic;
import flixel.util.FlxSort;

class CutsceneHandler extends FlxBasic
{
	public var timedEvents:Array<Dynamic> = [];
	public var finishCallback:Void->Void = null;
	public var finishCallback2:Void->Void = null;
	public var onStart:Void->Void = null;
	public var skipCallback:Void->Void = null; //Psych 1.0.4：长按跳过过场时调用
	public var endTime:Float = 0;
	public var objects:Array<FlxSprite> = [];
	public var music:String = null;
	final _timeToSkip:Float = 1;
	var holdingTime:Float = 0;
	public function new()
	{
		super();

		timer(0, function()
		{
			if(music != null)
			{
				FlxG.sound.playMusic(Paths.music(music), 0, false);
				FlxG.sound.music.fadeIn();
			}
			if(onStart != null) onStart();
		});
		PlayState.instance.add(this);
	}

	private var cutsceneTime:Float = 0;
	private var firstFrame:Bool = false;
	override function update(elapsed)
	{
		super.update(elapsed);

		if(FlxG.state != PlayState.instance || !firstFrame)
		{
			firstFrame = true;
			return;
		}

		cutsceneTime += elapsed;

		// Psych 1.0.4：长按 accept 跳过过场（skipCallback 为空时退化为直接完成，兼容老场景）
		if(cutsceneTime > 0.1)
		{
			if(Controls.instance.pressed('accept'))
				holdingTime = Math.max(0, Math.min(_timeToSkip, holdingTime + elapsed));
			else if (holdingTime > 0)
				holdingTime = Math.max(0, holdingTime - elapsed * 3);
		}

		if(endTime <= cutsceneTime || holdingTime >= _timeToSkip)
		{
			if(holdingTime >= _timeToSkip)
			{
				if(skipCallback != null) skipCallback();
				else finishCallback();
			}
			else
			{
				finishCallback();
				if(finishCallback2 != null) finishCallback2();
			}

			for (spr in objects)
			{
				spr.kill();
				PlayState.instance.remove(spr);
				spr.destroy();
			}
			
			kill();
			destroy();
			PlayState.instance.remove(this);
		}
		
		while(timedEvents.length > 0 && timedEvents[0][0] <= cutsceneTime)
		{
			timedEvents[0][1]();
			timedEvents.splice(0, 1);
		}
	}

	public function push(spr:FlxSprite)
	{
		objects.push(spr);
	}

	public function timer(time:Float, func:Void->Void)
	{
		timedEvents.push([time, func]);
		timedEvents.sort(sortByTime);
	}

	function sortByTime(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}
}