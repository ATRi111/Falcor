#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define CUBE_VERTEX_COUNT 8

inline float cross2(float2 a, float2 b)
{
    return a.x * b.y - a.y * b.x;
}

#if !defined(HOST_CODE)


// 计算凸包
inline int convexHull2D(float2 points[CUBE_VERTEX_COUNT], int inputCount, out float2 hull[CUBE_VERTEX_COUNT])
{
    for (int i = 1; i < inputCount; ++i)
    {
        float2 key = points[i];
        int j = i - 1;
        while (j >= 0 && ((points[j].x > key.x) || (points[j].x == key.x && points[j].y > key.y)))
        {
            points[j + 1] = points[j];
            --j;
        }
        points[j + 1] = key;
    }

    // Andrew 单调链
    float2 H[2 * CUBE_VERTEX_COUNT];
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

#endif

END_NAMESPACE_FALCOR
