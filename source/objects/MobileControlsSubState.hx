package objects;

import backend.MusicBeatSubstate;
import backend.Paths;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.input.touch.FlxTouch;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

/**
 * 触控板设置（移植自 Psych MobileControlsSubState，界面重写为中文）：
 *  - 左右箭头切换布局模式（右手/左手/自定义/双手/判定区/无按键）
 *  - 自定义模式：直接拖动 4 个方向键调整位置，实时显示坐标
 *  - 保存并退出 / 恢复默认
 * 判定沿用 MobileControls 的底层 Tap 捕获，掉帧时 UI 点按也不会丢。
 */
class MobileControlsSubState extends MusicBeatSubstate
{
	public static final MODE_NAMES:Array<String> = ['右手按键', '左手按键', '自定义布局', '双手按键', '全屏判定区', '无按键'];

	var curMode:Int = 0;
	var preview:MobileControls = null;
	var dragging:String = null;
	var dragID:Int = -1; // 发起拖动的触点 ID：多指时只跟随该触点，防其他手指抢动

	var modeText:FlxText;
	var leftArrowRect:FlxSprite;
	var rightArrowRect:FlxSprite;
	var resetBtn:FlxSprite;
	var exitBtn:FlxSprite;
	var backBtn:FlxSprite;
	var posTexts:Array<FlxText> = [];
	var hintText:FlxText;
	var exitLabel:FlxText;
	var resetLabel:FlxText;

	override function create()
	{
		super.create();
		curMode = MobileControls.getMode();
		buildUI();
		rebuildPreview();
	}

	function buildUI():Void
	{
		// 半透明遮罩
		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xC810101C);
		bg.scrollFactor.set();
		add(bg);

