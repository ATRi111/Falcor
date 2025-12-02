#pragma once
#include "Utils/HostDeviceShared.slangh"

#if defined(HOST_CODE)
#include <vector>
using namespace Falcor::math;
#endif

#if !defined(HOST_CODE)
    #define MUTATING [mutating]
#else
    #define MUTATING
#endif

inline float2x2 make2x2(float a00, float a01, float a10, float a11)
{
#if defined(HOST_CODE)
    float2x2 ret;
    ret[0][0] = a00;
    ret[0][1] = a01;
    ret[1][0] = a10;
    ret[1][1] = a11;
    return ret;
#else
    return float2x2(a00, a01, a10, a11);
#endif
}

inline float3x3 zeros()
{
#if defined(HOST_CODE)
    return float3x3::zeros();
#else
    return float3x3(0, 0, 0, 0, 0, 0, 0, 0, 0);
#endif
}

inline float2x2 mulT(float2 a, float2 b)
{
    return make2x2(a.x * b.x, a.x * b.y, a.y * b.x, a.y * b.y);
}
