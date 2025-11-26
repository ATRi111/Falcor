#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define LOBE_COUNT 4

inline uint NormalIndex(float3 n)
{
    uint bx = (n.x >= 0) ? 1 : 0; // x≥0 -> 1
    uint bz = (n.z >= 0) ? 1 : 0; // z≥0 -> 1
    return (bx) | (bz << 1);
}

struct NDF
{
    float4 weightedNormals[LOBE_COUNT];

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            weightedNormals[i] = float4(0);
        }
    }

#if defined(HOST_CODE)
    void normalizeSelf()
    {
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            weightedNormals[i] = float4(normalize(weightedNormals[i].xyz()), weightedNormals[i].w);
        }
    }
#else
    [mutating]
    void normalizeSelf()
    {
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            weightedNormals[i] = float4(normalize(weightedNormals[i].xyz), weightedNormals[i].w);
        }
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
    float3 diffuse;
    float3 specular;
    NDF NDF;
    float roughness;
    float area;

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        diffuse = float3(0);
        specular = float3(0);
        NDF.init();
        roughness = 0;
        area = 0;
    }

#if defined(HOST_CODE)
    void accumulate(ABSDFInput &input)
#else
    [mutating]
    void accumulate(ABSDFInput input)
#endif
    {
        // StandardMaterial.slang
        float IoR = 1.5f;
        float f = (IoR - 1.f) / (IoR + 1.f);
        float F0 = f * f;

        diffuse += input.area * lerp(input.baseColor, float3(0), input.specular.b);
        specular += input.area * lerp(float3(F0), input.baseColor, input.specular.b);
        roughness += input.area * input.specular.g;

        uint index = NormalIndex(input.normal);
        NDF.weightedNormals[index] += input.area * float4(input.normal, 1);

        area += input.area;
    }
#if !defined(HOST_CODE)
    [mutating]
#endif
    void normalizeSelf()
    {
        if (area == 0)
            return;
        diffuse /= area;
        specular /= area;
        roughness /= area;
        NDF.normalizeSelf();
    }
};

enum class ABSDFDrawMode : uint32_t
{
    Default,
    Diffuse,
    Specular,
    Flat,
    Normal,
    EllipsoidProjArea,
    TotalArea,
    Coverage,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
    { ABSDFDrawMode::Default, "Default" },
    { ABSDFDrawMode::Diffuse, "Diffuse" },
    { ABSDFDrawMode::Specular, "Specular" },
    { ABSDFDrawMode::Flat, "Flat" },
    { ABSDFDrawMode::Normal, "Normal" },
    { ABSDFDrawMode::EllipsoidProjArea, "EllipsoidProjArea" },
    { ABSDFDrawMode::TotalArea, "TotalArea" },
    { ABSDFDrawMode::Coverage, "Coverage" },
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
