package modcharting;

import flixel.math.FlxAngle;
import openfl.geom.Vector3D;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 Meteoric Engine。
// 移植时修复上游两个已知问题：
//  1) transformVector 原为空壳（原样返回输入向量，未做任何旋转）——此处实现 q*v*q⁻¹；
//  2) conjugate 原未取反 x 分量。

typedef Quaternion =
{
    var x:Float;
    var y:Float;
    var z:Float;
    var w:Float;
};

class SimpleQuaternion
{
    public static function fromEuler(roll:Float, pitch:Float, yaw:Float) : Quaternion
    {
        //https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles
        var cr = Math.cos(roll * FlxAngle.TO_RAD);
        var sr = Math.sin(roll * FlxAngle.TO_RAD);
        var cp = Math.cos(pitch * FlxAngle.TO_RAD);
        var sp = Math.sin(pitch * FlxAngle.TO_RAD);
        var cy = Math.cos(yaw * FlxAngle.TO_RAD);
        var sy = Math.sin(yaw * FlxAngle.TO_RAD);

        var q:Quaternion = {x: 0, y: 0, z: 0, w: 0};
        q.w = cr * cp * cy + sr * sp * sy;
        q.x = sr * cp * cy - cr * sp * sy;
        q.y = cr * sp * cy + sr * cp * sy;
        q.z = cr * cp * sy - sr * sp * cy;
        return q;
    }

    public static function transformVector(v:Vector3D, q:Quaternion) : Vector3D
    {
        // v' = v + 2*w*(q_v × v) + 2*(q_v × (q_v × v))，q_v 为四元数向量部分（单位化后）
        var qx:Float = q.x, qy:Float = q.y, qz:Float = q.z;
        var len:Float = Math.sqrt(q.w * q.w + qx * qx + qy * qy + qz * qz);
        if (len <= 0)
            return v.clone();
        qx /= len; qy /= len; qz /= len;

        var out:Vector3D = v.clone();
        // u = q_v × v
        var ux:Float = qy * v.z - qz * v.y;
        var uy:Float = qz * v.x - qx * v.z;
        var uz:Float = qx * v.y - qy * v.x;
        // uu = q_v × u
        var uux:Float = qy * uz - qz * uy;
        var uuy:Float = qz * ux - qx * uz;
        var uuz:Float = qx * uy - qy * ux;

        out.x += 2 * q.w * ux + 2 * uux;
        out.y += 2 * q.w * uy + 2 * uuy;
        out.z += 2 * q.w * uz + 2 * uuz;
        return out;
    }

    public static function normalize(q:Quaternion) : Quaternion
    {
        var length = Math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
        if (length <= 0)
            return q;
        q.w = q.w / length;
        q.x = q.x / length;
        q.y = q.y / length;
        q.z = q.z / length;

        return q;
    }
    public static function conjugate(q:Quaternion) : Quaternion
    {
        q.x = -q.x; // 上游漏取反 x，已修正
        q.y = -q.y;
        q.z = -q.z;
        q.w = -q.w;
        return q;
    }
    public static function multiply(q1:Quaternion, q2:Quaternion) : Quaternion
    {
        var x = q1.x * q2.x - q1.y * q2.y - q1.z * q2.z - q1.w * q2.w;
        var y = q1.x * q2.y + q1.y * q2.x + q1.z * q2.w - q1.w * q2.z;
        var z = q1.x * q2.z - q1.y * q2.w + q1.z * q2.x + q1.w * q2.y;
        var w = q1.x * q2.w + q1.y * q2.z - q1.z * q2.y + q1.w * q2.x;

        q1.x = x;
        q1.y = y;
        q1.z = z;
        q1.w = w;

        return q1;
    }
}
