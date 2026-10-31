package modcharting;

#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
#end
import backend.ClientPrefs;
import backend.Conductor;
import states.PlayState;
import modcharting.Modifier;
import modcharting.PlayfieldRenderer;
import modcharting.NoteMovement;
import modcharting.ModchartUtil;
import scripting.lua.FunkinLua;

using StringTools;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// Lua 绑定：注册进 FunkinLua 的 implement 体系（每个脚本独立注册，与引擎其它函数组一致）。
//
// 门禁语义：函数永远注册（mod 脚本调用不报错），但 modchartsEnabled 关闭时全部空转
//（首次调用 trace 一次提示）。开启后首次调用惰性创建渲染器。
// 相比上游增强的函数：getMod / getSubMod / resetMods / modchartActive。

class ModchartFuncs
{
    static var _warnedDisabled:Bool = false;

    // 总开关：关闭时空转并提示一次
    public static function enabled():Bool
    {
        if (ClientPrefs.data.modchartsEnabled)
            return true;
        if (!_warnedDisabled)
        {
            _warnedDisabled = true;
            trace('[Modchart] 脚本调用了模表函数，但「编程 → 音符模表」开关未开启，已忽略');
        }
        return false;
    }

    // 惰性获取渲染器：首次调用时创建（此时谱面可能还没到判定线生成阶段，基准位稍后由 startCountdown 补）
    public static function renderer():PlayfieldRenderer
    {
        var ps = PlayState.instance;
        if (ps == null)
            return null;
        if (ps.playfieldRenderer == null)
            ps.initModchartRenderer();
        return ps.playfieldRenderer;
    }

    public static function implement(funk:FunkinLua)
    {
        #if LUA_ALLOWED
        var lua:State = funk.lua;
        Lua_helper.add_callback(lua, 'startMod', function(name:String, modClass:String, type:String = '', pf:Int = -1) {
            if (!enabled())
                return;
            var r = renderer(); if (r == null) return;
            startMod(name, modClass, type, pf);
            r.modifierTable.reconstructTable(); //needs to be reconstructed for lua modcharts
        });
        Lua_helper.add_callback(lua, 'setMod', function(name:String, value:Float) {
            if (!enabled()) return;
            setMod(name, value);
        });
        Lua_helper.add_callback(lua, 'setSubMod', function(name:String, subValName:String, value:Float) {
            if (!enabled()) return;
            setSubMod(name, subValName, value);
        });
        Lua_helper.add_callback(lua, 'getMod', function(name:String):Null<Float> {
            if (!enabled()) return null;
            return getMod(name);
        });
        Lua_helper.add_callback(lua, 'getSubMod', function(name:String, subValName:String):Null<Float> {
            if (!enabled()) return null;
            return getSubMod(name, subValName);
        });
        Lua_helper.add_callback(lua, 'setModTargetLane', function(name:String, value:Int) {
            if (!enabled()) return;
            setModTargetLane(name, value);
        });
        Lua_helper.add_callback(lua, 'setModPlayfield', function(name:String, value:Int) {
            if (!enabled()) return;
            setModPlayfield(name, value);
        });
        Lua_helper.add_callback(lua, 'addPlayfield', function(?x:Float = 0, ?y:Float = 0, ?z:Float = 0) {
            if (!enabled()) return;
            var r = renderer(); if (r == null) return;
            r.addNewPlayfield(x, y, z);
        });
        Lua_helper.add_callback(lua, 'removePlayfield', function(idx:Int) {
            if (!enabled()) return;
            var r = renderer(); if (r == null) return;
            if (idx >= 0 && idx < r.playfields.length)
                r.playfields.remove(r.playfields[idx]);
        });
        Lua_helper.add_callback(lua, 'tweenModifier', function(modifier:String, val:Float, time:Float, ease:String) {
            if (!enabled()) return;
            var r = renderer(); if (r == null) return;
            r.modifierTable.tweenModifier(modifier, val, time, ease, Modifier.beat);
        });
        Lua_helper.add_callback(lua, 'tweenModifierSubValue', function(modifier:String, subValue:String, val:Float, time:Float, ease:String) {
            if (!enabled()) return;
            var r = renderer(); if (r == null) return;
            r.modifierTable.tweenModifierSubValue(modifier, subValue, val, time, ease, Modifier.beat);
        });
        Lua_helper.add_callback(lua, 'setModEaseFunc', function(name:String, ease:String) {
            if (!enabled()) return;
            setModEaseFunc(name, ease);
        });
        Lua_helper.add_callback(lua, 'resetMods', function() {
            if (!enabled()) return;
            var r = renderer(); if (r == null) return;
            r.modifierTable.resetMods();
        });
        Lua_helper.add_callback(lua, 'modchartActive', function():Bool {
            var ps = PlayState.instance;
            return ps != null && ps.playfieldRenderer != null;
        });
        Lua_helper.add_callback(lua, 'set', function(beat:Float, argsAsString:String) {
            if (!enabled()) return;
            set(beat, argsAsString);
        });
        Lua_helper.add_callback(lua, 'ease', function(beat:Float, time:Float, easeStr:String, argsAsString:String) {
            if (!enabled()) return;
            ease(beat, time, easeStr, argsAsString);
        });
        #end
    }

