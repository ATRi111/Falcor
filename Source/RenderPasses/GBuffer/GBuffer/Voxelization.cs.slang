#include "Scene/VertexAttrib.slangh"

import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;
import GBufferHelpers;
import Rendering.Materials.TexLODHelpers;
import Scene.Material.BasicMaterialData;

ParameterBlock<Scene> scene;
RWTexture3D<uint> gOM;
RWTexture3D<float4> gDiffuse;
SamplerState s;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
    uint samplePointsPerCellFace;
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

bool SAT13(float3[3] points, float3 center, float3 extent)
{
    // Get the triangle points as vectors
    float3 v0 = points[0] - center;
    float3 v1 = points[1] - center;
    float3 v2 = points[2] - center;

    // Compute the edge vectors of the triangle  (ABC)
    // That is, get the lines between the points as vectors
    float3 f0 = v1 - v0; // B - A
    float3 f1 = v2 - v1; // C - B
    float3 f2 = v0 - v2; // A - C

    // Compute the face normals of the AABB, because the AABB
    // is at center, and of course axis aligned, we know that
    // it's normals are the X, Y and Z axis.
    float3 u0 = float3(1, 0, 0);
    float3 u1 = float3(0, 1, 0);
    float3 u2 = float3(0, 0, 1);

    // There are a total of 13 axis to test!

    // We first test against 9 axis, these axis are given by
    // cross product combinations of the edges of the triangle
    // and the edges of the AABB. You need to get an axis testing
    // each of the 3 sides of the AABB against each of the 3 sides

    // Compute the 9 axis
    float3[13] axis;

    axis[0] = normalize(cross(u0, f0));
    axis[1] = normalize(cross(u0, f1));
    axis[2] = normalize(cross(u0, f2));
    axis[3] = normalize(cross(u1, f0));
    axis[4] = normalize(cross(u1, f1));
    axis[5] = normalize(cross(u1, f2));
    axis[6] = normalize(cross(u2, f0));
    axis[7] = normalize(cross(u2, f1));
    axis[8] = normalize(cross(u2, f2));

    // Testing axis: axis_u0_f0
    // Project all 3 vertices of the triangle onto the Seperating axis
    axis[9] = u0;
    axis[10] = u1;
    axis[11] = u2;
    // Finally, we have one last axis to test, the face normal of the triangle
    // We can get the normal of the triangle by crossing the first two line segments
    axis[12] = normalize(cross(f0, f1));

    for (int i = 0; i < 13; i++)
    {
        // Testing axis: axis_u0_f0
        // Project all 3 vertices of the triangle onto the Seperating axis
        float p0 = dot(v0, axis[i]);
        float p1 = dot(v1, axis[i]);
        float p2 = dot(v2, axis[i]);

        float r = extent.x * abs(dot(u0, axis[i])) + extent.y * abs(dot(u1, axis[i])) + extent.z * abs(dot(u2, axis[i]));
        // Now do the actual test, basically see if either of
        // the most extreme of the triangle points intersects r
        // You might need to write Min & Max functions that take 3 arguments
        if (max(-max3(p0, p1, p2), min3(p0, p1, p2)) > r)
        {
            // This means BOTH of the points of the projected triangle
            // are outside the projected half-length of the AABB
            // Therefore the axis is seperating and we can exit
            return false;
        }
    }
    return true;
}

void updateOM(float3[3] positions)
{
    float3 minF = min3(positions[0], positions[1], positions[2]);
    float3 maxF = max3(positions[0], positions[1], positions[2]);
    int3 minI = (int3)floor(clamp(minF, 0, voxelCount - 1));
    int3 maxI = (int3)ceil(clamp(maxF, 0, voxelCount - 1));
    for (int z = minI.z; z <= maxI.z; z++)
    {
        for (int y = minI.y; y <= maxI.y; y++)
        {
            for (int x = minI.x; x <= maxI.x; x++)
            {
                float3 voxelMin = float3(x, y, z);
                if (gOM[int3(voxelMin)] == 0xFFFFFFFF)
                    continue;
                if (SAT13(positions, voxelMin + 0.5, 1))
                {
                    gOM[int3(voxelMin)] = 0xFFFFFFFF;
                }
            }
        }
    }
}

void sampleMaterial(float3 position, float2 texCoord, ITextureSampler lod, uint triangleId)
{
    MaterialSystem ms = scene.materials;
    MaterialType type = ms.getMaterialType(materialID);
    int3 p = int3(position);
    switch (type)
    {
    case MaterialType::Standard:
        BasicMaterialData data = ms.getBasicMaterialData(materialID);

        const float3 baseColor = ms.sampleTexture(data.texBaseColor, s, texCoord, data.baseColor, lod).rgb;
        const float4 spec = ms.sampleTexture(data.texSpecular, s, texCoord, data.specular, lod); // G - Roughness; B - Metallic
        // gDiffuse[p] += float4(texCoord, 0, 1);
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
    // float S_tex = 0.5f * length(cross(float3(texCoords[2] - texCoords[1], 0), float3(texCoords[2] - texCoords[0], 0)));
    float sampleCount = samplePointsPerCellFace * S;
    uint uCount = (uint)ceil(sqrt(2 * sampleCount / k));
    uint vCount = (uint)ceil(uCount * k);

    float deltaU = 1.0f / (uCount + 1);
    float deltaV = 1.0f / (vCount + 1);

    for (float u = deltaU; u < 1; u += deltaU)
    {
        for (float v = deltaV; v < 1; v += deltaV)
        {
            if (u + v > 1)
                continue;
            float3 pos = positions[0] * u + positions[1] * v + positions[2] * (1 - u - v);
            float2 texCoord = frac(texCoords[0] * u + texCoords[1] * v + texCoords[2] * (1 - u - v));
            let lod = ImplicitLodTextureSampler();
            sampleMaterial(pos, texCoord, lod, triangleId);
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
    updateOM(positions);
    sampleTriangle(positions, texCoords, triangleId);
}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    voxelizeTriangle(tid.x);
}
