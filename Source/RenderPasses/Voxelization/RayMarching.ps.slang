#include "Voxel/VoxelGrid.slang"
#include "Math/VoxelizationUtility.slang"
#include "Shading.slang"
#include "VoxelizationShared.slang"
import Scene.SceneTypes;
import Scene.Scene;
import Rendering.Materials.StandardMaterial;
import Utils.Sampling.UniformSampleGenerator;
import Scene.Lights.EnvMap;
import Rendering.Lights.EnvMapSampler;

#define MAX_BOUNCE 4
#define MAX_LIGHT_COUNT 4

ParameterBlock<EnvMapSampler> envMapSampler;
Texture3D<int> vBuffer;
StructuredBuffer<PrimitiveBSDF> gBuffer;
StructuredBuffer<Ellipsoid> pBuffer;
Texture2D<uint4> blockMap;
RWStructuredBuffer<float4> selectedVoxel;

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
    uint sampleStrategy;
    uint maxBounce;
    uint frameIndex;
    float minPdf;
    bool renderBackGround;
    float4 clearColor;
    uint2 selectedPixel;
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

bool isSolidVoxel(int3 cellInt, out int offset)
{
    offset = vBuffer[cellInt];
    if (offset < 0)
        return false;
    return gBuffer[offset].area > 0;
}

bool isSolidBlock(int3 blockInt)
{
    int component = blockInt.z / 32;
    uint value = 1 << blockInt.z % 32;
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

// 先后用体素和椭球裁剪线段
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
    HitResult result = { inOut.x >= 0, cellInt, cell + inOut.x * (to - from) };
    return result;
}

// 统一用网格坐标表示
HitResult rayMarching_DDA(float3 from, float3 direction, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));

    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        leave(cell, cellInt, directions, direction, reciprocal_direction);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;
        int offset;
        if (isSolidVoxel(cellInt, offset)) // 理论上不会出现面积为0的情况
        {
#if !CHECK_ELLIPSOID
            HitResult hit = { true, cellInt, cellInt + 0.5f };
            return hit;
#else
            Ellipsoid ellipsoid = pBuffer[offset];
            HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
            if (hit.hit)
                return hit;
#endif
        }
        leave(cell, cellInt, directions, direction, reciprocal_direction);
    }
    HitResult hit = { false, cellInt, cellInt + 0.5f };
    return hit;
}
// 统一用网格坐标表示
HitResult rayMarching_DDA(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));
    float distance = 0;

    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        distance += leave(cell, cellInt, directions, direction, reciprocal_direction);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;
        if (maxDistance > 0 && distance > maxDistance) // 非正数表示不限制距离
            break;
        int offset;
        if (isSolidVoxel(cellInt, offset)) // 理论上不会出现面积为0的情况
        {
#if !CHECK_ELLIPSOID
            HitResult hit = { true, cellInt, cellInt + 0.5f };
            return hit;
#else
            Ellipsoid ellipsoid = pBuffer[offset];
            HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
            if (hit.hit)
                return hit;
#endif
        }
        distance += leave(cell, cellInt, directions, direction, reciprocal_direction);
    }
    HitResult hit = { false, cellInt, cellInt + 0.5f };
    return hit;
}

HitResult rayMarching_Mipmap(float3 from, float3 direction, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));

    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        leave(cell, cellInt, directions, direction, reciprocal_direction);

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
                if (isSolidVoxel(cellInt, offset)) // 理论上不会出现面积为0的情况
                {
#if !CHECK_ELLIPSOID
                    HitResult hit = { true, cellInt, cellInt + 0.5f };
                    return hit;
#else
                    Ellipsoid ellipsoid = pBuffer[offset];
                    HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
                    if (hit.hit)
                        return hit;
#endif
                }
                leave(cell, cellInt, directions, direction, reciprocal_direction);
                current = cellInt / BLOCK_TO_VOXEL;
            }
        }
        else
        {
            leaveBlock(cell, cellInt, directions, direction, reciprocal_direction);
        }
    }
    HitResult hit = { false, cellInt, cellInt + 0.5f };
    return hit;
}

