package shaders;

import flixel.system.FlxAssets.FlxShader;
import openfl.filters.ShaderFilter;
import openfl.events.Event;
import openfl.geom.Rectangle;
import openfl.Lib;

/**
 * 全局后处理着色器挂载器 —— 模组脚本 API（Lua / HScript）的引擎侧。
 *
 * 挂载点：FlxG.game.setFilters()（flixel/FlxGame.hx 的休眠钩子，原版 FNF 0.2.x CRT 同机制）。
 * 根级 DisplayObject filter：整个画面（所有相机 / HUD / 子状态）合成后过滤**一次**，
 * 不像逐相机 filter 会在重叠区把扫描线叠两层。启用后跨界面常驻，由调用方（模组）负责 disable()。
 *
 * 语义约束（勿破）：
 *  - 默认关闭零行为变化：没有脚本调用 enable() 时，本类不产生任何渲染开销与行为差异。
 *  - 玩家级 shader 总闸 `ClientPrefs.data.shaders` 关闭时，enable() 一律拒绝 —— 不偷偷吃 GPU。
 *  - tick 监听与启用严格成对：startTick/stopTick 各只调一次，shader 为空时 onTick 自动摘除。
 */
class GlobalShaderHandler
{
	/** 内置 shader 注册表：名字 → 工厂。后续内置全局 shader 往这里加。 */
	static var factories:Map<String, Void->FlxShader> = [
		'crt' => function() { return new CRTShader(); }
	];

	static var shader:FlxShader = null;
	static var shaderName:String = '';
	static var tickActive:Bool = false;
	/** enable() 之前的 scrollRect（正常为 null），disable() 时原位复原。 */
	static var savedScrollRect:Rectangle = null;

	public static function isActive():Bool
	{
		return shader != null;
	}

	public static function getActiveName():String
	{
		return shaderName;
	}

	/**
	 * 启用全局 shader（跨界面常驻，模组自行 disable()）。
	 * @param params 可选参数表 {curvature, scan, vignette, rgbsplit}，Lua table / HScript 对象均可，
	 *               缺省项用 shader 自带默认值。未知的键静默忽略。
	 * @return false = 被门禁拒绝 / 名字未注册 / 游戏根对象未就绪
	 */
	public static function enable(name:String, ?params:Dynamic = null):Bool
	{
		if (!ClientPrefs.data.shaders)
		{
			FlxG.log.warn('[GlobalShaderHandler] ClientPrefs 的 shaders 总闸已关闭，拒绝启用');
			return false;
		}
		var factory:Void->FlxShader = factories.get(name);
		if (factory == null)
		{
			FlxG.log.warn('[GlobalShaderHandler] 未注册的全局 shader: $name');
			return false;
		}
		if (FlxG.game == null)
		{
			FlxG.log.warn('[GlobalShaderHandler] 游戏根对象未就绪');
			return false;
		}

		var newShader:FlxShader = factory();
		if (params != null)
		{
			tryApplyParam(newShader, params, 'curvature');
			tryApplyParam(newShader, params, 'scan');
			tryApplyParam(newShader, params, 'scanStrength');
			tryApplyParam(newShader, params, 'vignette');
			tryApplyParam(newShader, params, 'rgbsplit');
			tryApplyParam(newShader, params, 'rgbSplit');
		}

		shader = newShader;
		shaderName = name;
		// 根级 filter：整画面合成后过滤一次
		//
		// ⚠ scrollRect 不是可选项：FlxGame 里藏着「屏幕外的音量条」（FlxSoundTray 隐藏时
		// y = -64），openfl 的 __getRenderBounds **不会跳过 invisible 子对象**，于是
		// FlxGame.getBounds() = (-0.95, -64, 1221.9, 785) —— filter 的离屏纹理被迫比窗口
		// 高 64px，顶部那 64px 是空白。shader 按 0..1 采样就吃到空白，表现为画面顶部
		// 一条黑带（约窗口高度 8%，与 curvature/边框逻辑无关；关掉 shader 直接绘制时
		// 该子对象在屏幕外，所以看不到）。把 scrollRect 钉成窗口矩形，让纹理==窗口。
		if (FlxG.game.scrollRect != null)
			savedScrollRect = FlxG.game.scrollRect.clone();
		else
			savedScrollRect = null;
		applyClip();

		FlxG.game.setFilters([new ShaderFilter(newShader)]);
		startTick();
		backend.CrashHandler.logEvent('globalShader enable: $name');
		return true;
	}

