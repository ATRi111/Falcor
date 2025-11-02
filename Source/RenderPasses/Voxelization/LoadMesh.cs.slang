#include "VoxelizationShared.slang"
#include "Scene/VertexAttrib.slangh"

import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;

ParameterBlock<Scene> scene;
RWStructuredBuffer<float3> positions;
RWStructuredBuffer<float2> texCoords;
RWStructuredBuffer<uint3> triangles;

cbuffer MeshData
{
    uint vertexCount;
    uint triangleCount;
    uint vbOffset;
    uint ibOffset;
    uint triOffset;
    bool use16BitIndices;
};

void loadTriangle(uint triangleId)
{
    if (triangleId >= triangleCount)
        return;
    uint3 triangle = scene.getLocalIndices(ibOffset, triangleId, use16BitIndices);
    triangle += vbOffset;
    triangles[triangleId + triOffset] = triangle;
    uint[3] indices = { triangle.x, triangle.y, triangle.z };
    for (uint i = 0; i < 3; i++)
    {
        uint index = indices[i];
        StaticVertexData vertex = scene.getVertex(index);
        positions[index] = vertex.position;
        texCoords[index] = vertex.texCrd;
    }
}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    loadTriangle(tid.x);
}
