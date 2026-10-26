package backend;

import openfl.Lib;
import flixel.FlxG;

/**
 * 渲染后端管理（Vulkan 实验性轨道的引擎侧入口，仅桌面端由 TitleState 调用）。
 *
 * ── 语义（如实，勿夸大）────────────────────────────────────────
 * 主画面渲染（OpenFL/Flixel 显示列表）目前只有 OpenGL 一种实现 ——
 * OpenFL 截至 9.5.2 没有 Vulkan 渲染器。
 *
 * rendererBackend 存档值控制 **Vulkan 子系统**：
 *  - 'opengl'（默认）：什么都不做，行为与本功能落地前完全一致；
 *  - 'vulkan'：启动时创建 Vulkan 窗口（lime ≥8.4）走完整引导
 *    （loader→instance→surface→device→swapchain）并枚举物理设备；
 *    失败（旧 lime / 无 Vulkan 运行时 / macOS 未装 MoltenVK）→ 自动回退。
 *
 * ── Vulkan 画面镜像（rendererVulkanMirror，默认关）──────────────
 *  Vulkan 子系统就绪且镜像开启时：
 *   · Vulkan 窗口转为可见（1280×720，标题 Meteoric · Vulkan Mirror）；
 *   · 每帧（30fps 节流）从 GL 帧缓冲回读引擎画面（录像系统同款快路径：
 *     持久缓冲 + context.gl.readPixels，零逐帧分配），
 *     单趟完成「垂直翻转 + RGBA→BGRA 通道交换 + 最近邻缩放」，
 *     经 VKRenderer.setOverlayImage 上传并由 MoltenVK 在 Vulkan 交换链上呈现。
 *   · 这是引擎画面第一次真正由 Vulkan 呈现（主渲染仍为 OpenGL）。
 *
 * ── 兼容性 ──────────────────────────────────────────────────────
 * 全程 Reflect / 动态调用 + try/catch：lime 8.2.2（现行基座）上这些字段
 * 与分支不存在，自然落入回退路径；lime-meteoric（8.4 fork）上为真实现。
 */
class RendererBackend
{
	/** 实际生效状态：'opengl'（默认或回退）| 'vulkan'（子系统就绪）。 */
	public static var active(default, null):String = 'opengl';
	/** 状态细节：成功 = 物理设备名；失败 = 原因（供日志与后续 UI 显示）。 */
	public static var statusDetail(default, null):String = '';
	/** Vulkan 画面镜像是否在运行（每帧由 mirrorTick 置位/失效时清零）。 */
	public static var mirrorRunning(default, null):Bool = false;

	/**
	 * 隐藏 Vulkan 探测窗（成功时保留为子系统驻留句柄；镜像开启时转为可见的镜像窗口）。
	 * 强引用防 GC：lime Window 是原生资源的包装，被 GC 收走会悬垂。
	 */
	static var vulkanWindow:Dynamic = null;

	// ═══════════ 镜像态（全部持久缓冲，稳态零分配） ═══════════
	static var mirrorRenderer:Dynamic = null; // lime.graphics.vulkan.VKRenderer
	static var mirrorBuf:haxe.io.Bytes = null; // overlay 目标缓冲（mirrorW×mirrorH×4 BGRA，自管）
	static var glCtx:Dynamic = null; // NativeOpenGLRenderContext（快路径回读）
	static var frameBuf:haxe.io.Bytes = null; // GL 回读持久缓冲（fbW×fbH RGBA）
	static var framePtr:Dynamic = null; // lime.utils.DataPointer（静态平台不可空，存 Dynamic）
	static var fbW:Int = 0; // 物理帧缓冲尺寸（Retina 下为逻辑 2x）
	static var fbH:Int = 0;
	static var mirrorW:Int = 1280;
	static var mirrorH:Int = 720;
	static var lastMirrorStamp:Float = 0;
	static var mirrorTickAttached:Bool = false;
	static var overlayFn:Dynamic = null; // CFFI lime_vulkan_renderer_set_overlay（6 参，原生 __MULT）
	static var renderFn:Dynamic = null; // CFFI lime_vulkan_renderer_render（__MULT 约定入口）

