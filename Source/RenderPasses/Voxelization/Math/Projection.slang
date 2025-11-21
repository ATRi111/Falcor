#pragma once
#include "ConvexHull.slang"
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define PI 3.14159265358

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

#if !defined(HOST_CODE)
inline float2x2 mulT(float2 a, float2 b)
{
    return float2x2(a.x * b.x, a.x * b.y, a.y * b.x, a.y * b.y);
}

#endif

END_NAMESPACE_FALCOR
