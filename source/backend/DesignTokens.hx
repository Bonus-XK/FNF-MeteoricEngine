package backend;

import flixel.util.FlxColor;

/**
 * Meteoric 设计令牌中心（主题色功能的唯一色彩来源）
 *
 * 设计依据：skills/meteoric-design「MD3 Tokens — 固定色板（无壁纸动态取色）」+
 *          skills/README.md「取色策略：固定色板 + 设置内用户可选主题色」。
 *
 * 规则：
 *  - 色板为**固定 10 色**，玩家在 设置 → 界面 → 主题色 里选（存 ClientPrefs.data.themeIndex）。
 *  - 切换色板时**三个强调令牌同步派生**：primary / secondary / tertiary
 *    （primary = 选中/聚焦/链接；secondary = 次强调/特殊状态；tertiary = 品牌点缀）。
 *  - surface / outline / 判定色 / 成功失败语义色**不参与**主题化
 *    （判定色与 success/error 是内容语义色，见 meteoric-design 例外条款）。
 *  - 任何界面都必须在**创建时**读令牌，禁止每帧重新取色/重绘（mobile skill 性能红线）。
 *
 * themeIndex 0（青）的 primary = 0xFF9CE8FF，与主题色功能上线前
 * ControlsSubState / OutdatedState / CreditsState 使用的字面量完全一致（强调色零变化）；
 * 但 menuDesat 背景 tint 已改为跟随色板（原为历史品红，见 MENU_TINTS 注释）。
 */
class DesignTokens
{
	/** 色板条目上限（脚本 API 的 index 上限，越界会被夹取） */
	public static final THEME_COUNT:Int = 10;

	// ===== 令牌（运行时随主题色变化，界面创建时读取；不要缓存到局部 static final）=====

	/** 主强调：选中/聚焦/激活/链接（MD3 primary） */
	public static var primary(default, null):FlxColor = 0xFF9CE8FF;

	/** 次强调：特殊状态/提示/次强调（MD3 secondary） */
	public static var secondary(default, null):FlxColor = 0xFFFFD9A0;

	/** 品牌点缀：少用（MD3 tertiary；默认等于 primary） */
	public static var tertiary(default, null):FlxColor = 0xFFEA71FD;

	/** 系统域背景 menuDesat 的 tint（随色板变化，等价于当前主题的 primary；见 MENU_TINTS） */
	// 初始值必须与 THEME 0 的 primary 一致，否则 applyTheme 之前的取色会不一致
	public static var menuTint(default, null):FlxColor = 0xFF9CE8FF;

	/**
	 * 系统域「圆角磨砂玻璃面板」的填充底色 —— 由当前主题色 primary 轻微着色派生
	 * （不透明底 0xFF161622 混 10% primary，α 保持 0xCC 不变）。
	 * 21 处 makePanel 的默认值即引用本令牌，故面板随主题色改变**无需改动任何调用点**。
	 */
	public static var panelFill(default, null):FlxColor = 0xCC161622;

	/** 面板描边（白 27%，不随主题色变，避免彩边抢戏） */
	public static var panelOutline(default, null):FlxColor = 0x45FFFFFF;

	/**
	 * 面板内「选中/激活」高亮（selectorBar、选中行）—— 由 primary 低透明度派生。
	 * 原为纯白 0x3AFFFFFF（23%）：主题化后保留白色分量，使下层令牌色透出来，
	 * 视觉上即主题色高亮，同时不改变既有明度关系（白 30% + primary 42%）。
	 */
	public static var rowHighlight(default, null):FlxColor = 0x3AFFFFFF;

	/** 面板内「悬浮」高亮（比选中更轻，MD3 hover 层） */
	public static var rowHover(default, null):FlxColor = 0x2EFFFFFF;

	// ===== 色板定义（顺序 = 设置里的显示顺序；index 0 为默认）=====
	// 命名对齐 FNF 常见配色习惯：青 / 蓝 / 紫 / 品红 / 橙 / 金 / 绿 / 青绿 / 红 / 粉
	public static final THEME_KEYS:Array<String> = [
		'cyan', 'blue', 'purple', 'magenta', 'orange', 'gold', 'green', 'teal', 'red', 'pink'
	];

	public static final THEME_NAMES:Array<String> = [
		'青（默认）', '蓝', '紫', '品红', '橙', '金', '绿', '青绿', '红', '粉'
	];

