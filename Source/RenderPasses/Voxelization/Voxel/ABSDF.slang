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
    void normalizeSelf(float area)
    {
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            float w = weightedNormals[i].w;
            if (w > 0)
            {
#if defined(HOST_CODE)
                float3 n = weightedNormals[i].xyz();
#else
                float3 n = weightedNormals[i].xyz;
#endif

                n = safeNormalize(n);
                roughness[i] /= weightedNormals[i].w;
                weightedNormals[i] = float4(n, w / area);
            }
            else
            {
                roughness[i] = 0;
                weightedNormals[i] = float4(0);
            }
        }
    }
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
        NDF.normalizeSelf(area);
    }
};

enum class ABSDFDrawMode : uint32_t
{
    Default,
    Normal,
    Ellipsoid,
    EllipsoidProjArea,
    PrimitiveProjArea,
    PolygonsProjArea,
    TotalProjArea,
    Coverage,
    InternalVisibility,
    TotalArea,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
        { ABSDFDrawMode::Default, "Default" },
        { ABSDFDrawMode::Normal, "Normal" },
        { ABSDFDrawMode::Ellipsoid, "Ellipsoid" },
        { ABSDFDrawMode::EllipsoidProjArea, "EllipsoidProjArea" },
        { ABSDFDrawMode::PrimitiveProjArea, "PrimitiveProjArea" },
        { ABSDFDrawMode::PolygonsProjArea, "PolygonsProjArea" },
        { ABSDFDrawMode::TotalProjArea, "TotalProjArea" },
        { ABSDFDrawMode::Coverage, "Coverage" },
        { ABSDFDrawMode::InternalVisibility, "InternalVisibility" },
        { ABSDFDrawMode::TotalArea, "TotalArea" },
    }
);
FALCOR_ENUM_REGISTER(ABSDFDrawMode);

#if !defined(HOST_CODE)
inline float3 valueToColor(float value)
{
    if (value <= 1)
        return float3(value);
    return float3(value, 2 - value, 2 - value);
}

inline float3 pdfToColor(float pdf, float refPdf)
{
    float k = pdf / refPdf;
    // 蓝(0)->青->绿->黄->红(1)->黑(5)渐变
    float3 c;
    c.r = smoothstep(0.4, 1.0, k) - smoothstep(1.0, 5.0, k);
    c.g = smoothstep(0.0, 0.4, k) - smoothstep(0.6, 1.0, k);
    c.b = smoothstep(0.4, 0.0, k);
    return c;
}
#endif

END_NAMESPACE_FALCOR
