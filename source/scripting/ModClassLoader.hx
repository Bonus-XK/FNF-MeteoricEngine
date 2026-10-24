package scripting;

#if HSCRIPT_ALLOWED
import ex.ClassDeclEx;
import ex.InterpEx;
import ex.ModClassProvider;
import ex.ModClassRef;
import ex.ScriptClass;
import ex.ParserEx;
import hscript.Expr;
import hscript.Expr.ModuleDecl;
import hscript.Printer;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * 模组 Haxe 类库加载器（`mods/<mod>/source/` 下所有 `.hx`）。
 *
 * - 只在「脚本系统总开关」开启时工作。
 * - 类描述符全局注册；静态成员代理按 HScript 实例隔离（见 `ModClassProviderImpl`）。
 * - 只支持普通 class（含 `extends` / `implements` 语法，但解释器只实现 extends）；
 *   typedef / enum / abstract 不注册，import 仍由 HScript 自己处理。
 */
class ModClassLoader
{
	static var loaded:Bool = false;
	static var classOrigins:Map<String, String> = new Map();
	static var shortNames:Map<String, Array<String>> = new Map();
	static var classNames:Array<String> = [];

	public static function isEnabled():Bool
	{
		return ClientPrefs.data != null
			&& ClientPrefs.data.scriptingEnabled
			&& ClientPrefs.data.scriptingModClasses;
	}

	/** HScript 构造时调用；只加载一次，失败也置 loaded，避免每个脚本重复扫盘。 */
	public static function ensureLoaded():Void
	{
		if (!isEnabled())
		{
			// 开关可能在设置里被关掉再打开；关掉时必须清注册表，否则重新打开后
			// loaded 仍为 true，resolver 会一直停留在 null。
			clear();
			return;
		}
		if (loaded)
			return;
		loaded = true;

		#if sys
		var mods:Array<String> = null;
		try
		{
			mods = Mods.parseList().enabled;
		}
		catch (e:Dynamic)
		{
			trace('[ModClasses] failed to read mod list: ' + Std.string(e));
		}
		if (mods != null)
		{
			for (modName in mods)
			{
				if (modName == null || modName.length == 0) continue;
				var root = Paths.mods(modName + '/source');
				if (FileSystem.exists(root) && FileSystem.isDirectory(root))
					scanDirectory(root, modName);
			}
		}
		#end

		trace('[ModClasses] registered ' + classNames.length + ' mod classes');
	}

	/** F5 / Shift+F5 重建脚本前调用：清空注册表并重新扫描。 */
	public static function reload():Void
	{
		clear();
		loaded = false;
		ensureLoaded();
	}

	public static function clear():Void
	{
		for (name in classNames)
			InterpEx.unregisterScriptClass(name);
		classNames = [];
		classOrigins = new Map();
		shortNames = new Map();
		loaded = false;
	}

	public static function resolveClassName(name:String):String
	{
		if (name == null || name.length == 0) return null;
		if (classOrigins.exists(name)) return name;
		if (name.indexOf('.') == -1)
		{
			var names = shortNames.get(name);
			if (names != null && names.length == 1) return names[0];
		}
		return null;
	}

	public static function resolveImport(path:String):Dynamic
	{
		var full = resolveClassName(path);
		return full == null ? null : new ModClassRef(full);
	}

	public static function createProvider(owner:InterpEx):ModClassProvider
	{
		return new ModClassProviderImpl(owner);
	}

	public static function getClassNameList():Array<String>
	{
		return classNames.copy();
	}

	public static function getOrigin(name:String):String
	{
		return classOrigins.get(name);
	}

	#if sys
	static function scanDirectory(dir:String, modName:String):Void
	{
		var entries:Array<String> = null;
		try
		{
			entries = FileSystem.readDirectory(dir);
		}
		catch (e:Dynamic)
		{
			trace('[ModClasses] cannot read directory $dir: ' + Std.string(e));
			return;
		}
		entries.sort(Reflect.compare);
		for (entry in entries)
		{
			var path = dir + '/' + entry;
			if (FileSystem.isDirectory(path))
			{
				scanDirectory(path, modName);
			}
			else if (entry.toLowerCase().endsWith('.hx'))
			{
				loadFile(path);
			}
		}
	}

	static function loadFile(path:String):Void
	{
		try
		{
			var code = File.getContent(path);
			var parser = new ParserEx();
			var module = parser.parseModule(code, path);
			registerModule(module, path);
		}
		catch (e:Dynamic)
		{
			trace('[ModClasses] parse failed $path: ' + Std.string(e));
		}
	}
	#end

	static function registerModule(module:Array<ModuleDecl>, origin:String):Void
	{
		var pkg:Array<String> = null;
		var imports:Map<String, Array<String>> = new Map();
		for (decl in module)
		{
			switch (decl)
			{
				case DPackage(path):
					pkg = path;
				case DImport(path, _, asIdent):
					if (path == null || path.length == 0) continue;
					var last = path[path.length - 1];
					imports.set(asIdent != null ? asIdent : last, path);
				case DClass(c):
					if (c.isExtern) continue;
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
					var full = InterpEx.registerScriptClass(classDecl);
					if (!classOrigins.exists(full))
						classNames.push(full);
					classOrigins.set(full, origin);
					var sameName = shortNames.get(c.name);
					if (sameName == null)
					{
						sameName = [];
						shortNames.set(c.name, sameName);
					}
					if (!sameName.contains(full)) sameName.push(full);
				case DTypedef(_):
				case _:
			}
		}
	}
}

/**
 * 每个 HScript 一份：静态成员代理按脚本隔离。
 * 类描述符共享，所以同一份代码不会因为多个脚本而重复解析。
 */
class ModClassProviderImpl implements ModClassProvider
{
	var owner:InterpEx;
	var cache:Map<String, ScriptClass> = new Map();

	public function new(owner:InterpEx)
	{
		this.owner = owner;
	}

	public function resolveClassName(name:String):String
	{
		return ModClassLoader.resolveClassName(name);
	}

	public function getClassProxy(name:String):ScriptClass
	{
		var full = resolveClassName(name);
		if (full == null) return null;
		var cached = cache.get(full);
		if (cached != null) return cached;
		var decl = InterpEx.findScriptClassDescriptor(full);
		if (decl == null) return null;
		var proxy = new ScriptClass(decl, [], true, owner);
		cache.set(full, proxy);
		return proxy;
	}
}
#end