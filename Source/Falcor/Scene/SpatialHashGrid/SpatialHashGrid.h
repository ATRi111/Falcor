// Copyright (c) 2020, NVIDIA CORPORATION. All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
#pragma once
#include "Core/Pass/ComputePass.h"
#include "Falcor.h"

#include "Core/Macros.h"
#include "Core/API/Buffer.h"
#include "Core/API/Texture.h"

//#include <rtx/PathTracingParams.h>
//#include <rtx/raytracing/PathTracing.h>

#include <array>
#include <memory>

#include "SpatialHashGrid.h"
#include "SpatialHashGridParams.slang"
#include "Utils/Debug/PixelDebug.h"

namespace Falcor
{
constexpr uint32_t getNumEntries()
{
    // 8 times the default size
    return 65536u * 8u;// (8u * 1024u * 8u); // Place holder may need less entries for LC as we progress. Max size atm is 16k
                                             // (limited by texture max dim)
}
class FALCOR_API SpatialHashGrid
{
public:

    /// Cached params from the UI
    struct SpatialHashGridSettings
    {
        float retrace = 0.f;
        int32_t temporalReuse = 48;
        float temporalAlpha = .2f;
        uint32_t maxAgeForEviction = 100;
        bool enableSpatialJittering = false;
        bool enableDirectionalJittering = false;
        bool enableLODJittering = false;
        bool enableNanChecks = true;
        int32_t showDebugView = 0;

        bool dimUnusedEntries = false;
        bool dontResolveConflicts = false;

        // Flag to switch between cone based and distance based hash
        bool useDistanceBasedHash= true;

        // Params for cone-based hash (if useDistanceBasedHash==false)
        uint32_t clampVoxelSize = 12;
        int32_t voxelSize = 5;

        // Params for distance-based hash (if useDistanceBasedHash==true)
        uint32_t distanceBasedHashP0 = 400;
        uint32_t distanceBasedHashP1 = 4;
        float distanceOverride = 0.f; // to limit the min size of the voxel when distance-based hash is used (very large float by default)

        bool forceReset = false;
    };

    struct SpatialHashGridResources
    {
        ref<Buffer> HashKey;
        // ref<Buffer> PrevHashKey;
        ref<Buffer> TimeStamps;
        ref<Buffer> OverrideFlags;
        ref<Buffer> HashMapValues;
        // ref<Buffer> PrevHashMapValues;
        ref<Buffer> HashMapNewValues;
        ref<Buffer> VoxelSizeParams;
        ref<Buffer> HashMapCounter;
        ref<Texture> HashMapAuxBuffer;
        // ref<Texture> PrevHashMapAuxBuffer;
        // Used by lightcache for light selection
        //ref<Buffer> outHashMapLightInvCdf;
        //ref<Buffer> outHashMapLightIndices;
        ref<Buffer> MoVMFBuffer;
    };

    using SharedPtr = std::shared_ptr<SpatialHashGrid>;

    static SpatialHashGrid::SharedPtr create(ref<Device> pDevice, DirectionalDistType type);

    /// Build pipelines for cache management, etc
    void initialize(DirectionalDistType type);

    /// Call in the beginning of the frame to populate SpatialHashGridParams (inits it to 0 on first frame)
    void setupResources(
                        RenderContext* pRenderContext,
                        std::unique_ptr<PixelDebug>& pPixelDebug,
                        bool forceReset = false);

    /// Call after frame to merge/evict new/old data from the cache
    void processCache(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug);

    void runOnePassEM(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug);

    void beginFrame(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug, bool forceReset=false, bool useReSTIRSamples=false);

    /// Binds the resources from previous frame to the current one, so we reuse the data for the spatial hash
    void endFrame(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug);

    // controls parameters
    bool renderUI(Gui::Widgets& widget);

    ref<ParameterBlock> getParameterBlock();

    DirectionalDistType getType() { return m_type; }

private:

    SpatialHashGrid(ref<Device> pDevice, DirectionalDistType type);

    void createComputePass(ref<ComputePass>& pPass, std::string shaderFile, DefineList defines, ProgramDesc baseDesc, std::string entryFunction);

    /// This SpatialHashGridContext is owned by the path tracer and expects some basic functionality,
    /// even if it cannot run the algorithm itself. E.g. it cannot be run under Vulkan (because of atomics)
    // but still needs to generate a parameter block.

    /// The spatial hash structure is shared across different algorithms, the code is parameterized by type
    DirectionalDistType m_type = DirectionalDistType::Histogram;
    bool mUseReSTIRSamples = false;

    //
    ref<ParameterBlock>       mpSpatialHashGridBlock;          ///< Parameter block for the spatial hash grid.
    SpatialHashGridSettings mParameters;

    ref<ComputePass>  m_hashMapClearAllPipeline;
    ref<ComputePass>  m_hashMapClearNewCachePipeline;
    ref<ComputePass> m_hashMapInitMoVMFPipeline;
    ref<ComputePass> m_hashMapResolveMoVMFPipeline;
    ref<ComputePass>  m_hashMapEvictPipeline;
    ref<ComputePass>  m_hashMapCalculateVoxelSize;
    ref<ComputePass>  m_hashMapCombinePipeline;
    ref<ComputePass>  m_lightCacheNumLightsChangedPipeline;
    ref<ComputePass>  mpReflectTypes;

    SpatialHashGridResources mBuffers;

    //void updatePipelines();
    void initParamBlock(uint32_t frameNumber,
                        uint32_t numElementsPerEntry,
                        uint32_t strideElementsPerEntry,
                        uint32_t entryStride);
    uint32_t mFrameCount = 0;

    ref<Device> mpDevice; ///< GPU device.
};

} //