    public static function startMod(name:String, modClass:String, type:String = '', pf:Int = -1)
    {
        var ps = PlayState.instance;
        if (ps == null || ps.playfieldRenderer == null)
            return;
        var r = ps.playfieldRenderer;
        if (r.modchart.scriptListen)
        {
            r.modchart.data.modifiers.push([name, modClass, type, pf]);
        }

        if (r.modchart.customModifiers.exists(modClass))
        {
            var modifier = new Modifier(name, getModTypeFromString(type), pf);
            if (r.modchart.customModifiers.get(modClass).interp != null)
                r.modchart.customModifiers.get(modClass).interp.variables.set('instance', ps);
            r.modchart.customModifiers.get(modClass).initMod(modifier); //need to do it this way instead because using current value in the modifier script didnt work
            r.modifierTable.add(modifier);
            return;
        }

        var mod = Type.resolveClass('modcharting.' + modClass);
        if (mod == null) {mod = Type.resolveClass('modcharting.' + modClass + "Modifier");} //dont need to add "Modifier" to the end of every mod

        if (mod != null)
        {
            var modType = getModTypeFromString(type);
            var modifier = Type.createInstance(mod, [name, modType, pf]);
            r.modifierTable.add(modifier);
        }
        else
        {
            trace('[Modchart] startMod 找不到修饰器类: $modClass');
        }
    }
    public static function getModTypeFromString(type:String)
    {
        var modType = ModifierType.ALL;
        switch (type.toLowerCase())
        {
            case 'player':
                modType = ModifierType.PLAYERONLY;
            case 'opponent':
                modType = ModifierType.OPPONENTONLY;
            case 'lane' | 'lanespecific':
                modType = ModifierType.LANESPECIFIC;
        }
        return modType;
    }

