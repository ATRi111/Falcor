#pragma once
#include "VoxelizationBase.h"
#include "VoxelizationPass.h"
#include "MeshSampler.h"
#include <atomic>
#include <future>
#include <memory>

using namespace Falcor;

class VoxelizationPass_CPU : public VoxelizationPass
{
public:
    FALCOR_PLUGIN_CLASS(VoxelizationPass_CPU, "VoxelizationPass_CPU", "Insert pass description here.");

    static ref<VoxelizationPass_CPU> create(ref<Device> pDevice, const Properties& props) { return make_ref<VoxelizationPass_CPU>(pDevice, props); }

    VoxelizationPass_CPU(ref<Device> pDevice, const Properties& props);
    virtual ~VoxelizationPass_CPU() override;

    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual void voxelize(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void sample(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;

    virtual std::string getFileName() override;

private:
    enum class AsyncClipState
    {
        Idle,
        Pending,
        ReadyToFinalize,
    };

    struct AsyncClipInput
    {
        GridData gridData;
        SceneHeader header;
        std::vector<InstanceHeader> instanceList;
        std::vector<float3> positions;
        std::vector<float3> normals;
        std::vector<float2> texCoords;
        std::vector<uint3> triangles;
    };

    struct AsyncClipResult
    {
        bool cancelled = false;
        double durationMs = 0.0;
        GridData gridData;
        std::vector<VoxelData> gBuffer;
        std::vector<int> vBuffer;
        std::vector<std::vector<Polygon>> polygonArrays;
        std::vector<PolygonRange> polygonRangeBuffer;
    };

    void ensureLoadMeshPass();
    void startAsyncClip(RenderContext* pRenderContext);
    void releaseAsyncClipTaskResources();
    void clearAsyncClipControlState();
    void waitForAsyncClipTask();
    static AsyncClipResult runAsyncClipTask(
        AsyncClipInput input,
        const std::shared_ptr<std::atomic_bool>& pCancelRequested,
        const std::shared_ptr<std::atomic<uint64_t>>& pProcessedTriangles
    );

    ref<ComputePass> mLoadMeshPass;
    std::future<AsyncClipResult> mAsyncClipTask;
    AsyncClipState mAsyncClipState = AsyncClipState::Idle;
    std::shared_ptr<std::atomic_bool> mpAsyncCancelRequested;
    std::shared_ptr<std::atomic<uint64_t>> mpAsyncProcessedTriangles;
    uint64_t mAsyncTotalTriangles = 0;
    bool mAsyncCancellationRequestedByUser = false;
    std::vector<int> mVBufferCpu;

protected:
    virtual size_t estimatePeakWorkingSetBytes() const override;
    virtual const char* getGenerationBackendName() const override { return "CPU voxelization"; }
    virtual bool canFinalizeVoxelizationStage() const override;
    virtual void onVoxelizationStageFinalized() override;
    virtual bool canCancelGeneration() const override;
    virtual void cancelGeneration() override;
    virtual std::string getGenerationStatusText() const override;
};
