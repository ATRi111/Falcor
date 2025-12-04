#pragma once
#include "HostDeviceShared.slang"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Math/Triangle.slang"
#include "Math/SphericalHarmonics.slang"
BEGIN_NAMESPACE_FALCOR

struct VoxelData
{
    ABSDF ABSDF;
    Ellipsoid ellipsoid;
    SphericalHarmonics primitiveProjAreaFunc;
    SphericalHarmonics polygonsProjAreaFunc;

    MUTATING
    void init()
    {
        ABSDF.init();
        primitiveProjAreaFunc.init();
        polygonsProjAreaFunc.init();
    }

    float calcCoverage(float3 v)
    {
        float primitiveProjArea = primitiveProjAreaFunc.calc(v);
        if (primitiveProjArea <= 0)
            return 1;
        float polygonsProjArea = polygonsProjAreaFunc.calc(v);
        return saturate(polygonsProjArea / primitiveProjArea);
    }
};

END_NAMESPACE_FALCOR
