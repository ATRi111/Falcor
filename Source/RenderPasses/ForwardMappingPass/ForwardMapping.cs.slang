Texture2D<float4> gPackedNDO;
Texture2D<float4> gPackedMCR;
RWTexture2D<float4> gMappedNDO;
RWTexture2D<float4> gMappedMCR;
RWTexture2D<float4> gWorldNormal;

cbuffer CB
{
    float4x4 transform;
};

void tryWrite(float4 floats, uint2 ints)
{
    ;
}

void forwardMapping(uint2 originPixel)
{
    float4 originFloats = gPackedNDO[originPixel];
    float4 originScreenPos = float4(originPixel.xy, originFloats.z, 1); // 带深度屏幕空间坐标
    float4 screenPos = mul(transform, originScreenPos);
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 originTexC = dispatchThreadId.xy;
    forwardMapping(originTexC);
}