HitResult rayMarching_Mipmap(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));
    float distance = 0;

    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        distance += leave(cell, cellInt, directions, direction, reciprocal_direction);

    while (true)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;
        if (distance > maxDistance) // 非正数表示不限制距离
            break;

        int3 blockInt = cellInt / BLOCK_TO_VOXEL;
        if (isSolidBlock(blockInt))
        {
            int3 current = blockInt;
            while (all(current == blockInt))
            {
                if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
                    break;
                if (distance > maxDistance) // 非正数表示不限制距离
                    break;
                int offset;
                if (isSolidVoxel(cellInt, offset)) // 理论上不会出现面积为0的情况
                {
#if !CHECK_ELLIPSOID
                    HitResult hit = { true, cellInt, cellInt + 0.5f };
                    return hit;
#else
                    Ellipsoid ellipsoid = pBuffer[offset];
                    HitResult hit = checkPrimitive(ellipsoid, cell, direction, cellInt);
                    if (hit.hit)
                        return hit;
#endif
                }
                distance += leave(cell, cellInt, directions, direction, reciprocal_direction);
                current = cellInt / BLOCK_TO_VOXEL;
            }
        }
        else
        {
            distance += leaveBlock(cell, cellInt, directions, direction, reciprocal_direction);
        }
    }
    HitResult hit = { false, cellInt, cellInt + 0.5f };
    return hit;
}

HitResult rayMarching(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    direction = normalizeSafe(direction);
    if (all(direction == float3(0)))
    {
        HitResult hit = { false, int3(from), from };
        return hit;
    }
#if USE_MIP_MAP
    if (maxDistance > 0)
        return rayMarching_Mipmap(from, direction, maxDistance, ignoreFirst);
    return rayMarching_Mipmap(from, direction, ignoreFirst);
#else
    if (maxDistance > 0)
        return rayMarching_DDA(from, direction, maxDistance, ignoreFirst);
    return rayMarching_DDA(from, direction, maxDistance, ignoreFirst);
#endif
}

float calcTrasmissionVisibility(HitResult hit, float3 direction)
{
    hit = rayMarching(hit.cell, direction, -1, true);
    return hit.hit ? 0.f : 1.f;
}

float calcLightVisibility(HitResult hit, float3 direction, float3 mainNormal, float maxDistance)
{
    float3 from = hit.cell + shadowBias * mainNormal;
    hit = rayMarching(from, direction, maxDistance, true);
    return hit.hit ? 0.f : 1.f;
}

float3 debugShading(HitResult hit, uint offset, float3 v)
{
    PrimitiveBSDF bsdf = gBuffer[offset];
    Ellipsoid e = pBuffer[offset];
    float result = 0;
    switch (drawMode)
    {
    case ABSDFDrawMode::Normal:
        return bsdf.surface.getMainNormal(v) * 0.5 + 0.5;
    case ABSDFDrawMode::EllipsoidProjArea:
        result = e.projectArea(v) / PI * 2;
        break;
    case ABSDFDrawMode::EllipsoidCenter:
        return e.center;
    case ABSDFDrawMode::PolygonsProjArea:
        result = bsdf.polygonsProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::TotalProjArea:
        result = bsdf.totalProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::PrimitiveProjArea:
        result = bsdf.primitiveProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::Coverage:
        result = bsdf.polygonsProjAreaFunc.calc(v) / bsdf.primitiveProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::InternalVisibility:
        return bsdf.calcInternalVisibility(v);
    default:
        break;
    }
    return valueToColor(result);
}

float3 shading(uint offset, float3 l, float3 v, float3 h, float3 lightColor)
{
    PrimitiveBSDF BSDF = gBuffer[offset];
    return lightColor * BSDF.eval(l, v, h);
}