	/** TitleState.create 在 ClientPrefs.loadPrefs() 之后调用一次。 */
	public static function init():Void
	{
		active = 'opengl';
		statusDetail = '';
		mirrorRunning = false;

		// 默认路径零开销（一次字符串比较）——「新功能默认关闭、零行为变化」
		if (ClientPrefs.data == null || ClientPrefs.data.rendererBackend != 'vulkan')
			return;

		var vkCtx:Dynamic = null;
		try
		{
			vkCtx = probeVulkan();
		}
		catch (e:Dynamic)
		{
			fallback(Lang.tOr('renderer.initException', '初始化异常: ') + Std.string(e));
			return;
		}

		if (vkCtx == null)
			return; // probeVulkan 内部已走 fallback

		if (ClientPrefs.data.rendererVulkanMirror)
			setupMirror(vkCtx);
	}

	/**
	 * 探测 + 建立 Vulkan 子系统。返回 VulkanRenderContext（失败时内部走 fallback 并返回 null）。
	 * lime 的 Vulkan 绑定是窗口耦合的：VK.createInstance 必须传 VulkanRenderContext，
	 * 所以「探测可用性」= 真开一个隐藏窗口试试（hidden，8×8）。
	 */
	static function probeVulkan():Dynamic
	{
		var app:Dynamic = Lib.application;
		if (app == null || Reflect.field(app, 'createWindow') == null)
		{
			fallback(Lang.tOr('renderer.noWindowApi', '无窗口创建入口（lime 过旧？）'));
			return null;
		}

		// RenderContextType 是 enum abstract（from String）→ 直接传 'vulkan' 字符串即可。
		// 镜像模式从创建时就是「可见 + 目标尺寸 + 镜像标题」：lime Window 的
		// visible/width/height/title 都是纯属性（无存储字段），hxcpp 的
		// Reflect.setProperty 与 untyped 赋值都会抛 "Invalid field"（实测），
		// 事后改属性此路不通，只能在一开始就按需求建。
		var mirrorWanted:Bool = ClientPrefs.data != null && ClientPrefs.data.rendererVulkanMirror == true;
		var attrs:Dynamic = {
			width: mirrorWanted ? 1280 : 8,
			height: mirrorWanted ? 720 : 8,
			title: mirrorWanted ? 'Meteoric Vulkan Mirror' : 'Meteoric Vulkan',
			hidden: !mirrorWanted,
			resizable: true,
			context: {type: 'vulkan', hardware: true}
		};

		var win:Dynamic = Reflect.callMethod(app, Reflect.field(app, 'createWindow'), [attrs]);
		var ctx:Dynamic = (win != null) ? Reflect.field(win, 'context') : null;
		var vkCtx:Dynamic = (ctx != null) ? Reflect.field(ctx, 'vulkan') : null;

		if (win == null || vkCtx == null)
		{
			// Vulkan 引导失败（无运行时 / lime 不支持）：关掉探测窗走回退。
			closeWindow(win);
			fallback(Lang.tOr('renderer.bootstrapFail', 'Vulkan 窗口引导失败（需要 Vulkan 运行时；macOS 为 MoltenVK）'));
			return null;
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
			return null;
		}

		vulkanWindow = win; // 保留驻留句柄（镜像会把它转为可见窗口）
		active = 'vulkan';
		statusDetail = (deviceName != null && deviceName.length > 0) ? deviceName : Lang.tOr('renderer.readyName', 'Vulkan 就绪');
		// 日志拆两行：主行语言包（括号成对不落在拼接缝上），设备行 ASCII 标签。
		trace(Lang.tOr('renderer.logReady', '[Renderer] Vulkan 子系统就绪；主画面渲染仍为 OpenGL（OpenFL 尚无 Vulkan 渲染器）'));
		if (deviceName != null && deviceName.length > 0)
			trace('  device: ' + deviceName);
		return vkCtx;
	}

	// ═══════════════════════════════════════════════════════════════
	// Vulkan 画面镜像
	// ═══════════════════════════════════════════════════════════════

