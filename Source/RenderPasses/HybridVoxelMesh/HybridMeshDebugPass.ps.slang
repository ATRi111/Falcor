/*** Mesh-only GBuffer debug visualization for plan4 Phase1-3. ***/

#ifndef USE_ENV_MAP
#define USE_ENV_MAP 0
#endif

import Scene.Scene;
import Scene.HitInfo;
import Scene.SceneTypes;
import Utils.Math.MathHelpers;

Texture2D<float4> gPosW;
Texture2D<float4> gNormW;
Texture2D<float4> gFaceNormalW;
Texture2D<float4> gViewW;
Texture2D<float4> gDiffuseOpacity;
Texture2D<float4> gSpecRough;
Texture2D<float4> gEmissive;
Texture2D<PackedHitInfo> gVBuffer;

cbuffer PerFrameCB
{
    float3 gCameraPosW;
    float gDepthRange;
    float3 gKeyLightDirW;
    float4x4 gInvViewProj;
    uint gViewMode;
    bool gRenderBackground;
};

static const uint kViewModeBaseShading = 0;
static const uint kViewModeAlbedo = 1;
static const uint kViewModeNormal = 2;
static const uint kViewModeDepth = 3;
static const uint kViewModeEmissive = 4;
static const uint kViewModeSpecular = 5;
static const uint kViewModeRoughness = 6;
static const uint kViewModeRouteDebug = 7;

static const float kPi = 3.14159265359f;

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

float3 getRouteDebugColor(GeometryInstanceRenderRoute route)
{
    switch (route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        return float3(1.00f, 0.36f, 0.12f);
    case GeometryInstanceRenderRoute::VoxelOnly:
        return float3(0.12f, 0.68f, 1.00f);
    case GeometryInstanceRenderRoute::Blend:
    default:
        return float3(0.22f, 0.94f, 0.38f);
    }
}

float3 evalRouteDebug(int2 pixelPos)
{
    const HitInfo hit = HitInfo(gVBuffer.Load(int3(pixelPos, 0)));
    if (!hit.isValid())
        return 0.f;

    return getRouteDebugColor(gScene.getGeometryInstanceRenderRoute(hit.getInstanceID()));
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
    case kViewModeRouteDebug:
        color = evalRouteDebug(pixelPos);
        break;
    case kViewModeBaseShading:
    default:
        color = evalBaseShading(posW.xyz, normalW, viewW, diffuseOpacity.rgb, specRough.rgb, specRough.w, emissive);
        break;
    }

    return float4(color, 1.f);
}
