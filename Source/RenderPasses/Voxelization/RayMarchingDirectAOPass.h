#pragma once

#include "VoxelizationBase.h"
#include <Core/Pass/FullScreenPass.h>

using namespace Falcor;

class RayMarchingDirectAOPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(RayMarchingDirectAOPass, "RayMarchingDirectAOPass", "Mainline voxel direct lighting and AO pass.");

    static ref<RayMarchingDirectAOPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<RayMarchingDirectAOPass>(pDevice, props);
    }

    RayMarchingDirectAOPass(ref<Device> pDevice, const Properties& props);

    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

private:
    ref<Scene> mpScene;
    ref<FullScreenPass> mpFullScreenPass;

    GridData& gridData;
    bool mOptionsChanged;
    uint mFrameIndex;
    uint mSelectedResolution;
    uint2 mOutputResolution;
};
