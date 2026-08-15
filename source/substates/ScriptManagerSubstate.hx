package substates;

import backend.Mods;
import objects.BackButton;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxSpriteUtil;
import haxe.io.Path;
#if sys
import sys.FileSystem;
#end

typedef ScriptEntry =
{
	var folder:String; // 脚本所在目录（以 / 结尾）
	var file:String; // 实际文件名（关闭时带 .disabled 后缀）
	var display:String; // 显示名（去掉 .disabled）
	var enabled:Bool;
}

class ScriptManagerSubstate extends MusicBeatSubstate
{
	// ===== 布局常量（磨砂圆角风格，与游玩设置/暂停界面一致） =====
	static final TITLE_Y:Float = 22;
	static final PANEL_X:Float = 160;
	static final PANEL_Y:Float = 96;
	static final PANEL_W:Float = 960;
	static final PANEL_H:Float = 560;
	static final ROW_X:Float = 204;
	static final ROW_START_Y:Float = 164;
	static final ROW_GAP:Float = 56;
	static final VALUE_RIGHT:Float = 1096;
	static final VALUE_BOX_W:Float = 44;
	static final VALUE_X:Float = VALUE_RIGHT - VALUE_BOX_W;
	static final MAX_VISIBLE:Int = 8;
	static final HINT_Y:Float = 668;
	static final ROW_TEXT_SIZE:Int = 24;

	var curSelected:Int = 0;
	var scrollOffset:Int = 0;
	var scriptList:Array<ScriptEntry> = [];
	var songContext:Null<String> = null; // 指定后管理该歌曲的谱面脚本 data/<songName>/

	var grpLabels:Array<FlxText> = [];
	var grpValues:Array<FlxText> = [];
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var backBtn:BackButton;
	var emptyText:FlxText;

	var mouseActive:Bool = true; // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;
	var nextAccept:Int = 5;

