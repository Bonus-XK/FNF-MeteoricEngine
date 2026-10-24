package ex;

import hscript.Interp;
import hscript.Expr;
import hscript.Expr.ErrorDef;
import hscript.Expr.ModuleDecl;
import hscript.Expr.Argument;
import hscript.Expr.CType;
import hscript.Printer;
import hscript.Tools;
import hscript.CustomClassHandler;
import ex.ClassDeclEx;

@:access(ex.ScriptClass)
@:access(ex.AbstractScriptClass)
class InterpEx extends hscript.Interp
{
	public var pkg(default, null):String;

	/** SScript 库的 tea.SScript 需要跨类访问（原先通过 @:access(hscriptBase.Interp) 现失效）。 */
	public static var interps:Array<InterpEx> = [];
	private var _proxy:AbstractScriptClass = null;
	var origin:String = "SScriptX";

	var changedClasses:Map<String, Array<String>> = new Map();

	/** Meteoric：脚本级 mod 类提供器（实现 getClassProxy(name)）。 */
	public var classProvider:ModClassProvider = null;

	/** Meteoric：类代码里找不到标识符时回退到宿主脚本的变量表。 */
	public var fallbackVariables:Map<String, Dynamic> = null;

	/** Meteoric：宿主脚本顶层的 var 存在 locals（不是 variables），类代码也要能读。 */
	public var fallbackLocals:Dynamic = null;

	public function new(proxy:AbstractScriptClass = null, ?push:Bool = true, ?superClassInstances:Map<String, Dynamic>, ?source:InterpEx = null)
	{
		super();
		_proxy = proxy;
		if (source != null)
		{
			fallbackVariables = source.fallbackVariables != null ? source.fallbackVariables : source.variables;
			fallbackLocals = source.fallbackLocals != null ? source.fallbackLocals : source.locals;
			classProvider = source.classProvider;
		}
		variables.set("Type", Type);
		variables.set("Math", Math);
		variables.set("Std", Std);
		if (push)
			interps.push(this);
	}

	override function posInfos() {
		#if hscriptPos
			if (curExpr != null)
				return cast { fileName : curExpr.origin, lineNumber : curExpr.line };
		#end
		return cast { fileName : "SScriptX", lineNumber : 0 };
	}

	private static var _scriptClassDescriptors:Map<String, ClassDeclEx> = new Map<String, ClassDeclEx>();

	/** Meteoric：把解析出的类描述符注册进全局表（供 ModClassLoader 使用）。 */
	public static function registerScriptClass(c:ClassDeclEx):String
	{
		var name = c.name;
		if (c.pkg != null)
		{
			name = c.pkg.join(".") + "." + name;
		}
		_scriptClassDescriptors.set(name, c);
		return name;
	}

	public static function unregisterScriptClass(name:String):Void
	{
		_scriptClassDescriptors.remove(name);
	}

	public static function clearScriptClassDescriptors():Void
	{
		_scriptClassDescriptors = new Map<String, ClassDeclEx>();
	}

	public static function listScriptClassDescriptors():Map<String, ClassDeclEx>
	{
		return _scriptClassDescriptors.copy();
	}

	public static function findScriptClassDescriptor(name:String):ClassDeclEx
	{
		return _scriptClassDescriptors.get(name);
	}

	override function cnew(cl:String, args:Array<Dynamic>):Dynamic
	{
		var decl = _scriptClassDescriptors.get(cl);
		if (decl == null)
		{
			var alias = variables.get(cl);
			if (alias is ScriptClass)
				decl = cast(alias, ScriptClass)._c;
			else if (alias is ModClassRef)
				decl = _scriptClassDescriptors.get((cast alias:ModClassRef).name);
		}
		if (decl == null && classProvider != null)
		{
			var fullName = classProvider.resolveClassName(cl);
			if (fullName != null)
				decl = _scriptClassDescriptors.get(fullName);
		}
		if (decl != null)
		{
			// Meteoric: extends 目标有 _HSX 壳（CUSTOM_CLASSES 白名单基类）→ CNE 式壳实例路径：
			// 脚本类实例就是壳实例本身（真引擎子类，引擎 API 可接纳），脚本方法经壳 override 路由。
			var shell = findShellForDecl(decl);
			if (shell != null)
				return createShellInstance(decl, shell, args);
			return new ScriptClass(decl, args, false, this);
		}

		if (_proxy != null)
		{
			if (_proxy._c.pkg != null)
			{
				var packagedClass = _proxy._c.pkg.join(".") + "." + cl;
				if (_scriptClassDescriptors.exists(packagedClass))
					return new ScriptClass(_scriptClassDescriptors.get(packagedClass), args, false, this);
			}

			if (_proxy._c.imports != null && _proxy._c.imports.exists(cl))
			{
				var importedClass = _proxy._c.imports.get(cl).join(".");
				if (_scriptClassDescriptors.exists(importedClass))
					return new ScriptClass(_scriptClassDescriptors.get(importedClass), args, false, this);

				var c = Type.resolveClass(importedClass);
				if (c != null)
					return Type.createInstance(c, args);
			}
		}
		return super.cnew(cl, args);
	}

