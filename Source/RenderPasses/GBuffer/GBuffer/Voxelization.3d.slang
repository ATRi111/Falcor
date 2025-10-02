#include "Scene/VertexAttrib.slangh"

import Scene.Raster;
import Utils.Math.MathHelpers;
import GBufferHelpers;
import Rendering.Materials.TexLODHelpers;

RWTexture3D<uint2> gOccupancyMap;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
};

uint3 worldToCell(float3 worldPos)
{
    float3 relativePos = worldPos - gridMin;
    uint3 cell = uint3(relativePos / voxelSize);
    return cell;
}

VSOut vsMain(VSIn vsIn)
{
    return defaultVS(vsIn);
}

void psMain(VSOut vsOut, uint triangleIndex: SV_PrimitiveID, float3 barycentrics: SV_Barycentrics)
{
    uint3 cell = worldToCell(vsOut.posW.xyz);
    if (all(cell < voxelCount) && all(cell >= 0))
    {
        gOccupancyMap[cell] = uint2(0xFFFFFFFF, 0xFFFFFFFF);
    }
}
