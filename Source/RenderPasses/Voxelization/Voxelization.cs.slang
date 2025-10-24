#include "VoxelizationShared.slang"
#include "Scene/VertexAttrib.slangh"

import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;
import Rendering.Materials.TexLODHelpers;
import Scene.Material.BasicMaterialData;

ParameterBlock<Scene> scene;
RWStructuredBuffer<Ellipsoid> gEllipsoids;
RWTexture3D<float4> gDiffuse;
SamplerState s;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
    uint sampleFrequency;
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

void sampleMaterial(float3 position, float2 texCoord, float2 dduv, uint triangleId)
{
    MaterialSystem ms = scene.materials;
    MaterialType type = ms.getMaterialType(materialID);
    int3 p = int3(position);
#if AUTO_LOD
    ITextureSampler lod = ExplicitGradientTextureSampler(dduv.x, dduv.y);
#else
    ITextureSampler lod = ExplicitLodTextureSampler(0);
#endif

    int index = CellToIndex(p, voxelCount);
    Ellipsoid ellipsoid = gEllipsoids[index];
    if (gDiffuse[p].w == 0)
    {
        ellipsoid.min = frac(position);
        ellipsoid.max = frac(position);
        ellipsoid.alpha = 1;
    }
    else
    {
        ellipsoid.min = min(frac(position), ellipsoid.min);
        ellipsoid.max = max(frac(position), ellipsoid.max);
    }
    gEllipsoids[index] = ellipsoid;

    switch (type)
    {
    case MaterialType::Standard:
        BasicMaterialData data = ms.getBasicMaterialData(materialID);

        const float3 baseColor = ms.sampleTexture(data.texBaseColor, s, texCoord, data.baseColor, lod).rgb;
        const float4 spec = ms.sampleTexture(data.texSpecular, s, texCoord, data.specular, lod); // G - Roughness; B - Metallic

        gDiffuse[p] += float4(baseColor, 1);
        // if (data.getShadingModel() == ShadingModel::MetalRough)
        //{
        //     gDiffuse[p] += float4(lerp(baseColor, float3(0), spec.b), 1);
        //     // d.specular = lerp(float3(F0), baseColor, spec.b);
        //     // d.roughness = spec.g;
        //     // d.metallic = spec.b;
        // }
        // else // ShadingModel::SpecGloss
        //{
        //     gDiffuse[p] += float4(baseColor, 1);
        //     // d.specular = spec.rgb;
        //     // d.roughness = 1 - spec.a;
        //     // d.metallic = getMetallic(d.diffuse, d.specular);
        // }
        break;
    }
}

void sampleTriangle(float3[3] positions, float2[3] texCoords, uint triangleId)
{
    float3 BC = positions[2] - positions[1];
    float3 AC = positions[2] - positions[0];
    float k = length(BC) / length(AC);
    float S = 0.5f * length(cross(BC, AC));
    float sampleCount = sampleFrequency * S;
    float temp = sqrt(2 * sampleCount / k);
    uint aCount = (uint)ceil(temp);
    uint bCount = (uint)ceil(temp * k);

    float deltaA = 1.0f / (aCount + 1);
    float deltaB = 1.0f / (bCount + 1);
    float2 deltaUV = abs(texCoords[0] * deltaA + texCoords[1] * deltaB + texCoords[2] * (-deltaA - deltaB));

    for (float a = deltaA; a < 1; a += deltaA)
    {
        for (float b = deltaB; b < 1; b += deltaB)
        {
            if (a + b > 1)
                break;
            float3 pos = positions[0] * a + positions[1] * b + positions[2] * (1 - a - b);
            float2 texCoord = frac(texCoords[0] * a + texCoords[1] * b + texCoords[2] * (1 - a - b));
            sampleMaterial(pos, texCoord, deltaUV, triangleId);
        }
    }
}

void voxelizeTriangle(uint triangleId)
{
    // 不可删除此if，原因不明
    if (triangleId >= triangleCount)
        return;
    uint3 vtxIndices = scene.getLocalIndices(ibOffset, triangleId, use16BitIndices);
    if (any(vtxIndices >= vertexCount))
        return;
    vtxIndices += vbOffset;
    StaticVertexData[3] vertices = { scene.getVertex(vtxIndices.x), scene.getVertex(vtxIndices.y), scene.getVertex(vtxIndices.z) };
    float3[3] positions = { vertices[0].position, vertices[1].position, vertices[2].position };
    // 世界坐标处理成网格坐标
    for (int i = 0; i < 3; i++)
    {
        positions[i] = (positions[i] - gridMin) / voxelSize;
    }
    float2[3] texCoords = { vertices[0].texCrd, vertices[1].texCrd, vertices[2].texCrd };
    sampleTriangle(positions, texCoords, triangleId);
}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    voxelizeTriangle(tid.x);
}
