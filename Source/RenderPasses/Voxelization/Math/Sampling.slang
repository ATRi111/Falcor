#pragma once
#include "Utils/HostDeviceShared.slangh"
#include "Utils/Math/MathHelpers.slang"
#include "Projection.slang"
#include "Voxel/VoxelGrid.slang"

struct Ray
{
    float3 origin;
    float3 direction;
};

// 从体素内表面随机一点，沿随机方向发出
Ray rayFromVoxel(float3 p, float2 omega, float3 cellMin)
{
    float3 direction = sample_sphere(omega);
    Ray ray = { p + cellMin , direction };
    return ray;
}

// 沿给定方向取半个球面，从半球面内的随机点(对投影面积平均)沿反方向发出射线
Ray rayToVoxel(float2 uDisk, float3 direction, Basis2 basis, float3 cellCenter)
{
    float2 p = sample_disk(uDisk);
    float r = DIAG_2;
    float u = p.x * r;
    float w = p.y * r;

    float h = sqrt(max(0.0f, r * r - u * u - w * w));
    float3 point = h * direction + u * basis.u + w * basis.w;
    Ray ray = { point + cellCenter , -direction };
    return ray;
}
