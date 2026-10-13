package backend;

#if sys
import sys.io.File;
import sys.io.FileInput;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import StringTools;

/**
 * 音符级流式扫描器 —— **全程在 Bytes 上扫描，不产生任何 String**。
 *
 * ===== 为什么要改成 Bytes =====
 * 早期版本每块做一次 `buf += b.toString()`。Part 1（648.9MB / 78 块）在 hxcpp 上：
 *     每块 = 16MB 分块字符串 + 16MB 拼接结果 ≈ 32MB 分配
 *     78 块 ≈ **2.5GB 分配垃圾**
 * GC 来不及回收 → 实测常驻 2.7GB，而真正的数据（合并后约 4 个簇）只有几 KB。
 * 也就是说那 2.7GB 全是临时对象，**不是数据驻留** —— 流式丢弃和磁盘缓存都解决不了。
 * 本版本直接对 Bytes 做字节扫描，常驻降到与「块大小 + 未消费尾部」同阶（几十 MB），
 * 且总分配量降到块数次级别。
 *
 * ===== 为什么必须是「音符级」而不是「小节级」=====
 * 实测谱面 stupid-griefer-3.json（1.29GB / 59,057,663 音符）的结构是：
 *     880 个空 section + **1 个含全部 5900 万音符的巨型 section**
 * 按 section 切分的流式方案原理上不成立（唯一小节比整个文件还大）。
 *
 * ===== 与 buildChartNotes 的关系 =====
 * 堆叠合并在本类已完成（与 PlayState.buildChartNotes 语义逐条对齐），
 * 因此下游 buildFromPacked 不得再次合并。
 */
class PackedScanner
{
	// 状态机
	static inline var S_SEEK:Int = 0;  // 找下一个 '{'
	static inline var S_META:Int = 1;  // 小节头：mustHitSection / gfSection / sectionNotes
	static inline var S_NOTES:Int = 2; // 逐个解析音符元组

	// 分块大小。4MB：在 hxcpp 上只是 Bytes（无 UTF-16 扩张），
	// IO 次数与单块驻留的折中；未消费尾部正常只有几十字节。
	static inline var CHUNK:Int = 4 * 1024 * 1024;

	// 未消费尾部上限：只需装下**一个被切断的音符元组**（< 64 字节）。
	// 超过即说明状态机失效，必须抛错回退整读而不是吃光内存。
	static inline var CARRY_MAX:Int = 256 * 1024;

	// 字节常量（JSON 结构性字符）
	static inline var CH_LBRACE:Int = 123;  // {
	static inline var CH_RBRACE:Int = 125;  // }
	static inline var CH_LBRACK:Int = 91;   // [
	static inline var CH_RBRACK:Int = 93;   // ]
	static inline var CH_COMMA:Int = 44;    // ,
	static inline var CH_QUOTE:Int = 34;    // "
	static inline var CH_COLON:Int = 58;    // :
	static inline var CH_BACKSLASH:Int = 92; // \

	var state:Int = S_SEEK;

	/** 当前窗口（Bytes），cur 为读取游标 */
	var buf:Bytes;
	var cur:Int = 0;

	// 小节状态
	var mustHit:Bool = true;
	var gfSection:Bool = false;

	// 合并状态（跨小节、跨 Part 保持）
	var lastLane:Array<PackedChart> = [null, null, null, null];
	var chartSeq:Int = 0;
	// ⚠ 这三个计数**必须用 Float，不能用 Int**：
	//   hxcpp 的 Int 是 32 位有符号（上限 2,147,483,647）。Parts 组合实测 66 个 Part
	//   就有约 3,846,915,390 颗音符 —— 一旦用 Int，rawCount/mergedAway 会**溢出成负数**
	//   （实测 meta: raw=-448051906），进而让下游 `if (raw <= 0)` 之类的判空守卫误判，
	//   组合谱被静默丢弃、退回单 Part 加载（用户看到的是「Note 数量没变」）。
	//   Float 是 64 位双精度，整数精确到 2^53 ≈ 9.0e15，足够且无需改类型签名。
	var totalNotes:Float = 0;
	var mergedAway:Float = 0;
	var rawCount:Float = 0;
	var sectionCount:Int = 0; // 66 Part 实测 58512 小节，远未到 Int 上限，保持 Int
	/** 是否真的读到过音符。判空**只认这个标志**，不再依赖计数器符号（计数器会溢出）。 */
	public var sawAnyNote:Bool = false;
	var out:Array<PackedChart> = [];
	var doMerge:Bool = true;

	public var ghostRange:Float;
	public var ghostDensity:Bool;
	/** 每簇保留的偏移样本数上限（0 = 全量，行为与旧版一致） */
	public var offsKeepLimit:Int;