	/** 每套主题的 primary（主强调） */
	static final PRIMARY_COLORS:Array<FlxColor> = [
		0xFF9CE8FF, // 青（默认，= 上线前字面量）
		0xFF7CB8FF, // 蓝
		0xFFB79CFF, // 紫
		0xFFF08CF0, // 品红
		0xFFFFB27A, // 橙
		0xFFFFD98A, // 金
		0xFF8FE8A8, // 绿
		0xFF6EE0D8, // 青绿
		0xFFFF9A9A, // 红
		0xFFFFA8CC  // 粉
	];

	/** 每套主题的 secondary（次强调） */
	static final SECONDARY_COLORS:Array<FlxColor> = [
		0xFFFFD9A0, // 青 → 暖金（历史 secondary，保持不变）
		0xFFFFD9A0, // 蓝
		0xFFFFD9A0, // 紫
		0xFFFFD9A0, // 品红
		0xFFFFE3B8, // 橙 → 更浅的暖色，避免与 primary 撞色
		0xFFFFE8B8, // 金
		0xFFFFF0B8, // 绿 → 浅黄
		0xFFC8F0FF, // 青绿 → 浅青
		0xFFFFD0D0, // 红 → 浅红
		0xFFFFDCEB  // 粉 → 浅粉
	];

	/** 每套主题的 tertiary（品牌点缀） */
	static final TERTIARY_COLORS:Array<FlxColor> = [
		0xFFEA71FD, // 青 → 品牌紫（= OptionsState 历史 tint，保持不变）
		0xFFC9A6FF, // 蓝 → 薰衣草
		0xFFE0C4FF, // 紫 → 浅紫
		0xFFFFC4E8, // 品红 → 浅玫红
		0xFFFFD2B0, // 橙 → 浅杏
		0xFFFFF0B0, // 金 → 浅金
		0xFFD6FFC8, // 绿 → 浅绿
		0xFFC8FFF4, // 青绿 → 浅碧
		0xFFFFC8C8, // 红 → 浅红
		0xFFFFD6EA  // 粉 → 浅粉
	];

	/**
	 * 每套主题的 menuDesat 背景 tint —— **与 PRIMARY_COLORS 同值**。
	 *
	 * ⚠ 曾经把 index 0 设成历史值品红 0xFFEA71FD（理由：保持旧观感、避免功能性回归），
	 * 但主题色是**用户主动选择**的：选「青」却得到品红底色，前后矛盾且被实测吐槽
	 * （2026-09-11「按下青色后背景变成 FNF 最原始的紫色」）。
	 * 结论：色板是显式选择时，背景必须跟随所选的色板色，不做"向后兼容"的特殊照顾。
	 */
	static final MENU_TINTS:Array<FlxColor> = [
		0xFF9CE8FF, // 青（默认，= primary，不再用品红）
		0xFF7CB8FF, 0xFFB79CFF, 0xFFF08CF0, 0xFFFFB27A,
		0xFFFFD98A, 0xFF8FE8A8, 0xFF6EE0D8, 0xFFFF9A9A, 0xFFFFA8CC
	];

	// ===== 运行时状态 =====
	/** 当前生效的主题索引（-1 表示非法/未初始化，读取时回退 0） */
	public static var themeIndex(default, null):Int = 0;

	/** 是否被脚本临时覆盖（true 时设置页保存不会覆盖玩家的临时覆盖语义，仅记录） */
	public static var scriptOverride(default, null):Bool = false;

	/**
	 * 主题色变更监听者（监听者模式，供 UI 组件同步选中态）。
	 * 为什么不用"每帧比对 themeIndex 变了没"：主题色是低频事件，轮询会造成无谓的每帧开销，
	 * 而 mobile skill 的性能红线明确禁止在 update 里做无谓工作。
	 */
	static var themeListeners:Array<Void->Void> = [];

	/** 注册主题变更监听（必须在 destroy 时用 removeThemeListener 摘掉，否则会对已销毁的精灵调用） */
	public static function addThemeListener(fn:Void->Void):Void
	{
		if (fn == null) return;
		if (!themeListeners.contains(fn)) themeListeners.push(fn);
	}

	public static function removeThemeListener(fn:Void->Void):Void
	{
		if (fn == null) return;
		themeListeners.remove(fn);
	}

	/**
	 * 清空全部监听者。
	 * 用途：界面销毁路径的兜底清理 —— 监听表是静态的，任何忘记摘除的组件都会留下僵尸回调。
	 */
	public static function clearThemeListeners():Void
	{
		themeListeners = [];
	}