float3 shadingDirect(HitResult hit, uint offset, float3 v, inout UniformSampleGenerator sg)
{
    PrimitiveBSDF BSDF = gBuffer[offset];
    float3 mainNormal = BSDF.surface.getMainNormal(v);
    float3 posW = gridMin + hit.cell * voxelSize;
    uint lightCount = min(gScene.lightCount, MAX_LIGHT_COUNT - 1);
    float totalIlluminance = 0;

    float3 l, h;
    float3 lightColor = 0;
    float maxDistance = 0;
    float pdf = 1;

    float3[MAX_LIGHT_COUNT] lightColors;
    float[MAX_LIGHT_COUNT] illuminances;
    float3[MAX_LIGHT_COUNT] ls;
    float[MAX_LIGHT_COUNT] maxDistances;

    for (uint i = 0; i < lightCount; i++)
    {
        LightData light = gScene.getLight(i);
        switch (light.type)
        {
        case LightType::Point:
            float3 toL = light.posW - posW;
            ls[i] = normalize(toL);
            maxDistances[i] = length(toL / voxelSize);
            float sqrDistance = max(dot(toL, toL), 1e-4f);

            float spot = 1.0f;
            if (light.openingAngle < PI)
            {
                float cosTerm = dot(light.dirW, -ls[i]);
                float cosOuter = light.cosOpeningAngle;
                float innerAng = max(light.openingAngle - light.penumbraAngle, 0.0f);
                float cosInner = cos(innerAng);

                float t = saturate((cosTerm - cosOuter) / max(cosInner - cosOuter, 1e-6f));
                spot = t * t * (3.0f - 2.0f * t);

                if (light.penumbraAngle <= 0.0f)
                    spot = (cosTerm >= cosOuter) ? 1.0f : 0.0f;
            }
            lightColors[i] = light.intensity * spot / sqrDistance;
            break;
        case LightType::Directional:
            ls[i] = -light.dirW;
            lightColors[i] = light.intensity;
            maxDistances[i] = -1;
            break;
        }
        if (dot(mainNormal, ls[i]) < 0)
            illuminances[i] = 0;
        else
        {
            illuminances[i] = (lightColors[i].x + lightColors[i].y + lightColors[i].z);
            totalIlluminance += illuminances[i];
        }
    }
#if !NO_ENV_MAP
    illuminances[lightCount] = 10; // TODO:计算环境贴图光照度
    maxDistances[lightCount] = -1; // 无穷远处
    totalIlluminance += illuminances[lightCount];
    lightCount++;
#endif

    bool isEnv = false;
    if (totalIlluminance == 0)
        return 0;

    // 在若干个光源和环境光间选择一个
    float r = Next(sg) * totalIlluminance;
    for (uint i = 0; i < lightCount; i++)
    {
        if (illuminances[i] > 0)
        {
            r -= illuminances[i];
            if (r <= 0 || i == lightCount - 1)
            {
                lightColor = lightColors[i];
                l = ls[i];
                maxDistance = maxDistances[i];
                pdf = illuminances[i] / totalIlluminance;
#if !NO_ENV_MAP
                isEnv = (i == lightCount - 1);
#endif
                break;
            }
        }
    }

    if (isEnv)
    {
        switch (sampleStrategy)
        {
        case SampleStrategy::EnviromentMap:
            EnvMapSample envSample;
            envMapSampler.sample(Next2(sg), envSample);
            l = envSample.dir;
            if (dot(mainNormal, l) < 0)
                l = -l;
            h = normalizeSafe(l + v);
            pdf *= envMapSampler.evalPdf(l) + envMapSampler.evalPdf(-l);
            break;
        case SampleStrategy::BSDF:
            BSDF.sample(v, l, h, sg);
            pdf *= BSDF.evalPdf(l, v, h);
            break;
        case SampleStrategy::Mix:
            float bsdfWeight = BSDF.surface.calcBRDFWeight();
            if (Next(sg) <= bsdfWeight)
            {
                BSDF.sample(v, l, h, sg);
            }
            else
            {
                EnvMapSample envSample;
                envMapSampler.sample(Next2(sg), envSample);
                l = envSample.dir;
                if (dot(mainNormal, l) < 0)
                    l = -l;
                h = normalizeSafe(l + v);
            }

            if (all(h == 0))
                pdf *= bsdfWeight * BSDF.evalPdf(l, v, h); // delta lobe的pdf本质上是无穷大，不能和其他pdf加权平均
            else
                pdf *= bsdfWeight * BSDF.evalPdf(l, v, h) + (1 - bsdfWeight) * (envMapSampler.evalPdf(l) + envMapSampler.evalPdf(-l));
            break;
        }
        lightColor = envMapSampler.eval(l);
    }
    else
    {
        h = normalizeSafe(l + v);
    }

    pdf = max(pdf, minPdf);
    float visibility = calcLightVisibility(hit, l, mainNormal, maxDistance);

    if (visibility > 0)
        return visibility * shading(offset, l, v, h, lightColor) / pdf;
    return 0;
}

