package modcharting;

import backend.ExtraKeys;
import objects.Note;
import states.PlayState;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// 移植增强：键数一律以 ExtraKeys.songKeys 为准（Meteoric 原生 1~12 键），
// 判定线缩放从真实 StrumNote 读取（含 laneScale），不再硬编码 0.7。

class NoteMovement
{
    public static var keyCount:Int = 4;
    public static var playerKeyCount:Int = 4;
    public static var totalKeyCount:Int = 8;
    public static var arrowScale:Float = 0.7;
    public static var arrowSize:Float = 112;
    public static var defaultStrumX:Array<Float> = [];
    public static var defaultStrumY:Array<Float> = [];
    public static var defaultScale:Array<Float> = [];
    public static var arrowSizes:Array<Float> = [];

    public static function getDefaultStrumPos(game:PlayState):Void
    {
        defaultStrumX = []; //reset
        defaultStrumY = [];
        defaultScale = [];
        arrowSizes = [];

        // 键数：ExtraKeys 是单一事实源；strumLineNotes 差值仅作实测校验
        keyCount = ExtraKeys.songKeys;
        playerKeyCount = ExtraKeys.songKeys;
        var measuredOpponent:Int = game.strumLineNotes.length - game.playerStrums.length;
        if (measuredOpponent > 0)
            keyCount = measuredOpponent;
        if (game.playerStrums.length > 0)
            playerKeyCount = game.playerStrums.length;

        for (i in 0...game.strumLineNotes.members.length)
        {
            var strum = game.strumLineNotes.members[i];
            if (strum == null)
            {
                defaultStrumX.push(0);
                defaultStrumY.push(0);
                defaultScale.push(0.7);
                arrowSizes.push(112);
                continue;
            }
            defaultStrumX.push(strum.x);
            defaultStrumY.push(strum.y);
            // 缩放取判定线实际值：4K 为 0.7，>4K 已按 ExtraKeys.laneScale 缩小
            var s:Float = strum.scale.x > 0 ? strum.scale.x : 0.7;
            defaultScale.push(s);
            arrowSizes.push(160 * s);
        }
        totalKeyCount = keyCount + playerKeyCount;
    }

    public static function setNotePath(daNote:Note, lane:Int, scrollSpeed:Float, curPos:Float, noteDist:Float, incomingAngleX:Float, incomingAngleY:Float)
    {
        daNote.x = defaultStrumX[lane];
        daNote.y = defaultStrumY[lane];
        daNote.z = 0;

        var pos = ModchartUtil.getCartesianCoords3D(incomingAngleX, incomingAngleY, curPos * noteDist);
        daNote.y += pos.y;
        daNote.x += pos.x;
        daNote.z += pos.z;
    }

    // 音符相对本方键位中心的偏移（以“格”为单位）。上游按 4 键硬编码，这里按 playerKeyCount 泛化。
    public static function getLaneDiffFromCenter(lane:Int):Float
    {
        var col:Float = lane % playerKeyCount;
        if ((col + 1) > (playerKeyCount * 0.5))
            col -= (playerKeyCount * 0.5) + 1;
        else
            col -= playerKeyCount * 0.5;
        return col;
    }
}
