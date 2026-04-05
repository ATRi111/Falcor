/*** Mesh deterministic direct + AO shading pass for plan4 Phase3. ***/

#ifndef USE_ENV_MAP
#define USE_ENV_MAP 0
#endif

import Scene.Scene;
import Scene.SceneTypes;
import Scene.Intersection;
import Scene.RaytracingInline;
import Rendering.Lights.LightHelpers;
import Utils.Geometry.GeometryHelpers;
import Utils.Math.MathHelpers;

Texture2D<float4> gPosW;
Texture2D<float4> gNormW;
Texture2D<float4> gFaceNormalW;
Texture2D<float4> gViewW;
Texture2D<float4> gDiffuseOpacity;
Texture2D<float4> gSpecRough;

cbuffer PerFrameCB
{
    float gShadowBias;
    float4x4 gInvViewProj;
    uint gViewMode;
    bool gRenderBackground;
    bool gAOEnabled;
    float gAOStrength;
    float gAORadius;
    uint gAOStepCount;
    uint gAODirectionSet;
    float gAOContactStrength;
    bool gAOUseStableRotation;
};

static const uint kViewModeCombined = 0;
static const uint kViewModeDirectOnly = 1;
static const uint kViewModeAOOnly = 2;

static const uint kMaxAnalyticLights = 8;
static const float kPi = 3.14159265359f;
static const float kRayDistanceMax = 3.402823466e+38f;

float schlick(float f0, float f90, float cosTheta)
{
    const float t = saturate(1.f - cosTheta);
    const float t2 = t * t;
    return lerp(f0, f90, t2 * t2 * t);
}

float3 schlick3(float3 f0, float3 f90, float cosTheta)
{
    return lerp(f0, f90, schlick(0.f, 1.f, cosTheta));
}

float ggx(float NdotH, float alpha)
{
    const float alpha2 = alpha * alpha;
    const float temp = max(1e-6f, NdotH * NdotH * (alpha2 - 1.f) + 1.f);
    return alpha2 / (kPi * temp * temp);
}

float lambdaTerm(float NdotX, float alpha)
{
    const float safeNdotX = max(NdotX, 1e-6f);
    const float temp = alpha * alpha + (1.f - alpha * alpha) * safeNdotX * safeNdotX;
    return (sqrt(temp) / safeNdotX - 1.f) * 0.5f;
}

float3 safeNormalize(float3 v, float3 fallback = float3(0.f, 0.f, 1.f))
{
    const float len2 = dot(v, v);
    return len2 > 1e-6f ? v * rsqrt(len2) : fallback;
}

float3 orientNormal(float3 normalW, float3 direction)
{
    return dot(normalW, direction) >= 0.f ? normalW : -normalW;
}

uint hashCell(int3 cellInt)
{
    uint seed = asuint(cellInt.x) * 73856093u;
    seed ^= asuint(cellInt.y) * 19349663u;
    seed ^= asuint(cellInt.z) * 83492791u;
    seed ^= seed >> 16;
    seed *= 2246822519u;
    seed ^= seed >> 13;
    seed *= 3266489917u;
    seed ^= seed >> 16;
    return seed;
}

float hashToUnitFloat(uint seed)
{
    return float(seed) * (1.0f / 4294967295.0f);
}

int3 quantizeStableCell(float3 posW)
{
    const float cellSize = max(gAORadius * 0.5f, 0.05f);
    return int3(floor(posW / cellSize));
}

void buildShadingBasis(float3 mainNormal, out float3 tangent, out float3 bitangent)
{
    float3 up = abs(mainNormal.z) < 0.999f ? float3(0, 0, 1) : float3(0, 1, 0);
    tangent = normalizeSafe(cross(up, mainNormal));
    if (dot(tangent, tangent) < 1e-6f)
        tangent = float3(1, 0, 0);
    bitangent = normalizeSafe(cross(mainNormal, tangent));
}

void applyStableRotation(inout float3 tangent, inout float3 bitangent, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    float3 rotatedTangent = c * tangent + s * bitangent;
    float3 rotatedBitangent = c * bitangent - s * tangent;
    tangent = rotatedTangent;
    bitangent = rotatedBitangent;
}

float3 screenCoordToWorld(float2 screenCoord, float ndcDepth)
{
    const float4 ndc = float4(2.f * screenCoord.x - 1.f, 1.f - 2.f * screenCoord.y, ndcDepth, 1.f);
    const float4 temp = mul(gInvViewProj, ndc);
    return temp.xyz / temp.w;
}

float3 getCameraRayDir(float2 texCoord)
{
    const float3 from = screenCoordToWorld(texCoord, 0.f);
    const float3 to = screenCoordToWorld(texCoord, 1.f);
    return safeNormalize(to - from);
}

