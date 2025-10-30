#include "VoxelizationBase.h"
#include "VoxelizationPass.h"
#include "RayMarchingPass.h"
#include "LoadMeshPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, VoxelizationPass>();
    registry.registerClass<RenderPass, RayMarchingPass>();
    registry.registerClass<RenderPass, LoadMeshPass>();
}

GridData VoxelizationBase::globalGridData = {};
