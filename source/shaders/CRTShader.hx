package shaders;

import flixel.system.FlxAssets.FlxShader;
import lime.graphics.opengl.GLProgram;

/**
 * 内置全局 CRT 后处理着色器：桶形畸变 + 扫描线 + 暗角 + RGB 分离 + 极淡滚动暗带。
 *
 * 由 shaders.GlobalShaderHandler 挂到游戏根对象（FlxG.game.setFilters），不是精灵级 ——
 * 整个画面合成后过滤一次，HUD / 子状态不会叠层。
 *
 * uniform 由 openfl 宏从下方 GLSL 自动生成同名 ShaderParameter 字段，
 * 脚本侧统一走 GlobalShaderHandler.setFloat / CRTShader.setUniform（显式 switch，不走反射）。
 *
 * GL 编译失败的兜底照 shaders.ErrorHandledShader.hx：编译发生在精灵首次渲染时，
 * 失败会原生崩（SIGSEGV），必须 try/catch 返回 null 走默认渲染管线。
 */
class CRTShader extends FlxShader
{
	@:glFragmentSource('
		#pragma header

		uniform float uCurvature;    // barrel distortion: 0 = off, 0.1 = classic subtle, 1 = extreme
		uniform float uScanStrength; // scanlines: 0..1
		uniform float uVignette;     // vignette: 0..1
		uniform float uRGBSplit;     // horizontal RGB shift (uv units)
		uniform float uTime;         // seconds; drives the faint rolling band only

		vec2 crtCurve(vec2 uv)
		{
			uv = uv * 2.0 - 1.0;
			// openfl_TextureSize should have a value on the filter path, but guard
			// against zero size (avoids aspect = 0 collapsing the whole screen)
			float texH = openfl_TextureSize.y > 0.5 ? openfl_TextureSize.y : 720.0;
			float texW = openfl_TextureSize.x > 0.5 ? openfl_TextureSize.x : texH * 1.7777777;
			float aspect = texW / texH;
			uv.x *= aspect;
			vec2 offset = abs(uv.yx) / vec2(6.0, 4.0);
			uv += uv * offset * offset * uCurvature * 10.0;
			uv.x /= aspect;
			return uv * 0.5 + 0.5;
		}

		void main(void)
		{
			vec2 uv = crtCurve(openfl_TextureCoordv);

			if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
			{
				// outside the curved tube: black border
				gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
				return;
			}

			float r = texture2D(bitmap, uv + vec2(uRGBSplit, 0.0)).r;
			vec4 base = texture2D(bitmap, uv);
			float b = texture2D(bitmap, uv - vec2(uRGBSplit, 0.0)).b;
			vec3 rgb = vec3(r, base.g, b);

			// scanlines follow physical texture rows
			float texH2 = openfl_TextureSize.y > 0.5 ? openfl_TextureSize.y : 720.0;
			float scan = 0.5 + 0.5 * sin(uv.y * texH2 * 3.14159265);
			rgb *= 1.0 - uScanStrength * scan;

			// vignette
			vec2 d = uv - 0.5;
			rgb *= 1.0 - uVignette * dot(d, d) * 1.6;

			// faint rolling band (CRT refresh feel, fixed 4%, not exposed as a param)
			float roll = fract(uv.y - uTime * 0.07);
			float band = smoothstep(0.0, 1.0, 1.0 - abs(roll - 0.5) / 0.15);
			rgb *= 1.0 - 0.04 * band;

			gl_FragColor = vec4(rgb, base.a);
		}')
	public function new()
	{
		super();
		this.uCurvature.value = [0.10];
		this.uScanStrength.value = [0.15];
		this.uVignette.value = [0.30];
		this.uRGBSplit.value = [0.0008];
		this.uTime.value = [0.0];
	}

	override function __createGLProgram(vertexSource:String, fragmentSource:String):GLProgram
	{
		try
		{
			return super.__createGLProgram(vertexSource, fragmentSource);
		}
		catch (error:Dynamic)
		{
			// 编译失败 → 返回 null，openfl 走默认渲染管线，游戏继续（见 ErrorHandledShader 注释）
			trace('[CRTShader] GL 编译失败，走默认渲染管线: $error');
			backend.CrashHandler.logEvent('crt-shader-compile-failed: $error');
			return null;
		}
	}

	/**
	 * 脚本侧 uniform 入口。接受带/不带 u 前缀的名字，返回 false = 未知属性。
	 * 规范名：curvature / scan / vignette / rgbsplit / time。
	 */
	public function setUniform(prop:String, value:Float):Bool
	{
		switch (prop)
		{
			case 'curvature' | 'uCurvature':
				this.uCurvature.value = [value];
			case 'scan' | 'scanStrength' | 'uScanStrength':
				this.uScanStrength.value = [value];
			case 'vignette' | 'uVignette':
				this.uVignette.value = [value];
			case 'rgbsplit' | 'rgbSplit' | 'uRGBSplit':
				this.uRGBSplit.value = [value];
			case 'time' | 'uTime':
				this.uTime.value = [value];
			default:
				return false;
		}
		return true;
	}

	public function getUniform(prop:String):Null<Float>
	{
		switch (prop)
		{
			case 'curvature' | 'uCurvature':
				return this.uCurvature.value[0];
			case 'scan' | 'scanStrength' | 'uScanStrength':
				return this.uScanStrength.value[0];
			case 'vignette' | 'uVignette':
				return this.uVignette.value[0];
			case 'rgbsplit' | 'rgbSplit' | 'uRGBSplit':
				return this.uRGBSplit.value[0];
			case 'time' | 'uTime':
				return this.uTime.value[0];
			default:
				return null;
		}
	}
}
