package backend;

import flixel.addons.ui.FlxUIState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxState;

class MusicBeatState extends FlxUIState
{
	#if LUA_ALLOWED
	// 界面脚本系统：该界面上运行的自定义 Lua 脚本（menus/<界面名>.lua）
	public var uiScripts:Array<psychlua.MenuScript> = [];
	#end

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	public var controls(get, never):Controls;
	private function get_controls()
	{
		return Controls.instance;
	}

	public static var camBeat:FlxCamera;

	override function create() {
		camBeat = FlxG.camera;
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		#if MODS_ALLOWED Mods.updatedOnState = false; #end

		super.create();

		#if mobile
		// 菜单/界面统一挂载 virtualpad A 键：触控选择，按 A 确认
		// Mods 界面与 HUD 自定义界面按需求不显示 A 键
		if (!Std.isOfType(this, PlayState)
			&& !Std.isOfType(this, states.ModsMenuState)
			&& !Std.isOfType(this, options.HUDCustomizeState))
		{
			add(new objects.MobileControls(true, FlxG.camera, -1, true));
		}
		#end

		if(!skip) {
			openSubState(new CustomFadeTransition(0.7, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
		timePassedOnState = 0;
	}

	public static var timePassedOnState:Float = 0;
	override function update(elapsed:Float)
	{
		backend.Diag.log();
		#if mobile
		// 安卓返回键 / 虚拟返回键（左上角 X）：默认退出游戏回到桌面；
		// 子类可重写 onAndroidBack 拦截（例如 PlayState 游玩中改为打开暂停菜单）
		var androidBack:Bool = false;
		#if android
		androidBack = FlxG.android.justPressed.BACK || FlxG.keys.justPressed.ESCAPE;
		#end
		if (androidBack
			|| (objects.MobileControls.instance != null && objects.MobileControls.instance.justPressed('exit')))
		{
			if (!onAndroidBack())
			{
				// 如果当前界面已经用 controls.BACK 处理了返回键（例如菜单返回上一级），
				// 就不要在这里强制退出，避免“刚返回上一级又立刻退出游戏”。
				#if android
				if (!controls.BACK)
				#end
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					Sys.exit(0);
					return;
				}
			}
		}
		#end

		//everyStep();
		var oldStep:Int = curStep;
		timePassedOnState += elapsed;

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

		if(FlxG.save.data != null) FlxG.save.data.fullscreen = FlxG.fullscreen;
		
		stagesFunc(function(stage:BaseStage) {
			stage.update(elapsed);
		});

		super.update(elapsed);

		#if LUA_ALLOWED
		for(script in uiScripts)
			script.update(elapsed);
		#end
	}

	/**
	 * 安卓返回键 / 虚拟返回键（左上角 X）按下时的回调。
	 * 返回 true 表示该按键已被本状态处理（不再退出游戏）；默认返回 false（退出到桌面）。
	 */
	#if mobile
	public function onAndroidBack():Bool
	{
		return false;
	}
	#end

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

	public function resetBPMChangeCache():Void
	{
		_lastBPMIndex = 0;
	}

	private var _lastBPMIndex:Int = 0;
	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSecondsCached(Conductor.songPosition, _lastBPMIndex);
		_lastBPMIndex = lastChange.index;

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public static function switchState(nextState:FlxState = null) {
		if(nextState == null) nextState = FlxG.state;
		if(nextState == FlxG.state)
		{
			resetState();
			return;
		}

		if(FlxTransitionableState.skipNextTransIn) FlxG.switchState(nextState);
		else startTransition(nextState);
		FlxTransitionableState.skipNextTransIn = false;
	}

	public static function resetState() {
		if(FlxTransitionableState.skipNextTransIn) FlxG.resetState();
		else startTransition();
		FlxTransitionableState.skipNextTransIn = false;
	}

	// Custom made Trans in
	public static function startTransition(nextState:FlxState = null)
	{
		if(nextState == null)
			nextState = FlxG.state;

		FlxG.state.openSubState(new CustomFadeTransition(0.6, false));
		if(nextState == FlxG.state)
			CustomFadeTransition.finishCallback = function() FlxG.resetState();
		else
			CustomFadeTransition.finishCallback = function() FlxG.switchState(nextState);
	}

	public static function getState():MusicBeatState {
		return cast (FlxG.state, MusicBeatState);
	}

	public function stepHit():Void
	{
		stagesFunc(function(stage:BaseStage) {
			stage.curStep = curStep;
			stage.curDecStep = curDecStep;
			stage.stepHit();
		});

		if (curStep % 4 == 0)
			beatHit();
	}

	public var stages:Array<BaseStage> = [];
	public function beatHit():Void
	{
		//trace('Beat: ' + curBeat);
		stagesFunc(function(stage:BaseStage) {
			stage.curBeat = curBeat;
			stage.curDecBeat = curDecBeat;
			stage.beatHit();
		});
	}

	public function sectionHit():Void
	{
		//trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
		stagesFunc(function(stage:BaseStage) {
			stage.curSection = curSection;
			stage.sectionHit();
		});
	}

	function stagesFunc(func:BaseStage->Void)
	{
		for (stage in stages)
			if(stage != null && stage.exists && stage.active)
				func(stage);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}