		// 标题
		var title:FlxText = new FlxText(0, 28, FlxG.width, '触控板设置', 30);
		title.setFormat(Paths.font('future.ttf'), 30, 0xFFFFFFFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2;
		title.scrollFactor.set();
		add(title);

		// 模式面板
		var panel:FlxSprite = makePanel(340, 130, 600, 180, 22);
		add(panel);

		modeText = new FlxText(340, 188, 600, '', 36);
		modeText.setFormat(Paths.font('future.ttf'), 36, 0xFFFFFFFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		modeText.borderSize = 2;
		modeText.scrollFactor.set();
		add(modeText);

		leftArrowRect = makeBtn(366, 178, 72, 72, '<');
		rightArrowRect = makeBtn(842, 178, 72, 72, '>');

		// 自定义模式坐标面板
		posTexts = [];
		for (i in 0...4)
		{
			var t:FlxText = new FlxText(360, 352 + i * 34, 280, '', 18);
			t.setFormat(Paths.font('vcr.ttf'), 18, 0xFFCFCFDC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.scrollFactor.set();
			add(t);
			posTexts.push(t);
		}

		hintText = new FlxText(120, 672, 1040, '', 16);
		hintText.setFormat(Paths.font('future.ttf'), 16, 0xFFFFFFFF, CENTER);
		hintText.scrollFactor.set();
		add(hintText);

		// 按钮
		exitBtn = makeBtn(FlxG.width - 270, FlxG.height - 84, 250, 60, null);
		exitBtn.color = 0xFF3AA86B;
		exitLabel = makeLabel(exitBtn, '保存并退出');

		resetBtn = makeBtn(FlxG.width - 270, FlxG.height - 156, 250, 60, null);
		resetBtn.color = 0xFFB05454;
		resetLabel = makeLabel(resetBtn, '恢复默认');
		resetBtn.visible = false;
		resetLabel.visible = false;

		// 与主菜单 BackButton 同款磨砂玻璃圆（替换原半透明方块）；makeGlassCircleBtn 不自挂,需 add
		backBtn = objects.MobileControls.makeGlassCircleBtn(0, 0, 110, '');
		add(backBtn);
		var backLabel:FlxText = objects.MobileControls.makeGlassCircleLabel(backBtn, 'X');
		add(backLabel);
		backLabel.alpha = 0.9;
	}

	function makeBtn(x:Float, y:Float, w:Float, h:Float, label:String):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), 0x33FFFFFF);
		spr.scrollFactor.set();
		add(spr);
		if (label != null) makeLabel(spr, label);
		return spr;
	}

	function makeLabel(parent:FlxSprite, text:String):FlxText
	{
		var label:FlxText = new FlxText(parent.x, parent.y, parent.width, text, Std.int(parent.height * 0.42));
		label.setFormat(Paths.font('vcr.ttf'), Std.int(parent.height * 0.42), 0xFFFFFFFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.5;
		label.scrollFactor.set();
		label.y = parent.y + (parent.height - label.height) / 2 - 4;
		add(label);
		return label;
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: 0x45FFFFFF, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	inline function touchInLogical(touch:FlxTouch, x:Float, y:Float, w:Float, h:Float):Bool
	{
		// 必须按本状态相机换算视图坐标：暂停路径经 openCamSubState 打开时 cameras[0]=camOther，
		// 裸 touch.x/y 是默认相机视图坐标（非 camOther）→ 全部命中错位（点 ◀差 90px、落点超出画布）。
		var p:FlxPoint = FlxPoint.get();
		var cam:FlxCamera = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		touch.getPositionInCameraView(cam, p);
		var hit:Bool = p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h;
		p.put();
		return hit;
	}

	function uiTapped(rect:FlxSprite):Bool
	{
		if (rect == null || !rect.visible) return false;
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed && touchInLogical(touch, rect.x, rect.y, rect.width, rect.height))
			{
				MobileControls.clearQueuedTap(touch.touchPointID);
				return true;
			}
		}
		return MobileControls.drainTapInRect(rect.x, rect.y, rect.width, rect.height);
	}

	function rebuildPreview():Void
	{
		if (preview != null) preview.destroy();
		// 预览 pad 渲染/判定必须与界面同层：暂停路径经 openCamSubState 打开时
		// 本子状态 cameras[0] = camOther，而 FlxG.camera 是游戏相机（暂停时 zoom/scroll
		// 非默认）→ 预览被盖住/判定错乱；主菜单路径 cameras[0]=默认相机，行为不变。
		var previewCam:FlxCamera = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		preview = new MobileControls(false, previewCam, curMode);
		add(preview);
		updateUI();
	}

	function updateUI():Void
	{
		if (modeText != null) modeText.text = MODE_NAMES[curMode];
		var custom:Bool = (curMode == MobileControls.MODE_CUSTOM);
		resetBtn.visible = custom;
		resetLabel.visible = custom;
		for (t in posTexts) t.visible = custom;
		hintText.text = custom
			? '拖动 4 个方向键调整位置 · < / > 切换布局 · 点击右上角保存'
			: '< / > 切换布局 · 点击右上角保存';
		if (custom) updatePosTexts();
	}

	function updatePosTexts():Void
	{
		if (preview == null) return;
		var labels:Array<String> = ['左键', '下键', '上键', '右键'];
		for (i in 0...4)
		{
			var zones:Array<FlxSprite> = preview.padButtons.get(MobileControls.CUSTOM_ORDER[i]);
			if (zones != null && zones.length > 0)
				posTexts[i].text = labels[i] + '  X: ' + Std.int(zones[0].x) + '  Y: ' + Std.int(zones[0].y);
		}
	}

	function changeMode(change:Int):Void
	{
		curMode += change;
		if (curMode < 0) curMode = MODE_NAMES.length - 1;
		if (curMode >= MODE_NAMES.length) curMode = 0;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		rebuildPreview();
	}

	function resetPositions():Void
	{
		if (preview == null) return;
		var defaults:Array<Array<Float>> = [
			[FlxG.width - 384, FlxG.height - 309],
			[FlxG.width - 258, FlxG.height - 201],
			[FlxG.width - 258, FlxG.height - 408],
			[FlxG.width - 132, FlxG.height - 309]
		];
		for (i in 0...4)
		{
			var zones:Array<FlxSprite> = preview.padButtons.get(MobileControls.CUSTOM_ORDER[i]);
			if (zones != null && zones.length > 0)
			{
				zones[0].x = defaults[i][0];
				zones[0].y = defaults[i][1];
			}
		}
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		updatePosTexts();
	}

	function saveAndExit():Void
	{
		MobileControls.setMode(curMode);
		if (curMode == MobileControls.MODE_CUSTOM && preview != null)
		{
			var positions:Array<Array<Float>> = [];
			for (key in MobileControls.CUSTOM_ORDER)
			{
				var zones:Array<FlxSprite> = preview.padButtons.get(key);
				if (zones != null && zones.length > 0)
					positions.push([zones[0].x, zones[0].y]);
			}
			if (positions.length >= 4) MobileControls.saveCustomPositions(positions);
		}
		FlxG.sound.play(Paths.sound('confirmMenu'));
		close();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// 自定义模式：拖动方向键（只跟随发起拖动的触点；拖动期间冻结 UI 点击，防误触）
		if (curMode == MobileControls.MODE_CUSTOM && preview != null)
		{
			if (dragging == null)
			{
				for (touch in FlxG.touches.list)
				{
					if (!touch.justPressed) continue;
					// 命中判定：重叠按键全部记录，选"中心距离触点最近"的键拖动。
					// （此前按 CUSTOM_ORDER 顺序取先命中者：叠放后想拖的键总是被压在
					//   底下的键抢走 → 表现为"拖不过去/被弹开"）
					var bestKey:String = null;
					var bestDist:Float = 1e30;
					for (key in MobileControls.CUSTOM_ORDER)
					{
						var zones:Array<FlxSprite> = preview.padButtons.get(key);
						if (zones == null || zones.length == 0) continue;
						for (zone in zones)
						{
							if (!touchInLogical(touch, zone.x, zone.y, zone.width, zone.height)) continue;
							var cx:Float = zone.x + zone.width / 2;
							var cy:Float = zone.y + zone.height / 2;
							var p:FlxPoint = FlxPoint.get();
							var cam:FlxCamera = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
							touch.getPositionInCameraView(cam, p);
							var d:Float = (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy);
							p.put();
							if (d < bestDist) { bestDist = d; bestKey = key; }
						}
					}
					if (bestKey != null)
					{
						dragging = bestKey;
						dragID = touch.touchPointID;
					}
					break;
				}
			}
			else
			{
				for (touch in FlxG.touches.list)
				{
					if (touch.touchPointID != dragID) continue;
					if (touch.pressed)
					{
						var zones:Array<FlxSprite> = preview.padButtons.get(dragging);
						if (zones != null && zones.length > 0)
						{
							// 拖动跟随同样按本状态相机视图坐标（暂停入口 camOther）
							var p:FlxPoint = FlxPoint.get();
							var cam:FlxCamera = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
							touch.getPositionInCameraView(cam, p);
							zones[0].x = FlxMath.bound(p.x - MobileControls.BTN_W / 2, 0, FlxG.width - MobileControls.BTN_W);
							zones[0].y = FlxMath.bound(p.y - MobileControls.BTN_H / 2, 0, FlxG.height - MobileControls.BTN_H);
							p.put();
						}
					}
					if (touch.justReleased)
					{
						dragging = null;
						dragID = -1;
					}
				}
			}
			updatePosTexts();
		}

		// 拖动期间不响应 UI 点击：防止拖动路径扫过"保存并退出/恢复默认/切换布局"时误触发
		if (dragging == null)
		{
			if (uiTapped(leftArrowRect)) changeMode(-1);
			if (uiTapped(rightArrowRect)) changeMode(1);
			if (uiTapped(resetBtn)) resetPositions();
			if (uiTapped(exitBtn)) { saveAndExit(); return; }
			if (uiTapped(backBtn)) { saveAndExit(); return; }
		}

		#if android
		if (FlxG.android.justReleased.BACK) { saveAndExit(); return; }
		#end
	}
}