	public function new(ghostRange:Float, ghostDensity:Bool, offsKeepLimit:Int)
	{
		this.ghostRange = ghostRange;
		this.ghostDensity = ghostDensity;
		this.offsKeepLimit = offsKeepLimit;
	}

	/** 流式解析。返回已合并的簇数组；null = 该文件不适合本路径（调用方回退整读）。 */
	public function scan(path:String, bpm:Float, forceMerge:Bool):Array<PackedChart>
	{
		doMerge = forceMerge;
		scanOne(path);
		return out;
	}

	/**
	 * 追加扫描一个 Part，**共用当前合并状态**（lastLane / out / 计数）。
	 *
	 * 这是「多 Part 叠加」的核心：多个 Part 必须共用同一个合并器，
	 * 这样同一时刻同一轨的多颗音符（来自不同 Part）才会并进**同一个簇**，
	 * density 自然累加 —— 正是「同刻两颗算 2」的语义。
	 * 若每个 Part 各自合并再拼接，两颗同刻音符会成为两个独立簇，无法正确计分。
	 *
	 * 每个文件开始前只重置**分块缓冲与状态机**（buf/cur/state），
	 * 合并状态（lastLane）与输出（out）跨文件保持。
	 */
	public function scanPart(path:String):Void
	{
		scanOne(path);
	}

	function scanOne(path:String):Void
	{
		var input:FileInput = File.read(path);
		if (input == null) return;
		var total:Int = 0;
		try
		{
			total = sys.FileSystem.stat(path).size;
		}
		catch (e:Dynamic)
		{
			input.close();
			return;
		}
		if (total <= 0)
		{
			input.close();
			return;
		}

		buf = Bytes.alloc(0);
		cur = 0;
		state = S_SEEK;
		var left:Int = total;
		while (left > 0)
		{
			// ⚠ Input.read(len) 在剩余不足 len 时抛 Eof 而非短读 → 必须按剩余字节请求
			var want:Int = (left < CHUNK) ? left : CHUNK;
			var b:Bytes = input.read(want);
			left -= want;
			if (b == null || b.length == 0) break;
			append(b);
			process(false);
			if (buf.length - cur > CARRY_MAX) throw 'packed scanner carry overflow: ' + (buf.length - cur);
		}
		input.close();
		process(true);
		// 文件收尾：清掉可能残留在缓冲里的半截 section，避免污染下一个 Part
		buf = Bytes.alloc(0);
		cur = 0;
		state = S_SEEK;
	}

	/**
	 * 追加分块：只把「未消费尾部 + 新分块」搬进新窗口，避免整体增长。
	 * 用 BytesBuffer 而非 Bytes.blit —— blit 在 neko 上是坏的（拷贝后内容变空格，
	 * 实测 neko 2.3 上 blit 不生效）。BytesBuffer 在 neko / hxcpp 上语义一致。
	 */
	function append(b:Bytes):Void
	{
		var keep:Int = buf.length - cur;
		if (keep < 0) keep = 0;
		var bb:BytesBuffer = new BytesBuffer();
		if (keep > 0) bb.add(buf.sub(cur, keep));
		bb.add(b);
		buf = bb.getBytes();
		cur = 0;
	}

	function compact():Void
	{
		if (cur <= 0) return;
		if (cur >= buf.length)
		{
			buf = Bytes.alloc(0);
			cur = 0;
			return;
		}
		buf = buf.sub(cur, buf.length - cur);
		cur = 0;
	}

	function process(isFinal:Bool):Void
	{
		var guard:Int = 0;
		while (true)
		{
			guard++;
			if (guard > 2000000) throw 'packed scanner guard tripped';
			if (state == S_SEEK)
			{
				var i = findByte(cur, CH_LBRACE);
				if (i < 0)
				{
					compact();
					return;
				}
				cur = i + 1;
				state = S_META;
				continue;
			}
			if (state == S_META)
			{
				mustHit = true; // 每 section 重置默认值，与 fastScanSectionNotes 同口径
				var mh = findBoolAfter(cur, "mustHitSection");
				if (mh != null) mustHit = mh;
				var gf = findBoolAfter(cur, "gfSection");
				if (gf != null) gfSection = gf;

				var ni = findAscii(cur, "sectionNotes");
				if (ni < 0)
				{
					if (buf.length - cur > 4096) cur = buf.length - 4096;
					return;
				}
				var br = findByte(ni, CH_LBRACK);
				if (br < 0)
				{
					if (buf.length - ni > 4096) cur = buf.length - 4096;
					return;
				}
				cur = br + 1;
				state = S_NOTES;
				continue;
			}
			if (!parseNotes(isFinal)) return;
		}
	}

