package states.editors.content;

import haxe.Json;
import flixel.util.FlxSort;
import backend.Song.SwagSong;
import backend.Section.SwagSection;

/**
 * Codename Engine (CNE) 谱面导出 —— 从 Seiun Engine 移植（export 部分）。
 * CNE_CHART_VERSION 1.6.0 与 Seiun 版一致。
 */
class CneExport
{
	public static final CNE_CHART_VERSION:String = "1.6.0";

	public static function psychToCne(song:SwagSong):String
	{
		var cne:Dynamic = buildCneChart(song);
		return Json.stringify(cne, "\t");
	}

	static function buildCneChart(song:SwagSong):Dynamic
	{
		var bpm:Float = song.bpm;
		var speed:Float = song.speed > 0 ? song.speed : 1.0;
		var outStage:String = song.stage != null ? song.stage : "stage";

		// Collect note types
		var noteTypeMap:Map<String, Int> = new Map<String, Int>();
		noteTypeMap.set("", 0);
		var noteTypes:Array<String> = [];
		var nextTypeId:Int = 1;

		function getNoteTypeId(name:String):Int
		{
			if (name == null || name == "") return 0;
			if (noteTypeMap.exists(name)) return noteTypeMap.get(name);
			noteTypeMap.set(name, nextTypeId);
			noteTypes.push(name);
			return nextTypeId++;
		}

		// Build strumLines note arrays
		var playerNotes:Array<Dynamic> = [];
		var opponentNotes:Array<Dynamic> = [];
		var gfNotes:Array<Dynamic> = [];
		var hasGfNotes:Bool = false;

		var curTime:Float = 0;
		var curBpm:Float = bpm;
		var curCrochet:Float = (60 / curBpm) * 1000;
		var beatsPerMeasure:Float = 4;

		if (song.notes != null)
		{
			for (section in song.notes)
			{
				if (section == null)
				{
					curTime += curCrochet * beatsPerMeasure;
					continue;
				}

				if (section.sectionBeats > 0)
					beatsPerMeasure = section.sectionBeats;

				if (section.changeBPM && section.bpm > 0)
				{
					curBpm = section.bpm;
					curCrochet = (60 / curBpm) * 1000;
				}

				if (section.sectionNotes != null)
				{
					for (note in section.sectionNotes)
					{
						var strumTime:Float = note[0];
						var rawData:Int = Std.int(note[1]);
						if (rawData < 0) continue;

						var data:Int = rawData % 4;
						var gottaHitNote:Bool = (rawData < 4);

						var sLen:Float = (note.length > 2 && note[2] != null) ? note[2] : 0;
						var noteTypeName:String = (note.length > 3 && note[3] != null) ? Std.string(note[3]) : "";
						var noteTypeId:Int = getNoteTypeId(noteTypeName);

						var cneNote:Dynamic = {
							time: strumTime,
							id: data,
							type: noteTypeId,
							sLen: sLen
						};

						if (section.gfSection == true && gottaHitNote == section.mustHitSection)
						{
							gfNotes.push(cneNote);
							hasGfNotes = true;
						}
						else if (gottaHitNote)
							playerNotes.push(cneNote);
						else
							opponentNotes.push(cneNote);
					}
				}

				curTime += curCrochet * beatsPerMeasure;
			}
		}

		function sortFn(a:Dynamic, b:Dynamic):Int
		{
			return FlxSort.byValues(FlxSort.ASCENDING, a.time, b.time);
		}
		playerNotes.sort(sortFn);
		opponentNotes.sort(sortFn);
		gfNotes.sort(sortFn);

		// Build strumLines
		var strumLines:Array<Dynamic> = [];

		var p2:String = song.player2 != null ? song.player2 : "dad";
		var p1:String = song.player1 != null ? song.player1 : "bf";
		var gfName:String = song.gfVersion != null ? song.gfVersion : "gf";

		strumLines.push({
			characters: [p2],
			type: 0,
			position: (p2.toLowerCase().startsWith("gf")) ? "girlfriend" : "dad",
			notes: opponentNotes,
			visible: true
		});

		strumLines.push({
			characters: [p1],
			type: 1,
			position: "boyfriend",
			notes: playerNotes,
			visible: true
		});

		if (hasGfNotes || (gfName != "none" && gfName != ""))
		{
			strumLines.push({
				characters: [gfName],
				type: 2,
				position: "girlfriend",
				notes: gfNotes,
				visible: hasGfNotes
			});
		}

		// Build events
		var cneEvents:Array<Dynamic> = [];
		if (song.events != null)
		{
			for (event in song.events)
			{
				if (event == null) continue;
				var t:Float = event[0];
				var subEvents:Array<Dynamic> = event[1];
				if (subEvents == null) continue;

				for (sub in subEvents)
				{
					var evtName:String = sub[0];
					var evtParams:Array<Dynamic> = [];

					switch (evtName)
					{
						case "Change Scroll Speed":
							evtParams.push(false);
							evtParams.push(Std.parseFloat(Std.string(sub[1])));
							evtParams.push(0);
							evtName = "Scroll Speed Change";

						case "Add Camera Zoom":
							evtParams.push(Std.parseFloat(Std.string(sub[1])));
							evtParams.push(Std.parseFloat(Std.string(sub[2])));

						case "Play Animation":
							evtParams.push(0);
							evtParams.push(sub[1]);

						default:
							evtParams.push(sub[1]);
							evtParams.push(sub[2]);
					}

					cneEvents.push({
						name: evtName,
						time: t,
						params: evtParams
					});
				}
			}
		}

		cneEvents.sort(function(a:Dynamic, b:Dynamic):Int {
			return FlxSort.byValues(FlxSort.ASCENDING, a.time, b.time);
		});

		// Build meta
		var meta:Dynamic = {
			name: song.song,
			bpm: bpm,
			needsVoices: song.needsVoices != false,
			beatsPerMeasure: 4,
			stepsPerBeat: 4,
			icon: "face",
			color: [255, 255, 255],
			difficulties: [],
			variants: [],
			coopAllowed: false,
			opponentModeAllowed: false,
			instSuffix: "",
			vocalsSuffix: ""
		};

		// Final chart object
		var chart:Dynamic = {
			codenameChart: true,
			chartVersion: CNE_CHART_VERSION,
			strumLines: strumLines,
			events: cneEvents,
			meta: meta,
			scrollSpeed: speed,
			stage: outStage,
			noteTypes: noteTypes
		};

		return chart;
	}

