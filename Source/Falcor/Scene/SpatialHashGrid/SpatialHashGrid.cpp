// Copyright (c) 2020, NVIDIA CORPORATION. All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
#include "SpatialHashGrid.h"
#include <memory>
#include "Scene/SpatialHashGrid/SpatialHashGridParams.slang"

namespace Falcor
{
static uint32_t getLaunchDimensions1d(uint32_t totalThreadSize, uint32_t shaderGroupSize)
{
    return (totalThreadSize + shaderGroupSize - 1) / shaderGroupSize;
}
SpatialHashGrid::SpatialHashGrid(ref<Device> pDevice, DirectionalDistType type)
{
    mpDevice = pDevice;
    // currently we only support grid for ray guiding
    initialize(type);
}

void SpatialHashGrid::createComputePass(
    ref<ComputePass>& pPass,
    std::string shaderFile,
    DefineList defines,
    ProgramDesc baseDesc,
    std::string entryFunction
)
{
    if (!pPass)
    {
        ProgramDesc desc = baseDesc;
        desc.addShaderLibrary(shaderFile).csEntry(entryFunction == "" ? "main" : entryFunction);
        pPass = ComputePass::create(mpDevice, desc, defines, false);
    }
    pPass->getProgram()->addDefines(defines);
    pPass->setVars(nullptr);
}

SpatialHashGrid::SharedPtr SpatialHashGrid::create(ref<Device> pDevice, DirectionalDistType type)
{
    return SharedPtr(new SpatialHashGrid(pDevice, type));
}

void SpatialHashGrid::initialize(DirectionalDistType type)
{
    m_type = type;

    // -----------------------------------------------------------------------
    // Compute shaders
    // -----------------------------------------------------------------------

    DefineList defines;
    ProgramDesc baseDesc;

    // TODO
    createComputePass(
        m_hashMapClearAllPipeline,
        "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang",
        defines,
        baseDesc,
        "clearAllHashMapResourcesMain"
    );

    createComputePass(
        m_hashMapClearNewCachePipeline,
        "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang",
        defines,
        baseDesc,
        "clearNewHashMapResourcesMain"
    );

    createComputePass(
        m_hashMapEvictPipeline, "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang", defines, baseDesc, "evictEntriesFromHashMapMain"
    );

    createComputePass(
        m_hashMapCalculateVoxelSize, "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang", defines, baseDesc, "calculateVoxelSize"
    );

    createComputePass(
        m_hashMapCombinePipeline, "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang", defines, baseDesc, "combineOldAndNewHashMapMain"
    );

    createComputePass(mpReflectTypes, "Scene/SpatialHashGrid/ReflectTypes.cs.slang", defines, baseDesc, "main");

    createComputePass(
        m_hashMapInitMoVMFPipeline, "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang", defines, baseDesc, "initMoVMFMain"
    );
    createComputePass(
        m_hashMapResolveMoVMFPipeline, "Scene/SpatialHashGrid/SpatialHashGridProcess.cs.slang", defines, baseDesc, "resolveMoVMFMain"
    );
}

// TODO: add pybind params

void SpatialHashGrid::initParamBlock(
    uint32_t frameNumber,
    uint32_t numElementsPerEntry,
    uint32_t strideElementsPerEntry,
    uint32_t entryStride
)
{
    if (!mpSpatialHashGridBlock)
    {
        auto reflector = mpReflectTypes->getProgram()->getReflector()->getParameterBlock("gSpatialHashGridParams");
        mpSpatialHashGridBlock = ParameterBlock::create(mpDevice, reflector);
    }

    ShaderVar spatialHashGridParams = mpSpatialHashGridBlock->getRootVar();

    {
        const SpatialHashGridSettings& params = mParameters;
        spatialHashGridParams["enableSpatialJitter"] = (uint)params.enableSpatialJittering;
        spatialHashGridParams["enableLODJitter"] = (uint)params.enableLODJittering;
        spatialHashGridParams["enableDirectionalJitter"] = (uint)params.enableDirectionalJittering;
        spatialHashGridParams["enableNanChecks"] = (uint)params.enableNanChecks;
        spatialHashGridParams["showDebugView"] = (uint)params.showDebugView;
        spatialHashGridParams["numEntries"] = getNumEntries();
        spatialHashGridParams["temporalReuse"] = float(params.temporalReuse);
        spatialHashGridParams["temporalAlpha"] = params.temporalAlpha;
        spatialHashGridParams["frameNumber"] = frameNumber;
        spatialHashGridParams["maxAgeForEviction"] = params.maxAgeForEviction;
        spatialHashGridParams["retrace"] = params.retrace;
        spatialHashGridParams["strideElementsPerEntry"] = strideElementsPerEntry;
        spatialHashGridParams["numElementsPerEntry"] = numElementsPerEntry;
        spatialHashGridParams["algmType"] = (uint)m_type;
        spatialHashGridParams["useReSTIRSamples"] = (uint)mUseReSTIRSamples;
        spatialHashGridParams["entryStride"] = entryStride;

        // Cone based spatial hash params
        spatialHashGridParams["voxelSize"] = params.voxelSize;
        spatialHashGridParams["clampVoxelSize"] = params.clampVoxelSize;

        // Distance based spatial hash params
        spatialHashGridParams["distanceBasedHashP0"] = params.distanceBasedHashP0;
        spatialHashGridParams["distanceBasedHashP1"] = params.distanceBasedHashP1;
        spatialHashGridParams["distanceOverride"] = params.distanceOverride;

        uint flags = 0;
        if (params.dimUnusedEntries)
        {
            flags |= eSpatialHashGridDimUnusedEnties;
        }
        if (params.dontResolveConflicts)
        {
            flags |= eSpatialHashGridDontResolveConflicts;
        }
        if (params.useDistanceBasedHash)
        {
            flags |= eSpatialHashGridDistanceBasedSpatialHash;
        }

        spatialHashGridParams["flags"] = flags;
    }
}

// call this everyframe
void SpatialHashGrid::setupResources(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug, bool forceReset)
{
    // We parameterize the buffer sizing by type of algorithm
    // TODO (zheng): probably elementSize?
    uint32_t entrySize;
    if (m_type == DirectionalDistType::Histogram || m_type == DirectionalDistType::Quadtree)
    {
        entrySize = 2 * sizeof(float); // usually one counter and one radiance value
    }
    else if (m_type == DirectionalDistType::movMF)
    {
        entrySize = sizeof(float);
    }

    // strideElementsPerEntry is decided by m_type, m_type is constant
    // so only case that strideElementsPerEntry is dynamic is for light cache
    uint32_t strideElementsPerEntry = 1;

    const uint32_t deviceIndex = 0;

    if (m_type == DirectionalDistType::Histogram)
    {
        strideElementsPerEntry = HISTOGRAM_OCT_SUBDIV_DIM * HISTOGRAM_OCT_SUBDIV_DIM; // RAY_GUIDE_OCT_SUBDIV_TOTAL (16*16)
    }
    else if (m_type == DirectionalDistType::Quadtree)
    {
        strideElementsPerEntry = TOTAL_QUADTREE_NODES;
    }
    else if (m_type == DirectionalDistType::movMF)
    {
        strideElementsPerEntry = 1 + 1 + 1 + 4 * K;
        // Sufficient statistics
        // 1: float i;
        // 1: float totalW;
        // 4 * K: float3 sumofWeightedDirections[K]; and float sumofWeights[K];
    }

    uint32_t numElementsPerEntry = strideElementsPerEntry;
    uint32_t entryStride = 1;

    if (m_type == DirectionalDistType::Histogram || m_type == DirectionalDistType::Quadtree || m_type == DirectionalDistType::movMF)
    {
        // increase logic:
        // never decrease
        // add by 4(aligned by 4) on each increase request
        strideElementsPerEntry = align_to(4u, strideElementsPerEntry);

        // The number of entries needed to accomodate the light count
        // Basic integer div ceiling operation
        entryStride = std::max(1u, strideElementsPerEntry / MAX_3D_TEX_WIDTH + (strideElementsPerEntry % MAX_3D_TEX_WIDTH != 0));
    }

    SpatialHashGridResources& spatialHashInOutParams = mBuffers;
    // we only fully initialize resource once
    const bool initializeResource = !spatialHashInOutParams.HashKey;

    if (initializeResource || forceReset || mParameters.forceReset)
        mFrameCount = 0;

    initParamBlock(mFrameCount, numElementsPerEntry, strideElementsPerEntry, entryStride);

    // TODO: do we need to update the shader definitions?
    // updatePipelines();
    ShaderVar spatialHashGridParams = mpSpatialHashGridBlock->getRootVar();

    // -----------------------------------------------------------------------------
    // Resource setup
    // -----------------------------------------------------------------------------
    // light op(create/destroy/swap) is processed before rendering start, so we can know if light cache update is needed
    // here
    const uint32_t hashMapNumEntries = getNumEntries();
    spatialHashGridParams["numEntries"] = hashMapNumEntries;

    static const uint max3DTexWidth = MAX_3D_TEX_WIDTH;

    if (initializeResource)
    {
        spatialHashInOutParams.HashKey = mpDevice->createBuffer(hashMapNumEntries * sizeof(uint32_t) * 2);
        spatialHashInOutParams.TimeStamps = mpDevice->createBuffer(hashMapNumEntries * sizeof(uint32_t));
        spatialHashInOutParams.OverrideFlags = mpDevice->createBuffer(hashMapNumEntries * sizeof(uint32_t));
        spatialHashInOutParams.HashMapValues = mpDevice->createBuffer(hashMapNumEntries * entrySize * strideElementsPerEntry);
        spatialHashInOutParams.HashMapNewValues = mpDevice->createBuffer(hashMapNumEntries * entrySize * strideElementsPerEntry);
        spatialHashInOutParams.VoxelSizeParams = mpDevice->createBuffer(eSpatialGridParamCount * sizeof(uint32_t));
        spatialHashInOutParams.HashMapCounter = mpDevice->createBuffer(1 * sizeof(uint32_t));

        if (m_type == DirectionalDistType::Histogram || m_type == DirectionalDistType::Quadtree)
        {
            FALCOR_ASSERT(hashMapNumEntries % 32 == 0);
            FALCOR_ASSERT((hashMapNumEntries / MAX_3D_TEX_WIDTH) * entryStride <= MAX_3D_TEX_WIDTH);
            // Due to tex size hw limitations, the linear buffer is split into 3d texture
            spatialHashInOutParams.HashMapAuxBuffer = mpDevice->createTexture3D(
                MAX_3D_TEX_WIDTH,
                std::min((hashMapNumEntries / max3DTexWidth) * entryStride, max3DTexWidth),
                std::min(strideElementsPerEntry, max3DTexWidth),
                ResourceFormat::R16Unorm,
                1,
                nullptr,
                ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess
            );
        }
        else if (m_type == DirectionalDistType::movMF)
        {
            auto var = mpReflectTypes->getRootVar();
            spatialHashInOutParams.MoVMFBuffer = mpDevice->createStructuredBuffer(
                var["gSpatialHashGridParams"]["RWMoVMFBuffer"],
                hashMapNumEntries,
                ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess,
                MemoryType::DeviceLocal,
                nullptr,
                false
            );
        }
    }

    // TODO: create a bind paramblock function for this
    // TODO: check if we should use prev or cur
    spatialHashGridParams["RWHashMapKey"] = spatialHashInOutParams.HashKey;
    spatialHashGridParams["RWTimeStamps"] = spatialHashInOutParams.TimeStamps;
    spatialHashGridParams["RWOverrideFlags"] = spatialHashInOutParams.OverrideFlags;
    spatialHashGridParams["RWVoxelSizeParams"] = spatialHashInOutParams.VoxelSizeParams;
    spatialHashGridParams["RWHashTableCounter"] = spatialHashInOutParams.HashMapCounter;
    spatialHashGridParams["RWCacheValues"] = spatialHashInOutParams.HashMapValues;
    spatialHashGridParams["RWNewCacheValues"] = spatialHashInOutParams.HashMapNewValues;

    spatialHashGridParams["RWCacheAuxBuffer"] = spatialHashInOutParams.HashMapAuxBuffer;

    spatialHashGridParams["enableSpatialJitter"] = (uint)mParameters.enableSpatialJittering;
    spatialHashGridParams["enableLODJitter"] = (uint)mParameters.enableLODJittering;
    spatialHashGridParams["enableDirectionalJitter"] = (uint)mParameters.enableDirectionalJittering;
    spatialHashGridParams["enableNanChecks"] = (uint)mParameters.enableNanChecks;
    spatialHashGridParams["showDebugView"] = (uint)mParameters.showDebugView;
    spatialHashGridParams["RWMoVMFBuffer"] = spatialHashInOutParams.MoVMFBuffer;

    // -----------------------------------------------------------------------------
    // Cache clearing
    // -----------------------------------------------------------------------------
    // We either need to clear the complete cache or prepare the RWNewCacheValues values before tracing.

    {
        FALCOR_PROFILE(pRenderContext, "ClearCache");
        // const uint32_t dispX = getLaunchDimensions1d(static_cast<uint32_t>(hashMapNumEntries), 1024);
        // printf("%d\n", hashMapNumEntries);
        // printf("dispX: %d\n", dispX);
        // FALCOR_ASSERT(dispX <= 65535);

        FALCOR_ASSERT(hashMapNumEntries <= 65536 * 1024); // can't have more than 65536 blocks

        if (initializeResource || forceReset || mParameters.forceReset)
        {
            if (m_type == DirectionalDistType::Histogram || m_type == DirectionalDistType::Quadtree)
            {
                ShaderVar var = m_hashMapClearAllPipeline->getRootVar();
                var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
                pPixelDebug->prepareProgram(m_hashMapClearAllPipeline->getProgram(), var);
                m_hashMapClearAllPipeline->execute(pRenderContext, uint3(hashMapNumEntries, 1, 1));
            }
            else if (m_type == DirectionalDistType::movMF)
            {
                ShaderVar var = m_hashMapInitMoVMFPipeline->getRootVar();
                var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
                pPixelDebug->prepareProgram(m_hashMapInitMoVMFPipeline->getProgram(), var);
                m_hashMapInitMoVMFPipeline->execute(pRenderContext, uint3(hashMapNumEntries, 1, 1));
            }
        }
        else
        {
            ShaderVar var = m_hashMapClearNewCachePipeline->getRootVar();
            var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
            pPixelDebug->prepareProgram(m_hashMapClearNewCachePipeline->getProgram(), var);
            m_hashMapClearNewCachePipeline->execute(pRenderContext, uint3(hashMapNumEntries, 1, 1));
        }
    }
}

void SpatialHashGrid::runOnePassEM(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug)
{
    FALCOR_PROFILE(pRenderContext, "ResolveMoVMF");
    ShaderVar var = m_hashMapResolveMoVMFPipeline->getRootVar();
    var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
    pPixelDebug->prepareProgram(m_hashMapResolveMoVMFPipeline->getProgram(), var);
    FALCOR_ASSERT(getNumEntries() <= 65536 * 1024); // can't have more than 65536 blocks
    m_hashMapResolveMoVMFPipeline->execute(pRenderContext, uint3(getNumEntries(), 1, 1));
}

void SpatialHashGrid::processCache(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug)
{
    ShaderVar spatialHashGridParams = mpSpatialHashGridBlock->getRootVar();
    const uint32_t hashMapNumEntries = getNumEntries();
    spatialHashGridParams["numEntries"] = hashMapNumEntries;
    spatialHashGridParams["temporalReuse"] = static_cast<float>(mParameters.temporalReuse);
    spatialHashGridParams["temporalAlpha"] = mParameters.temporalAlpha;
    spatialHashGridParams["retrace"] = mParameters.retrace;
    uint flags = 0;
    if (mParameters.dimUnusedEntries)
        flags |= eSpatialHashGridDimUnusedEnties;
    if (mParameters.dontResolveConflicts)
        flags |= eSpatialHashGridDontResolveConflicts;
    if (mParameters.useDistanceBasedHash)
        flags |= eSpatialHashGridDistanceBasedSpatialHash;
    spatialHashGridParams["flags"] = flags;

    // combine hashmap
    // if (m_type == DirectionalDistType::Histogram || m_type == DirectionalDistType::Quadtree)
    // {
    //     FALCOR_PROFILE(pRenderContext, "CombineHashmaps");
    //     ShaderVar var = m_hashMapCombinePipeline->getRootVar();
    //     var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
    //     pPixelDebug->prepareProgram(m_hashMapCombinePipeline->getProgram(), var);
    //     //const uint32_t dispX = getLaunchDimensions1d(static_cast<uint32_t>(hashMapNumEntries), 1024);
    //     FALCOR_ASSERT(hashMapNumEntries <= 65536 * 1024); // can't have more than 65536 blocks
    //     m_hashMapCombinePipeline->execute(pRenderContext, uint3(hashMapNumEntries, 1, 1));
    // }
    // else if (m_type == DirectionalDistType::movMF)
    // {
    //     runOnePassEM(pRenderContext, pPixelDebug);
    // }

    // calculate voxel size
    spatialHashGridParams["frameNumber"] = mFrameCount;
    spatialHashGridParams["maxAgeForEviction"] = mParameters.maxAgeForEviction;
    spatialHashGridParams["voxelSize"] = mParameters.voxelSize;

    //{
    //    FALCOR_PROFILE(pRenderContext,"CalculateVoxelSize");
    //    ShaderVar var = m_hashMapCalculateVoxelSize->getRootVar();
    //    var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
    //    m_hashMapCalculateVoxelSize->execute(pRenderContext, uint3(1, 1, 1));
    //}

    // -----------------------------------------------------------------------------
    // Evict old items from the cache // need to set maximum age for hash entry
    // -----------------------------------------------------------------------------

    // {
    //     FALCOR_PROFILE(pRenderContext,  "EvictEntries");
    //     ShaderVar var = m_hashMapEvictPipeline->getRootVar();
    //     var["gSpatialHashGridParams"] = mpSpatialHashGridBlock;
    //     //const uint32_t dispX = getLaunchDimensions1d(static_cast<uint32_t>(hashMapNumEntries), 1024);
    //     FALCOR_ASSERT(hashMapNumEntries <= 65536 * 1024); // can't have more than 65536 blocks
    //     pPixelDebug->prepareProgram(m_hashMapEvictPipeline->getProgram(), var);
    //     m_hashMapEvictPipeline->execute(pRenderContext, uint3(hashMapNumEntries, 1, 1));
    // }

    // copy cache to previous frame
    // pRenderContext->copyResource(mBuffers.PrevHashMapValues.get(), mBuffers.HashMapValues.get());
}

void SpatialHashGrid::beginFrame(
    RenderContext* pRenderContext,
    std::unique_ptr<PixelDebug>& pPixelDebug,
    bool forceReset,
    bool useReSTIRSamples
)
{
    setupResources(pRenderContext, pPixelDebug, forceReset);
    mUseReSTIRSamples = useReSTIRSamples;
}

void SpatialHashGrid::endFrame(RenderContext* pRenderContext, std::unique_ptr<PixelDebug>& pPixelDebug)
{
    processCache(pRenderContext, pPixelDebug);
    mFrameCount++;
}

bool SpatialHashGrid::renderUI(Gui::Widgets& widget)
{
    auto hashGridGroup = widget.group("Spatial Hash Grid Setting");

    bool dirty = hashGridGroup.var("Distance Hash P0", mParameters.distanceBasedHashP0);
    dirty |= hashGridGroup.var("Distance Hash P1", mParameters.distanceBasedHashP1);
    // TODO: add more

    dirty |= hashGridGroup.checkbox("Spatial Jittering", mParameters.enableSpatialJittering);
    dirty |= hashGridGroup.checkbox("Directional Jittering", mParameters.enableDirectionalJittering);
    dirty |= hashGridGroup.checkbox("LOD Jittering", mParameters.enableLODJittering);

    dirty |= hashGridGroup.var("max age for eviction", mParameters.maxAgeForEviction, 1u, 1000u);
    dirty |= hashGridGroup.var("temporal reuse max history", mParameters.temporalReuse, 0, 1000);
    dirty |= hashGridGroup.var("temporal EWA alpha", mParameters.temporalAlpha, 0.01f, 1.f);
    hashGridGroup.tooltip("additional factor multiplied with the weight derived from temporal sample count");

    dirty |= hashGridGroup.checkbox("Dim unused entries", mParameters.dimUnusedEntries);

    return dirty;
}

ref<ParameterBlock> SpatialHashGrid::getParameterBlock()
{
    return mpSpatialHashGridBlock;
}

} // namespace Falcor
