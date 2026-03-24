#include "Voxel/VoxelGrid.slang"
#include "Math/Triangle.slang"
#include "Math/VoxelizationUtility.slang"
#include "VoxelizationShared.slang"
#include "MixLightSampler.slang"
import Rendering.Materials.StandardMaterial;
import Utils.Sampling.UniformSampleGenerator;

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
    uint3 blockCount;
    float4x4 invVP;
    float shadowBias;
    uint drawMode;
    bool aoEnabled;
    uint aoSampleCount;
    float aoRadius;
    float aoStrength;
    uint frameIndex;
    float minPdf;
    bool renderBackground;
    float4 clearColor;
}

struct HitResult
{
    bool hit;
    int3 cellInt;
    float3 cell;
};

struct PsOut
{
    float4 color : SV_Target0;
};

static const uint kDrawModeCombined = 0;
static const uint kDrawModeDirectOnly = 1;
static const uint kDrawModeAOOnly = 2;
static const uint kDrawModeNormalDebug = 3;
static const uint kDrawModeCoverageDebug = 4;
static const float kCoverageThreshold = 0.05f;

bool isSolidVoxel(int3 cellInt, out int offset)
{
    offset = vBuffer[cellInt];
    if (offset < 0 || offset >= solidVoxelCount)
        return false;
    return gBuffer[offset].area > 0;
}

bool isSolidBlock(int3 blockInt)
{
    int component = blockInt.z / 32;
    uint value = 1 << (blockInt.z % 32);
    uint4 zMap = blockMap[blockInt.xy];
    switch (component)
    {
    case 0:
        value &= zMap.x;
        break;
    case 1:
        value &= zMap.y;
        break;
    case 2:
        value &= zMap.z;
        break;
    case 3:
        value &= zMap.w;
        break;
    }
    return value != 0;
}

HitResult checkPrimitive(Ellipsoid ellipsoid, float3 cell, float3 direction, int3 cellInt)
{
    float3 from = cell - cellInt;
    int3 directions = int3(sign(direction));
    float3 border = (directions + 1) / 2;
    float3 t = (border - from) / direction;
    float tMin = 2.0f;
    if (direction.x != 0 && t.x < tMin)
        tMin = t.x;
    if (direction.y != 0 && t.y < tMin)
        tMin = t.y;
    if (direction.z != 0 && t.z < tMin)
        tMin = t.z;
    float3 to = from + tMin * direction;
    float2 inOut = ellipsoid.clip(from, to);
    HitResult result = {inOut.x >= 0, cellInt, cell + inOut.x * (to - from)};
    return result;
}

HitResult rayMarching_DDA(float3 from, float3 direction, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));

    float3 reciprocalDirection = 1.0f / direction;
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        leave(cell, cellInt, directions, direction, reciprocalDirection);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;

        int offset;
        if (isSolidVoxel(cellInt, offset))
        {
#if !CHECK_ELLIPSOID
            HitResult hit = {true, cellInt, cellInt + 0.5f};
            return hit;
#else
            Ellipsoid ellipsoid = pBuffer[offset];
            HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
            if (hit.hit)
                return hit;
#endif
        }

        leave(cell, cellInt, directions, direction, reciprocalDirection);
    }

    HitResult hit = {false, cellInt, cellInt + 0.5f};
    return hit;
}

HitResult rayMarching_DDA(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));
    float distance = 0;

    float3 reciprocalDirection = 1.0f / direction;
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        distance += leave(cell, cellInt, directions, direction, reciprocalDirection);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;
        if (maxDistance > 0 && distance > maxDistance)
            break;

        int offset;
        if (isSolidVoxel(cellInt, offset))
        {
#if !CHECK_ELLIPSOID
            HitResult hit = {true, cellInt, cellInt + 0.5f};
            return hit;
#else
            Ellipsoid ellipsoid = pBuffer[offset];
            HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
            if (hit.hit)
                return hit;
#endif
        }

        distance += leave(cell, cellInt, directions, direction, reciprocalDirection);
    }

    HitResult hit = {false, cellInt, cellInt + 0.5f};
    return hit;
}

