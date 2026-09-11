package backend;

/**
 * 容器清单解析（`container.json`）。
 *
 * 设计原则：
 *  - 引擎对目标引擎**零改写**：清单只描述“怎么启动、资源放哪、怎么退出”，
 *    绝不写入目标引擎的目录（不生成 config.json、不改主程序）。
 *  - 解析永不抛异常：任何字段缺失/类型错误都回落到安全默认值，并把问题写进
 *    `problem` 字段供界面显示。容器装错时是“界面上一行红字”，不是崩溃。
 *
 * 命名说明：类名带 Parser 后缀是为了不与 `backend.ContainerManifest`（清单结果 typedef，
 * 必须是同文件同名类型）撞名。
 */
class ContainerManifestParser
{
	public static inline var FILE_NAME:String = 'container.json';

	/**
	 * 解析清单。`containerDir` 为容器根目录（绝对路径）。
	 * 不抛异常：文件缺失 / JSON 损坏 / 类型错误一律折成 problem 文案。
	 */
	public static function load(containerDir:String):ContainerManifest
	{
		var out:ContainerManifest = {exists: false, raw: null, problem: null};
		if (containerDir == null || containerDir.length < 1)
		{
			out.problem = '容器目录为空';
			return out;
		}

		var path:String = containerDir;
		if (!StringTools.endsWith(path, '/')) path += '/';
		path += FILE_NAME;

		if (!ContainerStore.fileExists(path))
		{
			out.problem = '缺少清单文件 ' + FILE_NAME + '（容器未完成配置）';
			return out;
		}
		out.exists = true;

		var text:String = null;
		try
			text = sys.io.File.getContent(path)
		catch (e:Dynamic)
		{
			out.problem = '清单读取失败：' + Std.string(e);
			return out;
		}

		var parsed:Dynamic = null;
		try
			parsed = haxe.Json.parse(text)
		catch (e:Dynamic)
		{
			out.problem = '清单 JSON 解析失败：' + Std.string(e);
			return out;
		}

		if (parsed == null || Reflect.fields(parsed).length < 1)
		{
			out.problem = '清单内容为空';
			return out;
		}

		out.raw = cast parsed;
		return out;
	}

	/** 取字符串字段（安全，类型不符/缺失时返回 def）。 */
	public static function str(data:ContainerManifestData, field:String, ?def:String = null):String
	{
		if (data == null) return def;
		var v:Dynamic = null;
		try
			v = Reflect.field(data, field)
		catch (e:Dynamic)
			return def;
		if (v == null) return def;
		var s:String = Std.string(v);
		if (s == null || s.length < 1 || s == 'null') return def;
		return s;
	}

	/** 取布尔字段（安全）。 */
	public static function bool(data:ContainerManifestData, field:String, def:Bool):Bool
	{
		if (data == null) return def;
		var v:Dynamic = null;
		try
			v = Reflect.field(data, field)
		catch (e:Dynamic)
			return def;
		if (v == null) return def;
		var s:String = Std.string(v).toLowerCase();
		if (s == 'true' || s == '1' || s == 'yes') return true;
		if (s == 'false' || s == '0' || s == 'no') return false;
		return def;
	}

	/** 取浮点字段（安全；非正数视为缺失）。 */
	public static function num(data:ContainerManifestData, field:String, def:Float):Float
	{
		if (data == null) return def;
		var v:Dynamic = null;
		try
			v = Reflect.field(data, field)
		catch (e:Dynamic)
			return def;
		if (v == null) return def;
		var f:Float = Std.parseFloat(Std.string(v));
		if (Math.isNaN(f) || f <= 0) return def;
		return f;
	}
}
