#include "VoxelizationPass_CPU.h"
#include <chrono>

namespace
{
const std::string kLoadMeshProgramFile = "RenderPasses/Voxelization/LoadMesh.cs.slang";
}; // namespace

VoxelizationPass_CPU::VoxelizationPass_CPU(ref<Device> pDevice, const Properties& props) : VoxelizationPass(pDevice, props)
{
}

VoxelizationPass_CPU::~VoxelizationPass_CPU()
{
    cancelGeneration();
    waitForAsyncClipTask();
    clearAsyncClipControlState();
}

size_t VoxelizationPass_CPU::estimatePeakWorkingSetBytes() const
{
    size_t bytes = VoxelizationPass::estimatePeakWorkingSetBytes();
    if (!mpScene)
        return bytes;

    size_t vertexCount = 0;
    size_t triangleCount = 0;
    const uint32_t meshCount = mpScene->getMeshCount();
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        vertexCount += meshDesc.vertexCount;
        triangleCount += meshDesc.getTriangleCount();
    }

    const size_t meshStagingBytes = vertexCount * (sizeof(float3) + sizeof(float3) + sizeof(float2)) + triangleCount * sizeof(uint3);
    bytes += 2 * meshStagingBytes;
    return bytes;
}

bool VoxelizationPass_CPU::canFinalizeVoxelizationStage() const
{
    return mAsyncClipState == AsyncClipState::ReadyToFinalize;
}

void VoxelizationPass_CPU::onVoxelizationStageFinalized()
{
    clearAsyncClipControlState();
}

bool VoxelizationPass_CPU::canCancelGeneration() const
{
    return mAsyncClipState == AsyncClipState::Pending && !mAsyncCancellationRequestedByUser;
}

void VoxelizationPass_CPU::cancelGeneration()
{
    if (mAsyncClipState != AsyncClipState::Pending || !mpAsyncCancelRequested)
        return;

    mAsyncCancellationRequestedByUser = true;
    mpAsyncCancelRequested->store(true, std::memory_order_relaxed);
    logInfo("CPU voxelization cancellation requested.");
}

std::string VoxelizationPass_CPU::getGenerationStatusText() const
{
    switch (mAsyncClipState)
    {
    case AsyncClipState::Pending:
    {
        if (mAsyncCancellationRequestedByUser)
            return "CPU async clip cancellation requested...";

        if (!mpAsyncProcessedTriangles || mAsyncTotalTriangles == 0)
            return "CPU async clip running...";

        uint64_t processedTriangles = mpAsyncProcessedTriangles->load(std::memory_order_relaxed);
        if (processedTriangles > mAsyncTotalTriangles)
            processedTriangles = mAsyncTotalTriangles;

        return "CPU async clip running: " + std::to_string(processedTriangles) + " / " + std::to_string(mAsyncTotalTriangles) +
               " triangles";
    }
    case AsyncClipState::ReadyToFinalize:
        return "CPU async clip finished, uploading buffers.";
    default:
        return {};
    }
}

void VoxelizationPass_CPU::ensureLoadMeshPass()
{
    if (mLoadMeshPass)
        return;

    ProgramDesc desc;
    desc.addShaderModules(mpScene->getShaderModules());
    desc.addShaderLibrary(kLoadMeshProgramFile).csEntry("main");
    desc.addTypeConformances(mpScene->getTypeConformances());

    DefineList defines;
    defines.add(mpScene->getSceneDefines());

    mLoadMeshPass = ComputePass::create(mpDevice, desc, defines, true);
}

void VoxelizationPass_CPU::releaseAsyncClipTaskResources()
{
    mpAsyncCancelRequested.reset();
    mpAsyncProcessedTriangles.reset();
    mAsyncTotalTriangles = 0;
    mAsyncCancellationRequestedByUser = false;
    mAsyncClipTask = {};
}

void VoxelizationPass_CPU::clearAsyncClipControlState()
{
    mAsyncClipState = AsyncClipState::Idle;
    releaseAsyncClipTaskResources();
}

void VoxelizationPass_CPU::waitForAsyncClipTask()
{
    if (!mAsyncClipTask.valid())
        return;

    try
    {
        mAsyncClipTask.wait();
        mAsyncClipTask.get();
    }
    catch (const std::exception& e)
    {
        logWarning("CPU voxelization async cleanup ignored task error: {}", e.what());
    }
}

VoxelizationPass_CPU::AsyncClipResult VoxelizationPass_CPU::runAsyncClipTask(
    AsyncClipInput input,
    const std::shared_ptr<std::atomic_bool>& pCancelRequested,
    const std::shared_ptr<std::atomic<uint64_t>>& pProcessedTriangles
)
{
    const auto startTime = std::chrono::steady_clock::now();

    PolygonGenerator polygonGenerator(input.gridData);
    polygonGenerator.reset();

    AsyncClipResult result = {};
    if (
        !polygonGenerator.clipAll(
            input.header,
            input.instanceList,
            input.positions.data(),
            input.normals.data(),
            input.texCoords.data(),
            input.triangles.data(),
            pCancelRequested.get(),
            pProcessedTriangles.get()
        )
    )
    {
        result.cancelled = true;
        return result;
    }

    result.gridData = polygonGenerator.getGridData();
    result.gBuffer = std::move(polygonGenerator.gBuffer);
    result.vBuffer = std::move(polygonGenerator.vBuffer);
    result.polygonArrays = std::move(polygonGenerator.polygonArrays);
    result.polygonRangeBuffer = std::move(polygonGenerator.polygonRangeBuffer);
    result.durationMs =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - startTime).count();
    return result;
}

