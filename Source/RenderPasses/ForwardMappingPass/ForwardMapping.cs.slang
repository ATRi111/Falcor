Texture2D<float4> gPackedNDO;   // Impostor记录的世界空间法线、深度、透明度
Texture2D<float4> gPackedMCR;   // Impostor记录的纹理ID 、纹理坐标、粗糙度
RWTexture2D<float4> gMappedNDO; // 映射到GBuffer的世界空间法线、深度、透明度
RWTexture2D<float4> gMappedMCR; // 映射到GBuffer的纹理ID、纹理坐标、粗糙度
RWTexture2D<uint> gTexelLock;

SamplerState gPointSampler;

cbuffer CB
{
    float4x4 GBufferVP; // GBuffer的观察投影矩阵
    float4x4 GBufferV;    // GBuffer的观察矩阵
    float4x4 GBufferP;    // GBuffer的投影矩阵
    float4x4 invOriginVP; // Impostor的观察投影矩阵的逆矩阵
    uint lowerLevel;
    float t;
    uint width;           // 水平方向的总采样点个数
    uint height;          // 垂直方向的总采样点个数
    uint outputWidth;     // G-Buffer的宽度
    uint outputHeight;    // G-Buffer的高度
    float depthThreshold; // 深度差距大于此阈值的纹素间不可混合
};

struct SampleOutput
{
    float4 NDO;
    float4 MCR;
    float weight;
}

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

float4 originCoordToNDC(float2 originCoord, float originDepth)
{
    float4 originNDC = float4(2 * originCoord.x - 1, 1 - 2 * originCoord.y, originDepth, 1);
    float4 temp = mul(invOriginVP, originNDC);
    float4 posWorld = temp / temp.w;
    float4 posClip = mul(GBufferVP, posWorld);
    return posClip / posClip.w;
}

float4 originCoordToView(float2 originCoord, float originDepth)
{
    float4 originNDC = float4(2 * originCoord.x - 1, 1 - 2 * originCoord.y, originDepth, 1);
    float4 temp = mul(invOriginVP, originNDC);
    float4 posWorld = temp / temp.w;
    return mul(GBufferV, posWorld);
}

SampleOutput sample(float2 originCoord, uint level)
{
    SampleOutput output = {};
    output.NDO = 0;
    output.MCR = 0;
    output.weight = 0;
    float4 NDO = gPackedNDO.SampleLevel(gPointSampler, originCoord, level);
    if (NDO.w == 0)
        return output;
    float4 NDC = originCoordToNDC(originCoord, NDO.z);
    if (any(NDC.xyz < float3(-1, -1, 0)) || any(NDC.xyz > float3(1, 1, 1)))
        return output;
    // 暂时不对深度进行坐标变换

    float2 coord = float2(0.5 * NDC.x + 0.5, 0.5 - 0.5 * NDC.y);
    float4 MCR = gPackedMCR.SampleLevel(gPointSampler, originCoord, level);
    output.NDO = NDO;
    output.MCR = MCR;
    output.weight = 1;
    return output;
}

void forwardMapping(float2 originCoord)
{
    SampleOutput lower = sample(originCoord, lowerLevel);
    SampleOutput higher = sample(originCoord, lowerLevel + 1);
    if (lower.weight * higher.weight == 0)
        return;
    float4 lowerView = originCoordToView(originCoord, lower.NDO.z);
    float4 higherView = originCoordToView(originCoord, higher.NDO.z);
    if (abs(lowerView.z - higherView.z) > depthThreshold)
    {
        if (lowerView.z < higherView.z)
            higher.weight = 0;
        else
            lower.weight = 0;
    }
    float t_weight = (t * higher.weight) / ((1 - t) * lower.weight + t * higher.weight);

    float4 NDO = 0;
    float4 MCR = 0;
    float4 view = lerp(lowerView, higherView, t_weight);
    float4 clip = mul(GBufferP, view);
    float4 NDC = clip / clip.w;
    if (any(NDC.xyz < float3(-1, -1, 0)) || any(NDC.xyz > float3(1, 1, 1)))
        return;
    NDO.z = NDC.z; // 深度变换到当前坐标系

    float3 lowerNormal = octoUVToNormal(lower.NDO.xy);
    float3 higherNormal = octoUVToNormal(higher.NDO.xy);
    float3 normal = normalize(lerp(lowerNormal, higherNormal, t_weight));
    NDO.xy = normalToOctoUV(normal);
    NDO.w = lerp(lower.NDO.w, higher.NDO.w, t_weight);
    MCR.yzw = lerp(lower.MCR.yzw, higher.MCR.yzw, t_weight);
    MCR.x = lower.MCR.x;

    float2 coord = float2(0.5 * NDC.x + 0.5, 0.5 - 0.5 * NDC.y);
    uint2 pixel = uint2((uint)floor(coord.x * outputWidth), (uint)floor(coord.y * outputHeight));

#if ENABLE_LOCK
    uint old = 1;
    while (old != 0)
    {
        InterlockedCompareExchange(gTexelLock[pixel], 1u, 0u, old);
    }
#endif
    float4 currentNDO = gMappedNDO[pixel];
    if (currentNDO.w == 0 || NDO.z < currentNDO.z)
    {
        gMappedNDO[pixel] = NDO;
        gMappedMCR[pixel] = MCR;
    }
#if ENABLE_LOCK
    uint dummy;
    InterlockedExchange(gTexelLock[pixel], 0u, dummy);
#endif
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 originPixel = dispatchThreadId.xy;

    float2[4] superSamplingOffset = { float2(0.1f, 0.3f), float2(0.7f, 0.1f), float2(0.3f, 0.9f), float2(0.9f, 0.7f) };

#if ENABLE_SUPERSAMPLING
    for (uint i = 0; i < 4; i++)
    {
        float2 p = originPixel + superSamplingOffset[i];
        forwardMapping(float2(p.x / width, p.y / height));
    }
#else
    float2 p = originPixel + 0.5f;
    forwardMapping(float2(p.x / width, p.y / height));
#endif
}