	public function new(?songContext:Null<String> = null)
	{
		super();
		this.songContext = songContext;

		// 固定渲染在专用相机上：zoom=1、scroll=(0,0)，暂停时不受游戏相机缩放影响
		var settingsCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [settingsCam];

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.6;
		add(bg);

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, '脚本管理', 48);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		// ---- 磨砂面板 ----
		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 20);
		add(panel);

		// ---- 选中高亮条 ----
		selectorBar = makePanel(PANEL_X + 16, ROW_START_Y - 4, PANEL_W - 32, 40, 12, 0x2EFFFFFF, null);
		add(selectorBar);

		// ---- 预创建可见行（随滚动复用） ----
		// 行文本使用 autoSize（构造宽度 0）渲染：OpenFL 会强制文本框宽度 = 文字宽度 + 4，
		// 无论文字多长都完整绘制，从根本上杜绝右侧裁切。
		// 同时给 textField 加 1px 内边距，抵消桌面端绘制时的 (-1,-1) 平移对描边的裁切。
		for (i in 0...MAX_VISIBLE)
		{
			var rowY:Float = ROW_START_Y + (i * ROW_GAP);

			var lbl:FlxText = new FlxText(ROW_X, rowY + 2, 0, '', ROW_TEXT_SIZE);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, 0xFF9A9AA8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.wordWrap = false; // 强制单行
			lbl.textField.x = 1; // 左/上 1px 内边距，避免描边被裁
			lbl.textField.y = 1;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			add(lbl);
			grpLabels.push(lbl);

			var val:FlxText = new FlxText(VALUE_X, rowY + 2, VALUE_BOX_W, '', ROW_TEXT_SIZE);
			val.scrollFactor.set();
			val.wordWrap = false;
			val.setFormat(Paths.font('future.ttf'), ROW_TEXT_SIZE, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			add(val);
			grpValues.push(val);
		}

		// ---- 空列表提示 ----
		emptyText = new FlxText(0, PANEL_Y + PANEL_H / 2 - 20, FlxG.width, '没有找到可管理的脚本', 26);
		emptyText.scrollFactor.set();
		emptyText.setFormat(Paths.font('future.ttf'), 26, 0xFF9A9AA8, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyText.borderSize = 1.5;
		emptyText.antialiasing = ClientPrefs.data.antialiasing;
		emptyText.visible = false;
		add(emptyText);

		// ---- 返回按钮 + 操作提示 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		var hintText:FlxText = new FlxText(0, HINT_Y, FlxG.width, '↑ ↓ 选择 · 回车 开关脚本（含当前谱面脚本，关闭后加 .disabled 后缀，重启歌曲生效）· ESC 返回', 18);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), 18, 0xFFA9A9B8, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);

		loadScripts();
		refreshList();
		FlxG.mouse.visible = true;
	}

	// 扫描所有脚本目录（与引擎加载顺序一致）：assets/scripts、全局 mod、mods/scripts、当前 mod，
	// 以及当前曲目的谱面根目录 data/<songName>/（与 PlayState 加载歌曲脚本一致）
	function loadScripts():Void
	{
		scriptList = [];
		#if sys
		var folders:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'scripts/');
		addScriptsFromFolders(folders);

		var songName:Null<String> = null;
		if (songContext != null && songContext.length > 0)
			songName = songContext;
		else if (PlayState.instance != null && PlayState.SONG != null)
			songName = Paths.formatToSongPath(PlayState.SONG.song);

		if (songName != null)
		{
			folders = Mods.directoriesWithFile(Paths.getPreloadPath(), 'data/' + songName + '/');
			addScriptsFromFolders(folders);
		}
		#end
	}

	function addScriptsFromFolders(folders:Array<String>):Void
	{
		#if sys
		for (folder in folders)
		{
			if (!FileSystem.exists(folder)) continue;

			var files:Array<String> = FileSystem.readDirectory(folder);
			files.sort((a, b) -> {
				var la:String = a.toLowerCase();
				var lb:String = b.toLowerCase();
				if (la == lb) return 0;
				return la < lb ? -1 : 1;
			});

			for (file in files)
			{
				var lower:String = file.toLowerCase();
				var enabled:Bool = true;
				var base:String = file;
				if (lower.endsWith('.disabled'))
				{
					enabled = false;
					base = file.substr(0, file.length - '.disabled'.length);
					lower = base.toLowerCase();
				}
				if (!lower.endsWith('.lua') && !lower.endsWith('.hx')) continue;

				// 只显示文件名，不显示文件夹前缀
				scriptList.push({folder: folder, file: file, display: base, enabled: enabled});
			}
		}
		#end
	}

	// 每个可见行对应的固定命中区域（不依赖文本宽度，点击/悬停区域始终是整行）
	function getRowRect(i:Int):FlxRect
	{
		return new FlxRect(ROW_X, ROW_START_Y + i * ROW_GAP, VALUE_RIGHT - ROW_X, ROW_GAP);
	}

	function refreshList():Void
	{
		if (selectorBar != null)
		{
			var barY:Float = ROW_START_Y - 4 + ((curSelected - scrollOffset) * ROW_GAP);
			if (selectorBar.y != barY)
			{
				if (selectorTween != null)
				{
					selectorTween.cancel();
					selectorTween = null;
				}
				selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
			}
		}

		for (i in 0...MAX_VISIBLE)
		{
			var idx:Int = scrollOffset + i;
			if (idx >= 0 && idx < scriptList.length)
			{
				var entry:ScriptEntry = scriptList[idx];

				var lbl:FlxText = grpLabels[i];
				lbl.visible = true;
				lbl.text = entry.display; // autoSize 下 OpenFL 自动按文字宽度生成位图，完整绘制
				lbl.color = (idx == curSelected) ? FlxColor.WHITE : (entry.enabled ? 0xFF9A9AA8 : 0xFF666677);

				grpValues[i].visible = true;
				grpValues[i].text = entry.enabled ? '开' : '关';
				grpValues[i].color = (idx == curSelected) ? FlxColor.WHITE : (entry.enabled ? 0xFF7CFC9A : 0xFFFF8A8A);
			}
			else
			{
				grpLabels[i].visible = false;
				grpValues[i].visible = false;
			}
		}

		if (emptyText != null)
			emptyText.visible = (scriptList.length == 0);
	}

	function changeSelection(change:Int):Void
	{
		if (scriptList.length == 0) return;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		curSelected += change;
		if (curSelected < 0) curSelected = scriptList.length - 1;
		if (curSelected >= scriptList.length) curSelected = 0;

		// 滚动窗口跟随选中项
		if (curSelected < scrollOffset) scrollOffset = curSelected;
		else if (curSelected >= scrollOffset + MAX_VISIBLE) scrollOffset = curSelected - MAX_VISIBLE + 1;

		refreshList();
	}

	// 开关当前脚本：开启 → 文件名加 .disabled；关闭 → 删除 .disabled 后缀
	function toggleSelected():Void
	{
		if (scriptList.length == 0) return;
		var entry:ScriptEntry = scriptList[curSelected];
		var oldPath:String = Path.join([entry.folder, entry.file]);
		var newPath:String = entry.enabled ? (oldPath + '.disabled') : oldPath.substr(0, oldPath.length - '.disabled'.length);

		#if sys
		try
		{
			FileSystem.rename(oldPath, newPath);
			entry.enabled = !entry.enabled;
			entry.file = entry.enabled ? entry.file.substr(0, entry.file.length - '.disabled'.length) : (entry.file + '.disabled');
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
		}
		catch (e:Dynamic)
		{
			trace('脚本切换失败：$e');
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
		#end
		refreshList();
	}

	function getHoveredID(mouseX:Float, mouseY:Float):Int
	{
		for (i in 0...MAX_VISIBLE)
		{
			var idx:Int = scrollOffset + i;
			if (idx >= scriptList.length) break;
			var rowRect:FlxRect = getRowRect(i);
			if (mouseX >= rowRect.x && mouseX <= rowRect.x + rowRect.width && mouseY >= rowRect.y && mouseY <= rowRect.y + rowRect.height)
				return idx;
		}
		return -1;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if (border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	override function update(elapsed:Float)
	{
		if (cameras != null && cameras[0] != null)
		{
			cameras[0].zoom = 1;
			cameras[0].scroll.set(0, 0);
		}
		super.update(elapsed);

		var mousePos:FlxPoint = FlxG.mouse.getScreenPosition(cameras[0], FlxPoint.get());

		if (controls.UI_UP_P)
		{
			mouseActive = false;
			mouseLockX = mousePos.x;
			mouseLockY = mousePos.y;
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			mouseActive = false;
			mouseLockX = mousePos.x;
			mouseLockY = mousePos.y;
			changeSelection(1);
		}

		if (!controls.controllerMode)
		{
			var hoveredID:Int = getHoveredID(mousePos.x, mousePos.y);

			// 悬停高亮
			for (i in 0...MAX_VISIBLE)
			{
				var idx:Int = scrollOffset + i;
				if (idx >= scriptList.length) break;
				if (idx != curSelected)
					grpLabels[i].color = (hoveredID == idx) ? 0xFFD7D7E0 : (scriptList[idx].enabled ? 0xFF9A9AA8 : 0xFF666677);
			}

			if (!mouseActive)
			{
				var dx:Float = mousePos.x - mouseLockX;
				var dy:Float = mousePos.y - mouseLockY;
				if (dx * dx + dy * dy > 10 * 10) mouseActive = true;
			}

			if (FlxG.mouse.wheel != 0)
			{
				mouseActive = true;
				changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
			}

			backBtn.setHovered(mousePos.x, mousePos.y);
			if (FlxG.mouse.justPressed && backBtn.over(mousePos.x, mousePos.y))
			{
				mousePos.put();
				close();
				FlxG.sound.play(Paths.sound('cancelMenu'));
				return;
			}

			if (FlxG.mouse.justPressed && hoveredID >= 0)
			{
				mouseActive = true;
				if (hoveredID != curSelected)
					changeSelection(hoveredID - curSelected);
				else
					toggleSelected();
			}
		}
		mousePos.put();

		if (controls.BACK)
		{
			close();
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		if (nextAccept <= 0 && controls.ACCEPT)
			toggleSelected();
		if (nextAccept > 0) nextAccept -= 1;
	}

	#if mobile
	/** 脚本管理（暂停菜单里打开）：按返回键 = 关闭并回到暂停菜单，不退出游戏 */
	override public function onAndroidBack():Bool
	{
		close();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		return true;
	}
	#end
}
