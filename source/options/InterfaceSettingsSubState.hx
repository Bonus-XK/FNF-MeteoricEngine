package options;

import substates.TextInputPrompt;

class InterfaceSettingsSubState extends BaseOptionsMenu
{
	/** 主题色选项（onChange 需回读它的值，见 applyThemeSelection） */
	var themeOption:Option = null;

	public function new()
	{
		title = '界面';
		rpcTitle = '界面设置菜单'; //for Discord Rich Presence

		// ===== 主题色（固定 10 色色板；三强调令牌同步派生，见 backend/DesignTokens.hx）=====
		// int 类型：左右键/◀▶/滚轮 每步 ±1 即换一套色板，选中项即时生效（onChange → applyThemeSelection）
		themeOption = new Option('主题色',
			'选择界面主题色（固定 10 色，作用于系统界面与部分强调元素的 主/次/点缀 三个令牌）：'
			+ '\n青·蓝·紫·品红·橙·金·绿·青绿·红·粉'
			+ '\n改动即时生效：本页当前观感马上更新，其余界面在下次进入时应用新配色。',
			'themeIndex',
			'int');
		themeOption.minValue = 0;
		themeOption.maxValue = backend.DesignTokens.THEME_COUNT - 1;
		themeOption.changeValue = 1;
		// 值文字显示色板名（存索引、显示中文名）：用 Option.displayFormatter，不做选项名字符串嗅探
		themeOption.displayFormatter = function(v:Dynamic):String {
			return backend.DesignTokens.themeName(Std.parseInt(Std.string(v)));
		};
		addOption(themeOption);
		themeOption.onChange = applyThemeSelection;

		var option:Option = new Option('隐藏HUD',
			'开启后，血量条等界面元素将不会显示',
			'hideHud',
			'bool');
		addOption(option);

		var option:Option = new Option('计分文字字体: ',
		    '选择计分文字使用的字体：',
			'scoreTxtFont',
			'string',
			['默认', 'Bahnschrift']);
		addOption(option);

		var option:Option = new Option('Score栏格式',
			'自定义 Score 栏文本格式。可用变量：{score} {misses} {rank} {accuracy} {nps} {fc} {combo} {health}。按确认键打开输入框',
			'scoreTxtFormat',
			'string',
			[ClientPrefs.data.scoreTxtFormat]);
		// 值是一大长串格式串（含 {score}/{misses}/…），行内放不下 → 只显示入口提示
		option.valueHint = '点击查看';
		addOption(option);
		option.onChange = openScoreFormatPrompt;

		var option:Option = new Option('隐藏水印',
			'开启后，左下角的水印将不会显示',
			'hideWatermark',
			'bool');
		addOption(option);
		
		var option:Option = new Option('时间条:',
			'选择时间条的显示样式：',
			'timeBarType',
			'string',
			['剩余时间', '已过时间', '歌曲名称', '禁用']);
		addOption(option);

		var option:Option = new Option('新时间条样式',
			'开启后，时间条变为黑色圆角样式。已走过部分的填充色：开启「时间条颜色跟随对方」时用对手图标颜色，'
			+ '否则用主题色（颜色过暗时自动兜底）',
			'newTimeBarStyle',
			'bool');
		addOption(option);

		var option:Option = new Option('时间条颜色跟随对方',
			'开启后，时间条填充色跟随对方角色血量条颜色（过暗/过亮时自动兜底）；关闭时使用当前主题色。'
			+ '两种时间条样式均受此开关控制',
			'timeBarOpponentColors',
			'bool');
		addOption(option);

		var option:Option = new Option('血条透明度',
			'调整血量条的透明度',
			'healthBarAlpha',
			'percent');
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		var option:Option = new Option('Combo堆叠',
			'关闭后，评级与 Combo 数字将不再堆叠，节省系统内存，读谱也更清晰',
			'comboStacking',
			'bool');
		addOption(option);

		#if !mobile
		var option:Option = new Option('FPS计数器',
			'关闭后，帧数计数器（FPS）将不会显示',
			'showFPS',
			'bool');
		addOption(option);
		option.onChange = onChangeFPSCounter;

		var option:Option = new Option('FPS显示到窗口标题',
			'开启后，FPS/内存/峰值内存/CPU 显示在窗口标题栏，屏幕上的计数器隐藏',
			'fpsInTitleBar',
			'bool');
		addOption(option);
		option.onChange = onChangeFPSCounter;
		#end
		
		var option:Option = new Option('FPS引擎版本',
			'关闭后，帧数计数器下方的引擎版本将不会显示',
			'showVer',
			'bool');
		addOption(option);

		var option:Option = new Option('FPS显示颜色: ',
		    '选择 FPS 计数器显示的颜色；"自动"模式会随帧率变色（高帧绿色、中帧黄色、低帧红色），"彩虹"模式为 KE 引擎风格的循环彩虹色',
			'fpsColor',
			'string',
			['自动', '彩虹', '白色', '青色', '蓝色', '红色', '绿色', '黄色']);
		addOption(option);

		var option:Option = new Option('显示滚动速度',
			'开启后，FPS 计数器下方显示当前音符滚动速度，颜色随速度变化（慢速绿色、中速黄色、快速红色）',
			'showScrollSpeed',
			'bool');
		addOption(option);

		var option:Option = new Option('显示NPS',
			'开启后，Score 栏显示每秒收到的音符数（NPS），用于查看自己的读谱速度（不含长条，每秒更新）',
			'showNPS',
			'bool');
		addOption(option);

		var option:Option = new Option('判定计数侧边栏',
			'开启后，屏幕右上角显示总命中数、连击数、Marvelous/Sick/Good/Bad/Shit/Misses 数量',
			'showJudgementCounter',
			'bool');
		addOption(option);

		var option:Option = new Option('血条溢出图标飞出',
			'开启后，任意堆叠命中（≥2 连打簇，即使没顶破 100%）都会触发：血量显示按该堆叠提供的血量%爆发'
			+ '（堆叠越大越高，最多 1000%），小图标按比例冲出条外再被慢速拉回；\n'
			+ '血条上限仍为 100%，仅显示与飞行节奏发生变化',
			'iconFlyOverflow',
			'bool');
		addOption(option);


		super();

		// ⚠ 登记与挂载都必须放在 super() **之后**：
		// hxcpp 把实例字段初始化器放在基类构造里执行，super() 之前对字段的任何赋值都会被清掉
		// （_themeSwatchesWanted 会被重置为 false，守卫直接返回 → 什么都不会挂上）。
		setupThemeSwatches();
		ensureThemeSwatchesAdded();
	}

