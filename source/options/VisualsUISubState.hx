package options;

import objects.Note;
import objects.StrumNote;

class VisualsUISubState extends BaseOptionsMenu
{
	var noteOptionID:Int = -1;
	var notes:FlxTypedGroup<StrumNote>;
	var notesTween:Array<FlxTween> = [];
	var noteY:Float = 90;
	public function new()
	{
		title = '视觉与界面';
		rpcTitle = '视觉与界面设置菜单'; //for Discord Rich Presence

		// for note skins
		notes = new FlxTypedGroup<StrumNote>();
		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = new StrumNote(100 + (520 / Note.colArray.length) * i, -200, i, 0);
			note.centerOffsets();
			note.centerOrigin();
			note.playAnim('static');
			notes.add(note);
		}

		// options

		var noteSkins:Array<String> = Mods.mergeAllTextsNamed('images/noteSkins/list.txt', 'shared');
		if(noteSkins.length > 0)
		{
			if(!noteSkins.contains(ClientPrefs.data.noteSkin))
				ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin; //Reset to default if saved noteskin couldnt be found

			noteSkins.insert(0, ClientPrefs.defaultData.noteSkin); //Default skin always comes first
			var option:Option = new Option('音符皮肤:',
				"选择你的箭头样式：",
				'noteSkin',
				'string',
				noteSkins);
			addOption(option);
			option.onChange = onChangeNoteSkin;
			noteOptionID = optionsArray.length - 1;
		}
		
		var noteSplashes:Array<String> = Mods.mergeAllTextsNamed('images/noteSplashes/list.txt', 'shared');
		if(noteSplashes.length > 0)
		{
			if(!noteSplashes.contains(ClientPrefs.data.splashSkin))
				ClientPrefs.data.splashSkin = ClientPrefs.defaultData.splashSkin; //Reset to default if saved splashskin couldnt be found

			noteSplashes.insert(0, ClientPrefs.defaultData.splashSkin); //Default skin always comes first
			var option:Option = new Option('音符打击特效:',
				'选择音符打击粒子的样式：',
				'splashSkin',
				'string',
				noteSplashes);
			addOption(option);
		}

		var option:Option = new Option('打击特效透明度',
			'调整音符打击粒子的透明度',
			'splashAlpha',
			'percent');
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

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
		    '选择 FPS 计数器显示的颜色：',
			'fpsColor',
			'string',
			['白色', '青色', '蓝色', '红色', '绿色', '黄色']);
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

		var option:Option = new Option('Combo堆叠',
			'关闭后，评级与 Combo 数字将不再堆叠，节省系统内存，读谱也更清晰',
			'comboStacking',
			'bool');
		addOption(option);

		super();
		add(notes);
	}

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		
		if(noteOptionID < 0) return;

		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = notes.members[i];
			if(notesTween[i] != null) notesTween[i].cancel();
			if(curSelected == noteOptionID)
				notesTween[i] = FlxTween.tween(note, {y: noteY}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
			else
				notesTween[i] = FlxTween.tween(note, {y: -200}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
		}
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

	function onChangeNoteSkin()
	{
		notes.forEachAlive(function(note:StrumNote) {
			changeNoteSkin(note);
			note.centerOffsets();
			note.centerOrigin();
		});
	}

	function changeNoteSkin(note:StrumNote)
	{
		var skin:String = Note.defaultNoteSkin;
		var customSkin:String = skin + Note.getNoteSkinPostfix();
		if(Paths.fileExists('images/$customSkin.png', IMAGE)) skin = customSkin;

		note.texture = skin; //Load texture and anims
		note.reloadNote();
		note.playAnim('static');
	}

	override function destroy()
	{
		if(changedMusic && !OptionsState.onPlayState) FlxG.sound.playMusic(Paths.music('freakyMenu'), 1, true);
		super.destroy();
	}

	#if !mobile
	function onChangeFPSCounter()
	{
		if(Main.fpsVar != null)
			Main.fpsVar.applyDisplayMode();
	}
	#end
}
