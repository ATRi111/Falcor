#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/Polygon.slang"

//import Utils.Math.MathHelpers;

RWStructuredBuffer<VoxelData> gBuffer;
StructuredBuffer<PolygonInVoxel> polygonBuffer;
RWTexture3D<uint> vBuffer;

cbuffer CB
{
    uint3 voxelCount;
}

void calc(uint3 vid)
{
    if (any(vid >= voxelCount))
        return;

    uint offset = vBuffer[vid];
    PolygonInVoxel p = polygonBuffer[offset];
}

[numthreads(8, 8, 8)]
void main(uint3 vid: SV_DispatchThreadID)
{
    calc(vid);
}
