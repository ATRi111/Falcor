#pragma once
#include "Falcor.h"
#include "VoxelizationShared.Slang"

struct ABSDF
{
    float4 diffuse;
    float4 specular;
    NDF NDF;
    float area;
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
        uint bx = (n.x >= 0.0f) ? 1u : 0u;   // x≥0 -> 1
        uint by = (n.y >= 0.0f) ? 1u : 0u;   // y≥0 -> 1
        uint bz = (n.z >= 0.0f) ? 1u : 0u;   // z≥0 -> 1
        return (bx) | (by << 1) | (bz << 2); // 0..7
    }

public:
    static void Accumulate(ABSDF& ABSDF, const ABSDFInput& input)
    {
        // StandardMaterial.slang
        float IoR = 1.5f;
        float f = (IoR - 1.f) / (IoR + 1.f);
        float F0 = f * f;

        // d.roughness = spec.g;
        // d.metallic = spec.b;

        ABSDF.diffuse += input.area * float4(math::lerp(input.baseColor, float3(0), input.specular.b), 1);
        ABSDF.specular += input.area * float4(math::lerp(float3(F0), input.baseColor, input.specular.b), 1);

        uint index = NormalIndex(input.normal);
        ABSDF.NDF.weightedNormals[index] += input.area * float4(input.normal, 1);
        index = NormalIndex(-input.normal);
        ABSDF.NDF.weightedNormals[index] += input.area * float4(-input.normal, 1);

        ABSDF.area += input.area;
    }
};
