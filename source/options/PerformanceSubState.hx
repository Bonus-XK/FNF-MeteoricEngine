package options;

/**
 * H-Slice 移植：音符管线性能设置页。
 * 默认值全部按"大谱面最优"设定，普通谱面不受影响。
 */
class PerformanceSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '性能';
		rpcTitle = '性能设置菜单';

		var option:Option = new Option('堆叠音符合并',
			'开启后，同一轨道在 ±合并窗口 内的重复箭头会合并为一个音符（用 density 计数），\n'
			+ '15 万级堆叠谱面的解析与渲染开销大幅下降；正常谱面没有重复箭头，不受影响',
			'skipGhostNotes',
			'bool');
		addOption(option);

		option = new Option('合并计数模式',
			'开启：合并后按箭头数量计分/计数（分数、连击、Miss 与真实箭头一致）；\n关闭：重复箭头直接丢弃（H-Slice 幽灵模式）',
			'ghostDensity',
			'bool');
		addOption(option);

		option = new Option('合并窗口（毫秒）',
			'同轨时间差不超过该值的箭头视为堆叠。15 建议值；调大可合并更多，调小更保守',
			'ghostRange',
			'float');
		option.changeValue = 1;
		option.decimals = 0;
		option.minValue = 0;
		option.maxValue = 100;
		addOption(option);

		option = new Option('已过音符不再生成',
			'开启后，跳转时间/快速重开时已过出生窗口的音符被静默消费（不判 Miss、不溅射），\n'
			+ '配合快速跳谱使用；普通游玩逐帧生成不受影响',
			'optimizeSpawnNote',
			'bool');
		addOption(option);

		option = new Option('快速跳谱（二分）',
			'开启后，跳转时间时用二分查找整段跳过已过音符，替代逐条移除（15 万级谱面跳转不再卡顿）',
			'bulkSkip',
			'bool');
		addOption(option);

		option = new Option('可见音符快速排序',
			'开启后每帧只对可见音符排序（绘制顺序），大谱面下排序开销降为 O(可见数)。\n'
			+ '默认关闭以保持与旧版完全一致的绘制顺序',
			'fastSort',
			'bool');
		addOption(option);

		option = new Option('场上音符上限',
			'限制同时存在的音符对象数量（0 = 不限）。堆叠谱面防爆内存时使用；\n'
			+ '达到上限时后来的音符会被丢弃（不判判定）',
			'limitNotes',
			'int');
		option.changeValue = 500;
		option.minValue = 0;
		option.maxValue = 100000;
		addOption(option);

		option = new Option('重叠隐藏间距',
			'同一轨道上间距小于该值的后一个音符会被隐藏（渲染裁剪，不参与判定），\n'
			+ '0 = 关闭。开启后可显著降低极端堆叠谱的渲染开销',
			'hideOverlapped',
			'float');
		option.changeValue = 10;
		option.decimals = 0;
		option.minValue = 0;
		option.maxValue = 500;
		addOption(option);

		option = new Option('自动游玩排期命中',
			'开启后，自动游玩命中走"生成即排期、到点入队"架构（大谱面 100% 覆盖的核心）。
关闭则回退逐帧入队（旧行为，密集谱覆盖下降）',
			'botplayScheduledHits',
			'bool');
		addOption(option);

		option = new Option('排期弹出余量（毫秒）',
			'弹出窗 = 帧步长 + 余量。必须 ≥ 回收窗，否则先杀后弹造成漏命中；
帧率越低建议越大 = 可测帧步长（1000/FPS）',
			'botplayPopMargin',
			'int');
		option.changeValue = 1;
		option.minValue = 0;
		option.maxValue = 60;
		addOption(option);

		option = new Option('自动游玩回收窗（毫秒）',
			'未命中箭头在判定线后的存活时间（越小柱子越贴线；< 弹出余量会竞态漏命中）',
			'botplayKillWindow',
			'int');
		option.changeValue = 1;
		option.minValue = 2;
		option.maxValue = 60;
		addOption(option);

		option = new Option('生成回调 onSpawnNote',
			'关闭后生成音符不再触发 Lua/Hscript 的 onSpawnNote（15 万级堆叠谱可省去海量回调开销）；\n'
			+ '若模组脚本依赖该回调请保持开启',
			'spawnNoteEvent',
			'bool');
		addOption(option);

		super();
	}
}
