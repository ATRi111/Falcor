#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/Polygon.slang"
#include "Math/Ellipsoid.slang"

cbuffer CB
{
    int solidVoxelCount;
}

RWStructuredBuffer<VoxelData> gBuffer;
StructuredBuffer<PolygonInVoxel> polygonBuffer;

void analyze(uint offset)
{
    if (offset >= solidVoxelCount || gBuffer[offset].ABSDF.area <= 0)
        return;
    
    gBuffer[offset].ellipsoid.fit(polygonBuffer[offset]);
    gBuffer[offset].ABSDF.normalizeSelf();
}

[numthreads(256, 1, 1)]
void main(uint3 offset: SV_DispatchThreadID)
{
    analyze(offset.x);
}
