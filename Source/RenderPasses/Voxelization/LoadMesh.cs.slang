#include "Voxel/VoxelGrid.slang"
#include "Scene/VertexAttrib.slangh"

import Scene.SceneTypes;
import Scene.Scene;
import Scene.Raster;
import Utils.Math.MathHelpers;

RWStructuredBuffer<float3> positions;
RWStructuredBuffer<float3> normals;
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
    uint3 triangle = gScene.getLocalIndices(ibOffset, triangleId, use16BitIndices);
    triangle += vbOffset;
    triangles[triangleId + triOffset] = triangle;
    uint indices[3] = { triangle.x, triangle.y, triangle.z };
    for (uint i = 0; i < 3; i++)
    {
        uint index = indices[i];
        StaticVertexData vertex = gScene.getVertex(index);
        positions[index] = vertex.position;
        texCoords[index] = vertex.texCrd;
        normals[index] = vertex.normal;
    }
}

[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    loadTriangle(tid.x);
}
