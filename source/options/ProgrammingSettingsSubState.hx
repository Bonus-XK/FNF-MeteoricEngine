package options;

/**
 * 「编程」分区（系统域）。
 *
 * 本分区是 Meteoric 编程能力的唯一设置入口：
 *  - CNE 式 HScript 编程层总开关（cneScripting）；
 *  - 状态脚本 / 全局脚本 / ModState / 界面重定向 / 热重载 / 脚本类与日志；
 *  - 原先放在「音符」分区的 PE 0.6.3 兼容项（psych063Mode / luaUse063Compat）集中到这里。
 *
 * 设计契约：
 *  - 选项定义只有一份：主设置 `OptionsState` 以 headless 方式构造本类、暂停内设置以正常实例打开，
 *    两条路径共用本表（与其余 BaseOptionsMenu 子类同款），禁止在宿主里另抄一份。
 *  - 所有编程层开关默认保守：`cneScripting` 关闭时，引擎行为与改动前完全一致
 *    （不加载 CNE 风格脚本、不注册状态改写钩子、不挂热重载检测）。
 *  - 子项在总开关关闭时仍可见，靠说明文字提示“需先开启编程层”，不引入新的禁用态样式。
 */
class ProgrammingSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		super();

		title = '编程';
		rpcTitle = '编程设置菜单';

		var option:Option = new Option('CNE 式 HScript 编程层',
			'总开关。开启后 Meteoric 会加载 CNE 风格的 HScript 编程层：\n'
			+ '状态脚本（data/states/<界面类名>/LIB_<mod>.hx）、全局脚本（data/global/LIB_<mod>.hx）、\n'
			+ 'ModState/ModSubState、界面重定向与脚本热重载。\n'
			+ '⚠ 脚本可访问 Sys/File 等引擎能力，只对你信任的 mod 开启；关闭时零行为变化。',
			'cneScripting',
			'bool');
		addOption(option);

		var option:Option = new Option('状态脚本',
			'允许每个引擎界面加载自己的 HScript：data/states/<界面类名>/LIB_<mod>.hx。\n'
			+ '脚本可挂 create/update/stepHit/beatHit/destroy 等钩子（需先开启编程层）。',
			'cneStateScripts',
			'bool');
		addOption(option);

		var option:Option = new Option('全局脚本',
			'允许常驻 HScript：data/global/LIB_<mod>.hx。\n'
			+ '全局脚本跨界面运行，可用于全局 UI、事件总线和整局游戏逻辑（需先开启编程层）。',
			'cneGlobalScripts',
			'bool');
		addOption(option);

		var option:Option = new Option('ModState / ModSubState',
			'允许用 HScript 写完整界面：new ModState("MyState") / new ModSubState("MySubState")。\n'
			+ '脚本放在 data/states/MyState/LIB_<mod>.hx；这是“不编译引擎也能做独立游戏”的核心入口。',
			'cneModStates',
			'bool');
		addOption(option);

		var option:Option = new Option('界面重定向',
			'允许 mod 用 flags.ini 的 [StateRedirects] / [StateRedirects.force] 把引擎界面\n'
			+ '替换成自己的 HScript 界面。会改写状态切换请求，风险较高，默认关闭。',
			'cneStateRedirects',
			'bool');
		addOption(option);

		var option:Option = new Option('脚本热重载',
			'开启后：F5 重载当前界面脚本；Shift+F5 重建全局脚本。\n'
			+ '第一版走 CNE 忠实语义（F5 会重进当前界面/关卡），不重启游戏。',
			'cneHotReload',
			'bool');
		addOption(option);

		var option:Option = new Option('脚本定义/继承类',
			'允许 HScript 在脚本里定义 class 并继承引擎类（SScript EX 模式）。\n'
			+ '关闭可降低脚本误用引擎内部结构的风险。',
			'cneScriptClasses',
			'bool');
		addOption(option);

		var option:Option = new Option('脚本加载日志',
			'开启后在控制台打印脚本加载/销毁/重载记录，便于调试（默认关闭，避免刷屏）。',
			'cneScriptLogs',
			'bool');
		addOption(option);

		var option:Option = new Option('CNE 模组兼容',
			'让 Codename Engine 格式的 mod 在 Meteoric 里加载（默认关闭）：\n'
			+ '· 谱面 songs/<song>/charts/<难度>.json（自动转成 psych_v1）；\n'
			+ '· 音频 songs/<song>/song/Inst|Voices[-难度]；\n'
			+ '· 人物 data/characters/<名字>.xml（自动转成 Psych 人物 JSON）；\n'
			+ '· 周目 data/weeks/weeks/<周目>.xml（出现在 Story/Freeplay）；\n'
			+ '· mods/ 下的 .zip 包（首次使用时自动解到 mods/_cnestage/，可在 Mod 列表里识别）。\n'
			+ '⚠ 未覆盖：CNE 舞台 data/stages/*.xml、人物 .hx 扩展、data/notes/*.hx 自定义音符行为。',
			'cneModCompat',
			'bool');
		addOption(option);

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
