package options;
import backend.Lang;

import objects.MenuText;


class Option
{
	public var child:MenuText;
	public var text(get, set):String;
	public var onChange:Void->Void = null; //Pressed enter (on Bool type options) or pressed/held left/right (on other types)

	public var type(get, default):String = 'bool'; //bool, int (or integer), float (or fl), percent, string (or str)
	// Bool will use checkboxes
	// Everything else will use a text

	public var scrollSpeed:Float = 50; //Only works on int/float, defines how fast it scrolls per second while holding left/right
	/** 存档变量名（ClientPrefs 字段）。
	 *  对外**只读**：这是与语言无关的稳定标识，多语言 key 也以它为准
	 *  （见 Lang：key = `option.` + variable），因此不能允许外部改写。 */
	public var variable(default, null):String = null; //Variable from ClientPrefs.hx
	public var defaultValue:Dynamic = null;

	public var curOption:Int = 0; //Don't change this
	public var options:Array<String> = null; //Only used in string type
	public var displayOptions:Array<String> = null; //Only used in string type：与 options 一一对应的显示名（不改变存储值，用于中文化显示）
	public var changeValue:Dynamic = 1; //Only used in int/float/percent type, how much is changed when you PRESS
	public var minValue:Dynamic = null; //Only used in int/float/percent type
	public var maxValue:Dynamic = null; //Only used in int/float/percent type
	public var decimals:Int = 1; //Only used in float/percent type

	public var displayFormat:String = '%v'; //How String/Float/Percent/Int values are shown, %v = Current value, %d = Default value
	/**
	 * 可选：把存储值转成显示文本（优先级高于 displayFormat / displayOptions）。
	 * 用于「存储是 Int/字符串，但展示必须是人类可读名」的选项，例如主题色存索引 0..9 而显示色板名。
	 * 只影响显示，**不写回存储值**。
	 */
	public var displayFormatter:Dynamic->String = null;

	/**
	 * 可选：值位置显示的**固定提示文案**（优先于真实值），用于「值是一大长串、行内放不下」的选项
	 * （如 Score 栏格式），改为提示可交互的入口。只影响显示，不写回存储值。
	 * 优先级：valueHint > displayFormatter > displayFormat / displayOptions。
	 */
	public var valueHint:String = null;
	public var description:String = '';
	public var name:String = 'Unknown';

	/** 构造时传入的**原文**（未本地化）。语言切换后 relocalize() 靠它重新取译文 ——
	 *  否则已构造的选项会一直显示切语言之前的那一份文本。 */
	private var originName:String = null;
	private var originDesc:String = null;

	public function new(name:String, description:String = '', variable:String, type:String = 'bool', ?options:Array<String> = null)
	{
		this.variable = variable;
		// ===== 多语言：选项名/说明按「存档变量名」派生 key（option.<variable>）=====
		// 用 tOr 而非 t：语言包里还没有这个 key 时，显示这里传进来的中文原文，
		// 与多语言功能上线前**逐字一致**（零视觉回归）；补进语言包后自动切换。
		// 这样做的收益：10 个设置子页几百条选项文案**一处接入**全部生效，
		// 不用逐个子页改代码 —— key 天然稳定（存档字段名，与语言无关）。
		this.originName = name;
		this.originDesc = description;
		this.name = Lang.tOr('option.' + variable, name);
		this.description = Lang.tOr('optionDesc.' + variable, description);
		this.type = type;
		this.defaultValue = Reflect.getProperty(ClientPrefs.defaultData, variable);
		this.options = options;

		// string 档位的显示名表：自动按「存档变量名 + 档位下标」派生 key
		// （optionValue.<variable>.<i>）。
		// 关键：**options 仍是存档值，一个字都不改**（改了就破坏旧存档兼容性）；
		// 本地化只发生在 displayOptions 这张显示表上，由 OptionValue.display() 消费。
		// 例：timeBarType 存 '剩余时间'，英文界面显示 'Remaining'，存档不受影响。
		// 调用方若显式给了 displayOptions（见 LanguageSettingsSubState）则以那份为准。
		if (type == 'string' && options != null && displayOptions == null)
		{
			displayOptions = [];
			for (i in 0...options.length)
				displayOptions.push(Lang.tOr('optionValue.' + variable + '.' + i, options[i]));
		}

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

	/**
	 * 语言切换后**就地重取译文**（由 Option 宿主在 Lang 监听回调里对所有已构造选项调用）。
	 *
	 * 为什么需要：选项名/说明是在**构造期**用 Lang.tOr 解析的，而分区实例（含 headless
	 * 构造的那些）会长期存活 —— 不重取的话，用户在设置里切了语言，当前界面还是旧语言。
	 *
	 * 用构造时存下的 originName/originDesc 重新解析，因此**不会丢原文**：
	 * 语言包里没有该 key 时依旧显示原文（零回归）。
	 */
	public function relocalize():Void
	{
		if (originName != null) name = Lang.tOr('option.' + variable, originName);
		if (originDesc != null) description = Lang.tOr('optionDesc.' + variable, originDesc);
		if (type == 'string' && options != null && displayOptions != null)
		{
			for (i in 0...options.length)
				if (i < displayOptions.length)
					displayOptions[i] = Lang.tOr('optionValue.' + variable + '.' + i, options[i]);
		}
	}

	public function getValue():Dynamic
	{
		return Reflect.getProperty(ClientPrefs.data, variable);
	}
	public function setValue(value:Dynamic)
	{
		Reflect.setProperty(ClientPrefs.data, variable, value);
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