#pragma once
#include "ABSDF.slang"

float ggx(float3 n, float3 h, float rough)
{
    const static float PI = 3.14159265359;
    float rough2 = rough * rough;
    float temp = dot(n, h) * dot(n, h) * (rough2 - 1) + 1;
    temp = max(1e-6, temp);
    return rough2 / PI / temp / temp;
}
float3 fresnel(float3 v, float3 h, float3 spec)
{
    return spec + (1 - spec) * pow(1 - saturate(dot(v, h)), 5); //不能出现负底数
}
float masking(float3 n, float3 x, float rough)
{
    float k = (rough + 1) * (rough + 1) / 8;
    float temp = dot(n, x);
    temp /= (temp * (1 - k) + k);
    return temp;
}
float3 cookTorrence(float3 l, float3 v, float3 h, float3 n, float3 spec, float rough)
{
    float3 specColor = ggx(n, h, rough) * fresnel(v, h, spec) * masking(n, v, rough) * masking(n, l, rough) / 4 / max(1e-6, dot(n, v));
    return specColor;
}

float3 weightedCookTorrence(NDF NDF, float3 l, float3 v, float3 spec, float rough)
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
            sum += cookTorrence(l, v, h, n, spec, rough) * w;
        }
    }
    return sum; // 未归一化，已经带有余弦项
}
