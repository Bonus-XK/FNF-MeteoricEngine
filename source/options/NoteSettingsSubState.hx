package options;

import flixel.animation.FlxAnimation;
import flixel.graphics.frames.FlxFrame;
import objects.Note;
import objects.NoteSplash;
import objects.StrumNote;

class NoteSettingsSubState extends BaseOptionsMenu
{
	/** 整屏路径（暂停内嵌）下预览精灵的隐藏位 y（与既有箭头预览同值） */
	static final PREVIEW_HIDDEN_Y:Float = -200;

	/**
	 * 打击特效预览的轨道布局 = **音符皮肤预览的同一套间距/位置**（同一个公式：
	 *   `x = 100 + (520 / Note.colArray.length) * i`，见本文件构造里 notes 的创建式）。
	 * 精灵形态与溅射相对位仍照搬 Psych Engine 0.7.3 `states/editors/NoteSplashDebugState.hx`：
	 *   站立箭头 alpha 0.75；溅射精灵位 = 箭头位 − (Note.swagWidth * 0.95, Note.swagWidth)。
	 */

	/**
	 * 打击特效预览一律用 PE 0.7.3 `NoteSplashDebugState` 的**全尺寸**排版：
	 * 站立箭头 = 实战 scale 0.7，溅射不缩放（与暂停内嵌路径、实战同尺寸）。
	 * 预览带只有 108px（6 行），最高的 splash 皮肤（noteSplashes-vanilla 整段动画包络 316px）装不下 ——
	 * 按用户明确指令「遮挡问题不用管」：允许预览压住选项行/说明条，不再为躲遮挡整体缩小。
	 * （缩小不但让 Note 变小，还把缩放折算引入位置/offset，正是切换皮肤时 Note 偏移的温床。）
	 */

	var noteOptionID:Int = -1;
	var splashOptionID:Int = -1;
	var notes:FlxTypedGroup<StrumNote>;
	var notesTween:Array<FlxTween> = [];
	var noteY:Float = 90;

	// ---- 打击特效预览（4 轨「站立箭头 + 溅射」，轨位与音符皮肤预览一致）----
	var previewRoot:flixel.group.FlxGroup;     // 预览容器：[箭头预览 | 打击特效预览]（宿主按它摆预览带）
	var splashGroup:flixel.group.FlxGroup;     // 打击特效预览整组（整组显隐 + 隐藏时停 update）
	var splashArrows:Array<StrumNote>;         // 站立箭头（alpha 0.75，站位 + 提供该轨 RGB 调色板）
	var splashSprites:Array<FlxSprite>;        // 溅射预览（PE 用普通 FlxSprite：不进实战池、不参与命中逻辑）
	var splashTexture:String = '';
	var panePreview:Bool = false;               // 构造期是否由单界面宿主构造（headless 只在构造期为 true）

	public function new()
	{
		title = '音符';
		rpcTitle = '音符设置菜单'; //for Discord Rich Presence

		// 构造期的 headless 是准的（唯一可靠的"被单界面宿主构造"信号就在此时）
		panePreview = BaseOptionsMenu.headless;

		// for note skins（箭头样式预览）
		// 整屏路径（暂停内嵌）：预览挂在子状态里，从屏幕上方滑入；
		// 单界面宿主：挂到内容区的**预览带**容器（BaseOptionsMenu.headlessVisualHost），
		// 因内容区没有裁剪遮罩，起始就放静止位（-200 会画到选项行上面）。
		notes = new FlxTypedGroup<StrumNote>();
		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = new StrumNote(100 + (520 / Note.colArray.length) * i, panePreview ? 0 : -200, i, 0);
			note.centerOffsets();
			note.centerOrigin();
			note.playAnim('static');
			notes.add(note);
		}

		// 打击特效预览：只依赖轨道数与皮肤解析，与选项表无关
		buildSplashPreview();

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

