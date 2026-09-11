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

		var option:Option = new Option('长条按压覆盖', //Name
			'命中长条时在判定线上显示按压覆盖动画（QT 模组 NoteHoldCover 原生移植，可关闭）', //Description
			'holdCover',
			'bool');
		addOption(option);

		var option:Option = new Option('运行时贴图密排列', //Name
			'把 ≤160px 的小贴图打包进运行时共享图集（减少纹理数量与绘制批次；实验性，若出现贴图错乱请关闭）', //Description
			'runtimePack',
			'bool');
		addOption(option);

		var option:Option = new Option('背景图分辨率', //Name
			'独立大背景图（舞台/菜单背景等）的缩放比例，0.5 = 50%（大幅省内存，背景略降清晰度）', //Description
			'backgroundScale',
			'float');
		addOption(option);
		option.minValue = 0.25;
		option.maxValue = 1.0;
		option.displayFormat = '%v%';
		option.scrollSpeed = 0.05;
		option.onChange = null;

		// JS 优化移植续：帧率上限设置项（原 30~1000 的「帧率」项已被移除，现以档位形式回归）
		//
		// 「无上限」档位 = 100000 哨兵（"无人工限制"标记，非字面目标帧率）：把 framePeriod 压到
		//   0.01ms，要求原生帧循环里的 `nextUpdate` 是**浮点**（ci/lime-sdl3-patch 的墙钟补丁）。
		//   若手上是没打补丁的 ndll，每次 `nextUpdate += framePeriod` 被整型截断成 +0 →
		//   `while (nextUpdate <= currentUpdate)` 永不前进 → 主线程 100% 死循环、卡在加载界面
		//   （2026-09-11 实测事故）。
		//   处置方式（2026-09-11 之后重做）：
		//     · macOS —— 构建后恢复 tools/lime.ndll.wallclock 保证补丁在位，档位常驻；
		//     · Windows —— 档位重新提供，但实际取值由启动自检决定：补丁版 lime.ndll
		//       （含原生导出符号 lime_meteoric_frame_loop_patch）→ 100000；
		//       老 ndll → 自动退回 480。见 ClientPrefs.hasWallclockFrameLoop()。
		var frameRateOptions:Array<String> = ['120', '240', '480'];
		#if (mac || windows)
		frameRateOptions.push('无上限');
		#end
		var option:Option = new Option('帧率上限',
			'游戏更新/绘制帧率档位：120 / 240 / 480'
			+ #if (mac || windows) ' / 无上限（帧率只受 CPU/GPU 限制，发热/耗电更高）' #else '' #end
			+ '。移动端默认 120 防过热；切换立即生效',
			'framerateMode',
			'string',
			frameRateOptions);
		addOption(option);
		option.onChange = ClientPrefs.applyFramerate;

		#if desktop
		var option:Option = new Option('高清渲染',
			'2x 清晰渲染（Retina 下画面锐利；大规模谱面约 700~1400 帧）。关闭 = 1x 高性能（画面略糊，帧率约 3 倍，轻松 2200+）。修改后需重启游戏生效',
			'highDPIRender',
			'bool');
		addOption(option);
		option.onChange = ClientPrefs.applyHighDPIRenderMode;
		#end

		#if desktop
		var option:Option = new Option('性能模式',
			'Seiun 式音符快速路径：音符去 RGB 着色器、改用 ColorTransform 上色并直连 quad 合批（消除 shader 绑定开销，大规模谱面帧率大幅提升；音符颜色由三色渐变改为单色平涂）',
			'perfMode',
			'bool');
		addOption(option);
		#end

		#if desktop
		// 引擎关闭动画（Seiun 融合移植）：仅桌面显示；移动端不启用该功能也不显示这里的三项
		var option:Option = new Option('引擎关闭动画',
			'点击窗口关闭按钮（X）或按 Alt+F4 时，在窗口真正关闭前播放一段关闭动画；动画结束后才退出。手机端不适用',
			'closeAnimEnabled',
			'bool');
		addOption(option);

		var option:Option = new Option('关闭动画样式',
			'关闭动画的窗口变换方式：压扁=先压扁高度再压扁宽度；缩放=向中心缩小；坠落=一边缩小一边下落；滑出=一边缩小一边向左滑出',
			'closeAnimStyle',
			'string',
			['squeeze', 'zoom', 'drop', 'slide']);
		option.displayOptions = ['压扁', '缩放', '坠落', '滑出'];
		addOption(option);

		var option:Option = new Option('关闭动画速度',
			'关闭动画的播放速度倍率：1.0 为默认速度，数值越大播放越快（0.25x ~ 5.0x）',
			'closeAnimSpeed',
			'float');
		option.minValue = 0.25;
		option.maxValue = 5.0;
		option.changeValue = 0.25;
		option.decimals = 2;
		option.scrollSpeed = 0.8;
		addOption(option);
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

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		boyfriend.visible = (antialiasingOption == curSelected);
	}
}
