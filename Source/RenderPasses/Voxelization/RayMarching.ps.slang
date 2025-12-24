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

#define MAX_BOUNCE 10

ParameterBlock<Scene> scene;
Texture3D<int> vBuffer;
StructuredBuffer<VoxelData> gBuffer;
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
    float4x4 invVP;
    float visibilityBias;
    uint drawMode;
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
}

struct PsOut
{
    float4 color : SV_Target0;
};

bool isSolidVoxel(int3 cellInt, out int offset)
{
    offset = vBuffer[cellInt];
    return offset >= 0 && gBuffer[offset].ABSDF.area > 0;
}

bool isTransmition(float3 l, float3 v)
{
    return abs(dot(l, v) + 1) < 1e-6f;
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
HitResult rayMarching(float3 from, float3 direction, float maxDistance, bool ignoreFirst)
{
    float3 cell = from;
    int3 cellInt = int3(floor(from));

    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));
    if (ignoreFirst)
        leave(cell, cellInt, directions, direction, reciprocal_direction);

    uint maxTimes = voxelCount.x + voxelCount.y + voxelCount.z;
    for (uint i = 0; i < maxTimes; i++)
    {
        if (any(cellInt < int3(0)) || any(cellInt >= (int3)voxelCount))
            break;
        if (maxDistance > 0 && length(cell - from) > maxDistance) // 非正数表示不限制距离
            break;
        int offset;
        if (isSolidVoxel(cellInt, offset)) // 理论上不会出现面积为0的情况
        {
#if !CHECK_ELLIPSOID
            HitResult hit = { true, cellInt, cellInt + 0.5f };
            return hit;
#else
            Ellipsoid ellipsoid = gBuffer[offset].ellipsoid;
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

float3 screenCoordToCell(float2 screenCoord, float NDCDepth)
{
    float4 NDC = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, NDCDepth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posWorld = temp / temp.w;
    float3 cell = (posWorld.xyz - gridMin) / voxelSize;
    return cell;
}

float calcVisibility(HitResult hit, float3 direction, float maxDistance)
{
    float3 from = hit.cell + visibilityBias * direction;
    hit = rayMarching(from, direction, maxDistance, true);
    return hit.hit ? 0.f : 1.f;
}

float3 debugShading(HitResult hit, uint offset, float3 v)
{
    VoxelData voxelData = gBuffer[offset];
    ABSDF ABSDF = voxelData.ABSDF;
    NDF NDF = ABSDF.NDF;
    Ellipsoid e = voxelData.ellipsoid;
    SphericalFunc polygonsProjAreaFunc = voxelData.polygonsProjAreaFunc;
    SphericalFunc primitiveProjAreaFunc = voxelData.primitiveProjAreaFunc;
    float result = 0;
    switch (drawMode)
    {
    case ABSDFDrawMode::Normal:
        return NDF.getMainNormal(v) * 0.5 + 0.5;
    case ABSDFDrawMode::EllipsoidProjArea:
        result = e.projectArea(v) / PI * 2;
        break;
    case ABSDFDrawMode::Roughness:
        result = ABSDF.NDF.getAverageRoughness();
        break;
    case ABSDFDrawMode::TotalArea:
        result = ABSDF.area;
        break;
    case ABSDFDrawMode::EllipsoidCenter:
        return e.center;
    case ABSDFDrawMode::PolygonsProjArea:
        result = polygonsProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::TotalProjArea:
        result = voxelData.totalProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::PrimitiveProjArea:
        result = primitiveProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::Coverage:
        result = polygonsProjAreaFunc.calc(v) / primitiveProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::InternalVisibility:
        return voxelData.calcVisibility(v);
    default:
        break;
    }
    return valueToColor(result);
}

float3 shading(uint offset, float3 v, float3 l, float3 lightColor)
{
    if (isTransmition(l, v))
        return lightColor;

    VoxelData voxelData = gBuffer[offset];
    ABSDF ABSDF = voxelData.ABSDF;
    float3 specular = ABSDF.specular;
    float3 diffuse = ABSDF.diffuse;
    NDF NDF = ABSDF.NDF;

#if CHECK_VISIBILITY
    float visibility = voxelData.calcVisibility(l);
#else
    float visibility = 1.f;
#endif
    if (visibility == 0)
        return 0;

    float3 h = normalize(l + v);
    float3 diffuseColor = lightColor * weightedDiffuseCos(NDF, l, v, h, diffuse);
    float3 specularColor = lightColor * weightedCookTorrenceCos(NDF, l, v, h, specular);
    float3 result = 0;
    switch (drawMode)
    {
    case ABSDFDrawMode::Default:
        result = diffuseColor + specularColor;
        break;
    case ABSDFDrawMode::Diffuse:
        result = diffuseColor;
        break;
    case ABSDFDrawMode::Specular:
        result = specularColor;
        break;
    default:
        break;
    }
    return result;
}

float3 shadingDirect(HitResult hit, uint offset, float3 v, LightData light)
{
    float3 posW = gridMin + hit.cell * voxelSize;
    float3 l;
    float3 lightColor = 0;
    float maxDistance = -1;

    switch (light.type)
    {
    case LightType::Point:
        l = normalize(light.posW - posW);
        maxDistance = length((light.posW - posW) / voxelSize);
        break;
    case LightType::Directional:
        l = -light.dirW;
        break;
    }

    float visibility = calcVisibility(hit, l, maxDistance);

    if (visibility == 0)
        return 0;

    switch (light.type)
    {
    case LightType::Point:
        float3 toL = light.posW - posW;
        float sqrDistance = max(dot(toL, toL), 1e-4f);

        float spot = 1.0f;
        if (light.openingAngle < PI)
        {
            float cosTerm = dot(light.dirW, -l);
            float cosOuter = light.cosOpeningAngle;
            float innerAng = max(light.openingAngle - light.penumbraAngle, 0.0f);
            float cosInner = cos(innerAng);

            float t = saturate((cosTerm - cosOuter) / max(cosInner - cosOuter, 1e-6f));
            spot = t * t * (3.0f - 2.0f * t);

            if (light.penumbraAngle <= 0.0f)
                spot = (cosTerm >= cosOuter) ? 1.0f : 0.0f;
        }
        lightColor = light.intensity * spot / sqrDistance;
        break;
    case LightType::Directional:
        lightColor = light.intensity;
        break;
    }

    float3 color = shading(offset, v, l, lightColor);
    return visibility * color;
}

float3 shadingDirect(HitResult hit, uint offset, float3 v)
{
    float3 directColor = 0;
    for (uint i = 0; i < scene.lightCount; i++)
    {
        directColor += shadingDirect(hit, offset, v, scene.lights[i]);
    }
    return directColor;
}

float3 shadingGlobal(HitResult hit, float3 v, uint bounce, inout UniformSampleGenerator sg)
{
    // 非递归版本，先计算所有命中点，再倒回来统计
    HitResult[MAX_BOUNCE + 1] hits;
    float3[MAX_BOUNCE + 1] sampleDirections; // 第i个采样方向即第i个体素指向第i+1个体素的方向
    float[MAX_BOUNCE + 1] pdfs;              // 第i个pdf即第i+1个体素对第i个体素的贡献权重
    uint hitCount = bounce + 1;
    bool sampleEnvMap = false;
    hits[0] = hit;
    for (int i = 0; i < bounce; i++)
    {
        uint offset = vBuffer[hits[i].cellInt];
        float3 currentV = i == 0 ? v : -sampleDirections[i - 1];
        sampleDirections[i] = samplePrimitive(gBuffer[offset], currentV, sg, pdfs[i]);

        hits[i + 1] = rayMarching(hits[i].cell, sampleDirections[i], -1, true);
        if (pdfs[i] < minPdf)
        {
            hitCount = i + 1;
            break;
        }
        if (!hits[i + 1].hit)
        {
            sampleEnvMap = true;
            hitCount = i + 1;
            break;
        }
        pdfs[i] = max(pdfs[i], 1e-6);
    }

    float3 reflectLights[MAX_BOUNCE + 1];
    for (int i = hitCount - 1; i >= 0; i--)
    {
        reflectLights[i] = 0;
        HitResult currentHit = hits[i];
        uint currentOffset = vBuffer[currentHit.cellInt];
        float3 currentV = i == 0 ? v : -sampleDirections[i - 1];
        reflectLights[i] += shadingDirect(currentHit, currentOffset, currentV);
#if !NO_ENV_MAP
        if (sampleEnvMap && i == hitCount - 1 && pdfs[i] > 0)
        {
            float3 incidentLight = scene.envMap.eval(sampleDirections[i]);
            reflectLights[i] += shading(currentOffset, currentV, sampleDirections[i], incidentLight) / pdfs[i];
        }
#endif
        if (i < hitCount - 1 && pdfs[i] > 0)
        {
            HitResult nextHit = hits[i + 1];
            uint nextOffset = vBuffer[nextHit.cellInt];
            float3 incidentLight = gBuffer[nextOffset].calcCoverage(sampleDirections[i]) * reflectLights[i + 1];
            reflectLights[i] += shading(currentOffset, currentV, sampleDirections[i], incidentLight) / pdfs[i];
        }
    }
    return reflectLights[0];
}

float2 randomJitter(inout UniformSampleGenerator sg)
{
    float2 jitter = Next2(sg) - 0.5f;
    jitter /= pixelCount;
    return jitter;
}

float4 renderBackground(float3 direction)
{
#if !NO_ENV_MAP
    if (renderBackGround)
    {
        float3 color = scene.envMap.eval(direction);
        return float4(color, 1);
    }
#endif
    return clearColor;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = { };
    uint2 pixel = uint2(texCoord * pixelCount);
    UniformSampleGenerator sg = UniformSampleGenerator(pixel, frameIndex);
    float2 jitter = randomJitter(sg);
    texCoord = saturate(texCoord + jitter);
    float3 from = screenCoordToCell(texCoord, 0);
    float3 to = screenCoordToCell(texCoord, 1);
    float3 delta = to - from;
    float3 direction = normalize(delta); // 网格/世界空间下的方向相同
    psOut.color = renderBackground(direction);

    float2 inOut = clip(float3(0), float3(voxelCount), from, to);
    if (inOut.x < 0)
        return psOut;

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
        case ABSDFDrawMode::Diffuse:
        case ABSDFDrawMode::Specular:
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
