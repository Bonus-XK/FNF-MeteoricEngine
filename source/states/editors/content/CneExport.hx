package states.editors.content;

import haxe.Json;
import flixel.util.FlxSort;
import backend.Song.SwagSong;

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
}
