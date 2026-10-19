package backend;

class Highscore
{
	public static var weekScores:Map<String, haxe.Int64> = new Map();
	public static var songScores:Map<String, haxe.Int64> = new Map<String, haxe.Int64>();
	public static var songRating:Map<String, Float> = new Map<String, Float>();

	public static function resetSong(song:String, diff:Int = 0):Void
	{
		var daSong:String = formatSong(song, diff);
		setScore(daSong, 0);
		setRating(daSong, 0);
	}

	public static function resetWeek(week:String, diff:Int = 0):Void
	{
		var daWeek:String = formatSong(week, diff);
		setWeekScore(daWeek, 0);
	}

	public static function saveScore(song:String, ?score:Null<haxe.Int64>, ?diff:Int = 0, ?rating:Float = -1):Void
	{
		if (score == null) score = 0;
		var daSong:String = formatSong(song, diff);

		if (songScores.exists(daSong)) {
			if (songScores.get(daSong) < score) {
				setScore(daSong, score);
				if(rating >= 0) setRating(daSong, rating);
			}
		}
		else {
			setScore(daSong, score);
			if(rating >= 0) setRating(daSong, rating);
		}
	}

	public static function saveWeekScore(week:String, ?score:Null<haxe.Int64>, ?diff:Int = 0):Void
	{
		if (score == null) score = 0;
		var daWeek:String = formatSong(week, diff);

		if (weekScores.exists(daWeek))
		{
			if (weekScores.get(daWeek) < score)
				setWeekScore(daWeek, score);
		}
		else
			setWeekScore(daWeek, score);
	}

	/**
	 * YOU SHOULD FORMAT SONG WITH formatSong() BEFORE TOSSING IN SONG VARIABLE
	 */
	static function setScore(song:String, score:haxe.Int64):Void
	{
		// Reminder that I don't need to format this song, it should come formatted!
		songScores.set(song, score);
		// haxe.Serializer 不支持 Int64（实测：std 源码无 Int64 分支），而 OpenFL SharedObject
		// 落盘走 Serializer.run（openfl/net/SharedObject.hx:461），直接把 Int64 Map 塞进
		// FlxG.save 会在 flush 时炸。分数上限 ~1.8e12（36 亿谱面 × 500/音符）< 2^53，
		// Float 存档不丢精度；songRating 的 Map<String, Float> 走同一条通道（现成先例）
		FlxG.save.data.songScores = i64ToFloatMap(songScores);
		FlxG.save.flush();
	}
	static function setWeekScore(week:String, score:haxe.Int64):Void
	{
		// Reminder that I don't need to format this song, it should come formatted!
		weekScores.set(week, score);
		FlxG.save.data.weekScores = i64ToFloatMap(weekScores);
		FlxG.save.flush();
	}

	static function setRating(song:String, rating:Float):Void
	{
		// Reminder that I don't need to format this song, it should come formatted!
		songRating.set(song, rating);
		FlxG.save.data.songRating = songRating;
		FlxG.save.flush();
	}

	public static function formatSong(song:String, diff:Int):String
	{
		return Paths.formatToSongPath(song) + Difficulty.getFilePath(diff);
	}

	public static function getScore(song:String, diff:Int):haxe.Int64
	{
		var daSong:String = formatSong(song, diff);
		if (!songScores.exists(daSong))
			setScore(daSong, 0);

		return songScores.get(daSong);
	}

	public static function getRating(song:String, diff:Int):Float
	{
		var daSong:String = formatSong(song, diff);
		if (!songRating.exists(daSong))
			setRating(daSong, 0);

		return songRating.get(daSong);
	}

	public static function getWeekScore(week:String, diff:Int):haxe.Int64
	{
		var daWeek:String = formatSong(week, diff);
		if (!weekScores.exists(daWeek))
			setWeekScore(daWeek, 0);

		return weekScores.get(daWeek);
	}

	public static function load():Void
	{
		// 落盘是 Map<String, Float>（i64ToFloatMap），读回来归一化成 Int64；
		// 同时兼容旧版 Int 存档。Unserializer 会原样还原 StringMap（std both ways supported）
		if (FlxG.save.data.songScores != null)
			songScores = floatMapTo64(FlxG.save.data.songScores);
		if (FlxG.save.data.weekScores != null)
			weekScores = floatMapTo64(FlxG.save.data.weekScores);
		if (FlxG.save.data.songRating != null)
			songRating = FlxG.save.data.songRating;
	}

	static function i64ToFloatMap(m:Map<String, haxe.Int64>):Map<String, Float>
	{
		var out:Map<String, Float> = new Map<String, Float>();
		for (k in m.keys())
			out.set(k, I64.toFloat(m.get(k)));
		return out;
	}

	static function floatMapTo64(raw:Dynamic):Map<String, haxe.Int64>
	{
		var out:Map<String, haxe.Int64> = new Map<String, haxe.Int64>();
		if (raw == null) return out;
		var m:Map<String, Dynamic> = raw;
		for (k in m.keys())
		{
			var v:Dynamic = m.get(k);
			if (haxe.Int64.isInt64(v))
				out.set(k, v);
			else if (Std.isOfType(v, Float))
				out.set(k, haxe.Int64.fromFloat(v));
			else if (Std.isOfType(v, Int))
				out.set(k, haxe.Int64.ofInt(v)); // 旧版存档
		}
		return out;
	}
}
