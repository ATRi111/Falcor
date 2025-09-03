Texture2D<float4> gPackedNDO; // 传入的世界空间法线、深度、透明度
RWTexture2D<float> gDepth;    // 映射到当前相机的深度

cbuffer CB
{
    float4x4 VP;          // 当前相机的观察投影矩阵
    float4x4 invOriginVP; // 预生成纹理时的观察投影矩阵的逆矩阵
    uint width;           // Impostor的宽度
    uint height;          // Impostor的高度
    uint outputWidth;     // 窗口的宽度
    uint outputHeight;    // 窗口的高度
};

void forwardMapping(uint2 originPixel)
{
    float4 packedNDO = gPackedNDO[originPixel];
    if (packedNDO.w == 0)
        return; // 忽略未写入透明度的纹素
    float4 originNDC = float4(2 * (originPixel.x + 0.5) / width - 1, 1 - 2 * (originPixel.y + 0.5) / height, packedNDO.z, 1);
    float4 temp = mul(invOriginVP, originNDC);
    float4 posWorld = temp / temp.w;
    float4 posClip = mul(VP, posWorld);
    float4 NDC = posClip / posClip.w;
    float2 coord = NDC.xy * 0.5 + 0.5;
    uint2 pixel = uint2((uint)floor(coord.x * outputWidth), (uint)floor((1 - coord.y) * outputHeight));
    float depth = NDC.z;
    if (pixel.x >= 0 && pixel.x < outputWidth && pixel.y >= 0 && pixel.y < outputHeight)
    {
        if (gDepth[pixel] == 0)
            gDepth[pixel] = depth;
        else
            gDepth[pixel] = min(gDepth[pixel], depth);
    }
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 originScreenPos = dispatchThreadId.xy;
    forwardMapping(originScreenPos);
}
