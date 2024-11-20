package options;

#if desktop
import Discord.DiscordClient;
#end
import flash.text.TextField;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import lime.utils.Assets;
import flixel.FlxSubState;
import flash.text.TextField;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxSave;
import haxe.Json;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import flixel.input.keyboard.FlxKey;
import flixel.graphics.FlxGraphic;
import Controls;

using StringTools;

class VisualsUISubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Visuals and UI';
		rpcTitle = 'Visuals & UI Settings Menu'; //for Discord Rich Presence

		var option:Option = new Option('Note Splashes',
			"如果你不勾选，那么按下箭头时不会有打击粒子",
			'noteSplashes',
			'bool',
			false);
		addOption(option);

		var option:Option = new Option('Hide HUD',
			'如果你勾选了，那么血量条等东西将不会显示',
			'hideHud',
			'bool',
			false);
		addOption(option);

		var option:Option = new Option('Hide Watermark',
			'如果你勾选了，那么左下角水印将不会显示',
			'hideWatermark',
			'bool',
			false);
		addOption(option);
		
		var option:Option = new Option('Time Bar:',
			"你想让时间条怎么显示？",
			'timeBarType',
			'string',
			'Song Name',
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']);
		addOption(option);

		var option:Option = new Option('Flashing Lights',
			"如果你不勾选，那么不会有频闪",
			'flashing',
			'bool',
			true);
		addOption(option);

		var option:Option = new Option('Camera Zooms',
			"如果你不勾选，那么镜头就不会缩放（我不知道）",
			'camZooms',
			'bool',
			true);
		addOption(option);

		var option:Option = new Option('Score Text Zoom on Hit',
			"如果你不勾选，那么你按下箭头时血量条文字不会跳动",
			'scoreZoom',
			'bool',
			true);
		addOption(option);

		var option:Option = new Option('Health Bar Transparency',
			'你想让你的血量条透明吗？',
			'healthBarAlpha',
			'percent',
			1);
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
			'bool',
			true);
		addOption(option);
		option.onChange = onChangeFPSCounter;
		#end
		
		var option:Option = new Option('FPS Engine Version',
			'如果你不勾选，那么帧数计数器下的引擎版本将不会显示',
			'showVer',
			'bool',
			true);
		addOption(option);

		var option:Option = new Option('FPS Display Color: ',
		    "你想让你的FPS计数器显示什么颜色？",
			'fpsColor',
			'string',
			'White',
			['White', 'Cyan', 'Blue', 'Red', 'Green', 'Yellow']);
		addOption(option);
		
		var option:Option = new Option('Pause Screen Song:',
			"你想让你停下来放什么音乐？",
			'pauseMusic',
			'string',
			'Tea Time',
			['None', 'Breakfast', 'Tea Time']);
		addOption(option);
		option.onChange = onChangePauseMusic;

		var option:Option = new Option('Check for Updates',
			'勾选此选项来检查你的ME引擎是不是最新的',
			'checkForUpdates',
			'bool');
		addOption(option);

		var option:Option = new Option('Combo Stacking',
			"如果不勾选，评级和连击将不会叠加，节省系统内存并使其更易于加载铺子",
			'comboStacking',
			'bool',
			true);
		addOption(option);

		super();
	}

	var changedMusic:Bool = false;
	function onChangePauseMusic()
	{
		if(ClientPrefs.pauseMusic == 'None')
			FlxG.sound.music.volume = 0;
		else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.pauseMusic)));

		changedMusic = true;
	}

	override function destroy()
	{
		if(changedMusic) FlxG.sound.playMusic(Paths.music('freakyMenu'));
		super.destroy();
	}

	#if !mobile
	function onChangeFPSCounter()
	{
		if(Main.fpsVar != null)
			Main.fpsVar.visible = ClientPrefs.showFPS;
	}
	#end
}
