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

struct ABSDFInput
{
    float3 baseColor;
    float4 specular;
    float3 normal;
    float area;
};

struct ABSDFLobe
{
    float weight;
    float3 normal;
    float rough;
    float3 diffuse;
    float3 specular;

    MUTATING
    void init()
    {
        weight = 0;
        normal = float3(0);
        rough = 0;
        diffuse = float3(0);
        specular = float3(0);
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
        rough += input.area * input.specular.g;
        normal += input.area * input.normal;
        weight += input.area;
    }

    MUTATING
    void normalizeSelf(float area)
    {
        if (weight > 0)
        {
            normal = safeNormalize(normal);
            diffuse /= weight;
            specular /= weight;
            rough /= weight;
            weight /= area;
        }
    }

    bool IsValid() { return weight > 0 && dot(normal, normal) > 0; }
};

struct ABSDF
{
    ABSDFLobe lobes[LOBE_COUNT];
    float area;

    MUTATING
    void init()
    {
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            lobes[i].init();
        }
        area = 0;
    }

    MUTATING
    void accumulate(ABSDFInput input)
    {
        if (input.normal.y < 0)
            input.normal = -input.normal;
        uint index = NormalIndex(input.normal);
        lobes[index].accumulate(input);
        area += input.area;
    }

    MUTATING
    void normalizeSelf()
    {
        if (area == 0)
            return;
        for (int i = 0; i < LOBE_COUNT; i++)
        {
            lobes[i].normalizeSelf(area);
        }
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
