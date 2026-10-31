package modcharting;
import haxe.Json;
import backend.ClientPrefs;
import backend.Conductor;
import backend.ExtraKeys;
import backend.Paths;
import objects.Note;
import shaders.ColorSwap;
import states.PlayState;
#if sys
import sys.io.File;
import sys.FileSystem;
#end
import hscript.Interp;
import hscript.Parser;
import hscript.Expr;
import lime.utils.Assets;
using StringTools;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// modchart.json 加载 + customMods/*.hx（hscript 自定义修饰器）。
// 文件位置约定（与上游 Psych 一致）：mods/<mod>/data/<谱面>/modchart.json 优先，资源内 data/<谱面>/modchart.json 兜底。

typedef ModchartJson =
{
    var modifiers:Array<Array<Dynamic>>;
    var events:Array<Array<Dynamic>>;
    var playfields:Int;
}

class ModchartFile
{

    //used for indexing
    public static final MOD_NAME = 0; //the modifier name
    public static final MOD_CLASS = 1; //the class/custom mod it uses
    public static final MOD_TYPE = 2; //the type, which changes if its for the player, opponent, a specific lane or all
    public static final MOD_PF = 3; //the playfield that mod uses
    public static final MOD_LANE = 4; //the lane the mod uses

    public static final EVENT_TYPE = 0; //event type (set or ease)
    public static final EVENT_DATA = 1; //event data
    public static final EVENT_REPEAT = 2; //event repeat data

    public static final EVENT_TIME = 0; //event time (in beats)
    public static final EVENT_SETDATA = 1; //event data (for sets)
    public static final EVENT_EASETIME = 1; //event ease time
    public static final EVENT_EASE = 2; //event ease
    public static final EVENT_EASEDATA = 3; //event data (for eases)

    public static final EVENT_REPEATBOOL = 0; //if event should repeat
    public static final EVENT_REPEATCOUNT = 1; //how many times it repeats
    public static final EVENT_REPEATBEATGAP = 2; //how many beats in between each repeat

    public var data:ModchartJson = null;
    private var renderer:PlayfieldRenderer;
    public var scriptListen:Bool = false;
    public var customModifiers:Map<String, CustomModifierScript> = new Map<String, CustomModifierScript>();
    public function new(renderer:PlayfieldRenderer)
    {
        this.renderer = renderer;
        data = loadFromJson(Paths.formatToSongPath(PlayState.SONG.song));
        renderer.modchart = this;
        loadPlayfields();
        loadModifiers();
        loadEvents();
    }

    // 谱面是否带 modchart.json（PlayState.create 用它决定是否创建渲染器；没有数据 = 零开销）
    public static function existsForSong(song:String):Bool
    {
        if (PlayState.SONG == null)
            return false;
        var key:String = Paths.formatToSongPath(song) + '/modchart';
        #if sys
        if (FileSystem.exists(Paths.modsJson(key)))
            return true;
        var filePath:String = Paths.json(key);
        if (FileSystem.exists(filePath))
            return true;
        #end
        return Assets.exists(Paths.json(key));
    }

    public function loadFromJson(folder:String):ModchartJson //load da shit
    {
        var rawJson = null;
        var folderShit:String = "";
        #if sys
        var moddyFile:String = Paths.modsJson(folder + '/modchart');
        if (FileSystem.exists(moddyFile)) {
            rawJson = File.getContent(moddyFile).trim();
            folderShit = moddyFile.replace("modchart.json", "customMods/");
        }
        #end
        if (rawJson == null)
        {
            var filePath = Paths.json(folder + '/modchart');
            folderShit = filePath.replace("modchart.json", "customMods/");

            #if sys
            if (FileSystem.exists(filePath))
                rawJson = File.getContent(filePath).trim();
            else
            #end
                if (Assets.exists(filePath))
                    rawJson = Assets.getText(filePath).trim();
        }
        var json:ModchartJson = null;
        if (rawJson != null)
        {
            json = cast Json.parse(rawJson);
            trace('[Modchart] 已加载 $folderShit');
            #if sys
            if (FileSystem.isDirectory(folderShit))
            {
                for (file in FileSystem.readDirectory(folderShit))
                {
                    if (file.endsWith('.hx')) //custom mods!!!!
                    {
                        var scriptStr = File.getContent(folderShit + file);
                        var script = new CustomModifierScript(scriptStr);
                        customModifiers.set(file.replace(".hx", ""), script);
                    }
                }
            }
            #end
        }
        else
        {
            json = {modifiers: [], events: [], playfields: 1};
        }
        return json;
    }
    public function loadEmpty()
    {
        data.modifiers = [];
        data.events = [];
        data.playfields = 1;
    }

