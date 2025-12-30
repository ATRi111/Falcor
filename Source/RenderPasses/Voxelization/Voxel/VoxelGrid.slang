#pragma once
#include "../HostDeviceShared.slang"

BEGIN_NAMESPACE_FALCOR

#define DIAG 1.7320508
// 体素外接球投影而得的圆的面积
#define PROJECT_CIRCLE_AREA 2.35619449
#define BLOCK_TO_VOXEL 8

struct GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
    size_t solidVoxelCount;

    size_t totalVoxelCount() { return (size_t)voxelCount.x * (size_t)voxelCount.y * (size_t)voxelCount.z; }
    uint2 blockCount()
    {
        return uint2((voxelCount.x + BLOCK_TO_VOXEL - 1) / BLOCK_TO_VOXEL, (voxelCount.y + BLOCK_TO_VOXEL - 1) / BLOCK_TO_VOXEL);
    }

    uint3 blockCount3D()
    {
        return uint3((voxelCount.x + BLOCK_TO_VOXEL - 1) / BLOCK_TO_VOXEL, (voxelCount.y + BLOCK_TO_VOXEL - 1) / BLOCK_TO_VOXEL, (voxelCount.z + BLOCK_TO_VOXEL - 1) / BLOCK_TO_VOXEL);
    }

    uint totalBlockCount()
    {
        uint2 temp = blockCount();
        return temp.x * temp.y;
    }
};

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

#if !defined(HOST_CODE)
// DDA
inline void leave(inout float3 cell, inout int3 cellInt, int3 directions, float3 direction, float3 reciprocal_direction)
{
    float3 border = cellInt + (directions + 1) / 2;
    float3 t = (border - cell) * reciprocal_direction;
    float tMin = 2;
    int3 selectedDirection = 0;
    if (direction.x != 0 && t.x < tMin)
    {
        tMin = t.x;
        selectedDirection = int3(directions.x, 0, 0);
    }
    if (direction.y != 0 && t.y < tMin)
    {
        tMin = t.y;
        selectedDirection = int3(0, directions.y, 0);
    }
    if (direction.z != 0 && t.z < tMin)
    {
        tMin = t.z;
        selectedDirection = int3(0, 0, directions.z);
    }

    cell += tMin * direction;
    cellInt += selectedDirection;
}

inline float leaveBlockFace(float c, int cInt, float reciprocal)
{
    int temp = cInt % BLOCK_TO_VOXEL;
    float t = -1;
    if (reciprocal < 0)
        t = (cInt - temp - c) * reciprocal;
    if (reciprocal > 0)
        t = (cInt - temp + BLOCK_TO_VOXEL - c) * reciprocal;
    return t > 0 ? t : 1e30;
}

inline void leaveBlock(inout float3 cell, inout int3 cellInt, int3 directions, float3 direction, float3 reciprocal_direction)
{
    float tMin = 2 * BLOCK_TO_VOXEL;
    float t = leaveBlockFace(cell.x, cellInt.x, reciprocal_direction.x);
    tMin = min(t, tMin);
    t = leaveBlockFace(cell.y, cellInt.y, reciprocal_direction.y);
    tMin = min(t, tMin);
    t = leaveBlockFace(cell.z, cellInt.z, reciprocal_direction.z);
    tMin = min(t, tMin);
    cell += tMin * direction;
    cellInt = int3(cell + direction * 1e-3);
}
#endif

END_NAMESPACE_FALCOR
