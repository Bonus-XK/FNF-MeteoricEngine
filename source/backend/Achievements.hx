package backend;

class Achievements {
	public static var achievementsStuff:Array<Dynamic> = [ //Name, Description, Achievement save tag, Hidden achievement, 触发方式
		[Lang.tOr("achievement.friday_night_play.name", "周五狂欢夜"),
				Lang.tOr("achievement.friday_night_play.desc", "在星期五的晚上游玩本游戏"),'friday_night_play',	 true,	Lang.tOr("achievement.friday_night_play.trigger", "在周五 18:00 之后打开游戏")],
		[Lang.tOr("achievement.week1_nomiss.name", "她也叫我爸爸"),
				Lang.tOr("achievement.week1_nomiss.desc", "用困难难度无失误通关第一周"),'week1_nomiss',	 false,	Lang.tOr("achievement.week1_nomiss.trigger", "在故事模式中用困难难度通关第一周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.week2_nomiss.name", "不再耍花招"),
				Lang.tOr("achievement.week2_nomiss.desc", "用困难难度无失误通关第二周"),'week2_nomiss',	 false,	Lang.tOr("achievement.week2_nomiss.trigger", "在故事模式中用困难难度通关第二周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.week3_nomiss.name", "叫我杀手"),
				Lang.tOr("achievement.week3_nomiss.desc", "用困难难度无失误通关第三周"),'week3_nomiss',	 false,	Lang.tOr("achievement.week3_nomiss.trigger", "在故事模式中用困难难度通关第三周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.week4_nomiss.name", "女士杀手"),
				Lang.tOr("achievement.week4_nomiss.desc", "用困难难度无失误通关第四周"),'week4_nomiss',	 false,	Lang.tOr("achievement.week4_nomiss.trigger", "在故事模式中用困难难度通关第四周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.week5_nomiss.name", "无失误的圣诞"),
				Lang.tOr("achievement.week5_nomiss.desc", "用困难难度无失误通关第五周"),'week5_nomiss',	 false,	Lang.tOr("achievement.week5_nomiss.trigger", "在故事模式中用困难难度通关第五周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.week6_nomiss.name", "高分！"),
				Lang.tOr("achievement.week6_nomiss.desc", "用困难难度无失误通关第六周"),'week6_nomiss',	 false,	Lang.tOr("achievement.week6_nomiss.trigger", "在故事模式中用困难难度通关第六周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.week7_nomiss.name", "我的老天！"),
				Lang.tOr("achievement.week7_nomiss.desc", "用困难难度无失误通关第七周"),'week7_nomiss',	 false,	Lang.tOr("achievement.week7_nomiss.trigger", "在故事模式中用困难难度通关第七周，全程无失误（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.ur_bad.name", "多么混乱的演出！"),
				Lang.tOr("achievement.ur_bad.desc", "完成一首准确率低于 20% 的曲目"),'ur_bad',	 false,	Lang.tOr("achievement.ur_bad.trigger", "通关一首曲目，最终准确率低于 20%（不可开启练习模式）")],
		[Lang.tOr("achievement.ur_good.name", "完美主义者"),
				Lang.tOr("achievement.ur_good.desc", "完成一首准确率达到 100% 的曲目"),'ur_good',	 false,	Lang.tOr("achievement.ur_good.trigger", "通关一首曲目，最终准确率达到 100%（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.roadkill_enthusiast.name", "公路杀手爱好者"),
				Lang.tOr("achievement.roadkill_enthusiast.desc", "目睹死亡界面 50 次"),'roadkill_enthusiast',	 false,	Lang.tOr("achievement.roadkill_enthusiast.trigger", "累计死亡 50 次（累计看到 50 次死亡界面）")],
		[Lang.tOr("achievement.oversinging.name", "唱得太投入了……？"),
				Lang.tOr("achievement.oversinging.desc", "长按任意箭头十秒钟"),'oversinging',	 false,	Lang.tOr("achievement.oversinging.trigger", "游玩中长按箭头键累计 10 秒（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.hype.name", "活力四射"),
				Lang.tOr("achievement.hype.desc", "在不进入空闲状态的情况下完成一首曲目"),'hype',	 false,	Lang.tOr("achievement.hype.trigger", "通关一首曲目且全程未触发空闲动画（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.two_keys.name", "只有我们两个"),
				Lang.tOr("achievement.two_keys.desc", "只用两个按键完成一首曲目"),'two_keys',	 false,	Lang.tOr("achievement.two_keys.trigger", "只用两个或更少的按键通关一首曲目（不可开启练习或自动游玩）")],
		[Lang.tOr("achievement.toastie.name", "烤面包机玩家"),
				Lang.tOr("achievement.toastie.desc", "你有没有尝试过在烤面包机上运行游戏"),'toastie',	 false,	Lang.tOr("achievement.toastie.trigger", "开启低画质、关闭着色器与抗锯齿后通关一首曲目")],
		[Lang.tOr("achievement.debugger.name", "调试者"),
				Lang.tOr("achievement.debugger.desc", "在谱面编辑器加载并通关测试曲目"),'debugger',	 true,	Lang.tOr("achievement.debugger.trigger", "在谱面编辑器中加载测试曲目并通关（不可开启练习或自动游玩）")]
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
