#include "Math/LebedevQuadrature.slang"
#include "Math/Polygon.slang"
#include "Math/Triangle.slang"
#include "Voxel/VoxelGrid.slang"
#include "VoxelizationShared.slang"
import Utils.Sampling.UniformSampleGenerator;
import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;
import Rendering.Materials.TexLODHelpers;
import Scene.Material.BasicMaterialData;

StructuredBuffer<Polygon> polygonBuffer; // 局部缓冲区
StructuredBuffer<PolygonRange> polygonRangeBuffer;
RWStructuredBuffer<VoxelData> gBuffer;
RWStructuredBuffer<uint> gBufferLock;
RWStructuredBuffer<uint> blockMap; // 逻辑上是Texture2D<uint4>
SamplerState sampler;

#define DISABLE_LOCK 1

cbuffer CB
{
    uint gBufferOffset;
    uint groupVoxelCount;
    uint sampleFrequency;
    uint2 blockCount;
}

void Estimate(
    Ellipsoid e,
    PolygonRange range,
    inout SphericalFunc polygonFunc,
    inout SphericalFunc primitiveFunc,
    inout SphericalFunc totalFunc
)
{
    float3 cellMin = range.cellInt;
    float3 cellCenter = cellMin + 0.5f;
    for (uint i = 0; i < LEBEDEV_DIRECTION_COUNT; i += 2)
    {
        LebedevSample sample = LebedevSamples[i];
        float3 direction = sample.direction;
        Basis2 basis = orthonormal_basis(direction);
        uint hitCount = 0;
        for (uint j = 0; j < sampleFrequency; j++)
        {
            SamplingRay ray = rayToVoxel(Hammersley2D(j, sampleFrequency), direction, basis, cellCenter);
            float3 from = ray.origin;
            float3 to = from + 2 * ray.direction;
            float2 inOut = clip(cellMin, cellMin + 1.f, from, to);
            if (inOut.x >= 0) // 命中体素
            {
                float3 v = to - from;
                to = from + inOut.y * v - cellMin;
                from = from + inOut.x * v - cellMin;
                inOut = e.clip(from, to);
                if (inOut.x >= 0) // 命中图元
                    hitCount++;
            }
        }

        float weight = 8 * PI * sample.weight; // 正反方向的采样结果总是相同,只统计其中一个方向,则权重翻倍
        float primitiveProjArea = PROJECT_CIRCLE_AREA * hitCount / (float)sampleFrequency;
        primitiveFunc.accumulate(weight * primitiveProjArea, direction);

        float totalProjArea = range.calcTotalProjArea(polygonBuffer, direction);
        // TODO:计算可见投影面积
        polygonFunc.accumulate(weight * totalProjArea, direction);
        totalFunc.accumulate(weight * totalProjArea, direction);
    }
}

float4 sampleTextureArea(TextureHandle handle, float2 uv, float uvArea, float4 uniformValue)
{
    MaterialSystem ms = gScene.materials;
    TextureInfo info = ms.getTextureInfo(handle);
    float pixelArea = uvArea * info.width * info.height;
    float lodLevel = 0.5f * log2(max(pixelArea, 1));
    ITextureSampler lod = ExplicitLodTextureSampler(lodLevel);
    return ms.sampleTexture(handle, sampler, uv, uniformValue, lod);
}

void sampleTexture(Polygon polygon, int3 cellInt, int offset, inout ABSDF ABSDF)
{
    TriangleRef triRef = polygon.triRef;
    MaterialSystem ms = gScene.materials;
    MaterialType type = ms.getMaterialType(triRef.materialID);

    float2[MAX_VERTEX_COUNT] uvs;
    uint3 vtxIndices = gScene.getIndices(triRef.meshID, triRef.triangleID);
    Triangle tri = {};
    StaticVertexData[3] vertices = { gScene.getVertex(vtxIndices.x), gScene.getVertex(vtxIndices.y), gScene.getVertex(vtxIndices.z) };
    for (int i = 0; i < 3; i++)
    {
        tri.uvs[i] = vertices[i].texCrd;
    }
    tri.buildTBN();
    for (uint i = 0; i < polygon.count; i++)
    {
        float3 bary = calcBarycentricCoordinates(vertices[0].position, vertices[1].position, vertices[2].position, polygon.vertices[i]);
        float2 uv = vertices[0].texCrd * bary.x + vertices[1].texCrd * bary.y + vertices[2].texCrd * bary.z;
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
    BasicMaterialData data = ms.getBasicMaterialData(triRef.materialID);

    float3 baseColor = sampleTextureArea(data.texBaseColor, center, area, data.baseColor).rgb;
    float4 spec = sampleTextureArea(data.texSpecular, center, area, data.specular);
    float3 normal = sampleTextureArea(data.texNormalMap, center, area, float4(0, 0, 1, 0)).rgb;
    normal = normal * 2.f - 1.f;
    normal = calcShadingNormal(tri.TBN, normal);

    ABSDFInput input = { baseColor, spec, normal, polygon.calcArea() };

#if !DISABLE_LOCK
    uint old;
    do
    {
        InterlockedCompareExchange(gBufferLock[offset], 0u, 1u, old);
    } while (old != 0u);
#endif
    ABSDF.accumulate(input);
#if !DISABLE_LOCK
    uint dummy;
    InterlockedExchange(gBufferLock[offset], 0u, dummy);
#endif
}

void updateBlockMap(int3 cellInt)
{
    int3 blockInt = cellInt / BLOCK_TO_VOXEL;
    int component = blockInt.z / 32;
    uint value = 1 << blockInt.z % 32;
    uint index = blockInt.x + blockInt.y * blockCount.x;
    index = 4 * index + component; // 4个分量一组
    InterlockedOr(blockMap[index], value);
}

void calc(uint offset)
{
    if (offset >= groupVoxelCount)
        return;

    uint index = offset + gBufferOffset;
    VoxelData data = gBuffer[index];
    PolygonRange range = polygonRangeBuffer[index];
    for (uint i = range.localHead; i < range.localHead + range.count; i++)
    {
        Polygon polygon = polygonBuffer[i];
        sampleTexture(polygon, range.cellInt, index, data.ABSDF);
    }
    
    if (!data.IsSolid())
        return;

    data.ellipsoid.fit(polygonBuffer, range);
    data.ABSDF.normalizeSelf();

    SphericalFunc polyF = data.polygonsProjAreaFunc;
    SphericalFunc primF = data.primitiveProjAreaFunc;
    SphericalFunc totalF = data.totalProjAreaFunc;

    Estimate(data.ellipsoid, range, polyF, primF, totalF);

    data.polygonsProjAreaFunc = polyF;
    data.primitiveProjAreaFunc = primF;
    data.totalProjAreaFunc = totalF;

    gBuffer[index] = data;

    updateBlockMap(range.cellInt);
}

[numthreads(256, 1, 1)]
void main(uint3 offset: SV_DispatchThreadID)
{
    calc(offset.x);
}
