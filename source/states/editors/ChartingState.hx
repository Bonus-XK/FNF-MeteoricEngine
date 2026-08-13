package states.editors;

import flash.geom.Rectangle;
import tjson.TJSON as Json;
import haxe.format.JsonParser;
import haxe.io.Bytes;

import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxInputText;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUIDropDownMenu;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUISlider;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.ui.FlxButton;

import flixel.util.FlxColor;
import flixel.util.FlxSort;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxTimer;
import lime.media.AudioBuffer;
import lime.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.media.Sound;
import openfl.net.FileReference;
import openfl.utils.Assets as OpenFlAssets;

import backend.Song;
import backend.Section;
import backend.StageData;
import backend.Paths;
import backend.Mods;
import backend.Conductor;
import backend.ClientPrefs;
import backend.CoolUtil;
import backend.MusicBeatState;

import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.HealthIcon;
import objects.AttachedSprite;
import objects.Character;
import substates.Prompt;


#if sys
import flash.media.Sound;
import sys.FileSystem;
import sys.io.File;
#end

@:access(flixel.sound.FlxSound._sound)
@:access(openfl.media.Sound.__buffer)

class ChartingState extends MusicBeatState
{
	public static var noteTypeList:Array<String> = //Used for backwards compatibility with 0.1 - 0.3.2 charts, though, you should add your hardcoded custom note types here too.
	[
		'',
		'Alt Animation',
		'Hey!',
		'Hurt Note',
		'GF Sing',
		'No Animation'
	];
	public var ignoreWarnings = false;
	var curNoteTypes:Array<String> = [];
	var undos = [];
	var redos = [];
	var eventStuff:Array<Dynamic> =
	[
		['', "Nothing. Yep, that's right."],
		['Dadbattle Spotlight', "Used in Dad Battle,\nValue 1: 0/1 = ON/OFF,\n2 = Target Dad\n3 = Target BF"],
		['Hey!', "Plays the \"Hey!\" animation from Bopeebo,\nValue 1: BF = Only Boyfriend, GF = Only Girlfriend,\nSomething else = Both.\nValue 2: Custom animation duration,\nleave it blank for 0.6s"],
		['Set GF Speed', "Sets GF head bopping speed,\nValue 1: 1 = Normal speed,\n2 = 1/2 speed, 4 = 1/4 speed etc.\nUsed on Fresh during the beatbox parts.\n\nWarning: Value must be integer!"],
		['Philly Glow', "Exclusive to Week 3\nValue 1: 0/1/2 = OFF/ON/Reset Gradient\n \nNo, i won't add it to other weeks."],
		['Kill Henchmen', "For Mom's songs, don't use this please, i love them :("],
		['Add Camera Zoom', "Used on MILF on that one \"hard\" part\nValue 1: Camera zoom add (Default: 0.015)\nValue 2: UI zoom add (Default: 0.03)\nLeave the values blank if you want to use Default."],
		['BG Freaks Expression', "Should be used only in \"school\" Stage!"],
		['Trigger BG Ghouls', "Should be used only in \"schoolEvil\" Stage!"],
		['Play Animation', "Plays an animation on a Character,\nonce the animation is completed,\nthe animation changes to Idle\n\nValue 1: Animation to play.\nValue 2: Character (Dad, BF, GF)"],
		['Camera Follow Pos', "Value 1: X\nValue 2: Y\n\nThe camera won't change the follow point\nafter using this, for getting it back\nto normal, leave both values blank."],
		['Alt Idle Animation', "Sets a specified suffix after the idle animation name.\nYou can use this to trigger 'idle-alt' if you set\nValue 2 to -alt\n\nValue 1: Character to set (Dad, BF or GF)\nValue 2: New suffix (Leave it blank to disable)"],
		['Screen Shake', "Value 1: Camera shake\nValue 2: HUD shake\n\nEvery value works as the following example: \"1, 0.05\".\nThe first number (1) is the duration.\nThe second number (0.05) is the intensity."],
		['Change Character', "Value 1: Character to change (Dad, BF, GF)\nValue 2: New character's name"],
		['Change Scroll Speed', "Value 1: Scroll Speed Multiplier (1 is default)\nValue 2: Time it takes to change fully in seconds."],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		['Play Sound', "Value 1: Sound file name\nValue 2: Volume (Default: 1), ranges from 0 to 1"]
	];

	var _file:FileReference;

	// ===================== 现代 UI（Freeplay 设计语言） =====================
	static final PANEL_X:Float = 656;
	static final PANEL_Y:Float = 20;
	static final PANEL_W:Float = 472;
	static final PANEL_H:Float = 600;
	static final CONTENT_X:Float = PANEL_X + 16;
	static final CONTENT_Y:Float = PANEL_Y + 100;
	static final CONTENT_W:Float = PANEL_W - 32;
	static final CONTENT_RW:Float = (PANEL_W - 48) / 2;

	var tabGroups:Array<FlxSpriteGroup> = [];
	var tabBtns:Array<{bg:FlxSprite, txt:FlxText}> = [];
	var curTab:Int = 0;
	var lastHoveredTab:Int = -2;
	var dropdownLayer:FlxSpriteGroup;
	var allButtons:Array<EditorButton> = [];
	var allToggles:Array<EditorToggle> = [];
	var allInputs:Array<EditorInput> = [];
	var allSteppers:Array<EditorStepper> = [];
	var allDropdowns:Array<EditorDropdown> = [];
	var strumTimeInputText:EditorInput;
	var stepperSusLength:EditorStepper;
	var noteTypeDropDown:EditorDropdown;
	var eventDropDown:EditorDropdown;
	var currentType:Int = 0;
	var toastText:FlxText;
	var toastTimer:FlxTimer;
	var hintTxt:FlxText;
	var statusTxt:FlxText;
	var descText:FlxText;
	var selectedEventText:FlxText;

	public static var goToPlayState:Bool = false;
	/**
	 * Array of notes showing when each section STARTS in STEPS
	 * Usually rounded up??
	 */
	public static var curSec:Int = 0;
	public static var lastSection:Int = 0;
	private static var lastSong:String = '';

	var bpmTxt:FlxText;

	var camPos:FlxObject;
	var strumLine:FlxSprite;
	var quant:AttachedSprite;
	var strumLineNotes:FlxTypedGroup<StrumNote>;
	var curSong:String = 'Test';
	var amountSteps:Int = 0;
	var bullshitUI:FlxGroup;

	var highlight:FlxSprite;

	public static var GRID_SIZE:Int = 40;
	var CAM_OFFSET:Int = 360;

	var dummyArrow:FlxSprite;

	var curRenderedSustains:FlxTypedGroup<FlxSprite>;
	var curRenderedNotes:FlxTypedGroup<Note>;
	var curRenderedNoteType:FlxTypedGroup<FlxText>;

	var nextRenderedSustains:FlxTypedGroup<FlxSprite>;
	var nextRenderedNotes:FlxTypedGroup<Note>;

	var gridBG:FlxSprite;
	var nextGridBG:FlxSprite;

	var daquantspot = 0;
	var curEventSelected:Int = 0;
	var curUndoIndex = 0;
	var curRedoIndex = 0;
	var _song:SwagSong;
	/*
	 * WILL BE THE CURRENT / LAST PLACED NOTE
	**/
	var curSelectedNote:Array<Dynamic> = null;
	var check_gfSection:EditorToggle;
	var check_changeBPM:EditorToggle;
	var check_altAnim:EditorToggle;
	var check_notesSec:EditorToggle;
	var check_eventsSec:EditorToggle;
	var stepperBeats:EditorStepper;
	var stepperSectionBPM:EditorStepper;
	var check_mustHitSection:EditorToggle;
	var check_voices:EditorToggle;
	var notesCopied:Array<Dynamic> = [];
	var sectionToCopy:Int = 0;

	var playbackSpeed:Float = 1;

	var vocals:FlxSound = null;

	var leftIcon:HealthIcon;
	var rightIcon:HealthIcon;
	var leftNameTxt:FlxText;
	var rightNameTxt:FlxText;

	var value1InputText:EditorInput;
	var value2InputText:EditorInput;
	var currentSongName:String;

	var zoomTxt:FlxText;

	var zoomList:Array<Float> = [
		0.25,
		0.5,
		1,
		2,
		3,
		4,
		6,
		8,
		12,
		16,
		24
	];
	var curZoom:Int = 2;

	var waveformSprite:FlxSprite;
	var gridLayer:FlxTypedGroup<FlxSprite>;

	public static var quantization:Int = 16;
	public static var curQuant = 3;

	public var quantizations:Array<Int> = [
		4,
		8,
		12,
		16,
		20,
		24,
		32,
		48,
		64,
		96,
		192
	];

	var text:String = "";
	public static var vortex:Bool = false;
	public var mouseQuant:Bool = false;
	override function create()
	{
		if (PlayState.SONG != null)
			_song = PlayState.SONG;
		else
		{
			Difficulty.resetList();
			_song = {
				song: 'Test',
				notes: [],
				events: [],
				bpm: 150.0,
				needsVoices: true,
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 1,
				stage: 'stage'
			};
			addSection();
			PlayState.SONG = _song;
		}

		// Paths.clearMemory();

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
		#end

		vortex = FlxG.save.data.chart_vortex;
		ignoreWarnings = FlxG.save.data.ignoreWarnings;
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.color = 0xFF222222;
		add(bg);

		gridLayer = new FlxTypedGroup<FlxSprite>();
		add(gridLayer);

		waveformSprite = new FlxSprite(GRID_SIZE, 0).makeGraphic(1, 1, 0x00FFFFFF);
		add(waveformSprite);

		var eventIcon:FlxSprite = new FlxSprite(-GRID_SIZE - 5, -90).loadGraphic(Paths.image('eventArrow'));
		eventIcon.antialiasing = ClientPrefs.data.antialiasing;
		leftIcon = new HealthIcon('bf');
		rightIcon = new HealthIcon('dad');
		eventIcon.scrollFactor.set(1, 1);
		leftIcon.scrollFactor.set(1, 1);
		rightIcon.scrollFactor.set(1, 1);

		eventIcon.setGraphicSize(30, 30);
		leftIcon.setGraphicSize(0, 40);
		rightIcon.setGraphicSize(0, 40);

		add(eventIcon);
		add(leftIcon);
		add(rightIcon);

		leftIcon.setPosition(GRID_SIZE + 10, 4);
		rightIcon.setPosition(GRID_SIZE * 5.2, 4);

		leftNameTxt = makeText(GRID_SIZE + 52, 18, 100, '', 11, 0xFFD7D7E0);
		add(leftNameTxt);
		rightNameTxt = makeText(GRID_SIZE * 5.2 + 52, 18, 100, '', 11, 0xFFD7D7E0);
		add(rightNameTxt);

		curRenderedSustains = new FlxTypedGroup<FlxSprite>();
		curRenderedNotes = new FlxTypedGroup<Note>();
		curRenderedNoteType = new FlxTypedGroup<FlxText>();

		nextRenderedSustains = new FlxTypedGroup<FlxSprite>();
		nextRenderedNotes = new FlxTypedGroup<Note>();

		FlxG.mouse.visible = true;
		//FlxG.save.bind('funkin', CoolUtil.getSavePath());

		//addSection();

		// sections = _song.notes;

		currentSongName = Paths.formatToSongPath(_song.song);
		loadSong();
		reloadGridLayer();
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		if(curSec >= _song.notes.length) curSec = _song.notes.length - 1;

		bpmTxt = new FlxText(370, 32, 0, "", 14);
		bpmTxt.setFormat(Paths.font('future.ttf'), 14, 0xFFB8B8C8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		bpmTxt.scrollFactor.set();
		add(bpmTxt);

		strumLine = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * 9), 4);
		add(strumLine);

		quant = new AttachedSprite('chart_quant','chart_quant');
		quant.animation.addByPrefix('q','chart_quant',0,false);
		quant.animation.play('q', true, false, 0);
		quant.sprTracker = strumLine;
		quant.xAdd = -32;
		quant.yAdd = 8;
		add(quant);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		for (i in 0...8){
			var note:StrumNote = new StrumNote(GRID_SIZE * (i+1), strumLine.y, i % 4, 0);
			note.setGraphicSize(GRID_SIZE, GRID_SIZE);
			note.updateHitbox();
			note.playAnim('static', true);
			strumLineNotes.add(note);
			note.scrollFactor.set(1, 1);
		}
		add(strumLineNotes);

		camPos = new FlxObject(0, 0, 1, 1);
		camPos.setPosition(strumLine.x + CAM_OFFSET, strumLine.y);

		dummyArrow = new FlxSprite().makeGraphic(GRID_SIZE, GRID_SIZE);
		dummyArrow.antialiasing = ClientPrefs.data.antialiasing;
		add(dummyArrow);

