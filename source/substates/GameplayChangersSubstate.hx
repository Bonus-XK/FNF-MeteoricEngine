package substates;

import objects.BackButton;
import flixel.math.FlxPoint;
import flixel.util.FlxSpriteUtil;

class GameplayChangersSubstate extends MusicBeatSubstate
{
	// ===== 布局常量（磨砂圆角风格，与暂停/结算界面一致） =====
	static final TITLE_Y:Float = 22;
	static final PANEL_X:Float = 200;
	static final PANEL_Y:Float = 100;
	static final PANEL_W:Float = 880;
	static final PANEL_H:Float = 470;
	static final ROW_X:Float = 244;
	static final ROW_START_Y:Float = 150;
	static final MAX_ROW_GAP:Float = 48;
	static final VALUE_RIGHT:Float = 1032;
	static final HINT_Y:Float = 600;

	var curOption:GameplayOption = null;
	var curSelected:Int = 0;
	var optionsArray:Array<Dynamic> = [];

	var grpLabels:Array<FlxText> = [];
	var grpValues:Array<FlxText> = [];
	var grpValueLast:Array<String> = [];
	var selectorBar:FlxSprite;
	var selectorTween:FlxTween;
	var backBtn:BackButton;
	var rowGap:Float = MAX_ROW_GAP; // 行距随选项数量自动收缩，保证最后一行不超出面板

	var mouseActive:Bool = true;  // 鼠标跟随是否激活（键盘操作时冻结，鼠标移动/点击时恢复）
	var mouseLockX:Float = 0;
	var mouseLockY:Float = 0;

	var nextAccept:Int = 5;
	var holdTime:Float = 0;
	var holdValue:Float = 0;

	function getOptions()
	{
		var goption:GameplayOption = new GameplayOption('Scroll Type', 'scrolltype', 'string', 'multiplicative', ["multiplicative", "constant"]);
		optionsArray.push(goption);

		var option:GameplayOption = new GameplayOption('Scroll Speed', 'scrollspeed', 'float', 1);
		option.scrollSpeed = 2.0;
		option.minValue = 0.35;
		option.changeValue = 0.05;
		option.decimals = 2;
		if (goption.getValue() != "constant")
		{
			option.displayFormat = '%vX';
			option.maxValue = 3;
		}
		else
		{
			option.displayFormat = "%v";
			option.maxValue = 6;
		}
		optionsArray.push(option);

		#if !html5
		var option:GameplayOption = new GameplayOption('Playback Rate', 'songspeed', 'float', 1);
		option.scrollSpeed = 1;
		option.minValue = 0.5;
		option.maxValue = 3.0;
		option.changeValue = 0.05;
		option.displayFormat = '%vX';
		option.decimals = 2;
		optionsArray.push(option);
		#end

		var option:GameplayOption = new GameplayOption('Health Gain Multiplier', 'healthgain', 'float', 1);
		option.scrollSpeed = 2.5;
		option.minValue = 0;
		option.maxValue = 5;
		option.changeValue = 0.1;
		option.displayFormat = '%vX';
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('Health Loss Multiplier', 'healthloss', 'float', 1);
		option.scrollSpeed = 2.5;
		option.minValue = 0.5;
		option.maxValue = 5;
		option.changeValue = 0.1;
		option.displayFormat = '%vX';
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('Instakill on Miss', 'instakill', 'bool', false);
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('Opponent Push', 'opponentpush', 'bool', false);
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('God Mode', 'practice', 'bool', false);
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('AutoPlay', 'botplay', 'bool', false);
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('Infinite Loop', 'infiniteloop', 'bool', false);
		optionsArray.push(option);
	}

	public function getOptionByName(name:String)
	{
		for(i in optionsArray)
		{
			var opt:GameplayOption = i;
			if (opt.name == name)
				return opt;
		}
		return null;
	}

