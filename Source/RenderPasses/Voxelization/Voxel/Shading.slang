#pragma once
#include "ABSDF.slang"
import Utils.Math.MathHelpers;

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
    return spec + (1 - spec) * pow(1 - saturate(dot(v, h)), 5); // 不能出现负底数
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
// 可视化法线分布时，要渲染的点在球面上的方向充当h即可
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

inline float3x3 rotateMatrix(float3 from, float3 to)
{
    float3 f = normalize(from);
    float3 t = normalize(to);

    float cosAngle = dot(f, t);
    float3 axis = cross(f, t);
    float s = length(axis);

    if (s < 1e-6f) // 几乎共线
    {
        if (cosAngle > 0.0f)
        {
            return float3x3(1.0f, 0, 0, 0, 1.0f, 0, 0, 0, 1.0f);
        }
        else
        {
            float3 ortho = (abs(f.x) < 0.9f) ? float3(1, 0, 0) : float3(0, 1, 0);
            float3 axis180 = normalize(cross(f, ortho));
            return rotateMatrix(-1.0f, axis180);
        }
    }

    axis /= s;
    return rotateMatrix(cosAngle, axis);
}
inline float3 importanceSampling(float3 n, float3 v, float3 spec, float roughness, float2 uDir, float uEnergy, out float pdf)
{
    float averageFresnel = (20.0f * (spec.x + spec.y + spec.z) / 3.0f + 1.0f) / 21.0f;
    float3x3 rot = rotateMatrix(float3(0, 0, 1), n);
    float3 l;
    float pdf_diffuse, pdf_specular;
    if (uEnergy <= averageFresnel)
    {
        // 根据镜面反射选择采样方向
        float r2 = roughness * roughness;
        float phi = 2.0 * Pi * uDir.x;
        float cosTheta = sqrt((1.0 - uDir.y) / (1.0 + (r2 - 1.0) * uDir.y));
        float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
        float3 h = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
        h = mul(rot, h);
        l = reflect(-v, h);
        pdf_specular = ggx(n, h, roughness) * dot(n, h) / (4.0 * max(1e-6, dot(l, h)));
        pdf_diffuse = dot(n, l) / Pi;
    }
    else
    {
        // 根据漫反射选择采样方向
        l = sample_cosine_hemisphere_concentric(uDir, pdf_diffuse);
        l = mul(rot, l);
        float3 h = normalize(l + v);
        pdf_specular = ggx(n, h, roughness) * dot(n, h) / (4.0 * max(1e-6, dot(l, h)));
    }
    pdf = averageFresnel * pdf_specular + (1.0 - averageFresnel) * pdf_diffuse;
    return l;
}