HitResult rayMarching_Mipmap(float3 from, float3 direction, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));

    float3 reciprocalDirection = 1.0f / direction;
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        leave(cell, cellInt, directions, direction, reciprocalDirection);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;

        int3 blockInt = cellInt / BLOCK_TO_VOXEL;
        if (isSolidBlock(blockInt))
        {
            int3 current = blockInt;
            while (all(current == blockInt))
            {
                if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
                    break;

                int offset;
                if (isSolidVoxel(cellInt, offset))
                {
#if !CHECK_ELLIPSOID
                    HitResult hit = {true, cellInt, cellInt + 0.5f};
                    return hit;
#else
                    Ellipsoid ellipsoid = pBuffer[offset];
                    HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
                    if (hit.hit)
                        return hit;
#endif
                }

                leave(cell, cellInt, directions, direction, reciprocalDirection);
                current = cellInt / BLOCK_TO_VOXEL;
            }
        }
        else
        {
            leaveBlock(cell, cellInt, directions, direction, reciprocalDirection);
        }
    }

    HitResult hit = {false, cellInt, cellInt + 0.5f};
    return hit;
}

HitResult rayMarching_Mipmap(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));
    float distance = 0;

    float3 reciprocalDirection = 1.0f / direction;
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        distance += leave(cell, cellInt, directions, direction, reciprocalDirection);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;
        if (distance > maxDistance)
            break;

        int3 blockInt = cellInt / BLOCK_TO_VOXEL;
        if (isSolidBlock(blockInt))
        {
            int3 current = blockInt;
            while (all(current == blockInt))
            {
                if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
                    break;
                if (distance > maxDistance)
                    break;

                int offset;
                if (isSolidVoxel(cellInt, offset))
                {
#if !CHECK_ELLIPSOID
                    HitResult hit = {true, cellInt, cellInt + 0.5f};
                    return hit;
#else
                    Ellipsoid ellipsoid = pBuffer[offset];
                    HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
                    if (hit.hit)
                        return hit;
#endif
                }

                distance += leave(cell, cellInt, directions, direction, reciprocalDirection);
                current = cellInt / BLOCK_TO_VOXEL;
            }
        }
        else
        {
            distance += leaveBlock(cell, cellInt, directions, direction, reciprocalDirection);
        }
    }

    HitResult hit = {false, cellInt, cellInt + 0.5f};
    return hit;
}

HitResult rayMarching(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    direction = normalizeSafe(direction);
    if (all(direction == float3(0)))
    {
        HitResult hit = {false, int3(from), from};
        return hit;
    }

#if USE_MIP_MAP
    if (maxDistance > 0)
        return rayMarching_Mipmap(from, direction, maxDistance, ignoreFirst);
    return rayMarching_Mipmap(from, direction, ignoreFirst);
#else
    if (maxDistance > 0)
        return rayMarching_DDA(from, direction, maxDistance, ignoreFirst);
    return rayMarching_DDA(from, direction, ignoreFirst);
#endif
}

float calcLightVisibility(HitResult hit, float3 direction, float3 mainNormal, float distance)
{
    float ignoreDistance = 2;
    if (distance >= 0 && distance <= ignoreDistance)
        return 1;

    float3 from = hit.cell + shadowBias * mainNormal;
    hit = rayMarching(from, direction, distance - ignoreDistance, true);
    return hit.hit ? 0 : 1;
}

float3 evalBSDF(uint offset, float3 l, float3 v, float3 h, float3 lightColor)
{
    PrimitiveBSDF bsdf = gBuffer[offset];
    bsdf.updateCoverage(v, kCoverageThreshold);
    return lightColor * bsdf.eval(l, v, h);
}

float3 shadingDirect(HitResult hit, uint offset, float3 v, inout UniformSampleGenerator sg)
{
    PrimitiveBSDF bsdf = gBuffer[offset];
    float3 posW = gridMin + hit.cell * voxelSize;
    LightSample ls = {};
    bool valid = sampleLight(posW, v, bsdf, sg, ls);

    if (!valid || ls.pdf <= 0 || all(ls.h == 0))
        return 0;

    ls.pdf = max(ls.pdf, minPdf);
    float3 mainNormal = bsdf.surface.getMainNormal(ls.l);
    float visibility = calcLightVisibility(hit, ls.l, mainNormal, ls.distance / voxelSize.x);
    if (visibility <= 0)
        return 0;

    return visibility * evalBSDF(offset, ls.l, v, ls.h, ls.lightColor) / ls.pdf;
}

float3 sampleUniformHemisphere(float2 u)
{
    float z = u.x;
    float r = safeSqrt(max(0.0f, 1.0f - z * z));
    float phi = 2.0f * Pi * u.y;
    return float3(r * cos(phi), r * sin(phi), z);
}

