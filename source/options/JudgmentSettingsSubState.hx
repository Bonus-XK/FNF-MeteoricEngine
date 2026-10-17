package options;

class JudgmentSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '判定';

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

		var option:Option = new Option('Marvelous 判定',
			'开启后，最高判定（Sick/45ms）显示为 Marvelous 贴图（KE 1.8 风格）',
			'marvelousJudgement',
			'bool');
		addOption(option);

		var option:Option = new Option('Phigros 式评级',
			'只把**评级**换成 Phigros 的档位：φ / V（全连）/ S / A / B / C / F，分档依据是准确率。\n'
			+ '准确率 =（Sick/Marvelous + Good×0.65）÷ 谱面音符总数。\n'
			+ '**分数与判定完全不变**：分数仍是引擎原口径（每判定固定加分），高分榜/回放/暂停界面都不受影响。\n'
			+ '**仅结算页生效**（游玩中 HUD 的 Rank/Accuracy 保持原样 —— ACC 分母是整张谱面音符数，打完才有意义）。\n'
			+ '关闭时评级与改动前完全一致（PF/SHDC/F…AAA 那套）。',
			'phigrosRating',
			'bool');
		addOption(option);

		var option:Option = new Option('Phigros 准确率',
			'准确率（ACC）换用 Phigros 的算法：（Sick/Marvelous + Good×0.65）÷ 总音符。\n'
			+ '关闭时用引擎原口径：命中权重和 ÷ 已判定数（Sick=1 / Good=0.67 / Bad=0.34 / Shit=0）。\n'
			+ '两者权重不同，同一局会得到不同数字（Good 算 65% vs 67%），分母也不同（已判定数 vs 谱面总数）。\n'
			+ '**仅结算页生效**：游玩中 HUD 的 Accuracy 始终是原口径，否则开局会显示 0%。',
			'phigrosAccuracy',
			'bool');
		addOption(option);

		super();
	}

	function onChangeHitsoundVolume()
	{
		FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);
	}
}
