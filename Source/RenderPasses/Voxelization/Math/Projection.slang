#pragma once
#include "../HostDeviceShared.slang"

BEGIN_NAMESPACE_FALCOR

#define PI 3.14159265359

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

END_NAMESPACE_FALCOR
