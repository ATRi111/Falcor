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
    SphericalHarmonics primitiveArea;
    SphericalHarmonics polygonArea;
};

END_NAMESPACE_FALCOR
