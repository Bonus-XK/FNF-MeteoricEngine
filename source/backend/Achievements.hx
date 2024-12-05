package backend;

class Achievements {
	public static var achievementsStuff:Array<Dynamic> = [ //Name, Description, Achievement save tag, Hidden achievement
		["周五晚上的怪异Freaky on a Friday Night",	"在星期五的晚上玩这个游戏",						'friday_night_play',	 true],
		["她也叫我爸爸She Calls Me Daddy Too",		"用Hard难度打败第一周且无失误",				'week1_nomiss',			false],
		["不再有技巧No More Tricks",				"用Hard难度打败第二周且无失误",				'week2_nomiss',			false],
		["叫我杀手Call Me The Hitman",			"用Hard难度打败第三周且无失误",				'week3_nomiss',			false],
		["女士杀手Lady Killer",					"用Hard难度打败第四周且无失误",				'week4_nomiss',			false],
		["没有失误的万圣节Missless Christmas",			"用Hard难度打败第五周且无失误",				'week5_nomiss',			false],
		["高分！！Highscore!!",					"用Hard难度打败第六周且无失误",				'week6_nomiss',			false],
		["该死的！God Effing Damn It!",			"用Hard难度打败第七周且无失误",				'week7_nomiss',			false],
		["多么有趣的灾难！What a Funkin' Disaster!",	"完成一首准确率低于20%的曲目",	'ur_bad',				false],
		["完美主义者 Perfectionist",				"完成一首准确率为100%的曲目",			'ur_good',				false],
		["公路杀手爱好者 Roadkill Enthusiast",			"看死亡界面50次",			'roadkill_enthusiast',	false],
		["过度说唱……？Oversinging Much...?",		"按住箭头十秒钟",					'oversinging',			false],
		["活跃 Hyperactive",					"在不进入空闲状态的情况下完成一首曲目",				'hype',					false],
		["只有我们两个人 Just the Two of Us",			"只用两个按键完成一首曲目",			'two_keys',				false],
		["烤面包机玩家 Toaster Gamer",				"你有没有尝试过在烤面包机上运行游戏",		'toastie',				false],
		["调试者 Debugger",					"在铺面编辑器加载并打败 Test 曲目",	'debugger',				 true]
	];
	public static var achievementsMap:Map<String, Bool> = new Map<String, Bool>();

	public static var henchmenDeath:Int = 0;
	public static function unlockAchievement(name:String):Void {
		FlxG.log.add('Completed achievement "' + name +'"');
		achievementsMap.set(name, true);
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.7);
	}

	public static function isAchievementUnlocked(name:String) {
		if(achievementsMap.exists(name) && achievementsMap.get(name)) {
			return true;
		}
		return false;
	}

	public static function getAchievementIndex(name:String) {
		for (i in 0...achievementsStuff.length) {
			if(achievementsStuff[i][2] == name) {
				return i;
			}
		}
		return -1;
	}

	public static function loadAchievements():Void {
		if(FlxG.save.data != null) {
			if(FlxG.save.data.achievementsMap != null) {
				achievementsMap = FlxG.save.data.achievementsMap;
			}
			if(henchmenDeath == 0 && FlxG.save.data.henchmenDeath != null) {
				henchmenDeath = FlxG.save.data.henchmenDeath;
			}
		}
	}
}