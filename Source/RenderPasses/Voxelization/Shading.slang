#pragma once
#include "VoxelizationShared.slang"
#include "Math/Random.slang"
import Utils.Math.MathHelpers;

const static float Pi = 3.14159265359;
const static float InvPi = 0.318309886183790671538;

inline float pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}
inline float3 calcSchlick(float3 f0, float3 f90, float cosTheta)
{
    return lerp(f0, f90, pow5(1 - cosTheta));
}
inline float calcSchlick(float f0, float f90, float cosTheta)
{
    return lerp(f0, f90, pow5(1 - cosTheta));
}

inline float ggx(float NdotH, float alpha)
{
    float alpha2 = alpha * alpha;
    float temp = NdotH * NdotH * (alpha2 - 1) + 1;
    temp = max(1e-6, temp);
    return alpha2 / Pi / temp / temp;
}
inline float3 fresnel(float3 v, float3 h, float3 spec)
{
    return calcSchlick(spec, float3(1, 1, 1), dot(v, h));
}

float Lambda(float NdotX, float alpha)
{
    float temp = alpha * alpha + (1 - alpha * alpha) * NdotX * NdotX;
    temp = safeSqrt(temp) / max(1e-6, NdotX) - 1;
    return temp / 2;
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

            float NdotH = dot(n, h);
            if (NdotH < 0)
                n = -n;
            float rough = NDF.roughness[i];
            sum += ggx(NdotH, rough * rough) * w;
        }
    }
    return sum;
}

inline float calcPrimitiveWeight(VoxelData data)
{
    float rough = data.ABSDF.NDF.getAverageRoughness();
    float glossy = (1 - rough) * calcSpecularWeight(data.ABSDF.specular);
    return lerp(0.8, 0.2, glossy);
}

inline float calcPrimitivePdf(VoxelData data, float3 v, float3 l,bool isTransmittance)
{
    if (isTransmittance)
        return 1 - coverage; 
    float specularWeight = calcSpecularWeight(data.ABSDF.specular);
    return  // 这里不乘coverage，计算反射光颜色时也不乘coverage(本来就相互抵消)，避免pdf过小
}
inline float3 samplePrimitive(VoxelData data, float3 v, inout UniformSampleGenerator sg, out bool isTransmittance, out float pdf)
{
    float coverage = data.calcCoverage(v);
#if !CHECK_COVERAGE
    coverage = 1;
#endif
    if (coverage == 1 || (float)Next(sg) <= coverage) //coverage的时间里只采样BSDF Lobe
    {
        uint lobeIndex;
        ABSDF ABSDF = data.ABSDF;
        NDF NDF = ABSDF.NDF;
        float uLobe = (float)Next(sg);
        float specularWeight = calcSpecularWeight(ABSDF.specular);
        float3 l = sampleSurface(NDF, v, specularWeight, Next2(sg), (float)Next(sg), uLobe);
        isTransmittance = false;
        pdf = coverage * calcSurfacePdf(data.ABSDF.NDF, l, v, specularWeight);
        return l;
    }
    isTransmittance = true;
    return -v;  //1-coverage的时间里只采样Delta Lobe
}

inline void buildTBN(out float3 t, out float3 b, float3 n)
{
    float3 up = (abs(n.z) < 0.999f) ? float3(0, 0, 1) : float3(1, 0, 0);
    t = normalize(cross(up, n));
    b = cross(n, t);
}
inline float3 localToWorld(float3 localDir, float3 t, float3 b, float3 n)
{
    return localDir.x * t + localDir.y * b + localDir.z * n;
}
inline float3 worldToLocal(float3 worldDir, float3 t, float3 b, float3 n)
{
    return float3(dot(worldDir, t), dot(worldDir, b), dot(worldDir, n));
}

float calcSpecularWeight(float3 specular)
{
    float specularWeight = (20 * (specular.x + specular.y + specular.z) / 3 + 1) / 21.0;
    return saturate(specularWeight);
}

struct FrostbiteCosBRDF
{
    float3 diffuse; //Lambert反射率
    float rough;

    [mutating]
    void init(float3 diffuse, float rough)
    {
        this.diffuse = diffuse;
        this.rough = rough;
    }

    float3 eval(float3 l, float3 v, float3 h)
    {
        if (l.z <= 0 || v.z <= 0)
            return 0;
        float VdotH = dot(v, h);
        float energyBias = lerp(0.f, 0.5f, rough);
        float energyFactor = lerp(1.f, 1.f / 1.51f, rough);
        float fd90 = energyBias + 2.f * VdotH * VdotH * rough;
        float fd0 = 1.f;
        float wiScatter = calcSchlick(fd0, fd90, l.z);
        float woScatter = calcSchlick(fd0, fd90, v.z);
        return wiScatter * woScatter * energyFactor * diffuse / Pi * l.z;
    }

    void sample(float3 v, out float3 l, out float3 h, inout ISampleGenerator sg)
    {
        float2 d = sample_disk_concentric(Next2(sg));
        float z = safeSqrt(1.f - dot(d, d));
        l = float3(d, z);
        h = normalize(l + v);
    }

    float evalPdf(float3 l, float3 v, float3 h)
    {
        if (l.z <= 0 || v.z <= 0)
            return 0;
        return InvPi * l.z;
    }
};

