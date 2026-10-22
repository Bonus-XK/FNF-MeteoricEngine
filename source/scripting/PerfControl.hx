package scripting;

import backend.ClientPrefs;
import backend.PerfProbe;
import flixel.FlxG;

/**
 * 性能面：脚本能**读**的性能快照 + 能**改**的受控旋钮。
 *
 * 设计约束（来自 AGENTS.md 的产品约束）：
 *  - **不许为速度吃内存**：白名单里的旋钮都不存在「用内存换速度」的方向 ——
 *    `gcBreathing` 是释放内存方向，`visualFold` / `perfMode` 只影响视觉与判定无关，
 *    `runtimePack` 是减少纹理内存方向。
 *  - **降采样完全放弃**：`textureScale` / `characterTextureScale` / `backgroundScale`
 *    刻意**不在**白名单里（脚本也不该去动它们）。
 *  - 白名单里的旋钮在设置页里都能看到（性能页 / 图像页），脚本改了用户也能在 UI 里看见同一份值。
 */
class PerfControl
{
	/** 可被脚本修改的性能旋钮白名单：名字 → 取值类型。 */
	public static final OPTIONS:Map<String, String> = [
		'gcBreathing' => 'bool', // GC 呼吸阀：进曲设最低空余水位 + 每 20s 强制一次全量回收
		'visualFold' => 'int', // 视觉折叠：0=关 / 1=75% / 2=50% / 3=25%（只影响视觉副本，不参与判定）
		'perfMode' => 'bool', // 性能模式：音符绘制走精简路径
		'runtimePack' => 'bool' // 运行时贴图密排列：减少纹理与绘制批次
	];

	/**
	 * 性能快照（只读）。
	 *
	 * 返回**匿名结构体**而不是 Map：SScript 反射拿不到 `Map` 抽象的方法
	 * （`map.get('fps')` 会抛 Null Function Pointer），结构体字段则可以直接 `st.fps` 读。
	 */
	public static function stats():Dynamic
	{
		var rss:Float = -1;
		try
		{
			rss = PerfProbe.processRSS();
		}
		catch (e:Dynamic) {}

		return {
			fps: FlxG.drawFramerate,
			elapsed: FlxG.elapsed,
			rssMB: rss,
			gcBreathing: ClientPrefs.data != null && ClientPrefs.data.gcBreathing,
			visualFold: ClientPrefs.data != null ? ClientPrefs.data.visualFold : 0,
			perfMode: ClientPrefs.data != null && ClientPrefs.data.perfMode,
			runtimePack: ClientPrefs.data != null && ClientPrefs.data.runtimePack
		};
	}

	/**
	 * 改一个受控的性能旋钮。
	 *
	 * @return true = 改成功（并已落盘）；false = 不在白名单 / 值不可用。
	 */
	public static function setOption(name:String, value:Dynamic):Bool
	{
		if (name == null || ClientPrefs.data == null) return false;

		switch (name)
		{
			case 'gcBreathing':
				ClientPrefs.data.gcBreathing = (value == true);

			case 'visualFold':
				var v:Int = Std.int(value);
				if (v < 0) v = 0;
				if (v > 3) v = 3;
				ClientPrefs.data.visualFold = v;

			case 'perfMode':
				ClientPrefs.data.perfMode = (value == true);

			case 'runtimePack':
				ClientPrefs.data.runtimePack = (value == true);

			default:
				return false;
		}

		// 副作用成对：改了存档字段就要落盘
		ClientPrefs.saveSettings();
		return true;
	}

	/**
	 * 立刻触发一次全量 GC（回收内存）。
	 *
	 * 代价：一次 20~80ms 的顿挫（与 GC 呼吸阀每 20s 强制回收同量级）。
	 * 只在 cpp 目标可用。
	 */
	public static function collectGarbage():Bool
	{
		#if cpp
		try
		{
			cpp.vm.Gc.run(true);
			return true;
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}
}
