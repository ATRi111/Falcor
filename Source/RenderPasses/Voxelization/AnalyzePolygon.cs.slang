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
    if (offset >= solidVoxelCount)
        return;
    float3[MAX_FIT_POINT_COUNT] points;
    int count = 0;
    PolygonInVoxel polygons = polygonBuffer[offset];
    for (uint i = 0; i < polygons.count; i++)
    {
        Polygon polygon = polygons.polygons[i];
        for (uint j = 0; j < polygon.count; j++)
        {
            points[count] = polygon.vertices[j];    //不检查容量
        }
    }
    gBuffer[offset].ellipsoid.fit(points, count, polygonBuffer[offset].cellMin);
    gBuffer[offset].ABSDF.normalizeSelf();
}

[numthreads(256, 1, 1)]
void main(uint3 offset: SV_DispatchThreadID)
{
    analyze(offset.x);
}
