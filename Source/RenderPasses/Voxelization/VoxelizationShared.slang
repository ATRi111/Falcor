#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define LOBE_COUNT 4
#define PI 3.14159265358

struct NDF
{
    float4 weightedNormals[LOBE_COUNT];
};

struct Basis2
{
    float3 u;
    float3 v;
};

struct Ellipsoid
{
    float3 center; // 相对于所在体素左下角的偏移量
    float3x3 shape;
    float det;

    float projectArea(float3 direction)
    {
        direction = normalize(direction);
        float A = dot(direction, mul(shape, direction));
        return PI * sqrt(A / det);
    }

    bool contains(float3 p, float epsilon)
    {
        float3 offset = p - center;
        float d = dot(offset, mul(shape, offset));
        return d <= (1.0 + epsilon);
    }
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
    Flat,
    Normal,
    Ellipsoid,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
        { ABSDFDrawMode::Default, "Default" },
        { ABSDFDrawMode::Diffuse, "Diffuse" },
        { ABSDFDrawMode::Specular, "Specular" },
        { ABSDFDrawMode::Flat, "Flat" },
        { ABSDFDrawMode::Normal, "Normal" },
        { ABSDFDrawMode::Ellipsoid, "Ellipsoid" },
    }
);
FALCOR_ENUM_REGISTER(ABSDFDrawMode);

END_NAMESPACE_FALCOR