float4 renderMissBackground(float3 direction)
{
#if USE_ENV_MAP
    if (gRenderBackground)
        return float4(gScene.envMap.eval(direction), 1.f);
#endif

    if (!gRenderBackground)
        return float4(0.f, 0.f, 0.f, 1.f);

    const float t = saturate(direction.y * 0.5f + 0.5f);
    const float3 horizonColor = float3(0.08f, 0.09f, 0.11f);
    const float3 zenithColor = float3(0.26f, 0.29f, 0.35f);
    return float4(lerp(horizonColor, zenithColor, t), 1.f);
}

float3 evalVoxelStyleBRDF(float3 normalW, float3 diffuse, float3 specular, float roughness, float3 lightDir, float3 viewDir)
{
    const float3 n = orientNormal(safeNormalize(normalW), viewDir);
    const float3 l = lightDir;
    const float3 v = viewDir;
    const float3 h = safeNormalize(l + v, n);

    const float NdotL = dot(n, l);
    const float NdotV = dot(n, v);
    const float NdotH = dot(n, h);
    if (NdotL <= 0.f || NdotV <= 0.f || NdotH <= 0.f)
        return 0.f;

    const float safeRoughness = max(roughness, 0.01f);
    const float alpha = safeRoughness * safeRoughness;
    const float VdotH = saturate(dot(v, h));

    const float energyBias = lerp(0.f, 0.5f, safeRoughness);
    const float energyFactor = lerp(1.f, 1.f / 1.51f, safeRoughness);
    const float fd90 = energyBias + 2.f * VdotH * VdotH * safeRoughness;
    const float wiScatter = schlick(1.f, fd90, NdotL);
    const float woScatter = schlick(1.f, fd90, NdotV);
    const float3 diffuseTerm = wiScatter * woScatter * energyFactor * diffuse / kPi * NdotL;

    const float3 fresnel = schlick3(specular, float3(1.f), VdotH);
    const float3 specularTerm = ggx(NdotH, alpha) * fresnel / (1.f + lambdaTerm(NdotL, alpha) + lambdaTerm(NdotV, alpha)) / 4.f / max(1e-6f, NdotV);

    return diffuseTerm + specularTerm;
}

bool traceLightVisibility(float3 posW, float3 faceNormalW, float3 lightDir, float lightDistance)
{
    const float3 offsetNormal = orientNormal(safeNormalize(faceNormalW), lightDir);
    const float3 origin = computeRayOrigin(posW + offsetNormal * gShadowBias, offsetNormal);
    const float maxDistance = lightDistance < kRayDistanceMax ? max(lightDistance - gShadowBias, 0.f) : kRayDistanceMax;

    SceneRayQuery<1> sceneRayQuery;
    return sceneRayQuery.traceVisibilityRay(Ray(origin, lightDir, 0.f, maxDistance));
}

bool traceAOHit(float3 posW, float3 faceNormalW, float3 rayDir, float maxDistance, out float hitT)
{
    hitT = 0.f;
    const float safeDistance = max(maxDistance - gShadowBias, 0.f);
    if (safeDistance <= 0.f)
        return false;

    const float3 offsetNormal = orientNormal(safeNormalize(faceNormalW), rayDir);
    const float3 origin = computeRayOrigin(posW + offsetNormal * gShadowBias, offsetNormal);

    SceneRayQuery<1> sceneRayQuery;
    HitInfo hit = sceneRayQuery.traceRay(Ray(origin, rayDir, 0.f, safeDistance), hitT);
    return hit.isValid();
}

float evalProbeOcclusion(float3 posW, float3 faceNormalW, float3 direction, float maxDistance)
{
    const float safeRadius = max(maxDistance, 1e-3f);
    float hitT = 0.f;
    if (!traceAOHit(posW, faceNormalW, direction, safeRadius, hitT))
        return 0.f;

    const uint stepCount = max(gAOStepCount, 1u);
    const float stepLength = safeRadius / float(stepCount);
    const float hitStep = ceil(hitT / max(stepLength, 1e-4f));
    const float distanceWeight = 1.f - (max(hitStep, 1.f) - 1.f) / float(stepCount);
    return saturate(distanceWeight);
}

float evalContactAO(float3 posW, float3 mainNormal, float3 faceNormalW, float3 tangent, float3 bitangent)
{
    const float contactRadius = clamp(gAORadius * 0.35f, 0.03f, 0.15f);
    float occlusion = 0.0f;

    [unroll]
    for (uint sampleIndex = 0; sampleIndex < 4; ++sampleIndex)
    {
        float azimuth = (float(sampleIndex) + 0.5f) * (kPi * 0.5f);
        float3 lateral = cos(azimuth) * tangent + sin(azimuth) * bitangent;
        float3 probeDir = normalizeSafe(mainNormal * 1.15f + lateral);
        if (dot(probeDir, probeDir) > 0.0f)
            occlusion += evalProbeOcclusion(posW, faceNormalW, probeDir, contactRadius);
    }

    float meanOcclusion = occlusion * 0.25f;
    return saturate(1.0f - gAOContactStrength * meanOcclusion);
}

