#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/VoxelizationUtility.slang"
#include "Scene/VertexAttrib.slangh"

import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;
import Rendering.Materials.TexLODHelpers;
import Scene.Material.BasicMaterialData;

#define DISABLE_LOCK 1

RWStructuredBuffer<int> vBuffer;
RWStructuredBuffer<VoxelData> gBuffer;
RWStructuredBuffer<uint> polygonCountBuffer;
RWStructuredBuffer<uint> gBufferLock;
RWStructuredBuffer<uint> solidVoxelCount; // 单元素缓冲区
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

    int v = vBuffer[index];
    if (v >= 0)
        return v;

    int original;
    InterlockedCompareExchange(vBuffer[index], -1, -2, original); //-2表示分配中
    if (original == -1)
    {
        uint offset;
        InterlockedAdd(solidVoxelCount[0], 1u, offset);

        vBuffer[index] = (int)offset;
        return (int)offset;
    }

    while ((v = vBuffer[index]) == -2)
    {
    }
    return v;
}

float4 sampleTextureArea(TextureHandle handle, float2 uv, float uvArea, float4 uniformValue)
{
    MaterialSystem ms = gScene.materials;
    TextureInfo info = ms.getTextureInfo(handle);
    float pixelArea = uvArea * info.width * info.height;
    float lodLevel = 0.5f * log2(max(pixelArea, 1));
    ITextureSampler lod = ExplicitLodTextureSampler(lodLevel);
    return ms.sampleTexture(handle, s, uv, uniformValue, lod);
}

void sampleArea(Triangle tri, Polygon polygon, int3 cellInt)
{
    MaterialSystem ms = gScene.materials;
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
    BasicMaterialData data = ms.getBasicMaterialData(materialID);

    float3 baseColor = sampleTextureArea(data.texBaseColor, center, area, data.baseColor).rgb;
    float4 spec = sampleTextureArea(data.texSpecular, center, area, data.specular);
    float3 normal = sampleTextureArea(data.texNormalMap, center, area, float4(0, 0, 1, 0)).rgb;
    normal = normal * 2.f - 1.f;
    normal = calcShadingNormal(tri.TBN, normal);

    ABSDFInput input = { baseColor, spec, normal, polygon.calcArea() };

    int offset = tryGetOffset(cellInt);
#if !DISABLE_LOCK
    uint old;
    do
    {
        InterlockedCompareExchange(gBufferLock[offset], 0u, 1u, old);
    } while (old != 0u);
#endif
    gBuffer[offset].ABSDF.accumulate(input);
    InterlockedAdd(polygonCountBuffer[offset], 1);
#if !DISABLE_LOCK
    uint dummy;
    InterlockedExchange(gBufferLock[offset], 0u, dummy);
#endif
}

void sampleTriangle(Triangle tri)
{
    AABBInt aabb = tri.calcAABBInt();
    for (int i = 0; i < aabb.count(); i++)
    {
        int3 cellInt = aabb.indexToCell(i);
        float3 minPoint = float3(cellInt);
        Polygon polygon = boxClipTriangle(minPoint, minPoint + 1.f, tri); // 多边形与三角形顶点顺序一致

        if (polygon.count >= 3)
            sampleArea(tri, polygon, cellInt);
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
    sampleTriangle(triangle);
}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    voxelizeTriangle(tid.x);
}
