package backend;

#if sys
import sys.io.File;
import lime.system.System;
#end
import flixel.FlxG;

/**
 * 诊断日志：把当前状态名 + 触摸/鼠标状态写入应用目录 diag.txt，
 * 用于排查“触控不生效 / UI 消失”类问题（release 构建 trace 不可见时使用）。
 * 不影响正常游戏逻辑；写完自动关闭。
 */
class Diag
{
	static var lastLog:Float = 0;

	public static function log():Void
	{
		#if sys
		var now:Float = Date.now().getTime();
		if (now - lastLog < 500) return; // 每 500ms 一条
		lastLog = now;

		var touchCount:Int = 0;
		var touchX:Float = -1;
		var touchY:Float = -1;
		var touchDown:Bool = false;
		if (FlxG.touches != null)
		{
			touchCount = FlxG.touches.list.length;
			for (t in FlxG.touches.list)
			{
				if (t.pressed) { touchDown = true; touchX = t.screenX; touchY = t.screenY; }
			}
		}

		var mouseDown:Bool = false;
		if (FlxG.mouse != null) mouseDown = FlxG.mouse.pressed;

		var stateName:String = '?';
		if (FlxG.state != null) stateName = Type.getClassName(Type.getClass(FlxG.state));
		var subName:String = '?';
		if (FlxG.state != null && FlxG.state.subState != null) subName = Type.getClassName(Type.getClass(FlxG.state.subState));

		var line:String = DateTools.format(Date.now(), '%H:%M:%S') + ' | state=' + stateName
			+ ' | sub=' + subName
			+ ' | touches=' + touchCount + (touchDown ? (' down@' + Std.int(touchX) + ',' + Std.int(touchY)) : '')
			+ ' | mouse=' + (FlxG.mouse != null ? Std.int(FlxG.mouse.screenX) + ',' + Std.int(FlxG.mouse.screenY) + (mouseDown ? ' DOWN' : '') : 'null')
			+ '\n';
		try
		{
			var path:String = System.applicationStorageDirectory + 'diag.txt';
			var f = File.append(path, false);
			f.writeString(line);
			f.close();
		}
		catch (e:Dynamic) {}
		#end
	}
}
