package backend;

import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;

import states.TitleState;

// Add a variable here and it will get automatically saved
class SaveVariables {
	@:keep public var downScroll:Bool = false;
	@:keep public var middleScroll:Bool = false;
	@:keep public var opponentStrums:Bool = true;
	@:keep public var showFPS:Bool = true;
	@:keep public var showVer:Bool = true;
	@:keep public var fpsInTitleBar:Bool = false;
	@:keep public var fpsColor:String = '自动';
	@:keep public var showScrollSpeed:Bool = true; // FPS 计数器下方显示当前滚动速度（颜色随速度变化）
	@:keep public var flashing:Bool = true;
	@:keep public var CustomFade:String = '移动';
	@:keep public var CustomFadeText:Bool = true;
	@:keep public var autoPause:Bool = true;
	@:keep public var antialiasing:Bool = true;
	@:keep public var noteSkin:String = 'Default';
	@:keep public var splashSkin:String = 'Psych';
	@:keep public var splashAlpha:Float = 0.6;
	@:keep public var lowQuality:Bool = false;
	@:keep public var shaders:Bool = true;
	@:keep public var cacheOnGPU:Bool = #if !switch false #else true #end; //From Stilic
	@:keep public var framerate:Int = 120;
	@:keep public var camZooms:Bool = true;
	@:keep public var hideHud:Bool = false;
	@:keep public var scoreTxtFont:String = '默认';
	@:keep public var hideWatermark:Bool = false;
	@:keep public var healthBarOverlay:Bool = true;
	@:keep public var oldHealthBar:Bool = false; // Psych 0.6.3 旧版血量条（兼容 0.6.3 及以下的旧模组）
	public var noteOffset:Int = 0;
	public var arrowRGB:Array<Array<FlxColor>> = [
		[0xFFC24B99, 0xFFFFFFFF, 0xFF3C1F56],
		[0xFF00FFFF, 0xFFFFFFFF, 0xFF1542B7],
		[0xFF12FA05, 0xFFFFFFFF, 0xFF0A4447],
		[0xFFF9393F, 0xFFFFFFFF, 0xFF651038]];
	public var arrowRGBPixel:Array<Array<FlxColor>> = [
		[0xFFE276FF, 0xFFFFF9FF, 0xFF60008D],
		[0xFF3DCAFF, 0xFFF4FFFF, 0xFF003060],
		[0xFF71E300, 0xFFF6FFE6, 0xFF003100],
		[0xFFFF884E, 0xFFFFFAF5, 0xFF6C0000]];

	@:keep public var ghostTapping:Bool = true;
	@:keep public var smoothHealth:Bool = true;
	@:keep public var sbIconBop:Bool = true;
	@:keep public var keIconBop:Bool = false;
	@:keep public var timeBarType:String = '剩余时间';
	@:keep public var newTimeBarStyle:Bool = false;
	@:keep public var timeBarOpponentColors:Bool = false; // 时间条填充色跟随对方角色血量颜色（贴图样式下生效）
	@:keep public var noReset:Bool = false;
	@:keep public var restartNoChartReload:Bool = false;
	@:keep public var rewindOnRestart:Bool = true;
	@:keep public var healthBarAlpha:Float = 1;
	@:keep public var hitsoundVolume:Float = 0;
	@:keep public var pauseMusic:String = 'Tea Time';
	@:keep public var checkForUpdates:Bool = true;
	@:keep public var comboStacking:Bool = false;
	@:keep public var comboStackMigrated:Bool = false;
	@:keep public var preRenderNotes:Bool = false; // 提前渲染：加载曲目时烘焙音符贴图，优化大谱面堆叠（开启后会牺牲加载速度）
	@:keep public var psych063Mode:Bool = false; // Psych Engine 0.6.3 兼容模式：关闭强制烘焙，兼容旧版箭头贴图格式
	@:keep public var mobileControlsMode:Int = 0; // 移动端触控板模式：0右手 1左手 2自定义 3双手 4判定区 5无按键
	public var gameplaySettings:Map<String, Dynamic> = [
		'scrollspeed' => 1.0,
		'scrolltype' => 'multiplicative', 
		// anyone reading this, amod is multiplicative speed mod, cmod is constant speed mod, and xmod is bpm based speed mod.
		// an amod example would be chartSpeed * multiplier
		// cmod would just be constantSpeed = chartSpeed
		// and xmod basically works by basing the speed on the bpm.
		// iirc (beatsPerSecond * (conductorToNoteDifference / 1000)) * noteSize (110 or something like that depending on it, prolly just use note.height)
		// bps is calculated by bpm / 60
		// oh yeah and you'd have to actually convert the difference to seconds which I already do, because this is based on beats and stuff. but it should work
		// just fine. but I wont implement it because I don't know how you handle sustains and other stuff like that.
		// oh yeah when you calculate the bps divide it by the songSpeed or rate because it wont scroll correctly when speeds exist.
		// -kade
		'songspeed' => 1.0,
		'healthgain' => 1.0,
		'healthloss' => 1.0,
		'instakill' => false,
		'opponentpush' => false,
		'practice' => false,
		'botplay' => false,
		'opponentplay' => false,
		'infiniteloop' => false
	];

