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
    uint2 blockCount() { return uint2(voxelCount.x / BLOCK_TO_VOXEL, voxelCount.y / BLOCK_TO_VOXEL); }

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
    float tMin = 2.0f;
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

inline void leaveBlock(inout float3 cell, inout int3 cellInt, int3 directions, float3 direction, float3 reciprocal_direction)
{
    cellInt /= BLOCK_TO_VOXEL; // 转换到块坐标
    cell /= BLOCK_TO_VOXEL;
    leave(cell, cellInt, directions, direction, reciprocal_direction);
    cellInt *= BLOCK_TO_VOXEL;
    cell *= BLOCK_TO_VOXEL;
}
#endif

END_NAMESPACE_FALCOR
