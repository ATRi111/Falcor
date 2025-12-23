#pragma once
#include "../HostDeviceShared.slang"

BEGIN_NAMESPACE_FALCOR

#define LOBE_COUNT 4

inline uint NormalIndex(float3 n)
{
    uint bx = (n.x >= 0) ? 1 : 0;
    uint bz = (n.z >= 0) ? 1 : 0;
    return (bx) | (bz << 1);
}

struct NDF
{
    float4 weightedNormals[LOBE_COUNT];
    float roughness[LOBE_COUNT];

    MUTATING
    void init()
    {
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            weightedNormals[i] = float4(0);
            roughness[i] = 0;
        }
    }

    MUTATING
    void normalizeSelf()
    {
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
#if defined(HOST_CODE)
            float3 n = weightedNormals[i].xyz();
#else
            float3 n = weightedNormals[i].xyz;
#endif
            float l = length(n);
            if (l > 0)
                weightedNormals[i] = float4(n / l, weightedNormals[i].w);
            else
                weightedNormals[i] = float4(0);

            if (weightedNormals[i].w > 0)
                roughness[i] /= weightedNormals[i].w;
            else
                roughness[i] = 0;
        }
    }

#if !defined(HOST_CODE)
    float3 getAverageNormal(float3 direction)
    {
        float3 sum = 0;
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            float w = weightedNormals[i].w;
            if (w > 0)
            {
                float3 n = weightedNormals[i].xyz;
                float cosTerm = dot(n, direction);
                sum += sign(cosTerm) * n * w; // 夹角大于90°的法线，系数小于0，负负得正
            }
        }
        return normalize(sum);
    }

    // 返回与所给方向夹角不超过90°且权重最大的法线
    float3 getMainNormal(float3 direction)
    {
        float3 n = 0;
        float maxWeight = 0;
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            float w = weightedNormals[i].w;
            if (w > maxWeight)
            {
                n = weightedNormals[i].xyz;
                float cosTerm = dot(n, direction);
                if (cosTerm < 0)
                    n = -n;
                maxWeight = w;
            }
        }
        return n;
    }

    float getAverageRoughness()
    {
        float sumRoughness = 0;
        float sumWeight = 0;
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            float w = weightedNormals[i].w;
            if (w > 0)
            {
                sumRoughness += roughness[i] * w;
                sumWeight += w;
            }
        }
        if (sumWeight > 0)
            return sumRoughness / sumWeight;
        return 0;
    }

    float weightedDot(float3 l, float3 v) // v不影响漫反射强度,但影响受光面的判断
    {
        float sum = 0;
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            float w = weightedNormals[i].w;
            if (w > 0)
            {
                float3 n = weightedNormals[i].xyz;
                float cosTerm = dot(n, v);
                if (cosTerm < 0)
                    n = -n;
                cosTerm = dot(n, l);
                sum += max(cosTerm, 0) * w;
            }
        }
        return sum; // 未归一化
    }

    uint getRandomLobe(float randomArea)
    {
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            if (weightedNormals[i].w <= 0)
                continue;
            randomArea -= weightedNormals[i].w;
            if (randomArea <= 0)
                return i;
        }
        return LOBE_COUNT - 1;
    }

    uint getMainLobe()
    {
        uint maxIndex = 0;
        for (uint i = 1; i < LOBE_COUNT; i++)
        {
            if (weightedNormals[i].w > weightedNormals[maxIndex].w)
                maxIndex = i;
        }
        return maxIndex;
    }
#endif
};

struct ABSDFInput
{
    float3 baseColor;
    float4 specular;
    float3 normal;
    float area;
};

struct ABSDF
{
    float3 diffuse;  // 兰伯特反射率
    float3 specular; // 光线入射和出射方向相同时的菲涅尔反射率
    NDF NDF;
    float area;

    MUTATING
    void init()
    {
        diffuse = float3(0);
        specular = float3(0);
        NDF.init();
        area = 0;
    }

    MUTATING
    void accumulate(ABSDFInput input)
    {
        // StandardMaterial.slang
        float IoR = 1.5f;
        float f = (IoR - 1.f) / (IoR + 1.f);
        float F0 = f * f;

        diffuse += input.area * lerp(input.baseColor, float3(0), input.specular.b);
        specular += input.area * lerp(float3(F0), input.baseColor, input.specular.b);

        uint index = NormalIndex(input.normal);
        NDF.weightedNormals[index] += input.area * float4(input.normal, 1);
        NDF.roughness[index] += input.area * input.specular.g;

        area += input.area;
    }

    MUTATING
    void normalizeSelf()
    {
        if (area == 0)
            return;
        diffuse /= area;
        specular /= area;
        NDF.normalizeSelf();
    }
};

enum class ABSDFDrawMode : uint32_t
{
    Default,
    Diffuse,
    Specular,
    Roughness,
    Normal,
    EllipsoidCenter,
    EllipsoidProjArea,
    PrimitiveProjArea,
    PolygonsProjArea,
    TotalProjArea,
    TotalArea,
    Coverage,
    InternalVisibility,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
        { ABSDFDrawMode::Default, "Default" },
        { ABSDFDrawMode::Diffuse, "Diffuse" },
        { ABSDFDrawMode::Specular, "Specular" },
        { ABSDFDrawMode::Roughness, "Roughness" },
        { ABSDFDrawMode::Normal, "Normal" },
        { ABSDFDrawMode::EllipsoidCenter, "EllipsoidCenter" },
        { ABSDFDrawMode::EllipsoidProjArea, "EllipsoidProjArea" },
        { ABSDFDrawMode::PrimitiveProjArea, "PrimitiveProjArea" },
        { ABSDFDrawMode::PolygonsProjArea, "PolygonsProjArea" },
        { ABSDFDrawMode::TotalProjArea, "TotalProjArea" },
        { ABSDFDrawMode::TotalArea, "TotalArea" },
        { ABSDFDrawMode::Coverage, "Coverage" },
        { ABSDFDrawMode::InternalVisibility, "InternalVisibility" },
    }
);
FALCOR_ENUM_REGISTER(ABSDFDrawMode);

inline float3 valueToColor(float value)
{
    if (value <= 1)
        return float3(value);
    return float3(value, 2 - value, 2 - value);
}

END_NAMESPACE_FALCOR
