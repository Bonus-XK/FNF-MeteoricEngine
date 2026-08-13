package backend;

import flixel.FlxSubState;

class MusicBeatSubstate extends FlxSubState
{
	#if LUA_ALLOWED
	// 界面脚本系统：该界面上运行的自定义 Lua 脚本（menus/<界面名>.lua）
	public var uiScripts:Array<psychlua.MenuScript> = [];
	#end

	public function new()
	{
		super();
	}

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return Controls.instance;

	override function update(elapsed:Float)
	{
		//everyStep();
		if(!persistentUpdate) MusicBeatState.timePassedOnState += elapsed;
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if(curStep > 0)
				stepHit();

			if(PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		super.update(elapsed);

		#if LUA_ALLOWED
		for(script in uiScripts)
			script.update(elapsed);
		#end
	}

	// 加载界面脚本：menus/<name>.lua（可被 mod 覆盖）
	public function loadUIscripts(name:String)
	{
		#if LUA_ALLOWED
		var scriptPath:String = psychlua.MenuScript.findScriptPath(name);
		if(scriptPath != null)
			uiScripts.push(new psychlua.MenuScript(this, scriptPath));
		#end
	}

	// 向界面脚本广播事件（如 onChangeSelection、onConfirm）
	public function callUIScripts(funcName:String, ?args:Array<Dynamic> = null)
	{
		#if LUA_ALLOWED
		if(args == null) args = [];
		for(script in uiScripts)
			script.call(funcName, args);
		#end
	}

	override function destroy()
	{
		#if LUA_ALLOWED
		for(script in uiScripts)
			script.destroy();
		uiScripts = [];
		#end
		super.destroy();
	}

	private function updateSection():Void
	{
		if(stepsToDo < 1) stepsToDo = Math.round(getBeatsOnSection() * 4);
		while(curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if(curStep < 0) return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if(stepsToDo > curStep) break;
				
				curSection++;
			}
		}

		if(curSection > lastSection) sectionHit();
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep/4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		//do literally nothing dumbass
	}
	
	public function sectionHit():Void
	{
		//yep, you guessed it, nothing again, dumbass
	}
	
	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}
