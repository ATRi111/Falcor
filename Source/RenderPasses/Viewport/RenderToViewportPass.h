#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "Core/Pass/FullScreenPass.h"

using namespace Falcor;

class RenderToViewportPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(RenderToViewportPass, "RenderToViewportPass", "");

    static ref<RenderToViewportPass> create(ref<Device> pDevice, const Properties& props) { return make_ref<RenderToViewportPass>(pDevice, props); }

    RenderToViewportPass(ref<Device> pDevice, const Properties& props);

    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
private:
    ref<FullScreenPass> mpFullScreenPass;
    ref<Sampler> mpSampler;

    bool mEnable;
    uint2 mOutputMin;
    uint2 mOutputSize;
    bool mOptionsChanged;
};

