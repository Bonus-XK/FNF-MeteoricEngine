package psychlua.functions;

import psychlua.FunkinLua;

//
// ScoreCommands —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class ScoreCommands
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "addScore", function(value:Int = 0) {
			game.songScore += value;
			game.RecalculateRating();
		});

		Lua_helper.add_callback(lua, "addMisses", function(value:Int = 0) {
			game.songMisses += value;
			game.RecalculateRating();
		});

		Lua_helper.add_callback(lua, "addHits", function(value:Int = 0) {
			game.songHits += value;
			game.RecalculateRating();
		});

		Lua_helper.add_callback(lua, "setScore", function(value:Int = 0) {
			game.songScore = value;
			game.RecalculateRating();
		});

		Lua_helper.add_callback(lua, "setMisses", function(value:Int = 0) {
			game.songMisses = value;
			game.RecalculateRating();
		});

		Lua_helper.add_callback(lua, "setHits", function(value:Int = 0) {
			game.songHits = value;
			game.RecalculateRating();
		});

		Lua_helper.add_callback(lua, "getScore", function() {
			return game.songScore;
		});

		Lua_helper.add_callback(lua, "getMisses", function() {
			return game.songMisses;
		});

		Lua_helper.add_callback(lua, "getHits", function() {
			return game.songHits;
		});

		Lua_helper.add_callback(lua, "setHealth", function(value:Float = 0) {
			game.health = value;
		});

		Lua_helper.add_callback(lua, "addHealth", function(value:Float = 0) {
			game.health += value;
		});

		Lua_helper.add_callback(lua, "getHealth", function() {
			return game.health;
		});

		Lua_helper.add_callback(lua, "setRatingPercent", function(value:Float) {
			game.ratingPercent = value;
		});

		Lua_helper.add_callback(lua, "setRatingName", function(value:String) {
			game.ratingName = value;
		});

		Lua_helper.add_callback(lua, "setRatingFC", function(value:String) {
			game.ratingFC = value;
		});

		Lua_helper.add_callback(lua, "setHealthBarColors", function(left:String, right:String) {
			// Psych 0.6.3 语义：left 为未填充侧（对手）颜色，right 为填充侧（玩家）颜色
			game.healthBar.createFilledBar(CoolUtil.colorFromString(left), CoolUtil.colorFromString(right));
			game.healthBar.updateBar();
		});

		Lua_helper.add_callback(lua, "setTimeBarColors", function(left:String, right:String) {
			game.timeBar.setColors(CoolUtil.colorFromString(left), CoolUtil.colorFromString(right));
		});
	}
}
