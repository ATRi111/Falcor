Texture2D<float4> gMappedNDO;
Texture2D<float4> gMappedMCR;
RWTexture2D<float4> gFilteredNDO;
RWTexture2D<float4> gFilteredMCR;
SamplerState gSampler;

cbuffer CB
{
    int blockSize;
};

void filter(uint2 block)
{
    for (int x = 0; x < blockSize; x++)
    {
        for (int y = 0; y < blockSize; y++)
        {
            uint2 pixel = block * blockSize + uint2(x, y);
            gFilteredNDO[pixel] = gMappedNDO[pixel];
            gFilteredMCR[pixel] = gMappedMCR[pixel];
        }
    }
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    filter(dispatchThreadId.xy);
}