	/** 返回 false = 需要更多数据 */
	function parseNotes(isFinal:Bool):Bool
	{
		var len = buf.length;
		while (cur < len)
		{
			var c = buf.get(cur);
			// 空白与逗号
			if (c == 32 || c == 10 || c == 13 || c == 9 || c == CH_COMMA)
			{
				cur++;
				continue;
			}
			if (c == CH_RBRACK)
			{
				cur++;
				sectionCount++;
				state = S_SEEK;
				return true;
			}
			if (c == CH_RBRACE)
			{
				state = S_SEEK;
				return true;
			}
			if (c != CH_LBRACK)
			{
				cur++;
				continue;
			}
			// ⚠ 必须用返回值判断数据不足：parseTuple 不足时不推进游标，无条件继续会死循环
			if (!parseTuple()) return false;
		}
		if (isFinal)
		{
			state = S_SEEK;
			return true;
		}
		return false;
	}

	/** 解析 [t,col,sustain,type]。返回 false = 数据不足（游标未推进）。 */
	function parseTuple():Bool
	{
		var p = cur + 1;
		var t:Float = 0;
		var col:Int = 0;
		var sus:Float = 0;
		var typeStr:String = null;
		var slot = 0;
		var len = buf.length;

		while (slot < 4 && p < len)
		{
			// 跳过空白**和逗号**（元组字段分隔符）——
			// 只跳空白会让 ',' 被当成一个字段吃掉，slot 错位导致 col 永远读不到
			while (p < len)
			{
				var cc = buf.get(p);
				if (cc == 32 || cc == 10 || cc == 13 || cc == 9 || cc == CH_COMMA) p++;
				else break;
			}
			if (p >= len) return false;

			var ch = buf.get(p);
			if (ch == CH_QUOTE)
			{
				p++;
				var st = p;
				var closed = false;
				while (p < len)
				{
					var q = buf.get(p);
					if (q == CH_BACKSLASH) p += 2;
					else if (q == CH_QUOTE)
					{
						closed = true;
						break;
					}
					else p++;
				}
				if (!closed) return false;
				// noteType 字符串是少数情况（标准谱为 true/false），这里才分配
				typeStr = buf.sub(st, p - st).toString();
				p++;
				slot++;
				continue;
			}
			if ((ch >= 48 && ch <= 57) || ch == 45 || ch == 43 || ch == 46)
			{
				var nst = p;
				while (p < len)
				{
					var c3 = buf.get(p);
					if ((c3 >= 48 && c3 <= 57) || c3 == 45 || c3 == 46 || c3 == 43 || c3 == 101 || c3 == 69) p++;
					else break;
				}
				// 未遇到分隔符说明可能被块边界截断
				if (p >= len) return false;
				var v:Float = scanNum(buf, nst, p);
				if (slot == 0) t = v;
				else if (slot == 1) col = Std.int(v);
				else if (slot == 2) sus = v;
				slot++;
				continue;
			}
			// true / false / null 等非数值 token
			while (p < len)
			{
				var t3 = buf.get(p);
				if (t3 == CH_COMMA || t3 == CH_RBRACK) break;
				p++;
			}
			slot++;
		}
		if (slot < 1) return false;

		while (p < len && buf.get(p) != CH_RBRACK) p++;
		if (p >= len) return false;
		p++;
		cur = p;

		rawCount++;
		emit(t, col, sus, typeStr);
		return true;
	}

	// ===== 字节级查找 =====

	function findByte(from:Int, b:Int):Int
	{
		var len = buf.length;
		var i = from;
		while (i < len)
		{
			if (buf.get(i) == b) return i;
			i++;
		}
		return -1;
	}

	/** 查找 ASCII 子串（不做正则、不分配） */
	function findAscii(from:Int, pat:String):Int
	{
		var len = buf.length;
		var pl = pat.length;
		if (pl == 0 || from < 0 || from + pl > len) return -1;
		var p0 = StringTools.fastCodeAt(pat, 0);
		var p1 = pl > 1 ? StringTools.fastCodeAt(pat, 1) : -1;
		var i = from;
		var limit = len - pl;
		while (i <= limit)
		{
			if (buf.get(i) == p0 && (p1 < 0 || buf.get(i + 1) == p1))
			{
				var ok = true;
				for (k in 2...pl)
				{
					if (buf.get(i + k) != StringTools.fastCodeAt(pat, k))
					{
						ok = false;
						break;
					}
				}
				if (ok) return i;
			}
			i++;
		}
		return -1;
	}

