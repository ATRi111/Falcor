#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

struct Ellipsoid
{
    float16_t3 min;
    float16_t3 max;
    float16_t3 alpha;
};

struct GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
};

END_NAMESPACE_FALCOR