	static function setupMirror(vkCtx:Dynamic):Void
	{
		var __stage:String = 'enter';
		try
		{
			// 快路径回读：与 VideoRecorder 同款（context.gl + 持久缓冲 + DataPointer）。
			// 物理帧缓冲尺寸（Retina 下 = 逻辑 2x）多重来源：
			//   ① GL viewport（lime 8.4 实测可能返回 0x0，不可单独依赖）
			//   ② 主窗口逻辑尺寸 × window.scale（内容缩放，Retina=2.0）
			__stage = 'gl';
			var mainWin:Dynamic = Lib.application.window;
			glCtx = Reflect.field(mainWin.context, 'gl');
			if (glCtx == null)
				throw 'no gl context';
			fbW = 0;
			fbH = 0;
			try
			{
				var vp:Dynamic = Reflect.callMethod(glCtx, Reflect.field(glCtx, 'getParameter'), [Reflect.field(glCtx, 'VIEWPORT')]);
				if (Std.isOfType(vp, Array) && vp.length >= 4)
				{
					fbW = Std.int(vp[2]);
					fbH = Std.int(vp[3]);
				}
			}
			catch (e:Dynamic) {}
			if (fbW <= 0 || fbH <= 0)
			{
				var scaleF:Float = 1.0;
				try
				{
					var s:Dynamic = Reflect.field(mainWin, 'scale');
					if (s != null && s > 0) scaleF = s;
				}
				catch (e:Dynamic) {}
				fbW = Std.int(FlxG.stage.stageWidth * scaleF);
				fbH = Std.int(FlxG.stage.stageHeight * scaleF);
			}
			if (fbW <= 0 || fbH <= 0)
				throw 'framebuffer size ' + fbW + 'x' + fbH;
			__stage = 'alloc';
			frameBuf = haxe.io.Bytes.alloc(fbW * fbH * 4);
			framePtr = lime.utils.DataPointer.fromBytes(frameBuf);

			// 窗口可见性/尺寸/标题已在探测期按镜像需求创建（见 probeVulkan 注释），
			// 此处不再事后改属性（hxcpp 属性反射不可写）。

			// VKRenderer：C++ 侧完整的 instance/device/swapchain/overlay 呈现器。
			// ⚠ 不走 vkCtx.createRenderer()（其内部 NativeCFFI 静态绑定在引擎构建形态下
			//   抛 Null Function Pointer，沙盒却正常——绑定环节不可靠）。
			// ⚠ CFFI.load 的 arity 1..5 入口也不能用：ExternalPrimitive::__Run 按
			//   prim_mult 约定 (args*, nargs) 调用，与 __N 工厂给出的直调签名 wrap
			//   错位，会把 nargs 当 value 解引用（实测 SIGSEGV @0x2，见
			//   ExternalInterface.cpp 的 __MULT 注释）。故一律用 __MULT 入口
			//   （args=-1 → __loadprim 拼 "__MULT"）；6 参的 set_overlay 原生即 MULT。
			__stage = 'createRenderer';
			var __winHandle:Dynamic = Reflect.field(vkCtx, '__windowHandle');
			if (__winHandle == null)
				throw 'no window handle on VulkanRenderContext';
			var __createFn:Dynamic = lime.system.CFFI.load('lime', 'lime_vulkan_renderer_create', -1);
			if (__createFn == null)
				throw 'CFFI.load(lime_vulkan_renderer_create) failed';
			overlayFn = lime.system.CFFI.load('lime', 'lime_vulkan_renderer_set_overlay', 6);
			renderFn = lime.system.CFFI.load('lime', 'lime_vulkan_renderer_render', -1);
			if (overlayFn == null || renderFn == null)
				throw 'CFFI.load(set_overlay/render) failed';
			mirrorRenderer = Reflect.callMethod(__createFn, __createFn, [__winHandle, 'Meteoric Vulkan Mirror']);
			if (mirrorRenderer == null)
			{
				var __errFn:Dynamic = lime.system.CFFI.load('lime', 'lime_vulkan_renderer_get_last_error', 0);
				var __err:Dynamic = (__errFn != null) ? __errFn() : null;
				throw 'createRenderer failed: ' + Std.string(__err);
			}

			// overlay 目标缓冲：直接自管 haxe.io.Bytes（mirrorW×mirrorH×4），不走 lime 的
			// Image.readPixels/resize —— 它们内部的 CFFI 静态绑定在引擎构建形态下同样
			// 抛 Null Function Pointer（实测卡在 stage=resize，与 createRenderer 同款）。
			// 此后逐帧原地改写、零分配。
			__stage = 'allocBuf';
			mirrorBuf = haxe.io.Bytes.alloc(mirrorW * mirrorH * 4);
			if (mirrorBuf == null || mirrorBuf.length < mirrorW * mirrorH * 4)
				throw 'mirror buffer alloc failed';

			if (!mirrorTickAttached)
			{
				FlxG.signals.postDraw.add(mirrorTick);
				mirrorTickAttached = true;
			}
			mirrorRunning = true;
			trace(Lang.tOr('renderer.mirrorOn', '[Renderer] Vulkan 画面镜像已开启')
				+ ' (' + mirrorW + 'x' + mirrorH + ' <- ' + fbW + 'x' + fbH + ')');
		}
		catch (e:Dynamic)
		{
			mirrorRunning = false;
			mirrorRenderer = null;
			mirrorBuf = null;
			glCtx = null;
			frameBuf = null;
			framePtr = null;
			trace(Lang.tOr('renderer.mirrorFail', '[Renderer] Vulkan 画面镜像开启失败：') + '[stage=' + __stage + '] ' + Std.string(e));
		}
	}

