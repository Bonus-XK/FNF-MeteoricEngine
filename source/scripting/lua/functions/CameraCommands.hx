package scripting.lua.functions;

import scripting.lua.FunkinLua;

//
// CameraCommands —— 由 FunkinLua.hx 拆分而来（阶段 A：纯搬运，零行为变更）
// 回调注册顺序与拆分前一致；注册名/签名/回调体逐字保留。
//
class CameraCommands
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		Lua_helper.add_callback(lua, "cameraSetTarget", function(target:String) {
			var isDad:Bool = false;
			if(target == 'dad') {
				isDad = true;
				game.moveCamera(isDad);
			}
			else if(target == 'gf') {
				// Camera Freedom Kit：支持跟随 GF（原引擎只认 dad/其余=boyfriend）
				game.moveCameraToGF();
			}
			else {
				game.moveCamera(isDad);
			}
			return isDad;
		});

		Lua_helper.add_callback(lua, "cameraShake", function(camera:String, intensity:Float, duration:Float) {
			LuaUtils.cameraFromString(camera).shake(intensity, duration);
		});

		Lua_helper.add_callback(lua, "cameraFlash", function(camera:String, color:String, duration:Float,forced:Bool) {
			LuaUtils.cameraFromString(camera).flash(CoolUtil.colorFromString(color), duration, null,forced);
		});

		// cameraFade 语义 = Psych 0.6.3 逐字一致（FadeIn 固定 false，第 4 参 force）。
		// ⚠ 不要「修复」成 FadeIn=true：flixel fade(FadeIn=false) 完成后 _fxFadeAlpha 停在 1
		//（draw 只查 >0）→ 渐入黑色并保持，这是 0.6.3 的确定行为，模组按此语义写演出。
		// 实测案例 stupid-griefer：onSongStart cameraFade('game','000000',20,true,true)
		// = 作者故意的「舞台渐黑只留判定线」整活演出，不是引擎 bug（2026-10-31 排查定案）。
		// Psych 1.0 起签名才改为 (tag, camera, fromColor, toColor, duration, force)。
		Lua_helper.add_callback(lua, "cameraFade", function(camera:String, color:String, duration:Float, forced:Bool) {
			LuaUtils.cameraFromString(camera).fade(CoolUtil.colorFromString(color), duration, false, null, forced);
		});

		// ===================== Camera Freedom Kit（镜头自由化） =====================

		// 把跟随点钉在 (x,y)（= 停止小节跟随）；resetCameraFollowPos 恢复。
		// 等价谱面事件 Camera Follow Pos 的脚本直调版。
		Lua_helper.add_callback(lua, "setCameraFollowPos", function(x:Float, y:Float) {
			game.setCameraFollowPos(x, y);
		});

		Lua_helper.add_callback(lua, "resetCameraFollowPos", function() {
			game.resetCameraFollowPos();
		});

		// 镜头位置补间（丝滑移镜）：把镜头移到 (toX,toY)（舞台坐标）。
		// duration 秒；<= 0 = 瞬移；ease 为空 = linear（doTween 同款缓动名）。
		// camGame 的补间完成后跟随会从新落点继续（不回弹）；要永久钉住请再调 setCameraFollowPos。
		Lua_helper.add_callback(lua, "tweenCamera", function(camera:String, toX:Float, toY:Float, duration:Float, ?ease:String) {
			game.tweenCameraScroll(camera, toX, toY, duration, ease);
		});

		// 镜头 zoom 补间：直接设定目标 zoom（区别于 Add Camera Zoom 的累加）。
		// 补间期间引擎对该相机暂停顶拍回落，完成后以新值为基线；duration <= 0 = 瞬时。
		Lua_helper.add_callback(lua, "tweenCameraZoom", function(camera:String, zoom:Float, duration:Float, ?ease:String) {
			game.tweenCameraZoom(camera, zoom, duration, ease);
		});

		// 取消该相机进行中的镜头补间（scroll + zoom）。
		Lua_helper.add_callback(lua, "cancelCameraTween", function(camera:String) {
			game.cancelCameraTweens(camera);
		});

		// 直接设定相机 scroll（补间/跟随之外的一次性挪动）。
		Lua_helper.add_callback(lua, "setCameraScroll", function(camera:String, x:Float, y:Float) {
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			if (cam != null) cam.scroll.set(x, y);
		});

		// 创建脚本自定义相机（重名幂等返回已有实例；保留名 game/hud/other 拒绝，返回 null）。
		// 创建后 setObjectCamera / cameraShake / cameraFlash / tweenCamera 等所有按名解析处均可使用；
		// 相机绘制在最上层（camOther 之上），bgColor 为空 = 全透明，宽高 <= 0 = 全屏。
		// ⚠ 返回值（FlxCamera）过 llua 边界会变 nil —— 成败请用 cameraExists(name) 判断。
		Lua_helper.add_callback(lua, "registerCamera", function(name:String, ?width:Float, ?height:Float, ?bgColor:Dynamic) {
			var lower:String = name == null ? '' : name.toLowerCase().trim();
			if (lower.length == 0) {
				FunkinLua.luaTrace('registerCamera: Camera name is empty', false, false, FlxColor.RED);
				return null;
			}
			switch (lower) {
				case 'game' | 'camgame' | 'hud' | 'camhud' | 'other' | 'camother':
					FunkinLua.luaTrace("registerCamera: '" + name + "' is a reserved built-in camera name", false, false, FlxColor.RED);
					return null;
			}
			var bgColorInt:Null<Int> = null;
			if (bgColor != null) {
				switch (Type.typeof(bgColor)) {
					case Type.ValueType.TInt | Type.ValueType.TFloat: bgColorInt = Std.int(bgColor);
					default: bgColorInt = CoolUtil.colorFromString(Std.string(bgColor));
				}
			}
			return LuaUtils.registerCamera(lower, width == null ? -1 : Std.int(width), height == null ? -1 : Std.int(height), bgColorInt);
		});

		// 查询自定义相机是否已注册。注意：registerCamera 的返回值（FlxCamera 对象）
		// 在 llua 转换层会变成 nil（TClass 实例不压栈，见 source/llua/Convert.hx），
		// 脚本侧请用本函数判断，而不是看 registerCamera 的返回值。
		Lua_helper.add_callback(lua, "cameraExists", function(name:String) {
			return LuaUtils.getCustomCamera(name) != null;
		});

		// 注销并销毁自定义相机（本局结束时引擎也会自动清理）。
		Lua_helper.add_callback(lua, "removeCamera", function(name:String) {
			return LuaUtils.removeCamera(name);
		});
	}
}
