Texture2D<float4> gPrevNDO;
RWTexture2D<float4> gCurrentNDO;
Texture2D<float4> gPrevMCR;
RWTexture2D<float4> gCurrentMCR;

cbuffer CB
{
    uint currentLevel;
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
    if (length(uv) == 0)
        return 0;
    float2 p = uv * 2 - 1;
    float3 n = float3(p, 1 - dot(1, abs(p)));
    if (n.z < 0)
    {
        n.xy = (1 - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

float mixDepth(float[4] ds, uint validCount)
{
    float ret = ds[0];
    for (uint i = 1; i < validCount; i++)
    {
        ret = min(ret, ds[i]);
    }
    return ret;
}

float3 mixNormal(float3[4] ns, uint validCount)
{
    float3 sum = 0;
    for (uint i = 0; i < validCount; i++)
    {
        sum += ns[i];
    }
    return normalize(sum);
}

float mixOpacity(float[4] os, uint validCount)
{
    float sum = 0;
    for (uint i = 0; i < validCount; i++)
    {
        sum += os[i];
    }
    return sum / validCount;
}

uint IDToMask(uint id)
{
    return 1 << (id * 4); // 简单地认为ID总是取0~7，每个ID分别占用计数器的4位
}

uint materialIDCounter(uint[4] ms, uint validCount)
{
    uint sum = 0;
    for (uint i = 0; i < validCount; i++)
    {
#if FIRSTCOUNTER
        sum += IDToMask(ms[i]);
#else
        sum += ms[i]; // 受限于计数器，Mipmap只能生成两层
#endif
    }
    return sum;
}

float2 mixTexCoord(float2[4] cs, uint validCount)
{
    float2 sum = 0;
    for (uint i = 0; i < validCount; i++)
    {
        sum += cs[i];
    }
    return sum / validCount;
}

void mix(uint2 currentPixel)
{
    uint2 prevPixel = currentPixel * 2;
    uint2[4] offsets;
    offsets[0] = uint2(0, 0);
    offsets[1] = uint2(1, 0);
    offsets[2] = uint2(0, 1);
    offsets[3] = uint2(1, 1);

    float[4] depths;
    float3[4] normals;
    float[4] opacitys;
    uint[4] materialIDs;
    float2[4] texCoords;
    // 不完全透明的纹素才被视为有效纹素，参与混合（透明像素仍参与透明度混合）
    uint validCount = 0;
    for (uint i = 0; i < 4; i++)
    {
        float4 NDO = gPrevNDO[prevPixel + offsets[i]];
        float4 MCR = gPrevMCR[prevPixel + offsets[i]];
        opacitys[i] = NDO.w;
        if (NDO.w == 0)
            continue;
        depths[validCount] = NDO.z;
        normals[validCount] = octoUVToNormal(NDO.xy);
        materialIDs[validCount] = asuint(MCR.x);
        texCoords[validCount] = MCR.yz;
        validCount++;
    }
    if (validCount > 0)
    {
        float3 normal = mixNormal(normals, validCount);
        float2 octoUV = normalToOctoUV(normal);
        float depth = mixDepth(depths, validCount);
        float opacity = mixOpacity(opacitys, 4);
        uint materialID = materialIDCounter(materialIDs, validCount);
        float2 texCoord = mixTexCoord(texCoords, validCount);
        gCurrentNDO[currentPixel] = float4(octoUV, depth, opacity);
        gCurrentMCR[currentPixel] = float4(asfloat(materialID), texCoord, 0);
    }
    else
    {
        gCurrentNDO[currentPixel] = 0;
        gCurrentMCR[currentPixel] = 0;
    }
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadID: SV_DispatchThreadID)
{
    uint2 currentPixel = dispatchThreadID.xy;
    mix(currentPixel);
}
