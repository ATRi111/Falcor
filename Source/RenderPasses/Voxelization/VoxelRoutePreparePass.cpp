#include "VoxelRoutePreparePass.h"
#include "Shading.slang"

namespace
{
const std::string kShaderFile = "RenderPasses/Voxelization/VoxelRoutePrepare.cs.slang";
const std::string kPropInstanceRouteMask = "instanceRouteMask";
}

VoxelRoutePreparePass::VoxelRoutePreparePass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice), mpDevice(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    for (const auto& [key, value] : props)
    {
        if (key == kPropInstanceRouteMask)
            mInstanceRouteMask = uint32_t(value) & Scene::kAllGeometryInstanceRenderRoutesMask;
        else
            logWarning("Unknown property '{}' in a VoxelRoutePreparePass properties.", key);
    }
}

Properties VoxelRoutePreparePass::getProperties() const
{
    Properties props;
    props[kPropInstanceRouteMask] = mInstanceRouteMask;
    return props;
}

RenderPassReflection VoxelRoutePreparePass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput(kGBuffer, kGBuffer)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(PrimitiveBSDF));

    reflector.addInput(kSolidVoxelCellBuffer, "Solid voxel cell coordinates")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(int3));

    reflector.addOutput(kSolidVoxelAcceptedRouteMask, "Accepted route mask per solid voxel")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(uint32_t));

    reflector.addOutput(kResolvedBlockMap, "Route-aware voxel block map")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.totalBlockCount() * sizeof(uint4));

    return reflector;
}

void VoxelRoutePreparePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    ref<Buffer> pSolidVoxelAcceptedRouteMask = renderData.getResource(kSolidVoxelAcceptedRouteMask)->asBuffer();
    FALCOR_ASSERT(pSolidVoxelAcceptedRouteMask);
    pRenderContext->clearUAV(pSolidVoxelAcceptedRouteMask->getUAV().get(), uint4(0));

    ref<Buffer> pResolvedBlockMap = renderData.getResource(kResolvedBlockMap)->asBuffer();
    FALCOR_ASSERT(pResolvedBlockMap);
    pRenderContext->clearUAV(pResolvedBlockMap->getUAV().get(), uint4(0));

    if (!mpScene || gridData.solidVoxelCount == 0)
        return;

    if (!mpComputePass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kShaderFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines = mpScene->getSceneDefines();
        mpComputePass = ComputePass::create(mpDevice, desc, defines, true);
    }

    auto var = mpComputePass->getRootVar();
    mpScene->bindShaderData(var["gScene"]);
    var[kGBuffer] = renderData.getResource(kGBuffer)->asBuffer();
    var[kSolidVoxelCellBuffer] = renderData.getResource(kSolidVoxelCellBuffer)->asBuffer();
    var[kSolidVoxelAcceptedRouteMask] = pSolidVoxelAcceptedRouteMask;
    var[kResolvedBlockMap] = pResolvedBlockMap;

    auto cb = var["CB"];
    cb["solidVoxelCount"] = static_cast<uint32_t>(gridData.solidVoxelCount);
    cb["blockCountX"] = gridData.blockCount().x;
    cb["executionRouteMask"] = mInstanceRouteMask;

    mpComputePass->execute(pRenderContext, uint3(static_cast<uint32_t>(gridData.solidVoxelCount), 1, 1));
}

void VoxelRoutePreparePass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void VoxelRoutePreparePass::renderUI(Gui::Widgets& widget) {}

void VoxelRoutePreparePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpComputePass = nullptr;
}
