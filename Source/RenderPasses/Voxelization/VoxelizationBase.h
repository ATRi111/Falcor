#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "VoxelizationShared.slang"
using namespace Falcor;

class VoxelizationBase
{
public:
    static GridData globalGridData;
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
