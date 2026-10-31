package modcharting;

import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import backend.Conductor;
import states.PlayState;
import modcharting.Modifier; // 模块 import：XModifier/YModifier 等子类型靠它进裸名作用域

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// 修饰器注册表：按 [playfield][lane] 预计算命中表，逐帧管线里只查表不遍历全修饰器。

class ModTable
{
    public var modifiers:Map<String, Modifier> = new Map<String, Modifier>();
    private var instance:PlayState = null;
    private var renderer:PlayfieldRenderer = null;

    //The table is used to precalculate all the playfield and lane checks on each modifier,
    //so it should end up with a lot less loops and if checks each frame
    //index table by playfield, then lane, and then loop through each modifier
    private var table:Array<Array<Array<Modifier>>> = [];

    public function new(instance:PlayState, renderer:PlayfieldRenderer)
    {
        this.instance = instance;
        this.renderer = renderer;
        loadDefaultModifiers();
        reconstructTable();
    }

    public function add(mod:Modifier) : Void
    {
        mod.instance = instance;
        mod.renderer = renderer;
        remove(mod.tag); //in case you replace one???
        modifiers.set(mod.tag, mod);
    }
    public function remove(tag:String) : Void
    {
        if (modifiers.exists(tag))
            modifiers.remove(tag);
    }
    public function clear() : Void
    {
        modifiers.clear();

        loadDefaultModifiers();
    }
    public function resetMods() : Void
    {
        for (mod in modifiers)
            mod.reset();
    }
    public function setModTargetLane(tag:String, lane:Int) : Void
    {
        if (modifiers.exists(tag))
        {
            modifiers.get(tag).targetLane = lane;
        }
    }

    public function loadDefaultModifiers() : Void
    {
        //default modifiers
        add(new XModifier('x'));
        add(new YModifier('y'));
        add(new ZModifier('z'));
        add(new ConfusionModifier('confusion'));
        // 逐格（lane-specific）修饰器按实际总键数生成：x0..x(2k-1)，1~12 键全适配
        for (i in 0...((NoteMovement.keyCount + NoteMovement.playerKeyCount)))
        {
            add(new XModifier('x' + i, ModifierType.LANESPECIFIC));
            add(new YModifier('y' + i, ModifierType.LANESPECIFIC));
            add(new ZModifier('z' + i, ModifierType.LANESPECIFIC));
            add(new ConfusionModifier('confusion' + i, ModifierType.LANESPECIFIC));
            setModTargetLane('x' + i, i);
            setModTargetLane('y' + i, i);
            setModTargetLane('z' + i, i);
            setModTargetLane('confusion' + i, i);
        }
    }

    // 按需补齐 lane-specific 默认修饰器 + 重建命中表。
    // 渲染器在判定线生成前创建时，键数还是默认 4（表只盖 lane 0..7）；
    // 多 K 谱面判定线生成后键数实测变大，必须补齐 x{i}/y{i}/z{i}/confusion{i} 并重建，
    // 否则 lane >= 8 查空表 → 对应判定线/音符不吃任何修饰（实测 6K 谱右侧 4 条判定线不动）。
    // 只补缺失 tag：脚本/json 已改过值的默认修饰器不被覆盖。
    public function ensureLaneMods() : Void
    {
        var total:Int = NoteMovement.keyCount + NoteMovement.playerKeyCount;
        for (i in 0...total)
        {
            if (!modifiers.exists('x' + i))
            {
                add(new XModifier('x' + i, ModifierType.LANESPECIFIC));
                setModTargetLane('x' + i, i);
            }
            if (!modifiers.exists('y' + i))
            {
                add(new YModifier('y' + i, ModifierType.LANESPECIFIC));
                setModTargetLane('y' + i, i);
            }
            if (!modifiers.exists('z' + i))
            {
                add(new ZModifier('z' + i, ModifierType.LANESPECIFIC));
                setModTargetLane('z' + i, i);
            }
            if (!modifiers.exists('confusion' + i))
            {
                add(new ConfusionModifier('confusion' + i, ModifierType.LANESPECIFIC));
                setModTargetLane('confusion' + i, i);
            }
        }
        reconstructTable();
    }

    public function reconstructTable() : Void
    {
        table = [];

        for (pf in 0...renderer.playfields.length)
        {
            if (table[pf] == null)
                table[pf] = [];

            for (lane in 0...NoteMovement.totalKeyCount)
            {
                table[pf].push([]);

                for (mod in modifiers)
                {
                    if (mod.checkLane(lane) && mod.checkPlayField(pf))
                    {
                        table[pf][lane].push(mod); //add mod to table
                    }
                }
            }
        }
    }

