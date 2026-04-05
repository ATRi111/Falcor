/*** Hybrid mesh/voxel composition for plan4 Phase4. ***/

import Scene.Scene;
import Scene.HitInfo;
import Scene.SceneTypes;

Texture2D<float4> gMeshColor;
Texture2D<float4> gVoxelColor;
Texture2D<float4> gBlendMask;
Texture2D<PackedHitInfo> gVBuffer;

cbuffer PerFrameCB
{
    uint gViewMode;
};

static const uint kViewModeComposite = 0;
static const uint kViewModeMeshOnly = 1;
static const uint kViewModeVoxelOnly = 2;
static const uint kViewModeBlendMask = 3;
static const uint kViewModeRouteDebug = 4;

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
    case kViewModeComposite:
    default:
        color = compositeColor;
        break;
    }

    return float4(color, 1.f);
}
