#include "MyRasterSharedTypes.slang"

Texture2D<float4> gNormal;
Texture2D<float4> gPosW;
Texture2D<float4> gViewW;
Texture2D<float4> gDiffuseOpacity;
Texture2D<float4> gSpecRough;
Texture2D<float4> gEmissive;
SamplerState gSampler;

cbuffer DirectionalLightCB
{
    float3 lightPosW;
    float3 lightColor;
    float3 lightDirW;
};

cbuffer CB
{
    uint gRasterMode;
};

float3 BlinnPhong(float3 v, float3 n, float3 diff, float3 spec, float g)
{
    float3 l = -lightDirW;
    float3 h = normalize(l + v);
    float3 diffL = max(0, dot(l, n)) * diff * lightColor;
    float3 specL = pow(max(0, dot(h, n)), g) * spec * lightColor;
    return diffL + specL;
}

float GGX_D(float3 n, float3 h, float rough)
{
    float Pi = 3.14159265359;
    float rough2 = rough * rough;
    float temp = dot(n, h) * dot(n, h) * (rough2 - 1) + 1;
    return rough2 / Pi / temp / temp;
}
float3 GGX_F(float3 v, float3 h, float3 spec)
{
    return spec + (1 - spec) * pow(1 - dot(v, h), 5);
}
float GGX_g(float3 n, float3 x, float rough)
{
    float k = (rough + 1) * (rough + 1) / 8;
    float temp = dot(n, x);
    return temp / (temp * (1 - k) + k);
}
float3 GGX(float3 v, float3 n, float3 diff, float3 spec, float rough)
{
    float3 l = -lightDirW;
    float3 h = normalize(l + v);
    float3 diffL = max(0, dot(l, n)) * diff * lightColor;
    float3 specL =
        GGX_D(n, h, rough) * GGX_F(v, h, spec) * GGX_g(n, v, rough) * GGX_g(n, l, rough) / 4 / max(0.001, dot(n, v)) * lightColor;
    return diffL + specL;
}

float4 main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION) : SV_TARGET
{
    uint mode = (MyRasterMode)gRasterMode;
    float3 normal = gNormal.Sample(gSampler, texCoord).xyz;
    float3 posW = gPosW.Sample(gSampler, texCoord).xyz;
    float3 viewW = gViewW.Sample(gSampler, texCoord).xyz;
    float3 diff = gDiffuseOpacity.Sample(gSampler, texCoord).xyz;
    float3 spec = gSpecRough.Sample(gSampler, texCoord).xyz;
    float roughness = gSpecRough.Sample(gSampler, texCoord).w;
    float3 emissive = gEmissive.Sample(gSampler, texCoord).xyz;
    float gloss = 2 / roughness / roughness - 2;

    float3 dirL = 0;
    float3 pointL = 0;

    switch (mode)
    {
    case MyRasterMode::BlinnPhong:
        dirL = BlinnPhong(viewW, normal, diff, spec, gloss);
        break;
    case MyRasterMode::GGX:
        dirL = GGX(viewW, normal, diff, spec, roughness);
        break;
    }

    return float4(dirL + pointL + emissive, 1);
}
