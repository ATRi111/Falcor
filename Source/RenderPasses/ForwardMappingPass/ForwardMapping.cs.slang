Texture2D<float4> gPackedNDO;   // Impostor记录的世界空间法线、深度、透明度
Texture2D<float4> gPackedMCR;   // Impostor记录的纹理ID 、纹理坐标、粗糙度
RWTexture2D<float4> gMappedNDO; // 映射到GBuffer的世界空间法线、深度、透明度
RWTexture2D<float4> gMappedMCR; // 映射到GBuffer的纹理ID、纹理坐标、粗糙度
RWTexture2D<uint> gTexelLock;

SamplerState gPointSampler;

cbuffer CB
{
    float4x4 GBufferVP;   // GBuffer的观察投影矩阵
    float4x4 invOriginVP; // Impostor的观察投影矩阵的逆矩阵
    uint lowerLevel;
    float t;
    uint width;        // 水平方向的总采样点个数
    uint height;       // 垂直方向的总采样点个数
    uint outputWidth;  // G-Buffer的宽度
    uint outputHeight; // G-Buffer的高度
};

float2 normalToOctoUV(float3 n)
{
    float2 p = n.xy / dot(1, abs(n));
    if (n.z < 0)
        p = (1.0 - abs(p.yx)) * sign(p.xy);
    return p * 0.5 + 0.5;
}
float3 octoUVToNormal(float2 uv)
{
    float2 p = uv * 2 - 1;
    float3 n = float3(p, 1 - dot(1, abs(p)));
    if (n.z < 0)
    {
        n.xy = (1 - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

float4 originCoordToNDC(float2 originCoord, float depth)
{
    float4 originNDC = float4(2 * originCoord.x - 1, 1 - 2 * originCoord.y, depth, 1);
    float4 temp = mul(invOriginVP, originNDC);
    float4 posWorld = temp / temp.w;
    float4 posClip = mul(GBufferVP, posWorld);
    return posClip / posClip.w;
}

float2 originPixelToPixel(float2 originPixel, float depth)
{
    float2 originCoord = float2(originPixel.x / width, originPixel.y / height);
    float4 NDC = originCoordToNDC(originCoord, depth);
    float2 coord = float2(0.5 * NDC.x + 0.5, 0.5 - 0.5 * NDC.y);
    return coord * float2(outputWidth, outputHeight);
}

void forwardMapping(float2 originCoord, float4 higherNDO, float4 higherMCR)
{
    float4 lowerNDO = gPackedNDO.SampleLevel(gPointSampler, originCoord, lowerLevel);
    if (lowerNDO.w == 0)
        return;
    float4 NDC = originCoordToNDC(originCoord, lowerNDO.z);
    lowerNDO.z = NDC.z;
    if (any(NDC.xyz < float3(-1, -1, 0)) || any(NDC.xyz > float3(1, 1, 1)))
        return;

    float2 coord = float2(0.5 * NDC.x + 0.5, 0.5 - 0.5 * NDC.y);
    uint2 pixel = uint2((uint)floor(coord.x * outputWidth), (uint)floor(coord.y * outputHeight));
    float4 NDO;
    float4 MCR;
    float4 lowerMCR = gPackedMCR.SampleLevel(gPointSampler, originCoord, lowerLevel);

    float3 lowerNormal = octoUVToNormal(lowerNDO.xy);
    float3 higherNormal = octoUVToNormal(higherNDO.xy);
    float3 normal = normalize(lerp(lowerNormal, higherNormal, t));
    NDO.xy = normalToOctoUV(normal);
    NDO.z = lerp(lowerNDO.z, higherNDO.z, t);
    NDO.w = lerp(lowerNDO.w, higherNDO.w, t);
    MCR.yzw = lerp(lowerMCR.yzw, higherMCR.yzw, t);
    MCR.x = lowerMCR.x;

#if ENABLE_LOCK
    uint old = 1;
    while (old != 0)
    {
        InterlockedCompareExchange(gTexelLock[pixel], 1u, 0u, old);
    }
#endif
    float4 currentNDO = gMappedNDO[pixel];
    if (currentNDO.w == 0 || NDC.z < currentNDO.z)
    {
        gMappedNDO[pixel] = NDO;
        gMappedMCR[pixel] = MCR;
    }
#if ENABLE_LOCK
    uint dummy;
    InterlockedExchange(gTexelLock[pixel], 0u, dummy);
#endif
}
// 调用次数等于higherLevel的像素数
[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 originPixel = dispatchThreadId.xy;

    float2 originCoord = float2((originPixel.x + 0.5f) / width, (originPixel.y + 0.5f) / height);
    float4 higherNDO = gPackedNDO.SampleLevel(gPointSampler, originCoord, lowerLevel + 1);
    float4 higherMCR = gPackedMCR.SampleLevel(gPointSampler, originCoord, lowerLevel + 1);
    if (higherNDO.w == 0)
        return;

    float4 NDC = originCoordToNDC(originCoord, higherNDO.z);
    if (any(NDC.xyz < float3(-1, -1, 0)) || any(NDC.xyz > float3(1, 1, 1)))
        return;

    higherNDO.z = NDC.z;

    float2[4] subPixelOffset = { float2(0.f, 0.f), float2(0.5f, 0.f), float2(0.f, 0.5f), float2(0.5f, 0.5f) };
    float2[4] superSamplingOffset = { float2(0.05f, 0.15f), float2(0.35f, 0.05f), float2(0.15f, 0.45f), float2(0.45f, 0.35f) };
#if ENABLE_SUPERSAMPLING
    for (uint i = 0; i < 4; i++)
    {
        for (uint j = 0; j < 4; j++)
        {
            float2 p = originPixel + subPixelOffset[i] + superSamplingOffset[j];
            forwardMapping(float2(p.x / width, p.y / height), higherNDO, higherMCR);
        }
    }
#else
    for (uint i = 0; i < 4; i++)
    {
        float2 p = originPixel + subPixelOffset[i] + 0.25f;
        forwardMapping(float2(p.x / width, p.y / height), higherNDO, higherMCR);
    }
#endif
}
