#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define LOBE_COUNT 4
struct NDF
{
    float4 weightedNormals[LOBE_COUNT];
};

struct ABSDF
{
    float3 diffuse;
    float3 specular;
    NDF NDF;
    float roughness;
    float area;
};

enum class ABSDFDrawMode : uint32_t
{
    Default,
    Diffuse,
    Specular,
    Flat,
    Normal,
    Ellipsoid,
    ClippedEllipsoid,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
        { ABSDFDrawMode::Default, "Default" },
        { ABSDFDrawMode::Diffuse, "Diffuse" },
        { ABSDFDrawMode::Specular, "Specular" },
        { ABSDFDrawMode::Flat, "Flat" },
        { ABSDFDrawMode::Normal, "Normal" },
        { ABSDFDrawMode::Ellipsoid, "Ellipsoid" },
        { ABSDFDrawMode::ClippedEllipsoid, "ClippedEllipsoid" },
    }
);
FALCOR_ENUM_REGISTER(ABSDFDrawMode);

END_NAMESPACE_FALCOR
