package backend;

import backend.Song;
import backend.Section;
import objects.Note;

typedef BPMChangeEvent =
{
	var stepTime:Int;
	var songTime:Float;
	var bpm:Float;
	@:optional var stepCrochet:Float;
	@:optional var index:Int;
}

class Conductor
{
	public static var bpm(default, set):Float = 100;
	public static var crochet:Float = ((60 / bpm) * 1000); // beats in milliseconds
	public static var stepCrochet:Float = crochet / 4; // steps in milliseconds
	/** 歌曲播放位置（毫秒）。
	 *  ⚠ **所有权契约**：本字段的写入者**只有 Conductor 自己**，外部一律经下面三个
	 *  意图命名的方法改动（`syncToMusic` / `setPosition` / `advance`）。
	 *  这样做的目的不是形式统一，而是让"谁在推时钟"变成可审计的单一事实来源：
	 *  此前 10 个文件、31 处直接赋值横跨 UI/菜单/编辑器/结算，任何一次改动都无法推理后果
	 *  （收敛后：外部裸赋值 0 处，读取站点数量不变）。
	 *
	 *  ⚠ **契约的可审计范围 = 引擎源码**。字段必须保持 `public` —— Lua/HScript 可经
	 *  `setPropertyFromClass('Conductor','songPosition', …)` 直写它，这是既有 mod 生态的
	 *  一部分（仓库内至少 2 处实例：`tools/user_mods_prev/mods/66666/scripts/fast forward script.lua:51`、
	 *  `tools/user_mods_prev/mods/66666/data/s49-subleader/fast forward script.lua:37`），
	 *  **不得**为了让"单写者"好看而把字段私有化（那会破坏 mod 兼容）。
	 *  因此：引擎内改动受本契约约束并可静态审计；脚本侧写入**不受约束、也不被本契约覆盖**。
	 *  若将来要收敛脚本侧，只能"新增只读/受控访问器 + 保留字段可写"，不能收窄兼容面。
	 *
	 *  三个方法均为 `inline`，编译后与原来的裸赋值**零开销等价**、数值语义完全不变。 */
	public static var songPosition:Float = 0;

	/** 把时钟同步到当前音乐播放器位置（对应原 `= FlxG.sound.music.time`）。
	 *  调用方若有 `if (FlxG.sound.music != null)`/`>= 0` 等前置守卫，请**原样保留**在调用处。 */
	@:keep public static inline function syncToMusic():Void
	{
		songPosition = FlxG.sound.music.time;
	}

	/** 直接设定时钟（对应原 `= <表达式>`）：重置(0 / -5000 / -crochet*5)、回退、编辑器跳转等。 */
	@:keep public static inline function setPosition(ms:Float):Void
	{
		songPosition = ms;
	}

	/** 按增量推进时钟（对应原 `+= <表达式>`；负值即原 `-=`）。 */
	@:keep public static inline function advance(ms:Float):Void
	{
		songPosition += ms;
	}
	public static var offset:Float = 0;

	//public static var safeFrames:Int = 10;
	public static var safeZoneOffset:Float = 0; // is calculated in create(), is safeFrames in milliseconds

	public static var bpmChangeMap:Array<BPMChangeEvent> = [];

	public function new()
	{
	}

	public static function judgeNote(arr:Array<Rating>, diff:Float=0):Rating // die
	{
		var data:Array<Rating> = arr;
		for(i in 0...data.length-1) //skips last window (Shit)
			if (diff <= data[i].hitWindow)
				return data[i];

		return data[data.length - 1];
	}

	public static function getCrotchetAtTime(time:Float){
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepCrochet*4;
	}

	public static function getBPMFromSeconds(time:Float):BPMChangeEvent {
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: bpm,
			stepCrochet: stepCrochet,
			index: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (time >= Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		return lastChange;
	}

	public static function getBPMFromSecondsCached(time:Float, startIndex:Int):BPMChangeEvent {
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: bpm,
			stepCrochet: stepCrochet,
			index: 0
		}
		var map = Conductor.bpmChangeMap;
		var i:Int = startIndex;
		while (i < map.length)
		{
			if (time >= map[i].songTime) {
				lastChange = map[i];
				lastChange.index = i;
			} else break;
			i++;
		}

		return lastChange;
	}

	public static function getBPMFromStep(step:Float){
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: bpm,
			stepCrochet: stepCrochet
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (Conductor.bpmChangeMap[i].stepTime<=step)
				lastChange = Conductor.bpmChangeMap[i];
		}

		return lastChange;
	}

	public static function beatToSeconds(beat:Float): Float{
		var step = beat * 4;
		var lastChange = getBPMFromStep(step);
		return lastChange.songTime + ((step - lastChange.stepTime) / (lastChange.bpm / 60)/4) * 1000; // TODO: make less shit and take BPM into account PROPERLY
	}

	public static function getStep(time:Float){
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepTime + (time - lastChange.songTime) / lastChange.stepCrochet;
	}

	public static function getStepRounded(time:Float){
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepTime + Math.floor(time - lastChange.songTime) / lastChange.stepCrochet;
	}

	public static function getBeat(time:Float){
		return getStep(time)/4;
	}

	public static function getBeatRounded(time:Float):Int{
		return Math.floor(getStepRounded(time)/4);
	}

	public static function mapBPMChanges(song:SwagSong)
	{
		bpmChangeMap = [];

		var curBPM:Float = song.bpm;
		var totalSteps:Int = 0;
		var totalPos:Float = 0;
		for (i in 0...song.notes.length)
		{
			if(song.notes[i].changeBPM && song.notes[i].bpm != curBPM)
			{
				curBPM = song.notes[i].bpm;
				var event:BPMChangeEvent = {
					stepTime: totalSteps,
					songTime: totalPos,
					bpm: curBPM,
					stepCrochet: calculateCrochet(curBPM)/4
				};
				bpmChangeMap.push(event);
			}

			var deltaSteps:Int = Math.round(getSectionBeats(song, i) * 4);
			totalSteps += deltaSteps;
			totalPos += ((60 / curBPM) * 1000 / 4) * deltaSteps;
		}
		trace("new BPM map BUDDY " + bpmChangeMap);
	}

	static function getSectionBeats(song:SwagSong, section:Int)
	{
		var val:Null<Float> = null;
		if(song.notes[section] != null) val = song.notes[section].sectionBeats;
		return val != null ? val : 4;
	}

	inline public static function calculateCrochet(bpm:Float){
		return (60/bpm)*1000;
	}

	public static function set_bpm(newBPM:Float):Float {
		bpm = newBPM;
		crochet = calculateCrochet(bpm);
		stepCrochet = crochet / 4;

		return bpm = newBPM;
	}
}