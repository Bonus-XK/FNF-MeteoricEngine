/**
 * CNE 谱面导入（states/editors/content/CneExport.cneToPsych）算法级实跑测试。
 *
 * 目的：在没有 CNE 样本 mod、且用户要求"只构建不启动"的前提下，**直接执行仓库真实源码**
 * （本目录的 CneExport.hx 是从仓库逐字节复制的副本，只把 flixel/backend 依赖替换为
 * 逐字段一致的测试替身），用 CNE 官方 base 谱面 + 一份覆盖全部规则分支的合成谱面做断言。
 *
 * 运行：haxe -cp /tmp/cne_oracle -main Test --interp
 */
class Test
{
	static var failures:Int = 0;

	static function check(label:String, ok:Bool, detail:String = ''):Void
	{
		Sys.println((ok ? 'PASS  ' : 'FAIL  ') + label + (detail.length > 0 ? '   [' + detail + ']' : ''));
		if (!ok) failures++;
	}

	static function main():Void
	{
		// CNE 源码根目录：由 run.sh 传入（默认取本机 Documents 下的快照），用于读官方 base 谱面
		var cneRoot:String = Sys.getEnv('CNE_SRC_ROOT');
		if (cneRoot == null || cneRoot.length == 0) cneRoot = '/Users/raidbounce/Documents/CodenameEngine-main';

		// ---------------- A) CNE 官方 base 谱面（真实数据） ----------------
		var chartPath:String = cneRoot + '/assets/songs/bopeebo/charts/normal.json';
		var metaPath:String = cneRoot + '/assets/songs/bopeebo/meta.json';
		var raw:String = sys.io.File.getContent(chartPath);
		var meta:String = sys.io.File.getContent(metaPath);

		check('A1 isCneFormat(官方谱面)', states.editors.content.CneExport.isCneFormat(raw));

		var cne:Dynamic = haxe.Json.parse(raw);
		var rawCount:Int = 0;
		var expPlayer:Int = 0;
		var expOpp:Int = 0;
		var expGf:Int = 0;
		for (line in cast(cne.strumLines, Array<Dynamic>))
		{
			var notes:Array<Dynamic> = cast line.notes;
			var cnt:Int = (notes == null) ? 0 : notes.length;
			rawCount += cnt;
			switch (Std.int(line.type))
			{
				case 1: expPlayer += cnt;
				case 0: expOpp += cnt;
				default: expGf += cnt;
			}
		}

		var song:backend.Song.SwagSong = states.editors.content.CneExport.cneToPsych(raw, meta);
		check('A2 转换返回非空', song != null);
		if (song == null)
		{
			Sys.println('FAILURES=' + failures);
			Sys.exit(1);
			return;
		}

		var total:Int = 0, player:Int = 0, opponent:Int = 0, holds:Int = 0, typed:Int = 0;
		var lastTime:Float = 0;
		var gfSections:Int = 0;
		for (sec in song.notes)
		{
			if (sec.gfSection) gfSections++;
			for (n in sec.sectionNotes)
			{
				total++;
				if (Std.int(n[1]) < 4) player++ else opponent++;
				if (Std.parseFloat(Std.string(n[2])) > 0) holds++;
				if (n[3] != null && Std.string(n[3]).length > 0) typed++;
				var t:Float = Std.parseFloat(Std.string(n[0]));
				if (t > lastTime) lastTime = t;
			}
		}

		Sys.println('  [A] raw notes=' + rawCount + ' (player=' + expPlayer + ' opponent=' + expOpp + ' gf=' + expGf + ')'
			+ ' → psych notes=' + total + ' (player=' + player + ' opponent=' + opponent + ')'
			+ ' holds=' + holds + ' typed=' + typed + ' sections=' + song.notes.length);

		check('A3 音符总数守恒', total == rawCount, 'raw=' + rawCount + ' psych=' + total);
		check('A4 玩家线音符全部落列 <4', player == expPlayer, 'expect=' + expPlayer + ' got=' + player);
		check('A5 对手线音符全部落列 >=4', opponent == expOpp, 'expect=' + expOpp + ' got=' + opponent);
		check('A6 bpm 来自 meta.json（100）', song.bpm == 100, 'bpm=' + song.bpm);
		check('A7 输出 format 为 psych_v1', song.format == 'psych_v1', 'format=' + song.format);
		check('A8 角色槽来自 strumLines', song.player1 == 'bf' && song.player2 == 'dad' && song.gfVersion == 'gf',
			song.player1 + '/' + song.player2 + '/' + song.gfVersion);
		check('A9 stage 透传', song.stage == 'stage', 'stage=' + song.stage);
		check('A10 谱面自带类型名被别名（No Anim Note → No Animation）', typed > 0, 'typed=' + typed);
		check('A11 段落覆盖到最后一颗音符',
			song.notes.length > 0 && lastTime > 0 && lastTime <= 999999, 'lastTime=' + lastTime);

		// ---------------- B) 合成谱面：覆盖全部规则分支 ----------------
		var synth:String = haxe.Json.stringify({
			codenameChart: true,
			chartVersion: "1.6.0",
			scrollSpeed: 1.7,
			stage: "philly",
			noteTypes: ["No Anim Note"],
			strumLines: [
				{characters: ["dad"], type: 0, position: "dad", visible: true, notes: [
					{time: 500, id: 2, type: 1, sLen: 300},
					{time: 7200, id: 1, type: 0, sLen: 0}
				]},
				{characters: ["bf"], type: 1, position: "boyfriend", visible: true, notes: [
					{time: 1200, id: 0, type: 0, sLen: 0},
					{time: 7500, id: 3, type: 0, sLen: 0}
				]},
				{characters: ["gf"], type: 2, position: "girlfriend", visible: true, notes: [
					{time: 1300, id: 1, type: 0, sLen: 0}
				]}
			],
			events: [
				{name: "Camera Movement", time: 0, params: ([1] : Array<Dynamic>)},
				{name: "BPM Change", time: 2500, params: ([120] : Array<Dynamic>)},
				{name: "Scroll Speed Change", time: 3000, params: ([false, 1.5, 0] : Array<Dynamic>)},
				{name: "Custom Thing", time: 3000, params: (["a", "b"] : Array<Dynamic>)},
				{name: "Camera Flash", time: 3000, params: ([false, -1, 8, "camHUD"] : Array<Dynamic>)},
				{name: "Time Signature Change", time: 4900, params: ([3] : Array<Dynamic>)},
				{name: "Alt Animation Toggle", time: 5000, params: ([true] : Array<Dynamic>)},
				{name: "Play Animation", time: 4000, params: ([0, "dance", true, "NONE"] : Array<Dynamic>)},
				{name: "Play Animation", time: 4500, params: ([1, "hey", true, "NONE"] : Array<Dynamic>)},
				{name: "Camera Movement", time: 7000, params: ([0] : Array<Dynamic>)}
			]
		});

		var s2:backend.Song.SwagSong = states.editors.content.CneExport.cneToPsych(synth, meta);
		check('B1 合成谱面转换非空', s2 != null);
		if (s2 == null)
		{
			Sys.println('FAILURES=' + failures);
			Sys.exit(1);
			return;
		}

		Sys.println('  [B] sections=' + s2.notes.length + ' bpm=' + s2.bpm + ' speed=' + s2.speed
			+ ' stage=' + s2.stage + ' events=' + haxe.Json.stringify(s2.events));
		for (i in 0...s2.notes.length)
		{
			var sec = s2.notes[i];
			Sys.println('  [B] sec' + i + ' mustHit=' + sec.mustHitSection + ' gf=' + sec.gfSection
				+ ' bpm=' + sec.bpm + ' changeBPM=' + sec.changeBPM + ' beats=' + sec.sectionBeats
				+ ' altAnim=' + sec.altAnim + ' notes=' + haxe.Json.stringify(sec.sectionNotes));
		}

		check('B2 段数 = 4', s2.notes.length == 4, 'sections=' + s2.notes.length);
		if (s2.notes.length == 4)
		{
			var s0 = s2.notes[0];
			var s1 = s2.notes[1];
			var s2sec = s2.notes[2];
			var s3 = s2.notes[3];

			// 段 0：镜头在玩家（Camera Movement [1] @0）；对手/玩家/GF 各一颗
			check('B3 段0 mustHit=true（Camera Movement[1]）', s0.mustHitSection == true);
			check('B4 段0 gfSection=true（含 GF 线音符）', s0.gfSection == true);
			check('B5 段0 对手音符列=6（id2+4）', colOf(s0, 500) == 6, 'col=' + colOf(s0, 500));
			check('B6 段0 对手音符类型=No Animation（别名）', typeOf(s0, 500) == 'No Animation', 'type=' + typeOf(s0, 500));
			check('B7 段0 玩家音符列=0', colOf(s0, 1200) == 0, 'col=' + colOf(s0, 1200));
			check('B8 段0 GF 音符取 mustHit 同向列=1', colOf(s0, 1300) == 1, 'col=' + colOf(s0, 1300));
			check('B9 段0 长按长度透传=300', holdOf(s0, 500) == 300, 'sLen=' + holdOf(s0, 500));

			// 段 1：BPM Change @2500 落在本段窗口内 → 本段 bpm=120 且 changeBPM=true
			check('B10 段1 bpm=120（BPM Change 归属本段）', s1.bpm == 120, 'bpm=' + s1.bpm);
			check('B11 段1 changeBPM=true', s1.changeBPM == true);

			// 段 2：Time Signature Change @4900 → beats=3；Alt Animation Toggle @5000 → altAnim=true
			check('B12 段2 sectionBeats=3（Time Signature Change）', s2sec.sectionBeats == 3, 'beats=' + s2sec.sectionBeats);
			check('B13 段2 altAnim=true（Alt Animation Toggle）', s2sec.altAnim == true);

			// 段 3：Camera Movement [0] @7000 → mustHit=false；对手列=5（id1+4）
			check('B14 段3 mustHit=false（Camera Movement[0]）', s3.mustHitSection == false);
			check('B15 段3 对手音符列=5', colOf(s3, 7200) == 5, 'col=' + colOf(s3, 7200));
			check('B16 段3 玩家音符列=3', colOf(s3, 7500) == 3, 'col=' + colOf(s3, 7500));
		}

		check('B17 bpm/speed/stage 透传', s2.bpm == 100 && s2.speed == 1.7 && s2.stage == 'philly',
			s2.bpm + '/' + s2.speed + '/' + s2.stage);

		// 事件：镜头/变速/拍号/交替动画被烘焙进 section，不再出现在 events；其余透传
		var evJson:String = haxe.Json.stringify(s2.events);
		check('B18 事件不含 Camera Movement', evJson.indexOf('Camera Movement') == -1);
		check('B19 事件不含 BPM Change', evJson.indexOf('BPM Change') == -1);
		check('B20 事件不含 Time Signature Change', evJson.indexOf('Time Signature Change') == -1);
		check('B21 事件不含 Alt Animation Toggle', evJson.indexOf('Alt Animation Toggle') == -1);
		check('B22 Scroll Speed Change → Change Scroll Speed', evJson.indexOf('Change Scroll Speed') != -1, evJson);
		check('B23 自定义事件透传', evJson.indexOf('Custom Thing') != -1, evJson);
		// B24：CNE 布尔参数必须归一化成 Psych 的 "1"/"0"（第三方 custom_events 脚本按数字解析）
		// B24：CNE Camera Flash → Psych 约定（value1=时长秒 = stepCrochet/1000*8，bpm100 → 1.2；value2=颜色）
		check('B24 Camera Flash → 时长秒/颜色', evJson.indexOf('[\"Camera Flash\",\"1.2\",\"ffffff\"]') != -1, evJson);
		// B25/B26：CNE `Play Animation` 的 params[0] 是 strumLine 索引，必须按该行 type 映射成
		// Psych 的角色槽（0→dad / 1→bf / 2→gf）。此前写死 'bf'，对手线（type 0，SMA Really Happy
		// 的 reallyhappyrat）的变身动画会被打到玩家 bfsma 身上，而 bfsma 没有 dance/death 动画。
		check('B25 Play Animation[strumLine 0] → dad', evJson.indexOf('["Play Animation","dance","dad"]') != -1, evJson);
		check('B26 Play Animation[strumLine 1] → bf', evJson.indexOf('["Play Animation","hey","bf"]') != -1, evJson);

		// ---------------- C) 曲名兜底（CNE meta.json 常常只有 displayName / 完全没有 name） ----------------
		// C1：谱面内嵌 meta 只有 displayName
		var synth2:String = haxe.Json.stringify({
			codenameChart: true,
			scrollSpeed: 1,
			stage: "stage",
			strumLines: [{characters: ["bf"], type: 1, position: "boyfriend", notes: [{time: 0, id: 0, type: 0, sLen: 0}]}],
			events: [],
			meta: {displayName: "Happy", bpm: 110}
		});
		var s3:backend.Song.SwagSong = states.editors.content.CneExport.cneToPsych(synth2, null, "happy");
		check('C1 内嵌 meta 只有 displayName → song=displayName', s3 != null && s3.song == 'Happy', s3 == null ? 'null' : s3.song);
		check('C1b 内嵌 meta 的 bpm 生效', s3 != null && s3.bpm == 110, s3 == null ? 'null' : Std.string(s3.bpm));

		// C2：谱面完全没有内嵌 meta（SMA 的真实形态）→ bpm 取自外部 meta.json、曲名取目录名 hint
		var synth3:String = haxe.Json.stringify({
			codenameChart: true,
			scrollSpeed: 2.6,
			stage: "street2",
			strumLines: [{characters: ["bfsma"], type: 1, position: "boyfriend", notes: [{time: 0, id: 0, type: 0, sLen: 0}]}],
			events: []
		});
		var s4:backend.Song.SwagSong = states.editors.content.CneExport.cneToPsych(synth3,
			'{"displayName":"Happy","bpm":110,"difficulties":["Hard"],"needsVoices":true}', "happy");
		check('C2 无内嵌 meta → bpm 来自外部 meta.json', s4 != null && s4.bpm == 110, s4 == null ? 'null' : Std.string(s4.bpm));
		check('C2b 无内嵌 meta → 曲名走 displayName', s4 != null && s4.song == 'Happy', s4 == null ? 'null' : s4.song);
		check('C2c displayName 缺失时走目录名 hint',
			states.editors.content.CneExport.cneToPsych(synth3, '{"bpm":110}', "happy").song == 'happy');
		check('C2d 三者都没有时退化为 Unknown',
			states.editors.content.CneExport.cneToPsych(synth3, '{"bpm":110}', null).song == 'Unknown');

		Sys.println(failures == 0 ? 'RESULT: ALL PASS' : 'RESULT: FAILURES=' + failures);
		Sys.exit(failures == 0 ? 0 : 1);
	}

	// -------- 小工具：按时间取段内音符字段 --------
	static function noteAt(sec:backend.Section.SwagSection, time:Float):Dynamic
	{
		for (n in sec.sectionNotes)
			if (Std.parseFloat(Std.string(n[0])) == time) return n;
		return null;
	}

	static function colOf(sec:backend.Section.SwagSection, time:Float):Int
	{
		var n:Dynamic = noteAt(sec, time);
		return (n == null) ? -1 : Std.int(n[1]);
	}

	static function typeOf(sec:backend.Section.SwagSection, time:Float):String
	{
		var n:Dynamic = noteAt(sec, time);
		return (n == null || n[3] == null) ? '' : Std.string(n[3]);
	}

	static function holdOf(sec:backend.Section.SwagSection, time:Float):Float
	{
		var n:Dynamic = noteAt(sec, time);
		return (n == null) ? -1 : Std.parseFloat(Std.string(n[2]));
	}
}
