Texture2D<float4> gPackedNDO;   // Impostor记录的世界空间法线、深度、透明度
Texture2D<float4> gPackedMCR;   // Impostor记录的纹理ID 、纹理坐标、粗糙度
RWTexture2D<float4> gMappedNDO; // 映射到GBuffer的世界空间法线、深度、透明度
RWTexture2D<float4> gMappedMCR; // 映射到GBuffer的纹理ID、纹理坐标、粗糙度
RWTexture2D<float4> gPosW;      // 世界空间坐标

cbuffer CB
{
    float4x4 GBufferVP; // GBuffer的观察投影矩阵
    float4x4 invOriginVP; // 预生成纹理时的观察投影矩阵的逆矩阵
    uint width;        // Impostor的宽度
    uint height;       // Impostor的高度
    uint outputWidth;  // G-Buffer的宽度
    uint outputHeight; // G-Buffer的高度
};

// offset为采样点相对于纹素左上角的偏移量
void forwardMapping(uint2 originPixel, float2 offset)
{
    float4 packedNDO = gPackedNDO[originPixel];
    if (packedNDO.w == 0)
        return;
    float2 p = float2(originPixel.x, originPixel.y) + offset;
    float4 originNDC = float4(2 * p.x / width - 1, 1 - 2 * p.y / height, packedNDO.z, 1);
    float4 temp = mul(invOriginVP, originNDC);
    float4 posWorld = temp / temp.w;
    float4 posClip = mul(GBufferVP, posWorld);
    float4 NDC = posClip / posClip.w;
    float2 coord = float2(0.5 * NDC.x + 0.5, 0.5 - 0.5 * NDC.y);
    uint2 pixel = uint2((uint)floor(coord.x * outputWidth), (uint)floor(coord.y * outputHeight));
    float depth = NDC.z;

    if (pixel.x >= 0 && pixel.x < outputWidth && pixel.y >= 0 && pixel.y < outputHeight)
    {
        float4 currentNDO = gMappedNDO[pixel];
        float w = currentNDO.w;
        if (depth <= currentNDO.z || w == 0)
        {
            // gMappedNDO[pixel] = float4(packedNDO.xy, depth, saturate(packedNDO.w + w)); // 透明度叠加
            gMappedNDO[pixel] = float4(packedNDO.xy, depth, packedNDO.w);
            gMappedMCR[pixel] = gPackedMCR[originPixel];
#if WRITE_POSW
            gPosW[pixel] = posWorld;
#endif
        }
    }
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 originScreenPos = dispatchThreadId.xy;
#if ENABLE_SUPERSAMPLING
    forwardMapping(originScreenPos, float2(0.1f, 0.3f));
    forwardMapping(originScreenPos, float2(0.7f, 0.1f));
    forwardMapping(originScreenPos, float2(0.3f, 0.9f));
    forwardMapping(originScreenPos, float2(0.9f, 0.7f));
#else
    forwardMapping(originScreenPos, float2(0.5f, 0.5f));
#endif
}
