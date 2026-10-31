package modcharting;

import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import openfl.geom.Vector3D;
import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;
import backend.Conductor;
import objects.Note;
import objects.StrumNote;
import states.PlayState;
import modcharting.Modifier; // 模块 import：Modifier/ModifierType 及子类型靠它进裸名作用域

using StringTools;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// 核心机制：接管绘制 —— 藏起引擎的音符/判定线组（visible=false 只关绘制不关逻辑），
// 每帧对每个成员跑修饰器管线算出位置数据，再按 z 排序手动 draw。
// 音符的生成、判定、丢失、结算完全不受影响。
//
// Meteoric 适配点：
//  - NoteGroup 池化：成员循环必须跳过已 kill（批处理窗口内仍在 members 里）与 invisible（hideOverlapped）的音符；
//  - 音符角度写入走 Note.engineSetAngle（不污染 copyAngle 的“脚本接管旋转”语义）；
//  - 音符/判定线基础透明度取自真实 strum.alpha（对上 middlescroll 半透 / 关闭对手判定线）；
//  - 长条 curPos 无需上游的 Psych 0.6.x 下落补偿反修（Meteoric 长条不偏移 strumTime）。

typedef StrumNoteType = StrumNote;

class PlayfieldRenderer extends FlxSprite //extending flxsprite just so i can edit draw
{
    public var strumGroup:FlxTypedGroup<StrumNoteType>;
    public var notes:FlxTypedGroup<Note>;
    public var instance:PlayState;
    public var playfields:Array<Playfield> = []; //adding an extra playfield will add 1 for each player

    public var eventManager:ModchartEventManager;
    public var modifierTable:ModTable;
    public var tweenManager:FlxTweenManager;

    public var modchart:ModchartFile;
    public var inEditor:Bool = false;
    public var editorPaused:Bool = false;

    public var speed:Float = 1.0;

    public var modifiers(get, default):Map<String, Modifier>;

    private function get_modifiers() : Map<String, Modifier>
    {
        return modifierTable.modifiers; //back compat with lua modcharts
    }

    public function new(strumGroup:FlxTypedGroup<StrumNoteType>, notes:FlxTypedGroup<Note>, instance:PlayState)
    {
        super(0, 0);
        this.strumGroup = strumGroup;
        this.notes = notes;
        this.instance = instance;

        strumGroup.visible = false; //drawing with renderer instead
        notes.visible = false;

        //fix stupid crash because the renderer in playstate is still technically null at this point and its needed for json loading
        instance.playfieldRenderer = this;

        tweenManager = new FlxTweenManager();
        eventManager = new ModchartEventManager(this);
        modifierTable = new ModTable(instance, this);
        addNewPlayfield(0, 0, 0);
        modchart = new ModchartFile(this);
    }

    public function addNewPlayfield(?x:Float = 0, ?y:Float = 0, ?z:Float = 0, ?alpha:Float = 1)
    {
        playfields.push(new Playfield(x, y, z, alpha));
    }

    // 判定线生成/重建后调用：捕获基准位 + 按实测键数补齐 lane 修饰器并重建命中表
    public function refreshStrumPos():Void
    {
        NoteMovement.getDefaultStrumPos(instance);
        modifierTable.ensureLaneMods();
    }

    override function update(elapsed:Float)
    {
        eventManager.update(elapsed);
        tweenManager.update(elapsed); //should be automatically paused when you pause in game
        super.update(elapsed);
    }

    override public function draw()
    {
        if (alpha == 0 || !visible)
            return;
        if (NoteMovement.defaultStrumX.length == 0)
            return; //判定线基准位还没捕获（create 早期 / startCountdown 之前）

        strumGroup.cameras = this.cameras;
        notes.cameras = this.cameras;

        drawStuff(getNotePositions());
        //draw notes to screen
    }

    private function addDataToStrum(strumData:NotePositionData, strum:FlxSprite)
    {
        strum.x = strumData.x;
        strum.y = strumData.y;
        //strum.z = strumData.z;
        strum.angle = strumData.angle;
        strum.alpha = strumData.alpha;
        strum.scale.x = strumData.scaleX;
        strum.scale.y = strumData.scaleY;
    }

