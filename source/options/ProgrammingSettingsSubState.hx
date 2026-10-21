package options;

/**
 * 「编程」分区（系统域）。
 *
 * 本分区现有两组东西：
 *  ① **Meteoric 脚本系统**（编程层）：1 个总开关 + 4 个分项开关。
 *     脚本本体是 HScript，放在模组的 `scripting/` 目录里，规范见 `PROGRAMMING.md`。
 *  ② 两项 PE 0.6.3 兼容开关（原先放在「音符」分区，集中到这里）。
 *
 * 历史：这里原先还有一整套 **CNE 式 HScript 编程层**开关（总开关 / 状态脚本 / 全局脚本 /
 * `ModState` / 界面重定向 / 脚本热重载 / 脚本类 / 脚本日志）与「CNE 模组兼容」开关，共 9 项；
 * 连同 `source/cne/` 下的全部实现已于 2026-10-05 **移除**（CNE 作者反对把引擎功能移植到其它引擎）。
 * 模组侧唯一残留是 `backend/CneModProbe` —— 只在 Mods 界面识别并提示「这是 CNE 格式」，
 * 不加载、不解析、不转换任何 CNE 资源。
 *
 * 设计契约：选项定义只有一份 —— 主设置 `OptionsState` 以 headless 方式构造本类、
 * 暂停内设置以正常实例打开，两条路径共用本表（与其余 BaseOptionsMenu 子类同款），
 * 禁止在宿主里另抄一份。
 *
 * ⚠ 构造顺序与兄弟分区一致：`title` 与全部 `addOption()` 都在 `super()` **之前**。
 *   原因：`BaseOptionsMenu.new()` 末尾会调 `changeSelection()`，它读 `optionsArray.length`；
 *   若 `super()` 在前，此时 `optionsArray` 还是 null（`addOption` 才惰性建表）→ 空引用崩溃。
 *   本文件原先把 `super()` 放在开头，从暂停菜单打开「编程」分区会崩（2026-10-21 修复）。
 */
class ProgrammingSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
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

		// ===== Meteoric 脚本系统（编程层）=====
		// 总开关 + 4 个分项开关。全部默认关闭 —— 关闭时引擎行为与该功能落地前完全一致。
		var option:Option = new Option('脚本系统（总开关）',
			'开启 Meteoric 脚本系统：允许用 HScript 写脚本改玩法 / 界面。\n脚本放在模组的 scripting/ 目录里，改完按 F5 立即生效，不用重开游戏。\n关闭时引擎行为与没有这个功能完全一致。',
			'scriptingEnabled',
			'bool');
		addOption(option);

		var option:Option = new Option('全局常驻脚本',
			'加载 scripting/global/*.hx：这些脚本跨所有界面常驻运行（能收到节拍、状态切换、焦点、窗口尺寸等引擎级事件）。\n需要先打开「脚本系统（总开关）」。',
			'scriptingGlobalScripts',
			'bool');
		addOption(option);

		var option:Option = new Option('状态脚本（覆盖界面）',
			'加载 scripting/states/<界面名>.hx：让脚本接管某个界面（菜单、暂停、设置……），可改它的控件与行为。\n需要先打开「脚本系统（总开关）」。',
			'scriptingStateScripts',
			'bool');
		addOption(option);

		var option:Option = new Option('脚本热重载',
			'开启后：F5 = 重建当前界面的状态脚本，Shift+F5 = 重建全局脚本。\n脚本自己创建的对象要在 destroy() 里清理，否则会残留。\n需要先打开「脚本系统（总开关）」。',
			'scriptingHotReload',
			'bool');
		addOption(option);

		var option:Option = new Option('可取消事件',
			'让脚本能拦截引擎的关键决策点（音符生成、命中、评级、谱面事件、结算……）：\n脚本可以改参数，也可以 event.cancel() 接管默认行为。\n需要先打开「脚本系统（总开关）」。',
			'scriptingEvents',
			'bool');
		addOption(option);

		// ⚠ super() 必须在最后（见类头注释：changeSelection() 会读 optionsArray）
		super();
	}
}