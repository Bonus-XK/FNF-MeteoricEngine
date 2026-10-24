/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package hscript;
import haxe.PosInfos;
import hscript.Expr;
import haxe.Constraints.IMap;

private enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

class Interp {

	public var variables : Map<String,Dynamic>;
	public var locals : Map<String,{ r : Dynamic }>;
	var binops : Map<String, Expr -> Expr -> Dynamic >;

	var depth : Int;
	var inTry : Bool;
	var declared : Array<{ n : String, old : { r : Dynamic } }>;
	var returnValue : Dynamic;

	// Meteoric: import / using / package 支持
	public var imports : Map<String, Dynamic>;       // 导入的符号名 -> 类/值（import a.b as c / import a.b）
	public var usingPrefixes : Array<Array<String>>; // using 前缀列表（using a.b / import a.b.*）
	public var currentPackage : Null<Array<String>>; // 当前 package 声明

	// Meteoric: 脚本类壳实例支持（移植自 hscript-improved CustomClassHandler）
	public var errorHandler : Error -> Void; // error() 触发时的回调（hscriptPos 下为包装类 Error），默认 null = 零行为变化
	public var scriptObject : Dynamic;                                           // 壳实例反向引用（interp 所属对象）

	#if hscriptPos
	var curExpr : Expr;
	#end

	public function new() {
		locals = new Map();
		declared = new Array();
		resetVariables();
		imports = new Map<String, Dynamic>();
		usingPrefixes = new Array<Array<String>>();
		currentPackage = null;
		initOps();
	}

