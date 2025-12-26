Texture2D<float4> input;
SamplerState sampler;

cbuffer CB
{
    bool enable;
    uint2 outputMin;
    uint2 outputSize;
    uint2 windowSize;
}

struct PsOut
{
    float4 color : SV_Target0;
};

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = {};
    if (enable)
    {
        uint2 pixel = uint2(texCoord * windowSize);
        float2 localCoord = (pixel - outputMin) / (float2)outputSize;
        psOut.color = input.Sample(sampler, localCoord);
    }
    else
    {
        psOut.color = input.Sample(sampler, texCoord);
    }
    return psOut;
}
