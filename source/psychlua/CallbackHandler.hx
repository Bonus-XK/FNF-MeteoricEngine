package psychlua;

class CallbackHandler
{
	public static inline function call(l:State, fname:String):Int
	{
		try
		{
			//trace('calling $fname');
			var cbf:Dynamic = Lua_helper.callbacks.get(fname);

			//Local functions have the lowest priority
			//This is to prevent a "for" loop being called in every single operation,
			//so that it only loops on reserved/special functions
			if(cbf == null) 
			{
				// 阶段 C（对齐 Psych 0.7.3）：优先命中"最近一次被调用的脚本"，
				// 避免每次 C 回调都线性扫 luaArray（脚本多时是每帧热点）。
				// 保留 Meteoric 原有的 script.lua == l 身份校验与 null 检查，行为更保守。
				var last:FunkinLua = FunkinLua.lastCalledScript;
				if(last != null && last.lua == l)
					cbf = last.callbacks.get(fname);
				else
				{
					//trace('looping thru scripts');
					for (script in PlayState.instance.luaArray)
						if(script != null && script != last && script.lua == l)
						{
							//trace('found script');
							cbf = script.callbacks.get(fname);
							break;
						}
				}
			}
			
			if(cbf == null) return 0;

			var nparams:Int = Lua.gettop(l);
			var args:Array<Dynamic> = [];

			for (i in 0...nparams) {
				args[i] = Convert.fromLua(l, i + 1);
			}

			var ret:Dynamic = null;
			/* return the number of results */

			ret = Reflect.callMethod(null,cbf,args);

			if(ret != null){
				Convert.toLua(l, ret);
				return 1;
			}
		}
		catch(e:Dynamic)
		{
			if(Lua_helper.sendErrorsToLua) {LuaL.error(l, 'CALLBACK ERROR! ${if(e.message != null) e.message else e}');return 0;}
			trace(e);
			throw(e);
		}
		return 0;
	}
}