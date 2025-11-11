#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

struct NDF
{
    float4 weightedNormals[8];
};

struct Ellipsoid
{
    float3 center;
    float3x3 shape;
};

struct GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;

    size_t totalVoxelCount() { return (size_t)voxelCount.x * (size_t)voxelCount.y * (size_t)voxelCount.z; }
};

// TODO:Z-Order Curve
inline int CellToIndex(int3 cell, uint3 size)
{
    return cell.x + cell.y * size.x + cell.z * size.x * size.y;
}

inline int3 IndexToCell(int index, uint3 size)
{
    int z = index / (size.x * size.y);
    int y = (index % (size.x * size.y)) / size.x;
    int x = index % size.x;
    return int3(x, y, z);
}

enum class ABSDFDrawMode : uint32_t
{
    Default,
    Diffuse,
    Specular,
    BaseColor,
    Flat,
    Normal,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
        { ABSDFDrawMode::Default, "Default" },
        { ABSDFDrawMode::Diffuse, "Diffuse" },
        { ABSDFDrawMode::Specular, "Specular" },
        { ABSDFDrawMode::BaseColor, "BaseColor" },
        { ABSDFDrawMode::Flat, "Flat" },
        { ABSDFDrawMode::Normal, "Normal" },
    }
);
FALCOR_ENUM_REGISTER(ABSDFDrawMode);

END_NAMESPACE_FALCOR