	/** 主题色已变更后派发给监听者（索引未变化时也派发：脚本可能改的是同索引但要求强制刷新） */
	static function notifyThemeListeners():Void
	{
		if (themeListeners.length < 1) return;
		// 复制一份再遍历：回调内部可能注册/注销监听，避免遍历中被改写
		var snapshot:Array<Void->Void> = themeListeners.copy();
		for (fn in snapshot)
		{
			if (fn != null) fn();
		}
	}

	/**
	 * 应用主题色。
	 * @param index      色板索引（自动夹取到 0..THEME_COUNT-1，非法值回退 0）
	 * @param byScript   是否由脚本调用（仅用于标记 scriptOverride，不影响取色结果）
	 * @param saveToPrefs 是否写入玩家存档（设置页 = true；脚本默认 false，传 true 才持久化）
	 */
	public static function applyTheme(?index:Null<Int>, byScript:Bool = false, saveToPrefs:Bool = false):Void
	{
		// 注意：静态平台上 Int 不能为 null，所以可空入口必须显式声明为 Null<Int>
		var idx:Int = 0;
		if (index != null) idx = index;
		if (idx < 0 || idx >= THEME_COUNT) idx = 0;

		themeIndex = idx;
		scriptOverride = byScript;

		primary = PRIMARY_COLORS[idx];
		secondary = SECONDARY_COLORS[idx];
		tertiary = TERTIARY_COLORS[idx];
		menuTint = MENU_TINTS[idx];
		panelFill = derivePanelFill(primary);
		rowHighlight = withAlpha(primary, 0.42);
		rowHover = withAlpha(primary, 0.30);

		if (saveToPrefs && ClientPrefs.data != null)
		{
			ClientPrefs.data.themeIndex = idx;
			ClientPrefs.saveSettings();
		}

		// 派发给 UI 监听者（色块选择器同步选中态等）
		notifyThemeListeners();
	}

	/**
	 * 从存档读取并应用主题色。
	 * 调用时机：ClientPrefs.loadPrefs() 数据就绪之后（存档缺失该字段时保留默认 0）。
	 */
	public static function initFromPrefs():Void
	{
		var idx:Int = 0;
		if (ClientPrefs.data != null) idx = ClientPrefs.data.themeIndex;
		applyTheme(idx, false, false);
	}

	/** 当前主题名（设置页显示 / 脚本查询）；index 省略或越界 → 用当前主题 */
	public static function themeName(?index:Null<Int>):String
	{
		var i:Int = themeIndex;
		if (index != null) i = index;
		if (i < 0 || i >= THEME_COUNT) i = 0;
		return THEME_NAMES[i];
	}

	/** 当前主题 key（英文，供脚本/调试比对）；index 省略或越界 → 用当前主题 */
	public static function themeKey(?index:Null<Int>):String
	{
		var i:Int = themeIndex;
		if (index != null) i = index;
		if (i < 0 || i >= THEME_COUNT) i = 0;
		return THEME_KEYS[i];
	}

	/** 色板全部显示名（脚本查询用，返回副本避免外部改写） */
	public static function allThemeNames():Array<String>
	{
		return THEME_NAMES.copy();
	}

	/** 全部主题的 primary 列表（供色块选择器渲染；返回副本避免外部改写） */
	public static function primaryPalette():Array<FlxColor>
	{
		return PRIMARY_COLORS.copy();
	}

	/** 面板底色：不透明深底 0xFF161622 混 10% 主题色（保留原 α 0xCC） */
	static function derivePanelFill(primaryColor:FlxColor):FlxColor
	{
		var mixed:Null<FlxColor> = FlxColor.interpolate((0xFF161622 : FlxColor), primaryColor, 0.10);
		if (mixed == null) return 0xCC161622;
		// 注意：FlxColor 的 RED/GREEN/BLUE 是**颜色常量**而非通道掩码，没有 .r/.g/.b 字段；
		// 这里用算术提取通道，0xCC 是被有意丢弃的（保留面板原有 α）。
		return ((0xCC << 24) | (((Std.int(mixed) >> 16) & 0xFF) << 16)
			| (((Std.int(mixed) >> 8) & 0xFF) << 8) | (Std.int(mixed) & 0xFF));
	}

	/** 给颜色套一个 0..1 的透明度（保留 RGB，替换 α） */
	static function withAlpha(color:FlxColor, alpha:Float):FlxColor
	{
		var a:Int = Std.int(Math.max(0, Math.min(1, alpha)) * 255);
		var v:Int = Std.int(color);
		return ((a << 24) | (v & 0xFFFFFF));
	}
}
