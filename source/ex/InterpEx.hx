package ex;

import hscriptBase.Expr;
import hscriptBase.*;

import tea.backend.SScriptX;

@:access(ex.ScriptClass)
@:access(ex.AbstractScriptClass)
@:access(tea.backend.SScriptX)
class InterpEx extends hscriptBase.Interp
{
	var pkg(default, null):String;

	@:noPrivateAccess private static var interps:Array<InterpEx> = [];
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
		for (i in SScriptX.variables.keys())
			if (!variables.exists(i))
				variables.set(i, SScriptX.variables.get(i));
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

	public static function findScriptClassDescriptor(name:String)
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
			return new ScriptClass(decl, args, false, this);

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
			if (p == null) error(EUnknownVariable(f));
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
			error(EInvalidAccess(f));
		if (o is ModClassRef)
		{
			var p = classProvider != null ? classProvider.getClassProxy((cast o:ModClassRef).name) : null;
			if (p == null) error(EUnknownVariable(f));
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
					var sc:ScriptClass = cast proxy.superClass;
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
			error(EUnknownVariable(f));
		}
		return super.get(o, f);
	}

	override function set(o:Dynamic, f:String, v:Dynamic):Dynamic
	{
		if (o == null)
			error(EInvalidAccess(f));
		if (o is ModClassRef)
		{
			var p = classProvider != null ? classProvider.getClassProxy((cast o:ModClassRef).name) : null;
			if (p == null) error(EUnknownVariable(f));
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
					var sc:ScriptClass = cast proxy.superClass;
					if (sc.writeField(f, v)) return v;
				}
				else if (Reflect.hasField(proxy.superClass, f))
				{
					Reflect.setProperty(proxy.superClass, f, v);
					return v;
				}
			}
			error(EUnknownVariable(f));
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

		error(EUnknownVariable(id));
		return null;
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
					var pkg = pkg.copy();
					if (pkg.length > 1)
					{
						var s = pkg.pop();
						this.pkg = pkg.join('.') + '.$s';
					}
					else
						this.pkg = path[0];
				case DImport(path, _, asIdent):
					var last = path[path.length - 1];
					imports.set(asIdent != null ? asIdent : last, path);
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
						extend: extend,
						implement: c.implement,
						fields: c.fields,
						isExtern: c.isExtern
					};
					registerScriptClass(classDecl);
				case DTypedef(_):
				case _:
			}
		}
	}
}