		// ---- 右面板（Freeplay 设计语言） ----
		add(makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 22));
		var rightTitle:FlxText = makeText(CONTENT_X, PANEL_Y + 14, CONTENT_W, '编谱设置', 22, 0xFFFFFFFF);
		add(rightTitle);

		buildTabs();
		dropdownLayer = new FlxSpriteGroup();
		add(dropdownLayer);

		toastText = makeText(CONTENT_X, PANEL_Y + PANEL_H - 40, CONTENT_W, '', 13, 0xFFFFFFFF, CENTER);
		toastText.visible = false;
		add(toastText);

		hintTxt = makeText(10, 660, 620, 'W/S 滚动 · A/D 小节 · ↑/↓ 吸附 · ←/→ 量化 · Z/X 缩放 · 空格 播放 · ESC 试玩 · Enter 游玩 · Ctrl+Z 撤销', 12, 0xFF8A8FA8);
		add(hintTxt);

		statusTxt = makeText(PANEL_X + 10, 660, PANEL_W - 20, '', 12, 0xFF8A8FA8, RIGHT);
		add(statusTxt);

		addSongUI();
		addSectionUI();
		addNoteUI();
		addEventsUI();
		addChartingUI();
		addDataUI();
		updateHeads();
		updateWaveform();
		//UI_box.selected_tab = 4;

		add(curRenderedSustains);
		add(curRenderedNotes);
		add(curRenderedNoteType);
		add(nextRenderedSustains);
		add(nextRenderedNotes);

		if(lastSong != currentSongName) {
			changeSection();
		}
		lastSong = currentSongName;

		zoomTxt = new FlxText(370, 10, 0, "Zoom: 1 / 1", 14);
		zoomTxt.setFormat(Paths.font('future.ttf'), 14, 0xFFB8B8C8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		zoomTxt.scrollFactor.set();
		add(zoomTxt);

		changeTab(0);
		updateGrid();
		super.create();
	}

	var check_mute_inst:EditorToggle = null;
	var check_mute_vocals:EditorToggle = null;
	var check_vortex:EditorToggle = null;
	var check_warnings:EditorToggle = null;
	var playSoundBf:EditorToggle = null;
	var playSoundDad:EditorToggle = null;
	var UI_songTitle:EditorInput;
	var stageDropDown:EditorDropdown;
	var ddPlayer1:EditorDropdown;
	var ddPlayer2:EditorDropdown;
	var ddGF:EditorDropdown;
	var stepperSongBPM:EditorStepper;
	var stepperSongSpeed:EditorStepper;
	function addSongUI():Void
	{
		var grp = tabGroups[0];

		UI_songTitle = new EditorInput(CONTENT_X, CONTENT_Y, 300, '曲目名称', _song.song, function(text:String)
		{
			_song.song = text;
		});
		grp.add(UI_songTitle); allInputs.push(UI_songTitle);

		var check_voices:EditorToggle = new EditorToggle(CONTENT_X, CONTENT_Y + 52, '需要人声', _song.needsVoices, function()
		{
			_song.needsVoices = check_voices.checked;
		});
		grp.add(check_voices); allToggles.push(check_voices);

		stepperSongBPM = new EditorStepper(CONTENT_X, CONTENT_Y + 98, CONTENT_RW, '歌曲 BPM', _song.bpm, 1, 400, 1, 3, function(v:Float)
		{
			_song.bpm = v;
			Conductor.mapBPMChanges(_song);
			Conductor.bpm = v;
			if (stepperSusLength != null) stepperSusLength.step = Math.ceil(Conductor.stepCrochet / 2);
			updateGrid();
		});
		grp.add(stepperSongBPM); allSteppers.push(stepperSongBPM);

		stepperSongSpeed = new EditorStepper(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 98, CONTENT_RW, '歌曲速度', _song.speed, 0.1, 10, 0.1, 2, function(v:Float)
		{
			_song.speed = v;
		});
		grp.add(stepperSongSpeed); allSteppers.push(stepperSongSpeed);

		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('characters/'), Paths.mods(Mods.currentModDirectory + '/characters/'), Paths.getPreloadPath('characters/')];
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/characters/'));
		#else
		var directories:Array<String> = [Paths.getPreloadPath('characters/')];
		#end

		var characters:Array<String> = Mods.mergeAllTextsNamed('data/characterList.txt', Paths.getPreloadPath());
		var tempArray:Array<String> = [];
		for (character in characters)
		{
			if(character.trim().length > 0)
				tempArray.push(character);
		}

		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var charToCheck:String = file.substr(0, file.length - 5);
						if(charToCheck.trim().length > 0 && !charToCheck.endsWith('-dead') && !tempArray.contains(charToCheck)) {
							tempArray.push(charToCheck);
							characters.push(charToCheck);
						}
					}
				}
			}
		}
		#end

		ddPlayer1 = new EditorDropdown(CONTENT_X, CONTENT_Y + 152, CONTENT_RW, '玩家 1', characters, Std.int(Math.max(0, characters.indexOf(_song.player1))), function(i:Int)
		{
			_song.player1 = characters[i];
			updateHeads();
		}, dropdownLayer);
		grp.add(ddPlayer1); allDropdowns.push(ddPlayer1);

		ddGF = new EditorDropdown(CONTENT_X, CONTENT_Y + 206, CONTENT_RW, '女友', characters, Std.int(Math.max(0, characters.indexOf(_song.gfVersion))), function(i:Int)
		{
			_song.gfVersion = characters[i];
			updateHeads();
		}, dropdownLayer);
		grp.add(ddGF); allDropdowns.push(ddGF);

		ddPlayer2 = new EditorDropdown(CONTENT_X, CONTENT_Y + 260, CONTENT_RW, '玩家 2', characters, Std.int(Math.max(0, characters.indexOf(_song.player2))), function(i:Int)
		{
			_song.player2 = characters[i];
			updateHeads();
		}, dropdownLayer);
		grp.add(ddPlayer2); allDropdowns.push(ddPlayer2);

		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('stages/'), Paths.mods(Mods.currentModDirectory + '/stages/'), Paths.getPreloadPath('stages/')];
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/stages/'));
		#else
		var directories:Array<String> = [Paths.getPreloadPath('stages/')];
		#end

		var stageFile:Array<String> = Mods.mergeAllTextsNamed('data/stageList.txt', Paths.getPreloadPath());
		var stages:Array<String> = [];
		for (stage in stageFile) {
			if(stage.trim().length > 0) {
				stages.push(stage);
			}
			tempArray.push(stage);
		}
		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var stageToCheck:String = file.substr(0, file.length - 5);
						if(stageToCheck.trim().length > 0 && !tempArray.contains(stageToCheck)) {
							tempArray.push(stageToCheck);
							stages.push(stageToCheck);
						}
					}
				}
			}
		}
		#end

		if(stages.length < 1) stages.push('stage');

		stageDropDown = new EditorDropdown(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 152, CONTENT_RW, '舞台', stages, Std.int(Math.max(0, stages.indexOf(_song.stage))), function(i:Int)
		{
			_song.stage = stages[i];
		}, dropdownLayer);
		grp.add(stageDropDown); allDropdowns.push(stageDropDown);

		var y:Float = CONTENT_Y + 314;
		var saveButton:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '保存', function()
		{
			saveLevel();
		}, 13, true);
		grp.add(saveButton); allButtons.push(saveButton);

		var reloadSong:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '重新加载音频', function()
		{
			currentSongName = Paths.formatToSongPath(UI_songTitle.field.text);
			loadSong();
			updateWaveform();
			showToast('音频已重新加载');
		}, 13);
		grp.add(reloadSong); allButtons.push(reloadSong);

		y += 44;
		var saveEventsBtn:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '保存事件', function()
		{
			saveEvents();
		}, 13);
		grp.add(saveEventsBtn); allButtons.push(saveEventsBtn);

		var reloadSongJson:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '重新加载 JSON', function()
		{
			openSubState(new Prompt('重新加载将清空当前进度，是否继续？', 0, function() {
				loadJson(_song.song.toLowerCase());
			},
			null, ignoreWarnings));
		}, 13);
		grp.add(reloadSongJson); allButtons.push(reloadSongJson);

		y += 44;
		var loadAutosaveBtn:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '加载自动保存', function()
		{
			PlayState.SONG = Song.parseJSONshit(FlxG.save.data.autosave);
			MusicBeatState.resetState();
		}, 13);
		grp.add(loadAutosaveBtn); allButtons.push(loadAutosaveBtn);

		var loadEventJson:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '加载事件', function()
		{
			var songName:String = Paths.formatToSongPath(_song.song);
			var file:String = Paths.json(songName + '/events');
			#if sys
			if (#if MODS_ALLOWED FileSystem.exists(Paths.modsJson(songName + '/events')) || #end FileSystem.exists(file))
			#else
			if (OpenFlAssets.exists(file))
			#end
			{
				clearEvents();
				var events:SwagSong = Song.loadFromJson('events', songName);
				_song.events = events.events;
				changeSection(curSec);
			}
			else showToast('未找到事件文件');
		}, 13);
		grp.add(loadEventJson); allButtons.push(loadEventJson);

		y += 44;
		var clear_notes:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '清空音符', function()
		{
			openSubState(new Prompt('将清空全部音符，是否继续？', 0, function(){
				for (sec in 0..._song.notes.length) {
					_song.notes[sec].sectionNotes = [];
				}
				updateGrid();
				showToast('全部音符已清空');
			}, null, ignoreWarnings));
		}, 13, true);
		grp.add(clear_notes); allButtons.push(clear_notes);

		var clear_events:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '清空事件', function()
		{
			openSubState(new Prompt('将清空全部事件，是否继续？', 0, clearEvents, null, ignoreWarnings));
		}, 13, true);
		grp.add(clear_events); allButtons.push(clear_events);
	}

	function addSectionUI():Void
	{
		var grp = tabGroups[1];

		stepperBeats = new EditorStepper(CONTENT_X, CONTENT_Y, CONTENT_RW, '小节拍数', getSectionBeats(), 1, 16, 1, 1, function(v:Float)
		{
			_song.notes[curSec].sectionBeats = v;
			reloadGridLayer();
		});
		grp.add(stepperBeats); allSteppers.push(stepperBeats);

		stepperSectionBPM = new EditorStepper(CONTENT_X + CONTENT_RW + 24, CONTENT_Y, CONTENT_RW, '小节 BPM', _song.notes[curSec].bpm, 0, 999, 1, 1, function(v:Float)
		{
			_song.notes[curSec].bpm = v;
			updateGrid();
		});
		grp.add(stepperSectionBPM); allSteppers.push(stepperSectionBPM);

		check_mustHitSection = new EditorToggle(CONTENT_X, CONTENT_Y + 54, 'Must Hit 小节', _song.notes[curSec].mustHitSection, function()
		{
			_song.notes[curSec].mustHitSection = check_mustHitSection.checked;
			updateGrid();
			updateHeads();
		});
		grp.add(check_mustHitSection); allToggles.push(check_mustHitSection);

		check_gfSection = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 54, 'GF 小节', _song.notes[curSec].gfSection, function()
		{
			_song.notes[curSec].gfSection = check_gfSection.checked;
			updateGrid();
			updateHeads();
		});
		grp.add(check_gfSection); allToggles.push(check_gfSection);

		check_changeBPM = new EditorToggle(CONTENT_X, CONTENT_Y + 104, '本小节换速', _song.notes[curSec].changeBPM, function()
		{
			_song.notes[curSec].changeBPM = check_changeBPM.checked;
			Conductor.mapBPMChanges(_song);
			updateGrid();
		});
		grp.add(check_changeBPM); allToggles.push(check_changeBPM);

		check_altAnim = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 104, 'Alt 动画', _song.notes[curSec].altAnim, function()
		{
			_song.notes[curSec].altAnim = check_altAnim.checked;
		});
		grp.add(check_altAnim); allToggles.push(check_altAnim);

		check_notesSec = new EditorToggle(CONTENT_X, CONTENT_Y + 154, '音符', true);
		grp.add(check_notesSec); allToggles.push(check_notesSec);

		check_eventsSec = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 154, '事件', true);
		grp.add(check_eventsSec); allToggles.push(check_eventsSec);

		var y:Float = CONTENT_Y + 198;
		var copyButton:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '复制本节', function()
		{
			notesCopied = [];
			sectionToCopy = curSec;
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				notesCopied.push(note);
			}

			var startThing:Float = sectionStartTime();
			var endThing:Float = sectionStartTime(1);
			for (event in _song.events)
			{
				var strumTime:Float = event[0];
				if(endThing > event[0] && event[0] >= startThing)
				{
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length)
					{
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					notesCopied.push([strumTime, -1, copiedEventArray]);
				}
			}
			showToast('本节已复制');
		}, 13);
		grp.add(copyButton); allButtons.push(copyButton);

		var pasteButton:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '粘贴本节', function()
		{
			if(notesCopied == null || notesCopied.length < 1)
			{
				showToast('剪贴板为空');
				return;
			}

			var addToTime:Float = Conductor.stepCrochet * (getSectionBeats() * 4 * (curSec - sectionToCopy));

			for (note in notesCopied)
			{
				var copiedNote:Array<Dynamic> = [];
				var newStrumTime:Float = note[0] + addToTime;
				if(note[1] < 0)
				{
					if(check_eventsSec.checked)
					{
						var copiedEventArray:Array<Dynamic> = [];
						for (i in 0...note[2].length)
						{
							var eventToPush:Array<Dynamic> = note[2][i];
							copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
						}
						_song.events.push([newStrumTime, copiedEventArray]);
					}
				}
				else
				{
					if(check_notesSec.checked)
					{
						if(note[4] != null)
							copiedNote = [newStrumTime, note[1], note[2], note[3], note[4]];
						else
							copiedNote = [newStrumTime, note[1], note[2], note[3]];

						_song.notes[curSec].sectionNotes.push(copiedNote);
					}
				}
			}
			updateGrid();
			showToast('已粘贴到本节');
		}, 13);
		grp.add(pasteButton); allButtons.push(pasteButton);

		y += 44;
		var clearSectionButton:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '清空本节', function()
		{
			if(check_notesSec.checked)
			{
				_song.notes[curSec].sectionNotes = [];
			}

			if(check_eventsSec.checked)
			{
				var i:Int = _song.events.length - 1;
				var startThing:Float = sectionStartTime();
				var endThing:Float = sectionStartTime(1);
				while(i > -1) {
					var event:Array<Dynamic> = _song.events[i];
					if(event != null && endThing > event[0] && event[0] >= startThing)
					{
						_song.events.remove(event);
					}
					--i;
				}
			}
			updateGrid();
			updateNoteUI();
			showToast('本节已清空');
		}, 13, true);
		grp.add(clearSectionButton); allButtons.push(clearSectionButton);

		var swapSection:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '交换轨道', function()
		{
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				note[1] = (note[1] + 4) % 8;
				_song.notes[curSec].sectionNotes[i] = note;
			}
			updateGrid();
			showToast('轨道已交换');
		}, 13);
		grp.add(swapSection); allButtons.push(swapSection);

		y += 44;
		stepperCopy = new EditorStepper(CONTENT_X, y, 130, '往前几节', 1, -999, 999, 1, 0);
		grp.add(stepperCopy); allSteppers.push(stepperCopy);

		var copyLastButton:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '复制前 N 节', function()
		{
			var value:Int = Std.int(stepperCopy.value);
			if(value == 0) return;

			var daSec = FlxMath.maxInt(curSec, value);

			for (note in _song.notes[daSec - value].sectionNotes)
			{
				var strum = note[0] + Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);

				var copiedNote:Array<Dynamic> = [strum, note[1], note[2], note[3]];
				_song.notes[daSec].sectionNotes.push(copiedNote);
			}

			var startThing:Float = sectionStartTime(-value);
			var endThing:Float = sectionStartTime(-value + 1);
			for (event in _song.events)
			{
				var strumTime:Float = event[0];
				if(endThing > event[0] && event[0] >= startThing)
				{
					strumTime += Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length)
					{
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					_song.events.push([strumTime, copiedEventArray]);
				}
			}
			updateGrid();
			showToast('已复制上一节');
		}, 13);
		grp.add(copyLastButton); allButtons.push(copyLastButton);

		y += 44;
		var duetButton:EditorButton = new EditorButton(CONTENT_X, y, CONTENT_RW, 34, '二重奏', function()
		{
			var duetNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				var boob = note[1];
				if (boob>3){
					boob -= 4;
				}else{
					boob += 4;
				}

				var copiedNote:Array<Dynamic> = [note[0], boob, note[2], note[3]];
				duetNotes.push(copiedNote);
			}

			for (i in duetNotes){
				_song.notes[curSec].sectionNotes.push(i);
			}

			updateGrid();
			showToast('已生成二重奏');
		}, 13);
		grp.add(duetButton); allButtons.push(duetButton);

		var mirrorButton:EditorButton = new EditorButton(CONTENT_X + CONTENT_RW + 24, y, CONTENT_RW, 34, '镜像翻转', function()
		{
			for (note in _song.notes[curSec].sectionNotes)
			{
				var boob = note[1]%4;
				boob = 3 - boob;
				if (note[1] > 3) boob += 4;

				note[1] = boob;
			}
			updateGrid();
			showToast('已镜像翻转');
		}, 13);
		grp.add(mirrorButton); allButtons.push(mirrorButton);
	}

	function addNoteUI():Void
	{
		var grp = tabGroups[2];

		strumTimeInputText = new EditorInput(CONTENT_X, CONTENT_Y, 300, '音符时间 (毫秒)', '0', function(text:String)
		{
			if(curSelectedNote != null && curSelectedNote[2] != null)
			{
				var value:Float = Std.parseFloat(text);
				if(Math.isNaN(value)) value = 0;
				curSelectedNote[0] = value;
				updateGrid();
			}
		}, true);
		grp.add(strumTimeInputText); allInputs.push(strumTimeInputText);

		stepperSusLength = new EditorStepper(CONTENT_X, CONTENT_Y + 54, 300, '长条长度 (毫秒)', 0, 0, Conductor.stepCrochet * 64, Math.ceil(Conductor.stepCrochet / 2), 0, function(v:Float)
		{
			if(curSelectedNote != null && curSelectedNote[2] != null)
			{
				curSelectedNote[2] = v;
				updateGrid();
			}
		});
		grp.add(stepperSusLength); allSteppers.push(stepperSusLength);

		var key:Int = 0;
		while (key < noteTypeList.length) {
			curNoteTypes.push(noteTypeList[key]);
			key++;
		}

		#if sys
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'custom_notetypes/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
			{
				var fileName:String = file.toLowerCase().trim();
				var wordLen:Int = 4;
				if((#if LUA_ALLOWED fileName.endsWith('.lua') || #end
					#if HSCRIPT_ALLOWED (fileName.endsWith('.hx') && (wordLen = 3) == 3) || #end
					fileName.endsWith('.txt')) && fileName != 'readme.txt')
				{
					var fileToCheck:String = file.substr(0, file.length - wordLen);
					if(!curNoteTypes.contains(fileToCheck))
					{
						curNoteTypes.push(fileToCheck);
						key++;
					}
				}
			}
		#end

		var displayNameList:Array<String> = curNoteTypes.copy();
		for (i in 1...displayNameList.length) {
			displayNameList[i] = i + '. ' + displayNameList[i];
		}

		noteTypeDropDown = new EditorDropdown(CONTENT_X, CONTENT_Y + 108, 300, '音符类型', displayNameList, 0, function(i:Int)
		{
			currentType = i;
			if(curSelectedNote != null && curSelectedNote[1] > -1 && curSelectedNote[2] != null) {
				curSelectedNote[3] = curNoteTypes[currentType];
				updateGrid();
			}
		}, dropdownLayer);
		grp.add(noteTypeDropDown); allDropdowns.push(noteTypeDropDown);

		var delBtn:EditorButton = new EditorButton(CONTENT_X, CONTENT_Y + 168, CONTENT_RW, 34, '删除选中', function()
		{
			if(curSelectedNote != null)
			{
				if(curSelectedNote[2] != null) _song.notes[curSec].sectionNotes.remove(curSelectedNote);
				else _song.events.remove(curSelectedNote);
				curSelectedNote = null;
				updateGrid();
				updateNoteUI();
			}
		}, 13, true);
		grp.add(delBtn); allButtons.push(delBtn);

		var hint:FlxText = makeText(CONTENT_X, CONTENT_Y + 230, CONTENT_W, '点击网格放置音符
拖拽向下拉出长条
点击音符：删除 · Ctrl+点击：选中
Alt+点击：更换类型 · Q/E：调整长条
滚轮：滚动时间', 12, 0xFF7C8198);
		grp.add(hint);
	}

	function addEventsUI():Void
	{
		var grp = tabGroups[3];

		#if LUA_ALLOWED
		var eventPushedMap:Map<String, Bool> = new Map<String, Bool>();
		var directories:Array<String> = [];

		#if MODS_ALLOWED
		directories.push(Paths.mods('custom_events/'));
		directories.push(Paths.mods(Mods.currentModDirectory + '/custom_events/'));
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/custom_events/'));
		#end

		for (i in 0...directories.length) {
			var directory:String =  directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file != 'readme.txt' && file.endsWith('.txt')) {
						var fileToCheck:String = file.substr(0, file.length - 4);
						if(!eventPushedMap.exists(fileToCheck)) {
							eventPushedMap.set(fileToCheck, true);
							eventStuff.push([fileToCheck, File.getContent(path)]);
						}
					}
				}
			}
		}
		eventPushedMap.clear();
		eventPushedMap = null;
		#end

		descText = new FlxText(CONTENT_X, CONTENT_Y + 196, CONTENT_W, '', 11);
		descText.setFormat(Paths.font('future.ttf'), 11, 0xFF8A8FA8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.wordWrap = true;
		grp.add(descText);

		var leEvents:Array<String> = [];
		for (i in 0...eventStuff.length) {
			leEvents.push(eventStuff[i][0]);
		}

		eventDropDown = new EditorDropdown(CONTENT_X, CONTENT_Y, 300, '事件类型', leEvents, 0, function(i:Int)
		{
			descText.text = eventStuff[i][1];
			if (curSelectedNote != null && curSelectedNote[2] == null)
			{
				curSelectedNote[1][curEventSelected][0] = eventStuff[i][0];
				updateGrid();
			}
		}, dropdownLayer);
		grp.add(eventDropDown); allDropdowns.push(eventDropDown);

		value1InputText = new EditorInput(CONTENT_X, CONTENT_Y + 54, 140, '值 1', '', function(text:String)
		{
			if(curSelectedNote != null && curSelectedNote[2] == null)
			{
				if(curSelectedNote[1][curEventSelected] != null)
				{
					curSelectedNote[1][curEventSelected][1] = text;
					updateGrid();
				}
			}
		});
		grp.add(value1InputText); allInputs.push(value1InputText);

		value2InputText = new EditorInput(CONTENT_X + 160, CONTENT_Y + 54, 140, '值 2', '', function(text:String)
		{
			if(curSelectedNote != null && curSelectedNote[2] == null)
			{
				if(curSelectedNote[1][curEventSelected] != null)
				{
					curSelectedNote[1][curEventSelected][2] = text;
					updateGrid();
				}
			}
		});
		grp.add(value2InputText); allInputs.push(value2InputText);

		var btnY:Float = CONTENT_Y + 112;
		var removeButton:EditorButton = new EditorButton(CONTENT_X, btnY, 70, 34, '删除', function()
		{
			if(curSelectedNote != null && curSelectedNote[2] == null)
			{
				if(curSelectedNote[1].length < 2)
				{
					_song.events.remove(curSelectedNote);
					curSelectedNote = null;
				}
				else
				{
					curSelectedNote[1].remove(curSelectedNote[1][curEventSelected]);
				}

				var eventsGroup:Array<Dynamic>;
				--curEventSelected;
				if(curEventSelected < 0) curEventSelected = 0;
				else if(curSelectedNote != null && curEventSelected >= (eventsGroup = curSelectedNote[1]).length) curEventSelected = eventsGroup.length - 1;

				changeEventSelected();
				updateGrid();
				updateNoteUI();
			}
		}, 12, true);
		grp.add(removeButton); allButtons.push(removeButton);

		var addButton:EditorButton = new EditorButton(CONTENT_X + 80, btnY, 70, 34, '添加', function()
		{
			if(curSelectedNote != null && curSelectedNote[2] == null)
			{
				var eventsGroup:Array<Dynamic> = curSelectedNote[1];
				eventsGroup.push(['', '', '']);

				changeEventSelected(1);
				updateGrid();
				updateNoteUI();
			}
		}, 12);
		grp.add(addButton); allButtons.push(addButton);

		var moveLeftButton:EditorButton = new EditorButton(CONTENT_X + 160, btnY, 70, 34, '上一个', function()
		{
			changeEventSelected(-1);
		}, 12);
		grp.add(moveLeftButton); allButtons.push(moveLeftButton);

		var moveRightButton:EditorButton = new EditorButton(CONTENT_X + 240, btnY, 70, 34, '下一个', function()
		{
			changeEventSelected(1);
		}, 12);
		grp.add(moveRightButton); allButtons.push(moveRightButton);

		selectedEventText = new FlxText(CONTENT_X, CONTENT_Y + 160, CONTENT_W, '选中事件：无', 12);
		selectedEventText.setFormat(Paths.font('future.ttf'), 12, 0xFFD7D7E0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		grp.add(selectedEventText);

		var listLabel:FlxText = makeText(CONTENT_X, CONTENT_Y + 306, 200, '事件操作提示', 13, 0xFFD7D7E0);
		grp.add(listLabel);

		var tip:FlxText = makeText(CONTENT_X, CONTENT_Y + 330, CONTENT_W, '点击网格左侧事件轨道放置事件音符
选中事件后可在此编辑类型与数值
Ctrl+点击事件音符可选中', 12, 0xFF7C8198);
		grp.add(tip);
	}

	function changeEventSelected(change:Int = 0)
	{
		if(curSelectedNote != null && curSelectedNote[2] == null) //Is event note
		{
			curEventSelected += change;
			if(curEventSelected < 0) curEventSelected = Std.int(curSelectedNote[1].length) - 1;
			else if(curEventSelected >= curSelectedNote[1].length) curEventSelected = 0;
			selectedEventText.text = '选中事件：' + (curEventSelected + 1) + ' / ' + curSelectedNote[1].length;
		}
		else
		{
			curEventSelected = 0;
			selectedEventText.text = '选中事件：无';
		}
		updateNoteUI();
	}

	var metronome:EditorToggle;
	var mouseScrollingQuant:EditorToggle;
	var metronomeStepper:EditorStepper;
	var metronomeOffsetStepper:EditorStepper;
	var disableAutoScrolling:EditorToggle;
	#if desktop
	var waveformUseInstrumental:EditorToggle;
	var waveformUseVoices:EditorToggle;
	#end
	var instVolume:EditorStepper;
	var voicesVolume:EditorStepper;
	var stepperRate:EditorStepper;
	var stepperCopy:EditorStepper;
	function addChartingUI() {
		var grp = tabGroups[4];

		metronome = new EditorToggle(CONTENT_X, CONTENT_Y, '节拍器', FlxG.save.data.chart_metronome == true, function()
		{
			FlxG.save.data.chart_metronome = metronome.checked;
			FlxG.save.flush();
		});
		grp.add(metronome); allToggles.push(metronome);

		disableAutoScrolling = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y, '禁用自动滚动', FlxG.save.data.chart_noAutoScroll == true, function()
		{
			FlxG.save.data.chart_noAutoScroll = disableAutoScrolling.checked;
			FlxG.save.flush();
		});
		grp.add(disableAutoScrolling); allToggles.push(disableAutoScrolling);

		metronomeStepper = new EditorStepper(CONTENT_X, CONTENT_Y + 44, CONTENT_RW, '节拍器 BPM', _song.bpm, 1, 1500, 5, 1, null);
		grp.add(metronomeStepper); allSteppers.push(metronomeStepper);

		metronomeOffsetStepper = new EditorStepper(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 44, CONTENT_RW, '偏移 (毫秒)', 0, 0, 1000, 25, 1, null);
		grp.add(metronomeOffsetStepper); allSteppers.push(metronomeOffsetStepper);

		#if desktop
		waveformUseInstrumental = new EditorToggle(CONTENT_X, CONTENT_Y + 98, '伴奏波形', FlxG.save.data.chart_waveformInst == true, function()
		{
			if (waveformUseVoices != null) waveformUseVoices.setChecked(false, false);
			FlxG.save.data.chart_waveformVoices = false;
			FlxG.save.data.chart_waveformInst = waveformUseInstrumental.checked;
			FlxG.save.flush();
			updateWaveform();
		});
		grp.add(waveformUseInstrumental); allToggles.push(waveformUseInstrumental);

		waveformUseVoices = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 98, '人声波形', FlxG.save.data.chart_waveformVoices == true, function()
		{
			if (waveformUseInstrumental != null) waveformUseInstrumental.setChecked(false, false);
			FlxG.save.data.chart_waveformInst = false;
			FlxG.save.data.chart_waveformVoices = waveformUseVoices.checked;
			FlxG.save.flush();
			updateWaveform();
		});
		grp.add(waveformUseVoices); allToggles.push(waveformUseVoices);
		#end

		check_vortex = new EditorToggle(CONTENT_X, CONTENT_Y + 148, 'Vortex 编辑器', FlxG.save.data.chart_vortex == true, function()
		{
			FlxG.save.data.chart_vortex = check_vortex.checked;
			vortex = FlxG.save.data.chart_vortex;
			reloadGridLayer();
		});
		grp.add(check_vortex); allToggles.push(check_vortex);

		mouseScrollingQuant = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 148, '鼠标量化滚动', FlxG.save.data.mouseScrollingQuant == true, function()
		{
			FlxG.save.data.mouseScrollingQuant = mouseScrollingQuant.checked;
			mouseQuant = FlxG.save.data.mouseScrollingQuant;
			FlxG.save.flush();
		});
		grp.add(mouseScrollingQuant); allToggles.push(mouseScrollingQuant);

		check_warnings = new EditorToggle(CONTENT_X, CONTENT_Y + 198, '忽略进度警告', FlxG.save.data.ignoreWarnings == true, function()
		{
			FlxG.save.data.ignoreWarnings = check_warnings.checked;
			ignoreWarnings = FlxG.save.data.ignoreWarnings;
			FlxG.save.flush();
		});
		grp.add(check_warnings); allToggles.push(check_warnings);

		stepperRate = new EditorStepper(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 198, CONTENT_RW, '播放速度', playbackSpeed, 0.5, 3, 0.05, 2, function(v:Float)
		{
			playbackSpeed = v;
		});
		grp.add(stepperRate); allSteppers.push(stepperRate);

		check_mute_inst = new EditorToggle(CONTENT_X, CONTENT_Y + 252, '静音伴奏 (编辑中)', false, function()
		{
			var vol:Float = check_mute_inst.checked ? 0 : 1;
			if (FlxG.sound.music != null) FlxG.sound.music.volume = vol;
		});
		grp.add(check_mute_inst); allToggles.push(check_mute_inst);

		check_mute_vocals = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 252, '静音人声 (编辑中)', false, function()
		{
			if(vocals != null) {
				var vol:Float = check_mute_vocals.checked ? 0 : 1;
				vocals.volume = vol;
			}
		});
		grp.add(check_mute_vocals); allToggles.push(check_mute_vocals);

		playSoundBf = new EditorToggle(CONTENT_X, CONTENT_Y + 302, 'BF 音符音效', FlxG.save.data.chart_playSoundBf == true, function()
		{
			FlxG.save.data.chart_playSoundBf = playSoundBf.checked;
			FlxG.save.flush();
		});
		grp.add(playSoundBf); allToggles.push(playSoundBf);

		playSoundDad = new EditorToggle(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 302, 'Dad 音符音效', FlxG.save.data.chart_playSoundDad == true, function()
		{
			FlxG.save.data.chart_playSoundDad = playSoundDad.checked;
			FlxG.save.flush();
		});
		grp.add(playSoundDad); allToggles.push(playSoundDad);

		instVolume = new EditorStepper(CONTENT_X, CONTENT_Y + 352, CONTENT_RW, '伴奏音量', 1, 0, 1, 0.1, 1, function(v:Float)
		{
			if (FlxG.sound.music != null) FlxG.sound.music.volume = v;
		});
		grp.add(instVolume); allSteppers.push(instVolume);

		voicesVolume = new EditorStepper(CONTENT_X + CONTENT_RW + 24, CONTENT_Y + 352, CONTENT_RW, '人声音量', 1, 0, 1, 0.1, 1, function(v:Float)
		{
			if (vocals != null) vocals.volume = v;
		});
		grp.add(voicesVolume); allSteppers.push(voicesVolume);
	}

	var gameOverCharacterInputText:EditorInput;
	var gameOverSoundInputText:EditorInput;
	var gameOverLoopInputText:EditorInput;
	var gameOverEndInputText:EditorInput;
	var noteSkinInputText:EditorInput;
	var noteSplashesInputText:EditorInput;
	function addDataUI()
	{
		var grp = tabGroups[5];

		gameOverCharacterInputText = new EditorInput(CONTENT_X, CONTENT_Y, 300, '游戏结束角色', _song.gameOverChar != null ? _song.gameOverChar : '', function(text:String) { _song.gameOverChar = text; });
		grp.add(gameOverCharacterInputText); allInputs.push(gameOverCharacterInputText);

		gameOverSoundInputText = new EditorInput(CONTENT_X, CONTENT_Y + 54, 300, '死亡音效 (sounds/)', _song.gameOverSound != null ? _song.gameOverSound : '', function(text:String) { _song.gameOverSound = text; });
		grp.add(gameOverSoundInputText); allInputs.push(gameOverSoundInputText);

		gameOverLoopInputText = new EditorInput(CONTENT_X, CONTENT_Y + 108, 300, '结束循环音乐 (music/)', _song.gameOverLoop != null ? _song.gameOverLoop : '', function(text:String) { _song.gameOverLoop = text; });
		grp.add(gameOverLoopInputText); allInputs.push(gameOverLoopInputText);

		gameOverEndInputText = new EditorInput(CONTENT_X, CONTENT_Y + 162, 300, '结束重试音乐 (music/)', _song.gameOverEnd != null ? _song.gameOverEnd : '', function(text:String) { _song.gameOverEnd = text; });
		grp.add(gameOverEndInputText); allInputs.push(gameOverEndInputText);

		var check_disableNoteRGB:EditorToggle;
		check_disableNoteRGB = new EditorToggle(CONTENT_X, CONTENT_Y + 222, '禁用音符 RGB', _song.disableNoteRGB == true, function()
		{
			_song.disableNoteRGB = check_disableNoteRGB.checked;
			updateGrid();
		});
		grp.add(check_disableNoteRGB); allToggles.push(check_disableNoteRGB);

		noteSkinInputText = new EditorInput(CONTENT_X, CONTENT_Y + 276, 250, '音符皮肤', _song.arrowSkin != null ? _song.arrowSkin : '', function(text:String) { _song.arrowSkin = text; });
		grp.add(noteSkinInputText); allInputs.push(noteSkinInputText);

		var reloadNotesButton:EditorButton = new EditorButton(CONTENT_X + 268, CONTENT_Y + 278, 160, 34, '应用音符皮肤', function() {
			_song.arrowSkin = noteSkinInputText.field.text;
			updateGrid();
			showToast('音符皮肤已应用');
		}, 12);
		grp.add(reloadNotesButton); allButtons.push(reloadNotesButton);

		noteSplashesInputText = new EditorInput(CONTENT_X, CONTENT_Y + 330, 250, '溅射皮肤', _song.splashSkin != null ? _song.splashSkin : '', function(text:String) { _song.splashSkin = text; });
		grp.add(noteSplashesInputText); allInputs.push(noteSplashesInputText);

		var reloadSplashButton:EditorButton = new EditorButton(CONTENT_X + 268, CONTENT_Y + 332, 160, 34, '应用溅射皮肤', function() {
			_song.splashSkin = noteSplashesInputText.field.text;
			updateGrid();
			showToast('溅射皮肤已应用');
		}, 12);
		grp.add(reloadSplashButton); allButtons.push(reloadSplashButton);
	}

	function loadSong():Void
	{
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			// vocals.stop();
		}

		var file:Dynamic = Paths.voices(currentSongName);
		vocals = new FlxSound();
		if (Std.isOfType(file, Sound) || OpenFlAssets.exists(file)) {
			vocals.loadEmbedded(file);
			vocals.autoDestroy = false;
			FlxG.sound.list.add(vocals);
		}
		generateSong();
		FlxG.sound.music.pause();
		Conductor.songPosition = sectionStartTime();
		FlxG.sound.music.time = Conductor.songPosition;

		var curTime:Float = 0;
		//trace(_song.notes.length);
		if(_song.notes.length <= 1) //First load ever
		{
			trace('first load ever!!');
			while(curTime < FlxG.sound.music.length)
			{
				addSection();
				curTime += (60 / _song.bpm) * 4000;
			}
		}
	}

	var playtesting:Bool = false;
	var playtestingTime:Float = 0;
	var playtestingOnComplete:Void->Void = null;
	override function closeSubState()
	{
		if(playtesting)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = playtestingTime;
			FlxG.sound.music.onComplete = playtestingOnComplete;
			if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
			if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;

			if(vocals != null)
			{
				vocals.pause();
				vocals.time = playtestingTime;
				if (voicesVolume != null) vocals.volume = voicesVolume.value;
				if (check_mute_vocals != null && check_mute_vocals.checked) vocals.volume = 0;
			}

			#if desktop
			// Updating Discord Rich Presence
			DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
			#end
		}
		super.closeSubState();
	}

	function generateSong() {
		FlxG.sound.playMusic(Paths.inst(currentSongName), 0.6/*, false*/);
		FlxG.sound.music.autoDestroy = false;
		if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
		if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;

		FlxG.sound.music.onComplete = function()
		{
			FlxG.sound.music.pause();
			Conductor.songPosition = 0;
			if(vocals != null) {
				vocals.pause();
				vocals.time = 0;
			}
			changeSection();
			curSec = 0;
			updateGrid();
			updateSectionUI();
			vocals.play();
		};
	}

	override function getEvent(id:String, sender:Dynamic, data:Dynamic, ?params:Array<Dynamic>)
	{
		// 新版 UI 使用组件直接回调，不再依赖 FlxUI 事件分发
	}

	var updatedSection:Bool = false;

	function sectionStartTime(add:Int = 0):Float
	{
		var daBPM:Float = _song.bpm;
		var daPos:Float = 0;
		for (i in 0...curSec + add)
		{
			if(_song.notes[i] != null)
			{
				if (_song.notes[i].changeBPM)
				{
					daBPM = _song.notes[i].bpm;
				}
				daPos += getSectionBeats(i) * (1000 * 60 / daBPM);
			}
		}
		return daPos;
	}

	var lastConductorPos:Float;
	var colorSine:Float = 0;
	override function update(elapsed:Float)
	{
		curStep = recalculateSteps();

		// ---- UI 交互（标签页按钮 + 组件点击） ----
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;

		var hoveredTab:Int = -1;
		for (i in 0...tabBtns.length)
		{
			var b = tabBtns[i];
			var hover:Bool = mx >= b.bg.x && mx <= b.bg.x + b.bg.width && my >= b.bg.y && my <= b.bg.y + b.bg.height;
			if (hover) hoveredTab = i;
		}
		if (hoveredTab != lastHoveredTab)
		{
			lastHoveredTab = hoveredTab;
			for (i in 0...tabBtns.length)
			{
				redrawBox(tabBtns[i].bg, 74, 30, 10, (i == curTab || i == hoveredTab) ? 0x30FFFFFF : 0x1CFFFFFF, (i == curTab || i == hoveredTab) ? 0x8CFFFFFF : 0x45FFFFFF);
				tabBtns[i].txt.color = (i == curTab) ? 0xFFFFFFFF : (i == hoveredTab ? 0xFFE0E0E8 : 0xFFB8B8C8);
			}
		}
		if (FlxG.mouse.justPressed && hoveredTab >= 0 && hoveredTab != curTab)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
			changeTab(hoveredTab);
		}

		var typing:Bool = false;
		for (input in allInputs) if (input.field.hasFocus) { typing = true; break; }

		var openDropdown:EditorDropdown = null;
		for (d in allDropdowns) if (d.open) { openDropdown = d; break; }

		if (openDropdown != null)
		{
			openDropdown.updateOpen();
		}
		else if (!typing)
		{
			updateWidgets(mx, my);
		}


		if(FlxG.sound.music.time < 0) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		else if(FlxG.sound.music.time > FlxG.sound.music.length) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		_song.song = UI_songTitle.field.text;

		strumLineUpdateY();
		for (i in 0...8){
			strumLineNotes.members[i].y = strumLine.y;
		}

		FlxG.mouse.visible = true;//cause reasons. trust me
		camPos.y = strumLine.y;
		if(!disableAutoScrolling.checked) {
			if (Math.ceil(strumLine.y) >= gridBG.height)
			{
				if (_song.notes[curSec + 1] == null)
				{
					addSection();
				}

				changeSection(curSec + 1, false);
			} else if(strumLine.y < -10) {
				changeSection(curSec - 1, false);
			}
		}
		FlxG.watch.addQuick('daBeat', curBeat);
		FlxG.watch.addQuick('daStep', curStep);


		if (FlxG.mouse.x > gridBG.x
			&& FlxG.mouse.x < gridBG.x + gridBG.width
			&& FlxG.mouse.y > gridBG.y
			&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
		{
			dummyArrow.visible = true;
			dummyArrow.x = Math.floor(FlxG.mouse.x / GRID_SIZE) * GRID_SIZE;
			if (FlxG.keys.pressed.SHIFT)
				dummyArrow.y = FlxG.mouse.y;
			else
			{
				var gridmult = GRID_SIZE / (quantization / 16);
				dummyArrow.y = Math.floor(FlxG.mouse.y / gridmult) * gridmult;
			}
		} else {
			dummyArrow.visible = false;
		}

		if (FlxG.mouse.justPressed)
		{
			if (FlxG.mouse.overlaps(curRenderedNotes))
			{
				curRenderedNotes.forEachAlive(function(note:Note)
				{
					if (FlxG.mouse.overlaps(note))
					{
						if (FlxG.keys.pressed.CONTROL)
						{
							selectNote(note);
						}
						else if (FlxG.keys.pressed.ALT)
						{
							selectNote(note);
							curSelectedNote[3] = curNoteTypes[currentType];
							updateGrid();
						}
						else
						{
							//trace('tryin to delete note...');
							deleteNote(note);
						}
					}
				});
			}
			else
			{
				if (FlxG.mouse.x > gridBG.x
					&& FlxG.mouse.x < gridBG.x + gridBG.width
					&& FlxG.mouse.y > gridBG.y
					&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
				{
					FlxG.log.add('added note');
					addNote();
				}
			}
		}

		var blockInput:Bool = false;
		for (input in allInputs) {
			if(input.field.hasFocus) {
				ClientPrefs.toggleVolumeKeys(false);
				blockInput = true;
				break;
			}
		}

		if(!blockInput) {
			ClientPrefs.toggleVolumeKeys(true);
			for (dropDownMenu in allDropdowns) {
				if(dropDownMenu.open) {
					blockInput = true;
					break;
				}
			}
		}

		if (!blockInput)
		{
			if (FlxG.keys.justPressed.ESCAPE)
			{
				FlxG.sound.music.pause();
				if(vocals != null) vocals.pause();

				autosaveSong();
				playtesting = true;
				playtestingTime = Conductor.songPosition;
				playtestingOnComplete = FlxG.sound.music.onComplete;
				openSubState(new states.editors.EditorPlayState(playbackSpeed));
			}
			if (FlxG.keys.justPressed.ENTER)
			{
				autosaveSong();
				FlxG.mouse.visible = false;
				PlayState.SONG = _song;
				FlxG.sound.music.stop();
				if(vocals != null) vocals.stop();

				//if(_song.stage == null) _song.stage = stageDropDown.selectedLabel;
				StageData.loadDirectory(_song);
				LoadingState.loadAndSwitchState(new PlayState());
			}

			if(curSelectedNote != null && curSelectedNote[1] > -1) {
				if (FlxG.keys.justPressed.E)
				{
					changeNoteSustain(Conductor.stepCrochet);
				}
				if (FlxG.keys.justPressed.Q)
				{
					changeNoteSustain(-Conductor.stepCrochet);
				}
			}


			if (FlxG.keys.justPressed.BACKSPACE) {
				// Protect against lost data when quickly leaving the chart editor.
				autosaveSong();
				PlayState.chartingMode = false;
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				FlxG.mouse.visible = false;
				return;
			}

			if(FlxG.keys.justPressed.Z && FlxG.keys.pressed.CONTROL) {
				undo();
			}

			if(FlxG.keys.justPressed.Z && curZoom > 0 && !FlxG.keys.pressed.CONTROL) {
				--curZoom;
				updateZoom();
			}
			if(FlxG.keys.justPressed.X && curZoom < zoomList.length-1) {
				curZoom++;
				updateZoom();
			}

			if (FlxG.keys.justPressed.TAB)
			{
				if (FlxG.keys.pressed.SHIFT)
					changeTab((curTab + tabGroups.length - 1) % tabGroups.length);
				else
					changeTab((curTab + 1) % tabGroups.length);
			}

			if (FlxG.keys.justPressed.SPACE)
			{
				if (FlxG.sound.music.playing)
				{
					FlxG.sound.music.pause();
					if(vocals != null) vocals.pause();
				}
				else
				{
					if(vocals != null) {
						vocals.play();
						vocals.pause();
						vocals.time = FlxG.sound.music.time;
						vocals.play();
					}
					FlxG.sound.music.play();
				}
			}

			if (!FlxG.keys.pressed.ALT && FlxG.keys.justPressed.R)
			{
				if (FlxG.keys.pressed.SHIFT)
					resetSection(true);
				else
					resetSection();
			}

			if (FlxG.mouse.wheel != 0)
			{
				FlxG.sound.music.pause();
				if (!mouseQuant)
					FlxG.sound.music.time -= (FlxG.mouse.wheel * Conductor.stepCrochet*0.8);
				else
					{
						var time:Float = FlxG.sound.music.time;
						var beat:Float = curDecBeat;
						var snap:Float = quantization / 4;
						var increase:Float = 1 / snap;
						if (FlxG.mouse.wheel > 0)
						{
							var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
							FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
						}else{
							var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
							FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
						}
					}
				if(vocals != null) {
					vocals.pause();
					vocals.time = FlxG.sound.music.time;
				}
			}

			//ARROW VORTEX SHIT NO DEADASS



			if (FlxG.keys.pressed.W || FlxG.keys.pressed.S)
			{
				FlxG.sound.music.pause();

				var holdingShift:Float = 1;
				if (FlxG.keys.pressed.CONTROL) holdingShift = 0.25;
				else if (FlxG.keys.pressed.SHIFT) holdingShift = 4;

				var daTime:Float = 700 * FlxG.elapsed * holdingShift;

				if (FlxG.keys.pressed.W)
				{
					FlxG.sound.music.time -= daTime;
				}
				else
					FlxG.sound.music.time += daTime;

				if(vocals != null) {
					vocals.pause();
					vocals.time = FlxG.sound.music.time;
				}
			}

			if(!vortex){
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN  )
				{
					FlxG.sound.music.pause();
					updateCurStep();
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase; //(Math.floor((beat+snap) / snap) * snap);
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}else{
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase; //(Math.floor((beat+snap) / snap) * snap);
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
				}
			}

			var style = currentType;

			if (FlxG.keys.pressed.SHIFT){
				style = 3;
			}

			var conductorTime = Conductor.songPosition; //+ sectionStartTime();Conductor.songPosition / Conductor.stepCrochet;

			//AWW YOU MADE IT SEXY <3333 THX SHADMAR

			if(!blockInput){
				if(FlxG.keys.justPressed.RIGHT){
					curQuant++;
					if(curQuant>quantizations.length-1)
						curQuant = 0;

					quantization = quantizations[curQuant];
				}

				if(FlxG.keys.justPressed.LEFT){
					curQuant--;
					if(curQuant<0)
						curQuant = quantizations.length-1;

					quantization = quantizations[curQuant];
				}
				quant.animation.play('q', true, false, curQuant);
			}
			if(vortex && !blockInput){
				var controlArray:Array<Bool> = [FlxG.keys.justPressed.ONE, FlxG.keys.justPressed.TWO, FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR,
											   FlxG.keys.justPressed.FIVE, FlxG.keys.justPressed.SIX, FlxG.keys.justPressed.SEVEN, FlxG.keys.justPressed.EIGHT];

				if(controlArray.contains(true))
				{
					for (i in 0...controlArray.length)
					{
						if(controlArray[i])
							doANoteThing(conductorTime, i, style);
					}
				}

				var feces:Float;
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN  )
				{
					FlxG.sound.music.pause();


					updateCurStep();
					//FlxG.sound.music.time = (Math.round(curStep/quants[curQuant])*quants[curQuant]) * Conductor.stepCrochet;

						//(Math.floor((curStep+quants[curQuant]*1.5/(quants[curQuant]/2))/quants[curQuant])*quants[curQuant]) * Conductor.stepCrochet;//snap into quantization
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						feces = Conductor.beatToSeconds(fuck);
					}else{
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase; //(Math.floor((beat+snap) / snap) * snap);
						feces = Conductor.beatToSeconds(fuck);
					}
					FlxTween.tween(FlxG.sound.music, {time:feces}, 0.1, {ease:FlxEase.circOut});
					if(vocals != null) {
						vocals.pause();
						vocals.time = FlxG.sound.music.time;
					}

					var dastrum = 0;

					if (curSelectedNote != null){
						dastrum = curSelectedNote[0];
					}

					var secStart:Float = sectionStartTime();
					var datime = (feces - secStart) - (dastrum - secStart); //idk math find out why it doesn't work on any other section other than 0
					if (curSelectedNote != null)
					{
						var controlArray:Array<Bool> = [FlxG.keys.pressed.ONE, FlxG.keys.pressed.TWO, FlxG.keys.pressed.THREE, FlxG.keys.pressed.FOUR,
													   FlxG.keys.pressed.FIVE, FlxG.keys.pressed.SIX, FlxG.keys.pressed.SEVEN, FlxG.keys.pressed.EIGHT];

						if(controlArray.contains(true))
						{

							for (i in 0...controlArray.length)
							{
								if(controlArray[i])
									if(curSelectedNote[1] == i) curSelectedNote[2] += datime - curSelectedNote[2] - Conductor.stepCrochet;
							}
							updateGrid();
							updateNoteUI();
						}
					}
				}
			}
			var shiftThing:Int = 1;
			if (FlxG.keys.pressed.SHIFT)
				shiftThing = 4;

			if (FlxG.keys.justPressed.D)
				changeSection(curSec + shiftThing);
			if (FlxG.keys.justPressed.A) {
				if(curSec <= 0) {
					changeSection(_song.notes.length-1);
				} else {
					changeSection(curSec - shiftThing);
				}
			}
		} else if (FlxG.keys.justPressed.ENTER) {
			for (i in 0...allInputs.length) {
				if(allInputs[i].field.hasFocus) {
					allInputs[i].field.hasFocus = false;
				}
			}
		}

		strumLineNotes.visible = quant.visible = vortex;

		if(FlxG.sound.music.time < 0) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		else if(FlxG.sound.music.time > FlxG.sound.music.length) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		strumLineUpdateY();
		camPos.y = strumLine.y;
		for (i in 0...8){
			strumLineNotes.members[i].y = strumLine.y;
			strumLineNotes.members[i].alpha = FlxG.sound.music.playing ? 1 : 0.35;
		}

		// PLAYBACK SPEED CONTROLS //
		var holdingShift = FlxG.keys.pressed.SHIFT;
		var holdingLB = FlxG.keys.pressed.LBRACKET;
		var holdingRB = FlxG.keys.pressed.RBRACKET;
		var pressedLB = FlxG.keys.justPressed.LBRACKET;
		var pressedRB = FlxG.keys.justPressed.RBRACKET;

		if (!holdingShift && pressedLB || holdingShift && holdingLB)
			playbackSpeed -= 0.01;
		if (!holdingShift && pressedRB || holdingShift && holdingRB)
			playbackSpeed += 0.01;
		if (FlxG.keys.pressed.ALT && (pressedLB || pressedRB || holdingLB || holdingRB))
			playbackSpeed = 1;
		//

		if (playbackSpeed <= 0.5)
			playbackSpeed = 0.5;
		if (playbackSpeed >= 3)
			playbackSpeed = 3;

		FlxG.sound.music.pitch = playbackSpeed;
		vocals.pitch = playbackSpeed;

		bpmTxt.text =
		Std.string(FlxMath.roundDecimal(Conductor.songPosition / 1000, 2)) + " / " + Std.string(FlxMath.roundDecimal(FlxG.sound.music.length / 1000, 2)) +
		"\nSection: " + curSec +
		"\n\nBeat: " + Std.string(curDecBeat).substring(0,4) +
		"\n\nStep: " + curStep +
		"\n\nBeat Snap: " + quantization + "th";

		var playedSound:Array<Bool> = [false, false, false, false]; //Prevents ouchy GF sex sounds
		curRenderedNotes.forEachAlive(function(note:Note) {
			note.alpha = 1;
			if(curSelectedNote != null) {
				var noteDataToCheck:Int = note.noteData;
				if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;

				if (curSelectedNote[0] == note.strumTime && ((curSelectedNote[2] == null && noteDataToCheck < 0) || (curSelectedNote[2] != null && curSelectedNote[1] == noteDataToCheck)))
				{
					colorSine += elapsed;
					var colorVal:Float = 0.7 + Math.sin(Math.PI * colorSine) * 0.3;
					note.color = FlxColor.fromRGBFloat(colorVal, colorVal, colorVal, 0.999); //Alpha can't be 100% or the color won't be updated for some reason, guess i will die
				}
			}

			if(note.strumTime <= Conductor.songPosition) {
				note.alpha = 0.4;
				if(note.strumTime > lastConductorPos && FlxG.sound.music.playing && note.noteData > -1) {
					var data:Int = note.noteData % 4;
					var noteDataToCheck:Int = note.noteData;
					if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;
						strumLineNotes.members[noteDataToCheck].playAnim('confirm', true);
						strumLineNotes.members[noteDataToCheck].resetAnim = ((note.sustainLength / 1000) + 0.15) / playbackSpeed;
					if(!playedSound[data]) {
						if(note.hitsoundChartEditor && ((playSoundBf.checked && note.mustPress) || (playSoundDad.checked && !note.mustPress)))
						{
							var soundToPlay = note.hitsound;
							if(_song.player1 == 'gf') //Easter egg
								soundToPlay = 'GF_' + Std.string(data + 1);

							FlxG.sound.play(Paths.sound(soundToPlay)).pan = note.noteData < 4? -0.3 : 0.3; //would be coolio
							playedSound[data] = true;
						}

						data = note.noteData;
						if(note.mustPress != _song.notes[curSec].mustHitSection)
						{
							data += 4;
						}
					}
				}
			}
		});

		if(metronome.checked && lastConductorPos != Conductor.songPosition) {
			var metroInterval:Float = 60 / metronomeStepper.value;
			var metroStep:Int = Math.floor(((Conductor.songPosition + metronomeOffsetStepper.value) / metroInterval) / 1000);
			var lastMetroStep:Int = Math.floor(((lastConductorPos + metronomeOffsetStepper.value) / metroInterval) / 1000);
			if(metroStep != lastMetroStep) {
				FlxG.sound.play(Paths.sound('Metronome_Tick'));
				//trace('Ticked');
			}
		}
		lastConductorPos = Conductor.songPosition;
		super.update(elapsed);
	}

	function updateZoom() {
		var daZoom:Float = zoomList[curZoom];
		var zoomThing:String = '1 / ' + daZoom;
		if(daZoom < 1) zoomThing = Math.round(1 / daZoom) + ' / 1';
		zoomTxt.text = 'Zoom: ' + zoomThing;
		reloadGridLayer();
	}

	override function destroy()
	{
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		super.destroy();
	}

	/*
	function loadAudioBuffer() {
		if(audioBuffers[0] != null) {
			audioBuffers[0].dispose();
		}
		audioBuffers[0] = null;
		#if MODS_ALLOWED
		if(FileSystem.exists(Paths.modFolders('songs/' + currentSongName + '/Inst.ogg'))) {
			audioBuffers[0] = AudioBuffer.fromFile(Paths.modFolders('songs/' + currentSongName + '/Inst.ogg'));
			//trace('Custom vocals found');
		}
		else { #end
			var leVocals:String = Paths.getPath(currentSongName + '/Inst.' + Paths.SOUND_EXT, SOUND, 'songs');
			if (OpenFlAssets.exists(leVocals)) { //Vanilla inst
				audioBuffers[0] = AudioBuffer.fromFile('./' + leVocals.substr(6));
				//trace('Inst found');
			}
		#if MODS_ALLOWED
		}
		#end

		if(audioBuffers[1] != null) {
			audioBuffers[1].dispose();
		}
		audioBuffers[1] = null;
		#if MODS_ALLOWED
		if(FileSystem.exists(Paths.modFolders('songs/' + currentSongName + '/Voices.ogg'))) {
			audioBuffers[1] = AudioBuffer.fromFile(Paths.modFolders('songs/' + currentSongName + '/Voices.ogg'));
			//trace('Custom vocals found');
		} else { #end
			var leVocals:String = Paths.getPath(currentSongName + '/Voices.' + Paths.SOUND_EXT, SOUND, 'songs');
			if (OpenFlAssets.exists(leVocals)) { //Vanilla voices
				audioBuffers[1] = AudioBuffer.fromFile('./' + leVocals.substr(6));
				//trace('Voices found, LETS FUCKING GOOOO');
			}
		#if MODS_ALLOWED
		}
		#end
	}
	*/

	var lastSecBeats:Float = 0;
	var lastSecBeatsNext:Float = 0;
	var columns:Int = 9;
	function reloadGridLayer() {
		gridLayer.clear();
		gridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats() * 4 * zoomList[curZoom]));
		gridBG.antialiasing = false;
		gridBG.scale.set(GRID_SIZE, GRID_SIZE);
		gridBG.updateHitbox();

		#if desktop
		if(FlxG.save.data.chart_waveformInst || FlxG.save.data.chart_waveformVoices) {
			updateWaveform();
		}
		#end

		var leHeight:Int = Std.int(gridBG.height);
		var foundNextSec:Bool = false;
		if(sectionStartTime(1) <= FlxG.sound.music.length)
		{
			nextGridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats(curSec + 1) * 4 * zoomList[curZoom]));
			nextGridBG.antialiasing = false;
			nextGridBG.scale.set(GRID_SIZE, GRID_SIZE);
			nextGridBG.updateHitbox();
			leHeight = Std.int(gridBG.height + nextGridBG.height);
			foundNextSec = true;
		}
		else nextGridBG = new FlxSprite().makeGraphic(1, 1, FlxColor.TRANSPARENT);
		nextGridBG.y = gridBG.height;
		
		gridLayer.add(nextGridBG);
		gridLayer.add(gridBG);

		if(foundNextSec)
		{
			var gridBlack:FlxSprite = new FlxSprite(0, gridBG.height).makeGraphic(1, 1, FlxColor.BLACK);
			gridBlack.setGraphicSize(Std.int(GRID_SIZE * 9), Std.int(nextGridBG.height));
			gridBlack.updateHitbox();
			gridBlack.antialiasing = false;
			gridBlack.alpha = 0.4;
			gridLayer.add(gridBlack);
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + gridBG.width - (GRID_SIZE * 4)).makeGraphic(1, 1, FlxColor.BLACK);
		gridBlackLine.setGraphicSize(2, leHeight);
		gridBlackLine.updateHitbox();
		gridBlackLine.antialiasing = false;
		gridLayer.add(gridBlackLine);

		for (i in 1...4) {
			var beatsep:FlxSprite = new FlxSprite(gridBG.x, (GRID_SIZE * (4 * curZoom)) * i).makeGraphic(1, 1, 0x44FF0000);
			beatsep.scale.x = gridBG.width;
			beatsep.updateHitbox();
			if(vortex) gridLayer.add(beatsep);
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + GRID_SIZE).makeGraphic(1, 1, FlxColor.BLACK);
		gridBlackLine.setGraphicSize(2, leHeight);
		gridBlackLine.updateHitbox();
		gridBlackLine.antialiasing = false;
		gridLayer.add(gridBlackLine);
		updateGrid();

		lastSecBeats = getSectionBeats();
		if(sectionStartTime(1) > FlxG.sound.music.length) lastSecBeatsNext = 0;
		else getSectionBeats(curSec + 1);
	}

	function strumLineUpdateY()
	{
		strumLine.y = getYfromStrum((Conductor.songPosition - sectionStartTime()) / zoomList[curZoom] % (Conductor.stepCrochet * 16)) / (getSectionBeats() / 4);
	}

	var waveformPrinted:Bool = true;
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];

	var lastWaveformHeight:Int = 0;
	function updateWaveform() {
		#if desktop
		if(waveformPrinted) {
			var width:Int = Std.int(GRID_SIZE * 8);
			var height:Int = Std.int(gridBG.height);
			if(lastWaveformHeight != height && waveformSprite.pixels != null)
			{
				waveformSprite.pixels.dispose();
				waveformSprite.pixels.disposeImage();
				waveformSprite.makeGraphic(width, height, 0x00FFFFFF);
				lastWaveformHeight = height;
			}
			waveformSprite.pixels.fillRect(new Rectangle(0, 0, width, height), 0x00FFFFFF);
		}
		waveformPrinted = false;

		if(!FlxG.save.data.chart_waveformInst && !FlxG.save.data.chart_waveformVoices) {
			//trace('Epic fail on the waveform lol');
			return;
		}

		wavData[0][0] = [];
		wavData[0][1] = [];
		wavData[1][0] = [];
		wavData[1][1] = [];

		var steps:Int = Math.round(getSectionBeats() * 4);
		var st:Float = sectionStartTime();
		var et:Float = st + (Conductor.stepCrochet * steps);

		if (FlxG.save.data.chart_waveformInst) {
			var sound:FlxSound = FlxG.sound.music;
			if (sound._sound != null && sound._sound.__buffer != null) {
				var bytes:Bytes = sound._sound.__buffer.data.toBytes();

				wavData = waveformData(
					sound._sound.__buffer,
					bytes,
					st,
					et,
					1,
					wavData,
					Std.int(gridBG.height)
				);
			}
		}

		if (FlxG.save.data.chart_waveformVoices) {
			var sound:FlxSound = vocals;
			if (sound._sound != null && sound._sound.__buffer != null) {
				var bytes:Bytes = sound._sound.__buffer.data.toBytes();

				wavData = waveformData(
					sound._sound.__buffer,
					bytes,
					st,
					et,
					1,
					wavData,
					Std.int(gridBG.height)
				);
			}
		}

		// Draws
		var gSize:Int = Std.int(GRID_SIZE * 8);
		var hSize:Int = Std.int(gSize / 2);

		var lmin:Float = 0;
		var lmax:Float = 0;

		var rmin:Float = 0;
		var rmax:Float = 0;

		var size:Float = 1;

		var leftLength:Int = (
			wavData[0][0].length > wavData[0][1].length ? wavData[0][0].length : wavData[0][1].length
		);

		var rightLength:Int = (
			wavData[1][0].length > wavData[1][1].length ? wavData[1][0].length : wavData[1][1].length
		);

		var length:Int = leftLength > rightLength ? leftLength : rightLength;

		var index:Int;
		for (i in 0...length) {
			index = i;

			lmin = FlxMath.bound(((index < wavData[0][0].length && index >= 0) ? wavData[0][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			lmax = FlxMath.bound(((index < wavData[0][1].length && index >= 0) ? wavData[0][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			rmin = FlxMath.bound(((index < wavData[1][0].length && index >= 0) ? wavData[1][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			rmax = FlxMath.bound(((index < wavData[1][1].length && index >= 0) ? wavData[1][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			waveformSprite.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), i * size, (lmin + rmin) + (lmax + rmax), size), FlxColor.BLUE);
		}

		waveformPrinted = true;
		#end
	}

	function waveformData(buffer:AudioBuffer, bytes:Bytes, time:Float, endTime:Float, multiply:Float = 1, ?array:Array<Array<Array<Float>>>, ?steps:Float):Array<Array<Array<Float>>>
	{
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null) return [[[0], [0]], [[0], [0]]];

		var khz:Float = (buffer.sampleRate / 1000);
		var channels:Int = buffer.channels;

		var index:Int = Std.int(time * khz);

		var samples:Float = ((endTime - time) * khz);

		if (steps == null) steps = 1280;

		var samplesPerRow:Float = samples / steps;
		var samplesPerRowI:Int = Std.int(samplesPerRow);

		var gotIndex:Int = 0;

		var lmin:Float = 0;
		var lmax:Float = 0;

		var rmin:Float = 0;
		var rmax:Float = 0;

		var rows:Float = 0;

		var simpleSample:Bool = true;//samples > 17200;
		var v1:Bool = false;

		if (array == null) array = [[[0], [0]], [[0], [0]]];

		while (index < (bytes.length - 1)) {
			if (index >= 0) {
				var byte:Int = bytes.getUInt16(index * channels * 2);

				if (byte > 65535 / 2) byte -= 65535;

				var sample:Float = (byte / 65535);

				if (sample > 0) {
					if (sample > lmax) lmax = sample;
				} else if (sample < 0) {
					if (sample < lmin) lmin = sample;
				}

				if (channels >= 2) {
					byte = bytes.getUInt16((index * channels * 2) + 2);

					if (byte > 65535 / 2) byte -= 65535;

					sample = (byte / 65535);

					if (sample > 0) {
						if (sample > rmax) rmax = sample;
					} else if (sample < 0) {
						if (sample < rmin) rmin = sample;
					}
				}
			}

			v1 = samplesPerRowI > 0 ? (index % samplesPerRowI == 0) : false;
			while (simpleSample ? v1 : rows >= samplesPerRow) {
				v1 = false;
				rows -= samplesPerRow;

				gotIndex++;

				var lRMin:Float = Math.abs(lmin) * multiply;
				var lRMax:Float = lmax * multiply;

				var rRMin:Float = Math.abs(rmin) * multiply;
				var rRMax:Float = rmax * multiply;

				if (gotIndex > array[0][0].length) array[0][0].push(lRMin);
					else array[0][0][gotIndex - 1] = array[0][0][gotIndex - 1] + lRMin;

				if (gotIndex > array[0][1].length) array[0][1].push(lRMax);
					else array[0][1][gotIndex - 1] = array[0][1][gotIndex - 1] + lRMax;

				if (channels >= 2) {
					if (gotIndex > array[1][0].length) array[1][0].push(rRMin);
						else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(rRMax);
						else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				}
				else {
					if (gotIndex > array[1][0].length) array[1][0].push(lRMin);
						else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + lRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(lRMax);
						else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + lRMax;
				}

				lmin = 0;
				lmax = 0;

				rmin = 0;
				rmax = 0;
			}

			index++;
			rows++;
			if(gotIndex > steps) break;
		}

		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}

	function changeNoteSustain(value:Float):Void
	{
		if (curSelectedNote != null)
		{
			if (curSelectedNote[2] != null)
			{
				curSelectedNote[2] += Math.ceil(value);
				curSelectedNote[2] = Math.max(curSelectedNote[2], 0);
			}
		}

		updateNoteUI();
		updateGrid();
	}

	function recalculateSteps(add:Float = 0):Int
	{
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (FlxG.sound.music.time > Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		curStep = lastChange.stepTime + Math.floor((FlxG.sound.music.time - lastChange.songTime + add) / Conductor.stepCrochet);
		updateBeat();

		return curStep;
	}

	function resetSection(songBeginning:Bool = false):Void
	{
		updateGrid();

		FlxG.sound.music.pause();
		// Basically old shit from changeSection???
		FlxG.sound.music.time = sectionStartTime();

		if (songBeginning)
		{
			FlxG.sound.music.time = 0;
			curSec = 0;
		}

		if(vocals != null) {
			vocals.pause();
			vocals.time = FlxG.sound.music.time;
		}
		updateCurStep();

		updateGrid();
		updateSectionUI();
		updateWaveform();
	}

	function changeSection(sec:Int = 0, ?updateMusic:Bool = true):Void
	{
		var waveformChanged:Bool = false;
		if (_song.notes[sec] != null)
		{
			curSec = sec;
			if (updateMusic)
			{
				FlxG.sound.music.pause();

				FlxG.sound.music.time = sectionStartTime();
				if(vocals != null) {
					vocals.pause();
					vocals.time = FlxG.sound.music.time;
				}
				updateCurStep();
			}

			var blah1:Float = getSectionBeats();
			var blah2:Float = getSectionBeats(curSec + 1);
			if(sectionStartTime(1) > FlxG.sound.music.length) blah2 = 0;
	
			if(blah1 != lastSecBeats || blah2 != lastSecBeatsNext)
			{
				reloadGridLayer();
				waveformChanged = true;
			}
			else
			{
				updateGrid();
			}
			updateSectionUI();
		}
		else
		{
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		if(!waveformChanged) updateWaveform();
	}

	function updateSectionUI():Void
	{
		var sec = _song.notes[curSec];

		stepperBeats.value = getSectionBeats();
		check_mustHitSection.checked = sec.mustHitSection;
		check_gfSection.checked = sec.gfSection;
		check_altAnim.checked = sec.altAnim;
		check_changeBPM.checked = sec.changeBPM;
		stepperSectionBPM.value = sec.bpm;

		updateHeads();
	}

	function updateHeads():Void
	{
		var healthIconP1:String = loadHealthIconFromCharacter(_song.player1);
		var healthIconP2:String = loadHealthIconFromCharacter(_song.player2);

		if (_song.notes[curSec].mustHitSection)
		{
			leftIcon.changeIcon(healthIconP1);
			rightIcon.changeIcon(healthIconP2);
			leftNameTxt.text = _song.player1;
			rightNameTxt.text = _song.player2;
			if (_song.notes[curSec].gfSection)
			{
				leftIcon.changeIcon('gf');
				leftNameTxt.text = 'GF (' + _song.gfVersion + ')';
			}
		}
		else
		{
			leftIcon.changeIcon(healthIconP2);
			rightIcon.changeIcon(healthIconP1);
			leftNameTxt.text = _song.player2;
			rightNameTxt.text = _song.player1;
			if (_song.notes[curSec].gfSection)
			{
				leftIcon.changeIcon('gf');
				leftNameTxt.text = 'GF (' + _song.gfVersion + ')';
			}
		}
	}

	function loadHealthIconFromCharacter(char:String) {
		var characterPath:String = 'characters/' + char + '.json';
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(characterPath);
		if (!FileSystem.exists(path)) {
			path = Paths.getPreloadPath(characterPath);
		}

		if (!FileSystem.exists(path))
		#else
		var path:String = Paths.getPreloadPath(characterPath);
		if (!OpenFlAssets.exists(path))
		#end
		{
			path = Paths.getPreloadPath('characters/' + Character.DEFAULT_CHARACTER + '.json'); //If a character couldn't be found, change him to BF just to prevent a crash
		}

		#if MODS_ALLOWED
		var rawJson = File.getContent(path);
		#else
		var rawJson = OpenFlAssets.getText(path);
		#end

		var json:CharacterFile = cast Json.parse(rawJson);
		return json.healthicon;
	}

	function updateNoteUI():Void
	{
		if (curSelectedNote != null) {
			if(curSelectedNote[2] != null) {
				stepperSusLength.setValue(curSelectedNote[2]);
				if(curSelectedNote[3] != null) {
					currentType = curNoteTypes.indexOf(curSelectedNote[3]);
					if(currentType <= 0) {
						noteTypeDropDown.selectIndex(0);
					} else {
						noteTypeDropDown.selectIndex(currentType);
					}
				}
			} else {
				eventDropDown.selectIndex(eventStuff.length > 0 ? 0 : 0);
				var evtName:String = curSelectedNote[1][curEventSelected][0];
				for (i in 0...eventStuff.length)
				{
					if (eventStuff[i][0] == evtName) { eventDropDown.selectIndex(i); break; }
				}
				var selected:Int = eventDropDown.selectedIndex;
				if(selected > 0 && selected < eventStuff.length) {
					descText.text = eventStuff[selected][1];
				}
				value1InputText.setText('' + curSelectedNote[1][curEventSelected][1]);
				value2InputText.setText('' + curSelectedNote[1][curEventSelected][2]);
			}
			strumTimeInputText.setText('' + curSelectedNote[0]);
		}
	}

	function updateGrid():Void
	{
		curRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		curRenderedNotes.clear();
		curRenderedSustains.forEachAlive(function(spr:FlxSprite) spr.destroy());
		curRenderedSustains.clear();
		curRenderedNoteType.forEachAlive(function(spr:FlxText) spr.destroy());
		curRenderedNoteType.clear();
		nextRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		nextRenderedNotes.clear();
		nextRenderedSustains.forEachAlive(function(spr:FlxSprite) spr.destroy());
		nextRenderedSustains.clear();

		if (_song.notes[curSec].changeBPM && _song.notes[curSec].bpm > 0)
		{
			Conductor.bpm = _song.notes[curSec].bpm;
			//trace('BPM of this section:');
		}
		else
		{
			// get last bpm
			var daBPM:Float = _song.bpm;
			for (i in 0...curSec)
				if (_song.notes[i].changeBPM)
					daBPM = _song.notes[i].bpm;
			Conductor.bpm = daBPM;
		}

		// CURRENT SECTION
		var beats:Float = getSectionBeats();
		for (i in _song.notes[curSec].sectionNotes)
		{
			var note:Note = setupNoteData(i, false);
			curRenderedNotes.add(note);
			if (note.sustainLength > 0)
			{
				curRenderedSustains.add(setupSusNote(note, beats));
			}

			if(i[3] != null && note.noteType != null && note.noteType.length > 0) {
				var typeInt:Int = curNoteTypes.indexOf(i[3]);
				var theType:String = '' + typeInt;
				if(typeInt < 0) theType = '?';

				var daText:AttachedFlxText = new AttachedFlxText(0, 0, 100, theType, 24);
				daText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
				daText.xAdd = -32;
				daText.yAdd = 6;
				daText.borderSize = 1;
				curRenderedNoteType.add(daText);
				daText.sprTracker = note;
			}
			note.mustPress = _song.notes[curSec].mustHitSection;
			if(i[1] > 3) note.mustPress = !note.mustPress;
		}

		// CURRENT EVENTS
		var startThing:Float = sectionStartTime();
		var endThing:Float = sectionStartTime(1);
		for (i in _song.events)
		{
			if(endThing > i[0] && i[0] >= startThing)
			{
				var note:Note = setupNoteData(i, false);
				curRenderedNotes.add(note);

				var text:String = 'Event: ' + note.eventName + ' (' + Math.floor(note.strumTime) + ' ms)' + '\nValue 1: ' + note.eventVal1 + '\nValue 2: ' + note.eventVal2;
				if(note.eventLength > 1) text = note.eventLength + ' Events:\n' + note.eventName;

				var daText:AttachedFlxText = new AttachedFlxText(0, 0, 400, text, 12);
				daText.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
				daText.xAdd = -410;
				daText.borderSize = 1;
				if(note.eventLength > 1) daText.yAdd += 8;
				curRenderedNoteType.add(daText);
				daText.sprTracker = note;
				//trace('test: ' + i[0], 'startThing: ' + startThing, 'endThing: ' + endThing);
			}
		}

		// NEXT SECTION
		var beats:Float = getSectionBeats(1);
		if(curSec < _song.notes.length-1) {
			for (i in _song.notes[curSec+1].sectionNotes)
			{
				var note:Note = setupNoteData(i, true);
				note.alpha = 0.6;
				nextRenderedNotes.add(note);
				if (note.sustainLength > 0)
				{
					nextRenderedSustains.add(setupSusNote(note, beats));
				}
			}
		}

		// NEXT EVENTS
		var startThing:Float = sectionStartTime(1);
		var endThing:Float = sectionStartTime(2);
		for (i in _song.events)
		{
			if(endThing > i[0] && i[0] >= startThing)
			{
				var note:Note = setupNoteData(i, true);
				note.alpha = 0.6;
				nextRenderedNotes.add(note);
			}
		}
	}

	function setupNoteData(i:Array<Dynamic>, isNextSection:Bool):Note
	{
		var daNoteInfo = i[1];
		var daStrumTime = i[0];
		var daSus:Dynamic = i[2];

		var note:Note = new Note(daStrumTime, daNoteInfo % 4, null, null, true);
		if(daSus != null) { //Common note
			if(!Std.isOfType(i[3], String)) //Convert old note type to new note type format
			{
				i[3] = curNoteTypes[i[3]];
			}
			if(i.length > 3 && (i[3] == null || i[3].length < 1))
			{
				i.remove(i[3]);
			}
			note.sustainLength = daSus;
			note.noteType = i[3];
		} else { //Event note
			note.loadGraphic(Paths.image('eventArrow'));
			note.rgbShader.enabled = false;
			note.eventName = getEventName(i[1]);
			note.eventLength = i[1].length;
			if(i[1].length < 2)
			{
				note.eventVal1 = i[1][0][1];
				note.eventVal2 = i[1][0][2];
			}
			note.noteData = -1;
			daNoteInfo = -1;
		}

		note.setGraphicSize(GRID_SIZE, GRID_SIZE);
		note.updateHitbox();
		note.x = Math.floor(daNoteInfo * GRID_SIZE) + GRID_SIZE;
		if(isNextSection && _song.notes[curSec].mustHitSection != _song.notes[curSec+1].mustHitSection) {
			if(daNoteInfo > 3) {
				note.x -= GRID_SIZE * 4;
			} else if(daSus != null) {
				note.x += GRID_SIZE * 4;
			}
		}

		var beats:Float = getSectionBeats(isNextSection ? 1 : 0);
		note.y = getYfromStrumNotes(daStrumTime - sectionStartTime(), beats);
		//if(isNextSection) note.y += gridBG.height;
		if(note.y < -150) note.y = -150;
		return note;
	}

	function getEventName(names:Array<Dynamic>):String
	{
		var retStr:String = '';
		var addedOne:Bool = false;
		for (i in 0...names.length)
		{
			if(addedOne) retStr += ', ';
			retStr += names[i][0];
			addedOne = true;
		}
		return retStr;
	}

	function setupSusNote(note:Note, beats:Float):FlxSprite {
		var height:Int = Math.floor(FlxMath.remapToRange(note.sustainLength, 0, Conductor.stepCrochet * 16, 0, GRID_SIZE * 16 * zoomList[curZoom]) + (GRID_SIZE * zoomList[curZoom]) - GRID_SIZE / 2);
		var minHeight:Int = Std.int((GRID_SIZE * zoomList[curZoom] / 2) + GRID_SIZE / 2);
		if(height < minHeight) height = minHeight;
		if(height < 1) height = 1; //Prevents error of invalid height

		var spr:FlxSprite = new FlxSprite(note.x + (GRID_SIZE * 0.5) - 4, note.y + GRID_SIZE / 2).makeGraphic(8, height);
		return spr;
	}

	private function addSection(sectionBeats:Float = 4):Void
	{
		var sec:SwagSection = {
			sectionBeats: sectionBeats,
			bpm: _song.bpm,
			changeBPM: false,
			mustHitSection: true,
			gfSection: false,
			sectionNotes: [],
			typeOfSection: 0,
			altAnim: false
		};

		_song.notes.push(sec);
	}

	function selectNote(note:Note):Void
	{
		var noteDataToCheck:Int = note.noteData;

		if(noteDataToCheck > -1)
		{
			if(note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;
			for (i in _song.notes[curSec].sectionNotes)
			{
				if (i != curSelectedNote && i.length > 2 && i[0] == note.strumTime && i[1] == noteDataToCheck)
				{
					curSelectedNote = i;
					break;
				}
			}
		}
		else
		{
			for (i in _song.events)
			{
				if(i != curSelectedNote && i[0] == note.strumTime)
				{
					curSelectedNote = i;
					curEventSelected = Std.int(curSelectedNote[1].length) - 1;
					break;
				}
			}
		}
		changeEventSelected();

		updateGrid();
		updateNoteUI();
	}

	function deleteNote(note:Note):Void
	{
		var noteDataToCheck:Int = note.noteData;
		if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;

		if(note.noteData > -1) //Normal Notes
		{
			for (i in _song.notes[curSec].sectionNotes)
			{
				if (i[0] == note.strumTime && i[1] == noteDataToCheck)
				{
					if(i == curSelectedNote) curSelectedNote = null;
					//FlxG.log.add('FOUND EVIL NOTE');
					_song.notes[curSec].sectionNotes.remove(i);
					break;
				}
			}
		}
		else //Events
		{
			for (i in _song.events)
			{
				if(i[0] == note.strumTime)
				{
					if(i == curSelectedNote)
					{
						curSelectedNote = null;
						changeEventSelected();
					}
					//FlxG.log.add('FOUND EVIL EVENT');
					_song.events.remove(i);
					break;
				}
			}
		}

		updateGrid();
	}

	public function doANoteThing(cs, d, style){
		var delnote = false;
		if(strumLineNotes.members[d].overlaps(curRenderedNotes))
		{
			curRenderedNotes.forEachAlive(function(note:Note)
			{
				if (note.overlapsPoint(new FlxPoint(strumLineNotes.members[d].x + 1,strumLine.y+1)) && note.noteData == d%4)
				{
						//trace('tryin to delete note...');
						if(!delnote) deleteNote(note);
						delnote = true;
				}
			});
		}

		if (!delnote){
			addNote(cs, d, style);
		}
	}
	function clearSong():Void
	{
		for (daSection in 0..._song.notes.length)
		{
			_song.notes[daSection].sectionNotes = [];
		}

		updateGrid();
	}

	private function addNote(strum:Null<Float> = null, data:Null<Int> = null, type:Null<Int> = null):Void
	{
		//curUndoIndex++;
		//var newsong = _song.notes;
		//	undos.push(newsong);
		var noteStrum = getStrumTime(dummyArrow.y * (getSectionBeats() / 4), false) + sectionStartTime();
		var noteData = Math.floor((FlxG.mouse.x - GRID_SIZE) / GRID_SIZE);
		var noteSus = 0;
		var daAlt = false;
		var daType = currentType;

		if (strum != null) noteStrum = strum;
		if (data != null) noteData = data;
		if (type != null) daType = type;

		if(noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, noteData, noteSus, curNoteTypes[daType]]);
			curSelectedNote = _song.notes[curSec].sectionNotes[_song.notes[curSec].sectionNotes.length - 1];
		}
		else
		{
			var event = eventStuff[eventDropDown.selectedIndex][0];
			var text1 = value1InputText.field.text;
			var text2 = value2InputText.field.text;
			_song.events.push([noteStrum, [[event, text1, text2]]]);
			curSelectedNote = _song.events[_song.events.length - 1];
			curEventSelected = 0;
		}
		changeEventSelected();

		if (FlxG.keys.pressed.CONTROL && noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, (noteData + 4) % 8, noteSus, curNoteTypes[daType]]);
		}

		//trace(noteData + ', ' + noteStrum + ', ' + curSec);
		strumTimeInputText.field.text = '' + curSelectedNote[0];

		updateGrid();
		updateNoteUI();
	}

	// will figure this out l8r
	function redo()
	{
		//_song = redos[curRedoIndex];
	}

	function undo()
	{
		//redos.push(_song);
		undos.pop();
		//_song.notes = undos[undos.length - 1];
		///trace(_song.notes);
		//updateGrid();
	}

	function getStrumTime(yPos:Float, doZoomCalc:Bool = true):Float
	{
		var leZoom:Float = zoomList[curZoom];
		if(!doZoomCalc) leZoom = 1;
		return FlxMath.remapToRange(yPos, gridBG.y, gridBG.y + gridBG.height * leZoom, 0, 16 * Conductor.stepCrochet);
	}

	function getYfromStrum(strumTime:Float, doZoomCalc:Bool = true):Float
	{
		var leZoom:Float = zoomList[curZoom];
		if(!doZoomCalc) leZoom = 1;
		return FlxMath.remapToRange(strumTime, 0, 16 * Conductor.stepCrochet, gridBG.y, gridBG.y + gridBG.height * leZoom);
	}
	
	function getYfromStrumNotes(strumTime:Float, beats:Float):Float
	{
		var value:Float = strumTime / (beats * 4 * Conductor.stepCrochet);
		return GRID_SIZE * beats * 4 * zoomList[curZoom] * value + gridBG.y;
	}

	function getNotes():Array<Dynamic>
	{
		var noteData:Array<Dynamic> = [];

		for (i in _song.notes)
		{
			noteData.push(i.sectionNotes);
		}

		return noteData;
	}

	var missingText:FlxText;
	var missingTextTimer:FlxTimer;
	function loadJson(song:String):Void
	{
		//shitty null fix, i fucking hate it when this happens
		//make it look sexier if possible
		try {
			if (Difficulty.getString() != Difficulty.getDefault()) {
				if(Difficulty.getString() == null){
					PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
				}else{
					PlayState.SONG = Song.loadFromJson(song.toLowerCase() + "-" + Difficulty.getString(), song.toLowerCase());
				}
			}
			else PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
			MusicBeatState.resetState();
		}
		catch(e)
		{
			trace('ERROR! $e');

			var errorStr:String = e.toString();
			if(errorStr.startsWith('[file_contents,assets/data/')) errorStr = 'Missing file: ' + errorStr.substring(27, errorStr.length-1); //Missing chart
			
			if(missingText == null)
			{
				missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
				missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				missingText.scrollFactor.set();
				add(missingText);
			}
			else missingTextTimer.cancel();

			missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
			missingText.screenCenter(Y);

			missingTextTimer = new FlxTimer().start(5, function(tmr:FlxTimer) {
				remove(missingText);
				missingText.destroy();
			});
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	function autosaveSong():Void
	{
		FlxG.save.data.autosave = haxe.Json.stringify({
			"song": _song
		});
		FlxG.save.flush();
	}

	function clearEvents() {
		_song.events = [];
		updateGrid();
	}

	private function saveLevel()
	{
		if(_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var json = {
			"song": _song
		};

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), Paths.formatToSongPath(_song.song) + ".json");
		}
	}

	function sortByTime(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	private function saveEvents()
	{
		if(_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var eventsSong:Dynamic = {
			events: _song.events
		};
		var json = {
			"song": eventsSong
		}

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), "events.json");
		}
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved LEVEL DATA.");
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving Level data");
	}

	function getSectionBeats(?section:Null<Int> = null)
	{
		if (section == null) section = curSec;
		var val:Null<Float> = null;
		
		if(_song.notes[section] != null) val = _song.notes[section].sectionBeats;
		return val != null ? val : 4;
	}

	// ===================== 现代 UI 辅助 =====================
	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, ?color:Int = 0xFFD7D7E0, ?align:FlxTextAlign = LEFT, ?font:String = 'future.ttf'):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font(font), size, color, align, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		t.antialiasing = ClientPrefs.data.antialiasing;
		return t;
	}

	function redrawBox(spr:FlxSprite, w:Int, h:Int, radius:Float, fill:Int, border:Int):Void
	{
		spr.pixels.fillRect(spr.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != 0)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.dirty = true;
	}

	function buildTabs():Void
	{
		var tabLabels:Array<String> = ['歌曲', '小节', '音符', '事件', '编曲', '数据'];
		for (i in 0...tabLabels.length)
		{
			var btnBg:FlxSprite = new FlxSprite(PANEL_X + 12 + i * 76, PANEL_Y + 52).makeGraphic(74, 30, FlxColor.TRANSPARENT);
			btnBg.antialiasing = ClientPrefs.data.antialiasing;
			btnBg.scrollFactor.set();
			redrawBox(btnBg, 74, 30, 10, 0x1CFFFFFF, 0x45FFFFFF);
			add(btnBg);
			var btnTxt:FlxText = makeText(PANEL_X + 12 + i * 76, PANEL_Y + 58, 74, tabLabels[i], 13, 0xFFB8B8C8, CENTER);
			add(btnTxt);
			tabBtns.push({bg: btnBg, txt: btnTxt});
		}
		for (i in 0...tabLabels.length)
		{
			var grp:FlxSpriteGroup = new FlxSpriteGroup();
			grp.visible = false;
			grp.active = false;
			add(grp);
			tabGroups.push(grp);
		}
	}

	function changeTab(t:Int):Void
	{
		if (t < 0 || t >= tabGroups.length) return;
		curTab = t;
		for (i in 0...tabGroups.length)
		{
			tabGroups[i].visible = (i == t);
			tabGroups[i].active = (i == t);
		}
		blurAllInputs();
		for (d in allDropdowns) if (d.open) d.close();
		refreshTabButtons();
	}

	function refreshTabButtons():Void
	{
		for (i in 0...tabBtns.length)
		{
			var active:Bool = (i == curTab);
			redrawBox(tabBtns[i].bg, 74, 30, 10, active ? 0x38FFFFFF : 0x1CFFFFFF, active ? 0x8CFFFFFF : 0x45FFFFFF);
			tabBtns[i].txt.color = active ? 0xFFFFFFFF : 0xFFB8B8C8;
		}
	}

	function showToast(msg:String):Void
	{
		toastText.text = msg;
		toastText.visible = true;
		toastText.alpha = 1;
		if (toastTimer != null) toastTimer.cancel();
		toastTimer = new FlxTimer().start(2.2, function(_)
		{
			FlxTween.tween(toastText, {alpha: 0}, 0.4, {onComplete: function(_) toastText.visible = false});
		});
	}

	function blurAllInputs():Void
	{
		for (i in allInputs) i.field.hasFocus = false;
	}

	function updateWidgets(mx:Float, my:Float):Void
	{
		var clicked:Bool = FlxG.mouse.justPressed;

		for (b in allButtons)
		{
			b.setHovered(b.over(mx, my));
			if (clicked && b.over(mx, my) && b.onClick != null)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
				b.onClick();
			}
		}
		for (t in allToggles)
		{
			t.setHovered(t.over(mx, my));
			if (clicked && t.over(mx, my)) t.toggle();
		}
		for (s in allSteppers)
		{
			s.setHovered(s.overMinus(mx, my), s.overPlus(mx, my));
			if (clicked)
			{
				if (s.overMinus(mx, my)) s.stepBy(-1, FlxG.keys.pressed.SHIFT);
				else if (s.overPlus(mx, my)) s.stepBy(1, FlxG.keys.pressed.SHIFT);
			}
		}
		for (d in allDropdowns)
		{
			d.setHovered(d.over(mx, my));
			if (clicked && d.over(mx, my))
			{
				for (other in allDropdowns) if (other != d && other.open) other.close();
				d.toggle();
			}
		}
	}
}

class EditorButton extends FlxSpriteGroup
{
	public var onClick:Void->Void;
	public var enabled:Bool = true;
	public var hovered:Bool = false;
	public var bg:FlxSprite;
	public var label:FlxText;
	var accent:Bool;
	var w:Float;
	var h:Float;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, ?onClick:Void->Void, ?size:Int = 14, ?accent:Bool = false)
	{
		super(x, y);
		this.onClick = onClick;
		this.accent = accent;
		this.w = w;
		this.h = h;

		bg = new FlxSprite(0, 0).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		redraw();
		add(bg);

		label = new FlxText(0, 0, Std.int(w), text, size);
		label.setFormat(Paths.font('future.ttf'), size, accent ? 0xFFFFFFFF : 0xFFD7D7E0, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.2;
		label.scrollFactor.set();
		label.antialiasing = ClientPrefs.data.antialiasing;
		label.y = (h - label.height) / 2;
		add(label);
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + w && my >= y && my <= y + h;
	}

	public function setHovered(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		redraw();
	}

	function redraw():Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		var fill:Int = hovered ? 0x36FFFFFF : (accent ? 0x2EFFFFFF : 0x1CFFFFFF);
		var border:Int = hovered ? 0x8CFFFFFF : (accent ? 0x66FFFFFF : 0x45FFFFFF);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, w, h, 10, 10, fill, {color: border, thickness: 1.5});
		bg.dirty = true;
	}
}

