package modcharting;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。

class ModchartEvent
{
    public var time:Float = 0;
    public var func:Array<String>->Void;
    public var args:Array<String>;
    public function new(time:Float, func:Array<String>->Void, args:Array<String>)
    {
        this.time = time;
        this.func = func;
        this.args = args;
    }
}