	override function assign(e1:Expr, e2:Expr):Dynamic
	{
		var v = expr(e2);
		switch (Tools.expr(e1))
		{
			case EIdent(id):
				// Meteoric：类字段不再塞进 variables，裸字段赋值要写回 _fields。
				if (_proxy != null && locals.get(id) == null && !variables.exists(id) && _proxy.hasField(id))
				{
					_proxy.writeField(id, v);
					return v;
				}
				if (_proxy != null && locals.get(id) == null && !variables.exists(id) && _proxy.superClass is ScriptClass)
				{
					// 子类方法里直接写继承字段：父类字段存在 _fields，不是 Haxe 反射字段。
					var sc:ScriptClass = cast _proxy.superClass;
					if (sc.hasField(id))
					{
						sc.writeField(id, v);
						return v;
					}
				}
				if (_proxy != null && _proxy.superClass != null && Reflect.hasField(_proxy.superClass, id))
				{
					Reflect.setProperty(_proxy.superClass, id, v);
					return v;
				}
			case _:
		}
		return super.assign(e1, e2);
	}

	override function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic
	{
		if (o is ModClassRef)
		{
			var p = classProvider != null ? classProvider.getClassProxy((cast o:ModClassRef).name) : null;
			if (p == null) error(ErrorDef.EUnknownVariable(f));
			return fcall(p, f, args);
		}
		if ((o is ScriptClass))
		{
			_nextCallObject = null;
			var proxy:ScriptClass = cast(o, ScriptClass);
			return proxy.callFunction(f, args);
		}
		return super.fcall(o, f, args);
	}

	override function call(o:Dynamic, f:Dynamic, args:Array<Dynamic>):Dynamic
	{
		// TODO: not sure if this make sense !! seems hacky, but fn() in hscript wont resolve an object first (this.fn() or super.fn() would work fine)
		if (o == null && _nextCallObject != null)
		{
			o = _nextCallObject;
		}
		var r = super.call(o, f, args);
		_nextCallObject = null;
		return r;
	}

	override function get(o:Dynamic, f:String):Dynamic
	{
		if (o == null)
			error(ErrorDef.EInvalidAccess(f));
		if (o is ModClassRef)
		{
			var p = classProvider != null ? classProvider.getClassProxy((cast o:ModClassRef).name) : null;
			if (p == null) error(ErrorDef.EUnknownVariable(f));
			return get(p, f);
		}
		if ((o is ScriptClass))
		{
			var proxy:ScriptClass = cast(o, ScriptClass);
			if (proxy.hasField(f))
				return proxy.readField(f);
			if (proxy.superClass != null)
			{
				if (proxy.superClass is ScriptClass)
				{
					var sc:ScriptClass = cast _proxy.superClass;
					if (sc.hasField(f)) return sc.readField(f);
				}
				else if (Reflect.hasField(proxy.superClass, f))
					return Reflect.getProperty(proxy.superClass, f);
			}
			try
			{
				var ap:AbstractScriptClass = cast proxy;
				return ap.resolveField(f);
			}
			catch (e:Dynamic) {}
			error(ErrorDef.EUnknownVariable(f));
		}
		// Meteoric: 壳实例的动态访问（hscript-improved 同语义）：
		// 1) _HX_SUPER__ 优先 —— this.method() 防递归（壳 override 查 variables 会路由回脚本）
		// 2) hget 兜底 —— 脚本字段/方法从 __interp.variables 取（引擎字段由 hget 内部 Reflect 回落）
		if ((o is hscript.IHScriptCustomBehaviour))
		{
			if (Reflect.hasField(o, "_HX_SUPER__" + f))
				return Reflect.getProperty(o, "_HX_SUPER__" + f);
			var beh:hscript.IHScriptCustomBehaviour = cast o;
			return beh.hget(f);
		}
		return super.get(o, f);
	}