class EditorToggle extends FlxSpriteGroup
{
	public var checked:Bool;
	public var onChange:Void->Void;
	public var label:FlxText;
	var box:FlxSprite;
	var checkTxt:FlxText;
	var hovered:Bool = false;
	var hitW:Float = 220;

	public function new(x:Float, y:Float, text:String, initial:Bool, ?onChange:Void->Void, ?labelW:Float = 200)
	{
		super(x, y);
		this.onChange = onChange;
		checked = initial;

		box = new FlxSprite(0, 0).makeGraphic(22, 22, FlxColor.TRANSPARENT);
		box.antialiasing = ClientPrefs.data.antialiasing;
		box.scrollFactor.set();
		add(box);

		checkTxt = new FlxText(1, -1, 22, '✓', 15);
		checkTxt.setFormat(Paths.font('future.ttf'), 15, 0xFFFFFFFF, CENTER);
		checkTxt.scrollFactor.set();
		checkTxt.visible = checked;
		add(checkTxt);

		label = new FlxText(30, 2, Std.int(labelW), text, 14);
		label.setFormat(Paths.font('future.ttf'), 14, 0xFFD7D7E0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.2;
		label.scrollFactor.set();
		label.antialiasing = ClientPrefs.data.antialiasing;
		add(label);

		hitW = 30 + label.width;
		redraw();
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x - 4 && mx <= x + hitW && my >= y - 4 && my <= y + 30;
	}

	public function setHovered(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		redraw();
	}

	public function toggle():Void
	{
		checked = !checked;
		checkTxt.visible = checked;
		redraw();
		if (onChange != null) onChange();
	}

	public function setChecked(v:Bool, fire:Bool = true):Void
	{
		if (checked == v) return;
		checked = v;
		checkTxt.visible = checked;
		redraw();
		if (fire && onChange != null) onChange();
	}

	function redraw():Void
	{
		box.pixels.fillRect(box.pixels.rect, FlxColor.TRANSPARENT);
		var fill:Int = checked ? 0x406B7CFF : (hovered ? 0x26FFFFFF : 0x12FFFFFF);
		var border:Int = checked ? 0x8C9BB5FF : 0x45FFFFFF;
		FlxSpriteUtil.drawRoundRect(box, 0, 0, 22, 22, 6, 6, fill, {color: border, thickness: 1.5});
		box.dirty = true;
	}
}

class EditorInput extends FlxSpriteGroup
{
	public var field:FlxInputText;
	public var bg:FlxSprite;
	public var labelTxt:FlxText;
	public var userOnChange:String->Void;
	var h:Float = 30;

