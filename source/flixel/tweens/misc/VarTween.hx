package flixel.tweens.misc;

import flixel.tweens.FlxTween;

/**
 * Meteoric 覆盖版（基于 flixel 5.2.2 源码）：
 * 原版 VarTween 对无效目标（null / 无该属性 / 非数值）直接 throw，导致第三方 mod
 * 的一个 `FlxTween.tween(某对象, {x: ...})` 写错就把整局游戏打进报错界面。
 * 这里改为“跳过该项补间 + 打警告”，不影响其它正常补间，也不改变公开 API 与行为时序。
 */
class VarTween extends FlxTween
{
	var _object:Dynamic;
	var _properties:Dynamic;
	var _propertyInfos:Array<VarTweenProperty>;

	function new(options:TweenOptions, ?manager:FlxTweenManager)
	{
		super(options, manager);
	}

	/**
	 * Tweens multiple numeric public properties.
	 *
	 * @param	object		The object containing the properties.
	 * @param	properties	An object containing key/value pairs of properties and target values.
	 * @param	duration	Duration of the tween.
	 */
	public function tween(object:Dynamic, properties:Dynamic, duration:Float):VarTween
	{
		#if FLX_DEBUG
		if (object == null)
			throw "Cannot tween variables of an object that is null.";
		else if (properties == null)
			throw "Cannot tween null properties.";
		#end

		_object = object;
		_properties = properties;
		_propertyInfos = [];
		this.duration = duration;
		start();
		initializeVars();
		return this;
	}

	override function update(elapsed:Float):Void
	{
		var delay:Float = (executions > 0) ? loopDelay : startDelay;

		// Leave properties alone until delay is over
		if (_secondsSinceStart < delay)
			super.update(elapsed);
		else
		{
			// Wait until the delay is done to set the starting values of tweens
			// （Meteoric：全部属性被跳过时 _propertyInfos 为空，原版 _propertyInfos[0] 会 NRE）
			if (_propertyInfos.length > 0 && Math.isNaN(_propertyInfos[0].startValue))
				setStartValues();

			super.update(elapsed);

			if (active)
				for (info in _propertyInfos)
					Reflect.setProperty(info.object, info.field, info.startValue + info.range * scale);
		}
	}

	function initializeVars():Void
	{
		var fieldPaths:Array<String>;
		if (Reflect.isObject(_properties))
			fieldPaths = Reflect.fields(_properties);
		else
			throw "Unsupported properties container - use an object containing key/value pairs.";

		for (fieldPath in fieldPaths)
		{
			var target = _object;
			var path = fieldPath.split(".");
			var field = path.pop();
			var broken:Bool = false;
			for (component in path)
			{
				target = Reflect.getProperty(target, component);
				if (!Reflect.isObject(target))
				{
					broken = true;
					break;
				}
			}
			if (broken)
			{
				trace('[VarTween] 跳过无效属性路径 "' + fieldPath + '"（中间对象缺失）');
				continue;
			}
			if (target == null || Reflect.getProperty(target, field) == null)
			{
				trace('[VarTween] 跳过无效属性 "' + fieldPath + '"（目标或值为 null）');
				continue;
			}
			var range:Dynamic = Reflect.getProperty(_properties, fieldPath);
			if (range == null || (!Std.isOfType(range, Float) && !Std.isOfType(range, Int)))
			{
				trace('[VarTween] 跳过无效属性 "' + fieldPath + '"（目标值非数值）');
				continue;
			}

			_propertyInfos.push({
				object: target,
				field: field,
				startValue: Math.NaN, // gets set after delay
				range: range
			});
		}
	}

	function setStartValues()
	{
		for (info in _propertyInfos)
		{
			var value:Dynamic = Reflect.getProperty(info.object, info.field);
			if (value == null || (!Std.isOfType(value, Float) && !Std.isOfType(value, Int)) || Math.isNaN(value))
			{
				trace('[VarTween] 跳过无效属性 "' + info.field + '"（起始值缺失/非数值）');
				continue;
			}

			info.startValue = value;
			info.range = info.range - value;
		}
	}

	override public function destroy():Void
	{
		super.destroy();
		_object = null;
		_properties = null;
		_propertyInfos = null;
	}

	override function isTweenOf(object:Dynamic, ?field:String):Bool
	{
		if (object == _object && field == null)
			return true;

		for (property in _propertyInfos)
		{
			if (object == property.object && (field == property.field || field == null))
				return true;
		}

		return false;
	}
}

private typedef VarTweenProperty =
{
	object:Dynamic,
	field:String,
	startValue:Float,
	range:Float
}
