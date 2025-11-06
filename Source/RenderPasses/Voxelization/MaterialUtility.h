#pragma once
#include "Falcor.h"

struct ABSDF
{
    float4 diffuse;
    float4 specular;
};

struct ABSDFInput
{
    float3 baseColor;
    float4 specular;
};

class MaterialUtility
{
public:
    static ABSDF CalcABSDF(const ABSDFInput& input)
    {
        ABSDF absdf = {};
        // StandardMaterial.slang
        float IoR = 1.5f;
        float f = (IoR - 1.f) / (IoR + 1.f);
        float F0 = f * f;

        absdf.diffuse = float4(math::lerp(input.baseColor, float3(0), input.specular.b), 1);
        absdf.specular = float4(math::lerp(float3(F0), input.baseColor, input.specular.b), 1);
        // d.roughness = spec.g;
        // d.metallic = spec.b;
        return absdf;
    }
};
