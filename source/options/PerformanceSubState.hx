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

		// ===== JS Engine（JordanSantiagoYT/FNF-JS-Engine 优化页）移植 =====
		option = new Option('只显示 HUD',
			'开启后仅渲染音符与 HUD（角色/舞台/雨效等全场景不渲染，舞台脚本也跳过），帧率大幅提升；\n'
			+ '依赖舞台视觉或舞台脚本的模组请保持关闭',
			'hudOnly',
			'bool');
		addOption(option);

		option = new Option('启用 GC',
			'关闭可消除 GC 尖峰（内存可能上升）；默认开启与旧版一致',
			'enableGC',
			'bool');
		addOption(option);

		option = new Option('对手箭头点亮',
			'对手命中时 strum 是否高亮 confirm；关闭省一点绘制',
			'opponentLightStrum',
			'bool');
		addOption(option);

		option = new Option('自动游玩箭头点亮',
			'自动游玩命中时玩家 strum 是否高亮 confirm；关闭省绘制',
			'botLightStrum',
			'bool');
		addOption(option);

		option = new Option('玩家箭头点亮',
			'手动命中/按下时玩家 strum 是否高亮；关闭省绘制',
			'playerLightStrum',
			'bool');
		addOption(option);

		option = new Option('评分弹窗',
			'命中时是否创建评级弹窗（Sick/Good…）；关闭后仍正常计分，只少视觉',
			'ratingPopups',
			'bool');
		addOption(option);

		option = new Option('连击弹窗',
			'命中时是否创建连击数字与 Combo 词；关闭后仍正常计连击',
			'comboPopups',
			'bool');
		addOption(option);

		option = new Option('自动游玩省资源',
			'自动游玩时只计分/评级，不创建评分连击弹窗（少精灵创建与 GC 压力）',
			'lessBotLag',
			'bool');
		addOption(option);

		option = new Option('关闭命中回调',
			'命中音符不再触发 goodNoteHit/opponentNoteHit 的 Lua/Hscript 回调；\n'
			+ '依赖这些回调的模组（如计分/特效脚本）请保持开启',
			'noHitFuncs',
			'bool');
		addOption(option);

		super();
	}
}
