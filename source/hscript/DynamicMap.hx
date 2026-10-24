package hscript;

import haxe.Constraints.IMap;

/**
 * Meteoric: 动态键 Map（`new Map()` / Map 推导式的运行时容器）。
 *
 * hscript 的 `new Map()` 在运行期没有对应类（Map 是抽象），因此脚本侧统一落到这里：
 * 键按 Haxe `==` 语义比较，允许 string / int / 对象混合键。规模为脚本级小 Map，
 * 线性查找足够；不使用 Map 集合是为了避免“键类型必须一致”的推断限制。
 */
@:keep
class DynamicMap implements IMap<Dynamic, Dynamic> {
	var keyArr:Array<Dynamic> = [];
	var valArr:Array<Dynamic> = [];

	public function new() {}

	public function get( key:Dynamic ) : Null<Dynamic> {
		for( i in 0...keyArr.length )
			if( keyArr[i] == key )
				return valArr[i];
		return null;
	}

	public function set( key:Dynamic, value:Dynamic ) : Void {
		for( i in 0...keyArr.length )
			if( keyArr[i] == key ) {
				valArr[i] = value;
				return;
			}
		keyArr.push(key);
		valArr.push(value);
	}

	public function exists( key:Dynamic ) : Bool {
		for( k in keyArr )
			if( k == key )
				return true;
		return false;
	}

	public function remove( key:Dynamic ) : Bool {
		for( i in 0...keyArr.length )
			if( keyArr[i] == key ) {
				keyArr.splice(i, 1);
				valArr.splice(i, 1);
				return true;
			}
		return false;
	}

	public function clear() : Void {
		keyArr = [];
		valArr = [];
	}

	public function keys() : Iterator<Dynamic> {
		return keyArr.iterator();
	}

	public function iterator() : Iterator<Dynamic> {
		return valArr.iterator();
	}

	public function keyValueIterator() : KeyValueIterator<Dynamic, Dynamic> {
		return new haxe.iterators.MapKeyValueIterator(this);
	}

	public function copy() : IMap<Dynamic, Dynamic> {
		var out = new DynamicMap();
		for( i in 0...keyArr.length ) {
			out.keyArr.push(keyArr[i]);
			out.valArr.push(valArr[i]);
		}
		return out;
	}

	public function toString() : String {
		var parts = [];
		for( i in 0...keyArr.length )
			parts.push(Std.string(keyArr[i]) + " => " + Std.string(valArr[i]));
		return "{" + parts.join(", ") + "}";
	}
}
