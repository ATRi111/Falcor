#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/Triangle.slang"
#include "Math/Polygon.slang"
#include "Math/VoxelizationUtility.slang"
#include "Scene/VertexAttrib.slangh"

import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;
import Rendering.Materials.TexLODHelpers;
import Scene.Material.BasicMaterialData;

ParameterBlock<Scene> scene;
RWStructuredBuffer<int> vBuffer;
RWStructuredBuffer<VoxelData> gBuffer;
RWStructuredBuffer<PolygonInVoxel> polygonBuffer;
RWStructuredBuffer<uint> gBufferLock;
RWStructuredBuffer<uint> solidVoxelCount;   //2个元素的缓冲区，第二个元素作锁变量使用
SamplerState s;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
};

cbuffer MeshData
{
    uint vertexCount;
    uint triangleCount;
    uint vbOffset;
    uint ibOffset;
    bool use16BitIndices;
    uint materialID;
};

int tryGetOffset(int3 cellInt)
{
    int index = CellToIndex(cellInt, voxelCount);
    if (vBuffer[index] != -1)
        return vBuffer[index];

#if !DISABLE_LOCK
    uint old = 1;
    while (old != 0)
    {
        InterlockedCompareExchange(solidVoxelCount[1], 1u, 0u, old);
    }
#endif
    if (vBuffer[index] == -1)
    {
        // 分配全局唯一的 offset
        uint offset;
        InterlockedAdd(solidVoxelCount[0], 1u, offset); // offset 为加之前的值

        vBuffer[index] = offset;
        gBuffer[offset].init();
        polygonBuffer[offset].init();
        polygonBuffer[offset].cellMin = float3(cellInt);
    }
#if !DISABLE_LOCK
    uint dummy;
    InterlockedExchange(solidVoxelCount[1], 0u, dummy);
#endif
    return vBuffer[index];
}

void sampleArea(Triangle tri, Polygon polygon, int3 cellInt)
{
    MaterialSystem ms = scene.materials;
    MaterialType type = ms.getMaterialType(materialID);

    float2[MAX_VERTEX_COUNT] uvs;
    for (uint i = 0; i < polygon.count; i++)
    {
        float2 uv = tri.lerpUV(polygon.vertices[i]);
        uvs[i] = uv;
    }
    float area = 0;
    float2 center = 0;
    for (uint i = 0; i < polygon.count; ++i)
    {
        float2 a = uvs[i];
        float2 b = uvs[(i + 1) % polygon.count];
        area += a.x * b.y - a.y * b.x;
        center += uvs[i];
    }
    center /= polygon.count;
    area = 0.5f * abs(area);
    ITextureSampler lod = ExplicitGradientTextureSampler(sqrt(area), sqrt(area));
    BasicMaterialData data = ms.getBasicMaterialData(materialID);

    float3 baseColor = ms.sampleTexture(data.texBaseColor, s, center, data.baseColor, lod).rgb;
    float4 spec = ms.sampleTexture(data.texSpecular, s, center, data.specular, lod); // G - Roughness; B - Metallic
    float3 normal = ms.sampleTexture(data.texNormalMap, s, center, data.specular, lod).rgb;
    normal = calcShadingNormal(tri.TBN, normal);
    
    if (normal.y < 0)
        normal = -normal;
    ABSDFInput input = { baseColor, spec, normal, polygon.calcArea() };

    int offset = tryGetOffset(cellInt);
#if !DISABLE_LOCK
    uint old = 1;
    while (old != 0)
    {
        InterlockedCompareExchange(gBufferLock[offset], 1u, 0u, old);
    }
#endif
    gBuffer[offset].ABSDF.accumulate(input);
    polygonBuffer[offset].add(polygon);
#if !DISABLE_LOCK
    uint dummy;
    InterlockedExchange(gBufferLock[offset], 0u, dummy);
#endif
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
            sampleArea(tri, polygon, cellInt);
    }
}

void voxelizeTriangle(uint triangleId)
{
    if (triangleId >= triangleCount)
        return;
    
    Triangle triangle = {};
    uint3 vtxIndices = scene.getLocalIndices(ibOffset, triangleId, use16BitIndices);
    if (any(vtxIndices >= vertexCount))
        return;
    vtxIndices += vbOffset;
    StaticVertexData[3] vertices = { scene.getVertex(vtxIndices.x), scene.getVertex(vtxIndices.y), scene.getVertex(vtxIndices.z) };
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
