package luagraph;

/**
 * 新建模板：给用户一个"能跑起来"的起点，避免面对空画布无从下手。
 * 全部模板都只用真实存在的引擎 API，并且默认资源零依赖（色块精灵而非贴图），
 * 打开即可保存 → 生成 → 进游戏验证。
 */
class LuaGraphTemplates
{
	public static var NAMES:Array<String> = ['空白脚本', '按键生成特效', '镜头缩放', '精灵补间'];

	public static function make(index:Int, name:String):GDoc
	{
		return switch (index)
		{
			case 1: keysfx(name);
			case 2: camzoom(name);
			case 3: spritetween(name);
			default: blank(name);
		}
	}

	public static function blank(name:String):GDoc
	{
		var d:GDoc = base(name);
		d.stacks.push(new GStack('onCreate'));
		d.stacks.push(new GStack('onBeatHit'));
		return d;
	}

	/** 按空格在屏幕上生成一个上飘的色块 + 音效，0.6 秒后自动销毁（演示"等待后继续"）。 */
	public static function keysfx(name:String):GDoc
	{
		var d:GDoc = base(name);
		var s:GStack = new GStack('onKeyPress');

		var cond:GBlock = mk('flow_if', [['cond', "key == 'space'"]]);
		cond.body.push(mk('misc_print', [['text', '按下空格：生成特效'], ['color', 'WHITE']]));
		cond.body.push(mk('spr_makeGraphic', [
			['tag', 'keyNote'], ['x', '0'], ['y', '0'], ['w', '72'], ['h', '72'], ['color', '9CE8FF']
		]));
		cond.body.push(mk('spr_scroll', [['tag', 'keyNote'], ['sx', '0'], ['sy', '0']]));
		cond.body.push(mk('spr_screenCenter', [['tag', 'keyNote'], ['pos', 'xy']]));
		cond.body.push(mk('spr_add', [['tag', 'keyNote'], ['front', 'true']]));
		cond.body.push(mk('snd_playSound', [['sound', 'confirmMenu'], ['vol', '1'], ['tag', 'keySfx']]));
		cond.body.push(mk('tw_angle', [
			['tag', 'keyTw'], ['obj', 'keyNote'], ['value', '360'], ['dur', '0.6'], ['ease', 'quadOut']
		]));
		cond.body.push(mk('flow_wait', [['tag', 'keyWait'], ['secs', '0.6']]));
		cond.body.push(mk('spr_remove', [['tag', 'keyNote'], ['destroy', 'true']]));

		s.blocks.push(cond);
		d.stacks.push(s);
		return d;
	}

	/** 进曲拉镜 + 每 4 拍轻震一下。 */
	public static function camzoom(name:String):GDoc
	{
		var d:GDoc = base(name);

		var start:GStack = new GStack('onSongStart');
		start.blocks.push(mk('tw_zoom', [
			['tag', 'zoomTw'], ['obj', 'camGame'], ['value', '1.15'], ['dur', '2'], ['ease', 'sineInOut']
		]));
		start.blocks.push(mk('misc_print', [['text', '镜头缩放模板已启动'], ['color', 'WHITE']]));
		d.stacks.push(start);

		var beat:GStack = new GStack('onBeatHit');
		var cond:GBlock = mk('flow_if', [['cond', 'curBeat % 4 == 0']]);
		cond.body.push(mk('cam_shake', [['cam', 'camGame'], ['intensity', '0.02'], ['dur', '0.25']]));
		beat.blocks.push(cond);
		d.stacks.push(beat);
		return d;
	}

	/** 创建精灵 → 进场 → 旋转补间；每拍播放一次音效。 */
	public static function spritetween(name:String):GDoc
	{
		var d:GDoc = base(name);

		var create:GStack = new GStack('onCreate');
		create.blocks.push(mk('spr_makeGraphic', [
			['tag', 'meSprite'], ['x', '0'], ['y', '0'], ['w', '160'], ['h', '160'], ['color', 'EA71FD']
		]));
		create.blocks.push(mk('spr_scroll', [['tag', 'meSprite'], ['sx', '0'], ['sy', '0']]));
		create.blocks.push(mk('spr_screenCenter', [['tag', 'meSprite'], ['pos', 'x']]));
		create.blocks.push(mk('spr_graphicSize', [['tag', 'meSprite'], ['w', '160'], ['h', '160']]));
		create.blocks.push(mk('spr_add', [['tag', 'meSprite'], ['front', 'false']]));
		create.blocks.push(mk('spr_setProp', [['tag', 'meSprite'], ['prop', 'y'], ['value', '-200']]));
		create.blocks.push(mk('tw_y', [
			['tag', 'enterTw'], ['obj', 'meSprite'], ['value', '360'], ['dur', '1.2'], ['ease', 'bounceOut']
		]));
		create.blocks.push(mk('tw_angle', [
			['tag', 'spinTw'], ['obj', 'meSprite'], ['value', '360'], ['dur', '2'], ['ease', 'linear']
		]));
		d.stacks.push(create);

		var beat:GStack = new GStack('onBeatHit');
		beat.blocks.push(mk('snd_playSound', [['sound', 'scrollMenu'], ['vol', '0.4'], ['tag', '']]));
		d.stacks.push(beat);

		var destroy:GStack = new GStack('onDestroy');
		destroy.blocks.push(mk('tw_cancel', [['tag', 'spinTw']]));
		destroy.blocks.push(mk('tw_cancel', [['tag', 'enterTw']]));
		destroy.blocks.push(mk('misc_print', [['text', '脚本已销毁，补间已清理'], ['color', 'WHITE']]));
		d.stacks.push(destroy);
		return d;
	}

	static function base(name:String):GDoc
	{
		var d:GDoc = new GDoc();
		d.name = name;
		d.mod = backend.Mods.currentModDirectory == null ? '' : backend.Mods.currentModDirectory;
		return d;
	}

	static function mk(type:String, kv:Array<Array<String>>):GBlock
	{
		var b:GBlock = new GBlock(type);
		b.params = LuaBlockDefs.get(type) != null ? LuaBlockDefs.get(type).defaultParams() : new Map();
		for (pair in kv)
			if (pair.length >= 2) b.set(pair[0], pair[1]);
		return b;
	}
}
