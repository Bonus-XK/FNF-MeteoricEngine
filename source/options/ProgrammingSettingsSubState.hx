package options;

/**
 * 「编程」分区（系统域）。
 *
 * 原先这里还有一整套 **CNE 式 HScript 编程层**开关（总开关 / 状态脚本 / 全局脚本 /
 * `ModState` / 界面重定向 / 脚本热重载 / 脚本类 / 脚本日志）与「CNE 模组兼容」开关，共 9 项；
 * 连同 `source/cne/` 下的全部实现已于 2026-10-05 **移除**（CNE 作者反对把引擎功能移植到其它引擎）。
 * 模组侧唯一残留是 `backend/CneModProbe` —— 只在 Mods 界面识别并提示「这是 CNE 格式」，
 * 不加载、不解析、不转换任何 CNE 资源。
 *
 * 本分区现存两项是 PE 0.6.3 兼容开关（原先放在「音符」分区，集中到这里）。
 *
 * 设计契约：选项定义只有一份 —— 主设置 `OptionsState` 以 headless 方式构造本类、
 * 暂停内设置以正常实例打开，两条路径共用本表（与其余 BaseOptionsMenu 子类同款），
 * 禁止在宿主里另抄一份。
 */
class ProgrammingSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		super();

		title = '编程';

		var option:Option = new Option('Psych 0.6.3 兼容模式',
			'开启后，关闭强制音符烘焙，兼容 Psych Engine 0.6.3 模组的箭头贴图格式（箭头不显示时试试这个）',
			'psych063Mode',
			'bool');
		addOption(option);

		var option:Option = new Option('Lua 0.6.3 兼容',
			'开启后，Lua 脚本的停止哨兵按 Psych Engine 0.6.3 的数字约定处理（Function_Continue=0 / Function_Stop=1 / Function_StopLua=2）。\n0.6.3 老模组的 return Function_StopLua 无效（脚本停不下来）时试试这个',
			'luaUse063Compat',
			'bool');
		addOption(option);
	}
}