    public function loadModifiers()
    {
        if (data == null || renderer == null)
            return;
        renderer.modifierTable.clear();
        for (i in data.modifiers)
        {
            ModchartFuncs.startMod(i[MOD_NAME], i[MOD_CLASS], i[MOD_TYPE], Std.parseInt(i[MOD_PF]));
            if (i[MOD_LANE] != null)
                ModchartFuncs.setModTargetLane(i[MOD_NAME], i[MOD_LANE]);
        }
        renderer.modifierTable.reconstructTable();
    }
    public function loadPlayfields()
    {
        if (data == null || renderer == null)
            return;

        renderer.playfields = [];
        for (i in 0...data.playfields)
            renderer.addNewPlayfield(0, 0, 0, 1);
    }
    public function loadEvents()
    {
        if (data == null || renderer == null)
            return;
        renderer.eventManager.clearEvents();
        for (i in data.events)
        {
            if (i[EVENT_REPEAT] == null) //add repeat data if it doesnt exist
                i[EVENT_REPEAT] = [false, 1, 0];

            if (i[EVENT_REPEAT][EVENT_REPEATBOOL])
            {
                for (j in 0...(Std.int(i[EVENT_REPEAT][EVENT_REPEATCOUNT]) + 1))
                {
                    addEvent(i, (j * i[EVENT_REPEAT][EVENT_REPEATBEATGAP]));
                }
            }
            else
            {
                addEvent(i);
            }

        }
    }
    private function addEvent(i:Array<Dynamic>, ?beatOffset:Float = 0)
    {
        switch(i[EVENT_TYPE])
        {
            case "ease":
                ModchartFuncs.ease(Std.parseFloat(i[EVENT_DATA][EVENT_TIME]) + beatOffset, Std.parseFloat(i[EVENT_DATA][EVENT_EASETIME]), i[EVENT_DATA][EVENT_EASE], i[EVENT_DATA][EVENT_EASEDATA]);
            case "set":
                ModchartFuncs.set(Std.parseFloat(i[EVENT_DATA][EVENT_TIME]) + beatOffset, i[EVENT_DATA][EVENT_SETDATA]);
            case "hscript":
                //maybe just run some code???
        }
    }

    public function createDataFromRenderer() //a way to convert script modcharts into json modcharts
    {
        if (renderer == null)
            return;

        data.playfields = renderer.playfields.length;
        scriptListen = true;
    }
}

class CustomModifierScript
{
    public var interp:Interp = null;
    var script:Expr;
    var parser:Parser;
    public function new(scriptStr:String)
    {
        parser = new Parser();
        parser.allowTypes = true;
        parser.allowMetadata = true;
        parser.allowJSON = true;

        try
        {
            interp = new Interp();
            script = parser.parseString(scriptStr); //load da shit
            interp.execute(script);
        }
        catch(e)
        {
            lime.app.Application.current.window.alert(e.message, 'Error on custom mod .hx!');
            return;
        }
        init();
    }
    private function init()
    {
        if (interp == null)
            return;

        interp.variables.set('Math', Math);
        interp.variables.set('PlayfieldRenderer', PlayfieldRenderer);
        interp.variables.set('ModchartUtil', ModchartUtil);
        interp.variables.set('Modifier', Modifier);
        interp.variables.set('ModifierSubValue', Modifier.ModifierSubValue);
        interp.variables.set('BeatXModifier', Modifier.BeatXModifier);
        interp.variables.set('NoteMovement', NoteMovement);
        interp.variables.set('NotePositionData', NotePositionData);
        interp.variables.set('ModchartFile', ModchartFile);
        interp.variables.set('ModchartFuncs', ModchartFuncs);
        interp.variables.set('ExtraKeys', ExtraKeys);
        interp.variables.set('FlxG', flixel.FlxG);
        interp.variables.set('FlxSprite', flixel.FlxSprite);
        interp.variables.set('FlxMath', flixel.math.FlxMath);
        interp.variables.set('FlxCamera', flixel.FlxCamera);
        interp.variables.set('FlxTimer', flixel.util.FlxTimer);
        interp.variables.set('FlxTween', flixel.tweens.FlxTween);
        interp.variables.set('FlxEase', flixel.tweens.FlxEase);
        interp.variables.set('PlayState', PlayState);
        interp.variables.set('game', PlayState.instance);
        interp.variables.set('Paths', Paths);
        interp.variables.set('Conductor', Conductor);
        interp.variables.set('StringTools', StringTools);
        interp.variables.set('Note', Note);
        interp.variables.set('ClientPrefs', ClientPrefs);
        interp.variables.set('ColorSwap', ColorSwap);
    }
    public function call(event:String, args:Array<Dynamic>)
    {
        if (interp == null)
            return;
        if (interp.variables.exists(event)) //make sure it exists
        {
            try
            {
                if (args.length > 0)
                    Reflect.callMethod(null, interp.variables.get(event), args);
                else
                    interp.variables.get(event)(); //if function doesnt need an arg
            }
            catch(e)
            {
                lime.app.Application.current.window.alert(e.message, 'Error on custom mod .hx!');
            }
        }
    }
    public function initMod(mod:Modifier)
    {
        call("initMod", [mod]);
    }

    public function destroy()
    {
        interp = null;
    }
}
