#include "VoxelizationShared.slang"
import Scene.SceneTypes;
import Scene.Scene;
import Rendering.Materials.StandardMaterial;

ParameterBlock<Scene> scene;
Texture3D<float4> gDiffuse;
Texture3D<float4> gSpecular;
StructuredBuffer<NDF> gNDFLobes;
StructuredBuffer<Ellipsoid> gEllipsoids;

static const int3 adjacent[7] = {
    int3(0, 0, 0),
    int3(1, 0, 0),
    int3(0, 1, 0),
    int3(0, 0, 1),
    int3(-1, 0, 0),
    int3(0, -1, 0),
    int3(0, 0, -1),
};

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
}

cbuffer CB
{
    uint2 pixelCount;
    float4x4 invVP;
    float visibilityBias;
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

float weightedCos(NDF ndf, float3 direction)
{
    float sum = 0;
    float weightSum = 0;
    for (int i = 0; i < 8; i++)
    {
        float3 n = normalize(ndf.weightedNormals[i].xyz);
        float w = ndf.weightedNormals[i].w;
        if (w > 0)
        {
            float cosTheta = dot(n, direction);
            if (cosTheta > 0)
            {
                sum += cosTheta * w;
                weightSum += w;
            }
        }
    }
    return weightSum > 0 ? sum / weightSum : 0;
}

float2 intersect(float p1, float p2, float p0, float q)
{
    float u1 = (p1 - p0) / q;
    float u2 = (p2 - p0) / q;
    if (u1 > u2)
    {
        float temp = u1;
        u1 = u2;
        u2 = temp;
    }
    return float2(u1, u2);
}
// 应当统一用3D纹理的纹理坐标计算
float2 clip(float3 minPoint, float3 maxPoint, float3 from, float3 to)
{
    float uIn = 0, uOut = 1;
    float3 v = to - from;

    float2 u12 = intersect(minPoint.x, maxPoint.x, from.x, v.x);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    u12 = intersect(minPoint.y, maxPoint.y, from.y, v.y);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    u12 = intersect(minPoint.z, maxPoint.z, from.z, v.z);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    return float2(uIn, uOut);
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

float2 ellipsoidClip(Ellipsoid e, float3 from, float3 to)
{
    float3 v = to - from;
    from -= e.center;
    // quadratic equation
    float a = dot(v, mul(e.shape, v));
    float b = 2.f * dot(v, mul(e.shape, from));
    float c = dot(from, mul(e.shape, from)) - 1.f;
    float d = b * b - 4 * a * c;
    if (d < 0)
        return float2(-1, -1);
    float uIn = 0, uOut = 1;
    float s = sqrt(d);
    if (a >= 0)
    {
        uIn = max(uIn, (-b - s) / 2 / a);
        uOut = min(uOut, (-b + s) / 2 / a);
    }
    else
    {
        uIn = max(uIn, (-b + s) / 2 / a);
        uOut = min(uOut, (-b - s) / 2 / a);
    }
    if (uIn > uOut)
        return float2(-1, -1);
    return float2(uIn, uOut);
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
    float2 inOut = ellipsoidClip(ellipsoid, from, to);
    HitResult result = { inOut.x > 0, cellInt, cell + inOut.x * (to - from) };
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
        float accumulate = gDiffuse[current.cellInt].w;
        if (accumulate > 0)
        {
#if CHECK_ELLIPSOID
            int index = CellToIndex(current.cellInt, voxelCount);
            Ellipsoid ellipsoid = gEllipsoids[index];
            HitResult hit = checkEllipsoid(ellipsoid, current.cell, direction, current.cellInt);
            if (hit.hit)
                return hit;
#else
            current.hit = true;
            current.cell = current.cellInt + 0.5;
            return current;
#endif
        }
        current = leave(current, directions, direction, reciprocal_direction);
        if (any(current.cellInt < 0) || any(current.cellInt >= voxelCount))
            break;
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

float calcVisibility(HitResult hit, float3 direction)
{
    HitResult hit = leave(hit, int3(sign(direction)), direction, 1.0f / direction);
    float3 from = (hit.cell + visibilityBias * direction) / voxelCount;
    hit = rayMarching(from, from + 2 * direction);
    return hit.hit ? 0.f : 1.f;
}

float3 shading(float4 diffuse, float4 specular, NDF ndf, HitResult hit, LightData light)
{
    float3 posW = gridMin + hit.cell * voxelSize;
    float3 l;
    float3 v = normalize(scene.camera.data.posW - posW);
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

    float3 gridDirection = normalize(l / float3(voxelCount));
    float visibility = calcVisibility(hit, gridDirection);
    if (visibility <= 0.f)
        return 0;

    switch (light.type)
    {
    case LightType::Point:
        float3 toL = light.posW - posW;
        float sqrDistance = max(dot(toL, toL), 1e-4f);

        float spot = 1.0f;
        if (light.openingAngle < 3.1415926f)
        {
            float cosTheta = dot(light.dirW, -l);
            float cosOuter = light.cosOpeningAngle;
            float innerAng = max(light.openingAngle - light.penumbraAngle, 0.0f);
            float cosInner = cos(innerAng);

            float t = saturate((cosTheta - cosOuter) / max(cosInner - cosOuter, 1e-6f));
            spot = t * t * (3.0f - 2.0f * t);

            if (light.penumbraAngle <= 0.0f)
                spot = (cosTheta >= cosOuter) ? 1.0f : 0.0f;
        }

        lightColor = light.intensity * spot / sqrDistance;
        break;
    case LightType::Directional:
        lightColor = light.intensity;
        break;
    }
    float cosTerm = weightedCos(ndf, l);
    float3 diffuseColor = lightColor * diffuse.xyz / diffuse.w * cosTerm * visibility;
    return diffuseColor;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = { float4(0) };
    uint2 pixel = uint2(texCoord * pixelCount);
    float3 from = screenCoordToGridCoord(texCoord, 0);
    float3 to = screenCoordToGridCoord(texCoord, 1);

    float2 inOut = clip(float3(0), float3(1), from, to);
    if (inOut.x < 0)
        return psOut;
    float3 v = to - from;
    float3 direction = normalize(v * voxelCount);
    from = from + (inOut.x + 1e-5f) * v; // 避免边界处误差

    HitResult hit = rayMarching(from, to); // to足够远即可
    if (hit.hit)
    {
        int index = CellToIndex(hit.cellInt, voxelCount);
        float4 diffuse = gDiffuse[hit.cellInt];
        float4 specular = gSpecular[hit.cellInt];
        NDF ndf = gNDFLobes[index];
        float3 color = 0;
        for (uint i = 0; i < scene.lightCount; i++)
        {
            color += shading(diffuse, specular, ndf, hit, scene.lights[i]);
        }
        psOut.color = float4(color, 1);
    }

    return psOut;
}
