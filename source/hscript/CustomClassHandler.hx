package hscript;

import hscript.Expr;

using StringTools;

/**
 * Meteoric: 脚本类运行时处理器（移植自 hscript-improved CustomClassHandler）。
 *
 * 脚本 `class Foo extends FlxSprite` 注册为 CustomClassHandler；`new Foo()` 时：
 * 1. 新建专属 Interp，拷贝外层 interp 的 locals/variables（闭包捕获）；
 * 2. `Type.resolveClass('<extend>_HSX')` 创建编译期生成的壳实例（真引擎子类）；
 * 3. 执行脚本类体（方法/变量注册进专属 interp.variables）；
 * 4. `_class.__interp = interp`，壳的 override 方法由此路由到脚本；
 * 5. 调脚本 `new` 构造函数。
 *
 * 与 CNE 原版的差异：
 * - locals 无 depth 概念（官方 hscript 2.7.0 结构），直接全量拷贝；
 * - extend 解析失败抛 ECustom（我们的 ErrorDef 无 EInvalidClass）。
 */
class CustomClassHandler implements IHScriptCustomConstructor {
	public static var staticHandler = new StaticHandler();

	public var ogInterp:Interp;
	public var name:String;
	public var fields:Array<Expr>;
	public var extend:String;
	public var interfaces:Array<String>;

	public function new(ogInterp:Interp, name:String, fields:Array<Expr>, ?extend:String, ?interfaces:Array<String>) {
		this.ogInterp = ogInterp;
		this.name = name;
		this.fields = fields;
		this.extend = extend;
		this.interfaces = interfaces;
	}

	public function hnew(args:Array<Dynamic>):Dynamic {
		var interp = new Interp();

		interp.errorHandler = ogInterp.errorHandler;

		var cl = extend == null ? cast(TemplateClass, Class<Dynamic>) : Type.resolveClass('${extend}_HSX');
		if (cl == null) {
			#if hscriptPos
			throw ErrorDef.ECustom('could not resolve custom class shell: ' + extend);
			#else
			throw Error.ECustom('could not resolve custom class shell: ' + extend);
			#end
		}

		var _class = Type.createInstance(cl, args);

		var capturedLocals:Map<String, {r: Dynamic}> = ogInterp.duplicate(ogInterp.locals);

		var disallowCopy = Type.getInstanceFields(cl);

		for (key => value in capturedLocals) {
			if (!disallowCopy.contains(key)) {
				interp.locals.set(key, {r: value});
			}
		}
		for (key => value in ogInterp.variables) {
			if (!disallowCopy.contains(key)) {
				interp.variables.set(key, value);
			}
		}

		for (expr in fields) {
			interp.exprReturn(expr);
		}

		interp.variables.set("super", staticHandler);

		_class.__interp = interp;
		interp.scriptObject = _class;

		var newFunc = interp.variables.get("new");
		if (newFunc != null) {
			Reflect.callMethod(null, newFunc, args);
		}

		return _class;
	}

	public function toString():String {
		return name;
	}
}

/**
 * 无基类脚本类的兜底模板（extends 省略时使用）。
 */
class TemplateClass implements IHScriptCustomBehaviour {
	public var __interp:Interp;

	public function new() {}

	public function hset(name:String, val:Dynamic):Dynamic {
		if (this.__interp.variables.exists("set_" + name)) {
			return this.__interp.variables.get("set_" + name)(val);
		}
		if (this.__interp.variables.exists(name)) {
			this.__interp.variables.set(name, val);
			return val;
		}
		Reflect.setProperty(this, name, val);
		return Reflect.field(this, name);
	}

	public function hget(name:String):Dynamic {
		if (this.__interp.variables.exists("get_" + name))
			return this.__interp.variables.get("get_" + name)();
		if (this.__interp.variables.exists(name))
			return this.__interp.variables.get(name);
		return Reflect.getProperty(this, name);
	}
}

/**
 * `super` 占位（脚本类里 super.xxx 的静态转发目标；CNE 原版亦为空壳）。
 */
class StaticHandler {
	public function new() {}
}
