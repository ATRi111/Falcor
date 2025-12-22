#pragma once
#include "VoxelizationShared.slang"
#include "Math/Random.slang"
import Utils.Math.MathHelpers;

const static float Pi = 3.14159265359;

enum class SampleTarget : uint32_t
{
    Reflection,
    Transmission,
    LightSource
};

inline float ggx(float NdotH, float alpha)
{
    float alpha2 = alpha * alpha;
    float temp = NdotH * NdotH * (alpha2 - 1) + 1;
    temp = max(1e-6, temp);
    return alpha2 / Pi / temp / temp;
}
inline float ggx(float3 n, float3 h, float alpha)
{
    float NdotH = dot(n, h);
    return ggx(NdotH, alpha);
}
inline float3 fresnel(float3 v, float3 h, float3 spec)
{
    return spec + (1 - spec) * pow(1 - saturate(dot(v, h)), 5); // 不能出现负底数
}

float Lambda(float3 n, float3 x, float alpha)
{
    float NdotX = dot(n, x);
    float temp = alpha * alpha + (1 - alpha * alpha) * NdotX * NdotX;
    temp = sqrt(temp) / max(1e-6, NdotX) - 1;
    return temp / 2;
}
//带有余弦项，已经与分母中的余弦项约分掉
float3 cookTorrenceCos(float3 l, float3 v, float3 h, float3 n, float3 spec, float rough)
{
    float alpha = rough * rough;
    float3 specColor = ggx(n, h, alpha) * fresnel(v, h, spec) / (1 + Lambda(n, l, alpha) + Lambda(n, v, alpha)) / 4 / max(1e-6, dot(n, v));
    return specColor;
}

inline float3 weightedCookTorrenceCos(NDF NDF, float3 l, float3 v, float3 spec)
{
    float3 sum = 0;
    float3 h = normalize(l + v);
    for (int i = 0; i < LOBE_COUNT; i++)
    {
        float w = NDF.weightedNormals[i].w;
        if (w > 0)
        {
            float3 n = NDF.weightedNormals[i].xyz;
            if (dot(n, l) < 0)
                n = -n;
            if (dot(n, v) <= 0)
                continue;
            sum += cookTorrenceCos(l, v, h, n, spec, NDF.roughness[i]) * w;
        }
    }
    return sum; // 未归一化
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

inline float3 lambertianCos(NDF NDF, float3 l, float3 v, float3 diffuse, float3 spec)
{
    float cosTerm = NDF.weightedDot(l, v);
    return diffuse / Pi * (1 - fresnel(v, normalize(v + l), spec)) * cosTerm;
}

inline float3x3 rotateMatrix(float cosAngle, float3 axis)
{
    float c = cosAngle;
    float s = sqrt(1 - cosAngle * cosAngle); // 默认角度小于180°

    float3 temp = (1 - c) * axis;

    float3x3 rotate;
    rotate[0][0] = c + temp[0] * axis[0];
    rotate[0][1] = temp[1] * axis[0] - s * axis[2];
    rotate[0][2] = temp[2] * axis[0] + s * axis[1];

    rotate[1][0] = temp[0] * axis[1] + s * axis[2];
    rotate[1][1] = c + temp[1] * axis[1];
    rotate[1][2] = temp[2] * axis[1] - s * axis[0];

    rotate[2][0] = temp[0] * axis[2] - s * axis[1];
    rotate[2][1] = temp[1] * axis[2] + s * axis[0];
    rotate[2][2] = c + temp[2] * axis[2];

    return rotate;
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

inline float calcDiffusePdf(float NdotL)
{
    return NdotL / Pi;
}
inline float3 sampleDiffuse(float3 n, float2 uDir)
{
    float2 d = sample_disk_concentric(uDir);
    float z = sqrt(max(0.f, 1.f - dot(d, d)));
    float3 l = float3(d, z);
    float3x3 rot = rotateMatrix(float3(0, 0, 1), n);
    l = mul(rot, l);
    return l;
}

inline float calcSpecularPdf(float VdotH, float NdotH, float alpha)
{
    return ggx(NdotH, alpha) * NdotH / (4.0 * max(1e-6, VdotH));
}
inline float3 sampleSpecular(float3 n, float3 v, float alpha, float2 uDir)
{
    float alpha2 = alpha * alpha;
    float phi = 2.0 * Pi * uDir.x;
    float cosTheta = sqrt((1.0 - uDir.y) / (1.0 + (alpha2 - 1.0) * uDir.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    float3 h = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
    float3x3 rot = rotateMatrix(float3(0, 0, 1), n);
    h = mul(rot, h);
    float3 l = reflect(-v, h);
    return l;
}

inline float calcSpecularWeight(float3 spec)
{
    float specularWeight = (20.0f * (spec.x + spec.y + spec.z) / 3.0f + 1.0f) / 21.0f;
    return saturate(specularWeight);
}
inline float calcLobePdf(float NdotL, float NdotH, float VdotH, float alpha, float specularWeight)
{
    return (1 - specularWeight) * calcDiffusePdf(NdotL) + specularWeight * calcSpecularPdf(VdotH, NdotH, alpha);
}
inline float3 sampleLobe(float3 n, float3 v, float alpha, float specularWeight, float2 uDir, float uEnergy)
{
    float3 l;
    if (uEnergy <= specularWeight)
        l = sampleSpecular(n, v, alpha, uDir);
    else
        l = sampleDiffuse(n, uDir);
    return l;
}

inline float calcSurfacePdf(NDF NDF, float3 l, float3 v, float specularWeight)
{
    float3 h = normalize(l + v);
    float totalWeight = 0;
    float pdf = 0;
    for(uint i = 0; i < LOBE_COUNT; i++)
    {
        float w = NDF.weightedNormals[i].w;
        if (w > 0)
        {
            totalWeight += w;
            float3 n = NDF.weightedNormals[i].xyz;
            if (dot(n, v) < 0)
                n = -n;
            float NdotL = dot(n, l);
            if (NdotL <= 0)
                continue;
            float NdotH = dot(n, h);
            float VdotH = dot(v, h);
            float rough = NDF.roughness[i];
            pdf += w * calcLobePdf(NdotL, NdotH, VdotH, rough * rough, specularWeight); //混合重要性采样
        }
    }
    return pdf / totalWeight;
}
inline float3 sampleSurface(NDF NDF, float3 v, float specularWeight, float2 uDir, float uEnergy, float randomArea)
{
    uint lobeIndex = NDF.getRandomLobe(randomArea); // 根据权重随机选择一个Lobe
    float roughness = NDF.roughness[lobeIndex];
    float3 n = NDF.weightedNormals[lobeIndex].xyz;
    if (dot(n, v) < 0)
        n = -n;
    return sampleLobe(n, v, roughness, specularWeight, uDir, uEnergy);
}

inline float3 samplePrimitive(VoxelData data, float3 v, inout UniformSampleGenerator sg, out float pdf)
{
    float coverage = data.calcCoverage(v);
    if (coverage == 1 || (float)Next(sg) <= coverage) // 反射
    {
        uint lobeIndex;
        ABSDF ABSDF = data.ABSDF;
        NDF NDF = ABSDF.NDF;
        float randomArea = (float)Next(sg) * ABSDF.area;
        float specularWeight = calcSpecularWeight(ABSDF.specular);
        float3 l = sampleSurface(NDF, v, specularWeight, Next2(sg), (float)Next(sg), randomArea);
        pdf = coverage * calcSurfacePdf(NDF, l, v, specularWeight);
        return l;
    }
    // 透射
    pdf = 1 - coverage;
    return -v;
}
