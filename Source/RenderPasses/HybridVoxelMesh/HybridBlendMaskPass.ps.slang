/*** Route-aware hybrid mesh weight mask for plan5 Phase2. ***/

import Scene.Scene;
import Scene.HitInfo;
import Scene.SceneTypes;

Texture2D<float4> gPosW;
Texture2D<PackedHitInfo> gVBuffer;

cbuffer PerFrameCB
{
    float3 gCameraPosW;
    float gBlendStartDistance;
    float gBlendEndDistance;
    float gBlendExponent;
};

float evalBlendWeight(float3 posW)
{
    const float distanceToCamera = length(gCameraPosW - posW);
    const float blendWidth = gBlendEndDistance - gBlendStartDistance;

    if (blendWidth <= 1e-4f)
        return distanceToCamera <= gBlendStartDistance ? 1.f : 0.f;

    float t = saturate((distanceToCamera - gBlendStartDistance) / blendWidth);
    t = t * t * (3.f - 2.f * t);
    return pow(saturate(1.f - t), gBlendExponent);
}

float evalMeshWeight(int2 pixelPos, float4 posW)
{
    if (posW.w <= 0.f)
        return 0.f;

    const HitInfo hit = HitInfo(gVBuffer.Load(int3(pixelPos, 0)));
    if (!hit.isValid())
        return 0.f;

    const GeometryInstanceRenderRoute route = gScene.getGeometryInstanceRenderRoute(hit.getInstanceID());
    switch (route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        return 1.f;
    case GeometryInstanceRenderRoute::VoxelOnly:
        return 0.f;
    case GeometryInstanceRenderRoute::Blend:
    default:
        return evalBlendWeight(posW.xyz);
    }
}

float4 main(float2 texCoord : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    const int2 pixelPos = int2(pos.xy);
    const float4 posW = gPosW.Load(int3(pixelPos, 0));
    const float meshWeight = evalMeshWeight(pixelPos, posW);
    return float4(meshWeight.xxx, 1.f);
}
