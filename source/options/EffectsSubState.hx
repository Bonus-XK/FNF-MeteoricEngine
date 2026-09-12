package options;

class EffectsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '效果';
		rpcTitle = '效果设置菜单'; //for Discord Rich Presence

		var option:Option = new Option('频闪效果',
			'关闭后，游戏将不会出现频闪效果',
			'flashing',
			'bool');
		addOption(option);

		var option:Option = new Option('自定义过场动画',
		    '选择过场动画的样式（三种）：移动 = 左右横幅水平推拉；陨星 = 面板推拉并伴随斜向主题色光带掠过；星辉 = 满屏光效淡入淡出。',
			'CustomFade',
			'string',
			[CustomFadeTransition.MODE_MOVE, CustomFadeTransition.MODE_METEOR, CustomFadeTransition.MODE_STAR]);
		addOption(option);

		var option:Option = new Option('过场动画文字',
		    '关闭后，将不再显示过场动画的引擎版本与事件指示器',
			'CustomFadeText',
			'bool');
		addOption(option);

		var option:Option = new Option('镜头缩放',
			'关闭后，镜头将不会随节拍缩放',
			'camZooms',
			'bool');
		addOption(option);

		// 镜头缓动时长：换段/事件后镜头滑到新位置所需的时间。
		// 档位名（英文存储值）与秒数**都取自 ClientPrefs.camSmoothPresets**，此处不硬编码，避免设置页与实机脱节。
		var option:Option = new Option('镜头缓动',
			'换段或事件切换时镜头移动的平滑程度：迅捷=0.3 秒到位（最接近原版切换手感）；标准=0.5 秒；平滑=0.8 秒（滑行感最明显）',
			'camSmooth',
			'string',
			['fast', 'normal', 'smooth']);
		option.displayOptions = ['迅捷 0.3s', '标准 0.5s', '平滑 0.8s'];
		addOption(option);

		var option:Option = new Option('界面节拍跳动',
			'开启后，主菜单/故事模式/自由游玩等播放背景音乐的界面会随节拍轻微跳动',
			'menuBeatBump',
			'bool');
		addOption(option);

		var option:Option = new Option('暂停界面音乐:',
			'选择进入暂停界面时播放的音乐：',
			'pauseMusic',
			'string',
			['无', 'Breakfast', 'Tea Time']);
		addOption(option);
		option.onChange = onChangePauseMusic;

        var option:Option = new Option('检查更新',
			'开启后，自动检查引擎是否有新版本',
			'checkForUpdates',
			'bool');
		addOption(option);

		// 更新提示开关的「回程入口」：更新界面上的「稍后提醒 / 不再提示」把 updateNotify 置 false 后，
		// 更新界面不再弹出 —— 必须在这里留一条路能重新打开，否则玩家永远看不到更新提示。
		var option:Option = new Option('更新提示',
			'关闭后，检测到新版本时不再弹出更新界面（仍会继续检查更新）',
			'updateNotify',
			'bool');
		addOption(option);

		#if desktop
		var option:Option = new Option('Discord在线状态',
			'关闭后，Discord 的“正在游玩”状态将不再显示本应用，避免意外泄露',
			'discordRPC',
			'bool');
		addOption(option);
		#end

		super();
	}

	var changedMusic:Bool = false;
	function onChangePauseMusic()
	{
		if(ClientPrefs.data.pauseMusic == '无')
			FlxG.sound.music.volume = 0;
		else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));

		changedMusic = true;
	}

	override function destroy()
	{
		if(changedMusic && !OptionsState.onPlayState) FlxG.sound.playMusic(Paths.music('freakyMenu'), 1, true);
		super.destroy();
	}
}
