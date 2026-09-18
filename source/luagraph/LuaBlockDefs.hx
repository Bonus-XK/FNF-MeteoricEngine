package luagraph;

import flixel.util.FlxColor;
import backend.DesignTokens;

/** 积木目录：10 个分类 + 约 80 块，覆盖事件/流程/变量/精灵/补间/相机/音频/文本/杂项/兜底。 */
class LuaBlockDefs
{
	public static inline var CAT_EVENT:String = 'event';
	public static inline var CAT_FLOW:String = 'flow';
	public static inline var CAT_VAR:String = 'var';
	public static inline var CAT_SPRITE:String = 'sprite';
	public static inline var CAT_TWEEN:String = 'tween';
	public static inline var CAT_CAM:String = 'cam';
	public static inline var CAT_SOUND:String = 'sound';
	public static inline var CAT_TEXT:String = 'text';
	public static inline var CAT_MISC:String = 'misc';
	public static inline var CAT_ADV:String = 'adv';

	/** 分类显示顺序与中文名。 */
	public static var CATEGORIES:Array<Array<String>> = [
		[CAT_EVENT, '事件'],
		[CAT_FLOW, '流程'],
		[CAT_VAR, '变量'],
		[CAT_SPRITE, '精灵'],
		[CAT_TWEEN, '补间'],
		[CAT_CAM, '相机'],
		[CAT_SOUND, '音频'],
		[CAT_TEXT, '文本'],
		[CAT_MISC, '杂项'],
		[CAT_ADV, '兜底']
	];

	/** 缓动下拉：全部取自 LuaUtils.getTweenEaseByString 的接受值（其余会静默回落 linear）。 */
	public static var EASES:Array<String> = [
		'linear', 'sineIn', 'sineOut', 'sineInOut',
		'quadIn', 'quadOut', 'quadInOut',
		'cubeOut', 'quartOut', 'quintOut',
		'expoOut', 'circOut', 'backOut', 'bounceOut', 'elasticOut'
	];

	/** 混合模式下拉：取自 LuaUtils.blendModeFromString。 */
	public static var BLENDS:Array<String> = [
		'normal', 'add', 'multiply', 'screen', 'subtract', 'overlay', 'hardlight', 'invert', 'darken', 'lighten', 'difference'
	];

	/** 相机下拉：取自 LuaUtils.cameraFromString。 */
	public static var CAMERAS:Array<String> = ['camGame', 'camHUD', 'camOther'];

	public static var DEFS:Array<BlockDef> = build();
	static var BY_ID:Map<String, BlockDef> = null;

	public static function get(id:String):BlockDef
	{
		if (BY_ID == null)
		{
			BY_ID = new Map();
			for (d in DEFS) BY_ID.set(d.id, d);
		}
		return BY_ID.get(id);
	}

	/** 事件帽块 → 真实回调函数名（onCreate / onCreatePost / onBeatHit …）。 */
	public static function eventName(def:BlockDef):String
	{
		if (def == null) return '';
		if (def.cat == CAT_EVENT && StringTools.startsWith(def.id, 'ev_')) return def.id.substr(3);
		return def.id;
	}

	/** 用回调名查帽块定义（图里的 stack.event 存的就是回调名，与生成的 Lua 函数名一致）。 */
	public static function byEvent(name:String):BlockDef
	{
		if (name == null) return null;
		for (d in DEFS)
			if (d.cat == CAT_EVENT && eventName(d) == name) return d;
		return get(name);
	}

	public static function ofCat(cat:String):Array<BlockDef>
	{
		var out:Array<BlockDef> = [];
		for (d in DEFS)
			if (d.cat == cat) out.push(d);
		return out;
	}

	public static function catLabel(cat:String):String
	{
		for (c in CATEGORIES)
			if (c[0] == cat) return c[1];
		return cat;
	}

	/** 依据主题令牌派生积木配色（不写死十六进制，主题切换时随动）。 */
	public static function catAccent(cat:String):FlxColor
	{
		return switch (cat)
		{
			case CAT_EVENT: DesignTokens.primary;
			case CAT_FLOW: DesignTokens.secondary;
			case CAT_VAR: DesignTokens.tertiary;
			case CAT_SPRITE: mix(DesignTokens.primary, DesignTokens.tertiary, 0.45);
			case CAT_TWEEN: mix(DesignTokens.secondary, DesignTokens.tertiary, 0.45);
			case CAT_CAM: mix(DesignTokens.primary, DesignTokens.secondary, 0.45);
			case CAT_SOUND: mix(DesignTokens.tertiary, DesignTokens.secondary, 0.7);
			case CAT_TEXT: mix(DesignTokens.primary, FlxColor.WHITE, 0.35);
			case CAT_MISC: mix(DesignTokens.secondary, FlxColor.WHITE, 0.3);
			default: mix(DesignTokens.primary, DesignTokens.secondary, 0.5);
		};
	}

