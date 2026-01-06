#include "VoxelizationPass_GPU.h"
#include "Shading.slang"

namespace
{
const std::string kClipProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/ClipMesh.cs.slang";

}; // namespace

VoxelizationPass_GPU::VoxelizationPass_GPU(ref<Device> pDevice, const Properties& props) : VoxelizationPass(pDevice, props)
{
    maxSolidVoxelCount = (uint)floor(4294967296.0 / sizeof(PrimitiveBSDF)); // 缓冲区最大容量为4G

    mSampleFrequency = 256;

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Linear)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpSampler = pDevice->createSampler(samplerDesc);
}

void VoxelizationPass_GPU::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    VoxelizationPass::setScene(pRenderContext, pScene);
    mClipPass = nullptr;
}

void VoxelizationPass_GPU::voxelize(RenderContext* pRenderContext, const RenderData& renderData)
{
    gBuffer = mpDevice->createStructuredBuffer(sizeof(VoxelData), maxSolidVoxelCount, ResourceBindFlags::UnorderedAccess);
    vBuffer = mpDevice->createStructuredBuffer(sizeof(int), gridData.totalVoxelCount(), ResourceBindFlags::UnorderedAccess);
    solidVoxelCount = mpDevice->createStructuredBuffer(sizeof(uint), 2, ResourceBindFlags::UnorderedAccess);
    polygonCountBuffer = mpDevice->createStructuredBuffer(sizeof(uint), maxSolidVoxelCount, ResourceBindFlags::UnorderedAccess);
    pRenderContext->clearUAV(gBuffer->getUAV().get(), uint4(0));
    pRenderContext->clearUAV(vBuffer->getUAV().get(), uint4(0xFFFFFFFFu));
    pRenderContext->clearUAV(solidVoxelCount->getUAV().get(), uint4(0));
    pRenderContext->clearUAV(polygonCountBuffer->getUAV().get(), uint4(0));

    if (!mClipPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kClipProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());

        mClipPass = ComputePass::create(mpDevice, desc, defines, true);
    }

    ShaderVar var = mClipPass->getRootVar();
    var["s"] = mpSampler;
    mpScene->bindShaderData(var["scene"]);
    var[kGBuffer] = gBuffer;
    var[kVBuffer] = vBuffer;
    var["polygonCountBuffer"] = polygonCountBuffer;
    var["solidVoxelCount"] = solidVoxelCount;

    auto cb_grid = var["GridData"];
    cb_grid["gridMin"] = gridData.gridMin;
    cb_grid["voxelSize"] = gridData.voxelSize;
    cb_grid["voxelCount"] = gridData.voxelCount;

    uint meshCount = mpScene->getMeshCount();
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        uint triangleCount = meshDesc.getTriangleCount();

        auto cb_mesh = mClipPass->getRootVar()["MeshData"];
        cb_mesh["vertexCount"] = meshDesc.vertexCount;
        cb_mesh["vbOffset"] = meshDesc.vbOffset;
        cb_mesh["triangleCount"] = triangleCount;
        cb_mesh["ibOffset"] = meshDesc.ibOffset;
        cb_mesh["use16BitIndices"] = meshDesc.use16BitIndices();
        cb_mesh["materialID"] = meshDesc.materialID;
        mClipPass->execute(pRenderContext, uint3(triangleCount, 1, 1));
        pRenderContext->uavBarrier(gBuffer.get());
    }
    pRenderContext->submit(true);

    ref<Buffer> cpuSolidVoxelCount = copyToCpu(mpDevice, pRenderContext, solidVoxelCount);
    ref<Buffer> cpuVBuffer = copyToCpu(mpDevice, pRenderContext, vBuffer);
    ref<Buffer> cpuPolygonCountBuffer = copyToCpu(mpDevice, pRenderContext, polygonCountBuffer);
    pRenderContext->submit(true);

    uint* pSolidVoxelCount = reinterpret_cast<uint*>(cpuSolidVoxelCount->map());
    void* pVbuffer = cpuVBuffer->map();
    void* pPolygonCount = cpuPolygonCountBuffer->map();

    gridData.solidVoxelCount = pSolidVoxelCount[0];

    std::vector<uint> polygonCounts;
    polygonCounts.resize(gridData.solidVoxelCount);
    memcpy(polygonCounts.data(), pPolygonCount, sizeof(uint) * gridData.solidVoxelCount);

    std::vector<PolygonRange> polygonRanges;
    polygonRanges.resize(gridData.solidVoxelCount);
    polygonGroup.reserve(polygonCounts, polygonRanges);

    vBuffer_CPU.resize(gridData.totalVoxelCount());
    memcpy(vBuffer_CPU.data(), pVbuffer, sizeof(int) * gridData.totalVoxelCount());
    pVBuffer_CPU = vBuffer_CPU.data();

    cpuSolidVoxelCount->unmap();
    cpuPolygonCountBuffer->unmap();
    cpuVBuffer->unmap();
}

void VoxelizationPass_GPU::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
    VoxelizationPass::sample(pRenderContext, renderData);
}