	@:keep public var comboOffset:Array<Int> = [0, 0, 0, 0];
	@:keep public var ratingOffset:Int = 0;
	@:keep @:keep public var sickWindow:Int = 45;
	@:keep @:keep public var goodWindow:Int = 90;
	@:keep @:keep public var badWindow:Int = 135;
	@:keep public var safeFrames:Float = 10;
	@:keep public var noteJudgment:String = 'PE 判定';
	@:keep public var phigrosStyle:Bool = false; // Phigros 式判定线玩法
	@:keep public var discordRPC:Bool = true;
	@:keep public var hudLayout:Map<String, Array<Float>> = [ // 自定义界面：HUD 元素相对默认位置的偏移 [x, y]
		'note' => [0, 0],
		'timeBar' => [0, 0],
		'healthBar' => [0, 0],
		'score' => [0, 0],
		'watermark' => [0, 0]
	];

	public function new()
	{
		//Why does haxe needs this again?
	}
}

class ClientPrefs {
	public static var data:SaveVariables = null;
	public static var defaultData:SaveVariables = null;
	// 记录用户真实的 hideHud 设置，防止 Mod 脚本临时修改后污染后续对局
	public static var savedHideHud:Bool = false;

	//Every key has two binds, add your key bind down here and then add your control on options/ControlsSubState.hx and Controls.hx
	public static var keyBinds:Map<String, Array<FlxKey>> = [
		//Key Bind, Name for ControlsSubState
		'note_up'		=> [W, UP],
		'note_left'		=> [A, LEFT],
		'note_down'		=> [S, DOWN],
		'note_right'	=> [D, RIGHT],
		
		'ui_up'			=> [W, UP],
		'ui_left'		=> [A, LEFT],
		'ui_down'		=> [S, DOWN],
		'ui_right'		=> [D, RIGHT],
		
		'accept'		=> [SPACE, ENTER],
		'back'			=> [BACKSPACE, ESCAPE],
		'pause'			=> [ENTER, ESCAPE],
		'reset'			=> [R],
		
		'volume_mute'	=> [ZERO],
		'volume_up'		=> [NUMPADPLUS, PLUS],
		'volume_down'	=> [NUMPADMINUS, MINUS],
		
		'debug_1'		=> [SEVEN],
		'debug_2'		=> [EIGHT]
	];
	public static var gamepadBinds:Map<String, Array<FlxGamepadInputID>> = [
		'note_up'		=> [DPAD_UP, Y],
		'note_left'		=> [DPAD_LEFT, X],
		'note_down'		=> [DPAD_DOWN, A],
		'note_right'	=> [DPAD_RIGHT, B],
		
		'ui_up'			=> [DPAD_UP, LEFT_STICK_DIGITAL_UP],
		'ui_left'		=> [DPAD_LEFT, LEFT_STICK_DIGITAL_LEFT],
		'ui_down'		=> [DPAD_DOWN, LEFT_STICK_DIGITAL_DOWN],
		'ui_right'		=> [DPAD_RIGHT, LEFT_STICK_DIGITAL_RIGHT],
		
		'accept'		=> [A, START],
		'back'			=> [B],
		'pause'			=> [START],
		'reset'			=> [BACK]
	];
	public static var defaultKeys:Map<String, Array<FlxKey>> = null;
	public static var defaultButtons:Map<String, Array<FlxGamepadInputID>> = null;

	public static function resetKeys(controller:Null<Bool> = null) //Null = both, False = Keyboard, True = Controller
	{
		if(controller != true)
		{
			for (key in keyBinds.keys())
			{
				if(defaultKeys.exists(key))
					keyBinds.set(key, defaultKeys.get(key).copy());
			}
		}
		if(controller != false)
		{
			for (button in gamepadBinds.keys())
			{
				if(defaultButtons.exists(button))
					gamepadBinds.set(button, defaultButtons.get(button).copy());
			}
		}
	}

	public static function clearInvalidKeys(key:String) {
		var keyBind:Array<FlxKey> = keyBinds.get(key);
		var gamepadBind:Array<FlxGamepadInputID> = gamepadBinds.get(key);
		while(keyBind != null && keyBind.contains(NONE)) keyBind.remove(NONE);
		while(gamepadBind != null && gamepadBind.contains(NONE)) gamepadBind.remove(NONE);
	}

	public static function loadDefaultKeys() {
		defaultKeys = keyBinds.copy();
		defaultButtons = gamepadBinds.copy();
	}

