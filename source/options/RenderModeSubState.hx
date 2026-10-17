package options;

import backend.Lang;
import backend.VideoRecorder;

/**
 * Render Mode（引擎内置录像）设置页。
 *
 * 机制与 JS Engine 的 Game Renderer 同源，但换掉了它的经典落盘做法：
 * JS Engine 每帧存一张 PNG/JPG，事后手动跑 shell 脚本合成，且**没有音频**。
 * 这里改成帧数据直接管道喂 ffmpeg（不落盘），并把歌曲音频作为第二路输入。
 *
 * 触发：进曲自动开录，录完整首到结算（对齐 JS 的 ffmpegMode 语义）。
 *
 * ffmpeg 缺席时的行为（2026-10 便携化改造）：
 *   完整选项表**始终都建**（缺 ffmpeg 时只是进曲录像间会失败，设置本身照存）；
 *   若 ClientPrefs.data.ffmpegAutoFetch（默认开）且本机没有 ffmpeg，构造期就把
 *   官方静态构建的安装撂给 VideoRecorder 后台线程，首行「自动获取便携 ffmpeg」
 *   用行名实时反映进度，装好即状态行。玩家全程不用装任何东西；
 *   本机已有 ffmpeg（Homebrew / 用户自装）时这行根本不出现。
 *
 * 行名/说明是动态的，靠 BaseOptionsMenu.externalStep() 由宿主每帧驱动：
 * 整屏路径走 BaseOptionsMenu.update()，单界面路径走 OptionsPane → OptionsState。
 */
class RenderModeSubState extends BaseOptionsMenu
{
	/** 「自动获取」行。字段与 ClientPrefs.data.ffmpegAutoFetch 绑定（一个语义一个字段）。 */
	var fetchRow:Option = null;
	/** 动态行名/说明的已绘制快照：变化才置 rowsDirty，避免每帧无谓重绘。 */
	var paintedRow:String = '';
	var paintedDesc:String = '';

	public function new()
	{
		title = '录像';
		rpcTitle = '录像设置菜单';

		// ffmpeg 已可用（自带 / 用户自装 / 便携已装好）→ 本行根本没有，页面就是纯设置表
		if (!VideoRecorder.ffmpegAvailable())
		{
			fetchRow = makeFetchRow();
			addOption(fetchRow);
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

		// 自动获取：构造期撂给后台线程（幂等，在装/已装好都是 no-op）。
		// OptionsState 的分区是懒构造的 —— 用户第一次进到「录像」分区这里才执行，
		// 不碰暂停内嵌（别的页面）与 PlayState，满足「只在设置页里发生」。
		if (ClientPrefs.data.ffmpegAutoFetch == true)
			startInstall();
		else
			refreshDynamicRow(); // 首帧把行名/说明落到确切状态
	}

	/** 包装一下：防御性 try —— 安装触发失败不能把页面构造拉崩。 */
	function startInstall():Void
	{
		try
		{
			VideoRecorder.startPortableInstall();
		}
		catch (e:Dynamic) {}
		refreshDynamicRow();
	}

	/**
	 * 「自动获取便携 ffmpeg」行：
	 * 变量按时序承载的是**用户是否允许引擎自动装 ffmpeg**（一个语义一个字段，
	 * 与 renderMode 总开关分立）。ENTER 翻到 true = 试图开始/重试；
	 * 翻到 false = 撤销同意（已在跑的那次下载自然走向完成/失败，不再起下一次）。
	 */
	function makeFetchRow():Option
	{
		// 名字/说明交给语言包的 option.ffmpegAutoFetch / optionDesc.ffmpegAutoFetch（两个包都补了 key），
		// tOr 内的字面量只是缺译兜底原文 —— 都以 tOr 第二参的身份出现（i18n 覆盖检查按此豁免）。
		var row:Option = new Option(
			Lang.tOr('option.ffmpegAutoFetch', '自动获取便携 ffmpeg'),
			Lang.tOr('optionDesc.ffmpegAutoFetch',
				'本机没有 ffmpeg 时，引擎自动把官方静态构建装到引擎目录 ffmpeg/ 文件夹，装好录像立即可用，全程无需手动安装。\n关闭后录像功能需自行安装 ffmpeg（Windows: winget install Gyan.FFmpeg / macOS: brew install ffmpeg）'),
			'ffmpegAutoFetch',
			'bool');
		row.onChange = function()
		{
			if (ClientPrefs.data.ffmpegAutoFetch == true) startInstall();
			// 无论开关方向，强制下一帧重算行名/说明（显示要跟状态走）
			paintedRow = '';
			paintedDesc = '';
		};
		return row;
	}

	/**
	 * 每帧驱动（宿主调用）：把 installState 映射成行名 / 说明。
	 * 文本有变化才置 BaseOptionsMenu.rowsDirty（宿主次帧消费重绘，平时零开销）。
	 */
	override public function externalStep():Void
	{
		refreshDynamicRow();
	}

	function refreshDynamicRow():Void
	{
		if (fetchRow == null) return;
		var st:String = VideoRecorder.installState;
		var rowText:String = null;
		var descText:String = null;

		if (st == 'ready')
		{
			rowText = Lang.tOr('ffmpeg.ui.ready', 'ffmpeg 已就绪');
			descText = Lang.tOr('ffmpeg.ui.descReady',
				'官方静态构建已装到引擎目录 ffmpeg/ 文件夹（与录像输出同基准，随目录可携带）。本页下方选项即刻可用。');
		}
		else
		{
			switch (st)
			{
				case 'downloading':
					rowText = Lang.tOr('ffmpeg.ui.dl', '下载中 ') + Std.int(VideoRecorder.installCurMB) + 'MB';
					descText = Lang.tOr('ffmpeg.ui.descDl',
						'正在把官方静态构建下载到引擎目录 ffmpeg/ 文件夹（下载完自动解压安装，无需重启引擎）。期间可以照常改本页其它设置。');
				case 'unpacking':
					rowText = Lang.tOr('ffmpeg.ui.unpack', '解压安装中…');
					descText = Lang.tOr('ffmpeg.ui.descUnpack',
						'正在把 ffmpeg 解压安装到引擎目录 ffmpeg/ 文件夹，几秒就好。');
				case 'error':
					rowText = Lang.tOr('ffmpeg.ui.failed', '下载失败（可重试）');
					var err:String = (VideoRecorder.installError == null) ? '' : VideoRecorder.installError;
					var manual:String = #if windows 'winget install Gyan.FFmpeg' #else 'brew install ffmpeg' #end;
					descText = Lang.tOr('ffmpeg.ui.descFail', '自动下载失败：') + err
						+ '\n\n'
						+ Lang.tOr('ffmpeg.ui.descManual', '下次进本页会自动重试；或手动安装后重启引擎：')
						+ '\n' + manual;
				default:
					// 'idle'：按开关含义给稳定文案（装没装、要不要装在进入本页的瞬间就已定型）
					rowText = Lang.tOr('ffmpeg.ui.title', '自动获取便携 ffmpeg');
					descText = null;
			}
		}

		if (rowText != null && rowText != paintedRow)
		{
			fetchRow.name = rowText;
			paintedRow = rowText;
			BaseOptionsMenu.rowsDirty = true;
		}
		if (descText != null && descText != paintedDesc)
		{
			fetchRow.description = descText;
			paintedDesc = descText;
			BaseOptionsMenu.rowsDirty = true;
		}
	}
}