struct CookTorrenceCosBRDF
{
    float3 specular; // Fresnel反射率
    float alpha;

    [mutating]
    void init(float3 specular, float rough)
    {
        this.specular = specular;
        alpha = rough * rough;
    }

    float3 eval(float3 l, float3 v, float3 h)
    {
        if (l.z <= 0 || v.z <= 0)
            return 0.f;
        float3 specColor = ggx(h.z, alpha) * fresnel(v, h, specular) / (1 + Lambda(l.z, alpha) + Lambda(v.z, alpha)) / 4 / max(1e-6, v.z);
        return specColor;
    }

    void sample(float3 v, out float3 l, out float3 h, inout ISampleGenerator sg)
    {
        float2 uDir = Next2(sg);
        float phi = 2.0 * Pi * uDir.x;
        float cosTheta = safeSqrt((1.0 - uDir.y) / (1.0 + (alpha * alpha - 1.0) * uDir.y));
        float sinTheta = safeSqrt(1.0 - cosTheta * cosTheta);
        h = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
        l = reflect(-v, h);
    }

    float evalPdf(float3 l, float3 v, float3 h)
    {
        if (l.z <= 0 || v.z <= 0)
            return 0;
        return ggx(h.z, alpha) * h.z / (4.0 * max(1e-6, dot(v, h)));
    }
};

//从此结构体开始接收和返回世界空间方向
struct LobeBRDF
{
    FrostbiteCosBRDF frostBite;
    CookTorrenceCosBRDF cookTorrence;

    float3 t, b, n;
    float specularWeight;

    [mutating]
    void init(float3 n, float3 diffuse, float3 specular, float rough)
    {
        this.n = n;
        buildTBN(t, b, n);
        frostBite.init(diffuse, rough);
        cookTorrence.init(specular, rough);
        specularWeight = calcSpecularWeight(specular);
    }
    
    float3 eval(float3 l, float3 v, float3 h)
    {
        l = worldToLocal(l, t, b, n);
        v = worldToLocal(v, t, b, n);
        h = worldToLocal(h, t, b, n);
        return frostBite.eval(l, v, h) + cookTorrence.eval(l, v, h);
    }

    void sample(float3 v, out float3 l, out float3 h, inout ISampleGenerator sg)
    {
        v = worldToLocal(v, t, b, n);
        float uEnergy = Next(sg);
        if (uEnergy <= specularWeight)
            cookTorrence.sample(v, l, h, sg);
        else
            frostBite.sample(v, l, h, sg);
        l = localToWorld(l, t, b, n);
        h = localToWorld(h, t, b, n);
    }

    float evalPdf(float3 l, float3 v, float3 h)
    {
        l = worldToLocal(l, t, b, n);
        v = worldToLocal(v, t, b, n);
        h = worldToLocal(h, t, b, n);
        return (1 - specularWeight) * frostBite.evalPdf(l, v, h) + specularWeight * cookTorrence.evalPdf(l, v, h);
    }
};

struct SurfaceBRDF
{
    LobeBRDF[LOBE_COUNT] lobes;
    float[LOBE_COUNT] weights;

    [mutating]
    void init(ABSDF ABSDF)
    {
        NDF NDF = ABSDF.NDF;
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            lobes[i].init(NDF.weightedNormals[i].xyz, ABSDF.diffuse, ABSDF.specular, NDF.roughness[i]);
            weights[i] = NDF.weightedNormals[i].w;
        }
    }

    uint getRandomLobe(float uLobe)
    {
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            if (weights[i] <= 0)
                continue;
            uLobe -= weights[i];
            if (uLobe <= 0)
                return i;
        }
        return LOBE_COUNT - 1;
    }

    float3 eval(float3 l, float3 v, float3 h)
    {
        float3 sum = 0;
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            if(weights[i] > 0)
            {
                sum += weights[i] * lobes[i].eval(l, v, h);
            }
        }
        return sum;
    }

    void sample(float3 v, out float3 l, out float3 h, inout ISampleGenerator sg)
    {
        float uLobe = Next(sg);
        uint index = getRandomLobe(uLobe);
        return lobes[index].sample(v, l, h, sg);
    }

    float evalPdf(float3 l, float3 v, float3 h)
    {
        float pdf = 0;
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            if (weights[i] > 0)
            {
                pdf += weights[i] * lobes[i].evalPdf(l, v, h);
            }
        }
        return pdf;
    }
};

inline float calcSurfacePdf(NDF NDF, float3 l, float3 v, float specularWeight)
{
    float3 h = normalizeSafe(l + v);
    if (length(h) == 0)
        return 0;
    float pdf = 0;
    float VdotH = dot(v, h);
    for (uint i = 0; i < LOBE_COUNT; i++)
    {
        float w = NDF.weightedNormals[i].w;
        if (w > 0)
        {
            float3 n = NDF.weightedNormals[i].xyz;
            if (dot(n, v) < 0)
                n = -n;
            float NdotL = dot(n, l);
            if (NdotL <= 0)
                continue;
            float NdotH = dot(n, h);
            float rough = NDF.roughness[i];
            pdf += w * calcLobePdf(NdotL, NdotH, VdotH, rough * rough, specularWeight); // 单样本多重重要性采样
        }
    }
    return pdf;
}

