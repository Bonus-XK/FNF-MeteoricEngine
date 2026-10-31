package modcharting;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// Playfield：一个独立的音符图层（x/y/z 偏移 + 整层透明度），叠加在基准位之上。

class Playfield
{
    public var x:Float = 0;
    public var y:Float = 0;
    public var z:Float = 0;
    public var alpha:Float = 1;

    public function new(x:Float = 0, y:Float = 0, z:Float = 0, alpha:Float = 1)
    {
        this.x = x;
        this.y = y;
        this.z = z;
        this.alpha = alpha;
    }

    public function applyOffsets(noteData:NotePositionData)
    {
        noteData.x += x;
        noteData.y += y;
        noteData.z += z;
        noteData.alpha *= alpha;
    }
}
