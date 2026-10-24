package ex;

import hscript.Expr.FieldDecl;
import hscript.Expr.CType;

/** Meteoric：脚本类的完整描述符。hscript.Expr.ClassDecl 只有基础字段，缺少 imports/pkg，故自建。 */
typedef ClassDeclEx = {
	var imports : Map<String, Array<String>>;
	var pkg : Array<String>;
	var name : String;
	var params : Dynamic;
	var meta : Dynamic;
	var isPrivate : Bool;
	var isExtern : Bool;
	var extend : Null<CType>;
	var implement : Array<CType>;
	var fields : Array<FieldDecl>;
}
