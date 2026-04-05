/*** Mesh-only GBuffer debug visualization and deterministic direct lighting for plan4 Phase1-2. ***/

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
Texture2D<float4> gEmissive;

cbuffer PerFrameCB
{
    float3 gCameraPosW;
    float gDepthRange;
    float3 gKeyLightDirW;
    float gShadowBias;
    float4x4 gInvViewProj;
    uint gViewMode;
    bool gRenderBackground;
};

static const uint kViewModeBaseShading = 0;
static const uint kViewModeDirectOnly = 1;
static const uint kViewModeAlbedo = 2;
static const uint kViewModeNormal = 3;
static const uint kViewModeDepth = 4;
static const uint kViewModeEmissive = 5;
static const uint kViewModeSpecular = 6;
static const uint kViewModeRoughness = 7;

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

float3 screenCoordToWorld(float2 screenCoord, float ndcDepth)
{
    const float4 ndc = float4(2.f * screenCoord.x - 1.f, 1.f - 2.f * screenCoord.y, ndcDepth, 1.f);
    const float4 temp = mul(gInvViewProj, ndc);
    return (temp.xyz / temp.w);
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

float3 evalBaseShading(float3 posW, float3 normalW, float3 viewW, float3 albedo, float3 specular, float roughness, float3 emissive)
{
    const float3 N = safeNormalize(normalW);
    const float3 V = safeNormalize(viewW);
    const float3 L = safeNormalize(-gKeyLightDirW);
    const float3 H = safeNormalize(L + V, N);

    const float nDotL = saturate(dot(N, L));
    const float nDotV = saturate(dot(N, V));
    const float clampedRoughness = clamp(roughness, 0.04f, 1.0f);
    const float specPower = lerp(96.f, 6.f, clampedRoughness);
    const float specWeight = pow(saturate(dot(N, H)), specPower);
    const float rim = pow(1.f - nDotV, 4.f);

    const float3 ambient = albedo * 0.08f;
    const float3 diffuse = albedo * (0.20f + 0.80f * nDotL);
    const float3 specularTerm = specular * specWeight * nDotL * (0.25f + 0.75f * nDotV);
    const float3 rimTerm = albedo * (0.04f * rim);

    return ambient + diffuse + specularTerm + rimTerm + emissive;
}

float3 evalDepth(float3 posW)
{
    const float depth = length(gCameraPosW - posW);
    const float depth01 = 1.f - exp(-depth / max(gDepthRange, 1e-4f));
    return depth01.xxx;
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
    const float3 viewW = gViewW.Load(int3(pixelPos, 0)).xyz;
    const float4 diffuseOpacity = gDiffuseOpacity.Load(int3(pixelPos, 0));
    const float4 specRough = gSpecRough.Load(int3(pixelPos, 0));
    const float3 emissive = gEmissive.Load(int3(pixelPos, 0)).xyz;

    float3 color = 0.f;

    switch (gViewMode)
    {
    case kViewModeDirectOnly:
        color = evalDeterministicDirectLighting(posW.xyz, normalW, faceNormalW, safeNormalize(viewW), diffuseOpacity.rgb, specRough.rgb, specRough.w);
        break;
    case kViewModeAlbedo:
        color = diffuseOpacity.rgb;
        break;
    case kViewModeNormal:
        color = 0.5f * safeNormalize(normalW) + 0.5f;
        break;
    case kViewModeDepth:
        color = evalDepth(posW.xyz);
        break;
    case kViewModeEmissive:
        color = emissive;
        break;
    case kViewModeSpecular:
        color = specRough.rgb;
        break;
    case kViewModeRoughness:
        color = specRough.www;
        break;
    case kViewModeBaseShading:
    default:
        color = evalBaseShading(posW.xyz, normalW, viewW, diffuseOpacity.rgb, specRough.rgb, specRough.w, emissive);
        break;
    }

    return float4(color, 1.f);
}
