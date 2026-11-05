package shaders;

import flixel.system.FlxAssets.FlxShader;
import lime.graphics.opengl.GLProgram;

/**
 * 内置全局 CRT 后处理着色器 —— 移植自 Timothy Lottes 的 public domain CRT shader。
 *
 * 来源：libretro/glsl-shaders `crt/shaders/crt-lottes.glsl`
 * https://github.com/libretro/glsl-shaders/blob/master/crt/shaders/crt-lottes.glsl
 * 许可：public domain（原文件头 "Please take and use, change, or whatever."）。
 * 本文件只做 OpenFL/FlxShader 接口适配与脚本参数桥接，CRT 算法（Gaussian 滤波、
 * 扫描线、shadow mask、桶形畸变、bloom、gamma）保持原实现，见 GLSL 内注释。
 *
 * 由 shaders.GlobalShaderHandler 挂到游戏根对象（FlxG.game.setFilters），不是精灵级 ——
 * 整个画面合成后过滤一次，HUD / 子状态不会叠层。
 *
 * uniform 由 openfl 宏从下方 GLSL 自动生成同名 ShaderParameter 字段，
 * 脚本侧统一走 GlobalShaderHandler.setFloat / CRTShader.setUniform（显式 switch，不走反射）。
 * 旧参数名 curvature / scan / vignette / rgbsplit / time 全部保留，语义在 GLSL 里映射到 Lottes 参数。
 *
 * GL 编译失败的兜底照 shaders.ErrorHandledShader.hx：编译发生在精灵首次渲染时，
 * 失败会原生崩（SIGSEGV），必须 try/catch 返回 null 走默认渲染管线。
 */
