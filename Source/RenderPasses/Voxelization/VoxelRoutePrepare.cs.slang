#ifndef CHECK_COVERAGE
#define CHECK_COVERAGE 0
#endif

#ifndef CHECK_VISIBILITY
#define CHECK_VISIBILITY 0
#endif

#include "Voxel/VoxelGrid.slang"
#include "Shading.slang"
import Scene.Scene;
import Scene.SceneTypes;

StructuredBuffer<PrimitiveBSDF> gBuffer;
StructuredBuffer<int3> solidVoxelCellBuffer;
RWStructuredBuffer<uint> solidVoxelAcceptedRouteMask;
RWStructuredBuffer<uint4> resolvedBlockMap;

cbuffer CB
{
    uint solidVoxelCount;
    uint blockCountX;
    uint executionRouteMask;
}

static const float kTrustedIdentityThreshold = 0.999f;
static const uint kAllRouteMask = 0x7u;

uint getBlockIndex(int3 blockInt)
{
    return uint(blockInt.x) + uint(blockInt.y) * blockCountX;
}

void markResolvedBlock(int3 cellInt)
{
    const int3 blockInt = cellInt / BLOCK_TO_VOXEL;
    const uint blockIndex = getBlockIndex(blockInt);
    const int component = blockInt.z / 32;
    const uint bit = 1u << (blockInt.z % 32);

    switch (component)
    {
    case 0:
        InterlockedOr(resolvedBlockMap[blockIndex].x, bit);
        break;
    case 1:
        InterlockedOr(resolvedBlockMap[blockIndex].y, bit);
        break;
    case 2:
        InterlockedOr(resolvedBlockMap[blockIndex].z, bit);
        break;
    case 3:
        InterlockedOr(resolvedBlockMap[blockIndex].w, bit);
        break;
    }
}

uint getAcceptedRouteMask(PrimitiveBSDF bsdf)
{
    if (bsdf.area <= 0.f)
        return 0u;

    // Invalid or low-confidence identity must stay routable on both sides, otherwise
    // the block survives route prepare but the actual voxel hit gets rejected later.
    if (bsdf.dominantInstanceID == kInvalidVoxelInstanceID || bsdf.identityConfidence < kTrustedIdentityThreshold)
        return kAllRouteMask;

    GeometryInstanceID instanceID = { bsdf.dominantInstanceID };
    const GeometryInstanceRenderRoute route = gScene.getGeometryInstanceRenderRoute(instanceID);
    if (route == GeometryInstanceRenderRoute::Blend)
        return kAllRouteMask;

    return 1u << uint(route);
}

[numthreads(256, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    const uint offset = tid.x;
    if (offset >= solidVoxelCount)
        return;

    const PrimitiveBSDF bsdf = gBuffer[offset];
    const uint acceptedMask = getAcceptedRouteMask(bsdf);
    solidVoxelAcceptedRouteMask[offset] = acceptedMask;

    if ((acceptedMask & executionRouteMask) == 0u)
        return;

    markResolvedBlock(solidVoxelCellBuffer[offset]);
}
