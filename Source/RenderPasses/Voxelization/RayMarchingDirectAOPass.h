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

    virtual Properties getProperties() const override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

private:
    void parseProperties(const Properties& props);

    ref<Scene> mpScene;
    ref<FullScreenPass> mpFullScreenPass;

    GridData& gridData;
    uint mDrawMode;
    float mShadowBias100;
    bool mCheckEllipsoid;
    bool mCheckVisibility;
    bool mCheckCoverage;
    bool mUseMipmap;
    bool mRenderBackground;
    bool mAOEnabled;
    bool mOptionsChanged;
    bool mAOUseStableRotation;
    uint mFrameIndex;
    uint mAOStepCount;
    uint mAODirectionSet;
    uint mSelectedResolution;
    uint2 mOutputResolution;
    float mAOStrength;
    float mAORadius;
    float mAOContactStrength;
    float mTransmittanceThreshold100;
};
