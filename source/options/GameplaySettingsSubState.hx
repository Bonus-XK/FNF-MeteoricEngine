package options;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Gameplay Settings';
		rpcTitle = 'Gameplay Settings Menu'; //for Discord Rich Presence

		//I'd suggest using "Downscroll" as an example for making your own option since it is the simplest here
		var option:Option = new Option('Downscroll', //Name
			'如果被选中，那么UI界面将会垂直调换', //Description
			'downScroll', //Save data variable name
			'bool'); //Variable type
		addOption(option);

		var option:Option = new Option('Middlescroll',
			'如果被选中，那么箭头将居中显示',
			'middleScroll',
			'bool');
		addOption(option);

		var option:Option = new Option('Opponent Notes',
			'如果不被选中，那么对手箭头将不会显示',
			'opponentStrums',
			'bool');
		addOption(option);

		var option:Option = new Option('Ghost Tapping',
			"如果选中，在没有可点击的箭头时，您不会因为乱按而Miss",
			'ghostTapping',
			'bool');
		addOption(option);
		
		var option:Option = new Option('SB Engine Iconbop',
		    "如果选中，那么将会启用SB Engine的小图标跳动",
			'sbIconBop',
			'bool');
	    addOption(option);
		
		var option:Option = new Option('Smooth health',
		    "如果选中，你的血量条显示起来将会很丝滑",
			'smoothHealth',
			'bool');
		addOption(option);

		var option:Option = new Option('Health Bar Overlay',
		    "如果选中，在血量条上将会显示一层阴影",
			'healthBarOverlay',
			'bool');
		addOption(option);

		var option:Option = new Option('Auto Pause',
			"你想让游戏在后台运行吗",
			'autoPause',
			'bool');
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option('Disable Reset Button',
			"如果被选中，那么按下重置键就不会有任何反应",
			'noReset',
			'bool');
		addOption(option);

		var option:Option = new Option('Hitsound Volume',
			'当你按下有趣的箭头时，它们会“叮！”',
			'hitsoundVolume',
			'percent');
		addOption(option);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;

		var option:Option = new Option('Rating Offset',
			'更改您必须为“Sick”打晚/早！更高的值意味着您必须稍后打',
			'ratingOffset',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 20;
		option.minValue = -30;
		option.maxValue = 30;
		addOption(option);

		var option:Option = new Option('Sick! Hit Window',
			'更改您按下“Sick!”的时间（以毫秒为单位）',
			'sickWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 15;
		option.minValue = 15;
		option.maxValue = 45;
		addOption(option);

		var option:Option = new Option('Good Hit Window',
			'以毫秒为单位更改按下“Good”的时间',
			'goodWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 30;
		option.minValue = 15;
		option.maxValue = 90;
		addOption(option);

		var option:Option = new Option('Bad Hit Window',
			'以毫秒为单位更改您按下“Bad”的时间',
			'badWindow',
			'int');
		option.displayFormat = '%vms';
		option.scrollSpeed = 60;
		option.minValue = 15;
		option.maxValue = 135;
		addOption(option);

		var option:Option = new Option('Safe Frames',
			'更改提前或延迟按下箭头的帧数',
			'safeFrames',
			'float');
		option.scrollSpeed = 5;
		option.minValue = 2;
		option.maxValue = 50;
		option.changeValue = 0.1;
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