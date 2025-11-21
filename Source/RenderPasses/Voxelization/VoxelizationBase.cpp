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

const std::string kInputDiffuse = "diffuse";
const std::string kInputSpecular = "specular";
const std::string kInputRoughness = "roughness";
const std::string kInputArea = "area";
const ChannelList VoxelizationBase::Channels = {
    // clang-format off
    { "diffuse",        "gDiffuse",         "Diffuse Color",            true, ResourceFormat::RGB32Float },
    { "specular",       "gSpecular",        "Specular Color",           true, ResourceFormat::RGB32Float },
    { "roughness",      "gRoughness",       "Roughness",                true, ResourceFormat::R32Float },
    { "area",           "gArea",            "Area",                     true, ResourceFormat::R32Float },
    // clang-format on
};

const BufferlList VoxelizationBase::Buffers = {
    // clang-format off
    { "ABSDF",          "",                 "ABSDF",                     true, false,  sizeof(ABSDF)     },
    { "ellipsoid",      "gEllipsoid",       "Ellipsoid parameters",      true, true,   sizeof(Ellipsoid) },
    { "NDFLobes",       "gNDFLobes",        "NDF Lobes",                 false,true,   sizeof(NDF)       },
    { "visibilitySH",   "gVisibilitySH",    "SH of visibility",          true, true,   sizeof(SphericalHarmonics) },
    { "polygonAreaSH",  "gPolygonAreaSH",   "SH of polygon Area",        true, true,   sizeof(SphericalHarmonics) },
    // clang-format on
};
