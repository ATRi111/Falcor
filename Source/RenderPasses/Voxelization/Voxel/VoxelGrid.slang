#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define DIAG 1.7320508
#define DIAG_2 0.8660254

struct AABBInt
{
    int3 min;
    int3 max;
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

END_NAMESPACE_FALCOR
