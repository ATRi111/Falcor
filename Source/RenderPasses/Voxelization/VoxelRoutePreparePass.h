#pragma once

#include "VoxelizationBase.h"
#include <Core/Pass/ComputePass.h>

using namespace Falcor;

class VoxelRoutePreparePass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(VoxelRoutePreparePass, "VoxelRoutePreparePass", "Build route-aware voxel block maps for LOD execution.");

    static ref<VoxelRoutePreparePass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<VoxelRoutePreparePass>(pDevice, props);
    }

    VoxelRoutePreparePass(ref<Device> pDevice, const Properties& props);

    Properties getProperties() const override;
    RenderPassReflection reflect(const CompileData& compileData) override;
    void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    void renderUI(Gui::Widgets& widget) override;
    void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

private:
    ref<Device> mpDevice;
    ref<Scene> mpScene;
    ref<ComputePass> mpComputePass;
    GridData& gridData;
    uint32_t mInstanceRouteMask = Scene::kAllGeometryInstanceRenderRoutesMask;
};