	private function resetVariables(){
		variables = new Map<String,Dynamic>();
		variables.set("null",null);
		variables.set("true",true);
		variables.set("false",false);
		variables.set("trace", Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if( el.length > 0 ) inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function posInfos(): PosInfos {
		#if hscriptPos
			if (curExpr != null)
				return cast { fileName : curExpr.origin, lineNumber : curExpr.line };
		#end
		return cast { fileName : "hscript", lineNumber : 0 };
	}

	function initOps() {
		var me = this;
		binops = new Map();
		binops.set("+",function(e1,e2) return me.expr(e1) + me.expr(e2));
		binops.set("-",function(e1,e2) return me.expr(e1) - me.expr(e2));
		binops.set("*",function(e1,e2) return me.expr(e1) * me.expr(e2));
		binops.set("/",function(e1,e2) return me.expr(e1) / me.expr(e2));
		binops.set("%",function(e1,e2) return me.expr(e1) % me.expr(e2));
		binops.set("&",function(e1,e2) return me.expr(e1) & me.expr(e2));
		binops.set("|",function(e1,e2) return me.expr(e1) | me.expr(e2));
		binops.set("^",function(e1,e2) return me.expr(e1) ^ me.expr(e2));
		binops.set("<<",function(e1,e2) return me.expr(e1) << me.expr(e2));
		binops.set(">>",function(e1,e2) return me.expr(e1) >> me.expr(e2));
		binops.set(">>>",function(e1,e2) return me.expr(e1) >>> me.expr(e2));
		binops.set("==",function(e1,e2) return me.expr(e1) == me.expr(e2));
		binops.set("!=",function(e1,e2) return me.expr(e1) != me.expr(e2));
		binops.set(">=",function(e1,e2) return me.expr(e1) >= me.expr(e2));
		binops.set("<=",function(e1,e2) return me.expr(e1) <= me.expr(e2));
		binops.set(">",function(e1,e2) return me.expr(e1) > me.expr(e2));
		binops.set("<",function(e1,e2) return me.expr(e1) < me.expr(e2));
		binops.set("||",function(e1,e2) return me.expr(e1) == true || me.expr(e2) == true);
		// Meteoric: null 合并 a ?? b —— 左侧非 null 取左侧，否则求右侧
		binops.set("??",function(e1,e2) { var v = me.expr(e1); return v == null ? me.expr(e2) : v; });
		binops.set("&&",function(e1,e2) return me.expr(e1) == true && me.expr(e2) == true);
		binops.set("=",assign);
		binops.set("...",function(e1,e2) return new IntIterator(me.expr(e1),me.expr(e2)));
		binops.set("is",function(e1,e2) return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (me.expr(e1), me.expr(e2)));
		assignOp("+=",function(v1:Dynamic,v2:Dynamic) return v1 + v2);
		assignOp("-=",function(v1:Float,v2:Float) return v1 - v2);
		assignOp("*=",function(v1:Float,v2:Float) return v1 * v2);
		assignOp("/=",function(v1:Float,v2:Float) return v1 / v2);
		assignOp("%=",function(v1:Float,v2:Float) return v1 % v2);
		assignOp("&=",function(v1,v2) return v1 & v2);
		assignOp("|=",function(v1,v2) return v1 | v2);
		assignOp("^=",function(v1,v2) return v1 ^ v2);
		assignOp("<<=",function(v1,v2) return v1 << v2);
		assignOp(">>=",function(v1,v2) return v1 >> v2);
		assignOp(">>>=",function(v1,v2) return v1 >>> v2);
		// Meteoric: null 合并赋值 a ??= b —— a 为 null 时才赋 b
		assignOp("??=",function(v1:Dynamic,v2:Dynamic) return v1 == null ? v2 : v1);
	}

	function setVar( name : String, v : Dynamic ) {
		variables.set(name, v);
		return v;
	}

	function assign( e1 : Expr, e2 : Expr ) : Dynamic {
		var v = expr(e2);
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			var l = locals.get(id);
			if( l == null )
				setVar(id,v)
			else
				l.r = v;
		case EField(e,f):
			v = set(expr(e),f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				setMapValue(arr, index, v);
			}
			else {
				arr[index] = v;
			}

		default:
			error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp( op, fop : Dynamic -> Dynamic -> Dynamic ) {
		var me = this;
		binops.set(op,function(e1,e2) return me.evalAssignOp(op,fop,e1,e2));
	}

	function evalAssignOp(op,fop,e1,e2) : Dynamic {
		var v;
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			var l = locals.get(id);
			v = fop(expr(e1),expr(e2));
			if( l == null )
				setVar(id,v)
			else
				l.r = v;
		case EField(e,f):
			var obj = expr(e);
			v = fop(get(obj,f),expr(e2));
			v = set(obj,f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				v = fop(getMapValue(arr, index), expr(e2));
				setMapValue(arr, index, v);
			}
			else {
				v = fop(arr[index],expr(e2));
				arr[index] = v;
			}
		default:
			return error(EInvalidOp(op));
		}
		return v;
	}

	function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch(e) {
		case EIdent(id):
			var l = locals.get(id);
			var v : Dynamic = (l == null) ? resolve(id) : l.r;
			if( prefix ) {
				v += delta;
				if( l == null ) setVar(id,v) else l.r = v;
			} else
				if( l == null ) setVar(id,v + delta) else l.r = v + delta;
			return v;
		case EField(e,f):
			var obj = expr(e);
			var v : Dynamic = get(obj,f);
			if( prefix ) {
				v += delta;
				set(obj,f,v);
			} else
				set(obj,f,v + delta);
			return v;
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				var v = getMapValue(arr, index);
				if (prefix) {
					v += delta;
					setMapValue(arr, index, v);
				}
				else {
					setMapValue(arr, index, v + delta);
				}
				return v;
			}
			else {
				var v = arr[index];
				if( prefix ) {
					v += delta;
					arr[index] = v;
				} else
					arr[index] = v + delta;
				return v;
			}
		default:
			return error(EInvalidOp((delta > 0)?"++":"--"));
		}
	}

	public function execute( expr : Expr ) : Dynamic {
		depth = 0;
		locals = new Map();
		declared = new Array();
		return exprReturn(expr);
	}

	public function exprReturn(e) : Dynamic {
		try {
			return expr(e);
		} catch( e : Stop ) {
			switch( e ) {
			case SBreak: throw "Invalid break";
			case SContinue: throw "Invalid continue";
			case SReturn:
				var v = returnValue;
				returnValue = null;
				return v;
			}
		}
		return null;
	}

	public function duplicate<T>( h : Map<String,T> ) {
		var h2 = new Map();
		for( k in h.keys() )
			h2.set(k,h.get(k));
		return h2;
	}

	function restore( old : Int ) {
		while( declared.length > old ) {
			var d = declared.pop();
			locals.set(d.n,d.old);
		}
	}

