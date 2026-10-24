package ex;

import hscript.*;
import hscript.Expr;
import hscript.Expr.FieldDecl;
import hscript.Expr.FunctionDecl;
import hscript.Expr.VarDecl;
import hscript.Printer;
import ex.ClassDeclEx;

enum Param
{
	Unused;
}

class ScriptClass
{
	private var _c:ClassDeclEx;
	var _interp:InterpEx;

	public var superClass:Dynamic = null;

	var superClassName:String;

	/** Meteoric：只构造静态成员代理（不执行构造函数 / 不创建实例）。 */
	var _staticOnly:Bool = false;

	/** Meteoric：创建此实例的脚本解释器，用于把宿主变量暴露给类代码。 */
	var _sourceInterp:InterpEx = null;

	/** Meteoric：实例/静态字段独立存储，避免与函数参数同名冲突。 */
	var _fields:Map<String, Dynamic> = new Map();

	public function new(c:ClassDeclEx, args:Array<Dynamic>, ?staticOnly:Bool = false, ?sourceInterp:InterpEx = null)
	{
		_c = c;
		_staticOnly = staticOnly;
		_sourceInterp = sourceInterp;
		_interp = new InterpEx(this, false, null, sourceInterp);
		buildCaches();

		if (!staticOnly)
		{
			var ctorField = findField("new");
			if (ctorField != null)
			{
				callFunction("new", args);
				if (superClass == null && _c.extend != null)
				{
					_interp.reportError("super() not called");
				}
			}
			else if (_c.extend != null)
			{
				createSuperClass(args);
			}
		}
		else if (_c.extend != null)
		{
			createSuperClassStatic();
		}
	}

	public var className(get, null):String;

	private function get_className():String
	{
		var name = "";
		if (_c.pkg != null)
		{
			name += _c.pkg.join(".");
		}
		name += _c.name;
		return name;
	}

	private function superConstructor(arg0:Dynamic = Unused, arg1:Dynamic = Unused, arg2:Dynamic = Unused, arg3:Dynamic = Unused)
	{
		var args = [];
		if (arg0 != Unused)
			args.push(arg0);
		if (arg1 != Unused)
			args.push(arg1);
		if (arg2 != Unused)
			args.push(arg2);
		if (arg3 != Unused)
			args.push(arg3);
		createSuperClass(args);
	}

	private function createSuperClassStatic()
	{
		var extendString = new Printer().typeToString(_c.extend);
		if (_c.pkg != null && extendString.indexOf(".") == -1)
		{
			extendString = _c.pkg.join(".") + "." + extendString;
		}
		superClassName = extendString;
		var classDescriptor = InterpEx.findScriptClassDescriptor(extendString);
		if (classDescriptor != null && _sourceInterp != null && _sourceInterp.classProvider != null)
		{
			superClass = _sourceInterp.classProvider.getClassProxy(extendString);
		}
		else if (classDescriptor != null)
		{
			superClass = new ScriptClass(classDescriptor, [], true, _sourceInterp);
		}
		else
		{
			superClass = Type.resolveClass(extendString);
			if (superClass == null)
				_interp.reportError("could not resolve super class: " + extendString);
		}
	}

	private function createSuperClass(args:Array<Dynamic> = null)
	{
		if (args == null)
		{
			args = [];
		}
		var extendString = new Printer().typeToString(_c.extend);
		if (_c.pkg != null && extendString.indexOf(".") == -1)
		{
			extendString = _c.pkg.join(".") + "." + extendString;
		}
		var classDescriptor = InterpEx.findScriptClassDescriptor(extendString);
		superClassName = extendString;
		if (classDescriptor != null)
		{
			var abstractSuperClass:AbstractScriptClass = new ScriptClass(classDescriptor, args, false, _sourceInterp);
			superClass = abstractSuperClass;
		}
		else
		{
			var c = Type.resolveClass(extendString);
			if (c == null)
			{
				_interp.reportError("could not resolve super class: " + extendString);
			}
			else
			{
				function createSuperClass():Void
					superClass = Type.createInstance(c, args);

				// hscript 没有 SScript.superClassInstances 缓存，直接创建实例
				createSuperClass();
			}
		}
	}

	private inline function callFunction0(name:String)
	{
		return callFunction(name);
	}

	private inline function callFunction1(name:String, arg0:Dynamic)
	{
		return callFunction(name, [arg0]);
	}

	private inline function callFunction2(name:String, arg0:Dynamic, arg1:Dynamic)
	{
		return callFunction(name, [arg0, arg1]);
	}

	private inline function callFunction3(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic)
	{
		return callFunction(name, [arg0, arg1, arg2]);
	}

	private inline function callFunction4(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic)
	{
		return callFunction(name, [arg0, arg1, arg2, arg3]);
	}

