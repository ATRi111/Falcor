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
    }
};

END_NAMESPACE_FALCOR