	/** 主题色选项变更：即时应用 + 写存档；Options 页自身立刻换色，其余界面下次进入时生效 */
	function applyThemeSelection()
	{
		if (themeOption == null) return;
		var idx:Null<Int> = Std.parseInt(Std.string(themeOption.getValue()));
		if (idx == null) idx = 0;
		if (idx < 0 || idx >= backend.DesignTokens.THEME_COUNT) idx = 0;
		themeOption.setValue(idx);
		// 写入存档 + 刷新本页（menuDesat tint 与值文字色板名）；显式传索引，避免依赖 curOption
		refreshThemeVisuals(idx);
	}

	function openScoreFormatPrompt()
	{
		openSubState(new TextInputPrompt(
			'自定义 Score 栏格式',
			'可用变量：\n{score} 分数 | {misses} Miss | {rank} 评级 | {accuracy} 准度(不含%)\n{nps} 每秒音符 | {fc} FC状态 | {combo} 连击 | {health} 血量百分比',
			ClientPrefs.data.scoreTxtFormat,
			function(value:String) {
				if (value != null && value.trim() != '')
				{
					ClientPrefs.data.scoreTxtFormat = value;
					ClientPrefs.saveSettings();
				}
			}
		));
	}

	#if !mobile
	function onChangeFPSCounter()
	{
		if(Main.fpsVar != null)
			Main.fpsVar.applyDisplayMode();
	}
	#end
}
