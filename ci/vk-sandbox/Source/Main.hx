package;

import lime.app.Application;
import lime.graphics.RenderContext;
import lime.graphics.VulkanRenderContext;
import lime.graphics.vulkan.VK;
import lime.graphics.vulkan.VKInstance;
import lime.system.System;

/**
 * Meteoric Vulkan 沙盒（阶段 1）。
 *
 * 目标：证明 lime 8.4 develop 的 Vulkan 引导链在 macOS + MoltenVK 上完整可用：
 *   Vulkan 窗口 → VulkanRenderContext → VK.createInstance → 枚举物理设备 → 300 帧存活。
 *
 * 不做任何绘制（lime 的 VKRenderer 本来就没有管线/绘制调用）——
 * 窗口活着 + 设备枚举日志 = 引导链证明完毕。窗口能否出画面取决于
 * VKRenderer 的清屏/present 路径，属于额外收益，不作验收条件。
 */
class Main extends Application
{
	var frames:Int = 0;
	var instance:VKInstance = null;

	public function new()
	{
		super();
	}

	override function onWindowCreate():Void
	{
		var ctx:RenderContext = window.context;
		trace('[sandbox] window context type = ' + ctx.type);

		var vk:VulkanRenderContext = ctx.vulkan;
		if (vk == null)
		{
			trace('[sandbox] X 不是 Vulkan 窗口（context.vulkan = null）—— 检查 renderer="vulkan" 与 MoltenVK 加载');
			return;
		}

		trace('[sandbox] OK VulkanRenderContext 就绪');
		var exts:Array<String> = vk.getInstanceExtensions();
		trace('[sandbox] surface 所需 instance extensions: ' + exts.join(', '));

		instance = VK.createInstance(vk, 'Meteoric VK Sandbox');
		if (instance == null)
		{
			trace('[sandbox] X VK.createInstance 失败: ' + VK.getLastError());
			return;
		}
		trace('[sandbox] OK VkInstance 创建成功');

		var devs = instance.enumeratePhysicalDevices();
		trace('[sandbox] 物理设备 ' + devs.length + ' 个:');
		for (d in devs)
			trace('  - ' + d.name + ' | Vulkan ' + d.apiVersionString + ' | ' + d.deviceTypeName);
	}

	override function update(deltaTime:Int):Void
	{
		super.update(deltaTime);
		frames++;
		// 300 帧（约 5 秒 @60fps）后自动退出 —— 脚本化验证，不用人工关窗口
		if (frames == 300)
		{
			trace('[sandbox] 300 帧存活，Vulkan 引导链验证完成，退出');
			System.exit(0);
		}
	}
}
