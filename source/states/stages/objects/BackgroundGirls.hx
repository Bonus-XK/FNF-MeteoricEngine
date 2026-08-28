package states.stages.objects;

class BackgroundGirls extends FlxSprite
{
	var isPissed:Bool = true;
	public function new(x:Float, y:Float)
	{
		super(x, y);

		// BG fangirls dissuaded
		frames = Paths.getSparrowAtlas('weeb/bgFreaks');
		antialiasing = false;
		swapDanceType();

		setGraphicSize(Std.int(width * PlayState.daPixelZoom));
		updateHitbox();
		animation.play('danceLeft');
	}

	var danceDir:Bool = false;

	/** Meteoric：快速重开时原地重置为“构造完成态”（不销毁/重建，避免共享图集被销毁后贴图异常）。
	 *  注意 must 是 isPissed=false（开心动画）：swapDanceType() 是翻转语义，
	 *  重放的 BG Freaks Expression 事件会再翻一次 → 生气，与首次进入完全一致。 */
	public function resetState():Void
	{
		isPissed = false;
		animation.addByIndices('danceLeft', 'BG girls group', CoolUtil.numberArray(14), "", 24, false);
		animation.addByIndices('danceRight', 'BG girls group', CoolUtil.numberArray(30, 15), "", 24, false);
		animation.play('danceLeft');
	}

	public function swapDanceType():Void
	{
		isPissed = !isPissed;
		if(!isPissed) { //Gets unpissed
			animation.addByIndices('danceLeft', 'BG girls group', CoolUtil.numberArray(14), "", 24, false);
			animation.addByIndices('danceRight', 'BG girls group', CoolUtil.numberArray(30, 15), "", 24, false);
		} else { //Pisses
			animation.addByIndices('danceLeft', 'BG fangirls dissuaded', CoolUtil.numberArray(14), "", 24, false);
			animation.addByIndices('danceRight', 'BG fangirls dissuaded', CoolUtil.numberArray(30, 15), "", 24, false);
		}
		dance();
	}

	public function dance():Void
	{
		danceDir = !danceDir;

		if (danceDir)
			animation.play('danceRight', true);
		else
			animation.play('danceLeft', true);
	}
}