	public function new(x:Float, y:Float, w:Float, label:String, value:String, ?userOnChange:String->Void, ?numeric:Bool = false)
	{
		super(x, y);
		this.userOnChange = userOnChange;

		labelTxt = new FlxText(0, -20, Std.int(w), label, 12);
		labelTxt.setFormat(Paths.font('future.ttf'), 12, 0xFF8A8FA8, LEFT);
		labelTxt.scrollFactor.set();
		add(labelTxt);

		bg = new FlxSprite(0, 0).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		redraw(false);
		add(bg);

		field = new FlxInputText(8, 5, Std.int(w) - 16, value, 14, 0xFFE8E8F0, FlxColor.TRANSPARENT);
		field.setFormat(Paths.font('future.ttf'), 14, 0xFFE8E8F0, LEFT);
		field.scrollFactor.set();
		field.antialiasing = ClientPrefs.data.antialiasing;
		if (numeric) field.customFilterPattern = ~/[^0-9.\-]/g;
		field.callback = function(text:String, action:String)
		{
			if (action == FlxInputText.ENTER_ACTION) field.hasFocus = false;
			if (userOnChange != null) userOnChange(text);
		};
		field.focusGained = function() redraw(true);
		field.focusLost = function() redraw(false);
		add(field);
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + bg.width && my >= y && my <= y + h;
	}

