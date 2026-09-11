package objects;

import haxe.ds.ArraySort;
import objects.Note.CastNote;
import backend.ClientPrefs;

/**
 * H-Slice 移植：音符对象池 + 批处理组。
 * - 音符实例从池中复用（消除 15 万级谱面的对象创建/销毁与 GC 压力）
 * - 自动游玩预演模式跳过整组逐音符 update（命中由 PlayState 的 botHitQueue 统一驱动）
 * - 可选 fasterSort：只对可见音符排序（大谱面排序开销降为 O(可见数)）
 */
class NoteGroup extends FlxTypedGroup<Note>
{
	var pool:Array<Note> = [];
	// 【Turbo·notePool】对象池只在 densePerfMode 启用（窄范围、非密集谱行为与旧版完全一致）。
	// Seiun 最新版在同基座上常态化 pop/revive 复用；Meteoric 曾因旧管线下池化读字段
	// SIGSEGV 而整体停用——此处按 Seiun 的门控策略仅在密集自动档启用，且复用走的是
	// 现有 recycleNote 复位链（与"每音符全新构造 + recycleNote 填充"同一填充逻辑，
	// 仅省去 new 分配），池容量有界（DENSE_POOL_MAX），保守可回退。
	public static var poolEnabled:Bool = false;
	static inline var DENSE_POOL_MAX:Int = 256;

	public function resetPool():Void
	{
		pool = [];
	}

	// fasterSort 用（数组复用，Do not declare inside loops. This causes memory leaks.）
	var sortArr:Array<Note> = [];
	var indexArr:Array<Int> = [];
	var range:Int = 0;

	public function new(maxSize:Int = 0)
	{
		super(maxSize);
	}


	// 从池中弹出一个音符并复生为 target；无可用实例时新建
	public function spawnNote(target:CastNote):Note
	{
		// 【Turbo·notePool】dense 档复用池中实例（recycleNote 复位链与全新构造一致，仅省 new）。
		// 非 dense / 池空 → 全新构造（原行为）。
		var n:Note = null;
		if (poolEnabled && pool.length > 0)
		{
			n = pool.pop();
			n.revive();
		}
		if (n == null)
			n = new Note(0, 0, null, false, false);
		members.push(n);
		length++;
		aliveObjectCount++;
		return n.recycleNote(target);
	}

	// 长条重构：PlayState.spawnHoldTail 把已构造好的段 Note 直接注册进组
	public function addNoteObject(n:Note):Void
	{
		members.push(n);
		length++;
		aliveObjectCount++;
	}

	// 池化回收：击杀 + 移出组 + 回池（所有"杀音符"路径统一走这里，禁止直接 destroy）
	public function invalidateNote(n:Note):Void
	{
		if (n == null) return;
		// 批内延迟移除：processBotHits 期间登记，帧末由 endBatchKill 一次 O(n) 清扫——
		// 原 per-hit remove(n,true) 是 FlxGroup.remove 的 indexOf+splice（O(成员数)），
		// 每帧数百命中 × ~900 成员 = 每帧数十万次指针搬移（notes_avg 300us+ 的主因）。
		if (n.batchKillPending) return; // 已登记（防同帧重复登记）
		if (batchKill)
		{
			n.batchKillPending = true;
			batchKillCount++;
		}
		if (aliveObjectCount > 0) aliveObjectCount--;
		n.botQueued = false; // 死亡即解除排期保护（池中恢复可复用；队列条目由 !alive 跳过）
		n.botSched = false;
		n.invalidatePooled();
		n.kill();
		if (batchKill) return; // 登记完成，帧末统一移出成员表
		remove(n, true); // 第二参数 = Splice：真移除（remove(obj,false) 会在数组里留 null！）
		n.active = false;
		n.visible = false;
		// 【Turbo·notePool】dense 档击杀实例回池（有界），供 spawnNote 复用
		if (poolEnabled && pool.length < DENSE_POOL_MAX)
			pool.push(n);
	}

	// 【密集批·延迟移除】批开始：后续 invalidateNote 只登记不搬移
	public function beginBatchKill():Void
	{
		batchKill = true;
	}

	// 【密集批·延迟移除】批结束：一次 O(n) 过滤清扫（保留未登记音符的顺序）
	public function endBatchKill():Void
	{
		batchKill = false;
		if (batchKillCount == 0) return;
		var w:Int = 0;
		var arr:Array<Note> = members;
		for (i in 0...arr.length)
		{
			var n:Note = arr[i];
			if (n != null && n.batchKillPending)
			{
				n.batchKillPending = false;
				// 【Turbo·notePool】批内击杀同样回池（有界）
				if (poolEnabled && pool.length < DENSE_POOL_MAX)
					pool.push(n);
				continue;
			}
			arr[w++] = n;
		}
		arr.resize(w);
		@:privateAccess length = w; // FlxGroup.length 只读，privateAccess 直写保持同步
		batchKillCount = 0;
	}

	var batchKill:Bool = false;
	var batchKillCount:Int = 0;

	override function update(elapsed:Float)
	{
		// 自动游玩捷径：预演模式下各音符 update 由 PlayState 统一处理（跳过整组逐音符开销）
		if (PlayState.instance != null && PlayState.instance.cpuControlled
			&& !PlayState.instance.replayMode && PlayState.instance.botplayPlan != null)
			return;
		super.update(elapsed);
	}

	public function fasterSort(reverse:Bool = false)
	{
		range = 0;
		for (i => note in members)
		{
			if (note != null && note.visible)
			{
				sortArr[range] = note;
				indexArr[range++] = i;
			}
		}

		if (sortArr.length > range)
		{
			sortArr.resize(range);
			indexArr.resize(range);
		}

		ArraySort.sort(sortArr, (a, b) -> reverse ? noteSort(b, a) : noteSort(a, b));
		indexArr.sort((a, b) -> a - b);

		for (index => i in indexArr) members[i] = sortArr[index];
	}

	public static function noteSort(a:Note, b:Note):Int
	{
		return if (a.strumTime != b.strumTime) {
			a.strumTime > b.strumTime ? -1 : 1;
		} else if (a.isSustainNote != b.isSustainNote) {
			a.isSustainNote ? -1 : 1;
		} else 0;
	}

	// 场上存活音符数（density 合并计数一并计入，供 limitNotes 上限判断）
	var _living:Int = 0;
	override public function countLiving():Int
	{
		_living = 0;
		for (basic in members)
		{
			if (basic != null && basic.exists && basic.alive)
				_living += Std.int(basic.density);
		}
		return _living;
	}

	// 【密集对象硬上限】精灵对象数（非 density 加权）：由 spawnNote/addNoteObject/
	// invalidateNote 三个出入口自维护，供 PlayState 的 perfObjCap 使用。
	// 注意：不能复用 countLiving()——堆叠合并谱的 density 可达数百，加权计数
	// 会把整场压成个位数簇（破坏判定），对象上限必须按真实精灵数。
	public var aliveObjectCount:Int = 0;
}
