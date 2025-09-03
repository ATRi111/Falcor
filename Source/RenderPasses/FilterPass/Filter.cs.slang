Texture2D<float4> gMappedNDO;
Texture2D<float4> gMappedMCR;
RWTexture2D<float4> gFilteredNDO;
RWTexture2D<float4> gFilteredMCR;
SamplerState gSampler;

cbuffer CB
{
    uint kernelSize;
    float deltaU;
    float deltaV;
};

float calcWeight(uint2 offset, float4 centerNDO, float4 currentNDO)
{
    float weight = kernelSize * 2 + 1 - abs(offset.x) - abs(offset.y); // 类似高斯滤波
    weight *= currentNDO.w;
    return weight;
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

void filter(uint2 pixel)
{
    float4 centerNDO = gMappedNDO[pixel];
    float4 centerMCR = gMappedMCR[pixel];
    float2 mtlCoordSum = 0;
    float weightSum = 0;
    float depthSum = 0;
    float3 normalSum = 0;
    float opacitySum = 0;
    for (int x = -kernelSize; x <= kernelSize; x++)
    {
        for (int y = -kernelSize; y <= kernelSize; y++)
        {
            float2 uv = float2((pixel.x + 0.5f + x) * deltaU, (pixel.y + 0.5f + y) * deltaV);
            float4 currentNDO = gMappedNDO.Sample(gSampler, uv);
            float4 currentMCR = gMappedMCR.Sample(gSampler, uv);
            float weight = calcWeight(uint2(x, y), centerNDO, currentNDO);
            depthSum += weight * currentNDO.z;
            normalSum += weight * octoUVToNormal(currentNDO.xy);
            mtlCoordSum += weight * currentMCR.yz;
            opacitySum += currentNDO.w; // 透明度的权重始终为1
            weightSum += weight;
        }
    }
    if (weightSum == 0)
    {
        gFilteredNDO[pixel] = 0;
        gFilteredMCR[pixel] = 0;
    }
    else
    {
        normalSum = normalize(normalSum / weightSum);
        mtlCoordSum /= weightSum;
        depthSum /= weightSum;
        opacitySum /= (kernelSize * 2 + 1) * (kernelSize * 2 + 1);
        gFilteredNDO[pixel] = float4(normalToOctoUV(normalSum), depthSum, opacitySum);
        gFilteredMCR[pixel] = float4(centerMCR.x, mtlCoordSum, centerMCR.z);
    }
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    filter(dispatchThreadId.xy);
}