    public static function setMod(name:String, value:Float)
    {
        var r = renderer(); if (r == null) return;
        if (r.modchart.scriptListen)
        {
            r.modchart.data.events.push(["set", [0, value + "," + name]]);
        }
        if (r.modifierTable.modifiers.exists(name))
            r.modifierTable.modifiers.get(name).currentValue = value;
    }
    public static function setSubMod(name:String, subValName:String, value:Float)
    {
        var r = renderer(); if (r == null) return;
        if (r.modchart.scriptListen)
        {
            r.modchart.data.events.push(["set", [0, value + "," + name + ":" + subValName]]);
        }
        if (r.modifierTable.modifiers.exists(name) && r.modifierTable.modifiers.get(name).subValues.exists(subValName))
            r.modifierTable.modifiers.get(name).subValues.get(subValName).value = value;
    }
    public static function getMod(name:String):Null<Float>
    {
        var r = renderer(); if (r == null) return null;
        if (r.modifierTable.modifiers.exists(name))
            return r.modifierTable.modifiers.get(name).currentValue;
        return null;
    }
    public static function getSubMod(name:String, subValName:String):Null<Float>
    {
        var r = renderer(); if (r == null) return null;
        if (r.modifierTable.modifiers.exists(name) && r.modifierTable.modifiers.get(name).subValues.exists(subValName))
            return r.modifierTable.modifiers.get(name).subValues.get(subValName).value;
        return null;
    }
    public static function setModTargetLane(name:String, value:Int)
    {
        var r = renderer(); if (r == null) return;
        if (r.modifierTable.modifiers.exists(name))
            r.modifierTable.modifiers.get(name).targetLane = value;
    }
    public static function setModPlayfield(name:String, value:Int)
    {
        var r = renderer(); if (r == null) return;
        if (r.modifierTable.modifiers.exists(name))
            r.modifierTable.modifiers.get(name).playfield = value;
    }

    public static function setModEaseFunc(name:String, ease:String)
    {
        var r = renderer(); if (r == null) return;
        if (r.modifierTable.modifiers.exists(name))
        {
            var mod = r.modifierTable.modifiers.get(name);
            if (Std.isOfType(mod, EaseCurveModifier))
            {
                var temp:Dynamic = mod;
                var castedMod:EaseCurveModifier = temp;
                castedMod.setEase(ease);
            }
        }
    }
    public static function set(beat:Float, argsAsString:String)
    {
        var r = renderer(); if (r == null) return;
        if (r.modchart.scriptListen)
        {
            r.modchart.data.events.push(["set", [beat, argsAsString]]);
        }
        var args = argsAsString.trim().replace(' ', '').split(',');

        r.eventManager.addEvent(beat, function(arguments:Array<String>) {
            for (i in 0...Math.floor(arguments.length / 2))
            {
                var name:String = Std.string(arguments[1 + (i * 2)]);
                var value:Float = Std.parseFloat(arguments[0 + (i * 2)]);
                if (Math.isNaN(value))
                    value = 0;
                if (r.modifierTable.modifiers.exists(name))
                {
                    r.modifierTable.modifiers.get(name).currentValue = value;
                }
                else
                {
                    var subModCheck = name.split(':');
                    if (subModCheck.length > 1)
                    {
                        var modName = subModCheck[0];
                        var subModName = subModCheck[1];
                        if (r.modifierTable.modifiers.exists(modName)
                            && r.modifierTable.modifiers.get(modName).subValues.exists(subModName))
                            r.modifierTable.modifiers.get(modName).subValues.get(subModName).value = value;
                    }
                }
            }
        }, args);
    }
    public static function ease(beat:Float, time:Float, ease:String, argsAsString:String) : Void
    {
        var r = renderer(); if (r == null) return;
        if (r.modchart.scriptListen)
        {
            r.modchart.data.events.push(["ease", [beat, time, ease, argsAsString]]);
        }

        if (Math.isNaN(time))
            time = 1;

        var args = argsAsString.trim().replace(' ', '').split(',');

        var func = function(arguments:Array<String>) {
            for (i in 0...Math.floor(arguments.length / 2))
            {
                var name:String = Std.string(arguments[1 + (i * 2)]);
                var value:Float = Std.parseFloat(arguments[0 + (i * 2)]);
                if (Math.isNaN(value))
                    value = 0;
                var subModCheck = name.split(':');
                if (subModCheck.length > 1)
                {
                    var modName = subModCheck[0];
                    var subModName = subModCheck[1];
                    r.modifierTable.tweenModifierSubValue(modName, subModName, value, time * Conductor.crochet * 0.001, ease, beat);
                }
                else
                    r.modifierTable.tweenModifier(name, value, time * Conductor.crochet * 0.001, ease, beat);
            }
        };
        r.eventManager.addEvent(beat, func, args);
    }
}
