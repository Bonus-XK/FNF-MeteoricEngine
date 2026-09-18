package options;

/**
 * Option 的**取值/显示**单点实现。
 *
 * 为什么必须单点：
 *  「单界面设置」宿主（OptionsPane）与存量分页（BaseOptionsMenu）必须显示同一个值、走同一套步进规则，
 *  否则同一个选项在两个入口显示/行为会漂移（仓库已多次踩过"两套行为"的坑）。
 *  显示优先级与步进规则原实现于 BaseOptionsMenu.formatValue / changeOptionValue，现抽到这里，
 *  BaseOptionsMenu 委托到本类 —— 存量行为不变，新宿主直接复用。
 */
class OptionValue
{
	/**
	 * 值文本（显示优先级：valueHint > displayFormatter > displayOptions/displayFormat）。
	 * 三者都**只影响显示，不写回存储值**；valueHint 分支刻意放在读存档之前（省一次反射）。
	 */
	public static function display(option:Option):String
	{
		if (option == null) return '';
		var text:String = option.displayFormat;
		if (option.valueHint != null) return option.valueHint;

		var val:Dynamic = option.getValue();
		if (option.displayFormatter != null)
			return option.displayFormatter(val);

		// string 类型带 displayOptions：按存储值索引显示名（如英文存储值 → 中文显示），不写回存储
		if (option.type == 'string' && option.displayOptions != null)
		{
			var idx:Int = (option.options != null) ? option.options.indexOf(Std.string(val)) : -1;
			if (idx >= 0 && idx < option.displayOptions.length)
				val = option.displayOptions[idx];
		}
		if (option.type == 'percent') val *= 100;
		var def:Dynamic = option.defaultValue;
		return text.replace('%v', Std.string(val)).replace('%d', Std.string(def));
	}

	/**
	 * 单步取值（键盘 ←/→ 点按、鼠标点击、触控 ◀▶ 点按都走这里）：
	 *  int/float/percent 按 changeValue 加减并夹取/取整；string 循环切换档位。
	 *  ⚠ 不播放音效、不触发 onChange —— 那是调用方的事（两条路径的音效/存档时机不同）。
	 */
	public static function step(option:Option, dir:Int):Void
	{
		if (option == null) return;
		switch (option.type)
		{
			case 'int' | 'float' | 'percent':
				var v:Dynamic = option.getValue();
				var num:Float = Std.parseFloat(Std.string(v)) + dir * option.changeValue;
				if (num < option.minValue) num = option.minValue;
				else if (num > option.maxValue) num = option.maxValue;

				switch (option.type)
				{
					case 'int':
						option.setValue(Math.round(num));
					case 'float' | 'percent':
						option.setValue(flixel.math.FlxMath.roundDecimal(num, option.decimals));
				}

			case 'string':
				if (option.options == null || option.options.length == 0) return;
				var idx:Int = option.curOption + dir;
				if (idx < 0) idx = option.options.length - 1;
				else if (idx >= option.options.length) idx = 0;
				option.curOption = idx;
				option.setValue(option.options[idx]);
		}
	}

	/** 当前值在 string 档位表里的下标（-1 = 不在表内）。 */
	public static function optionIndex(option:Option):Int
	{
		if (option == null || option.options == null) return -1;
		return option.options.indexOf(Std.string(option.getValue()));
	}
}
