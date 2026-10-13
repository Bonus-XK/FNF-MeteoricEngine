package backend;

class Difficulty
{
	public static var defaultList(default, never):Array<String> = [
		'Easy',
		'Normal',
		'Hard'
	];
	public static var list:Array<String> = [];
	private static var defaultDifficulty(default, never):String = 'Normal'; //The chart that has no suffix and starting difficulty on Freeplay/Story Mode

	/** Parts 组合难度的条目名（对应 Song 侧的「枚举全部 Part」语义） */
	public static inline var PARTS_DIFFICULTY:String = 'Parts';

	/** 该难度名是否是 Parts 组合难度（大小写不敏感） */
	public static function isPartsDifficulty(name:String):Bool
	{
		return name != null && name.toLowerCase() == PARTS_DIFFICULTY.toLowerCase();
	}

	inline public static function getFilePath(num:Null<Int> = null)
	{
		if(num == null) num = PlayState.storyDifficulty;

		var fileSuffix:String = list[num];
		if(fileSuffix != defaultDifficulty)
		{
			fileSuffix = '-' + fileSuffix;
		}
		else
		{
			fileSuffix = '';
		}
		return Paths.formatToSongPath(fileSuffix);
	}

	inline public static function loadFromWeek(week:WeekData = null)
	{
		if(week == null) week = WeekData.getCurrentWeek();

		var diffStr:String = week.difficulties;
		if(diffStr != null && diffStr.length > 0)
		{
			var diffs:Array<String> = diffStr.trim().split(',');
			var i:Int = diffs.length - 1;
			while (i > 0)
			{
				if(diffs[i] != null)
				{
					diffs[i] = diffs[i].trim();
					if(diffs[i].length < 1) diffs.remove(diffs[i]);
				}
				--i;
			}

			if(diffs.length > 0 && diffs[0].length > 0)
				list = diffs;
		}
		else
			resetList();

		// Parts 组合难度：设置开启时追加「Parts」条目。选中它 → jsonInput 形如
		// "song-parts" → Song.resolvePartPaths 枚举该歌 data/ 下的全部 Part 并合并叠加。
		// ⚠ 这段必须在上面的 if/else **之外**：早前误把它写成 `if (partsMode) ... else resetList()`，
		//   导致 else 配对错位、**任何时候都执行 resetList()**，难度被重置成 Easy/Normal/Hard。
		if (ClientPrefs.data.partsMode && list.indexOf(PARTS_DIFFICULTY) < 0)
			list = list.copy().concat([PARTS_DIFFICULTY]);
	}

	inline public static function resetList()
	{
		list = defaultList.copy();
	}

	inline public static function copyFrom(diffs:Array<String>)
	{
		list = diffs.copy();
	}

	inline public static function getString(num:Null<Int> = null):String
	{
		return list[num == null ? PlayState.storyDifficulty : num];
	}

	inline public static function getDefault():String
	{
		return defaultDifficulty;
	}
}