	public function new()
	{
		super();

		// 固定渲染在专用相机上：zoom=1、scroll=(0,0)，暂停时不受游戏相机缩放影响
		var settingsCam:FlxCamera = (PlayState.instance != null && PlayState.instance.camOther != null) ? PlayState.instance.camOther : FlxG.camera;
		cameras = [settingsCam];

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.6;
		add(bg);

		// ---- 标题 ----
		var titleText:FlxText = new FlxText(0, TITLE_Y, FlxG.width, '游玩设置', 48);
		titleText.scrollFactor.set();
		titleText.setFormat(Paths.font('future.ttf'), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		add(titleText);

		// ---- 磨砂面板 ----
		var panel:FlxSprite = makePanel(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 20);
		add(panel);

		// ---- 选中高亮条 ----
		selectorBar = makePanel(PANEL_X + 16, rowYFor(0) - 4, PANEL_W - 32, 40, 12, 0x2EFFFFFF, null);
		add(selectorBar);

		getOptions();

		// 自动适配行距：所有选项（含最后一行与选中条）都完整落在面板内
		rowGap = Math.min(MAX_ROW_GAP, Math.max(30, (PANEL_H - 40 - (ROW_START_Y - PANEL_Y)) / Math.max(1, optionsArray.length - 1)));

		// ---- 选项行（标签左对齐，数值右对齐） ----
		for (i in 0...optionsArray.length)
		{
			var opt:GameplayOption = optionsArray[i];

			var lbl:FlxText = new FlxText(ROW_X, rowYFor(i), 0, translateName(opt.name), 24);
			lbl.scrollFactor.set();
			lbl.setFormat(Paths.font('future.ttf'), 24, 0xFFA9A9B8, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5;
			lbl.antialiasing = ClientPrefs.data.antialiasing;
			lbl.updateHitbox();
			add(lbl);
			grpLabels.push(lbl);

			var val:FlxText = new FlxText(VALUE_RIGHT, rowYFor(i), 0, '', 24);
			val.scrollFactor.set();
			val.setFormat(Paths.font('future.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			val.borderSize = 1.5;
			val.antialiasing = ClientPrefs.data.antialiasing;
			add(val);
			grpValues.push(val);
			grpValueLast.push('');
			updateValue(i);
		}

		// ---- 返回按钮 + 操作提示 ----
		backBtn = new BackButton(FlxG.width - 72, 12);
		add(backBtn.glow);
		add(backBtn.spr);
		add(backBtn.label);

		var hintText:FlxText = new FlxText(0, HINT_Y, FlxG.width, '← → 调整数值 · 回车 开关 · R 重置 · ESC 返回', 18);
		hintText.scrollFactor.set();
		hintText.setFormat(Paths.font('future.ttf'), 18, 0xFFA9A9B8, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = ClientPrefs.data.antialiasing;
		add(hintText);

		changeSelection();
		FlxG.mouse.visible = true;
	}

	function rowYFor(i:Int):Float
	{
		return ROW_START_Y + (i * rowGap);
	}

	function makePanel(x:Float, y:Float, w:Float, h:Float, ?radius:Float = 20, ?fill:Int = 0xCC161622, ?border:Int = 0x45FFFFFF):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, radius, radius, fill);
		if(border != null)
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, radius, radius, FlxColor.TRANSPARENT, {color: border, thickness: 1.5});
		spr.scrollFactor.set();
		return spr;
	}

	function translateName(name:String):String
	{
		switch (name)
		{
			case 'Scroll Type': return '滚动方式';
			case 'Scroll Speed': return '滚动速度';
			case 'Playback Rate': return '播放速率';
			case 'Health Gain Multiplier': return '血量回复倍率';
			case 'Health Loss Multiplier': return '血量损失倍率';
			case 'Instakill on Miss': return '失误即死';
			case 'Opponent Push': return '对方推条';
			case 'God Mode': return '上帝模式';
			case 'AutoPlay': return '自动游玩';
			case 'Infinite Loop': return '无限轮回';
		}
		return name;
	}

	// 数值文本只在内容变化时才重绘
	function updateValue(i:Int):Void
	{
		var opt:GameplayOption = optionsArray[i];
		var newText:String;
		if (opt.type == 'bool')
		{
			newText = (opt.getValue() == true) ? '开' : '关';
		}
		else if (opt.type == 'string')
		{
			switch (Std.string(opt.getValue()))
			{
				case 'multiplicative': newText = '乘法';
				case 'constant': newText = '恒定';
				default: newText = Std.string(opt.getValue());
			}
		}
		else
		{
			var text:String = opt.displayFormat;
			var val:Dynamic = opt.getValue();
			if(opt.type == 'percent') val *= 100;
			var def:Dynamic = opt.defaultValue;
			newText = text.replace('%v', val).replace('%d', def);
		}

		if (grpValueLast[i] != newText)
		{
			grpValueLast[i] = newText;
			var txt:FlxText = grpValues[i];
			txt.text = newText;
			txt.updateHitbox();
			txt.x = VALUE_RIGHT - txt.width;
		}
	}

	// 改动即时同步到正在游玩的 PlayState（自动生效）
	function applyChanges():Void
	{
		if (PlayState.instance != null)
			PlayState.instance.syncGameplaySettings();
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
			var hoveredID:Int = getHoveredOptionID(mousePos.x, mousePos.y);

			// 悬停只高亮不切换
			for (i in 0...grpLabels.length)
			{
				var hovered:Bool = (i == hoveredID);
				grpLabels[i].color = hovered ? 0xFFD7D7E0 : (i == curSelected ? FlxColor.WHITE : 0xFF9A9AA8);
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
				FlxG.sound.play(Paths.sound('scrollMenu'));
				changeSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
			}

			backBtn.setHovered(mousePos.x, mousePos.y);
			if (FlxG.mouse.justPressed && backBtn.over(mousePos.x, mousePos.y))
			{
				mousePos.put();
				close();
				ClientPrefs.saveSettings();
				FlxG.sound.play(Paths.sound('cancelMenu'));
				return;
			}

			if (FlxG.mouse.justPressed && hoveredID >= 0)
			{
				mouseActive = true;
				if (hoveredID != curSelected)
				{
					changeSelection(hoveredID - curSelected);
				}
				else if (curOption.type != 'key')
				{
					if (curOption.type == 'bool')
					{
						FlxG.sound.play(Paths.sound('scrollMenu'));
						curOption.setValue((curOption.getValue() == true) ? false : true);
						curOption.change();
						updateValue(curSelected);
						applyChanges();
					}
					else
					{
						changeOptionValue(1);
					}
				}
			}
		}
		mousePos.put();

		if (controls.BACK)
		{
			close();
			ClientPrefs.saveSettings();
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		if (nextAccept <= 0)
		{
			if (curOption.type == 'bool')
			{
				if (controls.ACCEPT)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'));
					curOption.setValue((curOption.getValue() == true) ? false : true);
					curOption.change();
					updateValue(curSelected);
					applyChanges();
				}
			}
			else if (controls.UI_LEFT || controls.UI_RIGHT)
			{
				var pressed = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
				if (holdTime > 0.5 || pressed)
				{
					if (pressed)
					{
						changeOptionValue(controls.UI_LEFT ? -1 : 1);
					}
					else if (curOption.type != 'string')
					{
						holdValue = Math.max(curOption.minValue, Math.min(curOption.maxValue, holdValue + curOption.scrollSpeed * elapsed * (controls.UI_LEFT ? -1 : 1)));

						switch(curOption.type)
						{
							case 'int':
								curOption.setValue(Math.round(holdValue));

							case 'float' | 'percent':
								var blah:Float = Math.max(curOption.minValue, Math.min(curOption.maxValue, holdValue + curOption.changeValue - (holdValue % curOption.changeValue)));
								curOption.setValue(FlxMath.roundDecimal(blah, curOption.decimals));
						}
						updateValue(curSelected);
						curOption.change();
						applyChanges();
					}
				}

				if(curOption.type != 'string') {
					holdTime += elapsed;
				}
			}
			else if(controls.UI_LEFT_R || controls.UI_RIGHT_R)
			{
				clearHold();
			}

			if (controls.RESET)
			{
				for (i in 0...optionsArray.length)
				{
					var leOption:GameplayOption = optionsArray[i];
					leOption.setValue(leOption.defaultValue);
					if(leOption.type != 'bool')
					{
						if(leOption.type == 'string')
						{
							leOption.curOption = leOption.options.indexOf(leOption.getValue());
						}
						updateValue(i);
					}
					else updateValue(i);

					if(leOption.name == 'Scroll Speed')
					{
						leOption.displayFormat = "%vX";
						leOption.maxValue = 3;
						if(leOption.getValue() > 3)
						{
							leOption.setValue(3);
						}
						updateValue(i);
					}
					leOption.change();
				}
				FlxG.sound.play(Paths.sound('cancelMenu'));
				applyChanges();
			}
		}

		if(nextAccept > 0) {
			nextAccept -= 1;
		}
	}

	function changeOptionValue(dir:Int = 1)
	{
		var add:Dynamic = null;
		if(curOption.type != 'string') {
			add = (dir < 0) ? -curOption.changeValue : curOption.changeValue;
		}

		switch(curOption.type)
		{
			case 'int' | 'float' | 'percent':
				holdValue = curOption.getValue() + add;
				if(holdValue < curOption.minValue) holdValue = curOption.minValue;
				else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;

				switch(curOption.type)
				{
					case 'int':
						holdValue = Math.round(holdValue);
						curOption.setValue(holdValue);

					case 'float' | 'percent':
						holdValue = FlxMath.roundDecimal(holdValue, curOption.decimals);
						curOption.setValue(holdValue);
				}

			case 'string':
				var num:Int = curOption.curOption;
				num += dir;

				if(num < 0) {
					num = curOption.options.length - 1;
				} else if(num >= curOption.options.length) {
					num = 0;
				}

				curOption.curOption = num;
				curOption.setValue(curOption.options[num]);
		}
		if (curOption.name == 'Scroll Type')
		{
			var speedOpt:GameplayOption = getOptionByName('Scroll Speed');
			if (speedOpt != null)
			{
				if (curOption.getValue() == 'constant')
				{
					speedOpt.displayFormat = '%v';
					speedOpt.maxValue = 6;
				}
				else
				{
					speedOpt.displayFormat = '%vX';
					speedOpt.maxValue = 3;
					if (speedOpt.getValue() > 3) speedOpt.setValue(3);
				}
				updateValue(optionsArray.indexOf(speedOpt));
			}
		}
		updateValue(curSelected);
		curOption.change();
		applyChanges();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function clearHold()
	{
		if(holdTime > 0.5) {
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		holdTime = 0;
	}

	function getHoveredOptionID(mouseX:Float, mouseY:Float):Int
	{
		for (i in 0...grpLabels.length)
		{
			var rowY:Float = rowYFor(i);
			if (mouseX >= PANEL_X + 24 && mouseX <= PANEL_X + PANEL_W - 24
				&& mouseY >= rowY - 8 && mouseY <= rowY + 36)
				return i;
		}
		return -1;
	}

	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0)
			curSelected = optionsArray.length - 1;
		if (curSelected >= optionsArray.length)
			curSelected = 0;

		for (i in 0...grpLabels.length)
		{
			var selected:Bool = (i == curSelected);
			grpLabels[i].alpha = selected ? 1 : 0.6;
			grpLabels[i].color = selected ? FlxColor.WHITE : 0xFF9A9AA8;
			grpValues[i].alpha = grpLabels[i].alpha;
		}

		curOption = optionsArray[curSelected];

		if (selectorBar != null)
		{
			if(selectorTween != null) {
				selectorTween.cancel();
				selectorTween = null;
			}
			var barY:Float = rowYFor(curSelected) - 4;
			if(selectorBar.y != barY)
				selectorTween = FlxTween.tween(selectorBar, {y: barY}, 0.12, {ease: FlxEase.cubeOut});
		}

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	override function destroy()
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}

class GameplayOption
{
	private var child:MenuText;
	public var text(get, set):String;
	public var onChange:Void->Void = null; //Pressed enter (on Bool type options) or pressed/held left/right (on other types)

	public var type(get, default):String = 'bool'; //bool, int (or integer), float (or fl), percent, string (or str)
	// Bool will use checkboxes
	// Everything else will use a text

	public var showBoyfriend:Bool = false;
	public var scrollSpeed:Float = 50; //Only works on int/float, defines how fast it scrolls per second while holding left/right

	private var variable:String = null; //Variable from ClientPrefs.hx's gameplaySettings
	public var defaultValue:Dynamic = null;

	public var curOption:Int = 0; //Don't change this
	public var options:Array<String> = null; //Only used in string type
	public var changeValue:Dynamic = 1; //Only used in int/float/percent type, how much is changed when you PRESS
	public var minValue:Dynamic = null; //Only used in int/float/percent type
	public var maxValue:Dynamic = null; //Only used in int/float/percent type
	public var decimals:Int = 1; //Only used in float/percent type

	public var displayFormat:String = '%v'; //How String/Float/Percent/Int values are shown, %v = Current value, %d = Default value
	public var name:String = 'Unknown';

	public function new(name:String, variable:String, type:String = 'bool', defaultValue:Dynamic = 'null variable value', ?options:Array<String> = null)
	{
		this.name = name;
		this.variable = variable;
		this.type = type;
		this.defaultValue = defaultValue;
		this.options = options;

		if(defaultValue == 'null variable value')
		{
			switch(type)
			{
				case 'bool':
					defaultValue = false;
				case 'int' | 'float':
					defaultValue = 0;
				case 'percent':
					defaultValue = 1;
				case 'string':
					defaultValue = '';
					if(options.length > 0) {
						defaultValue = options[0];
					}
			}
		}

		if(getValue() == null) {
			setValue(defaultValue);
		}

		switch(type)
		{
			case 'string':
				var num:Int = options.indexOf(getValue());
				if(num > -1) {
					curOption = num;
				}
	
			case 'percent':
				displayFormat = '%v%';
				changeValue = 0.01;
				minValue = 0;
				maxValue = 1;
				scrollSpeed = 0.5;
				decimals = 2;
		}
	}

	public function change()
	{
		//nothing lol
		if(onChange != null) {
			onChange();
		}
	}

	public function getValue():Dynamic
	{
		return ClientPrefs.data.gameplaySettings.get(variable);
	}
	public function setValue(value:Dynamic)
	{
		ClientPrefs.data.gameplaySettings.set(variable, value);
	}

	@:keep
	public function setChild(child:MenuText)
	{
		this.child = child;
	}

	private function get_text()
	{
		if(child != null) {
			return child.text;
		}
		return null;
	}
	private function set_text(newValue:String = '')
	{
		if(child != null) {
			child.text = newValue;
		}
		return null;
	}

	private function get_type()
	{
		var newValue:String = 'bool';
		switch(type.toLowerCase().trim())
		{
			case 'int' | 'float' | 'percent' | 'string': newValue = type;
			case 'integer': newValue = 'int';
			case 'str': newValue = 'string';
			case 'fl': newValue = 'float';
		}
		type = newValue;
		return type;
	}
}
