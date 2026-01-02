#pragma once
#include "HostDeviceShared.slang"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Math/Triangle.slang"
#include "Math/SphericalHarmonics.slang"
BEGIN_NAMESPACE_FALCOR

typedef EvenSphericalHarmonics SphericalFunc;

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

    bool IsSolid() { return ABSDF.area > 0; }
};

enum class SampleStrategy : uint32_t
{
    EnviromentMap,
    BSDF,
    Mix,
};
FALCOR_ENUM_INFO(
    SampleStrategy,
    { { SampleStrategy::EnviromentMap, "EnviromentMap" }, { SampleStrategy::BSDF, "BSDF" }, { SampleStrategy::Mix, "Mix" } }
);
FALCOR_ENUM_REGISTER(SampleStrategy);

END_NAMESPACE_FALCOR
