#include "VoxelizationPass.h"
#include "Image/ImageLoader.h"
#include <fstream>

namespace
{
const std::string kSamplePolygonProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/SamplePolygon.cs.slang";
}; // namespace

VoxelizationPass::VoxelizationPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice)
    , polygonGroup(pDevice)
    , gridData(VoxelizationBase::GlobalGridData)
{
    mSceneNameIndex = 4;
    mSceneName = "Chandelier";
    mVoxelizationComplete = true;
    mSamplingComplete = true;
    mCompleteTimes = 0;
    pVBuffer_CPU = nullptr;

    mSampleFrequency = 256;
    mVoxelResolution = 512;

    VoxelizationBase::UpdateVoxelGrid(nullptr, mVoxelResolution);

    mpDevice = pDevice;
}

RenderPassReflection VoxelizationPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addOutput("dummy", "Dummy")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);
    return reflector;
}

void VoxelizationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene || mVoxelizationComplete && mSamplingComplete)
        return;

    if (!mVoxelizationComplete)
    {
        voxelize(pRenderContext, renderData);
        mVoxelizationComplete = true;
    }
    else
    {
        if (mCompleteTimes < polygonGroup.size())
        {
            sample(pRenderContext, renderData);
            mCompleteTimes++;
        }
        else
        {
            ref<Buffer> cpuGBuffer = mpDevice->createBuffer(gBuffer->getSize(), ResourceBindFlags::None, MemoryType::ReadBack);
            ref<Buffer> cpuBlockMap =
                mpDevice->createBuffer(gridData.totalBlockCount() * sizeof(uint4), ResourceBindFlags::None, MemoryType::ReadBack);
            pRenderContext->copyResource(cpuGBuffer.get(), gBuffer.get());
            pRenderContext->copyResource(cpuBlockMap.get(), blockMap.get());
            mpDevice->wait();
            void* pGBuffer_CPU = cpuGBuffer->map();
            void* pBlockMap_CPU = cpuBlockMap->map();
            write(getFileName(), pGBuffer_CPU, pVBuffer_CPU, pBlockMap_CPU);
            cpuGBuffer->unmap();
            cpuBlockMap->unmap();
            Tools::Profiler::Print();
            Tools::Profiler::Reset();
            mSamplingComplete = true;
        }
    }
}

void VoxelizationPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void VoxelizationPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {16, 32, 64, 128, 256, 512, 1000, 1024};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(resolutions) / sizeof(uint); i++)
        {
            list.push_back({resolutions[i], std::to_string(resolutions[i])});
        }
        if (widget.dropdown("Voxel Resolution", list, mVoxelResolution))
        {
            VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
            requestRecompile();
        }
    }

    static const std::string sceneNames[] = {"Arcade", "Tree", "BoxBunny", "Box", "Chandelier"};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(sceneNames) / sizeof(std::string); i++)
        {
            list.push_back({i, sceneNames[i]});
        }
        if (widget.dropdown("Scene Name", list, mSceneNameIndex))
        {
            mSceneName = sceneNames[mSceneNameIndex];
        }
    }

    static const uint sampleFrequencies[] = {0, 1, 2, 4, 8, 16, 32, 64, 128, 256};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(sampleFrequencies) / sizeof(uint); i++)
        {
            list.push_back({sampleFrequencies[i], std::to_string(sampleFrequencies[i])});
        }
        widget.dropdown("Sample Frequency", list, mSampleFrequency);
    }

    static const uint polygonPerframes[] = { 1000,2000,4000,8000 };
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(polygonPerframes) / sizeof(uint); i++)
        {
            list.push_back({ polygonPerframes[i], std::to_string(polygonPerframes[i]) });
        }
        widget.dropdown("Polygon Per Frame", list, polygonGroup.maxPolygonCount);
    }

    if (mpScene && mVoxelizationComplete && mSamplingComplete && widget.button("Generate"))
    {
        ImageLoader::Instance().setSceneName(mSceneName);
        mVoxelizationComplete = false;
        mSamplingComplete = false;
        mCompleteTimes = 0;
    }
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mSamplePolygonPass = nullptr;
    VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
}

void VoxelizationPass::voxelize(RenderContext* pRenderContext, const RenderData& renderData) {}

void VoxelizationPass::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mSamplePolygonPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kSamplePolygonProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        mSamplePolygonPass = ComputePass::create(mpDevice, desc, defines, true);
    }

    if (!blockMap)
    {
        blockMap = mpDevice->createStructuredBuffer(sizeof(uint), 4 * gridData.totalBlockCount(), ResourceBindFlags::UnorderedAccess);
        pRenderContext->clearUAV(blockMap->getUAV().get(), uint4(0));
    }

    ShaderVar var = mSamplePolygonPass->getRootVar();
    var[kGBuffer] = gBuffer;
    var[kPolygonRangeBuffer] = polygonRangeBuffer;
    var[kPolygonBuffer] = polygonGroup.get(mCompleteTimes);
    var[kBlockMap] = blockMap;

    uint voxelCount = polygonGroup.getVoxelCount(mCompleteTimes);
    auto cb = var["CB"];
    cb["voxelCount"] = voxelCount;
    cb["sampleFrequency"] = mSampleFrequency;
    cb["gBufferOffset"] = polygonGroup.getVoxelOffset(mCompleteTimes);
    cb["blockCount"] = gridData.blockCount();

    Tools::Profiler::BeginSample("Sample Polygons");
    mSamplePolygonPass->execute(pRenderContext, uint3(voxelCount, 1, 1));
    mpDevice->wait();
    Tools::Profiler::EndSample("Sample Polygons");
}

std::string VoxelizationPass::getFileName() const
{
    std::ostringstream oss;
    oss << mSceneName;
    oss << "_";
    oss << ToString((int3)gridData.voxelCount);
    oss << "_";
    oss << std::to_string(mSampleFrequency);
    oss << ".bin";
    return oss.str();
}

void VoxelizationPass::write(std::string fileName, void* pGBuffer, void* pVBuffer, void* pBlockMap)
{
    std::ofstream f;
    std::string s = VoxelizationBase::ResourceFolder + fileName;
    f.open(s, std::ios::binary);
    f.write(reinterpret_cast<char*>(&gridData), sizeof(GridData));

    f.write(reinterpret_cast<const char*>(pVBuffer), gridData.totalVoxelCount() * sizeof(int));
    f.write(reinterpret_cast<const char*>(pGBuffer), gridData.solidVoxelCount * sizeof(VoxelData));
    f.write(reinterpret_cast<const char*>(pBlockMap), gridData.totalBlockCount() * sizeof(uint4));

    f.close();
    VoxelizationBase::FileUpdated = true;
}
