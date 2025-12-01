#include "Voxel/VoxelGrid.slang"
#include "Voxel/Shading.slang"
#include "VoxelizationShared.slang"
#include "Math/Sampling.slang"
#include "Math/Random.slang"
import Scene.SceneTypes;
import Scene.Scene;
import Rendering.Materials.StandardMaterial;
import Utils.Sampling.UniformSampleGenerator;

ParameterBlock<Scene> scene;
Texture3D<int> vBuffer;
StructuredBuffer<VoxelData> gBuffer;

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
    uint illuminateMode;
    uint frameIndex;
    float transmittanceThreshould;
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

void leave(inout float3 cell, inout int3 cellInt, int3 directions, float3 direction, float3 reciprocal_direction)
{
    float3 border = cellInt + (directions + 1) / 2;
    float3 t = (border - cell) * reciprocal_direction;
    float tMin = 2.0f;
    int3 selectedDirection = 0;
    if (direction.x != 0 && t.x < tMin)
    {
        tMin = t.x;
        selectedDirection = int3(directions.x, 0, 0);
    }
    if (direction.y != 0 && t.y < tMin)
    {
        tMin = t.y;
        selectedDirection = int3(0, directions.y, 0);
    }
    if (direction.z != 0 && t.z < tMin)
    {
        tMin = t.z;
        selectedDirection = int3(0, 0, directions.z);
    }
    cell += tMin * direction;
    cellInt += selectedDirection;
}

