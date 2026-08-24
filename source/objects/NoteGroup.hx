package objects;

import haxe.ds.ArraySort;
import objects.Note.CastNote;

/**
 * H-Slice 移植：音符对象池 + 批处理组。
 * - 音符实例从池中复用（消除 15 万级谱面的对象创建/销毁与 GC 压力）
 * - 自动游玩预演模式跳过整组逐音符 update（命中由 PlayState 的 botHitQueue 统一驱动）
 * - 可选 fasterSort：只对可见音符排序（大谱面排序开销降为 O(可见数)）
 */
class NoteGroup extends FlxTypedGroup<Note>
{
	var pool:Array<Note> = [];

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
		var n:Note;
		if (pool.length > 0)
		{
			n = pool.pop();
			if (n.botQueued)
			{
				// 排期未处理的对象不可复用（否则队列处理会命中新生命）；放回并新建——绝不循环
				pool.push(n);
				n = new Note(0, 0, null, false, false);
				members.push(n);
				length++;
			}
			else
			{
				n.exists = true;
				n.alive = true; // kill() 会置 alive=false，复用前必须复活
			}
		}
		else
		{
			n = new Note(0, 0, null, false, false);
		}
		// 池化/新建统一：重新加回组（invalidateNote 会 remove；不复归绝不入组——不可见且不被判定）
		members.push(n);
		length++;
		return n.recycleNote(target);
	}

	// 池化回收：击杀 + 移出组 + 回池（所有"杀音符"路径统一走这里，禁止直接 destroy）
	public function invalidateNote(n:Note):Void
	{
		if (n == null) return;
		n.botQueued = false; // 死亡即解除排期保护（池中恢复可复用；队列条目由 !alive 跳过）
		n.botSched = false;
		n.invalidatePooled();
		n.kill();
		remove(n, true); // 第二参数 = Splice：真移除（remove(obj,false) 会在数组里留 null！）
		n.active = false;
		n.visible = false;
		if (pool.length < 2048) pool.push(n);
	}

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
}
