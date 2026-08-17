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
		    '选择过场动画的样式：',
			'CustomFade',
			'string',
			['移动', '淡入淡出']);
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