    public function applyStrumMods(noteData:NotePositionData, lane:Int, pf:Int) : Void
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList)
                mod.getStrumPath(noteData, lane, pf);
        }
    }
    public function applyNoteMods(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) : Void
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList)
                mod.getNotePath(noteData, lane, curPos, pf);
        }
    }
    public function applyNoteDistMods(noteDist:Float, lane:Int, pf:Int) : Float
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList)
                noteDist = mod.getNoteDist(noteDist, lane, 0, pf);
        }
        return noteDist;
    }
    public function applyCurPosMods(lane:Int, curPos:Float, pf:Int) : Float
    {
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList)
                curPos = mod.getNoteCurPos(lane, curPos, pf);
        }
        return curPos;
    }
    public function applyIncomingAngleMods(lane:Int, curPos:Float, pf:Int) : Array<Float>
    {
        var incomingAngle:Array<Float> = [0, 0];
        if (table[pf] != null && table[pf][lane] != null)
        {
            var modList:Array<Modifier> = table[pf][lane];
            for (mod in modList)
            {
                var ang = mod.getIncomingAngle(lane, curPos, pf); //need to get incoming angle before
                incomingAngle[0] += ang[0];
                incomingAngle[1] += ang[1];
            }
        }
        return incomingAngle;
    }

    public function tweenModifier(modifier:String, val:Float, time:Float, ease:String, beat:Float)
    {
        var modifiers:Map<String, Modifier> = renderer.modifierTable.modifiers;
        if (modifiers.exists(modifier))
        {
            var easefunc = ModchartUtil.getFlxEaseByString(ease);
            if (Conductor.songPosition >= ModchartUtil.getTimeFromBeat(beat) + (time * 1000)) //cancel if should have ended
            {
                modifiers.get(modifier).currentValue = val;
                return;
            }
            time /= renderer.speed;
            var tween = renderer.tweenManager.tween(modifiers.get(modifier), {currentValue: val}, time, {ease: easefunc,
                onComplete: function(twn:FlxTween) {

                }
            });
            if (Conductor.songPosition > ModchartUtil.getTimeFromBeat(beat)) //skip to where it should be i guess??
            {
                @:privateAccess
                tween._secondsSinceStart += ((Conductor.songPosition - ModchartUtil.getTimeFromBeat(beat)) * 0.001);
                @:privateAccess
                tween.update(0);
            }
            if (renderer.editorPaused)
                tween.active = false;
        }
    }

    public function tweenModifierSubValue(modifier:String, subValue:String, val:Float, time:Float, ease:String, beat:Float)
    {
        var modifiers:Map<String, Modifier> = renderer.modifierTable.modifiers;
        if (modifiers.exists(modifier))
        {
            if (modifiers.get(modifier).subValues.exists(subValue))
            {
                var easefunc = ModchartUtil.getFlxEaseByString(ease);
                var tag = modifier + ' ' + subValue;

                var startValue = modifiers.get(modifier).subValues.get(subValue).value;

                if (Conductor.songPosition >= ModchartUtil.getTimeFromBeat(beat) + (time * 1000)) //cancel if should have ended
                {
                    modifiers.get(modifier).subValues.get(subValue).value = val;
                    return;
                }
                time /= renderer.speed;
                var tween = renderer.tweenManager.num(startValue, val, time, {ease: easefunc,
                    onComplete: function(twn:FlxTween) {
                        if (modifiers.exists(modifier))
                            modifiers.get(modifier).subValues.get(subValue).value = val;
                    },
                    onUpdate: function(twn:FlxTween) {
                        //need to update like this because its inside a map
                        if (modifiers.exists(modifier))
                            modifiers.get(modifier).subValues.get(subValue).value = FlxMath.lerp(startValue, val, easefunc(twn.percent));
                    }
                });
                if (Conductor.songPosition > ModchartUtil.getTimeFromBeat(beat)) //skip to where it should be i guess??
                {
                    @:privateAccess
                    tween._secondsSinceStart += ((Conductor.songPosition - ModchartUtil.getTimeFromBeat(beat)) * 0.001);
                    @:privateAccess
                    tween.update(0);
                }
                if (renderer.editorPaused)
                    tween.active = false;
            }

        }
    }
}