	override function set(o:Dynamic, f:String, v:Dynamic):Dynamic
	{
		if (o == null)
			error(ErrorDef.EInvalidAccess(f));
		if (o is ModClassRef)
		{
			var p = classProvider != null ? classProvider.getClassProxy((cast o:ModClassRef).name) : null;
			if (p == null) error(ErrorDef.EUnknownVariable(f));
			return set(p, f, v);
		}
		if ((o is ScriptClass))
		{
			var proxy:ScriptClass = cast(o, ScriptClass);
			if (proxy.writeField(f, v))
				return v;
			if (proxy.superClass != null)
			{
				if (proxy.superClass is ScriptClass)
				{
					var sc:ScriptClass = cast _proxy.superClass;
					if (sc.writeField(f, v)) return v;
				}
				else if (Reflect.hasField(proxy.superClass, f))
				{
					Reflect.setProperty(proxy.superClass, f, v);
					return v;
				}
			}
			error(ErrorDef.EUnknownVariable(f));
		}
		// Meteoric: 壳实例的动态写入（hset：脚本字段入 __interp.variables，引擎字段由 hset 内部 Reflect 回落）
		if ((o is hscript.IHScriptCustomBehaviour))
		{
			var beh:hscript.IHScriptCustomBehaviour = cast o;
			return beh.hset(f, v);
		}
		return super.set(o, f, v);
	}

	private var _nextCallObject:Dynamic = null;

	override function resolve(id:String):Dynamic
	{
		_nextCallObject = null;
		if (id == "super" && _proxy != null)
		{
			if (_proxy.superClass == null)
			{
				return _proxy.superConstructor;
			}
			else
			{
				return _proxy.superClass;
			}
		}
		else if (id == "this" && _proxy != null)
		{
			return _proxy;
		}

		var l = locals.get(id);
		if (l != null)
			return l.r;
		var v = variables.get(id);
		if (v != null || variables.exists(id))
			return v;

		if (_proxy != null)
		{
			if (_proxy.hasField(id))
			{
				_nextCallObject = _proxy;
				return _proxy.readField(id);
			}
			if (_proxy.findFunction(id) != null)
			{
				_nextCallObject = _proxy;
				return _proxy.resolveField(id);
			}
			else if (_proxy.superClass is ScriptClass)
			{
				// 子类方法里直接读继承字段：父类字段存在 _fields，不是 Haxe 反射字段。
				var sc:ScriptClass = cast _proxy.superClass;
				if (sc.hasField(id))
				{
					_nextCallObject = sc;
					return sc.readField(id);
				}
			}
			else if (_proxy.superClass != null
				&& (Reflect.hasField(_proxy.superClass, id) || Reflect.getProperty(_proxy.superClass, id) != null))
			{
				_nextCallObject = _proxy.superClass;
				return Reflect.getProperty(_proxy.superClass, id);
			}
			else
			{
				try
				{
					var r = _proxy.resolveField(id);
					_nextCallObject = _proxy;
					return r;
				}
				catch (e:Dynamic) {}
			}

			// Meteoric：类代码 import 的编译期类（短名）
			if (_proxy._c.imports != null && _proxy._c.imports.exists(id))
			{
				var path = _proxy._c.imports.get(id).join(".");
				var c:Dynamic = Type.resolveClass(path);
				if (c == null) c = Type.resolveEnum(path);
				if (c != null) return c;
				if (classProvider != null)
				{
					var p = classProvider.getClassProxy(path);
					if (p != null) return p;
				}
			}
		}

		if (fallbackVariables != null && fallbackVariables.exists(id))
			return fallbackVariables.get(id);

		if (fallbackLocals != null && fallbackLocals.exists(id))
		{
			var local:Dynamic = fallbackLocals.get(id);
			return local.r;
		}

		if (classProvider != null)
		{
			var p = classProvider.getClassProxy(id);
			if (p != null) return p;
		}

		error(ErrorDef.EUnknownVariable(id));
		return null;
	}

	/** 对外暴露的错误上报（供 ScriptClass 调用，hscript.Interp.error 可能不可见）。 */
	public function reportError(msg:String):Void
	{
		error(ErrorDef.ECustom(msg));
	}

	public function addModule(moduleContents:String)
	{
		var parser = new ex.ParserEx();
		var decls = parser.parseModule(moduleContents, this.origin);
		registerModule(decls);
	}

	public function createScriptClassInstance(className:String, args:Array<Dynamic> = null):AbstractScriptClass
	{
		if (args == null)
		{
			args = [];
		}
		var r:AbstractScriptClass = cnew(className, args);
		return r;
	}

