#include "Scene/VertexAttrib.slangh"

import Scene.Raster;
import Utils.Math.MathHelpers;
import GBufferHelpers;
import Rendering.Materials.TexLODHelpers;

RWTexture3D<uint> gOccupancyMap;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
};

struct PSOut
{
    float4 color : SV_TARGET0;
};

float3 worldToCell(float3 worldPos)
{
    float3 relativePos = worldPos - gridMin;
    return relativePos / voxelSize;
}

uint subVoxelOffsetToMask(float3 offset)
{
    uint x = (uint)(offset.x * 4);
    uint y = (uint)(offset.y * 2);
    uint z = (uint)(offset.z * 4);
    uint index = x + (y << 2) + (z << 3);
    return 1u << index;
}

VSOut vsMain(VSIn vsIn)
{
    return defaultVS(vsIn);
}

PSOut psMain(VSOut vsOut, uint triangleIndex: SV_PrimitiveID, float3 barycentrics: SV_Barycentrics)
{
    PSOut psOut = {};
    float3 cell = worldToCell(vsOut.posW.xyz);
    if (all(cell < voxelCount) && all(cell >= 0))
    {
        int3 cellInt = int3(floor(cell));
        uint mask = subVoxelOffsetToMask(cell - cellInt);
        InterlockedOr(gOccupancyMap[cellInt], mask);
    }
    psOut.color = float4(1);
    return psOut;
}
