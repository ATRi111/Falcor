#pragma once
#include "HostDeviceShared.slang"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Math/Triangle.slang"
#include "Math/SphericalHarmonics.slang"
BEGIN_NAMESPACE_FALCOR

typedef EvenSphericalHarmonics SphericalFunc;
static const uint kInvalidVoxelInstanceID = 0xffffffffu;

struct VoxelData
{
    ABSDF ABSDF;
    Ellipsoid ellipsoid;
    SphericalFunc primitiveProjAreaFunc;
    SphericalFunc polygonsProjAreaFunc; // Visible projected area for clipped polygons.
    SphericalFunc totalProjAreaFunc;    // Total projected area for all polygon contributors.
    uint dominantInstanceID;
    float identityConfidence;

    MUTATING
    void init()
    {
        ABSDF.init();
        primitiveProjAreaFunc.init();
        polygonsProjAreaFunc.init();
        totalProjAreaFunc.init();
        dominantInstanceID = kInvalidVoxelInstanceID;
        identityConfidence = 0.f;
    }

    bool IsSolid() { return ABSDF.area > 0; }
};

END_NAMESPACE_FALCOR