float3 shadingGlobal(HitResult hit, float3 v, uint bounce, inout UniformSampleGenerator sg)
{
    // 非递归版本，先计算所有命中点，再倒回来统计
    HitResult[MAX_BOUNCE + 1] hits;
    float3[MAX_BOUNCE + 1] ls; // 第i个采样方向即第i个体素指向第i+1个体素的方向
    float3[MAX_BOUNCE + 1] hs;
    float[MAX_BOUNCE + 1] pdfs; // 第i个pdf即第i+1个体素对第i个体素的贡献权重
    bounce = min(bounce, MAX_BOUNCE);
    uint hitCount = bounce + 1;
    hits[0] = hit;
    for (int i = 0; i < bounce; i++)
    {
        uint offset = vBuffer[hits[i].cellInt];
        PrimitiveBSDF BSDF = gBuffer[offset];
        float3 currentV = i == 0 ? v : -ls[i - 1];
        BSDF.sample(currentV, ls[i], hs[i], sg);

        hits[i + 1] = rayMarching(hits[i].cell, ls[i], -1, true);
        pdfs[i] = BSDF.evalPdf(ls[i], currentV, hs[i]);
        if (!hits[i + 1].hit || pdfs[i] < minPdf)
        {
            hitCount = i + 1;
            break;
        }
        pdfs[i] = max(pdfs[i], minPdf);
    }

    float3 reflectLights[MAX_BOUNCE + 1];
    for (int i = hitCount - 1; i >= 0; i--)
    {
        reflectLights[i] = 0;
        HitResult currentHit = hits[i];
        uint currentOffset = vBuffer[currentHit.cellInt];
        float3 currentV = i == 0 ? v : -ls[i - 1];

        reflectLights[i] += shadingDirect(currentHit, currentOffset, currentV, sg);
        if (i < hitCount - 1 && pdfs[i] > 0)
        {
            HitResult nextHit = hits[i + 1];
            uint nextOffset = vBuffer[nextHit.cellInt];
            float3 incidentLight = reflectLights[i + 1];
            reflectLights[i] += shading(currentOffset, ls[i], currentV, hs[i], incidentLight) / pdfs[i];
        }
    }
    return reflectLights[0];
}

float3 screenCoordToCell(float2 screenCoord, float NDCDepth)
{
    float4 NDC = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, NDCDepth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posWorld = temp / temp.w;
    float3 cell = (posWorld.xyz - gridMin) / voxelSize;
    return cell;
}
float2 randomJitter()
{
    UniformSampleGenerator sg = UniformSampleGenerator(0, frameIndex);
    float2 jitter = Next2(sg) - 0.5f;
    jitter /= pixelCount;
    return jitter;
}
float4 renderBackground(float3 direction)
{
#if !NO_ENV_MAP
    if (renderBackGround)
    {
        float3 color = gScene.envMap.eval(direction);
        return float4(color, 1);
    }
#endif
    return clearColor;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = {};
    uint2 pixel = uint2(texCoord * pixelCount);
    float2 jitter = randomJitter();
    texCoord = saturate(texCoord + jitter);
    float3 from = screenCoordToCell(texCoord, 0);
    float3 to = screenCoordToCell(texCoord, 1);
    float3 delta = to - from;
    float3 direction = normalize(delta); // 网格/世界空间下的方向相同
    psOut.color = renderBackground(direction);

    float2 inOut = clip(float3(0), float3(voxelCount), from, to);
    if (inOut.x < 0)
        return psOut;

    UniformSampleGenerator sg = UniformSampleGenerator(pixel, frameIndex);
    from = from + inOut.x * delta;
    HitResult hit = rayMarching(from, direction, -1, true);
    if (all(pixel == selectedPixel))
    {
        if (hit.hit)
        {
            int offset = vBuffer[hit.cellInt];
            selectedVoxel[0] = float4(-direction, (float)offset);
        }
        else
        {
            selectedVoxel[0] = float4(-1);
        }
    }

    if (hit.hit)
    {
        float3 color = 0;
        uint offset = vBuffer[hit.cellInt];
        switch (drawMode)
        {
        case ABSDFDrawMode::Default:
            color = shadingGlobal(hit, -direction, maxBounce, sg);
            break;
        default:
            color = debugShading(hit, offset, -direction);
            break;
        }
        psOut.color = float4(color, 1);
    }

    return psOut;
}