    private function getDataForStrum(i:Int, pf:Int)
    {
        var strumX = NoteMovement.defaultStrumX[i];
        var strumY = NoteMovement.defaultStrumY[i];
        var strumZ = 0;
        var strumScaleX = NoteMovement.defaultScale[i];
        var strumScaleY = NoteMovement.defaultScale[i];
        if (ModchartUtil.getIsPixelStage(instance))
        {
            //work on pixel stages
            strumScaleX = 1 * PlayState.daPixelZoom;
            strumScaleY = 1 * PlayState.daPixelZoom;
        }
        var strumData:NotePositionData = NotePositionData.get();
        strumData.setupStrum(strumX, strumY, strumZ, i, strumScaleX, strumScaleY, pf);
        // 基础透明度取判定线实际值：middlescroll 的 0.35 半透、关闭对手判定线的 0 都从这里来
        var strum:StrumNote = strumGroup.members[i];
        if (strum != null)
            strumData.alpha = strum.alpha;
        playfields[pf].applyOffsets(strumData);
        modifierTable.applyStrumMods(strumData, i, pf);
        return strumData;
    }

    private function addDataToNote(noteData:NotePositionData, daNote:Note)
    {
        daNote.x = noteData.x;
        daNote.y = noteData.y;
        daNote.z = noteData.z;
        daNote.engineSetAngle(noteData.angle); //引擎写入标记：避免关闭 copyAngle 语义
        daNote.alpha = noteData.alpha;
        daNote.scale.x = noteData.scaleX;
        daNote.scale.y = noteData.scaleY;
    }

    private function createDataFromNote(noteIndex:Int, playfieldIndex:Int, curPos:Float, noteDist:Float, incomingAngle:Array<Float>)
    {
        var noteX = notes.members[noteIndex].x;
        var noteY = notes.members[noteIndex].y;
        var noteZ = notes.members[noteIndex].z;
        var lane = getLane(noteIndex);
        var noteScaleX = NoteMovement.defaultScale[lane];
        var noteScaleY = NoteMovement.defaultScale[lane];

        // 基础透明度与引擎 followStrumNote 同源：判定线 alpha × 音符 multAlpha
        var strum:StrumNote = strumGroup.members[lane];
        var noteAlpha:Float = (strum != null ? strum.alpha : 1) * notes.members[noteIndex].multAlpha;

        if (ModchartUtil.getIsPixelStage(instance))
        {
            //work on pixel stages
            noteScaleX = 1 * PlayState.daPixelZoom;
            noteScaleY = 1 * PlayState.daPixelZoom;
        }

        var noteData:NotePositionData = NotePositionData.get();
        noteData.setupNote(noteX, noteY, noteZ, lane, noteScaleX, noteScaleY, playfieldIndex, noteAlpha,
            curPos, noteDist, incomingAngle[0], incomingAngle[1], notes.members[noteIndex].strumTime, noteIndex);
        playfields[playfieldIndex].applyOffsets(noteData);

        return noteData;
    }

    private function getNoteCurPos(noteIndex:Int, strumTimeOffset:Float = 0)
    {
        //Meteorc 的长条子段 strumTime 不做偏移补偿（与 Psych 0.6.x 不同），无需上游的反向修正
        var distance = (Conductor.songPosition - notes.members[noteIndex].strumTime) + strumTimeOffset;
        return distance * getCorrectScrollSpeed();
    }
    private function getLane(noteIndex:Int)
    {
        return (notes.members[noteIndex].mustPress ? notes.members[noteIndex].noteData + NoteMovement.keyCount : notes.members[noteIndex].noteData);
    }
    private function getNoteDist(noteIndex:Int)
    {
        var noteDist = -0.45;
        if (ModchartUtil.getDownscroll(instance))
            noteDist *= -1;
        return noteDist;
    }

