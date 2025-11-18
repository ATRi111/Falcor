#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define PI 3.14159265358
#define MAX_VERTEX_COUNT 8

#if !defined(HOST_CODE)

struct Basis2
{
    float3 u;
    float3 w;
};
inline Basis2 orthonormal_basis(float3 v)
{
    Basis2 ret;
    float3 axis = (abs(v.z) < 0.999) ? float3(0, 0, 1) : float3(1, 0, 0);
    ret.u = normalize(cross(axis, v));
    ret.w = normalize(cross(v, ret.u));
    return ret;
}
inline float2x2 mulT(float2 a, float2 b)
{
    return float2x2(a.x * b.x, a.x * b.y, a.y * b.x, a.y * b.y);
}
inline float cross2(float2 a, float2 b)
{
    return a.x * b.y - a.y * b.x;
}

// 计算凸包
inline int convexHull2D(float2 points[MAX_VERTEX_COUNT], int inputCount, out float2 hull[MAX_VERTEX_COUNT])
{
    inputCount = clamp(inputCount, 0, MAX_VERTEX_COUNT);

    // 按 (x, y) 进行插入排序 —— 只对前 n 个元素排序
    for (int i = 1; i < inputCount; ++i)
    {
        float2 key = points[i];
        int j = i - 1;
        // 注意括号：确保 j >= 0 对两个比较分支都生效，避免越界
        while (j >= 0 && ((points[j].x > key.x) || (points[j].x == key.x && points[j].y > key.y)))
        {
            points[j + 1] = points[j];
            --j;
        }
        points[j + 1] = key;
    }

    // Andrew 单调链
    float2 H[2 * MAX_VERTEX_COUNT];
    int count = 0;

    // 下链
    for (int i = 0; i < inputCount; ++i)
    {
        float2 pi = points[i];
        while (count >= 2)
        {
            float2 a = H[count - 1] - H[count - 2];
            float2 b = pi - H[count - 1];
            if (cross2(a, b) > 0) break;
            --count;
        }
        H[count++] = pi;
    }

    // 上链
    int t = count + 1;
    for (int i = inputCount - 2; i >= 0; --i)
    {
        float2 pi = points[i];
        while (count >= t)
        {
            float2 a = H[count - 1] - H[count - 2];
            float2 b = pi - H[count - 1];
            if (cross2(a, b) > 0) break;
            --count;
        }
        H[count++] = pi;
    }

    // 去掉重复起点
    count = max(count - 1, 0);

    for (int i = 0; i < count; ++i)
        hull[i] = H[i];

    return count;
}

struct Circle
{
    float r; // 默认圆心位于原点

    float area() { return PI * r * r; }

    bool contains(float2 p, float epsilon) { return dot(p, p) <= (r + epsilon) * (r + epsilon); }

    float sectorArea(float2 a, float2 b)
    {
        float ang = atan2(cross2(a, b), dot(a, b));
        return 0.5f * r * r * ang; // 有向面积
    }

    float2 clip(float2 from, float2 to)
    {
        float2 v = to - from;
        float a = dot(v, v);
        float b = 2.0f * dot(from, v);
        float c = dot(from, from) - r * r;
        float d = b * b - 4 * a * c;
        if (d < 0)
            return float2(-1, -1);
        float uIn = 0, uOut = 1;
        float s = sqrt(d);
        uIn = max(uIn, (-b - s) / 2 / a);
        uOut = min(uOut, (-b + s) / 2 / a);
        if (uIn > uOut)
            return float2(-1, -1);
        return float2(uIn, uOut);
    }

    // 圆心与两点连成的三角形和圆相交部分的面积
    float edgeIntersectionArea(float2 from, float2 to)
    {
        float2 v = to - from;
        if (dot(v, v) < 1e-6f)
            return 0.0f;
        float2 inOut = clip(from, to);

        // 无交点
        if (inOut.x < 0.0f && inOut.y < 0.0f)
        {
            if (contains(from, 0) && contains(to, 0)) // 两点均在圆内
                return 0.5f * cross2(from, to);
            return sectorArea(from, to); // 两点均在圆外
        }

        float2 enter = from + v * inOut.x;
        float2 exit = from + v * inOut.y;

        float area = 0.0f;

        if (inOut.x > 0.0f)
            area += sectorArea(from, enter);

        area += 0.5f * cross2(enter, exit);

        if (inOut.y < 1.0f)
            area += sectorArea(exit, to);

        return area; // 有向面积
    }

    float intersectArea(float2 points[MAX_VERTEX_COUNT])
    {
        float2 hull[MAX_VERTEX_COUNT];
        int count = convexHull2D(points, 8, hull);
        if (count < 3)
            return 0.0f;

        float acc = 0.0f;
        for (int i = 0; i < count; ++i)
        {
            float2 from = hull[i];
            float2 to = hull[(i + 1) % count];
            acc += edgeIntersectionArea(from, to);
        }

        return abs(acc);
    }
};

#endif

END_NAMESPACE_FALCOR
