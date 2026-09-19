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

	#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
	/** CNE 式状态脚本组（编程层；总开关关闭时恒为 null） */
	public var cneScripts:cne.ScriptPack = null;
	/** ModState/ModSubState 指定的脚本名；null = 用类名 */
	public var cneScriptName:String = null;
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

	/** 菜单音乐（assets/music/freakyMenu.ogg）的节拍速度。
	 *  取自启动初值：TitleState.create() 会执行 `Conductor.bpm = titleJSON.bpm`，
	 *  而 assets/preload/images/gfDanceTitle.json 的 bpm = 102。
	 *  三个节拍跳动界面（主菜单/故事模式/自由游玩）都用它，保证"跳动手感 = 启动时的手感"。 */
	public static inline var MENU_BPM:Float = 102;

	/** 把 Conductor 的节拍基准复位到菜单音乐：设置 BPM 并清空上一首歌残留的换速表。
	 *  Conductor.bpm / bpmChangeMap 是 static，PlayState 每首歌都会写入（含段落换速），
	 *  出曲后不清就会让菜单按"上一首歌的 BPM"算拍 → 跳动频率与曲目挂钩。
	 *  只在真正做节拍跳动的界面调用；必须在各界面设好背景音乐之后、update 之前调用。 */
	public function resetMenuBeat():Void
	{
		Conductor.bpm = MENU_BPM;   // 走 setter，同步 crochet / stepCrochet
		Conductor.bpmChangeMap = [];
		resetBPMChangeCache();
	}

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

		#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
		cne.ProgrammingManager.onStateCreate(this);
		#end
	}

	public static var timePassedOnState:Float = 0;
	override function update(elapsed:Float)
	{
		#if sys
		backend.ModInstaller.update(elapsed);
		#end
		// Meteoric：主线程维护（每帧分片异步解码 + 每 60s 清理未用贴图/声音）
		#if desktop
		backend.Paths.tickMaintenance(elapsed);
		#end
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

		#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
		cne.ProgrammingManager.onStateUpdate(this, elapsed);
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
		#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
		cne.ProgrammingManager.onStateDestroy(this);
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

	/** 是否处于 FlxState.resetSubState() 调用栈内（子状态关闭/替换的重入窗口）。
	 *  供 startTransition 判断是否需要延后开转场层，避免转场层被下一次 resetSubState 销毁。 */
	public static var inSubStateReset:Bool = false;

	override public function resetSubState():Void
	{
		inSubStateReset = true;
		super.resetSubState();
		inSubStateReset = false;
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

		// 重入保护（P0 修复）：**仅当处于 FlxState.resetSubState() 调用栈内**（即正由某个子状态的关闭/替换流程
		// 驱动、典型是子状态 closeCallback 里发起转场，例如结算界面「继续」→ 回自由选歌）时延后。
		// 此时直接 openSubState 会落进 flixel 的重入窗口：嵌套请求让**下一次** resetSubState 把刚建好的转场层
		// 当作「旧子状态」销毁（destroySubStates 默认 true）→ 转场层 update 永不执行 → finishCallback 永不触发 → 永久卡住。
		// 注意：**不能**用「当前有子状态」作判据 —— 暂停菜单「返回主菜单」等路径正是在子状态仍开着时切换，
		// 原逻辑靠 openSubState 替换掉该子状态，延后会永不执行（早期版本曾因此卡死，已修正）。
		if (inSubStateReset)
		{
			var deferredState:FlxState = nextState;
			FlxG.signals.postUpdate.addOnce(function() startTransition(deferredState));
			return;
		}

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

		#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
		cne.ProgrammingManager.onStateStep(this, curStep);
		#end

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

		#if (HSCRIPT_ALLOWED && SScript >= "3.0.3" && sys)
		cne.ProgrammingManager.onStateBeat(this, curBeat);
		#end
	}

	/**
	 * 界面节拍跳动：主菜单/故事模式/自由游玩等播放背景音乐的界面，
	 * 每个节拍让整屏轻微放大再回弹（由设置「界面节拍跳动」menuBeatBump 控制）。
	 * 调用方需已同步时钟（`Conductor.syncToMusic()`，否则节拍事件不触发）。
	 */
	public function menuBeatBump():Void
	{
		if (!ClientPrefs.data.menuBeatBump) return;
		var cam:FlxCamera = FlxG.camera;
		if (cam == null) return;
		FlxTween.cancelTweensOf(cam);
		cam.zoom = 1.015;
		FlxTween.tween(cam, {zoom: 1.0}, 0.15, {ease: FlxEase.quadOut});
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
