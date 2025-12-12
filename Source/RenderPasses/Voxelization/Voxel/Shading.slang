#pragma once
#include "ABSDF.slang"

const static float Pi = 3.14159265359;

inline float ggx(float3 n, float3 h, float rough)
{
    float rough2 = rough * rough;
    float temp = dot(n, h) * dot(n, h) * (rough2 - 1) + 1;
    temp = max(1e-6, temp);
    return rough2 / Pi / temp / temp;
}
inline float3 fresnel(float3 v, float3 h, float3 spec)
{
    return spec + (1 - spec) * pow(1 - saturate(dot(v, h)), 5); //不能出现负底数
}

float g(float3 n, float3 x, float rough)
{
    float dotNx = dot(n, x);
    float temp = rough * rough + (1 - rough * rough) * dotNx * dotNx;
    temp = sqrt(temp) / max(1e-6, dotNx) - 1;
    return temp / 2;
}
float3 cookTorrence(float3 l, float3 v, float3 h, float3 n, float3 spec, float rough)
{
    float3 specColor = ggx(n, h, rough) * fresnel(v, h, spec) / (1 + g(n, l, rough) + g(n, v, rough)) / 4 / max(1e-6, dot(n, v));
    return specColor;
}

inline float3 weightedCookTorrence(NDF NDF, float3 l, float3 v, float3 spec)
{
    float3 sum = 0;
    float3 h = normalize(l + v);
    for (int i = 0; i < LOBE_COUNT; i++)
    {
        float w = NDF.weightedNormals[i].w;
        if (w > 0)
        {
            float3 n = NDF.weightedNormals[i].xyz;
            float cosTerm = dot(n, l);
            if (cosTerm < 0)
                n = -n;
            if (dot(n, v) <= 0)
                continue;
            sum += cookTorrence(l, v, h, n, spec, NDF.roughness[i]) * w;
        }
    }
    return sum; // 未归一化，已经带有余弦项
}
//可视化法线分布时，要渲染的点在球面上的方向充当h即可
inline float weightedGGX(NDF NDF, float3 h)
{
    float sum = 0;
    for (int i = 0; i < LOBE_COUNT; i++)
    {
        float w = NDF.weightedNormals[i].w;
        if (w > 0)
        {
            float3 n = NDF.weightedNormals[i].xyz;

            float cosTerm = dot(n, h);
            if (cosTerm < 0)
                n = -n;
            sum += ggx(n, h, NDF.roughness[i]) * w;
        }
    }
    return sum; // 未归一化
}

inline float3 lambertian(NDF NDF, float3 l, float3 v, float3 diffuse, float3 spec)
{
    float cosTerm = NDF.weightedDot(l, v);
    return diffuse / Pi * (1 - fresnel(v, normalize(v + l), spec)) * cosTerm;
}
