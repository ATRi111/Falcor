#ifndef CHECK_ELLIPSOID
#define CHECK_ELLIPSOID 1
#endif

#ifndef CHECK_VISIBILITY
#define CHECK_VISIBILITY 1
#endif

#ifndef CHECK_COVERAGE
#define CHECK_COVERAGE 1
#endif

#ifndef USE_MIP_MAP
#define USE_MIP_MAP 1
#endif

#include "Voxel/VoxelGrid.slang"
#include "Math/VoxelizationUtility.slang"
#include "Shading.slang"

Texture3D<int> vBuffer;
StructuredBuffer<PrimitiveBSDF> gBuffer;
StructuredBuffer<Ellipsoid> pBuffer;
Texture2D<uint4> blockMap;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
    uint solidVoxelCount;
}

cbuffer CB
{
    uint2 pixelCount;
    float4x4 invVP;
    float shadowBias;
    uint drawMode;
    bool renderBackground;
}

#include "RayMarchingTraversal.slang"

struct PsOut
{
    float4 color : SV_Target0;
};

static const uint kDrawModeCombined = 0;
static const uint kDrawModeDirectOnly = 1;
static const uint kDrawModeAOOnly = 2;
static const uint kDrawModeNormalDebug = 3;
static const uint kDrawModeCoverageDebug = 4;

float3 screenCoordToCell(float2 screenCoord, float ndcDepth)
{
    float4 ndc = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, ndcDepth, 1);
    float4 temp = mul(invVP, ndc);
    float4 posWorld = temp / temp.w;
    return (posWorld.xyz - gridMin) / voxelSize;
}

float4 renderMissBackground(float3 direction)
{
    if (!renderBackground)
        return float4(0, 0, 0, 1);

    float t = saturate(direction.y * 0.5f + 0.5f);
    float3 horizonColor = float3(0.08f, 0.09f, 0.11f);
    float3 zenithColor = float3(0.26f, 0.29f, 0.35f);
    float3 color = lerp(horizonColor, zenithColor, t);
    return float4(color, 1);
}

float3 evalPlaceholderColor(uint mode, float3 mainNormal, float coverage)
{
    float diffuseTerm = saturate(dot(mainNormal, normalize(float3(0.45f, 0.80f, 0.38f))));
    float3 directPlaceholder = lerp(float3(0.10f, 0.08f, 0.06f), float3(0.82f, 0.75f, 0.60f), diffuseTerm);

    switch (mode)
    {
    case kDrawModeCombined:
        return directPlaceholder * lerp(0.35f, 1.0f, coverage);
    case kDrawModeDirectOnly:
        return directPlaceholder;
    case kDrawModeAOOnly:
        return coverage.xxx;
    default:
        return directPlaceholder;
    }
}

PsOut main(float2 texCoord : TEXCOORD, float4 pos : SV_POSITION)
{
    PsOut psOut = {};

    float3 from = screenCoordToCell(texCoord, 0);
    float3 to = screenCoordToCell(texCoord, 1);
    float3 delta = to - from;
    float3 direction = normalizeSafe(delta);
    psOut.color = renderMissBackground(direction);

    if (all(direction == 0))
        return psOut;

    float2 inOut = clip(float3(0), float3(voxelCount), from, to);
    if (inOut.x < 0)
        return psOut;

    from += (inOut.x + 1e-6f) * delta;
    HitResult hit = rayMarching(from, direction, -1, false);
    if (!hit.hit)
        return psOut;

    uint offset = vBuffer[hit.cellInt];
    PrimitiveBSDF bsdf = gBuffer[offset];
    float3 viewDir = -direction;
    float3 mainNormal = bsdf.surface.getMainNormal(viewDir);
    float coverage = bsdf.calcCoverage(viewDir);
    float3 color = 0;

    switch (drawMode)
    {
    case kDrawModeNormalDebug:
        color = mainNormal * 0.5f + 0.5f;
        break;
    case kDrawModeCoverageDebug:
        color = valueToColor(coverage);
        break;
    default:
        color = evalPlaceholderColor(drawMode, mainNormal, coverage);
        break;
    }

    psOut.color = float4(color, 1);
    return psOut;
}
