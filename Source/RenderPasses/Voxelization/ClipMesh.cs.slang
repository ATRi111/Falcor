#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/VoxelizationUtility.slang"
#include "Scene/VertexAttrib.slangh"
import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;

RWStructuredBuffer<Polygon> polygonBuffer;
RWStructuredBuffer<PolygonRange> polygonRangeBuffer;
RWStructuredBuffer<uint> polygonCountBuffer;
RWStructuredBuffer<uint> vBuffer;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
};

cbuffer CB
{
    uint groupVoxelCount;
    uint gBufferOffset;
}

cbuffer MeshData
{
    uint vertexCount;
    uint triangleCount;
    uint vbOffset;
    uint ibOffset;
    bool use16BitIndices;
    uint materialID;
};

int getOffset(int3 cellInt)
{
    int index = CellToIndex(cellInt, voxelCount);
    return vBuffer[index];
}

void clipTriangle(Triangle tri)
{
    AABBInt aabb = tri.calcAABBInt();
    for (int i = 0; i < aabb.count(); i++)
    {
        int3 cellInt = aabb.indexToCell(i);
        float3 minPoint = float3(cellInt);
        Polygon polygon = boxClipTriangle(minPoint, minPoint + 1.f, tri); // 多边形与三角形顶点顺序一致

        polygon.normal = float3(tri.TBN[0][2], tri.TBN[1][2], tri.TBN[2][2]); // 几何法线
        if (polygon.count >= 3)
        {
            int offset = getOffset(cellInt);
            if (offset < gBufferOffset || offset >= gBufferOffset + groupVoxelCount)
                continue;
            uint writeIndex;
            InterlockedAdd(polygonCountBuffer[offset], 1u, writeIndex);
            writeIndex += polygonRangeBuffer[offset].localHead;
            polygonBuffer[writeIndex] = polygon;
        }
    }
}

void voxelizeTriangle(uint triangleId)
{
    if (triangleId >= triangleCount)
        return;
    
    Triangle triangle = {};
    uint3 vtxIndices = gScene.getLocalIndices(ibOffset, triangleId, use16BitIndices);
    if (any(vtxIndices >= vertexCount))
        return;
    vtxIndices += vbOffset;
    StaticVertexData[3] vertices = { gScene.getVertex(vtxIndices.x), gScene.getVertex(vtxIndices.y), gScene.getVertex(vtxIndices.z) };
    // 世界坐标处理成网格坐标
    for (int i = 0; i < 3; i++)
    {
        triangle.vertices[i] = (vertices[i].position - gridMin) / voxelSize;
        triangle.uvs[i] = vertices[i].texCrd;
    }
    triangle.buildTBN();
    clipTriangle(triangle);
}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    voxelizeTriangle(tid.x);
}
