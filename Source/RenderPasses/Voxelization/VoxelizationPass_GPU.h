#pragma once
#include "VoxelizationBase.h"
#include "VoxelizationPass.h"

using namespace Falcor;

class VoxelizationPass_GPU : public VoxelizationPass
{
public:
    FALCOR_PLUGIN_CLASS(VoxelizationPass_GPU, "VoxelizationPass_GPU", "Insert pass description here.");

    static ref<VoxelizationPass_GPU> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<VoxelizationPass_GPU>(pDevice, props);
    }

    VoxelizationPass_GPU(ref<Device> pDevice, const Properties& props);

    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

    virtual void voxelize(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void sample(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual std::string getFileName() override;

private:
    uint maxSolidVoxelCount;
    ref<ComputePass> mSampleMeshPass;
    ref<ComputePass> mClipPolygonPass;

    ref<Buffer> vBuffer; // GPU上的vBuffer对于CPU管线来说不需要
    ref<Buffer> polygonCountBuffer;
    std::vector<uint> vBuffer_CPU;
    double mSolidRate;
};
