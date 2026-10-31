package shaders;

import flixel.addons.display.FlxRuntimeShader;
import lime.graphics.opengl.GLProgram;

/**
 * Psych 1.0.4 兼容：带错误处理的运行时 shader（移植自 Psych 的 shaders/ErrorHandledShader.hx）。
 *
 * 为什么必须有：`__createGLProgram` 是 openfl 编译 GLSL 的入口，发生在**精灵第一次被渲染**时；
 * 模组 shader 一旦编译失败（语法错误 / 不支持的 uniform / 驱动差异），openfl 会直接原生崩
 *（SIGSEGV，2026-10-31 实测：Sonic 模组 Ultimatum 的 rimlight shader 挂到角色上后崩在 noteSpawn 后，
 *  栈里没有 lua_pcall —— 因为崩的是渲染管线而不是脚本）。
 * Psych 官方对此的解法就是 try + 返回 null：shader 编译失败 → 该精灵走默认渲染管线，游戏继续。
 */
class ErrorHandledRuntimeShader extends FlxRuntimeShader
{
	public var shaderName:String = '';

	public function new(?shaderName:String, ?fragmentSource:String, ?vertexSource:String)
	{
		this.shaderName = shaderName;
		super(fragmentSource, vertexSource);
	}

	override function __createGLProgram(vertexSource:String, fragmentSource:String):GLProgram
	{
		try
		{
			final res = super.__createGLProgram(vertexSource, fragmentSource);
			return res;
		}
		catch (error:Dynamic)
		{
			crashSave(this.shaderName, error);
			return null;
		}
	}

	static function crashSave(shaderName:String, error:Dynamic):Void
	{
		var name:String = shaderName == null ? 'unnamed' : shaderName;
		trace('[ErrorHandledShader] GL 编译失败，改用默认渲染管线: $name\n$error');
		backend.CrashHandler.logEvent('shader-compile-failed: $name');
	}
}
