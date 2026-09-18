package substates;

/** stage 向 Game Over 提供的主题资源（角色 / 三种音效）。
 *  null 或省略字段 = 不干预，回退到谱面字段 / 引擎默认值。
 *  由 BaseStage.getGameOverTheme() 提供，PlayState 在进入结算时显式传给 GameOverSubstate 构造函数。 */
typedef GameOverTheme = {
	?characterName:String,
	?deathSoundName:String,
	?loopSoundName:String,
	?endSoundName:String
};