float calcAO(HitResult hit, uint offset, float3 viewDir, inout UniformSampleGenerator sg)
{
    if (!aoEnabled || aoSampleCount == 0 || aoRadius <= 0 || aoStrength <= 0)
        return 1;

    PrimitiveBSDF bsdf = gBuffer[offset];
    float3 mainNormal = bsdf.surface.getMainNormal(viewDir);
    float3 t, b;
    buildTBN(t, b, mainNormal);

    float visibleSampleCount = 0;
    float3 from = hit.cell + shadowBias * mainNormal;
    for (uint i = 0; i < aoSampleCount; ++i)
    {
        float3 localDir = sampleUniformHemisphere(Next2(sg));
        float3 sampleDir = localToWorld(localDir, t, b, mainNormal);
        HitResult aoHit = rayMarching(from, sampleDir, aoRadius, true);
        visibleSampleCount += aoHit.hit ? 0 : 1;
    }

    float visibility = visibleSampleCount / aoSampleCount;
    return lerp(1.0f, visibility, saturate(aoStrength));
}

float3 debugColor(uint offset, float3 viewDir)
{
    PrimitiveBSDF bsdf = gBuffer[offset];
    switch (drawMode)
    {
    case kDrawModeNormalDebug:
        return bsdf.surface.getMainNormal(viewDir) * 0.5f + 0.5f;
    case kDrawModeCoverageDebug:
        return valueToColor(bsdf.calcCoverage(viewDir));
    default:
        return 0;
    }
}

float3 screenCoordToCell(float2 screenCoord, float ndcDepth)
{
    float4 ndc = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, ndcDepth, 1);
    float4 temp = mul(invVP, ndc);
    float4 posWorld = temp / temp.w;
    return (posWorld.xyz - gridMin) / voxelSize;
}

float2 randomJitter()
{
    UniformSampleGenerator sg = UniformSampleGenerator(0, frameIndex);
    float2 jitter = Next2(sg) - 0.5f;
    jitter /= pixelCount;
    return jitter;
}

float4 renderSky(float3 direction)
{
#if USE_ENV_MAP
    if (renderBackground)
        return float4(gScene.envMap.eval(direction), 1);
#endif
    return clearColor;
}

PsOut main(float2 texCoord : TEXCOORD, float4 pos : SV_POSITION)
{
    PsOut psOut = {};
    uint2 pixel = uint2(texCoord * pixelCount);
    texCoord = saturate(texCoord + randomJitter());

    float3 from = screenCoordToCell(texCoord, 0);
    float3 to = screenCoordToCell(texCoord, 1);
    float3 delta = to - from;
    float3 direction = normalize(delta);
    psOut.color = renderSky(direction);

    float2 inOut = clip(float3(0), float3(voxelCount), from, to);
    if (inOut.x < 0)
        return psOut;

    UniformSampleGenerator sg = UniformSampleGenerator(pixel, frameIndex);
    from = from + (inOut.x + 1e-6f) * delta;
    HitResult hit = rayMarching(from, direction, -1, false);
    if (!hit.hit)
        return psOut;

    uint offset = vBuffer[hit.cellInt];
    float3 viewDir = -direction;
    if (drawMode == kDrawModeNormalDebug || drawMode == kDrawModeCoverageDebug)
    {
        psOut.color = float4(debugColor(offset, viewDir), 1);
        return psOut;
    }

#if USE_EMISSIVE_LIGHTS
    if (drawMode != kDrawModeAOOnly)
    {
        float3 emissiveColor = 0;
        float3 posW = gridMin + hit.cell * voxelSize;
        if (checkHitEmissive(posW, voxelSize.x, emissiveColor))
        {
            psOut.color = float4(emissiveColor, 1);
            return psOut;
        }
    }
#endif

    float3 direct = shadingDirect(hit, offset, viewDir, sg);
    float ao = calcAO(hit, offset, viewDir, sg);

    float3 color = 0;
    switch (drawMode)
    {
    case kDrawModeCombined:
        color = direct * ao;
        break;
    case kDrawModeDirectOnly:
        color = direct;
        break;
    case kDrawModeAOOnly:
        color = ao.xxx;
        break;
    default:
        color = direct;
        break;
    }

    psOut.color = float4(color, 1);
    return psOut;
}