	function findBoolAfter(from:Int, key:String):Null<Bool>
	{
		var i = findAscii(from, key);
		if (i < 0) return null;
		var c = findByte(i, CH_COLON);
		if (c < 0) return null;
		c++;
		var len = buf.length;
		while (c < len)
		{
			var ch = buf.get(c);
			if (ch == 32 || ch == 10 || ch == 13 || ch == 9) c++;
			else break;
		}
		if (c + 4 <= len && buf.get(c) == 116 && buf.get(c + 1) == 114 && buf.get(c + 2) == 117 && buf.get(c + 3) == 101) return true;
		if (c + 5 <= len && buf.get(c) == 102 && buf.get(c + 1) == 97 && buf.get(c + 2) == 108 && buf.get(c + 3) == 115 && buf.get(c + 4) == 101)
			return false;
		return null;
	}

	/** 原地把 [start,end) 的数字文本解析为 Float（零分配） */
	static function scanNum(b:Bytes, start:Int, end:Int):Float
	{
		var i = start;
		var neg = false;
		if (i < end)
		{
			var c = b.get(i);
			if (c == 45)
			{
				neg = true;
				i++;
			}
			else if (c == 43) i++;
		}
		var intVal:Float = 0;
		while (i < end)
		{
			var c = b.get(i);
			if (c >= 48 && c <= 57)
			{
				intVal = intVal * 10 + (c - 48);
				i++;
			}
			else break;
		}
		var frac:Float = 0;
		if (i < end && b.get(i) == 46)
		{
			i++;
			var div:Float = 10;
			while (i < end)
			{
				var c2 = b.get(i);
				if (c2 >= 48 && c2 <= 57)
				{
					frac += (c2 - 48) / div;
					div *= 10;
					i++;
				}
				else break;
			}
		}
		var v = intVal + frac;
		if (i < end)
		{
			var c3 = b.get(i);
			if (c3 == 101 || c3 == 69)
			{
				var j = i + 1;
				var eneg = false;
				if (j < end)
				{
					var c4 = b.get(j);
					if (c4 == 45)
					{
						eneg = true;
						j++;
					}
					else if (c4 == 43) j++;
				}
				var ev:Int = 0;
				var got = false;
				while (j < end)
				{
					var c5 = b.get(j);
					if (c5 >= 48 && c5 <= 57)
					{
						ev = ev * 10 + (c5 - 48);
						got = true;
						j++;
					}
					else break;
				}
				if (got) v *= Math.pow(10, eneg ? -ev : ev);
			}
		}
		return neg ? -v : v;
	}

	function emit(t:Float, col:Int, sus:Float, typeStr:String):Void
	{
		// ⚠⚠ psych_v1 列号转换（必须做，否则 dad 侧音符会整体跑到 bf 侧）
		//   原始 JSON 用「列号 0-3 + section.mustHitSection」表示方向，
		//   fastScanSectionNotes 靠下面几行转成绝对列号（<4 玩家 / >=4 对手）：
		//       colI = col % 4 ; gottaHit = (col<4) ? mustHit : !mustHit
		//   漏掉这一步的后果：该谱 mustHitSection=false + 列 0-3，
		//   直接用 `col<4` 判方向会全部判成玩家侧。
		var lane = col % 4;
		if (lane < 0) lane += 4;
		var must = (col < 4) ? mustHit : !mustHit;

		if (doMerge)
		{
			var m = lastLane[lane];
			if (m != null && Math.abs(t - m.t) <= ghostRange && m.mustHit == must)
			{
				if (ghostDensity) m.density += 1;
				// 偏移有界化：offs 只留前 KEEP 个，末个单独存 lastOffset，
				// 真实数量记 offsKeep（生成期据此还原视觉分布）
				var off:Float = t - m.t;
				m.offsKeep++;
				m.lastOffset = off;
				if (m.offs == null) m.offs = [];
				if (m.offs.length < offsKeepLimit) m.offs.push(off);
				mergedAway++;
				if (must) totalNotes++;
				if (sus > m.holdLength) m.holdLength = sus;
				sawAnyNote = true;
				return;
			}
		}

		var n = new PackedChart();
		n.t = t;
		n.lane = lane;
		n.mustHit = must;
		n.holdLength = sus;
		n.chartSeq = chartSeq++;
		n.noteType = (typeStr == null || typeStr.length == 0) ? null : ('' + typeStr);
		n.gfNote = gfSection && (must == mustHit);
		out.push(n);
		lastLane[lane] = n;
		if (must) totalNotes++;
		sawAnyNote = true;
	}

	/** 已合并的簇数组（多 Part 叠加时含全部 Part 的结果） */
	public function result():Array<PackedChart> return out;

	public function stats():Dynamic
	{
		return {
			raw: rawCount,
			merged: mergedAway,
			clusters: out.length,
			sections: sectionCount,
			totalNotes: totalNotes
		};
	}
}
#end