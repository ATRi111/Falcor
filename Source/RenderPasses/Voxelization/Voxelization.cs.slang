#include "Voxel/VoxelGrid.slang"
#include "Math/Ellipsoid.slang"
#include "Math/Triangle.slang"
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

void clipTriangle(Triangle triangle)
{

}

void voxelizeTriangle(uint triangleId)
{
    // 实际启动的线程数是线程组大小的整数倍，因此此语句必不可少
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

}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    voxelizeTriangle(tid.x);
}
