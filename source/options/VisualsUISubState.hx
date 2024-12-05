package options;

import objects.Note;
import objects.StrumNote;
import objects.Alphabet;

class VisualsUISubState extends BaseOptionsMenu
{
	var noteOptionID:Int = -1;
	var notes:FlxTypedGroup<StrumNote>;
	var notesTween:Array<FlxTween> = [];
	var noteY:Float = 90;
	public function new()
	{
		title = 'Visuals and UI';
		rpcTitle = 'Visuals & UI Settings Menu'; //for Discord Rich Presence

		// for note skins
		notes = new FlxTypedGroup<StrumNote>();
		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = new StrumNote(370 + (560 / Note.colArray.length) * i, -200, i, 0);
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
			var option:Option = new Option('Note Skins:',
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
			var option:Option = new Option('Note Splashes:',
				"选择你的箭头打击粒子样式：",
				'splashSkin',
				'string',
				noteSplashes);
			addOption(option);
		}

		var option:Option = new Option('Note Splash Opacity',
			'调整箭头打击粒子的透明度',
			'splashAlpha',
			'percent');
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		var option:Option = new Option('Hide HUD',
			'如果你勾选了，那么血量条等东西将不会显示',
			'hideHud',
			'bool');
		addOption(option);

		var option:Option = new Option('Score Txt Font: ',
		    "选择信息文字使用的字体：",
			'scoreTxtFont',
			'string',
			['Original', 'Bahnschrift']);
		addOption(option);

		var option:Option = new Option('Hide Watermark',
			'如果你勾选了，那么左下角水印将不会显示',
			'hideWatermark',
			'bool');
		addOption(option);
		
		var option:Option = new Option('Time Bar:',
			"你想让时间条怎么显示？",
			'timeBarType',
			'string',
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']);
		addOption(option);

		var option:Option = new Option('Flashing Lights',
			"如果你不勾选，那么不会有频闪",
			'flashing',
			'bool');
		addOption(option);

		var option:Option = new Option('Custom Cutscene',
		    "选择你的过场动画样式：",
			'CustomFade',
			'string',
			['Move', 'Alpha']);
		addOption(option);

		var option:Option = new Option('Cutscene Text',
		    "如果你不勾选，将会关闭过场动画的引擎版本和事件指示器",
			'CustomFadeText',
			'bool');
		addOption(option);

		var option:Option = new Option('Camera Zooms',
			"如果你不勾选，那么镜头就不会缩放（我不知道）",
			'camZooms',
			'bool');
		addOption(option);

		var option:Option = new Option('Health Bar Opacity',
			'你想让你的血量条透明吗？',
			'healthBarAlpha',
			'percent');
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);
		
		#if !mobile
		var option:Option = new Option('FPS Counter',
			'如果你不勾选，那么帧数计数器（FPS）将不会显示',
			'showFPS',
			'bool');
		addOption(option);
		option.onChange = onChangeFPSCounter;
		#end
		
		var option:Option = new Option('FPS Engine Version',
			'如果你不勾选，那么帧数计数器下的引擎版本将不会显示',
			'showVer',
			'bool');
		addOption(option);

		var option:Option = new Option('FPS Display Color: ',
		    "你想让你的FPS计数器显示什么颜色？",
			'fpsColor',
			'string',
			['White', 'Cyan', 'Blue', 'Red', 'Green', 'Yellow']);
		addOption(option);
		
		var option:Option = new Option('Pause Screen Song:',
			"你想让你停下来放什么音乐？",
			'pauseMusic',
			'string',
			['None', 'Breakfast', 'Tea Time']);
		addOption(option);
		option.onChange = onChangePauseMusic;

        var option:Option = new Option('Check for Updates',
			'勾选此选项来检查你的ME引擎是不是最新的',
			'checkForUpdates',
			'bool');
		addOption(option);

		#if desktop
		var option:Option = new Option('Discord Rich Presence',
			"取消选中此项以防止意外泄漏，它将在Discord的“播放”框中隐藏应用程序",
			'discordRPC',
			'bool');
		addOption(option);
		#end

		var option:Option = new Option('Combo Stacking',
			"如果未选中，Rank和Combo将不会堆叠，从而节省系统内存并使其更易于读铺",
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
		if(ClientPrefs.data.pauseMusic == 'None')
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
			Main.fpsVar.visible = ClientPrefs.data.showFPS;
	}
	#end
}
