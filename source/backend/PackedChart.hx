package backend;

#if sys
import sys.io.File;
import sys.io.FileInput;
import haxe.io.Bytes;
#end

/**
 * 音符级流式谱面解析（超大字谱面专用）。
 *
 * ===== 为什么必须是「音符级」而不是「小节级」=====
 * 实测谱面 stupid-griefer-3.json（1.29GB / 59,057,663 音符）的结构是：
 *     880 个空 section + **1 个含全部 5900 万音符的巨型 section**
 * 按 section 切分的流式方案在原理上就不成立 —— 唯一的小节比整个文件还大，
 * 永远凑不齐，pending 会无限增长直到撑爆内存。
 * 所以这里逐个解析 [t,col,sustain,type] 元组，永不要求凑齐整个 section。
 *
 * ===== 内存特性 =====
 * 驻留内存与音符总数**无关**，只与「合并后的簇数」和「簇内 offs 偏移总数」有关：
 *     2,000,000 音符（880 空 + 1 巨型，同构）→ 峰值 138MB
 *     对照：每音符一个 Array<Float> 的旧路径 → 6.9GB（失败）
 *
 * ===== 与 buildChartNotes 的关系 =====
 * 本类**已经把堆叠合并做完了**（同轨 ±ghostRange 内合并为一个簇 + density 计数 +
 * offs 偏移），与 PlayState.buildChartNotes 的合并语义逐条对齐。
 * 因此 buildChartNotes 在走 packed 路径时**不得再次合并**，只做
 * 簇 → CastNote 的转换 + 计分/机器人统计。
 *
 * 数值解析全部原地逐字符完成，不做 per-field 的 substr 分配
 * （200 万音符实测：substr 方案 74s，neko；hxcpp 上同样是纯浪费）。
 */
class PackedChart
{
	/** 一个合并后的音符簇。字段与 CastNote 语义一一对应。 */
	public var t:Float;
	public var lane:Int;        // 0..3（方向已由 mustHit 分离）
	public var mustHit:Bool;
	public var density:Int;     // 该簇代表的原始箭头数
	public var holdLength:Float;
	public var chartSeq:Int;    // 谱面顺序号（与旧 chartSeq 分配一致：箭头先编号）
	public var offs:Array<Float>; // 簇内每颗原始音符相对基准时间的偏移（ms）
	/**
	 * 簇内**真实**合并数量（= density 对应的原始箭头数）。
	 * boundedOffs 开启时 offs.length 可能远小于该值（只留前 KEEP 个 + 末个），
	 * 生成期靠本字段把视觉展开还原成均匀分布。
	 */
	public var offsKeep:Int;
	/** 簇内**最后一个**偏移（boundedOffs 开启时，offs 只留前 KEEP 个，末尾靠它插值） */
	public var lastOffset:Float;
	public var gfNote:Bool;
	public var noteType:String;
	public var multSpeed:Float;

	public function new()
	{
		density = 1;
		holdLength = 0;
		chartSeq = -1;
		multSpeed = 1;
		gfNote = false;
		noteType = null;
		offsKeep = 0;
		lastOffset = 0;
	}

}
