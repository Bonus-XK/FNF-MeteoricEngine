package options;

class JudgmentSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '判定';
		rpcTitle = '判定设置菜单'; //for Discord Rich Presence

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
}
