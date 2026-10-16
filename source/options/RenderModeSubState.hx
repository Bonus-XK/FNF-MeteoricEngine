package options;

import backend.VideoRecorder;
import haxe.io.Path;

/**
 * Render Mode（引擎内置录像）设置页。
 *
 * 机制与 JS Engine 的 Game Renderer 同源，但换掉了它的经典落盘做法：
 * JS Engine 每帧存一张 PNG/JPG，事后手动跑 shell 脚本合成，且**没有音频**。
 * 这里改成帧数据直接管道喂 ffmpeg（不落盘），并把歌曲音频作为第二路输入。
 *
 * 触发：进曲自动开录，录完整首到结算（对齐 JS 的 ffmpegMode 语义）。
 */
class RenderModeSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = '录像';
		rpcTitle = '录像设置菜单';

		if (!VideoRecorder.ffmpegAvailable())
		{
			var warn:Option = new Option('ffmpeg 未安装',
				'录像功能需要 ffmpeg。装好后重启引擎即可使用：\n\nbrew install ffmpeg',
				'renderMode',
				'bool');
			addOption(warn);
			super();
			return;
		}

		var option:Option = new Option('录像模式',
			'开启后，进曲时自动开始录像，录完整首直到结算，\n'
			+ '输出到「输出目录」下的 .mp4。\n\n'
			+ '不需要额外的录屏软件。录像期间会有轻微帧率开销\n'
			+ '（每帧要把画面从显卡读回内存），介意的话录完记得关掉',
			'renderMode',
			'bool');
		addOption(option);

		option = new Option('视频帧率',
			'录像的目标帧率。与游戏实际帧率解耦 ——\n'
			+ '游戏跑再快也只按这个帧率抓帧，避免白白拖慢自己',
			'renderFPS',
			'float');
		option.changeValue = 5;
		option.decimals = 0;
		option.minValue = 10;
		option.maxValue = 240;
		addOption(option);

		option = new Option('视频码率',
			'码率越高画质越好、文件越大。\n1080p60 建议 8-16，720p60 建议 4-8',
			'renderBitrate',
			'float');
		option.changeValue = 1;
		option.decimals = 0;
		option.minValue = 1;
		option.maxValue = 50;
		addOption(option);

		option = new Option('视频编码器',
			'libx264 兼容性最好，通用首选；\nlibx265 同画质体积更小但编码慢；\n其它编码器可用性取决于你的 ffmpeg 构建',
			'renderEncoder',
			'string',
			['libx264', 'libx265', 'libsvtav1', 'mpeg4']);
		addOption(option);

		option = new Option('输出目录',
			'录像文件的输出子目录（相对于 Meteoric.app 所在目录）。\n默认落在 app 旁边，不会写进 bundle 内部',
			'renderPath',
			'string',
			// ⚠ 必须给档位数组：BaseOptionsMenu 的 string 分支直接读 options.length，
			//   传 null 会让游标一进本分区就空引用崩溃（项目里所有 string 选项都带档位）。
			['recordings/', 'recordings/gameplay/', 'recordings/lagtest/']);
		addOption(option);

		super();
	}
}