	/** 关闭全局 shader 并回收 tick 监听。未启用时调用是安全空操作。 */
	public static function disable():Void
	{
		stopTick();
		if (FlxG.game != null)
		{
			FlxG.game.setFilters(null);
			FlxG.game.scrollRect = savedScrollRect;
		}
		savedScrollRect = null;
		if (shader != null)
		{
			backend.CrashHandler.logEvent('globalShader disable: $shaderName');
			shader = null;
			shaderName = '';
		}
	}

	/** 运行中改 uniform（动画 / 调参）。未启用或属性名未知返回 false。 */
	public static function setFloat(prop:String, value:Float):Bool
	{
		if (shader == null)
			return false;
		var crt:CRTShader = null;
		if (Std.isOfType(shader, CRTShader))
			crt = cast(shader, CRTShader);
		return crt != null && crt.setUniform(prop, value);
	}

	/** 读 uniform 当前值；未启用或属性名未知返回 null（Lua 侧为 nil）。 */
	public static function getFloat(prop:String):Null<Float>
	{
		if (shader == null)
			return null;
		var crt:CRTShader = null;
		if (Std.isOfType(shader, CRTShader))
			crt = cast(shader, CRTShader);
		return crt != null ? crt.getUniform(prop) : null;
	}

	// ==================== 内部 ====================

	/**
	 * 把根对象的 scrollRect 钉成当前逻辑视口（FlxG.width × FlxG.height）。
	 * 作用有两个：① 让 filter 离屏纹理的 bounds 恰好等于窗口（见 enable() 里的黑带说明）；
	 * ② 窗口尺寸变化（缩放模式切换 / 改窗口大小）后自动跟上，不必重建 shader。
	 */
	static function applyClip():Void
	{
		if (FlxG.game == null)
			return;
		var w:Float = Math.ceil(FlxG.width);
		var h:Float = Math.ceil(FlxG.height);
		var r:Rectangle = FlxG.game.scrollRect;
		if (r != null && r.x == 0 && r.y == 0 && r.width == w && r.height == h)
			return;
		FlxG.game.scrollRect = new Rectangle(0, 0, w, h);
	}

	/** 从 Lua table / HScript 对象里读一个数值参数（照 setShaderFloatArray 的装箱规整经验）。 */
	static function tryApplyParam(target:FlxShader, src:Dynamic, key:String):Void
	{
		var raw:Dynamic = null;
		try
		{
			raw = Reflect.field(src, key);
		}
		catch (_:Dynamic)
		{
			return;
		}
		if (raw == null)
			return;
		var v:Float;
		if (Std.isOfType(raw, Float) || Std.isOfType(raw, Int))
			v = cast raw;
		else
		{
			v = Std.parseFloat(Std.string(raw));
			if (Math.isNaN(v))
				return;
		}
		var crt:CRTShader = null;
		if (Std.isOfType(target, CRTShader))
			crt = cast(target, CRTShader);
		if (crt != null)
			crt.setUniform(key, v);
	}

	static function startTick():Void
	{
		if (tickActive)
			return;
		tickActive = true;
		FlxG.stage.addEventListener(Event.ENTER_FRAME, onTick);
	}

	static function stopTick():Void
	{
		if (!tickActive)
			return;
		tickActive = false;
		if (FlxG.stage != null)
			FlxG.stage.removeEventListener(Event.ENTER_FRAME, onTick);
	}

	/** 每帧 tick uTime（滚动暗带）。shader 为空时自动摘除监听（防御式）。 */
	static function onTick(_):Void
	{
		if (shader == null)
		{
			stopTick();
			return;
		}
		setFloat('time', Lib.getTimer() / 1000.0);
		applyClip();
	}
}