	public function setText(v:String):Void
	{
		if (field.text != v) field.text = v;
	}

	function redraw(focused:Bool):Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, bg.width, h, 8, 8, focused ? 0x1EFFFFFF : 0x10FFFFFF, {color: focused ? 0x66FFFFFF : 0x30FFFFFF, thickness: 1.5});
		bg.dirty = true;
	}
}

class EditorStepper extends FlxSpriteGroup
{
	public var value:Float;
	public var min:Float;
	public var max:Float;
	public var step:Float;
	public var onChange:Float->Void;
	public var labelTxt:FlxText;
	var minusBtn:FlxSprite;
	var plusBtn:FlxSprite;
	var minusTxt:FlxText;
	var plusTxt:FlxText;
	var valueTxt:FlxText;
	var decimals:Int;
	var hoverMinus:Bool = false;
	var hoverPlus:Bool = false;
	var w:Float;
	var h:Float = 30;

	public function new(x:Float, y:Float, w:Float, label:String, value:Float, min:Float, max:Float, step:Float, ?decimals:Int = 2, ?onChange:Float->Void)
	{
		super(x, y);
		this.value = value;
		this.min = min;
		this.max = max;
		this.step = step;
		this.onChange = onChange;
		this.decimals = decimals;
		this.w = w;

		labelTxt = new FlxText(0, -20, Std.int(w), label, 12);
		labelTxt.setFormat(Paths.font('future.ttf'), 12, 0xFF8A8FA8, LEFT);
		labelTxt.scrollFactor.set();
		add(labelTxt);

		minusBtn = new FlxSprite(0, 0).makeGraphic(30, Std.int(h), FlxColor.TRANSPARENT);
		minusBtn.antialiasing = ClientPrefs.data.antialiasing;
		minusBtn.scrollFactor.set();
		add(minusBtn);

		plusBtn = new FlxSprite(w - 30, 0).makeGraphic(30, Std.int(h), FlxColor.TRANSPARENT);
		plusBtn.antialiasing = ClientPrefs.data.antialiasing;
		plusBtn.scrollFactor.set();
		add(plusBtn);

		minusTxt = new FlxText(0, 4, 30, '-', 16);
		minusTxt.setFormat(Paths.font('future.ttf'), 16, 0xFFD7D7E0, CENTER);
		minusTxt.scrollFactor.set();
		add(minusTxt);

		plusTxt = new FlxText(w - 30, 4, 30, '+', 16);
		plusTxt.setFormat(Paths.font('future.ttf'), 16, 0xFFD7D7E0, CENTER);
		plusTxt.scrollFactor.set();
		add(plusTxt);

		valueTxt = new FlxText(30, 6, Std.int(w - 60), '', 13);
		valueTxt.setFormat(Paths.font('future.ttf'), 13, 0xFFE8E8F0, CENTER);
		valueTxt.scrollFactor.set();
		add(valueTxt);

		redraw();
		updateValueText();
	}

