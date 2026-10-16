package options;

import backend.CoolUtil;
import backend.SaveMover;

/**
 * 携带模式设置页。
 *
 * 总开关 = 引擎目录下的 `portable` 标记文件（引擎必须**读设置之前**就知道走哪条存档路径，
 * 所以不能用存档里的开关；本页的开关负责创建/删除那个文件）。
 * 数据类别勾选 = 存普通设置里，控制哪些用户数据跟着走。
 *
 * 三个「动作」条目（携带模式总开关 / 备份 / 还原）用的是一次性触发字段：
 * 勾上触发动作后立刻复位，checkbox 不会停在勾选态。
 */
class MoveState extends BaseOptionsMenu
{
	public function new()
	{
		title = '携带与备份';
		rpcTitle = '携带模式设置菜单';

		// 打开页面时用标记文件覆盖显示镜像（存档里存的值不作数）
		ClientPrefs.data.portableModeOn = CoolUtil.isPortable();

		var option:Option = new Option('携带模式',
			(ClientPrefs.data.portableModeOn ? '当前：**已开启** —— 设置、键位、高分会写到引擎目录。\n'
				: '当前：已关闭 —— 设置走系统用户目录。\n')
			+ '\n开启会在引擎目录创建 `portable` 标记文件，把整套设置、键位、高分带到 U 盘，'
			+ '插到别的电脑上直接可用。\n'
			+ '\n⚠ 改动在**下次启动**生效（存档路径在读设置之前就定死了）。\n'
			+ '关闭则删除该标记文件。',
			'portableModeOn',
			'bool');
		option.onChange = togglePortable;
		addOption(option);

		option = new Option('携带回放录像',
			'携带模式下，回放录像也放进引擎目录。\n关闭则回放留在系统用户目录（不跟着走）',
			'portableReplays',
			'bool');
		addOption(option);

		option = new Option('携带谱面缓存',
			'携带模式下，谱面缓存也放进引擎目录。\n'
			+ '⚠ 缓存动辄几 GB 且可自动重建，默认不带 —— 放 U 盘上会拖慢读写',
			'portableChartCache',
			'bool');
		addOption(option);

		option = new Option('备份到引擎目录',
			'把设置、键位、高分等打成一个 zip 放在引擎目录，文件名带时间戳。\n'
			+ '不带便携模式也能用 —— 这是把设置一次性带走的方式',
			'portableBackupAction',
			'bool');
		option.onChange = doBackup;
		addOption(option);

		option = new Option('从备份还原',
			'读取引擎目录里**最新的**那个备份 zip 并覆盖还原。\n'
			+ '⚠ 会覆盖同名文件。还原后建议重启引擎',
			'portableRestoreAction',
			'bool');
		option.onChange = doRestore;
		addOption(option);

		super();
	}

	function togglePortable():Void
	{
		var want:Bool = !ClientPrefs.data.portableModeOn;
		var now:Bool = CoolUtil.setPortable(want);
		// 以标记文件的真实结果为准（写入可能失败，比如引擎目录只读）
		ClientPrefs.data.portableModeOn = now;
		optionReset('portableModeOn');
		trace('[Move] 携带模式已' + (now ? '开启' : '关闭') + '（下次启动生效），标记文件：' + CoolUtil.portableMarkerPath());
	}

	function doBackup():Void
	{
		var p:String = SaveMover.backup(ClientPrefs.data.portableReplays, ClientPrefs.data.portableChartCache);
		optionReset('portableBackupAction');
		trace('[Move] 备份' + (p == null ? '失败（没有可备份的数据？）' : '完成：' + p));
	}

	function doRestore():Void
	{
		optionReset('portableRestoreAction');
		var z:String = SaveMover.latestBackup();
		if (z == null)
		{
			trace('[Move] 引擎目录里没有找到备份 zip');
			return;
		}
		var n:Int = SaveMover.restore(z);
		trace('[Move] 还原 ' + n + ' 个文件（来自 ' + z + '）');
	}

	/** 一次性动作触发后把字段复位，避免 checkbox 停在勾选态。 */
	function optionReset(variable:String):Void
	{
		var v:Dynamic = Reflect.field(ClientPrefs.data, variable);
		Reflect.setField(ClientPrefs.data, variable, (v is Bool) ? false : v);
		var arr:Array<Option> = getOptions();
		for (o in arr)
			if (o.variable == variable) o.setValue(Reflect.field(ClientPrefs.data, variable));
	}
}