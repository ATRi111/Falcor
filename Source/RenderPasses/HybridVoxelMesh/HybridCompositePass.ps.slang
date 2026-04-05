/*** Hybrid mesh/voxel composition for plan4 Phase4. ***/

import Scene.Scene;
import Scene.HitInfo;
import Scene.SceneTypes;
import Utils.Math.MathHelpers;

Texture2D<float4> gMeshColor;
Texture2D<float4> gVoxelColor;
Texture2D<float4> gBlendMask;
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float> gVoxelDepth;
Texture2D<float4> gVoxelNormal;
Texture2D<float> gVoxelConfidence;
Texture2D<uint> gVoxelInstanceID;

cbuffer PerFrameCB
{
    uint gViewMode;
};

static const uint kViewModeComposite = 0;
static const uint kViewModeMeshOnly = 1;
static const uint kViewModeVoxelOnly = 2;
static const uint kViewModeBlendMask = 3;
static const uint kViewModeRouteDebug = 4;
static const uint kViewModeVoxelDepth = 5;
static const uint kViewModeVoxelNormal = 6;
static const uint kViewModeVoxelConfidence = 7;
static const uint kViewModeVoxelRouteID = 8;
static const uint kViewModeVoxelInstanceID = 9;
static const uint kInvalidVoxelInstanceID = 0xffffffffu;

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

float3 safeNormalizeDebug(float3 value)
{
    const float len2 = dot(value, value);
    return len2 > 1e-6f ? value * rsqrt(len2) : 0.f;
}

float getVoxelConfidence(int2 pixelPos)
{
    return saturate(gVoxelConfidence.Load(int3(pixelPos, 0)));
}

bool getVoxelIdentity(int2 pixelPos, out uint instanceID, out float confidence)
{
    confidence = getVoxelConfidence(pixelPos);
    instanceID = gVoxelInstanceID.Load(int3(pixelPos, 0));
    return instanceID != kInvalidVoxelInstanceID && confidence > 0.f;
}

float3 evalRouteDebugColor(int2 pixelPos, float3 compositeColor)
{
    const HitInfo hit = HitInfo(gVBuffer.Load(int3(pixelPos, 0)));
    if (!hit.isValid())
        return compositeColor;

    const GeometryInstanceRenderRoute route = gScene.getGeometryInstanceRenderRoute(hit.getInstanceID());
    const float luma = dot(compositeColor, float3(0.299f, 0.587f, 0.114f));
    const float3 routeColor = getRouteDebugColor(route);
    return lerp(saturate(luma).xxx * 0.25f, routeColor, 0.85f);
}

float3 evalBlendMaskDebugColor(int2 pixelPos, float meshWeight)
{
    const HitInfo hit = HitInfo(gVBuffer.Load(int3(pixelPos, 0)));
    if (!hit.isValid())
        return meshWeight.xxx;

    const GeometryInstanceRenderRoute route = gScene.getGeometryInstanceRenderRoute(hit.getInstanceID());
    switch (route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        return getRouteDebugColor(route);
    case GeometryInstanceRenderRoute::VoxelOnly:
        return getRouteDebugColor(route);
    case GeometryInstanceRenderRoute::Blend:
    default:
        return lerp(float3(0.05f, 0.16f, 0.08f), getRouteDebugColor(route), meshWeight);
    }
}

float3 evalVoxelDepthDebugColor(int2 pixelPos)
{
    const float depth = gVoxelDepth.Load(int3(pixelPos, 0));
    if (depth <= 0.f)
        return 0.f;

    const float mappedDepth = 1.f - exp(-depth / 6.f);
    return mappedDepth.xxx;
}

float3 evalVoxelNormalDebugColor(int2 pixelPos)
{
    const float confidence = getVoxelConfidence(pixelPos);
    if (confidence <= 0.f)
        return 0.f;

    const float3 normal = safeNormalizeDebug(gVoxelNormal.Load(int3(pixelPos, 0)).xyz);
    return normal * 0.5f + 0.5f;
}

float3 evalVoxelConfidenceDebugColor(int2 pixelPos)
{
    const float confidence = getVoxelConfidence(pixelPos);
    return lerp(float3(0.14f, 0.05f, 0.03f), float3(0.20f, 0.94f, 0.38f), confidence);
}

float3 evalVoxelRouteDebugColor(int2 pixelPos)
{
    uint instanceID = kInvalidVoxelInstanceID;
    float confidence = 0.f;
    if (!getVoxelIdentity(pixelPos, instanceID, confidence))
        return 0.f;

    const GeometryInstanceID geometryInstanceID = { instanceID };
    const float3 routeColor = getRouteDebugColor(gScene.getGeometryInstanceRenderRoute(geometryInstanceID));
    return lerp(float3(0.08f, 0.08f, 0.08f), routeColor, max(confidence, 0.25f));
}

float3 hashInstanceColor(uint instanceID)
{
    float3 p = frac(float(instanceID) * float3(0.1031f, 0.11369f, 0.13787f));
    p += dot(p, p.yzx + 19.19f);
    return frac((p.xxy + p.yzz) * p.zyx);
}

float3 evalVoxelInstanceDebugColor(int2 pixelPos)
{
    uint instanceID = kInvalidVoxelInstanceID;
    float confidence = 0.f;
    if (!getVoxelIdentity(pixelPos, instanceID, confidence))
        return 0.f;

    return lerp(float3(0.06f, 0.06f, 0.06f), hashInstanceColor(instanceID), max(confidence, 0.25f));
}

float4 main(float2 texCoord : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    const int2 pixelPos = int2(pos.xy);
    const float4 meshColor = gMeshColor.Load(int3(pixelPos, 0));
    const float4 voxelColor = gVoxelColor.Load(int3(pixelPos, 0));
    const float meshWeight = saturate(gBlendMask.Load(int3(pixelPos, 0)).x);
    const float3 compositeColor = lerp(voxelColor.rgb, meshColor.rgb, meshWeight);

    float3 color = 0.f;
    switch (gViewMode)
    {
    case kViewModeMeshOnly:
        color = meshColor.rgb;
        break;
    case kViewModeVoxelOnly:
        color = voxelColor.rgb;
        break;
    case kViewModeBlendMask:
        color = evalBlendMaskDebugColor(pixelPos, meshWeight);
        break;
    case kViewModeRouteDebug:
        color = evalRouteDebugColor(pixelPos, compositeColor);
        break;
    case kViewModeVoxelDepth:
        color = evalVoxelDepthDebugColor(pixelPos);
        break;
    case kViewModeVoxelNormal:
        color = evalVoxelNormalDebugColor(pixelPos);
        break;
    case kViewModeVoxelConfidence:
        color = evalVoxelConfidenceDebugColor(pixelPos);
        break;
    case kViewModeVoxelRouteID:
        color = evalVoxelRouteDebugColor(pixelPos);
        break;
    case kViewModeVoxelInstanceID:
        color = evalVoxelInstanceDebugColor(pixelPos);
        break;
    case kViewModeComposite:
    default:
        color = compositeColor;
        break;
    }

    return float4(color, 1.f);
}