void VoxelizationPass_CPU::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    cancelGeneration();
    waitForAsyncClipTask();
    clearAsyncClipControlState();
    mVoxelizationComplete = true;
    mSamplingComplete = true;
    mCompleteTimes = 0;
    mVBufferCpu.clear();
    pVBuffer_CPU = nullptr;

    VoxelizationPass::setScene(pRenderContext, pScene);
    mLoadMeshPass = nullptr;
}

void VoxelizationPass_CPU::startAsyncClip(RenderContext* pRenderContext)
{
    ensureLoadMeshPass();

    mVBufferCpu.clear();
    pVBuffer_CPU = nullptr;

    const uint meshCount = mpScene->getMeshCount();
    uint vertexCount = 0;
    uint triangleCount = 0;
    std::vector<MeshHeader> meshList;
    meshList.reserve(meshCount);
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        vertexCount += meshDesc.vertexCount;
        triangleCount += meshDesc.getTriangleCount();
    }

    AsyncClipInput input = {};
    input.gridData = gridData;
    input.header = {meshCount, vertexCount, triangleCount};

    ref<Buffer> positions = mpDevice->createStructuredBuffer(sizeof(float3), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> normals = mpDevice->createStructuredBuffer(sizeof(float3), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> texCoords = mpDevice->createStructuredBuffer(sizeof(float2), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> triangles = mpDevice->createStructuredBuffer(sizeof(uint3), triangleCount, ResourceBindFlags::UnorderedAccess);

    ShaderVar var = mLoadMeshPass->getRootVar();
    mpScene->bindShaderData(var["gScene"]);
    var["positions"] = positions;
    var["normals"] = normals;
    var["texCoords"] = texCoords;
    var["triangles"] = triangles;

    uint triangleOffset = 0;
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        MeshHeader mesh = {meshID.get(), meshDesc.materialID, meshDesc.vertexCount, meshDesc.getTriangleCount(), triangleOffset};
        meshList.push_back(mesh);

        auto meshData = mLoadMeshPass->getRootVar()["MeshData"];
        meshData["vertexCount"] = meshDesc.vertexCount;
        meshData["vbOffset"] = meshDesc.vbOffset;
        meshData["triangleCount"] = meshDesc.getTriangleCount();
        meshData["ibOffset"] = meshDesc.ibOffset;
        meshData["triOffset"] = triangleOffset;
        meshData["use16BitIndices"] = meshDesc.use16BitIndices();
        mLoadMeshPass->execute(pRenderContext, uint3(meshDesc.getTriangleCount(), 1, 1));

        triangleOffset += meshDesc.getTriangleCount();
    }

    const auto* pAnimationController = mpScene->getAnimationController();
    FALCOR_ASSERT(pAnimationController);
    const auto& globalMatrices = pAnimationController->getGlobalMatrices();
    const auto& invTransposeMatrices = pAnimationController->getInvTransposeGlobalMatrices();
    const uint32_t instanceCount = mpScene->getGeometryInstanceCount();
    input.instanceList.reserve(instanceCount);
    for (uint32_t instanceID = 0; instanceID < instanceCount; ++instanceID)
    {
        const auto& instanceData = mpScene->getGeometryInstance(instanceID);
        const GeometryType type = instanceData.getType();
        if (type != GeometryType::TriangleMesh && type != GeometryType::DisplacedTriangleMesh)
            continue;

        const MeshID meshID = MeshID::fromSlang(instanceData.geometryID);
        const MeshDesc meshDesc = mpScene->getMesh(meshID);
        const auto& meshHeader = meshList[meshID.get()];

        InstanceHeader instance = {};
        instance.instanceID = instanceID;
        instance.meshID = meshID.get();
        instance.materialID = instanceData.materialID;
        instance.vertexCount = meshDesc.vertexCount;
        instance.triangleCount = meshDesc.getTriangleCount();
        instance.triangleOffset = meshHeader.triangleOffset;
        instance.use16BitIndices = meshDesc.use16BitIndices();
        instance.worldMatrix = globalMatrices[instanceData.globalMatrixID];
        instance.worldInvTransposeMatrix = invTransposeMatrices[instanceData.globalMatrixID];
        input.instanceList.push_back(instance);
    }

    ref<Buffer> cpuPositions = copyToCpu(mpDevice, pRenderContext, positions);
    ref<Buffer> cpuNormals = copyToCpu(mpDevice, pRenderContext, normals);
    ref<Buffer> cpuTexCoords = copyToCpu(mpDevice, pRenderContext, texCoords);
    ref<Buffer> cpuTriangles = copyToCpu(mpDevice, pRenderContext, triangles);
    pRenderContext->submit(true);

    float3* pPos = reinterpret_cast<float3*>(cpuPositions->map());
    float3* pNormal = reinterpret_cast<float3*>(cpuNormals->map());
    float2* pUV = reinterpret_cast<float2*>(cpuTexCoords->map());
    uint3* pTri = reinterpret_cast<uint3*>(cpuTriangles->map());
    input.positions.assign(pPos, pPos + vertexCount);
    input.normals.assign(pNormal, pNormal + vertexCount);
    input.texCoords.assign(pUV, pUV + vertexCount);
    input.triangles.assign(pTri, pTri + triangleCount);
    cpuPositions->unmap();
    cpuNormals->unmap();
    cpuTexCoords->unmap();
    cpuTriangles->unmap();

    const size_t asyncInstanceCount = input.instanceList.size();
    mpAsyncCancelRequested = std::make_shared<std::atomic_bool>(false);
    mpAsyncProcessedTriangles = std::make_shared<std::atomic<uint64_t>>(0ull);
    mAsyncTotalTriangles = triangleCount;
    mAsyncCancellationRequestedByUser = false;
    mAsyncClipTask = std::async(
        std::launch::async,
        [input = std::move(input), pCancelRequested = mpAsyncCancelRequested, pProcessedTriangles = mpAsyncProcessedTriangles]() mutable {
            return runAsyncClipTask(std::move(input), pCancelRequested, pProcessedTriangles);
        }
    );
    mAsyncClipState = AsyncClipState::Pending;

    logInfo(
        "CPU voxelization queued async clipping task for {} triangles across {} instances.",
        triangleCount,
        asyncInstanceCount
    );
}

void VoxelizationPass_CPU::voxelize(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mAsyncClipState == AsyncClipState::Idle)
    {
        startAsyncClip(pRenderContext);
        return;
    }

    if (mAsyncClipState != AsyncClipState::Pending)
        return;

    if (!mAsyncClipTask.valid())
        FALCOR_THROW("CPU voxelization async clip task is missing while pending.");

    if (mAsyncClipTask.wait_for(std::chrono::seconds(0)) != std::future_status::ready)
        return;

    const uint64_t totalTriangles = mAsyncTotalTriangles;
    const uint64_t processedTriangles =
        mpAsyncProcessedTriangles ? mpAsyncProcessedTriangles->load(std::memory_order_relaxed) : totalTriangles;

    AsyncClipResult result = {};
    try
    {
        result = mAsyncClipTask.get();
    }
    catch (...)
    {
        clearAsyncClipControlState();
        throw;
    }

    if (mAsyncCancellationRequestedByUser || result.cancelled)
    {
        clearAsyncClipControlState();
        mVBufferCpu.clear();
        pVBuffer_CPU = nullptr;
        mVoxelizationComplete = true;
        mSamplingComplete = true;
        mCompleteTimes = 0;
        Tools::Profiler::Reset();
        logInfo("CPU voxelization async clipping canceled after {} / {} triangles.", processedTriangles, totalTriangles);
        return;
    }

    releaseAsyncClipTaskResources();

    gridData = result.gridData;
    polygonGroup.setBlob(result.polygonArrays, result.polygonRangeBuffer);

    gBuffer = mpDevice->createStructuredBuffer(sizeof(VoxelData), gridData.solidVoxelCount, ResourceBindFlags::UnorderedAccess);
    if (gridData.solidVoxelCount > 0)
        gBuffer->setBlob(result.gBuffer.data(), 0, gridData.solidVoxelCount * sizeof(VoxelData));

    polygonRangeBuffer = mpDevice->createStructuredBuffer(
        sizeof(PolygonRange),
        gridData.solidVoxelCount,
        ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess
    );
    if (gridData.solidVoxelCount > 0)
        polygonRangeBuffer->setBlob(result.polygonRangeBuffer.data(), 0, gridData.solidVoxelCount * sizeof(PolygonRange));

    mVBufferCpu = std::move(result.vBuffer);
    pVBuffer_CPU = mVBufferCpu.empty() ? nullptr : mVBufferCpu.data();
    mAsyncClipState = AsyncClipState::ReadyToFinalize;

    logInfo(
        "CPU voxelization async clipping completed in {:.2f} ms with {} solid voxels.",
        result.durationMs,
        gridData.solidVoxelCount
    );

    pRenderContext->submit(true);
}

void VoxelizationPass_CPU::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
    VoxelizationPass::sample(pRenderContext, renderData);
}

void VoxelizationPass_CPU::renderUI(Gui::Widgets& widget)
{
    VoxelizationPass::renderUI(widget);
}

std::string VoxelizationPass_CPU::getFileName()
{
    return VoxelizationPass::getFileName() + "_CPU";
}