class CRTShader extends FlxShader
{
	@:glFragmentSource('
		#pragma header

		// ===========================================================================
		// PUBLIC DOMAIN CRT STYLED SCAN-LINE SHADER by Timothy Lottes
		// Upstream: libretro/glsl-shaders crt/shaders/crt-lottes.glsl
		// https://github.com/libretro/glsl-shaders/blob/master/crt/shaders/crt-lottes.glsl
		// License: public domain ("Please take and use, change, or whatever.")
		//
		// Adaptation to OpenFL FlxShader (algorithm unchanged):
		//  - Source/Texture -> bitmap, TEX0.xy -> openfl_TextureCoordv,
		//    gl_FragCoord -> openfl_TextureCoordv * openfl_TextureSize
		//  - SourceSize is a fixed simulated height (SOURCE_HEIGHT rows) so the
		//    scanline pitch stays identical on 720p / 1440p / Retina
		//  - original #pragma parameter constants are driven by the 5 engine
		//    uniforms below, so the Lua/HScript API keeps working
		// ===========================================================================

		uniform float uCurvature;    // -> warpX / warpY scale (0.10 = Lottes default)
		uniform float uScanStrength; // -> hardScan scale      (0.15 = Lottes default)
		uniform float uVignette;     // -> soft edge falloff   (0.30 = subtle)
		uniform float uRGBSplit;     // -> shadow mask R/B phase (uv units)
		uniform float uTime;         // -> static shader API placeholder

		#define SOURCE_HEIGHT 360.0
		#define HARD_PIX -3.0
		#define HARD_BLOOM_PIX -1.5
		#define HARD_BLOOM_SCAN -2.0
		#define SHAPE 2.0
		#define MASK_LIGHT 1.5
		#define BRIGHT_BOOST 1.0
		#define BLOOM_AMOUNT 0.15

		// Lottes parameters derived from uniforms at the top of main()
		float gHardScan;
		float gWarpX;
		float gWarpY;
		float gRGBShift;
		vec4 SourceSize;

		// sRGB <-> linear (Lottes scaleInLinearGamma = 1.0)
		float ToLinear1(float c)
		{
			return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
		}

		vec3 ToLinear(vec3 c)
		{
			return vec3(ToLinear1(c.r), ToLinear1(c.g), ToLinear1(c.b));
		}

		float ToSrgb1(float c)
		{
			return (c < 0.0031308) ? c * 12.92 : 1.055 * pow(c, 0.41666) - 0.055;
		}

		vec3 ToSrgb(vec3 c)
		{
			return vec3(ToSrgb1(c.r), ToSrgb1(c.g), ToSrgb1(c.b));
		}

		// Nearest emulated sample given floating point position and texel offset.
		vec3 Fetch(vec2 pos, vec2 off)
		{
			pos = (floor(pos * SourceSize.xy + off) + vec2(0.5, 0.5)) / SourceSize.xy;
			return ToLinear(BRIGHT_BOOST * texture2D(bitmap, pos.xy).rgb);
		}

		// Distance in emulated pixels to the nearest texel.
		vec2 Dist(vec2 pos)
		{
			pos = pos * SourceSize.xy;
			return -((pos - floor(pos)) - vec2(0.5));
		}

		// 1D Gaussian.
		float Gaus(float pos, float scale)
		{
			return exp2(scale * pow(abs(pos), SHAPE));
		}

		// 3-tap Gaussian filter along horz line.
		vec3 Horz3(vec2 pos, float off)
		{
			vec3 b = Fetch(pos, vec2(-1.0, off));
			vec3 c = Fetch(pos, vec2( 0.0, off));
			vec3 d = Fetch(pos, vec2( 1.0, off));
			float dst = Dist(pos).x;
			float scale = HARD_PIX;
			float wb = Gaus(dst - 1.0, scale);
			float wc = Gaus(dst + 0.0, scale);
			float wd = Gaus(dst + 1.0, scale);
			return (b * wb + c * wc + d * wd) / (wb + wc + wd);
		}

		// 5-tap Gaussian filter along horz line.
		vec3 Horz5(vec2 pos, float off)
		{
			vec3 a = Fetch(pos, vec2(-2.0, off));
			vec3 b = Fetch(pos, vec2(-1.0, off));
			vec3 c = Fetch(pos, vec2( 0.0, off));
			vec3 d = Fetch(pos, vec2( 1.0, off));
			vec3 e = Fetch(pos, vec2( 2.0, off));
			float dst = Dist(pos).x;
			float scale = HARD_PIX;
			float wa = Gaus(dst - 2.0, scale);
			float wb = Gaus(dst - 1.0, scale);
			float wc = Gaus(dst + 0.0, scale);
			float wd = Gaus(dst + 1.0, scale);
			float we = Gaus(dst + 2.0, scale);
			return (a * wa + b * wb + c * wc + d * wd + e * we) / (wa + wb + wc + wd + we);
		}

		// 7-tap Gaussian filter along horz line.
		vec3 Horz7(vec2 pos, float off)
		{
			vec3 a = Fetch(pos, vec2(-3.0, off));
			vec3 b = Fetch(pos, vec2(-2.0, off));
			vec3 c = Fetch(pos, vec2(-1.0, off));
			vec3 d = Fetch(pos, vec2( 0.0, off));
			vec3 e = Fetch(pos, vec2( 1.0, off));
			vec3 f = Fetch(pos, vec2( 2.0, off));
			vec3 g = Fetch(pos, vec2( 3.0, off));
			float dst = Dist(pos).x;
			float scale = HARD_BLOOM_PIX;
			float wa = Gaus(dst - 3.0, scale);
			float wb = Gaus(dst - 2.0, scale);
			float wc = Gaus(dst - 1.0, scale);
			float wd = Gaus(dst + 0.0, scale);
			float we = Gaus(dst + 1.0, scale);
			float wf = Gaus(dst + 2.0, scale);
			float wg = Gaus(dst + 3.0, scale);
			return (a * wa + b * wb + c * wc + d * wd + e * we + f * wf + g * wg)
				/ (wa + wb + wc + wd + we + wf + wg);
		}

		// Return scanline weight.
		float Scan(vec2 pos, float off)
		{
			float dst = Dist(pos).y;
			return Gaus(dst + off, gHardScan);
		}

		// Return scanline weight for bloom.
		float BloomScan(vec2 pos, float off)
		{
			float dst = Dist(pos).y;
			return Gaus(dst + off, HARD_BLOOM_SCAN);
		}

		// Allow nearest three lines to effect pixel.
		vec3 Tri(vec2 pos)
		{
			vec3 a = Horz3(pos, -1.0);
			vec3 b = Horz5(pos,  0.0);
			vec3 c = Horz3(pos,  1.0);
			float wa = Scan(pos, -1.0);
			float wb = Scan(pos,  0.0);
			float wc = Scan(pos,  1.0);
			return a * wa + b * wb + c * wc;
		}

		// Small bloom.
		vec3 Bloom(vec2 pos)
		{
			vec3 a = Horz5(pos, -2.0);
			vec3 b = Horz7(pos, -1.0);
			vec3 c = Horz7(pos,  0.0);
			vec3 d = Horz7(pos,  1.0);
			vec3 e = Horz5(pos,  2.0);
			float wa = BloomScan(pos, -2.0);
			float wb = BloomScan(pos, -1.0);
			float wc = BloomScan(pos,  0.0);
			float wd = BloomScan(pos,  1.0);
			float we = BloomScan(pos,  2.0);
			return a * wa + b * wb + c * wc + d * wd + e * we;
		}

		// Distortion of scanlines, and end of screen alpha.
		vec2 Warp(vec2 pos)
		{
			pos = pos * 2.0 - 1.0;
			pos *= vec2(1.0 + (pos.y * pos.y) * gWarpX, 1.0 + (pos.x * pos.x) * gWarpY);
			return pos * 0.5 + 0.5;
		}

		// Shadow mask: Lottes shadowMask = 3.0 (stretched VGA style).
		vec3 Mask(vec2 pos)
		{
			vec3 mask = vec3(0.5, 0.5, 0.5);
			pos.x += pos.y * 3.0;
			pos.x = fract(pos.x * 0.166666666);
			if      (pos.x < 0.333) mask.r = MASK_LIGHT;
			else if (pos.x < 0.666) mask.g = MASK_LIGHT;
			else                    mask.b = MASK_LIGHT;
			return mask;
		}

		void main(void)
		{
			// Simulated source resolution: fixed 360 rows, aspect from the real texture.
			float texH = openfl_TextureSize.y > 1.0 ? openfl_TextureSize.y : 720.0;
			vec2 sim = openfl_TextureSize * (SOURCE_HEIGHT / texH);
			SourceSize = vec4(sim, 1.0 / sim);

			// Bridge the legacy engine uniforms onto Lottes parameters.
			gHardScan = -8.0 * clamp(uScanStrength / 0.15, 0.0, 2.0);
			gWarpX = 0.031 * clamp(uCurvature / 0.10, 0.0, 4.0);
			gWarpY = 0.041 * clamp(uCurvature / 0.10, 0.0, 4.0);
			gRGBShift = uRGBSplit * 1000.0;

			vec2 pos = Warp(openfl_TextureCoordv);
			vec3 outColor = Tri(pos);
			outColor.rgb += Bloom(pos) * BLOOM_AMOUNT;

			// Shadow mask with per-channel phase offset (legacy rgbsplit param).
			vec2 fragPos = openfl_TextureCoordv * openfl_TextureSize * 1.000001;
			vec3 mr = Mask(fragPos + vec2(gRGBShift, 0.0));
			vec3 mg = Mask(fragPos);
			vec3 mb = Mask(fragPos - vec2(gRGBShift, 0.0));
			outColor.rgb *= vec3(mr.r, mg.g, mb.b);

			// Legacy vignette param: soft edge falloff (Lottes has only a hard border).
			vec2 d = abs(openfl_TextureCoordv - 0.5) * 2.0;
			outColor.rgb *= 1.0 - uVignette * dot(d, d) * 0.35;

			// Lottes GL_ES border test: black outside the warped tube.
			if (!(pos.x > 0.0001 && pos.x < 0.9999 && pos.y > 0.0001 && pos.y < 0.9999))
				outColor.rgb = vec3(0.0);

			// Lottes is a static shader; uTime is referenced only to keep the
			// legacy uniform/API alive. No animation is applied.
			outColor.rgb += uTime * 0.0;

			gl_FragColor = vec4(clamp(ToSrgb(outColor.rgb), 0.0, 1.0),
				texture2D(bitmap, openfl_TextureCoordv).a);
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
