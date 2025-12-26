#pragma once
#include "HostDeviceShared.slang"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Math/Triangle.slang"
#include "Math/SphericalHarmonics.slang"
BEGIN_NAMESPACE_FALCOR

typedef SphericalHarmonics SphericalFunc;

struct VoxelData
{
    ABSDF ABSDF;
    Ellipsoid ellipsoid;
    SphericalFunc primitiveProjAreaFunc;
    SphericalFunc polygonsProjAreaFunc; // 所有多边形的可见投影面积
    SphericalFunc totalProjAreaFunc;    // 所有多边形的总投影面积

    MUTATING
    void init()
    {
        ABSDF.init();
        primitiveProjAreaFunc.init();
        polygonsProjAreaFunc.init();
        totalProjAreaFunc.init();
    }

    float calcCoverage(float3 direction)
    {
        float primitiveProjArea = primitiveProjAreaFunc.calc(direction);
        if (primitiveProjArea <= 0)
            return 1;
        float polygonsProjArea = polygonsProjAreaFunc.calc(direction);
        return saturate(polygonsProjArea / primitiveProjArea);
    }

    float calcInternalVisibility(float3 direction) // 内部可见度
    {
        float totalProjArea = totalProjAreaFunc.calc(direction);
        if (totalProjArea <= 0)
            return 1;
        float polygonsProjArea = polygonsProjAreaFunc.calc(direction);
        return saturate(polygonsProjArea / totalProjArea);
    }
};

enum class SampleStretegy : uint32_t
{
    EnviromentMap,
    BSDF,
    Mix,
};
FALCOR_ENUM_INFO(
    SampleStretegy,
    {
    { SampleStretegy::EnviromentMap, "EnviromentMap" },
    { SampleStretegy::BSDF, "BSDF" },
    { SampleStretegy::Mix, "Mix" }
}
);
FALCOR_ENUM_REGISTER(SampleStretegy);

END_NAMESPACE_FALCOR