	/**
	 * Meteoric: 解析脚本类声明的 extends 目标对应的 _HSX 壳类；非白名单基类返回 null。
	 */
	function findShellForDecl(decl:ClassDeclEx):Null<Class<Dynamic>>
	{
		if (decl.extend == null) return null;
		var extendString = new Printer().typeToString(decl.extend);
		var shell = Type.resolveClass(extendString + "_HSX");
		if (shell != null) return shell;
		// 白名单基类都在 flixel 包（第一期），短名拼包前缀兜底
		if (extendString.indexOf(".") < 0)
		{
			shell = Type.resolveClass("flixel." + extendString + "_HSX");
			if (shell != null) return shell;
		}
		return null;
	}

	/**
	 * Meteoric: CNE 式壳实例创建（CustomClassHandler.hnew 的 InterpEx 移植）。
	 * 新建专属 interp 拷贝外层环境 → 执行脚本类体（方法/变量注册进 variables）→
	 * 创建壳实例并绑定 __interp → 调脚本 new。返回值就是壳实例（真引擎子类）。
	 */
	function createShellInstance(decl:ClassDeclEx, shell:Class<Dynamic>, args:Array<Dynamic>):Dynamic
	{
		var interp = new InterpEx(null, false, null, this);
		interp.errorHandler = errorHandler;

		var capturedLocals = duplicate(locals);
		var disallowCopy = Type.getInstanceFields(shell);

		for (key => value in capturedLocals)
		{
			if (!disallowCopy.contains(key))
				interp.locals.set(key, {r: value});
		}
		for (key => value in variables)
		{
			if (!disallowCopy.contains(key))
				interp.variables.set(key, value);
		}

		// 脚本类体：var 字段直接求值入 variables（与引擎字段同名时让位）；
		// function 字段**不过滤**——override 语义必须注册进 variables，壳 override 才能路由到脚本
		for (f in decl.fields)
		{
			switch (f.kind)
			{
				case KVar(v):
					if (disallowCopy.contains(f.name))
						continue; // 与引擎字段同名：脚本字段让位给引擎字段（CNE 同语义）
					var value:Dynamic = v.expr != null ? interp.exprReturn(v.expr) : null;
					interp.variables.set(f.name, value);
				case KFunction(fn):
					var fexpr:hscript.Expr = Tools.mk(ExprDef.EFunction(fn.args, fn.expr, f.name, fn.ret), fn.expr);
					interp.exprReturn(fexpr);
			}
		}

		interp.variables.set("super", CustomClassHandler.staticHandler);
		interp.variables.set("this", null); // 先占位，创建实例后回填

		var inst = Type.createInstance(shell, args);
		Reflect.setProperty(inst, "__interp", interp);
		interp.scriptObject = inst;
		interp.variables.set("this", inst);

		var newFunc = interp.variables.get("new");
		if (newFunc != null)
			Reflect.callMethod(null, newFunc, args);

		return inst;
	}

	public function registerModule(module:Array<ModuleDecl>)
	{
		var pkg:Array<String> = null;
		var imports:Map<String, Array<String>> = [];
		for (decl in module)
		{
			switch (decl)
			{
				case DPackage(path):
					pkg = path;
					var pkgCopy = pkg.copy();
					if (pkgCopy.length > 1)
					{
						var s = pkgCopy.pop();
						this.pkg = pkgCopy.join('.') + '.$s';
					}
					else
						this.pkg = path[0];
				case DImport(path, star, asIdent):
					// 注册到 Interp，供运行时 resolve() 查找
					this.registerImport(path, star, asIdent);
					if (!star && path != null && path.length > 0)
					{
						var last = path[path.length - 1];
						imports.set(asIdent != null ? asIdent : last, path);
					}
				case DUsing(path):
					// Meteoric: using pkg.Foo；记录前缀，供 resolve() 查找
					this.registerUsing(path);
				case DClass(c):
					var extend = c.extend;
					if (extend != null)
					{
						var superClassPath = new Printer().typeToString(extend);
						if (imports.exists(superClassPath))
						{
							switch (extend)
							{
								case CTPath(_, params):
									extend = CTPath(imports.get(superClassPath), params);
								case _:
							}
						}
					}
					var classDecl:ClassDeclEx = {
						imports: imports,
						pkg: pkg != null ? pkg.copy() : null,
						name: c.name,
						params: c.params,
						meta: c.meta,
						isPrivate: c.isPrivate,
						isExtern: c.isExtern,
						extend: extend,
						implement: c.implement,
						fields: c.fields
					};
					registerScriptClass(classDecl);
				case DTypedef(_):
				case _:
			}
		}
	}
}