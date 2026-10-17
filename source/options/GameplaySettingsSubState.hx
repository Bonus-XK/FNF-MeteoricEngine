package options;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '玩法';

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
		
		var option:Option = new Option('小图标跳动',
		    '选择血量条两侧小图标随节拍跳动的样式。脉冲最贴合手、点头保留一点手绘律动；'
			+ '错拍两侧反相、跳跃会上下弹起、挤压是卡通式压扁拉伸；关闭 = 完全静止',
			'iconBopStyle',
			'string',
			backend.IconBop.CHOICES);
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

		var option:Option = new Option('极简血条',
		    '开启后，隐藏血量条图标与阴影，血量条移到 Score 栏位置，Score 栏文字嵌入血量条中',
			'minimalHealthBar',
			'bool');
		addOption(option);

		var option:Option = new Option('旧版血量条',
		    '开启后，使用旧版血量条样式（填充裁剪为血条内部形状、背景由血量条自行绘制），用于兼容 0.6.3 及以下版本的旧模组脚本',
			'oldHealthBar',
			'bool');
		addOption(option);

		var option:Option = new Option('新版血量条',
		    '开启后，血量条不再依赖贴图而是自己绘制（白边框 + 内部填充），并自动融合 0.6.3 兼容模式（无阴影）',
			'newHealthBar',
			'bool');
		addOption(option);

		var option:Option = new Option('自动暂停',
			'开启后，游戏窗口失去焦点（切到后台）时会自动暂停',
			'autoPause',
			'bool');
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option('自动游玩模式',
			'敲击 = 正常机器人模式；销毁 = 音符到判定线立即销毁，不产生评级/分数，结算显示销毁数量',
			'botMode',
			'string',
			['tap', 'destroy']);
		addOption(option);

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

		// TuoboLoad：牺牲画质换加载速度。默认关闭 = 零行为变化。
		// 1=轻量（角色/舞台贴图降采样，总纹理省约 70%）；2=极简（不加载角色与舞台）。
		var option:Option = new Option(backend.Lang.tOr('option.tuoboLoad', 'TuoboLoad 极速加载'),
			backend.Lang.tOr('optionDesc.tuoboLoad', '牺牲画面换加载速度。关闭 = 完整画面（默认）。极简 = 不加载角色与舞台，只保留判定线与音符'),
			'tuoboLoad',
			'string',
			['0', '1']);
		addOption(option);

		super();
	}

	function onChangeAutoPause()
	{
		FlxG.autoPause = ClientPrefs.data.autoPause;
	}
}
