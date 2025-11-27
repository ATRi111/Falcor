#include "Voxel/VoxelGrid.slang"
#include "VoxelizationShared.slang"
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
    uint gDrawMode;
    uint gFrameIndex;
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

float ggx(float3 n, float3 h, float rough)
{
    float rough2 = rough * rough;
    float temp = dot(n, h) * dot(n, h) * (rough2 - 1) + 1;
    return rough2 / PI / temp / temp;
}
float3 fresnel(float3 v, float3 h, float3 spec)
{
    return spec + (1 - spec) * pow(1 - dot(v, h), 5);
}
float masking(float3 n, float3 x, float rough)
{
    float k = (rough + 1) * (rough + 1) / 8;
    float temp = dot(n, x);
    return temp / (temp * (1 - k) + k);
}
float3 cookTorrence(float3 l, float3 v, float3 h, float3 n, float3 spec, float rough)
{
    float3 specColor = ggx(n, h, rough) * fresnel(v, h, spec) * masking(n, v, rough) * masking(n, l, rough) / 4 / max(1e-4, dot(n, v));
    return specColor;
}
float3 weightedCookTorrence(NDF NDF, float3 l, float3 v, float3 spec, float rough)
{
    float3 sum = 0;
    for (int i = 0; i < LOBE_COUNT; i++)
    {
        float w = NDF.weightedNormals[i].w;
        if (w > 0)
        {
            float3 n = NDF.weightedNormals[i].xyz;
            float cosTerm = dot(n, l);
            if (cosTerm < 0)
                n = -n;
            cosTerm = dot(n, v);
            if (cosTerm <= 0)
                continue;
            float3 h = normalize(l + v);
            sum += cookTorrence(l, v, h, n, spec, rough) * w;
        }
    }
    return sum; // 未归一化
}

HitResult leave(HitResult current, int3 directions, float3 direction, float3 reciprocal_direction)
{
    float3 border = current.cellInt + (directions + 1) / 2;
    float3 t = (border - current.cell) * reciprocal_direction;
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
    current.cell += tMin * direction;
    current.cellInt += selectedDirection;
    return current;
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

// 统一用3D纹理坐标表示
HitResult rayMarching(float3 from, float3 to)
{
    HitResult current = { false, int3(from * voxelCount), from * voxelCount };
    float3 v = to - from;
    float3 direction = normalize(v * voxelCount);

    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));

    uint maxTimes = voxelCount.x + voxelCount.y + voxelCount.z;
    for (uint i = 0; i < maxTimes; i++)
    {
        if (any(current.cellInt < 0) || any(current.cellInt >= voxelCount))
            break;
        int offset = vBuffer[current.cellInt];
        if (offset != -1)
        {
#if !CHECK_ELLIPSOID
            current.hit = true;
            current.cell = current.cellInt + 0.5;
            return current;
#endif
            Ellipsoid ellipsoid = gBuffer[offset].ellipsoid;
            HitResult hit = checkEllipsoid(ellipsoid, current.cell, direction, current.cellInt);
            if (hit.hit)
                return hit;
        }
        current = leave(current, directions, direction, reciprocal_direction);
    }
    return current;
}

float3 screenCoordToGridCoord(float2 screenCoord, float NDCDepth)
{
    float4 NDC = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, NDCDepth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posWorld = temp / temp.w;
    float3 cell = (posWorld.xyz - gridMin) / voxelSize;
    return cell / voxelCount;
}

float calcVisibility(HitResult hit, float3 dirW)
{
    float3 from = (hit.cell + visibilityBias * dirW) / voxelCount;
    float3 direction = normalize(dirW / voxelCount);
    hit = rayMarching(from, from + 2 * direction);
    return hit.hit ? 0.f : 1.f;
}

float3 debugShading(HitResult hit, float3 v)
{
    int index = CellToIndex(hit.cellInt, voxelCount);
    uint offset = vBuffer[hit.cellInt];
    VoxelData voxelData = gBuffer[offset];
    ABSDF ABSDF = voxelData.ABSDF;
    NDF NDF = ABSDF.NDF;
    Ellipsoid e = voxelData.ellipsoid;
    SphericalHarmonics polygonsProjAreaFunc = voxelData.polygonsProjAreaFunc;
    SphericalHarmonics primitiveProjAreaFunc = voxelData.primitiveProjAreaFunc;
    float result = 0;
    switch (gDrawMode)
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

float3 shading(HitResult hit, float3 v, LightData light)
{
    int index = CellToIndex(hit.cellInt, voxelCount);
    uint offset = vBuffer[hit.cellInt];
    VoxelData voxelData = gBuffer[offset];
    ABSDF ABSDF = voxelData.ABSDF;
    float3 diffuse = ABSDF.diffuse;
    float3 specular = ABSDF.specular;
    float roughness = ABSDF.roughness;
    float area = ABSDF.area;
    NDF NDF = ABSDF.NDF;

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
    float cosTerm = NDF.weightedDot(l);
    float3 diffuseColor = lightColor * diffuse * cosTerm;
    float3 specularColor = lightColor * weightedCookTorrence(NDF, l, v, specular, roughness);
    float3 result = 0;
    float projectArea = 0;
    switch (gDrawMode)
    {
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
        result = diffuseColor + specularColor;
        break;
    }
    return visibility * result / area;
}

float2 randomJitter(inout UniformSampleGenerator sg)
{
    float x = float((sg.next() >> 8) & 0x00FFFFFFu) / 16777216 - 0.5;
    float y = float((sg.next() >> 8) & 0x00FFFFFFu) / 16777216 - 0.5;
    float2 jitter = float2(x, y);
    jitter /= pixelCount;
    return jitter;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = { float4(1, 0, 1, 1) };
    uint2 pixel = uint2(texCoord * pixelCount);
    UniformSampleGenerator sg = UniformSampleGenerator(pixel, gFrameIndex);
    float2 jitter = randomJitter(sg);
    texCoord += jitter;
    float3 from = screenCoordToGridCoord(texCoord, 0);
    float3 to = screenCoordToGridCoord(texCoord, 1);

    float2 inOut = clip(float3(0), float3(1), from, to);
    if (inOut.x < 0)
        return psOut;
    float3 v = to - from;
    float3 direction = normalize(v * voxelCount); // 网格/世界空间下的方向
    from = from + (inOut.x + 1e-5f) * v;          // 避免边界处误差

    HitResult hit = rayMarching(from, to); // to足够远即可
    if (hit.hit)
    {
        float3 color = 0;
        float coverage = 1;
        switch (gDrawMode)
        {
        case ABSDFDrawMode::Default:
        case ABSDFDrawMode::Diffuse:
        case ABSDFDrawMode::Specular:
        case ABSDFDrawMode::Flat:
            for (uint i = 0; i < scene.lightCount; i++)
            {
                color += shading(hit, -direction, scene.lights[i]);
            }
            break;
        default:
            color = debugShading(hit, -direction);
            break;
        }
        
        psOut.color = float4(color, 1);
    }

    return psOut;
}
