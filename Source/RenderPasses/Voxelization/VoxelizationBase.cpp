#include "VoxelizationBase.h"
#include "VoxelizationPass.h"
#include "RayMarchingPass.h"
#include "LoadMeshPass.h"
#include "ReadVoxelPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, VoxelizationPass>();
    registry.registerClass<RenderPass, RayMarchingPass>();
    registry.registerClass<RenderPass, LoadMeshPass>();
    registry.registerClass<RenderPass, ReadVoxelPass>();
}

GridData VoxelizationBase::GlobalGridData = {};
uint3 VoxelizationBase::MinFactor = uint3(1, 1, 1);
bool VoxelizationBase::FileUpdated = true;
std::string VoxelizationBase::ResourceFolder = "E:/Project/Falcor/resource/";
