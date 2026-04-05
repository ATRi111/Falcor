/*** Distance-based hybrid mesh weight mask for plan4 Phase4. ***/

Texture2D<float4> gPosW;

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

float4 main(float2 texCoord : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    const int2 pixelPos = int2(pos.xy);
    const float4 posW = gPosW.Load(int3(pixelPos, 0));
    const float meshWeight = posW.w > 0.f ? evalBlendWeight(posW.xyz) : 0.f;
    return float4(meshWeight.xxx, 1.f);
}