	public function overMinus(mx:Float, my:Float):Bool { return mx >= x && mx <= x + 30 && my >= y && my <= y + h; }
	public function overPlus(mx:Float, my:Float):Bool { return mx >= x + w - 30 && mx <= x + w && my >= y && my <= y + h; }

	public function setHovered(vMinus:Bool, vPlus:Bool):Void
	{
		if (hoverMinus == vMinus && hoverPlus == vPlus) return;
		hoverMinus = vMinus;
		hoverPlus = vPlus;
		redraw();
	}

	public function stepBy(sign:Int, big:Bool):Void
	{
		var s:Float = step * (big ? 10 : 1);
		value = FlxMath.bound(value + sign * s, min, max);
		updateValueText();
		if (onChange != null) onChange(value);
	}

	public function setValue(v:Float):Void
	{
		value = FlxMath.bound(v, min, max);
		updateValueText();
	}

	function updateValueText():Void
	{
		valueTxt.text = Std.string(FlxMath.roundDecimal(value, decimals));
	}

	function redraw():Void
	{
		for (pair in [{spr: minusBtn, hover: hoverMinus}, {spr: plusBtn, hover: hoverPlus}])
		{
			pair.spr.pixels.fillRect(pair.spr.pixels.rect, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(pair.spr, 0, 0, pair.spr.width, pair.spr.height, 8, 8, pair.hover ? 0x30FFFFFF : 0x14FFFFFF, {color: pair.hover ? 0x66FFFFFF : 0x38FFFFFF, thickness: 1.5});
			pair.spr.dirty = true;
		}
	}
}

class EditorDropdown extends FlxSpriteGroup
{
	public var options:Array<String>;
	public var selectedIndex:Int = 0;
	public var onChange:Int->Void;
	public var open:Bool = false;
	public var labelTxt:FlxText;
	var bg:FlxSprite;
	var valueTxt:FlxText;
	var arrowTxt:FlxText;
	var hovered:Bool = false;
	var w:Float;
	var h:Float = 30;
	var layer:FlxSpriteGroup;
	var panelBg:FlxSprite;
	var panelItems:Array<{bg:FlxSprite, txt:FlxText}> = [];
	var scroll:Int = 0;
	var hoveredItem:Int = -1;
	var lastHoveredItem:Int = -999;
	var lastSelectedForHover:Int = -999;
	var visibleRows:Int = 6;
	var rowH:Int = 30;

