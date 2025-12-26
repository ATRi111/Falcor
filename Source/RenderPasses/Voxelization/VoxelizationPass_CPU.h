#pragma once
#include "VoxelizationBase.h"
#include "VoxelizationPass.h"
#include "MeshSampler.h"

using namespace Falcor;

class VoxelizationPass_CPU : public VoxelizationPass
{
public:
    FALCOR_PLUGIN_CLASS(VoxelizationPass_CPU, "VoxelizationPass_CPU", "Insert pass description here.");

    static ref<VoxelizationPass_CPU> create(ref<Device> pDevice, const Properties& props) { return make_ref<VoxelizationPass_CPU>(pDevice, props); }

    VoxelizationPass_CPU(ref<Device> pDevice, const Properties& props);

    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual void voxelize(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void sample(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
private:
    ref<ComputePass> mLoadMeshPass;
    MeshSampler meshSampler;
};
