#pragma once

#include "VoxelizationBase.h"
#include <Core/Pass/FullScreenPass.h>
#include <Rendering/Lights/EnvMapSampler.h>

using namespace Falcor;

class VoxelDirectAOPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(VoxelDirectAOPass, "VoxelDirectAOPass", "Voxel direct lighting with voxel AO.");

    static ref<VoxelDirectAOPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<VoxelDirectAOPass>(pDevice, props);
    }

    VoxelDirectAOPass(ref<Device> pDevice, const Properties& props);

    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }

private:
    ref<Device> mpDevice;
    ref<Scene> mpScene;
    ref<FullScreenPass> mpFullScreenPass;
    std::unique_ptr<EnvMapSampler> mpEnvMapSampler;

    GridData& gridData;

    uint32_t mDrawMode;
    float mShadowBias100;
    bool mCheckEllipsoid;
    bool mCheckVisibility;
    bool mCheckCoverage;
    bool mUseMipmap;
    bool mUseEmissiveLight;
    bool mRenderBackground;
    bool mAOEnabled;
    uint32_t mAOSampleCount;
    float mAORadius;
    float mAOStrength;
    float3 mClearColor;

    bool mOptionsChanged;
    uint32_t mFrameIndex;
    uint32_t mSelectedResolution;
    uint2 mOutputResolution;
};