	/** 积木填充色：偏暗以保证白字可读，同时带主题色倾向。 */
	public static function catFill(cat:String):FlxColor
	{
		return mix(0xFF1B1B26, catAccent(cat), 0.34);
	}

	public static function catBorder(cat:String):FlxColor
	{
		return mix(catAccent(cat), 0xFFFFFFFF, 0.2);
	}

	static function mix(a:FlxColor, b:FlxColor, t:Float):FlxColor
	{
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		var r:Int = Std.int(a.red * (1 - t) + b.red * t);
		var g:Int = Std.int(a.green * (1 - t) + b.green * t);
		var bl:Int = Std.int(a.blue * (1 - t) + b.blue * t);
		return FlxColor.fromRGB(r, g, bl);
	}

	// ==================================================================
	//  积木目录（模板中的函数名/参数序 = psychlua 注册原文）
	// ==================================================================
	static function build():Array<BlockDef>
	{
		var d:Array<BlockDef> = [];

		// ---------------- 事件帽块（9）----------------
		d.push(new BlockDef('ev_onCreate', CAT_EVENT, '当脚本创建时', 'function onCreate()\n$$BODY$$\nend', [], true, true, false, '对应 Lua 回调 onCreate()，脚本加载时执行一次。'));
		d.push(new BlockDef('ev_onCreatePost', CAT_EVENT, '当脚本创建完成后', 'function onCreatePost()\n$$BODY$$\nend', [], true, true, false, '对应 onCreatePost()，此时舞台对象已就绪。'));
		d.push(new BlockDef('ev_onUpdatePost', CAT_EVENT, '当每帧结束时', 'function onUpdatePost(elapsed)\n$$BODY$$\nend', [], true, true, false, '每帧执行（elapsed = 本帧秒数）；放置高频逻辑请自行控制开销。'));
		d.push(new BlockDef('ev_onBeatHit', CAT_EVENT, '当每拍时', 'function onBeatHit()\n$$BODY$$\nend', [], true, true, false, '对应 onBeatHit()，按当前 BPM 触发。'));
		d.push(new BlockDef('ev_onStepHit', CAT_EVENT, '当每步时', 'function onStepHit()\n$$BODY$$\nend', [], true, true, false, '对应 onStepHit()，每拍 4 步。'));
		d.push(new BlockDef('ev_onKeyPress', CAT_EVENT, '当按键时', 'function onKeyPress(key)\n$$BODY$$\nend', [], true, true, false, '参数 key 是被按下的按键名（如 space、left）。'));
		d.push(new BlockDef('ev_goodNoteHit', CAT_EVENT, '当命中音符时', 'function goodNoteHit(id, noteData, noteType, isSustain)\n$$BODY$$\nend', [], true, true,
			false, '参数：音符下标、轨道(0-3)、音符类型、是否长按尾。'));
		d.push(new BlockDef('ev_onSongStart', CAT_EVENT, '当歌曲开始时', 'function onSongStart()\n$$BODY$$\nend', [], true, true, false, '歌曲正式开始（倒计时结束后）触发一次。'));
		d.push(new BlockDef('ev_onDestroy', CAT_EVENT, '当脚本销毁时', 'function onDestroy()\n$$BODY$$\nend', [], true, true, false, '退出歌曲/销毁脚本时执行，适合清理计时器与补间。'));

		// ---------------- 流程（6）----------------
		d.push(new BlockDef('flow_if', CAT_FLOW, '如果 … 那么', 'if {p:cond} then\n$$BODY$$\nend', [
			new PDef('cond', '条件', KExpr, 'true', 'Lua 表达式，如 keyJustPressed(\'space\') 或 getProperty(\'boyfriend.x\') > 500')
		], false, true, false, '条件为真时执行内部积木。'));
		d.push(new BlockDef('flow_ifElse', CAT_FLOW, '如果 … 那么 / 否则', 'if {p:cond} then\n$$BODY$$\nelse\n$$ELSE$$\nend', [
			new PDef('cond', '条件', KExpr, 'true', '同上；内部与"否则"分支各有一块放置区')
		], false, true, true, '双分支条件。'));
		d.push(new BlockDef('flow_repeat', CAT_FLOW, '重复 N 次', 'for _i = 1, {p:times} do\n$$BODY$$\nend', [
			new PDef('times', '次数', KNum, '4', '整数；生成 for _i = 1, N 循环')
		], false, true, false, '重复执行内部积木 N 次。'));
		d.push(new BlockDef('flow_while', CAT_FLOW, '当 … 时重复', 'while {p:cond} do\n$$BODY$$\nend', [
			new PDef('cond', '条件', KExpr, 'true', '循环条件；注意务必让条件最终为假，否则会卡住游戏')
		], false, true, false, '条件为真时循环执行。'));
		d.push(new BlockDef('flow_wait', CAT_FLOW, '等待 N 秒后继续', '', [
			new PDef('tag', '计时器标签', KText, 'myWait', '唯一标签；同一脚本内不要重复'),
			new PDef('secs', '秒数', KNum, '1', '等待时长（秒）')
		], false, false, false, '用 runTimer + 续接函数实现真正的"等待后继续"，不会卡住主线程。'));
		d.push(new BlockDef('flow_stop', CAT_FLOW, '停止本栈', 'return', [], false, false, false, '结束当前回调（或等待后的续接段），后面的积木不再执行。'));

		// ---------------- 变量（5）----------------
		d.push(new BlockDef('var_assign', CAT_VAR, '把变量设为', '{p:name} = {p:value}', [
			new PDef('name', '变量', KVar, 'myVar', '变量需先在左侧"＋ 新建变量"里声明'),
			new PDef('value', '值', KExpr, '0', 'Lua 表达式或字面量')
		], false, false, false, '赋值给脚本级变量。'));
		d.push(new BlockDef('var_add', CAT_VAR, '把变量增加', '{p:name} = {p:name} + ({p:delta})', [
			new PDef('name', '变量', KVar, 'myVar', ''),
			new PDef('delta', '增量', KNum, '1', '可为负数')
		], false, false, false, '自增/自减。'));
		d.push(new BlockDef('var_setRandom', CAT_VAR, '把变量设为随机整数', '{p:name} = getRandomInt({p:min}, {p:max})', [
			new PDef('name', '变量', KVar, 'myVar', ''),
			new PDef('min', '最小', KNum, '1', ''),
			new PDef('max', '最大', KNum, '10', '')
		], false, false, false, '对应引擎的 getRandomInt。'));
		d.push(new BlockDef('var_setSongPos', CAT_VAR, '把变量设为歌曲位置', '{p:name} = getSongPosition()', [
			new PDef('name', '变量', KVar, 'myVar', '')
		], false, false, false, 'currentSongPos，单位毫秒。'));
		d.push(new BlockDef('var_setGlobal', CAT_VAR, '设置跨脚本全局变量', 'setVar(\'{p:name}\', {p:value})', [
			new PDef('name', '全局名', KText, 'flag', '其它脚本可用 getVar 读取'),
			new PDef('value', '值', KExpr, '1', '')
		], false, false, false, '对应 setVar（跨脚本共享）。'));

		// ---------------- 精灵（17）----------------
		d.push(new BlockDef('spr_make', CAT_SPRITE, '创建精灵', 'makeLuaSprite(\'{p:tag}\', \'{p:image}\', {p:x}, {p:y})', [
			new PDef('tag', '标签', KTag, 'mySprite', '后续积木用它引用该精灵'),
			new PDef('image', '图片', KText, 'menuBG', 'images/ 下的图片名（不含扩展名）'),
			new PDef('x', 'X', KNum, '0', ''),
			new PDef('y', 'Y', KNum, '0', '')
		], false, false, false, 'makeLuaSprite(tag, image, x, y)。'));
		d.push(new BlockDef('spr_makeAnim', CAT_SPRITE, '创建动画精灵', 'makeAnimatedLuaSprite(\'{p:tag}\', \'{p:image}\', {p:x}, {p:y})', [
			new PDef('tag', '标签', KTag, 'mySprite', ''),
			new PDef('image', '图集', KText, 'menuBG', 'sparrow 图集名'),
			new PDef('x', 'X', KNum, '0', ''),
			new PDef('y', 'Y', KNum, '0', '')
		], false, false, false, 'makeAnimatedLuaSprite(tag, image, x, y)。'));
		d.push(new BlockDef('spr_makeFlxAnimate', CAT_SPRITE, '创建 FlxAnimate 精灵', 'makeFlxAnimateSprite(\'{p:tag}\', {p:x}, {p:y}, \'{p:folder}\')', [
			new PDef('tag', '标签', KTag, 'myAnimate', ''),
			new PDef('x', 'X', KNum, '0', ''),
			new PDef('y', 'Y', KNum, '0', ''),
			new PDef('folder', '图集目录', KText, 'characters/BOYFRIEND', '需含 Animation.json / spritemap')
		], false, false, false, 'FlxAnimate 角色/图集精灵。'));
		d.push(new BlockDef('spr_makeGraphic', CAT_SPRITE, '创建纯色色块精灵', 'makeLuaSprite(\'{p:tag}\', nil, {p:x}, {p:y})\nmakeGraphic(\'{p:tag}\', {p:w}, {p:h}, \'{p:color}\')', [
			new PDef('tag', '标签', KTag, 'myBox', ''),
			new PDef('x', 'X', KNum, '0', ''),
			new PDef('y', 'Y', KNum, '0', ''),
			new PDef('w', '宽', KNum, '256', ''),
			new PDef('h', '高', KNum, '256', ''),
			new PDef('color', '颜色', KText, 'FFFFFF', '十六进制，可带透明度')
		], false, false, false, '无需图片即可生成色块（两行代码）。'));
		d.push(new BlockDef('spr_addAnim', CAT_SPRITE, '添加动画', 'addAnimationByPrefix(\'{p:tag}\', \'{p:name}\', \'{p:prefix}\', {p:fps}, {p:loop})', [
			new PDef('tag', '标签', KTag, 'mySprite', ''),
			new PDef('name', '动画名', KText, 'idle', '后续播放动画用这个名'),
			new PDef('prefix', '帧前缀', KText, 'idle', '图集内帧名前缀'),
			new PDef('fps', '帧率', KNum, '24', ''),
			new PDef('loop', '循环', KEnum(['true', 'false']), 'true', '')
		], false, false, false, 'addAnimationByPrefix。'));
		d.push(new BlockDef('spr_playAnim', CAT_SPRITE, '播放动画', 'playAnim(\'{p:tag}\', \'{p:name}\', {p:forced})', [
			new PDef('tag', '标签', KTag, 'mySprite', ''),
			new PDef('name', '动画名', KText, 'idle', ''),
			new PDef('forced', '强制重播', KEnum(['false', 'true']), 'false', '')
		], false, false, false, 'playAnim。'));
		d.push(new BlockDef('spr_add', CAT_SPRITE, '把精灵加进舞台', 'addLuaSprite(\'{p:tag}\', {p:front})', [
			new PDef('tag', '标签', KTag, 'mySprite', ''),
			new PDef('front', '置于前景', KEnum(['false', 'true']), 'false', '')
		], false, false, false, 'addLuaSprite(tag, front)。'));
		d.push(new BlockDef('spr_remove', CAT_SPRITE, '移除精灵', 'removeLuaSprite(\'{p:tag}\', {p:destroy})', [
			new PDef('tag', '标签', KTag, 'mySprite', ''),
			new PDef('destroy', '同时销毁', KEnum(['true', 'false']), 'true', '')
		], false, false, false, 'removeLuaSprite。'));
		d.push(new BlockDef('spr_setProp', CAT_SPRITE, '设置对象属性', 'setProperty(\'{p:tag}.{p:prop}\', {p:value})', [
			new PDef('tag', '对象', KText, 'mySprite', '可写 boyfriend / dad / camGame 等'),
			new PDef('prop', '属性', KText, 'x', '如 x / y / angle / alpha / scale.x'),
			new PDef('value', '值', KExpr, '0', '')
		], false, false, false, 'setProperty（最通用的对象改动入口）。'));
		d.push(new BlockDef('spr_setCamera', CAT_SPRITE, '把对象放到相机', 'setObjectCamera(\'{p:tag}\', \'{p:cam}\')', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('cam', '相机', KEnum(CAMERAS), 'camGame', '')
		], false, false, false, 'setObjectCamera。'));
		d.push(new BlockDef('spr_scroll', CAT_SPRITE, '设置滚动系数', 'setScrollFactor(\'{p:tag}\', {p:sx}, {p:sy})', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('sx', '横向', KNum, '1', ''),
			new PDef('sy', '纵向', KNum, '1', '')
		], false, false, false, 'setScrollFactor（0 = 不随镜头滚动）。'));
		d.push(new BlockDef('spr_scale', CAT_SPRITE, '缩放对象（倍数）', 'scaleObject(\'{p:tag}\', {p:sx}, {p:sy}, true)', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('sx', '横向倍数', KNum, '1', ''),
			new PDef('sy', '纵向倍数', KNum, '1', '')
		], false, false, false, 'scaleObject（会同步更新命中框）。'));
		d.push(new BlockDef('spr_graphicSize', CAT_SPRITE, '设置宽高（像素）', 'setGraphicSize(\'{p:tag}\', {p:w}, {p:h})', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('w', '宽', KNum, '256', ''),
			new PDef('h', '高', KNum, '256', '')
		], false, false, false, 'setGraphicSize。'));
		d.push(new BlockDef('spr_screenCenter', CAT_SPRITE, '屏幕居中', 'screenCenter(\'{p:tag}\', \'{p:pos}\')', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('pos', '方向', KEnum(['xy', 'x', 'y']), 'xy', '')
		], false, false, false, 'screenCenter。'));
		d.push(new BlockDef('spr_blend', CAT_SPRITE, '设置混合模式', 'setBlendMode(\'{p:tag}\', \'{p:blend}\')', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('blend', '模式', KEnum(BLENDS), 'add', '')
		], false, false, false, 'setBlendMode。'));
		d.push(new BlockDef('spr_order', CAT_SPRITE, '设置图层顺序', 'setObjectOrder(\'{p:tag}\', {p:pos})', [
			new PDef('tag', '对象', KText, 'mySprite', ''),
			new PDef('pos', '位置', KNum, '0', '数值越大越靠前')
		], false, false, false, 'setObjectOrder。'));

		// ---------------- 补间（7）----------------
		d.push(tweenDef('tw_x', '补间 X 坐标', 'doTweenX', 'x 坐标'));
		d.push(tweenDef('tw_y', '补间 Y 坐标', 'doTweenY', 'y 坐标'));
		d.push(tweenDef('tw_angle', '补间旋转角度', 'doTweenAngle', '角度'));
		d.push(tweenDef('tw_alpha', '补间透明度', 'doTweenAlpha', '透明度 0-1'));
		d.push(tweenDef('tw_zoom', '补间镜头缩放', 'doTweenZoom', '缩放倍数', 'camGame'));
		d.push(new BlockDef('tw_color', CAT_TWEEN, '补间颜色', 'doTweenColor(\'{p:tag}\', \'{p:obj}\', \'{p:color}\', {p:dur}, \'{p:ease}\')', [
			new PDef('tag', '补间标签', KText, 'myTween', '每个补间标签必须唯一，取消补间时用同一个标签'),
			new PDef('obj', '目标对象', KText, 'mySprite', ''),
			new PDef('color', '目标颜色', KText, 'FF0000', '十六进制'),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('ease', '缓动', KEnum(EASES), 'quadOut', '')
		], false, false, false, 'doTweenColor(tag, obj, 颜色, 时长, 缓动)。'));
		d.push(new BlockDef('tw_start', CAT_TWEEN, '通用属性补间', 'startTween(\'{p:tag}\', \'{p:obj}\', {{p:prop} = {p:value}}, {p:dur}, {{ease = \'{p:ease}\'}})', [
			new PDef('tag', '补间标签', KText, 'myTween', '唯一'),
			new PDef('obj', '目标对象', KText, 'mySprite', ''),
			new PDef('prop', '属性', KText, 'angle', '如 angle / alpha / scale.x'),
			new PDef('value', '目标值', KNum, '360', ''),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('ease', '缓动', KEnum(EASES), 'sineInOut', '')
		], false, false, false, 'startTween（可补间任意属性）。'));
		d.push(new BlockDef('tw_cancel', CAT_TWEEN, '取消补间', 'cancelTween(\'{p:tag}\')', [
			new PDef('tag', '补间标签', KText, 'myTween', '与创建时的标签一致')
		], false, false, false, 'cancelTween。'));

		// ---------------- 相机（5）----------------
		d.push(new BlockDef('cam_target', CAT_CAM, '镜头切到角色', 'cameraSetTarget(\'{p:target}\')', [
			new PDef('target', '目标', KEnum(['dad', 'boyfriend']), 'dad', '')
		], false, false, false, 'cameraSetTarget。'));
		d.push(new BlockDef('cam_shake', CAT_CAM, '镜头震动', 'cameraShake(\'{p:cam}\', {p:intensity}, {p:dur})', [
			new PDef('cam', '相机', KEnum(CAMERAS), 'camGame', ''),
			new PDef('intensity', '强度', KNum, '0.02', ''),
			new PDef('dur', '时长（秒）', KNum, '1', '')
		], false, false, false, 'cameraShake。'));
		d.push(new BlockDef('cam_flash', CAT_CAM, '镜头闪光', 'cameraFlash(\'{p:cam}\', \'{p:color}\', {p:dur}, {p:forced})', [
			new PDef('cam', '相机', KEnum(CAMERAS), 'camGame', ''),
			new PDef('color', '颜色', KText, 'FFFFFF', ''),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('forced', '强制', KEnum(['true', 'false']), 'true', '')
		], false, false, false, 'cameraFlash。'));
		d.push(new BlockDef('cam_fade', CAT_CAM, '镜头淡色', 'cameraFade(\'{p:cam}\', \'{p:color}\', {p:dur}, {p:forced})', [
			new PDef('cam', '相机', KEnum(CAMERAS), 'camGame', ''),
			new PDef('color', '颜色', KText, '000000', ''),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('forced', '强制', KEnum(['true', 'false']), 'true', '')
		], false, false, false, 'cameraFade。'));
		d.push(new BlockDef('cam_zoomSet', CAT_CAM, '直接设置镜头缩放', 'setProperty(\'{p:cam}.zoom\', {p:value})', [
			new PDef('cam', '相机', KEnum(CAMERAS), 'camGame', ''),
			new PDef('value', '缩放', KNum, '1', '1 = 原始大小')
		], false, false, false, '需要平滑过渡请用"补间镜头缩放"。'));

		// ---------------- 音频（10）----------------
		d.push(new BlockDef('snd_playSound', CAT_SOUND, '播放音效', '', [
			new PDef('sound', '音效', KText, 'scrollMenu', 'sounds/ 下的名字'),
			new PDef('vol', '音量', KNum, '1', '0-1'),
			new PDef('tag', '标签', KText, '', '留空 = 不可控的一次性播放；填标签后可用停止/暂停/淡出积木')
		], false, false, false, 'playSound（标签留空时生成两参形式）。'));
		d.push(new BlockDef('snd_playMusic', CAT_SOUND, '播放音乐', 'playMusic(\'{p:sound}\', {p:vol}, {p:loop})', [
			new PDef('sound', '音乐', KText, 'song', ''),
			new PDef('vol', '音量', KNum, '1', ''),
			new PDef('loop', '循环', KEnum(['false', 'true']), 'false', '')
		], false, false, false, 'playMusic。'));
		d.push(new BlockDef('snd_stop', CAT_SOUND, '停止音效', 'stopSound(\'{p:tag}\')', [new PDef('tag', '标签', KText, 'mySound', '')], false, false, false, 'stopSound。'));
		d.push(new BlockDef('snd_pause', CAT_SOUND, '暂停音效', 'pauseSound(\'{p:tag}\')', [new PDef('tag', '标签', KText, 'mySound', '')], false, false, false, 'pauseSound。'));
		d.push(new BlockDef('snd_resume', CAT_SOUND, '继续音效', 'resumeSound(\'{p:tag}\')', [new PDef('tag', '标签', KText, 'mySound', '')], false, false, false, 'resumeSound。'));
		d.push(new BlockDef('snd_setVolume', CAT_SOUND, '设置音效音量', 'setSoundVolume(\'{p:tag}\', {p:value})', [
			new PDef('tag', '标签', KText, 'mySound', ''),
			new PDef('value', '音量', KNum, '1', '')
		], false, false, false, 'setSoundVolume。'));
		d.push(new BlockDef('snd_fadeOut', CAT_SOUND, '音效淡出', 'soundFadeOut(\'{p:tag}\', {p:dur}, {p:to})', [
			new PDef('tag', '标签', KText, 'mySound', ''),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('to', '淡到音量', KNum, '0', '')
		], false, false, false, 'soundFadeOut。'));
		d.push(new BlockDef('snd_fadeIn', CAT_SOUND, '音效淡入', 'soundFadeIn(\'{p:tag}\', {p:dur}, {p:from}, {p:to})', [
			new PDef('tag', '标签', KText, 'mySound', ''),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('from', '起始音量', KNum, '0', ''),
			new PDef('to', '目标音量', KNum, '1', '')
		], false, false, false, 'soundFadeIn。'));
		d.push(new BlockDef('snd_musicFadeOut', CAT_SOUND, '歌曲淡出', 'musicFadeOut({p:dur}, {p:to})', [
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('to', '淡到音量', KNum, '0', '')
		], false, false, false, 'musicFadeOut。'));
		d.push(new BlockDef('snd_musicFadeIn', CAT_SOUND, '歌曲淡入', 'musicFadeIn({p:dur}, {p:from}, {p:to})', [
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('from', '起始音量', KNum, '0', ''),
			new PDef('to', '目标音量', KNum, '1', '')
		], false, false, false, 'musicFadeIn。'));

		// ---------------- 文本（10）----------------
		d.push(new BlockDef('txt_make', CAT_TEXT, '创建文本', 'makeLuaText(\'{p:tag}\', \'{p:text}\', {p:width}, {p:x}, {p:y})', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('text', '内容', KText, '文字内容', '可中文'),
			new PDef('width', '宽度', KNum, '400', '0 = 自适应'),
			new PDef('x', 'X', KNum, '100', ''),
			new PDef('y', 'Y', KNum, '100', '')
		], false, false, false, 'makeLuaText。'));
		d.push(new BlockDef('txt_add', CAT_TEXT, '把文本加进舞台', 'addLuaText(\'{p:tag}\')', [new PDef('tag', '标签', KTag, 'myText', '')], false, false, false, 'addLuaText。'));
		d.push(new BlockDef('txt_set', CAT_TEXT, '设置文本内容', 'setTextString(\'{p:tag}\', \'{p:text}\')', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('text', '内容', KText, '新内容', '')
		], false, false, false, 'setTextString。'));
		d.push(new BlockDef('txt_size', CAT_TEXT, '设置文本字号', 'setTextSize(\'{p:tag}\', {p:size})', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('size', '字号', KNum, '24', '')
		], false, false, false, 'setTextSize。'));
		d.push(new BlockDef('txt_width', CAT_TEXT, '设置文本宽度', 'setTextWidth(\'{p:tag}\', {p:width})', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('width', '宽度', KNum, '400', '')
		], false, false, false, 'setTextWidth。'));
		d.push(new BlockDef('txt_color', CAT_TEXT, '设置文本颜色', 'setTextColor(\'{p:tag}\', \'{p:color}\')', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('color', '颜色', KText, 'FFFFFF', '')
		], false, false, false, 'setTextColor。'));
		d.push(new BlockDef('txt_border', CAT_TEXT, '设置文本描边', 'setTextBorder(\'{p:tag}\', {p:size}, \'{p:color}\')', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('size', '描边粗细', KNum, '2', ''),
			new PDef('color', '颜色', KText, '000000', '')
		], false, false, false, 'setTextBorder。'));
		d.push(new BlockDef('txt_font', CAT_TEXT, '设置文本字体', 'setTextFont(\'{p:tag}\', \'{p:font}\')', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('font', '字体', KText, 'future.ttf', '需已在 assets/fonts 内')
		], false, false, false, 'setTextFont。'));
		d.push(new BlockDef('txt_align', CAT_TEXT, '设置文本对齐', 'setTextAlignment(\'{p:tag}\', \'{p:align}\')', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('align', '对齐', KEnum(['left', 'center', 'right']), 'center', '')
		], false, false, false, 'setTextAlignment。'));
		d.push(new BlockDef('txt_remove', CAT_TEXT, '移除文本', 'removeLuaText(\'{p:tag}\', {p:destroy})', [
			new PDef('tag', '标签', KTag, 'myText', ''),
			new PDef('destroy', '同时销毁', KEnum(['true', 'false']), 'true', '')
		], false, false, false, 'removeLuaText。'));

		// ---------------- 杂项（10）----------------
		d.push(new BlockDef('misc_print', CAT_MISC, '打印调试信息', 'debugPrint(\'{p:text}\', \'{p:color}\')', [
			new PDef('text', '内容', KText, '调试输出', '显示在屏幕左上角的调试区'),
			new PDef('color', '颜色', KText, 'WHITE', '如 WHITE / RED / 0xFF00FF')
		], false, false, false, 'debugPrint。'));
		d.push(new BlockDef('misc_timer', CAT_MISC, '启动计时器', 'runTimer(\'{p:tag}\', {p:time}, {p:loops})', [
			new PDef('tag', '标签', KText, 'myTimer', '唯一标签'),
			new PDef('time', '间隔（秒）', KNum, '1', ''),
			new PDef('loops', '循环次数', KNum, '1', '0 = 无限')
		], false, false, false, 'runTimer（配合自定义区里的 onTimerCompleted 使用；本编辑器"等待"积木也用它）。'));
		d.push(new BlockDef('misc_cancelTimer', CAT_MISC, '取消计时器', 'cancelTimer(\'{p:tag}\')', [new PDef('tag', '标签', KText, 'myTimer', '')], false, false, false, 'cancelTimer。'));
		d.push(new BlockDef('misc_triggerEvent', CAT_MISC, '触发事件', 'triggerEvent(\'{p:name}\', \'{p:v1}\', \'{p:v2}\')', [
			new PDef('name', '事件名', KText, 'My Event', '与谱面事件同名即可触发'),
			new PDef('v1', '参数 1', KText, '', ''),
			new PDef('v2', '参数 2', KText, '', '')
		], false, false, false, 'triggerEvent（可直接驱动谱面事件）。'));
		d.push(new BlockDef('misc_healthSet', CAT_MISC, '设置血量', 'setHealth({p:value})', [new PDef('value', '血量', KNum, '2', '上限 2')], false, false, false, 'setHealth。'));
		d.push(new BlockDef('misc_healthAdd', CAT_MISC, '增加血量', 'addHealth({p:value})', [new PDef('value', '增量', KNum, '0.1', '可为负')], false, false, false, 'addHealth。'));
		d.push(new BlockDef('misc_scoreAdd', CAT_MISC, '增加分数', 'addScore({p:value})', [new PDef('value', '分数', KNum, '100', '')], false, false, false, 'addScore。'));
		d.push(new BlockDef('misc_precacheImage', CAT_MISC, '预载图片', 'precacheImage(\'{p:name}\')', [new PDef('name', '图片', KText, 'menuBG', '')], false, false, false, 'precacheImage（避免运行中卡顿）。'));
		d.push(new BlockDef('misc_precacheSound', CAT_MISC, '预载音效', 'precacheSound(\'{p:name}\')', [new PDef('name', '音效', KText, 'scrollMenu', '')], false, false, false, 'precacheSound。'));
		d.push(new BlockDef('misc_comment', CAT_MISC, '注释', '-- {p:text}', [new PDef('text', '注释内容', KText, '说明', '')], false, false, false, '生成一行 Lua 注释，便于阅读。'));

		// ---------------- 兜底（2）----------------
		d.push(new BlockDef('adv_call', CAT_ADV, '调用任意 Lua 函数', '{p:fname}({p:args})', [
			new PDef('fname', '函数名', KText, 'triggerEvent', '引擎注册的 203 个函数任意一个；写错会在游戏内报 nil 调用'),
			new PDef('args', '参数', KExpr, '\'My Event\', \'\', \'\'', '按原样填入括号，字符串记得自己加引号')
		], false, false, false, '覆盖全部引擎 API 的通用出口。'));
		d.push(new BlockDef('adv_lua', CAT_ADV, '直接写一行 Lua', '{p:code}', [
			new PDef('code', '代码', KExpr, 'debugPrint(\'hello\')', '高级用法：原样输出到生成的脚本里')
		], false, false, false, '完全自由的逃生舱；复杂逻辑仍建议写进底部自定义区。'));

		return d;
	}

	static function tweenDef(id:String, label:String, fn:String, valueLabel:String, ?objDef:String):BlockDef
	{
		var obj:String = objDef == null ? 'mySprite' : objDef;
		return new BlockDef(id, CAT_TWEEN, label, fn + '(\'{p:tag}\', \'{p:obj}\', {p:value}, {p:dur}, \'{p:ease}\')', [
			new PDef('tag', '补间标签', KText, 'myTween', '唯一；取消补间时用同一个标签'),
			new PDef('obj', '目标对象', KText, obj, objDef == null ? '精灵标签或角色名' : '相机名（camGame 等）'),
			new PDef('value', valueLabel, KNum, '0', ''),
			new PDef('dur', '时长（秒）', KNum, '1', ''),
			new PDef('ease', '缓动', KEnum(EASES), 'quadOut', '')
		], false, false, false, fn + '(补间标签, 目标对象, 目标值, 时长, 缓动)。');
	}
}

