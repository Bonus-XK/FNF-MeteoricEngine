/**
 * CNE 模组兼容层算法级实跑测试（人物 XML / 周目 XML / 谱面定位 / 音频回退 / zip 暂存）。
 *
 * 说明：`cne/CneModCompat.hx`、`cne/CneZipStore.hx`、`backend/ZipReader.hx` 都是从仓库
 * **逐字节复制**的副本；`backend/Paths.hx` 等替身只保留被调用的入口，其中
 * `formatToSongPath` 与 `modFolders` 的搜索顺序均按仓库原文复制。
 *
 * 运行：haxe -cp . -main Test2 --interp
 */
class Test2
{
	static var failures:Int = 0;

	static function check(label:String, ok:Bool, detail:String = ''):Void
	{
		Sys.println((ok ? 'PASS  ' : 'FAIL  ') + label + (detail.length > 0 ? '   [' + detail + ']' : ''));
		if (!ok) failures++;
	}

	static function write(path:String, content:String):Void
	{
		var dir:String = haxe.io.Path.directory(path);
		if (dir.length > 0 && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(path, content);
	}

	static function main():Void
	{
		// 工作根目录由 run.sh 传入（默认 /tmp/cne_mod_compat_test/），假 mod 与 zip 都建在这里
		var base:String = Sys.getEnv('CNE_TEST_WORK');
		if (base == null || base.length == 0) base = '/tmp/cne_mod_compat_test/';
		if (base.length > 0 && !base.endsWith('/')) base += '/';
		var root:String = base + 'fakemods/';
		// 清空上一次运行残留
		if (sys.FileSystem.exists(root)) deleteRecursive(root);
		sys.FileSystem.createDirectory(root);

		backend.Paths.MODS_ROOT = root;
		backend.Mods.currentModDirectory = 'MyCneMod';
		var mod:String = root + 'MyCneMod/';

		// ---------- 准备假 CNE mod ----------
		write(mod + 'data/characters/testy.xml',
			'<!DOCTYPE codename-engine-character>\n'
			+ '<character sprite="testy" icon="testy-icon" color="#AF66CE" holdTime="6.1" scale="0.9" x="12" y="-34" camx="-8" camy="4" flipX="true" antialiasing="false">\n'
			+ '\t<anim name="idle" anim="Testy idle" x="0" y="0" fps="24" loop="false" indices="2..4,0"/>\n'
			+ '\t<anim name="singLEFT" anim="Testy LEFT" x="-10" y="50" fps="30" loop="true"/>\n'
			+ '</character>');
		write(mod + 'data/weeks/weeks/week1.xml',
			'<!DOCTYPE codename-engine-week>\n'
			+ '<week name="TEST WEEK" chars="dad,bf,gf" sprite="testweek" bgColor="#112233">\n'
			+ '\t<song>Bopeebo</song>\n'
			+ '\t<song displayName="Fresh 2">Fresh</song>\n'
			+ '\t<difficulty name="hard"/>\n'
			+ '\t<difficulty name="normal"/>\n'
			+ '</week>');
		write(mod + 'data/weeks/weeks.txt', '# order file\nweek1\n');
		write(mod + 'data/config/freeplaySonglist.txt', '# CNE 曲目列表\nHappy\nReally Happy\n');
		write(mod + 'songs/happy/charts/hard.json', '{"codenameChart":true,"strumLines":[]}');
		write(mod + 'songs/happy/meta.json', '{"displayName":"Happy","bpm":110,"icon":"face","color":"#FFFFFF","difficulties":["Hard"],"needsVoices":true}');
		write(mod + 'songs/really happy/charts/hard.json', '{"codenameChart":true,"strumLines":[]}');
		write(mod + 'songs/really happy/meta.json', '{"displayName":"Really Happy","bpm":175,"icon":"face2","color":"#112233","difficulties":["hard"],"needsVoices":true}');
		write(mod + 'songs/bopeebo/charts/normal.json', '{"codenameChart":true,"strumLines":[]}');
		write(mod + 'songs/bopeebo/meta.json', '{"displayName":"Bopeebo","bpm":100.0}');
		write(mod + 'songs/bopeebo/song/Inst.ogg', 'x');
		write(mod + 'songs/bopeebo/song/Voices.ogg', 'x');

		// ---------- 1) mod 类型识别 ----------
		check('1 isCneMod(有 data/weeks/weeks 的 mod)=true', cne.CneModCompat.isCneMod('MyCneMod'));
		check('1b isCneMod(不存在)=false', !cne.CneModCompat.isCneMod('NotAMod'));

		// ---------- 2) 人物 XML → Psych JSON ----------
		var charJson:String = cne.CneModCompat.characterJson('testy');
		check('2 characterJson 非空', charJson != null);
		if (charJson != null)
		{
			var c:Dynamic = haxe.Json.parse(charJson);
			Sys.println('  [char] ' + charJson);
			check('2a image=characters/testy', c.image == 'characters/testy', Std.string(c.image));
			check('2b healthicon=testy-icon', c.healthicon == 'testy-icon', Std.string(c.healthicon));
			check('2c color=#AF66CE→[175,102,206]',
				Std.string(c.healthbar_colors) == '[175,102,206]', Std.string(c.healthbar_colors));
			check('2d holdTime→sing_duration=6.1', c.sing_duration == 6.1, Std.string(c.sing_duration));
			check('2e scale=0.9', c.scale == 0.9, Std.string(c.scale));
			check('2f x/y→position=[12,-34]', Std.string(c.position) == '[12,-34]', Std.string(c.position));
			check('2g camx/camy→camera_position=[-8,4]', Std.string(c.camera_position) == '[-8,4]', Std.string(c.camera_position));
			check('2h flipX→flip_x=true', c.flip_x == true);
			check('2i antialiasing=false→no_antialiasing=true', c.no_antialiasing == true);
			check('2j anim 数量=2', c.animations.length == 2, 'n=' + c.animations.length);
			if (c.animations.length == 2)
			{
				var a0:Dynamic = c.animations[0];
				var a1:Dynamic = c.animations[1];
				check('2k anim0 名/前缀/fps/loop', a0.anim == 'idle' && a0.name == 'Testy idle' && a0.fps == 24 && a0.loop == false);
				check('2l anim0 indices="2..4,0"→[2,3,4,0]', Std.string(a0.indices) == '[2,3,4,0]', Std.string(a0.indices));
				check('2m anim0 offsets=[0,0]', Std.string(a0.offsets) == '[0,0]', Std.string(a0.offsets));
				check('2n anim1 offsets=[-10,50]', Std.string(a1.offsets) == '[-10,50]', Std.string(a1.offsets));
				check('2o anim1 fps=30 loop=true', a1.fps == 30 && a1.loop == true);
			}
		}
		check('2p 缺人物返回 null', cne.CneModCompat.characterJson('nobody') == null);

		// ---------- 3) 谱面定位 ----------
		var p1:String = cne.CneModCompat.resolveChartPath('bopeebo', 'bopeebo');
		check('3 默认难度 → charts/normal.json', p1 != null && p1.endsWith('songs/bopeebo/charts/normal.json'), Std.string(p1));
		check('3b 未提供的难度 → null', cne.CneModCompat.resolveChartPath('bopeebo-hard', 'bopeebo') == null);
		write(mod + 'songs/bopeebo/charts/hard.json', '{"codenameChart":true,"strumLines":[]}');
		var p2:String = cne.CneModCompat.resolveChartPath('bopeebo-hard', 'bopeebo');
		check('3c 补上 hard.json → 命中', p2 != null && p2.endsWith('charts/hard.json'), Std.string(p2));
		check('3d metaJsonForChart 回溯 meta.json',
			(cne.CneModCompat.metaJsonForChart(p1) != null && cne.CneModCompat.metaJsonForChart(p1).indexOf('"bpm"') != -1));

		// ---------- 4) 音频回退 ----------
		var s1:String = cne.CneModCompat.resolveCneSound('songs', 'bopeebo/Inst');
		check('4 Inst → songs/bopeebo/song/Inst.ogg', s1 != null && s1.endsWith('songs/bopeebo/song/Inst.ogg'), Std.string(s1));
		var s2:String = cne.CneModCompat.resolveCneSound('songs', 'bopeebo/Voices');
		check('4b Voices → songs/bopeebo/song/Voices.ogg', s2 != null && s2.endsWith('song/Voices.ogg'), Std.string(s2));
		check('4c 不接管 Voices-Player（拆分人声由调用方回退）', cne.CneModCompat.resolveCneSound('songs', 'bopeebo/Voices-Player') == null);
		check('4d 不接管非 songs 目录', cne.CneModCompat.resolveCneSound('music', 'bopeebo/Inst') == null);
		check('4e 音频回退尊重 switch（开关关掉即 null）', switchOffTest());

		// ---------- 5) 周目 XML → Psych WeekFile ----------
		var weeks:Array<Dynamic> = cne.CneModCompat.cneWeekFiles('MyCneMod');
		check('5 周目数量=1', weeks.length == 1, 'n=' + weeks.length);
		if (weeks.length == 1)
		{
			var w:Dynamic = weeks[0].week;
			Sys.println('  [week] ' + haxe.Json.stringify(w));
			check('5a name=week1', weeks[0].name == 'week1', Std.string(weeks[0].name));
			check('5b weekName=TEST WEEK', w.weekName == 'TEST WEEK', Std.string(w.weekName));
			check('5c weekCharacters=[dad,bf,gf]', Std.string(w.weekCharacters) == '[dad,bf,gf]', Std.string(w.weekCharacters));
			check('5d songs 数量=2', w.songs.length == 2, 'n=' + w.songs.length);
			if (w.songs.length == 2)
			{
				check('5e song0=[Bopeebo,bf,[17,34,51]]',
					w.songs[0][0] == 'Bopeebo' && w.songs[0][1] == 'bf' && Std.string(w.songs[0][2]) == '[17,34,51]',
					haxe.Json.stringify(w.songs[0]));
				check('5f song1=Fresh', w.songs[1][0] == 'Fresh', Std.string(w.songs[1][0]));
			}
			check('5g difficulties=hard,normal', w.difficulties == 'hard,normal', Std.string(w.difficulties));
			check('5h freeplayColor=[17,34,51]', Std.string(w.freeplayColor) == '[17,34,51]', Std.string(w.freeplayColor));
			check('5i 无 menubackgrounds 图 → weekBackground 置空（避免加载不存在的贴图）',
				w.weekBackground == '', Std.string(w.weekBackground));
			check('5j startUnlocked=true / hideFreeplay=false', w.startUnlocked == true && w.hideFreeplay == false);
		}

		// ---------- 5b) 无周目 CNE mod 的 Freeplay 曲目列表 → 合成周目 ----------
		check('5b0 songNameFromChartPath 从谱面路径反推曲名',
			cne.CneModCompat.songNameFromChartPath('/x/mods/SMA/songs/happy/charts/hard.json') == 'happy'
			&& cne.CneModCompat.songNameFromChartPath('/x/mods/SMA/songs/happy/charts/variant/hard.json') == 'happy',
			Std.string(cne.CneModCompat.songNameFromChartPath('/x/mods/SMA/songs/happy/charts/hard.json')));
		var fpWeek:Dynamic = cne.CneModCompat.cneFreeplayWeek('MyCneMod');
		check('5b1 合成周目非空', fpWeek != null);
		if (fpWeek != null)
		{
			Sys.println('  [freeplayWeek] ' + haxe.Json.stringify(fpWeek));
			check('5b2 songs 数量=2（含带空格目录名）', fpWeek.songs.length == 2, 'n=' + fpWeek.songs.length);
			check('5b3 displayName/icon/color 取自 meta.json',
				fpWeek.songs[0][0] == 'Happy' && fpWeek.songs[0][1] == 'face' && Std.string(fpWeek.songs[0][2]) == '[255,255,255]',
				haxe.Json.stringify(fpWeek.songs[0]));
			check('5b4 带空格的 CNE 歌曲目录名可命中', fpWeek.songs[1][0] == 'Really Happy', Std.string(fpWeek.songs[1][0]));
			check('5b5 color 解析 #112233', Std.string(fpWeek.songs[1][2]) == '[17,34,51]', Std.string(fpWeek.songs[1][2]));
			check('5b6 difficulties = 各曲并集（Hard,hard）', fpWeek.difficulties == 'Hard,hard', Std.string(fpWeek.difficulties));
			check('5b7 hideStoryMode=true（只在 Freeplay 出现）', fpWeek.hideStoryMode == true && fpWeek.hideFreeplay == false);
		}
		check('5b8 列表缺失时回退扫 songs/ 下含 charts 的目录', fallbackScanTest());

		// ---------- 5b9) Freeplay 图标兜底（SMA meta.icon="face" 不存在 → 用谱面角色图标） ----------
		// 规则（SMA 实测）：① 先对手线（老鼠）；② 对手线内跳过无图标的角色；
		// ③ 对手线全无图标才退玩家线；④ 第二首没有可用兜底时保留 meta.icon。
		var happyChartPath:String = mod + 'songs/happy/charts/hard.json';
		var happyChartBackup:String = sys.io.File.getContent(happyChartPath);
		write(mod + 'images/icons/pico/icon.png', 'x');
		write(mod + 'images/icons/rat/icon.png', 'x');
		write(mod + 'images/icons/randy/icon.png', 'x');

		// ① 对手线有图标 → 优先对手（而不是玩家 bfsma/pico）
		write(happyChartPath, '{"codenameChart":true,"strumLines":[' +
			'{"type":0,"characters":["rat"],"notes":[]},' +
			'{"type":1,"characters":["pico"],"notes":[]},' +
			'{"type":2,"characters":["gf"],"notes":[]}]}');
		cne.CneModCompat.clearCaches();
		var fpA:Dynamic = cne.CneModCompat.cneFreeplayWeek('MyCneMod');
		check('5b9 对手线有图标 → 优先对手（老鼠）', fpA != null && Std.string(fpA.songs[0][1]) == 'rat',
			(fpA == null) ? 'null' : Std.string(fpA.songs[0][1]));

		// ② 对手线首个角色无图标 → 跳到同线下一个可解析角色（SMA smile: randah → randy）
		write(happyChartPath, '{"codenameChart":true,"strumLines":[' +
			'{"type":0,"characters":["noicon","randy"],"notes":[]},' +
			'{"type":1,"characters":["pico"],"notes":[]},' +
			'{"type":2,"characters":["gf"],"notes":[]}]}');
		cne.CneModCompat.clearCaches();
		var fpB:Dynamic = cne.CneModCompat.cneFreeplayWeek('MyCneMod');
		check('5b10 对手线首个无图标 → 同线下一个可解析角色', fpB != null && Std.string(fpB.songs[0][1]) == 'randy',
			(fpB == null) ? 'null' : Std.string(fpB.songs[0][1]));

		// ③ 对手线全无图标 → 退玩家线可解析角色（SMA WHISPERS: whispers → bf）
		write(happyChartPath, '{"codenameChart":true,"strumLines":[' +
			'{"type":0,"characters":["noicon"],"notes":[]},' +
			'{"type":1,"characters":["noicon2","pico"],"notes":[]},' +
			'{"type":2,"characters":["gf"],"notes":[]}]}');
		cne.CneModCompat.clearCaches();
		var fpC:Dynamic = cne.CneModCompat.cneFreeplayWeek('MyCneMod');
		check('5b11 对手线全无图标 → 退玩家线可解析角色', fpC != null && Std.string(fpC.songs[0][1]) == 'pico',
			(fpC == null) ? 'null' : Std.string(fpC.songs[0][1]));
		if (fpC != null)
			check('5b12 无法兜底的第二首保留 meta.icon=face2', Std.string(fpC.songs[1][1]) == 'face2',
				Std.string(fpC.songs[1][1]));
		sys.io.File.saveContent(happyChartPath, happyChartBackup);
		cne.CneModCompat.clearCaches();

		// ---------- 5d) CNE 箭头皮肤（images/game/notes/NOTE_assets*） ----------
		write(mod + 'images/game/notes/NOTE_assets_mack.png', 'x');
		write(mod + 'images/game/notes/NOTE_assets_mack.xml', '<x/>');
		check('5d1 noteSkin 扫出 mod 的 NOTE_assets_mack', cne.CneModCompat.noteSkin() == 'game/notes/NOTE_assets_mack',
			Std.string(cne.CneModCompat.noteSkin()));

		// ---------- 5c) CNE 舞台 XML → StageFile（背景不显示/角色站位的修法） ----------
		write(mod + 'data/stages/street2.xml',
			'<!DOCTYPE codename-engine-stage>\n'
			+ '<stage folder="/" name="street2" zoom="0.75">\n'
			+ '\t<sprite x="-594.1" sprite="street2" y="-301.5" type="none" scale="0.92" name="sprite_3"/>\n'
			+ '\t<girlfriend camyoffset="100"/>\n'
			+ '\t<dad x="-40" y="66.5" camxoffset="75" scale="1.1"/>\n'
			+ '\t<boyfriend x="828.1" y="58.6"/>\n'
			+ '</stage>');
		check('5c1 hasStageXml(有 XML 的舞台)', cne.CneModCompat.hasStageXml('street2'));
		check('5c2 hasStageXml(无 XML 的舞台)=false', !cne.CneModCompat.hasStageXml('nonexistentstage'));
		var sf:Dynamic = cne.CneModCompat.stageFile('street2');
		check('5c3 StageFile 非空', sf != null);
		if (sf != null)
		{
			Sys.println('  [stageFile] ' + haxe.Json.stringify(sf));
			check('5c4 defaultZoom=0.75（CNE stage zoom）', Std.parseFloat(Std.string(sf.defaultZoom)) == 0.75, Std.string(sf.defaultZoom));
			check('5c5 boyfriend 站位=[828.1,58.6]', Std.string(sf.boyfriend) == '[828.1,58.6]', Std.string(sf.boyfriend));
			check('5c6 opponent(dad) 站位=[-40,66.5]', Std.string(sf.opponent) == '[-40,66.5]', Std.string(sf.opponent));
			check('5c7 girlfriend 站位保持默认（XML 未给 x/y）', Std.string(sf.girlfriend) == '[400,130]', Std.string(sf.girlfriend));
			check('5c8 相机偏移 dad camx=75', Std.string(sf.camera_opponent) == '[75,0]', Std.string(sf.camera_opponent));
			check('5c9 相机偏移 gf camy=100', Std.string(sf.camera_girlfriend) == '[0,100]', Std.string(sf.camera_girlfriend));
		}
		var nodes:Array<Dynamic> = cne.CneModCompat.stageSpriteNodes('street2');
		check('5c10 图层节点=1 且 folder/sprite/scale 解析正确',
			nodes.length == 1 && nodes[0].sprite == 'street2' && nodes[0].folder == '' && nodes[0].scaleX == 0.92 && nodes[0].x == -594.1,
			nodes.length == 0 ? 'n=0' : haxe.Json.stringify(nodes[0]));

		// ---------- 6) zip mod 暂存 ----------
		var zipWork:String = base + 'zipwork/';
		if (sys.FileSystem.exists(zipWork)) deleteRecursive(zipWork);
		write(zipWork + 'MyZip/data/characters/zipchar.xml', '<character sprite="z" icon="z"/>');
		write(zipWork + 'MyZip/songs/zipsong/charts/normal.json', '{"codenameChart":true,"strumLines":[]}');
		var zipCmd:String = 'cd "' + zipWork + 'MyZip" && zip -0 -q -r "' + root + 'MyZip.zip" .';
		var code:Int = Sys.command(zipCmd);
		check('6 测试 zip 生成成功', code == 0 && sys.FileSystem.exists(root + 'MyZip.zip'), 'exit=' + code);

		check('6b zipNames 列出 MyZip', cne.CneZipStore.zipNames().indexOf('MyZip') != -1,
			Std.string(cne.CneZipStore.zipNames()));
		var mapped:String = cne.CneZipStore.remapKey('MyZip/data/characters/zipchar.xml');
		check('6c remapKey 指向 _cnestage 且文件已解包',
			mapped != null && mapped.indexOf('_cnestage/MyZip/') != -1 && sys.FileSystem.exists(mapped), Std.string(mapped));
		var mappedChart:String = cne.CneZipStore.remapKey('MyZip/songs/zipsong/charts/normal.json');
		check('6d zip 内 CNE 谱面可定位', mappedChart != null && sys.FileSystem.exists(mappedChart), Std.string(mappedChart));
		check('6e 同名真实文件夹优先（不劫持 MyCneMod）', cne.CneZipStore.remapKey('MyCneMod/data/weeks/weeks.txt') == null);
		check('6f _cnestage 自身不被重映射', cne.CneZipStore.remapKey('_cnestage/MyZip/data/x') == null);
		// 指纹失效 → 重解（改 zip 后 mtime 变化）
		Sys.sleep(1.1);
		write(zipWork + 'MyZip/data/characters/zipchar2.xml', '<character sprite="z2" icon="z2"/>');
		Sys.command('cd "' + zipWork + 'MyZip" && zip -0 -q -r "' + root + 'MyZip.zip" .');
		// 引擎在 Mod 列表刷新时走 clearCaches → CneZipStore.invalidate()，这里模拟同一动作
		cne.CneModCompat.clearCaches();
		var mapped2:String = cne.CneZipStore.remapKey('MyZip/data/characters/zipchar2.xml');
		check('6g zip 更新后指纹失效并重解（新文件可见）',
			mapped2 != null && sys.FileSystem.exists(mapped2), Std.string(mapped2));
		// 6h：走引擎真实入口 Paths.mods（remap → 暂存）而不是直接调 CneZipStore
		var viaPaths:String = backend.Paths.mods('MyZip/songs/zipsong/charts/normal.json');
		check('6h Paths.mods 入口同样命中 zip 内文件',
			viaPaths.indexOf('_cnestage/MyZip/') != -1 && sys.FileSystem.exists(viaPaths), Std.string(viaPaths));

		Sys.println(failures == 0 ? 'RESULT: ALL PASS' : 'RESULT: FAILURES=' + failures);
		Sys.exit(failures == 0 ? 0 : 1);
	}

	/** 删掉 freeplaySonglist.txt 后应回退到扫描 songs/ 下含 charts/ 的目录。 */
	static function fallbackScanTest():Bool
	{
		var listPath:String = '/tmp/cne_mod_compat_test/mod/fakemods/MyCneMod/data/config/freeplaySonglist.txt';
		var backup:String = listPath + '.bak';
		sys.io.File.saveContent(backup, sys.io.File.getContent(listPath));
		sys.FileSystem.deleteFile(listPath);
		cne.CneModCompat.clearCaches();
		var w:Dynamic = cne.CneModCompat.cneFreeplayWeek('MyCneMod');
		sys.io.File.saveContent(listPath, sys.io.File.getContent(backup));
		sys.FileSystem.deleteFile(backup);
		cne.CneModCompat.clearCaches();
		if (w == null) return false;
		var names:Array<String> = [];
		for (s in cast(w.songs, Array<Dynamic>)) names.push(Std.string(s[0]));
		return names.contains('Happy') && names.contains('Really Happy') && names.contains('Bopeebo');
	}

	static function switchOffTest():Bool
	{
		backend.ClientPrefs.data.cneModCompat = false;
		var r:String = cne.CneModCompat.resolveCneSound('songs', 'bopeebo/Inst');
		backend.ClientPrefs.data.cneModCompat = true;
		return r == null;
	}

	static function deleteRecursive(path:String):Void
	{
		if (!sys.FileSystem.exists(path)) return;
		if (sys.FileSystem.isDirectory(path))
		{
			for (f in sys.FileSystem.readDirectory(path)) deleteRecursive(path + '/' + f);
			sys.FileSystem.deleteDirectory(path);
		}
		else sys.FileSystem.deleteFile(path);
	}
}
