#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "VoxelizationShared.slang"
using namespace Falcor;

class VoxelizationBase
{
public:
    static GridData GlobalGridData;
    static uint3 MinFactor; // 网格的分辨率必须是此值的整数倍

    static void updateVoxelGrid(ref<Scene> scene, uint voxelResolution)
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
            diag *= 1.2f;
            length *= 1.2f;
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
};
