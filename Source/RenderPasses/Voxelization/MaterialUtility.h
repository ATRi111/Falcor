#pragma once
#include "Falcor.h"
#include "VoxelizationShared.Slang"

struct ABSDF
{
    float3 diffuse;
    float3 specular;
    NDF NDF;
    float roughness;
    float area;

    void Normalize()
    {
        if (area == 0)
            return;
        diffuse /= area;
        specular /= area;
        roughness /= area;
        for (uint i = 0; i < LOBE_COUNT; i++)
        {
            float4 temp = NDF.weightedNormals[i];
            temp = float4(math::normalize(temp.xyz()), temp.w);
            NDF.weightedNormals[i] = temp;
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

class MaterialUtility
{
private:
    static uint NormalIndex(float3 n)
    {
        uint bx = (n.x >= 0.0f) ? 1u : 0u; // x≥0 -> 1
        uint bz = (n.z >= 0.0f) ? 1u : 0u; // z≥0 -> 1
        return (bx) | (bz << 1);
    }

public:
    static void Accumulate(ABSDF& ABSDF, const ABSDFInput& input)
    {
        // StandardMaterial.slang
        float IoR = 1.5f;
        float f = (IoR - 1.f) / (IoR + 1.f);
        float F0 = f * f;

        ABSDF.diffuse += input.area * math::lerp(input.baseColor, float3(0), input.specular.b);
        ABSDF.specular += input.area * math::lerp(float3(F0), input.baseColor, input.specular.b);
        ABSDF.roughness += input.area * input.specular.g;

        uint index = NormalIndex(input.normal);
        ABSDF.NDF.weightedNormals[index] += input.area * float4(input.normal, 1);

        ABSDF.area += input.area;
    }
};
