package substates;

/** 一行 = 标题 + 右值 + 交互类型 + 两个回调。用类而非 typedef：Haxe 的
 *  结构体里放函数类型字段容易被 `,` 解析坑到，报 "Expected }" 很难定位。 */
class BackupRow
{
	public var label:String;
	/** 非 TOGGLE 行的右值文本（导出/还原/输出目录）。TOGGLE 行不用它，开关由 ToggleSwitch 画。 */
	public var value:String;
	public var kind:BackupKind;
	/**
	 * 仅 TOGGLE 行：**读取**当前开/关状态的函数（驱动 objects.ToggleSwitch）。
	 *
	 * ⚠ 必须是「读取函数」而不是 Bool 快照：切换回调改的是权威来源
	 *   （CoolUtil 的标记文件 / ClientPrefs.data.*），快照不会自动更新 ——
	 *   刷新时拿旧快照 setOn 会把刚拨动的开关立刻按回去，表现为「拨不动」。
	 *   每次渲染现读权威来源，才可能与真实状态一致。
	 */
	public var readState:Void->Bool;
	public var onToggle:Void->Void;
	public var onAccept:Void->Void;
	/**
	 * 右值是不是「长文本」（目前只有备份输出目录那行是）。
	 * true 时界面用小字号 + 按像素宽度掐头去尾，避免长路径压到左侧标签上。
	 */
	public var longValue:Bool;

	public function new(label:String, value:String, kind:BackupKind, readState:Void->Bool, onToggle:Void->Void, onAccept:Void->Void, longValue:Bool = false)
	{
		this.label = label;
		this.value = value;
		this.kind = kind;
		this.readState = readState;
		this.onToggle = onToggle;
		this.onAccept = onAccept;
		this.longValue = longValue;
	}
}