HitResult checkEllipsoid(Ellipsoid ellipsoid, float3 cell, float3 direction, int3 cellInt)
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
HitResult rayMarching(float3 from, float3 direction, bool ignoreFirst)
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
        int offset = vBuffer[cellInt];
        if (offset != -1)
        {
#if !CHECK_ELLIPSOID
            HitResult hit = { true, cellInt, cellInt + 0.5f };
            return hit;
#else
            Ellipsoid ellipsoid = gBuffer[offset].ellipsoid;
            HitResult hit = checkEllipsoid(ellipsoid, cell, direction, cellInt);
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

float calcVisibility(HitResult hit, float3 direction)
{
    float3 from = hit.cell + visibilityBias * direction;
    hit = rayMarching(from, direction, true);
    return hit.hit ? 0.f : 1.f;
}

float3 debugShading(HitResult hit, uint offset, float3 v)
{
    VoxelData voxelData = gBuffer[offset];
    ABSDF ABSDF = voxelData.ABSDF;
    NDF NDF = ABSDF.NDF;
    Ellipsoid e = voxelData.ellipsoid;
    SphericalHarmonics polygonsProjAreaFunc = voxelData.polygonsProjAreaFunc;
    SphericalHarmonics primitiveProjAreaFunc = voxelData.primitiveProjAreaFunc;
    float result = 0;
    switch (drawMode)
    {
    case ABSDFDrawMode::EllipsoidProjArea:
        result = e.projectArea(v) / PI * 2;
        break;
    case ABSDFDrawMode::TotalArea:
        result = ABSDF.area;
        break;
    case ABSDFDrawMode::PolygonsProjArea:
        result = polygonsProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::PrimitiveProjArea:
        result = primitiveProjAreaFunc.calc(v);
        break;
    case ABSDFDrawMode::Coverage:
        result = polygonsProjAreaFunc.calc(v) / primitiveProjAreaFunc.calc(v);
        break;
    default:
        break;
    }
    return valueToColor(result);
}

float calcCoverage(HitResult hit, uint offset, float3 v)
{
    VoxelData voxelData = gBuffer[offset];
    float primitiveProjArea = voxelData.primitiveProjAreaFunc.calc(v);
    if (primitiveProjArea <= 0)
        return 1;
    float polygonsProjArea = voxelData.polygonsProjAreaFunc.calc(v);
    return saturate(polygonsProjArea / primitiveProjArea);
}

float3 shading(uint offset, float3 v, float3 l, float3 lightColor)
{
    VoxelData voxelData = gBuffer[offset];
    ABSDF ABSDF = voxelData.ABSDF;
    float area = ABSDF.area; // area必然大于0
    float3 diffuse = ABSDF.diffuse;
    float3 specular = ABSDF.specular;
    float roughness = ABSDF.roughness;
    NDF NDF = ABSDF.NDF;

    float cosTerm = NDF.weightedDot(l, v);
    float3 diffuseColor = lightColor * diffuse * cosTerm;
    float3 specularColor = lightColor * weightedCookTorrence(NDF, l, v, specular, roughness);
    float3 result = 0;
    switch (drawMode)
    {
    case ABSDFDrawMode::Default:
        result = diffuseColor + specularColor;
        break;
    case ABSDFDrawMode::Normal:
        return NDF.getAverageNormal(l) * 0.5 + 0.5;
    case ABSDFDrawMode::Diffuse:
        result = diffuseColor;
        break;
    case ABSDFDrawMode::Specular:
        result = specularColor;
        break;
    case ABSDFDrawMode::Flat:
        result = cosTerm;
        break;
    default:
        break;
    }
    return result / area;
}

float3 shadingDirect(HitResult hit, uint offset, float3 v, LightData light)
{
    float3 posW = gridMin + hit.cell * voxelSize;
    float3 l;
    float3 lightColor = 0;

    switch (light.type)
    {
    case LightType::Point:
        l = normalize(light.posW - posW);
        break;
    case LightType::Directional:
        l = -light.dirW;
        break;
    }

#if CHECK_VISIBILITY
    float visibility = calcVisibility(hit, l);
#else
    float visibility = 1.f;
#endif

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

float2 randomJitter(inout UniformSampleGenerator sg)
{
    float2 jitter = Next2(sg) - 0.5f;
    jitter /= pixelCount;
    return jitter;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = { float4(0) };
    uint2 pixel = uint2(texCoord * pixelCount);
    UniformSampleGenerator sg = UniformSampleGenerator(pixel, frameIndex);
    float2 jitter = randomJitter(sg);
    texCoord = saturate(texCoord + jitter);
    float3 from = screenCoordToCell(texCoord, 0);
    float3 to = screenCoordToCell(texCoord, 1);

    float2 inOut = clip(float3(0), float3(voxelCount), from, to);
    if (inOut.x < 0)
    {
        psOut.color = float4(1, 0, 1, 1);
        return psOut;
    }
    float3 v = to - from;
    float3 direction = normalize(v); // 网格/世界空间下的方向相同
    from = from + inOut.x * v;
    HitResult hit = rayMarching(from, direction, true);

    float transmittance = 1;
    float times = 10;
    while (hit.hit && times > 0)
    {
        times--;
        float3 color = 0;
        float coverage = 1;
        uint offset = vBuffer[hit.cellInt];
        switch (drawMode)
        {
        case ABSDFDrawMode::Default:
        case ABSDFDrawMode::Diffuse:
        case ABSDFDrawMode::Specular:
        case ABSDFDrawMode::Flat:
        case ABSDFDrawMode::Normal:
            coverage = calcCoverage(hit, offset, direction);    //采样线命中图元的条件下，命中整体的概率
            for (uint i = 0; i < scene.lightCount; i++)
            {
                color += shadingDirect(hit, offset, -direction, scene.lights[i]);
            }
            float3 indirectColor = 0;
            float3 sampleDirection = sample_sphere(Next2(sg));
            HitResult subHit = rayMarching(hit.cell, sampleDirection, true);
            if (subHit.hit)
            {
                int subOffset = vBuffer[subHit.cellInt];
                float3 subLightColor = 0;
                for (uint i = 0; i < scene.lightCount; i++)
                {
                    subLightColor += shadingDirect(subHit, subOffset, -sampleDirection, scene.lights[i]);
                }
                subLightColor *= calcCoverage(subHit, subOffset, -sampleDirection); // 采样线命中图元的条件下，命中整体的概率
                indirectColor = shading(offset, -direction, sampleDirection, subLightColor);
            }
            switch(illuminateMode)
            {
            case IlluminateMode::Global:
                color += indirectColor;
                break;
            case IlluminateMode::Indirect:
                color = indirectColor;
                break;
            }
            break;
        default:
            color = debugShading(hit, offset, -direction);
            break;
        }
        float k = transmittance * coverage;
        psOut.color += float4(color * k, k);
        transmittance -= k;

        if (transmittance > transmittanceThreshould)
        {
            hit = rayMarching(hit.cell, direction, true);
        }
        else
        {
            break;
        }
    }

    if (psOut.color.w > 0)
        psOut.color /= psOut.color.w;
    else
        psOut.color = float4(1, 0, 1, 1);
    return psOut;
}
