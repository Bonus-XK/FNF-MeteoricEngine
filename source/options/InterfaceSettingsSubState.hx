package options;

class InterfaceSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '界面';
		rpcTitle = '界面设置菜单'; //for Discord Rich Presence

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
			'开启后，时间条变为黑色圆角样式，已走过部分显示对手图标颜色（颜色过暗时自动使用青色）',
			'newTimeBarStyle',
			'bool');
		addOption(option);

		var option:Option = new Option('时间条颜色跟随对方',
			'开启后，时间条（贴图样式）填充色跟随对方角色血量条颜色，颜色过暗或过亮时自动使用青色；新时间条样式不受此开关影响',
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
			'开启后，FPS 计数器下方显示每秒收到的音符数（NPS），用于查看自己的读谱速度（不含长条，每秒更新）',
			'showNPS',
			'bool');
		addOption(option);

		super();
	}

	#if !mobile
	function onChangeFPSCounter()
	{
		if(Main.fpsVar != null)
			Main.fpsVar.applyDisplayMode();
	}
	#end
}
