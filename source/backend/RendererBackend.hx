package backend;

import openfl.Lib;

/**
 * 渲染后端管理（Vulkan 实验性轨道的引擎侧入口，仅桌面端由 TitleState 调用）。
 *
 * ── 语义（如实，勿夸大）────────────────────────────────────────────
 * 主画面渲染（OpenFL/Flixel 显示列表）目前只有 OpenGL 一种实现 ——
 * OpenFL 截至 9.5.2 没有 Vulkan 渲染器；lime 8.4 的 Vulkan 后端也只
 * 服务「裸 lime」窗口（VKRenderer 只有引导 + swapchain，没有绘制管线）。
 *
 * 因此 rendererBackend 存档值控制的是 **Vulkan 子系统**：
 *  - 'opengl'（默认）：什么都不做，行为与本功能落地前完全一致；
 *  - 'vulkan'：启动时创建一个隐藏的 Vulkan 窗口（lime ≥ 8.4 才支持；
 *    窗口创建会在原生侧走完整引导 loader→instance→surface→device→swapchain），
 *    作为后续 Vulkan 二开（沙盒窗口 / 离屏特效层）的驻留句柄；
 *    探测失败（旧 lime / 无 Vulkan 运行时 / macOS 未装 MoltenVK）→ 自动回退，
 *    主渲染不受任何影响。
 *
 * ── 为什么探测 = 创建隐藏窗口 ───────────────────────────────────────
 * lime 8.4 的 Vulkan Haxe 绑定是**窗口耦合**的：VK.createInstance 必须
 * 传 VulkanRenderContext（只有 Vulkan 窗口才有，CFFI 全部以 __windowHandle
 * 为锚）。没有 Vulkan 窗口就没有任何 Vulkan 入口，所以「探测可用性」
 * 只能是真开一个窗口试试（hidden，8×8，试完即关）。
 *
 * ── 兼容性 ──────────────────────────────────────────────────────────
 * 全程 Reflect / 动态调用 + try/catch：当前基座 lime 8.2.2 上这些分支
 * 不存在（context.vulkan 恒为 null），自然落入回退路径；lime-meteoric
 * （lime 8.4 fork）上为真探测。不用静态 import，保证两代 lime 下都能
 * 编译、都不炸。
 */
class RendererBackend
{
	/** 实际生效状态：'opengl'（默认或回退）| 'vulkan'（子系统就绪）。 */
	public static var active(default, null):String = 'opengl';
	/** 状态细节：成功 = 物理设备名；失败 = 原因（供日志与后续 UI 显示）。 */
	public static var statusDetail(default, null):String = '';

	/**
	 * 隐藏 Vulkan 探测窗（成功时保留为子系统驻留句柄）。
	 * 强引用防 GC：lime Window 是原生资源的包装，被 GC 收走会悬垂。
	 */
	static var vulkanWindow:Dynamic = null;

	/** TitleState.create 在 ClientPrefs.loadPrefs() 之后调用一次。 */
	public static function init():Void
	{
		active = 'opengl';
		statusDetail = '';

		// 默认路径零开销（一次字符串比较）——「新功能默认关闭、零行为变化」
		if (ClientPrefs.data == null || ClientPrefs.data.rendererBackend != 'vulkan')
			return;

		try
		{
			probeVulkan();
		}
		catch (e:Dynamic)
		{
			fallback(Lang.tOr('renderer.initException', '初始化异常: ') + Std.string(e));
		}
	}

	static function probeVulkan():Void
	{
		var app:Dynamic = Lib.application;
		if (app == null || Reflect.field(app, 'createWindow') == null)
		{
			fallback(Lang.tOr('renderer.noWindowApi', '无窗口创建入口（lime 过旧？）'));
			return;
		}

		// RenderContextType 是 enum abstract（from String）→ 直接传 'vulkan' 字符串即可
		var attrs:Dynamic = {
			width: 8,
			height: 8,
			title: 'Meteoric Vulkan',
			hidden: true,
			resizable: false,
			context: {type: 'vulkan', hardware: true}
		};

		var win:Dynamic = Reflect.callMethod(app, Reflect.field(app, 'createWindow'), [attrs]);
		var ctx:Dynamic = (win != null) ? Reflect.field(win, 'context') : null;
		var vkCtx:Dynamic = (ctx != null) ? Reflect.field(ctx, 'vulkan') : null;

		if (win == null || vkCtx == null)
		{
			// Vulkan 引导失败（无运行时 / lime 不支持）：关掉探测窗走回退。
			// close 自身也包一层 —— 半途而废的窗口 close 也可能抛。
			closeWindow(win);
			fallback(Lang.tOr('renderer.bootstrapFail', 'Vulkan 窗口引导失败（需要 Vulkan 运行时；macOS 为 MoltenVK）'));
			return;
		}

		// 二次确认 + 取设备名：走一遍 Haxe 绑定 instance → 枚举物理设备 → 释放。
		var deviceName:String = null;
		try
		{
			var vk:Dynamic = Type.resolveClass('lime.graphics.vulkan.VK');
			if (vk != null)
			{
				var inst:Dynamic = Reflect.callMethod(vk, Reflect.field(vk, 'createInstance'), [vkCtx, 'Meteoric']);
				if (inst != null)
				{
					var devs:Dynamic = Reflect.callMethod(inst, Reflect.field(inst, 'enumeratePhysicalDevices'), []);
					if (Std.isOfType(devs, Array) && devs.length > 0)
						deviceName = Std.string(Reflect.field(devs[0], 'name'));
					Reflect.callMethod(inst, Reflect.field(inst, 'dispose'), []);
				}
			}
		}
		catch (e:Dynamic)
		{
			// 窗口在但枚举失败 —— 仍视为不可用，宁回退不冒险
			closeWindow(win);
			fallback(Lang.tOr('renderer.enumerateFail', 'Vulkan 设备枚举失败: ') + Std.string(e));
			return;
		}

		vulkanWindow = win; // 保留驻留句柄（后续 Vulkan 二开的锚点）
		active = 'vulkan';
		statusDetail = (deviceName != null && deviceName.length > 0) ? deviceName : Lang.tOr('renderer.readyName', 'Vulkan 就绪');
		// 日志文案拆两行：主行走语言包（括号成对不出现在拼接缝上，见 i18n 检查第 6 条），
		// 设备名行用 ASCII 标签（无 CJK，不进覆盖检查）。
		trace(Lang.tOr('renderer.logReady', '[Renderer] Vulkan 子系统就绪；主画面渲染仍为 OpenGL（OpenFL 尚无 Vulkan 渲染器）'));
		if (deviceName != null && deviceName.length > 0)
			trace('  device: ' + deviceName);
	}

	static function closeWindow(win:Dynamic):Void
	{
		if (win == null) return;
		try
		{
			Reflect.callMethod(win, Reflect.field(win, 'close'), []);
		}
		catch (e:Dynamic) {}
	}

	static function fallback(reason:String):Void
	{
		vulkanWindow = null;
		active = 'opengl';
		statusDetail = reason;
		trace(Lang.tOr('renderer.logFallback', '[Renderer] Vulkan 不可用，已自动回退 OpenGL：') + reason);
	}
}
