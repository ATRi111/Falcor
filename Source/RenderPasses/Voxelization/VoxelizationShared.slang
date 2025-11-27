#pragma once
#include "Utils/HostDeviceShared.slangh"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Math/SphericalHarmonics.slang"
BEGIN_NAMESPACE_FALCOR

struct VoxelData
{
    ABSDF ABSDF;
    Ellipsoid ellipsoid;
    SphericalHarmonics primitiveProjAreaFunc;
    SphericalHarmonics polygonsProjAreaFunc;

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        ABSDF.init();
    }
};

END_NAMESPACE_FALCOR