    private function getNotePositions()
    {
        var notePositions:Array<NotePositionData> = [];
        for (pf in 0...playfields.length)
        {
            for (i in 0...strumGroup.members.length)
            {
                var strumData = getDataForStrum(i, pf);
                notePositions.push(strumData);
            }
            for (i in 0...notes.members.length)
            {
                var n:Note = notes.members[i];
                // 池化组：批处理窗口内已 kill 的成员仍在 members 里；hideOverlapped 会置 invisible
                if (n == null || !n.exists || !n.visible)
                    continue;

                var songSpeed = getCorrectScrollSpeed();

                var lane = getLane(i);

                var noteDist = getNoteDist(i);
                noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);

                var sustainTimeThingy:Float = 0;

                var curPos = getNoteCurPos(i, sustainTimeThingy);
                curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

                if ((n.wasGoodHit || (n.prevNote != null && n.prevNote.wasGoodHit)) && curPos >= 0 && n.isSustainNote)
                    curPos = 0; //sustain clip

                var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
                if (noteDist < 0)
                    incomingAngle[0] += 180; //make it match for both scrolls

                //get the general note path
                NoteMovement.setNotePath(n, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);

                //save the position data
                var noteData = createDataFromNote(i, pf, curPos, noteDist, incomingAngle);

                //add offsets to data with modifiers
                modifierTable.applyNoteMods(noteData, lane, curPos, pf);

                //add position data to list
                notePositions.push(noteData);
            }
        }
        //sort by z before drawing
        notePositions.sort(function(a, b){
            if (a.z < b.z)
                return -1;
            else if (a.z > b.z)
                return 1;
            else
                return 0;
        });
        return notePositions;
    }

    private function drawStrum(noteData:NotePositionData)
    {
        if (noteData.alpha <= 0)
            return;
        var strumNote = strumGroup.members[noteData.index];
        if (strumNote == null)
            return;
        var thisNotePos = ModchartUtil.calculatePerspective(new Vector3D(noteData.x + (strumNote.width / 2), noteData.y + (strumNote.height / 2), noteData.z * 0.001),
        ModchartUtil.defaultFOV * (Math.PI / 180), -(strumNote.width / 2), -(strumNote.height / 2));

        noteData.x = thisNotePos.x;
        noteData.y = thisNotePos.y;
        noteData.scaleX *= (1 / -thisNotePos.z);
        noteData.scaleY *= (1 / -thisNotePos.z);

        addDataToStrum(noteData, strumGroup.members[noteData.index]); //set position and stuff before drawing
        strumGroup.members[noteData.index].cameras = this.cameras;

        strumGroup.members[noteData.index].draw();
    }
    private function drawNote(noteData:NotePositionData)
    {
        if (noteData.alpha <= 0)
            return;
        var daNote = notes.members[noteData.index];
        if (daNote == null)
            return;
        var thisNotePos = ModchartUtil.calculatePerspective(new Vector3D(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance), noteData.y + (daNote.height / 2), noteData.z * 0.001),
        ModchartUtil.defaultFOV * (Math.PI / 180), -(daNote.width / 2), -(daNote.height / 2));

        noteData.x = thisNotePos.x;
        noteData.y = thisNotePos.y;
        noteData.scaleX *= (1 / -thisNotePos.z);
        noteData.scaleY *= (1 / -thisNotePos.z);
        //set note position using the position data
        addDataToNote(noteData, notes.members[noteData.index]);
        //make sure it draws on the correct camera
        notes.members[noteData.index].cameras = this.cameras;
        //draw it
        notes.members[noteData.index].draw();
    }
    private function drawSustainNote(noteData:NotePositionData)
    {
        if (noteData.alpha <= 0)
            return;
        var daNote = notes.members[noteData.index];
        if (daNote == null)
            return;
        if (daNote.mesh == null)
            daNote.mesh = new SustainStrip(daNote);

        daNote.mesh.scrollFactor.x = daNote.scrollFactor.x;
        daNote.mesh.scrollFactor.y = daNote.scrollFactor.y;
        daNote.alpha = noteData.alpha;
        daNote.mesh.alpha = daNote.alpha;

        var songSpeed = getCorrectScrollSpeed();
        var lane = noteData.lane;

        //makes the sustain match the center of the parent note when at weird angles
        var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);

        var thisNotePos = ModchartUtil.calculatePerspective(new Vector3D(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance), noteData.y + (NoteMovement.arrowSizes[noteData.lane] / 2), noteData.z * 0.001),
        ModchartUtil.defaultFOV * (Math.PI / 180), -(daNote.width / 2), yOffsetThingy - (NoteMovement.arrowSizes[noteData.lane] / 2));

        var timeToNextSustain = ModchartUtil.getFakeCrochet() / 4;
        if (noteData.noteDist < 0)
            timeToNextSustain = -ModchartUtil.getFakeCrochet() / 4; //weird shit that fixes upscroll lol

        var nextHalfNotePos = getSustainPoint(noteData, timeToNextSustain * 0.5);
        var nextNotePos = getSustainPoint(noteData, timeToNextSustain);

        var flipGraphic = false;

        // mod/bound to 360, add 360 for negative angles, mod again just in case
        var fixedAngY = ((noteData.incomingAngleY % 360) + 360) % 360;

        var reverseClip = (fixedAngY > 90 && fixedAngY < 270);

        if (noteData.noteDist > 0) //downscroll
        {
            if (!ModchartUtil.getDownscroll(instance)) //fix reverse
                flipGraphic = true;
        }
        else
        {
            if (ModchartUtil.getDownscroll(instance))
                flipGraphic = true;
        }
        //render that shit
        daNote.mesh.constructVertices(noteData, thisNotePos, nextHalfNotePos, nextNotePos, flipGraphic, reverseClip);

        daNote.mesh.cameras = this.cameras;
        daNote.mesh.draw();
    }

    private function drawStuff(notePositions:Array<NotePositionData>)
    {
        for (noteData in notePositions)
        {
            if (noteData.isStrum) //draw strum
                drawStrum(noteData);
            else if (notes.members[noteData.index] == null)
                continue;
            else if (!notes.members[noteData.index].isSustainNote) //draw regular note
                drawNote(noteData);
            else //draw sustain
                drawSustainNote(noteData);
        }
    }

    function getSustainPoint(noteData:NotePositionData, timeOffset:Float):NotePositionData
    {
        var daNote:Note = notes.members[noteData.index];
        var songSpeed:Float = getCorrectScrollSpeed();
        var lane:Int = noteData.lane;
        var pf:Int = noteData.playfieldIndex;

        var noteDist:Float = getNoteDist(noteData.index);
        var curPos:Float = getNoteCurPos(noteData.index, timeOffset);

        curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

        if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit)) && curPos >= 0)
            curPos = 0;
        noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);
        var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
        if (noteDist < 0)
            incomingAngle[0] += 180; //make it match for both scrolls
        //get the general note path for the next note
        NoteMovement.setNotePath(daNote, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);
        //save the position data
        var noteData = createDataFromNote(noteData.index, pf, curPos, noteDist, incomingAngle);
        //add offsets to data with modifiers
        modifierTable.applyNoteMods(noteData, lane, curPos, pf);
        var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);
        var finalNotePos = ModchartUtil.calculatePerspective(new Vector3D(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance), noteData.y + (NoteMovement.arrowSizes[noteData.lane] / 2), noteData.z * 0.001),
        ModchartUtil.defaultFOV * (Math.PI / 180), -(daNote.width / 2), yOffsetThingy - (NoteMovement.arrowSizes[noteData.lane] / 2));

        noteData.x = finalNotePos.x;
        noteData.y = finalNotePos.y;
        noteData.z = finalNotePos.z;

        return noteData;
    }

    public function getCorrectScrollSpeed():Float
    {
        if (inEditor)
            return PlayState.SONG != null ? PlayState.SONG.speed : 1.0; //just use this while in editor so the instance shit works
        else
            return ModchartUtil.getScrollSpeed(instance);
    }

    override public function destroy()
    {
        if (modchart != null)
        {
            for (customMod in modchart.customModifiers)
            {
                customMod.destroy(); //make sure the interps are dead
            }
        }
        super.destroy();
    }
}