float evalMacroAO(float3 posW, float3 mainNormal, float3 faceNormalW, float3 tangent, float3 bitangent)
{
    const uint directionCount = gAODirectionSet >= 6 ? 6u : 4u;
    float occlusion = 0.0f;

    [loop]
    for (uint sampleIndex = 0; sampleIndex < directionCount; ++sampleIndex)
    {
        float azimuth = (2.0f * kPi) * (float(sampleIndex) + 0.5f) / float(directionCount);
        float3 lateral = cos(azimuth) * tangent + sin(azimuth) * bitangent;
        float3 probeDir = normalizeSafe(mainNormal * 1.35f + 0.75f * lateral);
        occlusion += evalProbeOcclusion(posW, faceNormalW, probeDir, gAORadius);
    }

    return saturate(1.0f - occlusion / float(directionCount));
}

float evalStableAO(float3 posW, float3 mainNormal, float3 faceNormalW)
{
    if (!gAOEnabled || gAOStrength <= 0.0f || gAORadius <= 0.0f)
        return 1.0f;

    float3 tangent;
    float3 bitangent;
    buildShadingBasis(mainNormal, tangent, bitangent);

    if (gAOUseStableRotation)
    {
        float stableAngle = (2.0f * kPi) * hashToUnitFloat(hashCell(quantizeStableCell(posW)));
        applyStableRotation(tangent, bitangent, stableAngle);
    }

    float contactAO = evalContactAO(posW, mainNormal, faceNormalW, tangent, bitangent);
    float macroAO = evalMacroAO(posW, mainNormal, faceNormalW, tangent, bitangent);
    return lerp(1.0f, contactAO * macroAO, saturate(gAOStrength));
}

float3 evalDeterministicDirectLighting(
    float3 posW,
    float3 normalW,
    float3 faceNormalW,
    float3 viewDir,
    float3 diffuse,
    float3 specular,
    float roughness
)
{
    float3 result = 0.f;
    uint supportedLightCount = 0;
    const uint lightCount = min(gScene.getLightCount(), (uint)kMaxAnalyticLights);

    [loop]
    for (uint i = 0; i < lightCount; ++i)
    {
        AnalyticLightSample ls = {};
        if (!evalLightApproximate(posW, gScene.getLight(i), ls))
            continue;

        supportedLightCount++;

        if (!traceLightVisibility(posW, faceNormalW, ls.dir, ls.distance))
            continue;

        result += ls.Li * evalVoxelStyleBRDF(normalW, diffuse, specular, roughness, ls.dir, viewDir);
    }

    bool hasStableDirectTerm = supportedLightCount > 0;

#if USE_ENV_MAP
    const float3 envDir = orientNormal(safeNormalize(normalW), viewDir);
    const float3 envColor = gScene.envMap.eval(envDir);
    if (any(envColor > 0.f))
    {
        result += envColor * evalVoxelStyleBRDF(normalW, diffuse, specular, roughness, envDir, viewDir);
        hasStableDirectTerm = true;
    }
#endif

    if (!hasStableDirectTerm)
    {
        const float3 skyDir = safeNormalize(float3(0.3f, 1.f, 0.2f));
        const float3 ambientNormal = orientNormal(safeNormalize(normalW), skyDir);
        const float NdotL = saturate(dot(ambientNormal, skyDir));
        const float ambient = 0.05f;
        result = (NdotL + ambient) * evalVoxelStyleBRDF(normalW, diffuse, specular, roughness, skyDir, viewDir);
    }

    return result;
}

float4 main(float2 texCoord : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    const int2 pixelPos = int2(pos.xy);
    const float4 posW = gPosW.Load(int3(pixelPos, 0));
    const float3 rayDir = getCameraRayDir(texCoord);

    if (posW.w <= 0.f)
        return renderMissBackground(rayDir);

    const float3 normalW = gNormW.Load(int3(pixelPos, 0)).xyz;
    const float3 faceNormalW = gFaceNormalW.Load(int3(pixelPos, 0)).xyz;
    const float3 viewW = safeNormalize(gViewW.Load(int3(pixelPos, 0)).xyz);
    const float4 diffuseOpacity = gDiffuseOpacity.Load(int3(pixelPos, 0));
    const float4 specRough = gSpecRough.Load(int3(pixelPos, 0));
    const float3 mainNormal = orientNormal(safeNormalize(normalW), viewW);
    const float ao = evalStableAO(posW.xyz, mainNormal, faceNormalW);

    float3 color = 0.f;

    switch (gViewMode)
    {
    case kViewModeDirectOnly:
        color = evalDeterministicDirectLighting(posW.xyz, mainNormal, faceNormalW, viewW, diffuseOpacity.rgb, specRough.rgb, specRough.w);
        break;
    case kViewModeAOOnly:
        color = pow(saturate(ao), 12.0f).xxx;
        break;
    case kViewModeCombined:
    default:
        color = evalDeterministicDirectLighting(posW.xyz, mainNormal, faceNormalW, viewW, diffuseOpacity.rgb, specRough.rgb, specRough.w) * ao;
        break;
    }

    return float4(color, 1.f);
}