	public static function saveSettings() {
		for (key in Reflect.fields(data)) {
			//trace('saved variable: $key');
			Reflect.setField(FlxG.save.data, key, Reflect.field(data, key));
		}
		// 设置保存视为用户真实意图：同步 hideHud 基准值，避免进入对局后被 resetHideHud/enforceHUD 撤销
		savedHideHud = data.hideHud;
		FlxG.save.data.achievementsMap = Achievements.achievementsMap;
		FlxG.save.data.henchmenDeath = Achievements.henchmenDeath;
		FlxG.save.flush();

		//Placing this in a separate save so that it can be manually deleted without removing your Score and stuff
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		save.data.keyboard = keyBinds;
		save.data.gamepad = gamepadBinds;
		save.flush();
		FlxG.log.add("Settings saved!");
	}

	public static function resetHideHud() {
		if (data != null) data.hideHud = savedHideHud;
	}

	public static function loadPrefs() {
		if(data == null) data = new SaveVariables();
		if(defaultData == null) defaultData = new SaveVariables();

		for (key in Reflect.fields(data)) {
			if (key != 'gameplaySettings' && Reflect.hasField(FlxG.save.data, key)) {
				//trace('loaded variable: $key');
				Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));
			}
		}
		savedHideHud = data.hideHud;

		// 判定选项旧值迁移：'新版' -> 'KE 判定'，'旧判定' -> 'PE 判定'
		if (data.noteJudgment == '新版' || data.noteJudgment == '旧判定')
			data.noteJudgment = (data.noteJudgment == '新版') ? 'KE 判定' : 'PE 判定';

		// 连击堆叠旧值迁移：新默认不堆叠（评级/连击数字图片不再叠成一片），只迁移一次，之后尊重用户手动选择
		if (!data.comboStackMigrated)
		{
			data.comboStackMigrated = true;
			if (data.comboStacking) data.comboStacking = false;
			saveSettings();
		}
		
		if(Main.fpsVar != null) {
			Main.fpsVar.applyDisplayMode();
		}

		#if (!html5 && !switch)
		FlxG.autoPause = ClientPrefs.data.autoPause;
		#end

		if(data.framerate > FlxG.drawFramerate) {
			FlxG.updateFramerate = data.framerate;
			FlxG.drawFramerate = data.framerate;
		} else {
			FlxG.drawFramerate = data.framerate;
			FlxG.updateFramerate = data.framerate;
		}

		if(FlxG.save.data.gameplaySettings != null) {
			var savedMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			for (name => value in savedMap)
				data.gameplaySettings.set(name, value);
		}
		
		// flixel automatically saves your volume!
		if(FlxG.save.data.volume != null)
			FlxG.sound.volume = FlxG.save.data.volume;
		if (FlxG.save.data.mute != null)
			FlxG.sound.muted = FlxG.save.data.mute;

		#if desktop
		DiscordClient.check();
		#end

		// controls on a separate save file
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		if(save != null)
		{
			if(save.data.keyboard != null) {
				var loadedControls:Map<String, Array<FlxKey>> = save.data.keyboard;
				for (control => keys in loadedControls) {
					if(keyBinds.exists(control)) keyBinds.set(control, keys);
				}
			}
			if(save.data.gamepad != null) {
				var loadedControls:Map<String, Array<FlxGamepadInputID>> = save.data.gamepad;
				for (control => keys in loadedControls) {
					if(gamepadBinds.exists(control)) gamepadBinds.set(control, keys);
				}
			}
			reloadVolumeKeys();
		}
	}

	inline public static function getGameplaySetting(name:String, defaultValue:Dynamic = null, ?customDefaultValue:Bool = false):Dynamic {
		if(!customDefaultValue) defaultValue = defaultData.gameplaySettings.get(name);
		return /*PlayState.isStoryMode ? defaultValue : */ (data.gameplaySettings.exists(name) ? data.gameplaySettings.get(name) : defaultValue);
	}

	public static function reloadVolumeKeys() {
		TitleState.muteKeys = keyBinds.get('volume_mute').copy();
		TitleState.volumeDownKeys = keyBinds.get('volume_down').copy();
		TitleState.volumeUpKeys = keyBinds.get('volume_up').copy();
		toggleVolumeKeys(true);
	}
	public static function toggleVolumeKeys(turnOn:Bool) {
		if(turnOn)
		{
			FlxG.sound.muteKeys = TitleState.muteKeys;
			FlxG.sound.volumeDownKeys = TitleState.volumeDownKeys;
			FlxG.sound.volumeUpKeys = TitleState.volumeUpKeys;
		}
		else
		{
			FlxG.sound.muteKeys = [];
			FlxG.sound.volumeDownKeys = [];
			FlxG.sound.volumeUpKeys = [];
		}
	}
}