		// 「Psych 0.6.3 兼容模式」「Lua 0.6.3 兼容」已迁至 options/ProgrammingSettingsSubState.hx（编程分区），
		// 变量名不变（psych063Mode / luaUse063Compat），老存档值继续生效。

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
			option.onChange = onChangeSplashSkin;
			splashOptionID = optionsArray.length - 1;
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

		super();
		// 预览容器（箭头预览 + 打击特效预览）：单界面宿主会把它整体摆进内容区的预览带
		if (previewRoot != null) addVisual(previewRoot);
		// ⚠ 必须在 super() **之后**赋值：hxcpp 把字段初始化器放在基类构造里跑，
		// super() 之前写的 previewRows 会被清回 0（meteoric-system 记录的静默失效事故同源）。
		if (BaseOptionsMenu.headless) previewRows = 6; // 预览带占 2 行（8 行 → 6 行）
	}

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		onPaneSelectionChange(curSelected);
	}

	/** 预览联动：分页路径（changeSelection 覆写）与单界面路径（OptionsPane）共用 */
	override function onPaneSelectionChange(index:Int)
	{
		if (notes == null) return;
		var showNotes:Bool = (noteOptionID >= 0 && index == noteOptionID);
		var showSplash:Bool = (splashOptionID >= 0 && index == splashOptionID);

		// 单界面宿主：预览在内容区的预览带里（没有裁剪遮罩）→ 只做显隐，不做"从屏幕上方滑入"。
		// ⚠ 判据必须是 paneHosted（常驻标志），**不能**用 BaseOptionsMenu.headless ——
		//   后者只在构造期为 true（OptionsState.sectionInstance 构造完即还原），换行时它是 false，
		//   会误走整屏分支：箭头被 tween 到 y=90 压到选项行上、溅射被摆到面板外（2026-09-16 实机截图定位）。
		// ⚠ 也不要在这里重置 sprite 的 y：预览带的位置是宿主按包围盒一次性摆好的（OptionsPane.setPreview），
		//   重置 y 会把那次摆放抹掉。
		if (paneHosted)
		{
			notes.visible = showNotes;
			setSplashPreviewShown(showSplash, false);
			return;
		}

		// 整屏路径（暂停内嵌）：箭头沿用原有的"从屏幕上方滑入"；打击特效预览直接切到位 ——
		// 该路径没有裁剪遮罩，滑动会扫过选项行，且再添 8 组并发动效会踩到 meteoric-design 的并发红线。
		setSplashPreviewShown(showSplash, true);

		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = notes.members[i];
			if(notesTween[i] != null) notesTween[i].cancel();
			if(showNotes)
				notesTween[i] = FlxTween.tween(note, {y: noteY}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
			else
				notesTween[i] = FlxTween.tween(note, {y: PREVIEW_HIDDEN_Y}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
		}
	}

	/**
	 * 打击特效预览整组显隐。
	 * @param moveY true = 整屏路径：同时把精灵摆到"静止位 / 隐藏位"（该路径没有宿主摆位，y 得自己管）
	 */
	function setSplashPreviewShown(show:Bool, moveY:Bool):Void
	{
		if (splashGroup == null) return;
		splashGroup.visible = show;
		splashGroup.active = show; // 隐藏时停掉溅射动画推进，不做无谓的逐帧开销
		if (!moveY) return;
		// 整屏路径：站立箭头落到 `noteY + swagWidth`，于是**溅射顶端正好在 noteY**，
		// 不会顶出面板/屏幕上沿（PE 0.7.3 调试界面也是把 y 放在 290 让溅射完整可见）。
		for (i in 0...splashSprites.length)
		{
			var y:Float = show ? noteY + Note.swagWidth : PREVIEW_HIDDEN_Y;
			splashArrows[i].y = y;
			splashSprites[i].y = y - Note.swagWidth;
		}
	}

	function onChangeNoteSkin()
	{
		notes.forEachAlive(function(note:StrumNote) {
			changeNoteSkin(note);
			note.centerOffsets();
			note.centerOrigin();
		});
		reloadSplashPreview(); // 打击特效预览里的站立箭头用同一份取皮肤逻辑，一并刷新
	}

	function onChangeSplashSkin()
	{
		reloadSplashPreview();
	}

	/**
	 * 构建打击特效预览 —— 精灵形态照搬 Psych Engine 0.7.3 `NoteSplashDebugState.create()`：
	 *   ① 每轨一个 StrumNote 站立箭头（alpha 0.75），负责站位 + 提供该轨 RGB 调色板；
	 *   ② 每轨一个普通 FlxSprite 作溅射，位置 = 箭头位 − (swagWidth*0.95, swagWidth)（实战公式）。
	 * 轨位**不再用 PE 的 1280 全屏排版**（`i * 220 + 240`），改用与音符皮肤预览逐字相同的
	 * `x = 100 + (520 / Note.colArray.length) * i`、`baseY = panePreview ? 0 : -200`，
	 * 使打击特效的 4 轨与音符皮肤预览的 4 支箭头同间距、同位置（用户要求）。
	 * 与 PE 调试界面的差别只有一处：动画设为**循环**（调试界面靠按键重播）。
	 * 全尺寸在 108px 预览带里会溢出、压住选项行 —— 用户明确要求「遮挡问题不用管」。
	 * 预览容器只有一个（宿主的 OptionsPane.setPreview 只接一个容器），两种预览按选中行整组显隐。
	 */
	function buildSplashPreview():Void
	{
		previewRoot = new flixel.group.FlxGroup();
		splashGroup = new flixel.group.FlxGroup();
		splashArrows = [];
		splashSprites = [];

		var baseY:Float = panePreview ? 0 : PREVIEW_HIDDEN_Y;
		for (i in 0...Note.colArray.length)
		{
			// 与上方 notes 的创建式逐字一致：同间距、同位置（音符皮肤预览的 4 支箭头）
			var x:Float = 100 + (520 / Note.colArray.length) * i;
			var note:StrumNote = new StrumNote(x, baseY, i, 0);
			note.alpha = 0.75; // PE 0.7.3: 站立箭头半透明，不抢溅射
			note.playAnim('static');
			splashArrows.push(note);
			splashGroup.add(note);

			var splash:FlxSprite = new FlxSprite(x, baseY);
			splash.setPosition(splash.x - Note.swagWidth * 0.95, splash.y - Note.swagWidth);
			splash.antialiasing = ClientPrefs.data.antialiasing;
			splashSprites.push(splash);
			splashGroup.add(splash);
		}

		reloadSplashPreview();

		previewRoot.add(notes);
		previewRoot.add(splashGroup);
		splashGroup.visible = false; // 默认选中「音符皮肤」行 → 只显示箭头预览
	}

	/**
	 * 重解析打击特效贴图/动画/偏移 + 与箭头预览同心 —— 对应 PE 0.7.3
	 * `NoteSplashDebugState.loadFrames() + reloadAnims()`。
	 * 贴图 = `NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix()`（与实战同一条解析式）；
	 * 动画名 = `'<config.anim> <列色> 1'`（PE 的 sparrow 帧名前缀）；帧率取 config 区间随机值；
	 * offset = `(10,10) + config.offsets[轨道]`（PE 的手动偏移校对值，实战同款）；
	 * 着色器 = 该轨站立箭头的 RGB 调色板（PE 原样），**063 预染色皮肤例外：不挂着色器**。
	 * 全程**不缩放**：站立箭头保持实战 scale 0.7，溅射保持素材原尺寸（PE 0.7.3 预览同款）。
	 */
	function reloadSplashPreview():Void
	{
		// 站立箭头先回到 scale = 1 的实战态：reloadNote/updateHitbox/centerOffsets 都按当前 scale 计算
		for (i in 0...splashArrows.length)
		{
			splashArrows[i].scale.set(1, 1);
			splashArrows[i].offset.set(0, 0);
			changeNoteSkin(splashArrows[i]);
		}

		splashTexture = NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix();
		var atlas = Paths.getSparrowAtlas(splashTexture); // 类型由 Paths.getSparrowAtlas 推断（FlxAtlasFrames）
		var config:NoteSplashConfig = NoteSplash.precacheConfig(splashTexture);
		if (atlas == null || config == null)
		{
			// 与 NoteSplash.loadAnims 同一条回退链：贴图/配置缺失时退回默认皮肤，不留空白预览
			splashTexture = NoteSplash.defaultNoteSplash;
			atlas = Paths.getSparrowAtlas(splashTexture);
			config = NoteSplash.precacheConfig(splashTexture);
		}

		// 063（PE 0.6.3 预染色四色贴图）不挂 NoteSplash 着色器：raw 直出才是它本来的样子，
		// 判据与 NoteSplash.use063Raw 一致（贴图名含 noteSplashes-063）。
		var raw:Bool = splashTexture.indexOf('noteSplashes-063') >= 0;
		var animName:String = (config != null && config.anim != null) ? config.anim : 'note splash';
		var minFps:Int = (config != null) ? config.minFps : 22;
		var maxFps:Int = (config != null) ? config.maxFps : 26;
		var offsets:Array<Array<Float>> = (config != null) ? config.offsets : null;

		for (i in 0...splashSprites.length)
		{
			var spl:FlxSprite = splashSprites[i];
			if (atlas != null)
			{
				spl.frames = atlas;
				spl.animation.destroyAnimations();
				spl.animation.addByPrefix('note$i-1', '$animName ${Note.colArray[i]} 1', 24, true); // loop=true：预览要一直爆
				spl.animation.play('note$i-1', true);
				if (spl.animation.curAnim != null) spl.animation.curAnim.frameRate = FlxG.random.int(minFps, maxFps);
			}

			var off:Array<Float> = [0, 0];
			if (offsets != null && offsets.length > 0)
				off = offsets[FlxMath.wrap(i, 0, offsets.length - 1)];
			spl.offset.set(10 + off[0], 10 + off[1]);
			spl.scale.set(1, 1); // 溅射保持素材原尺寸（PE 0.7.3 预览同款，不做缩放）
			spl.alpha = ClientPrefs.data.splashAlpha;
			spl.shader = raw ? null : splashArrows[i].rgbShader.parent.shader;
		}

		sizeSplashHitboxes(); // 只把包围盒设成整段动画包络，不动 offset/scale/position
		centerSplashGroup(panePreview);
	}

	/**
	 * 一个溅射精灵**整段动画**的绘制包络（相对"精灵位置 - offset"的原点，未缩放）。
	 * 必须逐帧量、不能取首帧：sparrow 每帧的 trim/rect 都不同（063 的 trim.y 在动画里从 87 变到 30），
	 * 首帧只有峰值帧的 ~85%，拿它当尺寸会让峰值帧顶出预览带。
	 * （FlxFrame.offset = sparrow trim：flixel 5.2.2 FlxAtlasFrames:271-282，offset = -frameX/-frameY）
	 */
	function splashDrawnBounds(spl:FlxSprite):Array<Float>
	{
		var anim:FlxAnimation = spl.animation.curAnim;
		if (anim == null || spl.frames == null) return [0, 0, spl.frameWidth, spl.frameHeight];

		var left:Float = 1e9;
		var top:Float = 1e9;
		var right:Float = -1e9;
		var bottom:Float = -1e9;
		for (fi in anim.frames)
		{
			var fr:FlxFrame = spl.frames.frames[fi];
			if (fr == null) continue;
			left = Math.min(left, fr.offset.x);
			top = Math.min(top, fr.offset.y);
			right = Math.max(right, fr.offset.x + fr.frame.width);
			bottom = Math.max(bottom, fr.offset.y + fr.frame.height);
		}
		return [left, top, right, bottom];
	}

	/**
	 * 只把溅射精灵的包围盒（width/height）设成**整段动画包络**，不做任何缩放
	 * （PE 0.7.3 预览是全尺寸；宿主/同心逻辑按 `x + width` 量包围盒，用首帧尺寸会让峰值帧越界：
	 *  063 首帧 303px vs 峰值 321px）。
	 * ⚠ 这里**不得**再改 offset/scale/position：Note 的锚点只能由站立箭头决定（见 centerSplashGroup）。
	 *   缩放折算会把"溅射包络随皮肤变化"传导到 Note 的落位 —— 用户实测的「每切一次样式 Note 偏移」。
	 */
	function sizeSplashHitboxes():Void
	{
		for (i in 0...splashSprites.length)
		{
			var spl:FlxSprite = splashSprites[i];
			var bounds:Array<Float> = splashDrawnBounds(spl);
			spl.width = bounds[2] - bounds[0];
			spl.height = bounds[3] - bounds[1];
		}
	}

	/**
	 * 把打击特效预览的**站立箭头**整组平移到与箭头预览同心。
	 * PE 的 `x = i*220 + 240` 是按 1280 全屏排的，直接搬进 956 宽内容区会整体偏右 ≈236px。
	 *
	 * ⚠ Note 的锚点只能是站立箭头：下面的 sMin/sMax **只统计 splashArrows**，不得把
	 *   splashSprites 的包络算进来。溅射包络随皮肤变化（225–316px），一旦参与居中，每切一次
	 *   NoteSplash 样式，整组（含站立箭头）都会被平移一段 —— 这就是用户实测的「Note 偏移」。
	 *   站立箭头只依赖音符皮肤 ⇒ 首次居中后 dx/dy 恒为 0，重复调用幂等，切样式不再移动 Note。
	 * 溅射相对箭头的实战位置（− swagWidth*0.95 / − swagWidth）+ config 偏移保持不变；
	 * 全尺寸下溅射会压住选项行/说明条 —— 用户明确要求「遮挡问题不用管」。
	 * @param centerY 预览带路径需要竖直同心；整屏路径保持 PE 的实战相对高度（溅射在箭头上方）。
	 */
	function centerSplashGroup(centerY:Bool):Void
	{
		if (splashArrows == null || splashArrows.length == 0) return;
		var aMinX:Float = 1e9;
		var aMaxX:Float = -1e9;
		var aMinY:Float = 1e9;
		var aMaxY:Float = -1e9;
		var sMinX:Float = 1e9;
		var sMaxX:Float = -1e9;
		var sMinY:Float = 1e9;
		var sMaxY:Float = -1e9;

		for (n in notes.members)
		{
			aMinX = Math.min(aMinX, n.x - n.offset.x);
			aMaxX = Math.max(aMaxX, n.x - n.offset.x + n.width);
			aMinY = Math.min(aMinY, n.y - n.offset.y);
			aMaxY = Math.max(aMaxY, n.y - n.offset.y + n.height);
		}
		// 只量站立箭头（Note 锚点）；溅射包络不参与，避免换皮肤时把 Note 推走
		for (i in 0...splashArrows.length)
		{
			var b:FlxSprite = splashArrows[i];
			sMinX = Math.min(sMinX, b.x - b.offset.x);
			sMaxX = Math.max(sMaxX, b.x - b.offset.x + b.width);
			sMinY = Math.min(sMinY, b.y - b.offset.y);
			sMaxY = Math.max(sMaxY, b.y - b.offset.y + b.height);
		}

		var dx:Float = (aMinX + aMaxX) * 0.5 - (sMinX + sMaxX) * 0.5;
		var dy:Float = centerY ? ((aMinY + aMaxY) * 0.5 - (sMinY + sMaxY) * 0.5) : 0;
		if (Math.abs(dx) < 0.01 && Math.abs(dy) < 0.01) return; // 已同心：重复调用幂等

		for (i in 0...splashSprites.length)
		{
			splashArrows[i].x += dx;
			splashSprites[i].x += dx;
			splashArrows[i].y += dy;
			splashSprites[i].y += dy;
		}
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
}
