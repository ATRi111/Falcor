#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

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

    uint totalVoxelCount() { return voxelCount.x * voxelCount.y * voxelCount.z; }
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

END_NAMESPACE_FALCOR