	public function callFunction(name:String, args:Array<Dynamic> = null)
	{
		var field = findField(name);
		var r:Dynamic = null;

		if (field != null)
		{
			var fn = findFunction(name);
			if (fn == null)
			{
				_interp.reportError('Field $name is not a function');
				return null;
			}
			var f = findField(name);
			if (f != null)
			{
				if (name != "new" && !f.access.contains(FieldAccess.AOverride))
				{
					if (superClass != null && Reflect.getProperty(superClass, name) != null)
						throw 'Field $name should be declared with \'override\' since it is inherited from superclass $className';
					else
					{
						var className:String = null;
						if (superClass != null)
							className = Type.getClassName(superClass);
						if (className == null)
							className = superClassName;
						var expr = Tools.expr(fn.expr);
						function isSuper(expr:ExprDef)
						{
							var e = expr;
							return switch e
							{
								case EIdent(v):
									if (v == 'super') true; else false;
								case EField(e, _):
									switch Tools.expr(e)
									{
										case EIdent(v):
											if (v == 'super') true; else false;
										case _:
											false;
									}
								case _: false;
							}
						}
						switch expr
						{
							case EBlock(e):
								for (i in e)
								{
									var i = Tools.expr(i);
									if (isSuper(i))
										throw 'Field $name should be declared with \'override\' since it is inherited from superclass $className';
									else
										switch i
										{
											case ECall(e, _):
												if (isSuper(Tools.expr(e)))
													throw 'Field $name should be declared with \'override\' since it is inherited from superclass $className';
											case _:
										}
								}
							case _:
						}
					}
				}
			}
			var previousValues:Map<String, Dynamic> = [];
			var i = 0;
			for (a in fn.args)
			{
				var value:Dynamic = null;

				if (args != null && i < args.length)
				{
					value = args[i];
				}
				else if (a.value != null)
				{
					value = _interp.expr(a.value);
				}

				if (_interp.variables.exists(a.name))
				{
					previousValues.set(a.name, _interp.variables.get(a.name));
				}
				_interp.variables.set(a.name, value);
				i++;
			}

			r = _interp.execute(fn.expr);

			for (a in fn.args)
			{
				if (previousValues.exists(a.name))
				{
					_interp.variables.set(a.name, previousValues.get(a.name));
				}
				else
				{
					_interp.variables.remove(a.name);
				}
			}
		}
		else if (superClass != null)
		{
			if (superClass is ScriptClass)
				return (cast superClass:ScriptClass).callFunction(name, args);

			var fixedArgs = [];
			if (args != null)
			{
				for (a in args)
				{
					if ((a is ScriptClass))
						fixedArgs.push(cast(a, ScriptClass).superClass);
					else
						fixedArgs.push(a);
				}
			}
			var fn = Reflect.field(superClass, name);
			if (fn != null)
				r = Reflect.callMethod(superClass, fn, fixedArgs);
		}
		return r;
	}

	inline function isStaticField(f:FieldDecl):Bool
	{
		return f.access != null && f.access.contains(FieldAccess.AStatic);
	}

	inline function matchesMode(f:FieldDecl):Bool
	{
		return isStaticField(f) == _staticOnly;
	}

	private function findFunction(name:String):FunctionDecl
	{
		if (_cachedFunctionDecls != null)
			return _cachedFunctionDecls.get(name);

		for (f in _c.fields)
		{
			if (f.name == name && matchesMode(f))
			{
				switch (f.kind)
				{
					case KFunction(fn):
						return fn;
					case _:
				}
			}
		}

		return null;
	}

	private function findVar(name:String):VarDecl
	{
		if (_cachedVarDecls != null)
			return _cachedVarDecls.get(name);

		for (f in _c.fields)
		{
			if (f.name == name && matchesMode(f))
			{
				switch (f.kind)
				{
					case KVar(v):
						return v;
					case _:
				}
			}
		}

		return null;
	}

	private function findField(name:String):FieldDecl
	{
		if (_cachedFieldDecls != null)
			return _cachedFieldDecls.get(name);

		for (f in _c.fields)
		{
			if (f.name == name && matchesMode(f))
				return f;
		}

		return null;
	}

	public function hasField(name:String):Bool
	{
		return _fields.exists(name) || findVar(name) != null;
	}

	public function readField(name:String):Dynamic
	{
		if (_fields.exists(name)) return _fields.get(name);
		var v = findVar(name);
		if (v != null && v.expr != null)
		{
			var value = _interp.expr(v.expr);
			_fields.set(name, value);
			return value;
		}
		return null;
	}

	public function writeField(name:String, value:Dynamic):Bool
	{
		if (findVar(name) == null && !_fields.exists(name)) return false;
		_fields.set(name, value);
		return true;
	}

	public function listFunctions():Map<String, FunctionDecl>
		return if (_cachedFunctionDecls != null) _cachedFunctionDecls else new Map();

	private var _cachedFieldDecls:Map<String, FieldDecl> = null;
	private var _cachedFunctionDecls:Map<String, FunctionDecl> = null;
	private var _cachedVarDecls:Map<String, VarDecl> = null;

	private function buildCaches()
	{
		_cachedFieldDecls = [];
		_cachedFunctionDecls = [];
		_cachedVarDecls = [];

		for (f in _c.fields)
		{
			if (!matchesMode(f)) continue;
			_cachedFieldDecls.set(f.name, f);
			switch (f.kind)
			{
				case KFunction(fn):
					_cachedFunctionDecls.set(f.name, fn);
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					if (v.expr != null)
						_fields.set(f.name, this._interp.expr(v.expr));
			}
		}
	}
}