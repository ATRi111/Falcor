#pragma once
#include "Voxel/VoxelGrid.slang"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "Math/VoxelizationUtility.h"
#include "Math/Random.h"
#include "VoxelizationShared.slang"
#include <random>
using namespace Falcor;

inline std::string ToString(size_t n)
{
    std::ostringstream oss;
    oss << n;
    return oss.str();
}
inline std::string ToString(float3 v)
{
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(4);
    oss << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    return oss.str();
}
inline std::string ToString(uint3 v)
{
    std::ostringstream oss;
    oss << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    return oss.str();
}

struct BufferDesc
{
    std::string name;      
    std::string texname;   //如果不直接对应着色器资源，设为空字符串
    std::string desc;
    bool serialized;
    bool isInputOrOutut;
    size_t bytesPerElement;
};
using BufferlList = std::vector<BufferDesc>;

inline std::string kGBuffer = "gBuffer";
inline std::string kVBuffer = "vBuffer";
inline std::string kPolygonBuffer = "polygonBuffer";

class VoxelizationBase
{
public:
    static const int NDFLobeCount = 8;
    static GridData GlobalGridData;
    static uint3 MinFactor; // 网格的分辨率必须是此值的整数倍
    static bool FileUpdated;
    static std::string ResourceFolder;

    static void UpdateVoxelGrid(ref<Scene> scene, uint voxelResolution)
    {
        float3 diag;
        float length;
        float3 center;
        if (scene)
        {
            AABB aabb = scene->getSceneBounds();
            diag = aabb.maxPoint - aabb.minPoint;
            length = std::max(diag.z, std::max(diag.x, diag.y));
            center = aabb.center();
            diag *= 1.02f;
            length *= 1.02f;
        }
        else
        {
            diag = float3(1);
            length = 1.f;
            center = float3(0);
        }

        GlobalGridData.voxelSize = float3(length / voxelResolution);
        float3 temp = diag / GlobalGridData.voxelSize;

        GlobalGridData.voxelCount = uint3(
            (uint)math::ceil(temp.x / MinFactor.x) * MinFactor.x,
            (uint)math::ceil(temp.y / MinFactor.y) * MinFactor.y,
            (uint)math::ceil(temp.z / MinFactor.z) * MinFactor.z
        );
        GlobalGridData.gridMin = center - 0.5f * GlobalGridData.voxelSize * float3(GlobalGridData.voxelCount);
        GlobalGridData.solidVoxelCount = 0;
    }
};

struct SceneHeader
{
    uint meshCount;
    uint vertexCount;
    uint triangleCount;
};

struct MeshHeader
{
    uint materialID;
    uint vertexCount;
    uint triangleCount;
    uint triangleOffset;
};