	inline function error(e : #if hscriptPos ErrorDef #else Error #end, rethrow=false ) : Dynamic {
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
		// Meteoric: errorHandler 回调（脚本类壳实例等外部使用方注册）；为 null 时零行为变化
		if (errorHandler != null) errorHandler(e);
		if( rethrow ) this.rethrow(e) else throw e;
		return null;
	}

	inline function rethrow( e : Dynamic ) {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	function resolve( id : String ) : Dynamic {
		var v = variables.get(id);
		if( v != null || variables.exists(id) )
			return v;
		// Meteoric: 查导入的符号（import a.b / import a.b as c）
		if( imports.exists(id) )
			return imports.get(id);
		// Meteoric: 查 using / 通配符导入的包前缀（using a.b / import a.b.*）
		for( prefix in usingPrefixes ) {
			var c = Type.resolveClass(prefix.join(".") + "." + id);
			if( c != null ) return c;
		}
		error(EUnknownVariable(id));
		return null;
	}

	// Meteoric: 注册 import 声明，供 resolve() 查找
	public function registerImport( path : Array<String>, star : Bool, ?asName : Null<String> ) : Void {
		if( path == null || path.length == 0 ) return;
		if( star ) {
			// import a.b.*：记录包前缀，resolve(id) 时尝试 a.b.id
			usingPrefixes.push(path.copy());
		} else if( asName != null ) {
			// import a.b.c as x：绑定到别名 x
			var c = Type.resolveClass(path.join("."));
			imports.set(asName, c);
		} else {
			// import a.b.c：绑定到最后一个路径组件 c
			var last = path[path.length - 1];
			var c = Type.resolveClass(path.join("."));
			imports.set(last, c);
		}
	}

	// Meteoric: 注册 using 声明
	public function registerUsing( path : Array<String> ) : Void {
		if( path == null || path.length == 0 ) return;
		usingPrefixes.push(path.copy());
	}

	// Meteoric: 注册 package 声明
	public function registerPackage( path : Array<String> ) : Void {
		if( path == null || path.length == 0 ) return;
		currentPackage = path.copy();
	}

	public function expr( e : Expr ) : Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch( e ) {
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			}
		case EIdent(id):
			var l = locals.get(id);
			if( l != null )
				return l.r;
			return resolve(id);
		case EVar(n,_,e):
			declared.push({ n : n, old : locals.get(n) });
			locals.set(n,{ r : (e == null)?null:expr(e) });
			return null;
		case EVars(tmp, vars, src):
			// Meteoric: 解构声明 var [a,b] = arr —— 源只求值一次，N 个变量按片段取值
			var sv = src == null ? null : expr(src);
			declared.push({ n : tmp, old : locals.get(tmp) });
			locals.set(tmp, { r : sv });
			for( v in vars ) {
				declared.push({ n : v.name, old : locals.get(v.name) });
				locals.set(v.name, { r : expr(v.e) });
			}
			return null;
		case EParent(e):
			return expr(e);
		case EBlock(exprs):
			var old = declared.length;
			var v = null;
			for( e in exprs )
				v = expr(e);
			restore(old);
			return v;
		case EField(e,f):
			return get(expr(e),f);
		case EBinop(op,e1,e2):
			var fop = binops.get(op);
			if( fop == null ) error(EInvalidOp(op));
			return fop(e1,e2);
		case EUnop(op,prefix,e):
			switch(op) {
			case "!":
				return expr(e) != true;
			case "-":
				return -expr(e);
			case "++":
				return increment(e,prefix,1);
			case "--":
				return increment(e,prefix,-1);
			case "~":
				return ~expr(e);
			default:
				error(EInvalidOp(op));
			}
		case ECall(e,params):
			var args = new Array();
			for( p in params ) {
				// Meteoric: spread 调用 f(...arr) —— EUnop("...",...) 展开可迭代对象
				switch( Tools.expr(p) ) {
				case EUnop("...", _, inner):
					var spread:Dynamic = expr(inner);
					if( spread != null ) {
						var sit = makeIterator(spread);
						while( sit.hasNext() ) args.push(sit.next());
					}
				default:
					args.push(expr(p));
				}
			}

			switch( Tools.expr(e) ) {
			case EField(e,f):
				var obj = expr(e);
				if( obj == null ) error(EInvalidAccess(f));
				return fcall(obj,f,args);
			default:
				return call(null,expr(e),args);
			}
		case EIf(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else if( e2 == null ) null else expr(e2);
		case EWhile(econd,e):
			whileLoop(econd,e);
			return null;
		case EDoWhile(econd,e):
			doWhileLoop(econd,e);
			return null;
		case EFor(v,it,e):
			forLoop(v,it,e);
			return null;
		case EForGen(it,e):
			Tools.getKeyIterator(it, function(vk,vv,it) {
				if( vk == null ) {
					#if hscriptPos
					curExpr = it;
					#end
					error(ECustom("Invalid for expression"));
					return;
				}
				forKeyValueLoop(vk,vv,it,e);
			});
			return null;
		case EBreak:
			throw SBreak;
		case EContinue:
			throw SContinue;
		case EReturn(e):
			returnValue = e == null ? null : expr(e);
			throw SReturn;
		case EFunction(params,fexpr,name,_):
			var capturedLocals = duplicate(locals);
			var me = this;
			var hasOpt = false, minParams = 0;
			// Meteoric: rest 参数 function f(a, ...rest) —— 收集剩余参数为数组
			var restIdx = -1;
			for( i in 0...params.length ) {
				var p = params[i];
				if( p.rest ) { restIdx = i; continue; }
				if( p.opt ) hasOpt = true; else minParams++;
			}
			var fixedCount = restIdx >= 0 ? restIdx : params.length;
			var f = function(args:Array<Dynamic>) {
				var argCount = (args == null) ? 0 : args.length;
				if( restIdx >= 0 ) {
					if( argCount < fixedCount ) {
						var str = "Invalid number of parameters. Got " + argCount + ", required " + fixedCount;
						if( name != null ) str += " for function '" + name+"'";
						error(ECustom(str));
					}
				} else if( argCount != params.length ) {
					if( argCount < minParams ) {
						var str = "Invalid number of parameters. Got " + argCount + ", required " + minParams;
						if( name != null ) str += " for function '" + name+"'";
						error(ECustom(str));
					}
					// make sure mandatory args are forced
					var args2 = [];
					var extraParams = argCount - minParams;
					var pos = 0;
					for( p in params )
						if( p.opt ) {
							if( extraParams > 0 ) {
								args2.push(args[pos++]);
								extraParams--;
							} else
								args2.push(null);
						} else
							args2.push(args[pos++]);
					args = args2;
				}
				var old = me.locals, depth = me.depth;
				me.depth++;
				me.locals = me.duplicate(capturedLocals);
				if( restIdx >= 0 ) {
					for( i in 0...fixedCount )
						me.locals.set(params[i].name,{ r : args[i] });
					var restArr:Array<Dynamic> = [];
					var pos = fixedCount;
					while( pos < argCount ) restArr.push(args[pos++]);
					me.locals.set(params[restIdx].name,{ r : restArr });
				} else {
					for( i in 0...params.length )
						me.locals.set(params[i].name,{ r : args[i] });
				}
				var r = null;
				var oldDecl = declared.length;
				if( inTry )
					try {
						r = me.exprReturn(fexpr);
					} catch( e : Dynamic ) {
						restore(oldDecl);
						me.locals = old;
						me.depth = depth;
						#if neko
						neko.Lib.rethrow(e);
						#else
						throw e;
						#end
					}
				else
					r = me.exprReturn(fexpr);
				restore(oldDecl);
				me.locals = old;
				me.depth = depth;
				return r;
			};
			var f = Reflect.makeVarArgs(f);
			if( name != null ) {
				if( depth == 0 ) {
					// global function
					variables.set(name, f);
				} else {
					// function-in-function is a local function
					declared.push( { n : name, old : locals.get(name) } );
					var ref = { r : f };
					locals.set(name, ref);
					capturedLocals.set(name, ref); // allow self-recursion
				}
			}
			return f;
		case EArrayDecl(arr):
			if( arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _)) ) {
				var keys = [];
				var values = [];
				for( e in arr ) {
					switch(Tools.expr(e)) {
					case EBinop("=>", eKey, eValue):
						keys.push(expr(eKey));
						values.push(expr(eValue));
					default:
						#if hscriptPos
						curExpr = e;
						#end
						error(ECustom("Invalid map key=>value expression"));
					}
				}
				return makeMap(keys,values);
			} else {
				var a = new Array();
				for( e in arr )
					a.push(expr(e));
				return a;
			}
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if( isMap(arr) )
				return getMapValue(arr, index);
			return arr[index];
		case ENew(cl,params):
			var a = new Array();
			for( e in params )
				a.push(expr(e));
			return cnew(cl,a);
		case EThrow(e):
			throw expr(e);
		case ETry(e,n,_,ecatch):
			var old = declared.length;
			var oldTry = inTry;
			try {
				inTry = true;
				var v : Dynamic = expr(e);
				restore(old);
				inTry = oldTry;
				return v;
			} catch( err : Stop ) {
				inTry = oldTry;
				throw err;
			} catch( err : Dynamic ) {
				// restore vars
				restore(old);
				inTry = oldTry;
				// declare 'v'
				declared.push({ n : n, old : locals.get(n) });
				locals.set(n,{ r : err });
				var v : Dynamic = expr(ecatch);
				restore(old);
				return v;
			}
		case EObject(fl):
			var o = {};
			for( f in fl )
				set(o,f.name,expr(f.e));
			return o;
		case ETernary(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else expr(e2);
		case ESwitch(e, cases, def):
			var val : Dynamic = expr(e);
			var match = false;
			for( c in cases ) {
				for( v in c.values )
					if( expr(v) == val ) {
						// Meteoric: switch 守卫 case v if (cond): —— guard 失败则尝试下一个 case
						if( c.guard == null || expr(c.guard) == true )
							match = true;
						break;
					}
				if( match ) {
					val = expr(c.expr);
					break;
				}
			}
			if( !match )
				val = def == null ? null : expr(def);
			return val;
		case EMeta(meta, args, e):
			return exprMeta(meta, args, e);
		case ECheckType(e,_), ECast(e,_):
			return expr(e);
		}
		return null;
	}

	function exprMeta(meta,args,e) : Dynamic {
		return expr(e);
	}

	function doWhileLoop(econd,e) {
		var old = declared.length;
		do {
			if( !loopRun(() -> expr(e)) )
				break;
		}
		while( expr(econd) == true );
		restore(old);
	}

	function whileLoop(econd,e) {
		var old = declared.length;
		while( expr(econd) == true ) {
			if( !loopRun(() -> expr(e)) )
				break;
		}
		restore(old);
	}

	function makeIterator( v : Dynamic ) : Iterator<Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if( v is Array )
			return (v : Array<Dynamic>).iterator();
		if( v.iterator != null ) v = v.iterator();
		#else
		// Meteoric: hxcpp 下 Dynamic.iterator() 动态调用不稳定，集合类型显式分支
		#if cpp
		if( v is Array ) return (cast v : Array<Dynamic>).iterator();
		if( v is DynamicMap ) return (cast v : DynamicMap).iterator();
		if( v is haxe.ds.StringMap ) return (cast v : haxe.ds.StringMap<Dynamic>).iterator();
		if( v is haxe.ds.IntMap ) return (cast v : haxe.ds.IntMap<Dynamic>).iterator();
		if( v is haxe.ds.ObjectMap ) return (cast v : haxe.ds.ObjectMap<Dynamic,Dynamic>).iterator();
		#end
		#if (cpp) if ( v.iterator != null ) #end
			try v = v.iterator() catch( e : Dynamic ) {};
		#end
		if( v.hasNext == null || v.next == null ) error(EInvalidIterator(v));
		return v;
	}

	function makeKeyValueIterator( v : Dynamic ) : KeyValueIterator<Dynamic,Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if( v is Array )
			return (v : Array<Dynamic>).keyValueIterator();
		if( v.keyValueIterator != null ) v = v.keyValueIterator();
		#else
		// Meteoric: hxcpp 下 Dynamic.keyValueIterator() 动态调用不稳定，集合类型显式分支
		#if cpp
		if( v is Array ) return (cast v : Array<Dynamic>).keyValueIterator();
		if( v is DynamicMap ) return (cast v : DynamicMap).keyValueIterator();
		if( v is haxe.ds.StringMap ) return (cast v : haxe.ds.StringMap<Dynamic>).keyValueIterator();
		if( v is haxe.ds.IntMap ) return (cast v : haxe.ds.IntMap<Dynamic>).keyValueIterator();
		if( v is haxe.ds.ObjectMap ) return (cast v : haxe.ds.ObjectMap<Dynamic,Dynamic>).keyValueIterator();
		#end
		try v = v.keyValueIterator() catch( e : Dynamic ) {};
		#end
		if( v.hasNext == null || v.next == null ) error(EInvalidIterator(v));
		return v;
	}

	function forLoop(n,it,e) {
		var old = declared.length;
		declared.push({ n : n, old : locals.get(n) });
		var it = makeIterator(expr(it));
		while( it.hasNext() ) {
			locals.set(n,{ r : it.next() });
			if( !loopRun(() -> expr(e)) )
				break;
		}
		restore(old);
	}

	function forKeyValueLoop(vk,vv,it,e) {
		var old = declared.length;
		declared.push({ n : vk, old : locals.get(vk) });
		declared.push({ n : vv, old : locals.get(vv) });
		var it = makeKeyValueIterator(expr(it));
		while( it.hasNext() ) {
			var v = it.next();
			locals.set(vk,{ r : v.key });
			locals.set(vv,{ r : v.value });
			if( !loopRun(() -> expr(e)) )
				break;
		}
		restore(old);
	}

	inline function loopRun( f : Void -> Void ) {
		var cont = true;
		try {
			f();
		} catch( err : Stop ) {
			switch( err ) {
			case SContinue:
			case SBreak:
				cont = false;
			case SReturn:
				throw err;
			}
		}
		return cont;
	}

	inline function isMap(o:Dynamic):Bool {
		return (o is IMap);
	}

	inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
		return cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
	}

	inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
		cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, value);
	}

	function makeMap( keys : Array<Dynamic>, values : Array<Dynamic> ) : Dynamic {
		var isAllString:Bool = true;
		var isAllInt:Bool = true;
		var isAllObject:Bool = true;
		var isAllEnum:Bool = true;
		for( key in keys ) {
			isAllString = isAllString && (key is String);
			isAllInt = isAllInt && (key is Int);
			isAllObject = isAllObject && Reflect.isObject(key);
			isAllEnum = isAllEnum && Reflect.isEnumValue(key);
		}

		#if (haxe_ver >= 4.1)
		if( isAllInt ) {
			var m = new Map<Int,Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		if( isAllString ) {
			var m = new Map<String,Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		if( isAllEnum ) {
			var m = new haxe.ds.EnumValueMap<Dynamic,Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		if( isAllObject ) {
			var m = new Map<{},Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		#else
		var m:Dynamic = {
			if ( isAllInt ) new haxe.ds.IntMap<Dynamic>();
			else if ( isAllString ) new haxe.ds.StringMap<Dynamic>();
			else if ( isAllEnum ) new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
			else if ( isAllObject ) new haxe.ds.ObjectMap<Dynamic, Dynamic>();
			else null;
		}
		if( m != null ) {
			for ( n in 0...keys.length )
				setMapValue(m, keys[n], values[n]);
			return m;
		}
		#end
		error(ECustom("Invalid map keys "+keys));
		return null;
	}

	function get( o : Dynamic, f : String ) : Dynamic {
		if ( o == null ) error(EInvalidAccess(f));
		return {
			#if php
				// https://github.com/HaxeFoundation/haxe/issues/4915
				try {
					Reflect.getProperty(o, f);
				} catch (e:Dynamic) {
					Reflect.field(o, f);
				}
			#else
				Reflect.getProperty(o, f);
			#end
		}
	}

	function set( o : Dynamic, f : String, v : Dynamic ) : Dynamic {
		if( o == null ) error(EInvalidAccess(f));
		Reflect.setProperty(o,f,v);
		return v;
	}

	function fcall( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
		return call(o, get(o, f), args);
	}

	function call( o : Dynamic, f : Dynamic, args : Array<Dynamic> ) : Dynamic {
		return Reflect.callMethod(o,f,args);
	}

	function cnew( cl : String, args : Array<Dynamic> ) : Dynamic {
		// Meteoric: `Map` 是抽象类，Type.resolveClass("Map") 为 null；脚本里的 `new Map()`
		//（Map 推导式也生成它）用动态键 IMap 顶替。
		if( cl == "Map" )
			return new DynamicMap();
		var c = Type.resolveClass(cl);
		if( c == null ) c = resolve(cl);
		return Type.createInstance(c,args);
	}

}
