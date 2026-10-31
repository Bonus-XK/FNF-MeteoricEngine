package modcharting;

import backend.Conductor;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// 按拍排程的模表事件队列（Lua 的 set()/ease() 与 modchart.json 的 events 都走这里）。

class ModchartEventManager
{
    private var renderer:PlayfieldRenderer;
    public function new(renderer:PlayfieldRenderer)
    {
        this.renderer = renderer;
    }
    private var events:Array<ModchartEvent> = [];
    public function update(elapsed:Float)
    {
        if (events.length > 1)
        {
            events.sort(function(a, b){
                if (a.time < b.time)
                    return -1;
                else if (a.time > b.time)
                    return 1;
                else
                    return 0;
            });
        }
        while(events.length > 0) {
            var event:ModchartEvent = events[0];
            if(Conductor.songPosition < event.time) {
                break;
            }
            event.func(event.args);
            events.shift();
        }
        Modifier.beat = ((Conductor.songPosition * 0.001) * (Conductor.bpm / 60));
    }
    public function addEvent(beat:Float, func:Array<String>->Void, args:Array<String>)
    {
        var time = ModchartUtil.getTimeFromBeat(beat);
        events.push(new ModchartEvent(time, func, args));
    }
    public function clearEvents()
    {
        events = [];
    }
}