	public function new(x:Float, y:Float, w:Float, label:String, options:Array<String>, selectedIndex:Int, ?onChange:Int->Void, layer:FlxSpriteGroup)
	{
		super(x, y);
		this.options = options;
		this.selectedIndex = selectedIndex;
		this.onChange = onChange;
		this.layer = layer;
		this.w = w;

		labelTxt = new FlxText(0, -20, Std.int(w), label, 12);
		labelTxt.setFormat(Paths.font('future.ttf'), 12, 0xFF8A8FA8, LEFT);
		labelTxt.scrollFactor.set();
		add(labelTxt);

		bg = new FlxSprite(0, 0).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		add(bg);

		valueTxt = new FlxText(10, 6, Std.int(w - 42), '', 13);
		valueTxt.setFormat(Paths.font('future.ttf'), 13, 0xFFE8E8F0, LEFT);
		valueTxt.scrollFactor.set();
		add(valueTxt);

		arrowTxt = new FlxText(w - 26, 3, 20, '▾', 14);
		arrowTxt.setFormat(Paths.font('future.ttf'), 14, 0xFFB8B8C8, CENTER);
		arrowTxt.scrollFactor.set();
		add(arrowTxt);

		redraw();
		refreshLabel();
	}

	public function over(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + w && my >= y && my <= y + h;
	}

