package options;

import backend.ClientPrefs;
import backend.Lang;

/**
 * 界面语言设置分区（设置 → 语言）。
 *
 * 语言是一个 string 选项：存储值 = 语言代码（zh / en / 社区码），
 * 显示名走 `Option.displayOptions`（与存储值一一对应、可本地化、不写回存储），
 * 所以社区语言的自称名（nativeName）能直接显示在下拉里，存档里只存稳定代码。
 *
 * 写法对齐 InterfaceSettingsSubState 的主题色选项：选项存成字段，
 * onChange 里 `getValue()` 回读（Option 本身已写入 ClientPrefs）。
 */
class LanguageSettingsSubState extends BaseOptionsMenu
{
	/** 语言选项（onChange 需回读它的值，见 onChangeLanguage） */
	var langOption:Option = null;

	public function new()
	{
		title = Lang.t('settings.language');
		rpcTitle = Lang.t('settings.language');

		var codes:Array<String> = Lang.codes();
		if (codes.length == 0) codes = [Lang.DEFAULT_LANG];

		langOption = new Option(
			Lang.t('settings.language'),
			'选择界面显示语言。中文与英文为引擎内置；\n'
			+ '社区语言包（.json）放入 Resources/languages/ 或作为 mod 的 languages/ 即可自动出现在此列表',
			'language',
			'string',
			codes);
		// 存代码、显示自称名（displayOptions 与 options 一一对应）
		langOption.displayOptions = [];
		for (code in codes) langOption.displayOptions.push(Lang.displayName(code));
		addOption(langOption);
		langOption.onChange = onChangeLanguage;

		super();
	}

	function onChangeLanguage()
	{
		if (langOption == null) return;
		var code:String = Std.string(langOption.getValue());
		// 立即切表（找不到会回落到默认语言，不抛异常）
		Lang.load(code);
		// 选项的显示名本身也可能随语言变（自称名），重建一次显示表
		var codes:Array<String> = Lang.codes();
		if (codes.length == 0) codes = [Lang.DEFAULT_LANG];
		langOption.options = codes;
		langOption.displayOptions = [];
		for (c in codes) langOption.displayOptions.push(Lang.displayName(c));
	}
}