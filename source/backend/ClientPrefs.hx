package backend;

import flixel.util.FlxSave;
import flixel.FlxG;
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
	// 帧率上限档位：120/240/480/无上限（移动端默认 120 防过热）
	// ⚠ 桌面端默认值按平台分：macOS = 无上限（构建后恢复 tools/lime.ndll.wallclock 保证补丁在位）；
	//   Windows = 120 —— 交付包历史上是没打墙钟补丁的 64 位 lime.ndll，存档默认给 100000 会
	//   在启动阶段就死循环卡黑屏（2026-09-11 实测事故）。所以 Windows 默认仍是 120，
	//   但「无上限」档位**重新可用**：选它以后由启动自检（hasWallclockFrameLoop()）决定
	//   真给 100000（补丁版 ndll）还是退回 480（老 ndll）。
	@:keep public var framerateMode:String = #if mac '无上限' #elseif desktop '120' #else '120' #end;
	@:keep public var showScrollSpeed:Bool = true; // FPS 计数器下方显示当前滚动速度（颜色随速度变化）
	@:keep public var showNPS:Bool = false; // FPS 计数器下方显示每秒收到的音符数（NPS）
	@:keep public var flashing:Bool = true;
	@:keep public var CustomFade:String = '移动';
	@:keep public var CustomFadeText:Bool = true;
	@:keep public var autoPause:Bool = true;
	@:keep public var antialiasing:Bool = true;
	@:keep public var holdCover:Bool = true; // 长条按压覆盖（QT 模组 NoteHoldCover.lua 原生移植）
	@:keep public var runtimePack:Bool = false; // 运行时贴图密排列（≤160px 小贴图打包进共享图集，减少纹理/绘制批次；实验性，默认关闭）
	@:keep public var noteSkin:String = 'Default';
	@:keep public var splashSkin:String = 'Psych';
	@:keep public var splashAlpha:Float = 0.6;
	@:keep public var lowQuality:Bool = false;
	@:keep public var shaders:Bool = true;
	// 桌面默认开启：释放 CPU 位图副本（大图集如 GF_assets 8000×6000≈192MB 只留 GPU 纹理，
	// 小谱面 300MB 的主要来源）；移动端/GLES 保持 false（稳定性）
	@:keep public var cacheOnGPU:Bool = #if desktop true #elseif switch true #else false #end; //From Stilic
	// 图集降采样（Meteoric Fix 续）：>2048px 大图集缩到该比例（默认桌面 50%），极大压纹理内存
	// （GF_assets 192MB→48MB）；小图（图标/HUD）不缩。1.0 = 关闭降采样
	// 图集降采样：实测对 sparrow/title 图集产生帧坐标失配（标题黑屏/文字错乱），
	// 已撤回——默认 100%（不降采样）；若未来重做需逐图集校准帧偏移
	@:keep public var textureScale:Float = 1.0;
	// 角色图集专属降采样（Meteoric Fix 续）：仅对 flxanimate 2020 角色图集（spritemap1）降采样，
	// sparrow/title/舞台/音符图集完全不碰（上次全局限缩放导致标题黑屏/文字错乱）。
	@:keep public var characterTextureScale:Float = #if desktop 0.5 #else 1.0 #end;
	// 独立背景图降采样（Meteoric 内存优化，实验性）：仅作用于 >1600px 且非图集的独立大图。
	// ⚠ 注意：舞台/菜单以原始像素绝对坐标摆放精灵（如 makeLuaSprite(x=-973,y=-1076)），
	// 位图缩小后精灵渲染尺寸减半但坐标不变 → 布局大错位。因此**默认 1.0（关闭）**，
	// 需要时在设置里手动开启并自行确认布局（或后续做“位置同比例补偿”的完整方案）。
	@:keep public var backgroundScale:Float = 1.0;
	// 高清渲染开关（重启生效）：true=Retina 2x 清晰（游戏内大规模谱面约 700~1400 帧）；
	// false=1x 高性能（画面略糊，帧率约 3 倍，游戏内可 2200+）。由 SDLWindow.cpp 在创建窗口时读取模式文件。
	@:keep public var highDPIRender:Bool = true;
	// 性能模式（Seiun 移植）：音符走「无着色器 + ColorTransform 上色 + 直连 quad 合批」快速路径，
	// 消除每 item 的 shader 绑定/缓冲重灌开销；部分音符渲染细节（如单色平涂代替三色渐变）略有差异。
	@:keep public var perfMode:Bool = false;
	// 引擎关闭动画（Seiun 融合移植）：点击窗口 X / Alt+F4 时先播放窗口变换动画再退出。
	// 仅桌面目标生效；移动端不启用且不显示设置项（Main.setupWindowCloseHandler 有 #if desktop 守卫）。
	@:keep public var closeAnimEnabled:Bool = true;
	// 关闭动画样式：squeeze 压扁 / zoom 缩放 / drop 坠落 / slide 滑出（设置页显示中文名，存储值为英文）
	@:keep public var closeAnimStyle:String = 'squeeze';
	// 关闭动画速度倍率（0.25x ~ 5.0x，默认 1.0x）
	@:keep public var closeAnimSpeed:Float = 1.0;
	// 【帧数上限已移除】framerate 偏好已删除：桌面端由 Main 配置 1000（无实际限制），移动端保持 120。
	@:keep public var camZooms:Bool = true;
	// 界面节拍跳动：主菜单/故事模式/自由游玩等播放背景音乐的界面随节拍轻微缩放（整屏跳动）
	@:keep public var menuBeatBump:Bool = true;
	@:keep public var hideHud:Bool = false;
	@:keep public var scoreTxtFont:String = '默认';
	@:keep public var scoreTxtFormat:String = 'Score: {score} | Misses: {misses} | Rank: {rank} | Accuracy: {accuracy}% | {fc}'; // Score 栏自定义格式，可用变量见 PlayState.buildScoreText
	@:keep public var hideWatermark:Bool = false;
	@:keep public var healthBarOverlay:Bool = true;
	@:keep public var minimalHealthBar:Bool = false; // 极简血条：隐藏图标与阴影，血条移到 Score 栏位置，scoreTxt 嵌入血条
	@:keep public var newHealthBar:Bool = false; // 新版血量条：自绘（不依赖贴图），并融合 0.6.3 兼容模式
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
	@:keep public var gpuCacheMigrated:Bool = false; // GPU 缓存旧默认迁移标记（一次性）
	@:keep public var texScaleMigrated:Bool = false;  // 图集降采样撤回迁移标记（一次性：把已写盘 0.5 复位为 1.0）
	@:keep public var bgScaleMigrated:Bool = false;   // 背景图降采样撤回迁移标记（一次性：把已写盘 0.5 复位为 1.0）
	@:keep public var gpuCacheForceOnMigrated:Bool = false; // GPU 缓存强制开启迁移（一次性；参考对话“开/关都炸”根因=Convert 栈下溢，已修复）
	@:keep public var preRenderNotes:Bool = false; // 提前渲染：加载曲目时烘焙音符贴图，优化大谱面堆叠（开启后会牺牲加载速度）
	// ===== H-Slice 移植：音符管线性能设置 =====
	@:keep public var skipGhostNotes:Bool = true;   // 堆叠音符合并：同轨 ±ghostRange 的幽灵箭头合并为一个音符（density 计数）
	@:keep public var ghostDensity:Bool = true;     // 合并模式：true=计数合并（保分数/命中量）；false=直接丢弃重复
	@:keep public var ghostRange:Float = 15;        // 合并窗口（毫秒）：同轨时间差 ≤ 该值的箭头视为堆叠
	@:keep public var optimizeSpawnNote:Bool = true;// 已过出生窗口的音符不再生成（跳时间时静默消费，不判 Miss）
	@:keep public var bulkSkip:Bool = true;         // 快速跳谱：二分跳过大段已过音符（重开/跳时间的核心优化）
	@:keep public var fastSort:Bool = false;        // 可见音符快速排序（绘制顺序）；默认关闭保持与旧版一致
	@:keep public var limitNotes:Int = 0;           // 场上音符对象上限（0=不限；堆叠谱防爆）
	@:keep public var hideOverlapped:Float = 0;     // 重叠隐藏间距（0=关闭）：同轨过近音符隐藏后段（渲染裁剪）
	@:keep public var spawnNoteEvent:Bool = true;   // 生成时触发 onSpawnNote 回调（关闭后可省去 15 万级回调开销）
	// ===== 自动游玩命中排期（性能页可调） =====
	@:keep public var botplayScheduledHits:Bool = true; // 生成即排期命中（大谱面自动游玩 100% 覆盖的架构开关）
	@:keep public var botplayPopMargin:Int = 6;         // 排期弹出提前余量（毫秒）：弹出窗 = 帧步长 + 余量，须 ≥ 回收窗
	@:keep public var botplayKillWindow:Int = 6;        // 自动游玩未命中回收窗（毫秒）：越小柱子越贴判定线，太小会与弹出竞态

	// ===== JS Engine（JordanSantiagoYT/FNF-JS-Engine 优化页）移植 =====
	// 默认全部 = 当前行为，纯自愿开启的性能开关
	@:keep public var hudOnly:Bool = false;             // 只显示 HUD：不渲染角色/舞台（含雨滤镜等全场景特效）；默认关闭=完整画面
	@:keep public var enableGC:Bool = true;             // 允许 GC（false=关闭 GC 消除尖峰，内存可能上升）
	@:keep public var opponentLightStrum:Bool = true;   // 对手命中时 strum 高亮 confirm
	@:keep public var botLightStrum:Bool = true;        // 自动游玩命中时玩家 strum 高亮 confirm
	@:keep public var playerLightStrum:Bool = true;     // 手动命中/按下时玩家 strum 高亮
	@:keep public var ratingPopups:Bool = true;         // 评级弹窗（Sick/Good…）
	@:keep public var comboPopups:Bool = true;          // 连击数字 + Combo 词弹窗
	@:keep public var lessBotLag:Bool = false;          // 自动游玩只计分不弹窗（JS 引擎 lessBotLag）
	@:keep public var noHitFuncs:Bool = false;          // 关闭 goodNoteHit/opponentNoteHit 的 Lua/Hscript 回调
	@:keep public var iconFlyOverflow:Bool = false;     // 血条溢出图标飞出（JS 引擎同款：>100% 时图标沿填充方向滑出条外，不封顶）
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
	@:keep public var marvelousJudgement:Bool = false; // Marvelous 判定：最高判定（Sick/45ms）显示为 Marvelous 贴图
	@:keep public var showJudgementCounter:Bool = false; // 侧边栏显示总命中/连击/各判定计数
	@:keep public var phigrosStyle:Bool = false; // Phigros 式判定线玩法
	@:keep public var discordRPC:Bool = true;
	@:keep public var hudLayout:Map<String, Array<Float>> = [ // 自定义界面：HUD 元素相对默认位置的偏移 [x, y]
		'note' => [0, 0],
		'timeBar' => [0, 0],
		'healthBar' => [0, 0],
		'score' => [0, 0],
		'watermark' => [0, 0]
	];

	// ===== 多版本容器（mods/_containers） =====
	// 容器功能总开关：关闭后 ContainersMenuState 只做浏览/自检，不允许启动（默认关闭 = 老玩家零感知）
	@:keep public var containersEnabled:Bool = false;
	// 容器返回热键。放在容器专属字段而不是 keyBinds，
	// 避免改动 ControlsSubState 的 keyBinds 表结构导致老存档的 controls_v3 出现空洞。
	//  - macOS：默认 Ctrl+C（**真组合键**：CONTROL 按住 + C 刚按下）
	//  - Windows：默认单键 F10 —— Windows 上宿主全局收键，Ctrl+C 在目标引擎（FNF/Psych）
	//    里是常用操作（复制/调试），会直接误退出容器；F10 与玩法零冲突。
	#if windows
	@:keep public var containerExitKeys:Array<FlxKey> = [F10];
	#else
	@:keep public var containerExitKeys:Array<FlxKey> = [CONTROL, C];
	#end

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
		#if android
		// 安卓权威设置文件：写入 .meteoric/meoptions（无后缀 JSON，随外部资源目录，
		// 卸载不清、玩家可备份/编辑）。FlxG.save 保留双写（兼容旧版本迁移与读取）。
		try
		{
			sys.io.File.saveContent(backend.AndroidStorage.root() + '/meoptions', haxe.Json.stringify(data));
		}
		catch (e:Dynamic) {}
		#end
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

	// 把容器热键从「JSON 往返后的裸整数/字符串数组」还原为 FlxKey 数组。
	// 必要性：FlxG.save / meoptions 走 haxe.Json，抽象枚举经 json 往返后是 Int 或 String，
	// 直接当 FlxKey 用会在 FlxG.keys.justPressed(key) 里类型错位（最坏情况静默不触发）。
	// 与 normalizeLoadedMaps 同因同治。
	static function normalizeLoadedKeys():Void
	{
		if (data == null) return;
		var raw:Dynamic = data.containerExitKeys;
		if (raw == null || !Std.isOfType(raw, Array))
		{
			data.containerExitKeys = defaultContainerExitKeys();
			return;
		}
		var list:Array<Dynamic> = cast raw;
		var out:Array<FlxKey> = [];
		for (item in list)
		{
			if (item == null) continue;
			var s:String = Std.string(item);
			if (s == 'null' || s.length < 1) continue;
			// FlxKey 是 enum abstract Int，且 flixel 自带名字表：
			//  - 名字形式（"C" / "CONTROL"）→ FlxKey.fromStringMap
			//  - 键码形式（67 / 17）→ 直接当 Int（FlxKey 有 from Int）
			var named:Null<FlxKey> = flixel.input.keyboard.FlxKey.fromStringMap.get(s);
			if (named != null)
			{
				out.push(named);
				continue;
			}
			var num:Null<Int> = Std.parseInt(s);
			if (num != null) out.push(cast num);
		}
		if (out.length < 1) out = defaultContainerExitKeys();
		data.containerExitKeys = out;
	}

	/** 平台默认的容器返回热键（Windows 单键 F10，其它平台 Ctrl+C 组合键）。 */
	public static function defaultContainerExitKeys():Array<FlxKey>
	{
		#if windows
		return [F10];
		#else
		return [CONTROL, C];
		#end
	}

	// haxe.Json 往返后把 Map 类型的设置字段还原为真正的 Haxe Map。
	// 判定：真正的 Haxe Map 通过 Std.isOfType(hud, Map)（hxcpp 对 Map 有专门识别）；
	// haxe.Json.parse 出的匿名对象 / 数组 / 字符串等一律重建为 Map（[k => [x, y]] 形式）。
	static function normalizeLoadedMaps():Void
	{
		if (data == null) return;
		var hud:Dynamic = data.hudLayout;
		if (hud == null)
		{
			data.hudLayout = [];
			return;
		}
		var isRealMap:Bool = false;
		try
		{
			// 真 Map：get() 不抛异常（无键返回 null）；数组也要排除（Array 无 get，也会抛）
			if (!Std.isOfType(hud, Array))
			{
				hud.get('__meteoric_probe__');
				isRealMap = true;
			}
		}
		catch (e:Dynamic) {}
		if (isRealMap) return;

		var m:Map<String, Array<Float>> = [];
		try
		{
			for (k in Reflect.fields(hud))
			{
				var v:Dynamic = Reflect.field(hud, k);
				var arr:Array<Float> = [0, 0];
				if (Std.isOfType(v, Array))
				{
					var items:Array<Dynamic> = cast v;
					if (items.length >= 1) arr[0] = Std.parseFloat(Std.string(items[0]));
					if (items.length >= 2) arr[1] = Std.parseFloat(Std.string(items[1]));
					if (Math.isNaN(arr[0])) arr[0] = 0;
					if (Math.isNaN(arr[1])) arr[1] = 0;
				}
				m.set(k, arr);
			}
		}
		catch (e:Dynamic) {}
		data.hudLayout = m;
	}

	// JS 优化移植续：帧率上限设置项（120/240/480/无上限）——
	// 把档位解析为实际帧率并接管 FlxG 步长/绘制帧率（FlxG.drawFramerate setter 会同步 stage.frameRate）。
	// 移动端默认 120（防过热）；「无上限」= 100000 哨兵（只是"无人工限制"的标记，非字面目标帧率），
	// 只受 CPU/GPU 限制 —— 前提是原生帧循环带「墙钟补丁」，见 hasWallclockFrameLoop()。
	#if windows
	/** 带「墙钟帧循环补丁」的那份 lime.ndll 的 SHA1（tools/lime.ndll.win64.wallclock）。
	 *  换新 ndll 时**必须**同步更新这个常量，否则「无上限」会退回 480。 */
	static inline var WALLCLOCK_NDLL_SHA1:String = 'af8663cd2beeddf2cd16ad5179d78acba2c8501e';

	/**
	 * 探测当前 `lime.ndll` 是否带「墙钟帧循环补丁」（Windows 专属判据）。
	 *
	 * 判据 = **文件身份**：读可执行文件旁边的 `lime.ndll`，算 SHA1 与
	 * `WALLCLOCK_NDLL_SHA1` 比对。对上 → 100000；对不上/读不到 → 退回 480。
	 *
	 * 为什么不用原生符号探测（走过两条死路，别再回头）：
	 *   ① `cpp.Lib._loadPrime(null, …)`：第一个参数是非空 String，传 null 会让 C++ 侧
	 *      构造 `std::string(nullptr)` → `std::logic_error: basic_string: construction
	 *      from null is not valid` → `terminate` → **启动即闪退**（实测）。
	 *   ② 改成空串/模块名后不崩了，但 `_loadPrime` 底层是
	 *      `__hxcpp_get_proc_address(inLib, inPrim, inNdll=false, …)`，而 hxcpp 的
	 *      `CFFILoader.h` 写明了它取的是**主程序里的 cffi 原语表**
	 *      （"Via 'GetProcAddress' on the exe"），不是"按名字去已加载的 DLL 里查符号"。
	 *      于是纯 C 导出符号 `lime_meteoric_frame_loop_patch` 永远查不到 →
	 *      **探测恒为"无"**（用户实测日志：`档位=120 墙钟补丁探测=无 无上限档取值=480`）。
	 *   原生符号本身仍然有用：`compile-windows.sh` 用 `objdump` 查它做**构建期门禁**，
	 *   保证交付的 ndll 是补丁版；运行期判据改用文件身份，确定性与版本无关。
	 *
	 * 为什么必须探测而不能假定：64 位 Windows 交付包长期带着**没打补丁**的 lime.ndll
	 * （8,281,088 字节、无 SDL3 标记），配上 100000 哨兵时原生帧循环里
	 * `nextUpdate += framePeriod` 被整型截断成 +0 → catch-up 循环永不前进 →
	 * 启动即 100% 死循环、黑屏卡在加载界面（2026-09-11 实测事故）。
	 * 探测不到补丁就把帧率压回 480（实测可用档位）：宁可跑不出极限帧率，也绝不启动死循环。
	 */
	static var _wallclockFrameLoopProbe:Int = -1;
	public static function hasWallclockFrameLoop():Bool
	{
		// ⚠ 每次进入都无条件重置哨兵，不能依赖字段初始化器 `= -1`：hxcpp 把静态字段初值
		//   放进 ClientPrefs_obj::__boot()，而 Main 的字段初始化器在 **Main 构造时**就调用
		//   本函数——跨编译单元静态初始化顺序不保证，`__boot()` 可能尚未执行，此时读到零
		//   初始化的 0，`>= 0` 恒真 → 直接 return false、探测一次都不执行（实测踩过）。
		_wallclockFrameLoopProbe = 0;
		#if sys
		try
		{
			var ndllPath:String = haxe.io.Path.directory(Sys.programPath()) + '/lime.ndll';
			if (sys.FileSystem.exists(ndllPath))
			{
				var input:sys.io.FileInput = sys.io.File.read(ndllPath, true);
				var bytes:haxe.io.Bytes = input.readAll(); // ~11MB，启动只算一次
				input.close();
				var digest:String = haxe.crypto.Sha1.make(bytes).toHex().toLowerCase();
				if (digest == WALLCLOCK_NDLL_SHA1)
					_wallclockFrameLoopProbe = 1;
			}
		}
		catch (e:Dynamic)
		{
			_wallclockFrameLoopProbe = 0;
		}
		#end
		return _wallclockFrameLoopProbe == 1;
	}

	/** 「无上限」档位在本机的实际取值：补丁版 ndll 给 100000 哨兵，否则退回 480。 */
	public static function unlimitedFramerateValue():Int
	{
		return hasWallclockFrameLoop() ? 100000 : 480;
	}
	#end

	public static function applyFramerate():Void
	{
		var target:Int = switch (data.framerateMode)
		{
			case '240': 240;
			case '480': 480;
			#if mac
			case '无上限': 100000;
			#end
			#if windows
			// Windows 的「无上限」由启动自检决定：补丁版 ndll → 100000（与 macOS 同款墙钟帧循环）；
			// 老 ndll → 480 兜底（见 hasWallclockFrameLoop 注释）
			case '无上限': unlimitedFramerateValue();
			#end
			default: 120;
		}
		if (FlxG.game == null) return;
		// 避免 flixel 的两个方向性警告：升档先 update 后 draw，降档先 draw 后 update
		if (target > FlxG.updateFramerate)
		{
			FlxG.updateFramerate = target;
			FlxG.drawFramerate = target;
		}
		else
		{
			FlxG.drawFramerate = target;
			FlxG.updateFramerate = target;
		}
	}

	public static function loadPrefs() {
		if(data == null) data = new SaveVariables();
		if(defaultData == null) defaultData = new SaveVariables();

		#if android
		// 安卓：meoptions 文件为权威设置源；不存在时回退 FlxG.save（旧版本迁移，
		// 下次 saveSettings 自动落盘 meoptions）
		var _optionsFromFile:Bool = false;
		try
		{
			var optFile:String = backend.AndroidStorage.root() + '/meoptions';
			if (sys.FileSystem.exists(optFile))
			{
				var parsed:Dynamic = haxe.Json.parse(sys.io.File.getContent(optFile));
				if (parsed != null)
				{
					for (key in Reflect.fields(data))
						if (key != 'gameplaySettings' && Reflect.hasField(parsed, key))
							Reflect.setField(data, key, Reflect.field(parsed, key));
					_optionsFromFile = true;
				}
			}
		}
		catch (e:Dynamic) {}
		if (!_optionsFromFile)
		{
		#end
		for (key in Reflect.fields(data)) {
			if (key != 'gameplaySettings' && Reflect.hasField(FlxG.save.data, key)) {
				//trace('loaded variable: $key');
				Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));
			}
		}
		#if android
		}
		#end
		// haxe.Json 的 Map 往返修复：Map 序列化成 JSON 对象（{"note":[0,0],...}），
		// parse 后是"匿名对象"而非 Haxe Map，直接赋给 Map 字段后运行时 .exists()/.get()
		// 全部抛 Null Object Reference。安卓 meoptions（haxe.Json）在玩家保存过一次设置后
		// 必然触发：下次启动进任何曲目都在 100% 后黑屏闪退（自定义 HUD 布局 hudLayout 即此问题）。
		// 这里把所有这类 Map 字段统一还原为真正的 Haxe Map。
		normalizeLoadedMaps();
		normalizeLoadedKeys();
		savedHideHud = data.hideHud;

		// 判定选项旧值迁移：'新版' -> 'KE 判定'，'旧判定' -> 'PE 判定'
		if (data.noteJudgment == '新版' || data.noteJudgment == '旧判定')
			data.noteJudgment = (data.noteJudgment == '新版') ? 'KE 判定' : 'PE 判定';

		// 帧率档位旧值迁移（2026-09-11 事故的临时处置）已**撤销**：
		// 当时非 macOS 上没有「无上限」档位，于是把存档里遗留的 '无上限' 收回 '120'。
		// 现在 Windows 重新提供该档位，能否真跑到 100000 改由启动自检
		// （hasWallclockFrameLoop()）决定：补丁版 lime.ndll 用 100000，老 ndll 自动退回 480。
		// 保留用户存档里的选择本身（不再改写 data.framerateMode），避免"选项列表里没有任何项被选中"。

		// 连击堆叠旧值迁移：新默认不堆叠（评级/连击数字图片不再叠成一片），只迁移一次，之后尊重用户手动选择
		if (!data.comboStackMigrated)
		{
			data.comboStackMigrated = true;
			if (data.comboStacking) data.comboStacking = false;
			saveSettings();
		}

		// GPU 缓存旧默认迁移：桌面旧默认 false（CPU 位图 + GPU 纹理双份，大图集 192MB×2）→
		// 新默认 true 只留 GPU 纹理（小谱面 300MB 的主要来源）。只迁移一次，之后尊重用户手动选择。
		if (!data.gpuCacheMigrated)
		{
			data.gpuCacheMigrated = true;
			#if desktop
			if (!data.cacheOnGPU) data.cacheOnGPU = true;
			#end
			saveSettings();
		}

		// 图集降采样撤回迁移：本会话曾把 textureScale 写盘为 0.5（标题黑屏/文字错乱回归），
		// 一次性复位为 1.0（100% 原分辨率）
		if (!data.texScaleMigrated)
		{
			data.texScaleMigrated = true;
			if (data.textureScale < 1) data.textureScale = 1.0;
			saveSettings();
		}

		// 背景图降采样撤回迁移：本会话曾把 backgroundScale 写盘为 0.5（舞台/菜单绝对坐标
		// 与位图缩放不同步 → 布局大错位），一次性复位为 1.0（关闭降采样）
		if (!data.bgScaleMigrated)
		{
			data.bgScaleMigrated = true;
			if (data.backgroundScale < 1) data.backgroundScale = 1.0;
			saveSettings();
		}

		// GPU 缓存强制开启迁移（一次性）：历史会话用户因崩溃关闭了 cacheOnGPU，
		// 而崩溃根因（Convert.toLua 栈下溢 → LuaJIT 堆损坏）已在本会话修复。
		// 贴图 CPU 副本是内存大头（blissful 701MB→GPU-only 后 ~400MB），强制回开一次；
		// 用户仍可在 设置→图像 手动关闭。
		if (!data.gpuCacheForceOnMigrated)
		{
			data.gpuCacheForceOnMigrated = true;
			#if desktop
			data.cacheOnGPU = true;
			#end
			saveSettings();
		}
		
		if(Main.fpsVar != null) {
			Main.fpsVar.applyDisplayMode();
		}

		// 高清/高性能渲染模式：写入可执行文件旁的模式文件，供 SDLWindow.cpp 下次启动创建窗口时读取（重启生效）
		applyHighDPIRenderMode();

		#if (!html5 && !switch)
		FlxG.autoPause = ClientPrefs.data.autoPause;
		#end

		// JS 优化移植续：帧率上限设置项（120/240/480/无上限）——加载设置后立即接管 FlxG 步长/绘制帧率
		applyFramerate();

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

	// 高清渲染模式 → 可执行文件旁 meteoric_dpi_mode.txt（'1'=2x 高清 / '0'=1x 高性能）
	// SDLWindow.cpp 在创建窗口前读取；修改需重启游戏生效。
	public static function applyHighDPIRenderMode() {
		#if sys
		try {
			var modeFile:String = haxe.io.Path.directory(Sys.programPath()) + '/meteoric_dpi_mode.txt';
			sys.io.File.saveContent(modeFile, data.highDPIRender ? '1' : '0');
		} catch (e:Dynamic) {}
		#end
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
