package options;

import objects.Character;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	var antialiasingOption:Int;
	var boyfriend:Character = null;
	public function new()
	{
		title = '图像设置';
		rpcTitle = '图像设置菜单'; //for Discord Rich Presence

		boyfriend = new Character(840, 170, 'bf', true);
		boyfriend.setGraphicSize(Std.int(boyfriend.width * 0.75));
		boyfriend.updateHitbox();
		boyfriend.dance();
		boyfriend.animation.finishCallback = function (name:String) boyfriend.dance();
		boyfriend.visible = false;

		//I'd suggest using "Low Quality" as an example for making your own option since it is the simplest here
		var option:Option = new Option('低画质', //Name
			'开启后，禁用部分背景细节，缩短加载时间并提升性能', //Description
			'lowQuality', //Save data variable name
			'bool'); //Variable type
		addOption(option);

		var option:Option = new Option('抗锯齿',
			'关闭后，禁用抗锯齿，画面边缘更锐利，同时提升性能',
			'antialiasing',
			'bool');
		option.onChange = onChangeAntiAliasing; //Changing onChange is only needed if you want to make a special interaction after it changes the value
		addOption(option);
		antialiasingOption = optionsArray.length-1;

		var option:Option = new Option('光影效果', //Name
			'关闭后，禁用光影特效。光影用于部分视觉效果，但对配置较弱的电脑比较吃 CPU', //Description
			'shaders',
			'bool');
		addOption(option);

		var option:Option = new Option('GPU缓存', //Name
			'开启后，使用 GPU 缓存纹理，可减少内存占用（显卡性能较差时建议关闭）', //Description
			'cacheOnGPU',
			'bool');
		addOption(option);

		var option:Option = new Option('提前渲染', //Name
			'开启后，在加载曲目时预先渲染所有音符贴图，大幅优化高密度音符堆叠场景（会牺牲加载速度）', //Description
			'preRenderNotes',
			'bool');
		addOption(option);

		#if !html5 //Apparently other framerates isn't correctly supported on Browser? Probably it has some V-Sync shit enabled by default, idk
		var option:Option = new Option('帧率',
			'调整游戏的帧率上限',
			'framerate',
			'int');
		addOption(option);

		option.minValue = 30;
		option.maxValue = 1000;
		option.displayFormat = '%v FPS';
		option.onChange = onChangeFramerate;
		#end

		super();
		insert(1, boyfriend);
	}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			var sprite:FlxSprite = cast sprite;
			if(sprite != null && (sprite is FlxSprite) && !(sprite is FlxText)) {
				sprite.antialiasing = ClientPrefs.data.antialiasing;
			}
		}
	}

	function onChangeFramerate()
	{
		if(ClientPrefs.data.framerate > FlxG.drawFramerate)
		{
			FlxG.updateFramerate = ClientPrefs.data.framerate;
			FlxG.drawFramerate = ClientPrefs.data.framerate;
		}
		else
		{
			FlxG.drawFramerate = ClientPrefs.data.framerate;
			FlxG.updateFramerate = ClientPrefs.data.framerate;
		}
	}

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		boyfriend.visible = (antialiasingOption == curSelected);
	}
}
