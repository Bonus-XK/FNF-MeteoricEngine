package scripting.lua;

#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end

class ShaderFunctions
{
	public static function implement(funk:FunkinLua)
	{
		var lua = funk.lua;
		// Psych 0.7 的 setDropShadow（本引擎未实现 drop shadow 渲染，空操作避免模组脚本报错）
		funk.addLocalCallback("setDropShadow", function(obj:String, ?dist:Float = 0, ?ang:Float = 0, ?str:Float = 0, ?x:Float = 0, ?y:Float = 0, ?thr:Float = 0, ?aa:Float = 0, ?r:Float = 0, ?g:Float = 0, ?b:Float = 0) { return false; });
		// shader shit
		funk.addLocalCallback("initLuaShader", function(name:String, ?glslVersion:Int = 120) {
			if(!ClientPrefs.data.shaders) return false;

			#if (!flash && MODS_ALLOWED && sys)
			return funk.initLuaShader(name, glslVersion);
			#else
			FunkinLua.luaTrace("initLuaShader: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
			return false;
		});
		
		funk.addLocalCallback("setSpriteShader", function(obj:String, shader:String) {
			if(!ClientPrefs.data.shaders) return false;

			#if (!flash && MODS_ALLOWED && sys)
			if(!funk.runtimeShaders.exists(shader) && !funk.initLuaShader(shader))
			{
				FunkinLua.luaTrace('setSpriteShader: Shader $shader is missing!', false, false, FlxColor.RED);
				return false;
			}

			var split:Array<String> = obj.split('.');
			var leObj:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				leObj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(leObj != null) {
				backend.CrashHandler.logEvent('setSpriteShader: ' + obj + ' <- ' + shader);
				#if mac
				// macOS：sprite 级 shader 在渲染时必崩（实测极简 shader 也崩，与内容无关），
				// 且 FlxSprite.shader 无 setter、子类无法拦截，只能在此跳过挂载。
				// 模组无需改写；Windows/Linux 走原生行为。
				trace('[setSpriteShader] macOS 跳过 sprite shader（渲染层会崩）: ' + obj + ' <- ' + shader);
				return false;
				#else
				var arr:Array<String> = funk.runtimeShaders.get(shader);
				leObj.shader = new FlxRuntimeShader(arr[0], arr[1]);
				return true;
				#end
			}
			#else
			FunkinLua.luaTrace("setSpriteShader: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
			return false;
		});
		Lua_helper.add_callback(lua, "removeSpriteShader", function(obj:String) {
			var split:Array<String> = obj.split('.');
			var leObj:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
			if(split.length > 1) {
				leObj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
			}

			if(leObj != null) {
				leObj.shader = null;
				(cast leObj : Dynamic).filters = null; // 与 setSpriteShader 的 filter 路径配对清理
				return true;
			}
			return false;
		});


		Lua_helper.add_callback(lua, "getShaderBool", function(obj:String, prop:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				FunkinLua.luaTrace("getShaderBool: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return null;
			}
			return shader.getBool(prop);
			#else
			FunkinLua.luaTrace("getShaderBool: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		Lua_helper.add_callback(lua, "getShaderBoolArray", function(obj:String, prop:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				FunkinLua.luaTrace("getShaderBoolArray: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return null;
			}
			return shader.getBoolArray(prop);
			#else
			FunkinLua.luaTrace("getShaderBoolArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		Lua_helper.add_callback(lua, "getShaderInt", function(obj:String, prop:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				FunkinLua.luaTrace("getShaderInt: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return null;
			}
			return shader.getInt(prop);
			#else
			FunkinLua.luaTrace("getShaderInt: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		Lua_helper.add_callback(lua, "getShaderIntArray", function(obj:String, prop:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				FunkinLua.luaTrace("getShaderIntArray: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return null;
			}
			return shader.getIntArray(prop);
			#else
			FunkinLua.luaTrace("getShaderIntArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		Lua_helper.add_callback(lua, "getShaderFloat", function(obj:String, prop:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				FunkinLua.luaTrace("getShaderFloat: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return null;
			}
			return shader.getFloat(prop);
			#else
			FunkinLua.luaTrace("getShaderFloat: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		Lua_helper.add_callback(lua, "getShaderFloatArray", function(obj:String, prop:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				FunkinLua.luaTrace("getShaderFloatArray: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return null;
			}
			return shader.getFloatArray(prop);
			#else
			FunkinLua.luaTrace("getShaderFloatArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});


		Lua_helper.add_callback(lua, "setShaderBool", function(obj:String, prop:String, value:Bool) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderBool: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}
			shader.setBool(prop, value);
			return true;
			#else
			FunkinLua.luaTrace("setShaderBool: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "setShaderBoolArray", function(obj:String, prop:String, values:Dynamic) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderBoolArray: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}
			shader.setBoolArray(prop, values);
			return true;
			#else
			FunkinLua.luaTrace("setShaderBoolArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "setShaderInt", function(obj:String, prop:String, value:Int) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderInt: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}
			shader.setInt(prop, value);
			return true;
			#else
			FunkinLua.luaTrace("setShaderInt: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "setShaderIntArray", function(obj:String, prop:String, values:Dynamic) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderIntArray: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}
			shader.setIntArray(prop, values);
			return true;
			#else
			FunkinLua.luaTrace("setShaderIntArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "setShaderFloat", function(obj:String, prop:String, value:Float) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderFloat: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}
			shader.setFloat(prop, value);
			return true;
			#else
			FunkinLua.luaTrace("setShaderFloat: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return false;
			#end
		});
		Lua_helper.add_callback(lua, "setShaderFloatArray", function(obj:String, prop:String, values:Dynamic) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderFloatArray: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}

			// ⚠ Lua table 传进来是 Array<Dynamic>（元素为装箱的 Dynamic），
			// 而 openfl 的 ShaderInput 对 `vec4`/`float[N]` 一律按 Array<Float> 读取并上传；
			// 直接把 Dynamic 数组丢给 setFloatArray，hxcpp 下元素类型不匹配，
			// uniform 上传时会在驱动层原生崩溃（SIGSEGV，try/catch 兜不住）。
			// 必须在引擎侧做一次规整 —— 让引擎兼容模组，而不是要求模组改写法。
			//（2026-10-31 实测：Sonic 模组 space-colony-ark 的 rimColor 即此）
			var arr:Array<Float> = [];
			if (Std.isOfType(values, Array))
			{
				for (v in (cast values : Array<Dynamic>))
				{
					if (v == null) { arr.push(0); continue; }
					if (Std.isOfType(v, Float)) arr.push(cast v);
					else if (Std.isOfType(v, Int)) arr.push(cast v);
					else
					{
						var f:Float = Std.parseFloat(Std.string(v));
						arr.push(Math.isNaN(f) ? 0 : f);
					}
				}
			}
			shader.setFloatArray(prop, arr);
			return true;
			#else
			FunkinLua.luaTrace("setShaderFloatArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return true;
			#end
		});

		Lua_helper.add_callback(lua, "setShaderSampler2D", function(obj:String, prop:String, bitmapdataPath:String) {
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if(shader == null)
			{
				FunkinLua.luaTrace("setShaderSampler2D: Shader is not FlxRuntimeShader!", false, false, FlxColor.RED);
				return false;
			}

			// trace('bitmapdatapath: $bitmapdataPath');
			var value = Paths.image(bitmapdataPath);
			if(value != null && value.bitmap != null)
			{
				// trace('Found bitmapdata. Width: ${value.bitmap.width} Height: ${value.bitmap.height}');
				shader.setSampler2D(prop, value.bitmap);
				return true;
			}
			return false;
			#else
			FunkinLua.luaTrace("setShaderSampler2D: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return false;
			#end
		});
	}
	
	#if (!flash && sys)
	/**
	 * sprite 级 shader 的「影子表」：key = 对象名（'dad' / 'gradient' …）。
	 * 用于「shader 已创建但不参与渲染」的降级模式下，仍让脚本能改 uniform 参数。
	 */
	public static var shadowShaders:Map<String, FlxRuntimeShader> = new Map<String, FlxRuntimeShader>();

	/**
	 * 是否跳过「把 shader 真正挂到 sprite 上」。
	 *
	 * ⚠ 仅 macOS 需要降级：macOS + flixel 6.2 + 当前 openfl 下，sprite 级 shader/filter
	 * 在渲染时会原生 SIGSEGV —— 连 `void main(){ gl_FragColor = vec4(1,0,0,1); }`
	 * 这种极简 shader 都崩（2026-10-31 实测），应用层无法捕获驱动层 abort。
	 *
	 * Windows / Linux 的 `sprite.shader` 路径是正常的（Psych 原版一直这么用），
	 * **必须保持 true 挂载**，否则会让所有模组的角色描边、着色等特效凭空消失。
	 *
	 * macOS 上想验证个别 shader 是否已不受影响，可设 METEORIC_SPRITE_SHADER=1 强制开启。
	 */
	public static var skipSpriteShaderApply:Bool =
		#if mac
		(Sys.getEnv('METEORIC_SPRITE_SHADER') != '1')
		#else
		false
		#end;

	public static function getShader(obj:String):FlxRuntimeShader
	{
		var split:Array<String> = obj.split('.');
		var target:FlxSprite = null;
		if(split.length > 1) target = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1]);
		else target = LuaUtils.getObjectDirectly(split[0]);
		if(target == null)
		{
			FunkinLua.luaTrace('Error on getting shader: Object $obj not found', false, false, FlxColor.RED);
			return null;
		}
		var sh:FlxRuntimeShader = cast (target.shader, FlxRuntimeShader);
		// 若 shader 走的是 filter 后处理路径（见 setSpriteShader 的 macOS 兼容改动），
		// 从 filters 里取回同一个实例，保证 setShaderFloat / setShaderFloatArray 改得到它。
		// 注意：filters 在 FlxSprite 的 Haxe 类型上不可直接访问，走 Dynamic。
		var _t:Dynamic = target;
		var _f:Dynamic = _t.filters;
		if (sh == null && _f != null)
		{
			for (fi in (cast _f : Array<Dynamic>))
			{
				if (Std.isOfType(fi, openfl.filters.ShaderFilter))
				{
					sh = cast ((cast fi : openfl.filters.ShaderFilter).shader, FlxRuntimeShader);
					if (sh != null) break;
				}
			}
		}
		return sh;
	}
	#end
}