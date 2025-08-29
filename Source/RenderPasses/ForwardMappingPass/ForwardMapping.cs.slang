Texture2D<float4> gPackedNDO;   //传入的世界空间法线、深度、透明度
Texture2D<float4> gPackedMCR;   //传入的纹理ID 、纹理坐标、粗糙度
RWTexture2D<float4> gMappedNDO; //映射后的世界空间法线、深度、透明度
RWTexture2D<float4> gMappedMCR; //映射后的纹理ID、纹理坐标、粗糙度
RWTexture2D<float4> gWorldNormal;

cbuffer CB
{
    float4x4 VP;            //当前视角下的观察投影矩阵
    float4x4 invOriginVP;   //预生成纹理时的观察投影矩阵的逆矩阵
    int width;
    int height;
};

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

void forwardMapping(uint2 originPixel)
{
    float4 gPackedNDO = gPackedNDO[originPixel];
    if (gPackedNDO.w == 0)
        return; // 忽略未写入透明度的纹素
    float4 originNDC = float4(2 * (originPixel.x + 0.5) / width - 1, 1 - 2 * (originPixel.y + 0.5) / height, gPackedNDO.z, 1);
    float4 temp = mul(invOriginVP, originNDC);
    float4 posWorld = temp / temp.w;
    float4 posClip = mul(VP, posWorld);
    float4 NDC = posClip / posClip.w;
    NDC = NDC * 0.5 + 0.5;
    uint2 pixel = uint2((uint)round(NDC.x * width), (uint)round((1 - NDC.y) * height));
    float depth = NDC.z;
    if (pixel.x >= 0 && pixel.x < width && pixel.y >= 0 && pixel.y < height)
    {
        float4 currentNDO = gMappedNDO[pixel];
        if (depth <= currentNDO.z || currentNDO.w == 0)
        {
            gMappedNDO[pixel] = float4(gPackedNDO.xy, depth, 1);
            gMappedMCR[pixel] = gPackedMCR[originPixel];
            float3 normal = octoUVToNormal(gPackedNDO.xy);
            gWorldNormal[pixel] = float4(normal * 0.5 + 0.5, 1);
        }
    }
}

[numthreads(16, 16, 1)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint2 originScreenPos = dispatchThreadId.xy;
    forwardMapping(originScreenPos);
}