	public function setHovered(v:Bool):Void
	{
		if (hovered == v) return;
		hovered = v;
		redraw();
	}

	public function selectIndex(i:Int):Void
	{
		selectedIndex = i;
		refreshLabel();
	}

	public function refreshLabel():Void
	{
		if (selectedIndex >= 0 && selectedIndex < options.length) valueTxt.text = options[selectedIndex];
		else valueTxt.text = '';
	}

	public function toggle():Void
	{
		if (open) close();
		else openPanel();
	}

	function openPanel():Void
	{
		open = true;
		scroll = 0;
		hoveredItem = -1;
		redraw();
		panelBg = new FlxSprite(x, y + h).makeGraphic(Std.int(w), visibleRows * rowH + 8, 0xEE161622);
		panelBg.antialiasing = true;
		panelBg.scrollFactor.set();
		FlxSpriteUtil.drawRoundRect(panelBg, 0, 0, w, visibleRows * rowH + 8, 10, 10, 0xEE161622, {color: 0x55FFFFFF, thickness: 1.5});
		layer.add(panelBg);
		rebuildItems();
	}

	public function close():Void
	{
		open = false;
		redraw();
		if (panelBg != null)
		{
			layer.remove(panelBg);
			panelBg.destroy();
			panelBg = null;
		}
		for (it in panelItems)
		{
			layer.remove(it.bg);
			layer.remove(it.txt);
			it.bg.destroy();
			it.txt.destroy();
		}
		panelItems = [];
	}

	public function updateOpen():Void
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;

		if (FlxG.mouse.wheel != 0)
		{
			scroll -= FlxG.mouse.wheel;
			scroll = Std.int(FlxMath.bound(scroll, 0, Math.max(0, options.length - visibleRows)));
			rebuildItems();
		}

		hoveredItem = -1;
		for (i in 0...panelItems.length)
		{
			var it = panelItems[i];
			if (mx >= it.bg.x && mx <= it.bg.x + it.bg.width && my >= it.bg.y && my <= it.bg.y + it.bg.height) hoveredItem = scroll + i;
		}
		rebuildHover();

		if (FlxG.mouse.justPressed)
		{
			if (over(mx, my))
			{
				close();
				return;
			}
			if (hoveredItem >= 0 && hoveredItem < options.length)
			{
				selectedIndex = hoveredItem;
				refreshLabel();
				var cb:Int->Void = onChange;
				close();
				if (cb != null) cb(selectedIndex);
			}
			else if (panelBg != null && !(mx >= panelBg.x && mx <= panelBg.x + panelBg.width && my >= panelBg.y && my <= panelBg.y + panelBg.height))
			{
				close();
			}
		}
	}

	function rebuildItems():Void
	{
		for (it in panelItems)
		{
			layer.remove(it.bg);
			layer.remove(it.txt);
			it.bg.destroy();
			it.txt.destroy();
		}
		panelItems = [];

		if (panelBg == null) return;
		for (i in 0...visibleRows)
		{
			var idx:Int = scroll + i;
			if (idx >= options.length) break;
			var y:Float = panelBg.y + 4 + i * rowH;

			var bg:FlxSprite = new FlxSprite(panelBg.x + 4, y).makeGraphic(Std.int(w - 8), rowH - 4, 0x00FFFFFF);
			bg.antialiasing = true;
			bg.scrollFactor.set();
			layer.add(bg);

			var txt:FlxText = new FlxText(panelBg.x + 14, y + 6, Std.int(w - 28), options[idx], 13);
			txt.setFormat(Paths.font('future.ttf'), 13, 0xFFE8E8F0, LEFT);
			txt.scrollFactor.set();
			layer.add(txt);

			panelItems.push({bg: bg, txt: txt});
		}
		lastHoveredItem = -999;
		lastSelectedForHover = -999;
		rebuildHover();
	}

	function rebuildHover():Void
	{
		if (lastHoveredItem == hoveredItem && lastSelectedForHover == selectedIndex) return;
		lastHoveredItem = hoveredItem;
		lastSelectedForHover = selectedIndex;
		for (i in 0...panelItems.length)
		{
			var idx:Int = scroll + i;
			var selected:Bool = idx == selectedIndex;
			var hover:Bool = idx == hoveredItem;
			var it = panelItems[i];
			it.bg.pixels.fillRect(it.bg.pixels.rect, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(it.bg, 0, 0, it.bg.width, it.bg.height, 6, 6, hover ? 0x30FFFFFF : (selected ? 0x1EFFFFFF : 0x00FFFFFF));
			it.bg.dirty = true;
			it.txt.color = (hover || selected) ? 0xFFFFFFFF : 0xFFE8E8F0;
		}
	}

	function redraw():Void
	{
		bg.pixels.fillRect(bg.pixels.rect, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(bg, 0, 0, w, h, 8, 8, open ? 0x1EFFFFFF : (hovered ? 0x26FFFFFF : 0x10FFFFFF), {color: open ? 0x66FFFFFF : (hovered ? 0x55FFFFFF : 0x30FFFFFF), thickness: 1.5});
		bg.dirty = true;
	}
}

class AttachedFlxText extends FlxText
{
	public var sprTracker:FlxSprite;
	public var xAdd:Float = 0;
	public var yAdd:Float = 0;

	public function new(X:Float = 0, Y:Float = 0, FieldWidth:Float = 0, ?Text:String, Size:Int = 8, EmbeddedFont:Bool = true)
	{
		super(X, Y, FieldWidth, Text, Size, EmbeddedFont);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
		{
			setPosition(sprTracker.x + xAdd, sprTracker.y + yAdd);
			angle = sprTracker.angle;
			alpha = sprTracker.alpha;
		}
	}
}
