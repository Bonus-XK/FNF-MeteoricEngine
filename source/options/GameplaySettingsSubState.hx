package options;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '游戏设置';
		rpcTitle = '游戏设置菜单'; //for Discord Rich Presence

		//I'd suggest using "Downscroll" as an example for making your own option since it is the simplest here
		var option:Option = new Option('向下滚动', //Name
			'开启后，界面会上下翻转，音符从上方往下落', //Description
			'downScroll', //Save data variable name
			'bool'); //Variable type
		addOption(option);

		var option:Option = new Option('中间滚动',
			'开启后，双方箭头都会居中显示',
			'middleScroll',
			'bool');
		addOption(option);

		var option:Option = new Option('对手音符',
			'关闭后，对手的箭头将不会显示',
			'opponentStrums',
			'bool');
		addOption(option);

		var option:Option = new Option('幽灵点击',
			'开启后，在没有可击打的箭头时乱按，也不会被判为 Miss',
			'ghostTapping',
			'bool');
		addOption(option);
		
		var option:Option = new Option('SB引擎图标跳动',
		    '开启后，启用 SB Engine 风格的小图标跳动',
			'sbIconBop',
			'bool');
	    addOption(option);

		var option:Option = new Option('KE引擎图标跳动',
		    '开启后，启用 Kade Engine 风格的小图标跳动（每拍放大后弹性缩回）',
			'keIconBop',
			'bool');
	    addOption(option);
		
		var option:Option = new Option('平滑血量',
		    '开启后，血量条的变化会更平滑流畅',
			'smoothHealth',
			'bool');
		addOption(option);

		var option:Option = new Option('血条覆盖',
		    '开启后，血量条上会覆盖一层阴影',
			'healthBarOverlay',
			'bool');
		addOption(option);

		var option:Option = new Option('旧版血量条',
		    '开启后，使用旧版血量条样式（填充裁剪为血条内部形状、背景由血量条自行绘制），用于兼容 0.6.3 及以下版本的旧模组脚本',
			'oldHealthBar',
			'bool');
		addOption(option);

		var option:Option = new Option('自动暂停',
			'开启后，游戏窗口失去焦点（切到后台）时会自动暂停',
			'autoPause',
			'bool');
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option('禁用重置键',
			'开启后，按下重置键不会触发任何效果',
			'noReset',
			'bool');
		addOption(option);

		var option:Option = new Option('快速重新开始',
			'开启后，重新开始时不再重新加载谱面（不读盘、不重建场景，重开更流畅）',
			'restartNoChartReload',
			'bool');
		addOption(option);

		var option:Option = new Option('快速重开回溯箭头',
			'快速重开时，屏幕上的箭头会像时间倒流一样飞回起点，然后再重新开始',
			'rewindOnRestart',
			'bool');
		addOption(option);

		var option:Option = new Option('打击音音量',
			'按下音符时，会发出“叮！”的打击音',
			'hitsoundVolume',
			'percent');
		addOption(option);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;

		var option:Option = new Option('评级偏移',
			'调整打出“Sick!”所需的提前/延迟范围；数值越大，要求按得越晚',
			'ratingOffset',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 20;
		option.minValue = -30;
		option.maxValue = 30;
		addOption(option);

		var option:Option = new Option('Sick!判定窗口',
			'Sick! 判定的可命中时间窗口（毫秒）',
			'sickWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 15;
		option.minValue = 15;
		option.maxValue = 45;
		addOption(option);

		var option:Option = new Option('Good判定窗口',
			'Good 判定的可命中时间窗口（毫秒）',
			'goodWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 30;
		option.minValue = 15;
		option.maxValue = 90;
		addOption(option);

		var option:Option = new Option('Bad判定窗口',
			'Bad 判定的可命中时间窗口（毫秒）',
			'badWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 60;
		option.minValue = 15;
		option.maxValue = 135;
		addOption(option);

		var option:Option = new Option('安全帧数',
			'允许提前或延迟按下的安全帧数，数值越大判定越宽松',
			'safeFrames',
			'float');
		option.scrollSpeed = 5;
		option.minValue = 2;
		option.maxValue = 50;
		option.changeValue = 0.1;
		addOption(option);

		var option:Option = new Option('Phigros 玩法',
			'开启后，使用 Phigros 式判定线玩法：发光判定线 + 彩色方块，方块从远处飞向判定线（重新开始歌曲后生效）',
			'phigrosStyle',
			'bool');
		addOption(option);

		var option:Option = new Option('音符判定',
			'选择音符判定方式：PE 判定为引擎原有判定；KE 判定为 Kade Engine 判定（提前窗口更短，45/90/135ms 评级窗口随安全帧缩放）',
			'noteJudgment',
			'string',
			['PE 判定', 'KE 判定']);
		addOption(option);

		super();
	}

	function onChangeHitsoundVolume()
	{
		FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);
	}

	function onChangeAutoPause()
	{
		FlxG.autoPause = ClientPrefs.data.autoPause;
	}
}