	/**
	 * 每帧钩子（FlxG.signals.postDraw，主画面绘制完成后 GL 帧缓冲内容有效）。
	 * 30fps 节流；单趟像素变换完成「垂直翻转（GL 自下而上）+ RGBA→BGRA（MoltenVK
	 * 交换链为 BGRA8）+ 最近邻缩放」，然后 overlay 上传 + present。
	 */
	static function mirrorTick():Void
	{
		if (!mirrorRunning)
			return;

		var now:Float = haxe.Timer.stamp();
		if (now - lastMirrorStamp < 1.0 / 30.0)
			return;
		lastMirrorStamp = now;

		try
		{
			Reflect.callMethod(glCtx, Reflect.field(glCtx, 'readPixels'),
				[0, 0, fbW, fbH, Reflect.field(glCtx, 'RGBA'), Reflect.field(glCtx, 'UNSIGNED_BYTE'), framePtr]);

			var src:haxe.io.Bytes = frameBuf;
			var dst:haxe.io.Bytes = mirrorBuf;
			var stepX:Float = fbW / mirrorW;
			var stepY:Float = fbH / mirrorH;
			for (my in 0...mirrorH)
			{
				var srcRow:Int = Std.int((mirrorH - 1 - my) * stepY) * fbW;
				var dstRow:Int = my * mirrorW;
				var sxF:Float = 0;
				for (mx in 0...mirrorW)
				{
					var si:Int = (srcRow + Std.int(sxF)) << 2;
					var di:Int = (dstRow + mx) << 2;
					dst.set(di, src.get(si + 2)); // B
					dst.set(di + 1, src.get(si + 1)); // G
					dst.set(di + 2, src.get(si)); // R
					dst.set(di + 3, 255); // A（引擎画面含透明区时钳到不透明）
					sxF += stepX;
				}
			}

			// overlay 上传 + 呈现：走 CFFI 原语（Reflect.callMethod → __Run → prim_mult
			// 约定，与 __MULT 入口匹配）。set_overlay 收 haxe.io.Bytes（BGRA 已就地
			// 写入 mirrorBuf，尺寸 mirrorW×mirrorH）。
			var __ok:Bool = Reflect.callMethod(overlayFn, overlayFn,
				[mirrorRenderer, mirrorBuf, mirrorW, mirrorH, 0, 0]);
			if (!__ok)
				throw 'set_overlay failed';
			Reflect.callMethod(renderFn, renderFn, [mirrorRenderer, 0.05, 0.05, 0.08, 1.0]);
		}
		catch (e:Dynamic)
		{
			mirrorRunning = false;
			trace(Lang.tOr('renderer.mirrorFrameFail', '[Renderer] Vulkan 镜像帧失败，本会话已停用镜像：') + Std.string(e));
		}
	}

	static function closeWindow(win:Dynamic):Void
	{
		if (win == null)
			return;
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