	// ========================================================================
	// CNE → Psych（「CNE 模组兼容」谱面导入；导出部分的镜像）
	//
	// 语义依据（不要凭印象改）：
	//  - CNE 段结构来源：`CodenameEngine-main/source/funkin/backend/chart/FNFLegacyParser.hx`
	//    · mustHitSection 由 `Camera Movement` 事件的 params[0]（strumLine 索引）决定：
	//      `chart.strumLines[params[0]].type == PLAYER`；
	//    · sectionBeats 由 `Time Signature Change`（params[0]）决定；bpm 由 `BPM Change` 决定；
	//    · altAnim 由 `Alt Animation Toggle` 决定。
	//  - 输出必须是 **psych_v1**：列号 <4 = 玩家、>=4 = 对手，mustHitSection 只管镜头
	//    （Meteoric `PlayState.hx:2156-2198`）。CNE 自家 `FNFLegacyParser.encode` 产的是
	//    0.6.x「相对 mustHitSection」的老语义，若照搬会让对手段音符翻到玩家侧。
	//  - gf 段落：与 mustHitSection 同方向的列由 GF 演奏（同 PlayState.hx:2196-2198）。
	// ========================================================================

	public static function isCneFormat(jsonStr:String):Bool
	{
		if (jsonStr == null || jsonStr.indexOf('"codenameChart"') == -1) return false;
		try
		{
			var data:Dynamic = Json.parse(jsonStr);
			return data != null && (data.codenameChart == true || data.codenameChart == "true") && data.strumLines != null;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	/**
	 * CNE 谱面（codenameChart）→ psych_v1 SwagSong。
	 * @param metaJsonStr CNE `songs/<song>/meta.json` 内容（bpm / needsVoices / instSuffix …）；
	 *                    只在谱面内嵌 meta 缺字段时用于补齐（bpm 是必须的，否则时间轴全错）。
	 */
	public static function cneToPsych(jsonStr:String, ?metaJsonStr:String, ?songNameHint:String):SwagSong
	{
		if (jsonStr == null) return null;
		try
		{
			var data:Dynamic = Json.parse(jsonStr);
			if (data == null || data.strumLines == null) return null;
			return buildPsychSong(data, metaJsonStr, songNameHint);
		}
		catch (e:Dynamic)
		{
			trace('[CNE] chart convert failed: ' + Std.string(e));
			return null;
		}
	}

	static function buildPsychSong(data:Dynamic, metaJsonStr:String, songNameHint:String):SwagSong
	{
		var meta:Dynamic = (data.meta != null) ? data.meta : {};
		if (metaJsonStr != null && metaJsonStr.length > 0)
		{
			var external:Dynamic = null;
			try external = Json.parse(metaJsonStr) catch (e:Dynamic) { external = null; }
			if (external != null)
			{
				for (field in ['name', 'bpm', 'needsVoices', 'instSuffix', 'vocalsSuffix', 'icon',
					'coopAllowed', 'opponentModeAllowed', 'beatsPerMeasure', 'stepsPerBeat', 'displayName'])
				{
					if (Reflect.field(meta, field) == null && Reflect.hasField(external, field))
						Reflect.setField(meta, field, Reflect.field(external, field));
				}
			}
		}

		var bpm:Float = numOf(meta.bpm, 0);
		if (bpm <= 0) bpm = 150; // CNE 正常都有 meta.json bpm；这里只是不崩兜底
		var beatsPerMeasure:Float = numOf(meta.beatsPerMeasure, 4);
		if (beatsPerMeasure <= 0) beatsPerMeasure = 4;

		// 曲名兜底链：CNE 的 `meta.json` 常常只有 `displayName` 没有 `name`（例如 saturday_morning_alive），
		// 谱面内也可能没有内嵌 meta —— 此时必须用**目录名**兜底，否则 SONG.song 退化成 "Unknown"，
		// 之后 Paths.inst(SONG.song) 找不到音频（整首无声）、回放/成绩也按错名字存。
		var stepsPerBeat:Float = numOf(meta.stepsPerBeat, 4);
		if (stepsPerBeat <= 0) stepsPerBeat = 4;

		var songName:String = null;
		if (meta.name != null && Std.string(meta.name).length > 0)
			songName = Std.string(meta.name);
		else if (meta.displayName != null && Std.string(meta.displayName).length > 0)
			songName = Std.string(meta.displayName);
		else if (songNameHint != null && songNameHint.length > 0)
			songName = songNameHint;
		if (songName == null || songName.length == 0) songName = "Unknown";
		var needsVoices:Bool = (meta.needsVoices != false);
		var speed:Float = numOf(data.scrollSpeed, 1);
		if (speed <= 0) speed = 1;
		var stage:String = (data.stage != null && Std.string(data.stage).length > 0) ? Std.string(data.stage) : "stage";

		var noteTypes:Array<String> = [];
		if (data.noteTypes != null)
			for (t in cast(data.noteTypes, Array<Dynamic>)) noteTypes.push((t == null) ? '' : Std.string(t));

		var player1:String = "bf";
		var player2:String = "dad";
		var gfVersion:String = "gf";
		var playerNotes:Array<Dynamic> = [];
		var opponentNotes:Array<Dynamic> = [];
		var gfNotes:Array<Dynamic> = [];
		var lineTypes:Array<Int> = [];

		var lines:Array<Dynamic> = cast data.strumLines;
		if (lines != null)
		{
			for (line in lines)
			{
				if (line == null) continue;
				var lt:Int = intOf(line.type, 0);
				lineTypes.push(lt);

				var chars:Array<Dynamic> = cast line.characters;
				if (chars != null && chars.length > 0 && chars[0] != null)
				{
					var cname:String = Std.string(chars[0]);
					if (cname.length > 0)
					{
						switch (lt)
						{
							case 1: player1 = cname;
							case 0: player2 = cname;
							case 2: gfVersion = cname;
							default:
						}
					}
				}

				var notes:Array<Dynamic> = cast line.notes;
				if (notes == null) continue;
				for (n in notes)
				{
					if (n == null) continue;
					var typeIdx:Int = intOf(n.type, 0);
					var typeName:String = '';
					if (typeIdx > 0 && typeIdx - 1 < noteTypes.length) typeName = noteTypes[typeIdx - 1];
					var mapped:Dynamic = {
						time: numOf(n.time, 0),
						id: intOf(n.id, 0),
						sLen: numOf(n.sLen, 0),
						typeName: aliasNoteType(typeName)
					};
					switch (lt)
					{
						case 1: playerNotes.push(mapped);
						case 2: gfNotes.push(mapped);
						default: opponentNotes.push(mapped);
					}
				}
			}
		}
		playerNotes.sort(sortByTime);
		opponentNotes.sort(sortByTime);
		gfNotes.sort(sortByTime);

		var events:Array<Dynamic> = cast data.events;
		var bpmEvents:Array<Dynamic> = [];
		var camEvents:Array<Dynamic> = [];
		var sigEvents:Array<Dynamic> = [];
		var altEvents:Array<Dynamic> = [];
		if (events != null)
		{
			for (e in events)
			{
				if (e == null) continue;
				var en:String = (e.name != null) ? Std.string(e.name) : '';
				switch (en)
				{
					case 'BPM Change': bpmEvents.push(e);
					case 'Camera Movement': camEvents.push(e);
					case 'Time Signature Change': sigEvents.push(e);
					case 'Alt Animation Toggle': altEvents.push(e);
					default:
				}
			}
		}
		bpmEvents.sort(sortByTime);
		camEvents.sort(sortByTime);
		sigEvents.sort(sortByTime);
		altEvents.sort(sortByTime);

		var lastNoteTime:Float = 0;
		for (arr in [playerNotes, opponentNotes, gfNotes])
			if (arr.length > 0 && arr[arr.length - 1].time > lastNoteTime) lastNoteTime = arr[arr.length - 1].time;

		var sections:Array<SwagSection> = [];
		var curTime:Float = 0;
		var curBpm:Float = bpm;
		var curBeats:Float = beatsPerMeasure;
		var mustHit:Bool = false; // 与 CNE FNFLegacyParser 一致：无 Camera Movement 事件时默认看对手
		var altAnim:Bool = false;
		var pIdx:Int = 0;
		var oIdx:Int = 0;
		var gIdx:Int = 0;
		var bIdx:Int = 0;
		var cIdx:Int = 0;
		var sIdx:Int = 0;
		var aIdx:Int = 0;
		var guard:Int = 0;

		while (curTime <= lastNoteTime + 1 && guard < 200000)
		{
			guard++;

			var crochet:Float = (60 / curBpm) * 1000;
			var sectionEnd:Float = curTime + crochet * curBeats;

			// 事件归属规则与 CNE `FNFLegacyParser.__convertToSwagSections` 一致：
			// 落在本段窗口内（time < sectionEnd）的事件属于本段，并覆盖更早的值。
			// 本段时长仍按进入本段时的 bpm/拍号算，改动从下一段生效（Psych section 语义）。
			while (bIdx < bpmEvents.length && eventTime(bpmEvents[bIdx]) < sectionEnd)
			{
				var v:Float = firstParam(bpmEvents[bIdx], 0);
				if (v > 0) curBpm = v;
				bIdx++;
			}
			while (sIdx < sigEvents.length && eventTime(sigEvents[sIdx]) < sectionEnd)
			{
				var v:Float = firstParam(sigEvents[sIdx], 0);
				if (v > 0) curBeats = v;
				sIdx++;
			}
			while (cIdx < camEvents.length && eventTime(camEvents[cIdx]) < sectionEnd)
			{
				mustHit = camTargetsPlayer(camEvents[cIdx], lineTypes);
				cIdx++;
			}
			while (aIdx < altEvents.length && eventTime(altEvents[aIdx]) < sectionEnd)
			{
				altAnim = firstParam(altEvents[aIdx], 0) != 0;
				aIdx++;
			}

			var sectionNotes:Array<Dynamic> = [];
			var hasGf:Bool = false;

			while (gIdx < gfNotes.length && gfNotes[gIdx].time < sectionEnd)
			{
				var n:Dynamic = gfNotes[gIdx];
				sectionNotes.push([n.time, n.id + (mustHit ? 0 : 4), n.sLen, n.typeName]);
				hasGf = true;
				gIdx++;
			}
			while (pIdx < playerNotes.length && playerNotes[pIdx].time < sectionEnd)
			{
				var n:Dynamic = playerNotes[pIdx];
				sectionNotes.push([n.time, n.id, n.sLen, n.typeName]);
				pIdx++;
			}
			while (oIdx < opponentNotes.length && opponentNotes[oIdx].time < sectionEnd)
			{
				var n:Dynamic = opponentNotes[oIdx];
				sectionNotes.push([n.time, n.id + 4, n.sLen, n.typeName]);
				oIdx++;
			}
			sectionNotes.sort(function(a:Array<Dynamic>, b:Array<Dynamic>):Int {
				var t1:Float = numOf(a[0], 0);
				var t2:Float = numOf(b[0], 0);
				return (t1 < t2) ? -1 : ((t1 > t2) ? 1 : 0);
			});

			var prevBpm:Float = (sections.length > 0) ? sections[sections.length - 1].bpm : bpm;
			sections.push({
				sectionNotes: sectionNotes,
				sectionBeats: curBeats,
				typeOfSection: 0,
				mustHitSection: mustHit,
				gfSection: hasGf,
				altAnim: altAnim,
				changeBPM: (sections.length == 0) ? (curBpm != bpm) : (prevBpm != curBpm),
				bpm: curBpm
			});

			curTime = sectionEnd;
		}

		if (sections.length == 0)
		{
			sections.push({
				sectionNotes: [],
				sectionBeats: 4,
				typeOfSection: 0,
				mustHitSection: true,
				gfSection: false,
				altAnim: false,
				changeBPM: false,
				bpm: bpm
			});
		}

		// 事件转换：镜头/变速/拍号/交替动画已烘焙进 section，不再重复导出
		var psychEvents:Array<Dynamic> = [];
		if (events != null)
		{
			var sorted:Array<Dynamic> = events.copy();
			sorted.sort(sortByTime);
			var i:Int = 0;
			while (i < sorted.length)
			{
				var t:Float = eventTime(sorted[i]);
				var subEvents:Array<Dynamic> = [];
				while (i < sorted.length && eventTime(sorted[i]) == t)
				{
					var e:Dynamic = sorted[i];
					var en:String = (e.name != null) ? Std.string(e.name) : '';
					var params:Array<Dynamic> = cast e.params;
					if (params == null) params = [];

					switch (en)
					{
						case 'Camera Movement', 'BPM Change', 'Time Signature Change', 'Alt Animation Toggle':
							// 已烘焙进 section
						case 'Scroll Speed Change':
							subEvents.push(['Change Scroll Speed',
								(params.length > 1 ? paramText(params[1]) : '1'),
								(params.length > 2 ? paramText(params[2]) : '0')]);
						case 'Add Camera Zoom':
							subEvents.push(['Add Camera Zoom',
								(params.length > 0 ? paramText(params[0]) : '0.015'),
								(params.length > 1 ? paramText(params[1]) : '0.03')]);
						case 'Camera Flash':
							// CNE 参数顺序是 [reversed?, color, timeSteps, camera]，而 Psych 的
							// 同名自定义事件（用户装的 `mods/custom_events/Camera Flash.lua`，文档写
							// "Value 1: speed"）把 value1 当**时长(秒)** 用 → 直接透传 params[0]（bool）
							// 会让 `doTweenAlpha(...,0,...)` 变零时长、白片永不淡出（= 实测的“闪光弹”）。
							// 这里按 CNE 自己的公式换算时长：duration = (stepCrochet/1000) * timeSteps。
							var steps:Float = (params.length > 2) ? numOf(params[2], 0) : 0;
							var stepCrochet:Float = (bpm > 0) ? (60 / bpm / stepsPerBeat) * 1000 : 0;
							var flashDur:Float = (stepCrochet / 1000) * ((steps > 0) ? steps : 4);
							var flashColor:String = colorText(params.length > 1 ? params[1] : null);
							subEvents.push(['Camera Flash', paramText(flashDur), flashColor]);
						case 'Play Animation':
							// CNE 的 `Play Animation` 参数是 [StrumLine 索引, 动画名, 强制?, 上下文]，
							// 而 Psych 同名事件用 value2 指定角色（'bf' → 玩家、'gf' → GF、其余 → dad）。
							// 这里此前硬编码 'bf'，于是对手 strumLine（type 0）的变身动画被打到玩家身上：
							// SMA `Really Happy` 的 `Play Animation [0,"dance"]` / `[0,"death"]` 目标是
							// `reallyhappyrat`，硬编码 'bf' 却让 bfsma 去播 dance/death —— bfsma.xml 里
							// 没有这两个动画 → 实机表现为「人物中途不变身」。改为按 strumLine.type 映射。
							subEvents.push(['Play Animation',
								(params.length > 1 ? paramText(params[1]) : ''),
								animTarget(params, lineTypes)]);
						default:
							if (en.length > 0)
								subEvents.push([en,
									(params.length > 0 ? paramText(params[0]) : ''),
									(params.length > 1 ? paramText(params[1]) : '')]);
					}
					i++;
				}
				if (subEvents.length > 0) psychEvents.push([t, subEvents]);
			}
		}

		var result:SwagSong = {
			song: songName,
			notes: sections,
			events: psychEvents,
			bpm: bpm,
			needsVoices: needsVoices,
			speed: speed,
			player1: player1,
			player2: player2,
			gfVersion: gfVersion,
			stage: stage,
			format: "psych_v1"
		};
		return result;
	}

	/** CNE 默认音符类型名 → Psych 内建类型名（`PlayState.hx:2211-2212` 只认后者的字面量）。 */
	static function aliasNoteType(name:String):String
	{
		if (name == null) return '';
		switch (name)
		{
			case 'No Anim Note': return 'No Animation';
			case 'Alt Anim Note': return 'Alt Animation';
			default: return name;
		}
	}

	/**
	 * CNE 事件参数 → Psych 事件值（都是 String）。
	 *
	 * **布尔必须归一化成 '1'/'0'**：CNE 的事件参数是带类型的（TBool），而 Psych 的事件值是
	 * 「数字字符串」约定 —— 引擎与第三方 `custom_events/*.lua|.hx` 普遍直接 `tonumber(v1)`。
	 * 实测（2026-09-18，saturday_morning_alive）：CNE 的 `Camera Flash` 首参是 bool，
	 * `Std.string(false)` = "false" 交给装了 Psych 全局自定义事件 `mods/custom_events/Camera Flash.lua`
	 * 的用户 → `doTweenAlpha(..., v1, ...)` 拿到非数字 → 原生层 SEGV（崩在 PlayState.create 的事件装载段，
	 * 表现为 139；把该 Lua 移开即不复现）。归一化成 '0' 后该事件按 0 时长处理，合法。
	 */
	static function paramText(v:Dynamic):String
	{
		if (v == null) return '';
		if (Std.isOfType(v, Bool)) return (cast v) ? '1' : '0';
		return Std.string(v);
	}

	/**
	 * CNE 颜色参数 → Psych 自定义事件约定的 6 位十六进制（不带 `#`）。
	 * CNE 里 `-1`/空值是「默认白」（SMA 的 `Camera Flash` 就是 `-1`）。
	 */
	static function colorText(v:Dynamic):String
	{
		if (v == null) return 'ffffff';
		var s:String = Std.string(v);
		if (s.length > 0 && s.charAt(0) == '#' && (s.length == 7 || s.length == 9))
			return s.substr(1, 6).toLowerCase();
		if (s.length == 6)
		{
			var hex:Bool = true;
			for (i in 0...6)
			{
				var c:String = s.charAt(i).toLowerCase();
				if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) { hex = false; break; }
			}
			if (hex) return s.toLowerCase();
		}
		return 'ffffff';
	}

	static function camTargetsPlayer(e:Dynamic, lineTypes:Array<Int>):Bool
	{
		var params:Array<Dynamic> = cast e.params;
		if (params == null || params.length == 0) return false;
		var raw:Dynamic = params[0];
		var idx:Int = intOf(raw, -1);
		if (idx >= 0 && idx < lineTypes.length) return lineTypes[idx] == 1;
		var s:String = Std.string(raw).toLowerCase();
		return (s == 'true' || s == 'boyfriend' || s == 'player' || s == 'bf');
	}

	/**
	 * CNE `Play Animation` 的目标角色 → Psych 同名事件的 value2。
	 *
	 * CNE 的 params[0] 是 **strumLine 索引**（`EventsData.hx` 的 `TStrumLine`），CNE 会
	 * 对该 strumLine 的**全部** `characters` 逐个 `playAnim`（`PlayState.hx` 的
	 * `case "Play Animation"`）；Psych 没有「按行索引选角色」的概念，只有
	 * boyfriend / gf / dad 三个角色，所以按该行的 type 映射：
	 *   0（对手，FNFLegacyParser 的 DAD）→ 'dad'
	 *   1（玩家，BOYFRIEND）             → 'bf'
	 *   2（GF）                          → 'gf'
	 * 越界或未知 type 按 0 处理（与 `camTargetsPlayer` 的默认一致）。
	 */
	static function animTarget(params:Array<Dynamic>, lineTypes:Array<Int>):String
	{
		var idx:Int = (params != null && params.length > 0) ? intOf(params[0], 0) : 0;
		var lt:Int = (idx >= 0 && idx < lineTypes.length) ? lineTypes[idx] : 0;
		return switch (lt)
		{
			case 1: 'bf';
			case 2: 'gf';
			default: 'dad';
		};
	}

	static function eventTime(e:Dynamic):Float
	{
		if (e == null) return 0;
		return numOf(e.time, 0);
	}

	static function firstParam(e:Dynamic, index:Int):Float
	{
		if (e == null) return 0;
		var params:Array<Dynamic> = cast e.params;
		if (params == null || index >= params.length) return 0;
		return numOf(params[index], 0);
	}

	static function numOf(v:Dynamic, def:Float):Float
	{
		if (v == null) return def;
		if (Std.isOfType(v, Bool)) return (cast v) ? 1 : 0;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		var f:Null<Float> = Std.parseFloat(Std.string(v));
		if (f == null || Math.isNaN(f)) return def;
		return f;
	}

	static function intOf(v:Dynamic, def:Int):Int
	{
		return Std.int(numOf(v, def));
	}

	static function sortByTime(a:Dynamic, b:Dynamic):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, a.time, b.time);
	}
}
