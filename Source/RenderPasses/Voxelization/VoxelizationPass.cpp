#include "VoxelizationPass.h"
#include "Image/ImageLoader.h"
#include <algorithm>
#include <exception>
#include <iomanip>
#include <limits>
#include <cctype>
#include <fstream>
#include <sstream>

namespace
{
const std::string kAnalyzePolygonProgramFile = "RenderPasses/Voxelization/AnalyzePolygon.cs.slang";
const std::string kSceneNames[] = {"Auto", "Arcade", "Azalea", "BoxBunny", "Box", "Chandelier", "Colosseum"};
constexpr uint32_t kSceneNameCount = sizeof(kSceneNames) / sizeof(kSceneNames[0]);
constexpr size_t kDefaultDenseVoxelSafetyLimit = 64ull * 1024ull * 1024ull;
constexpr size_t kHighMemoryDenseVoxelSafetyLimit = 128ull * 1024ull * 1024ull;
constexpr size_t kPeakWorkingSetSafetyLimit = 3ull * 1024ull * 1024ull * 1024ull;

uint32_t getSceneNameIndex(const std::string& sceneName)
{
    for (uint32_t i = 0; i < kSceneNameCount; ++i)
    {
        if (kSceneNames[i] == sceneName)
            return i;
    }

    return 0;
}

std::string formatByteCount(size_t bytes)
{
    static const char* kSuffixes[] = {"B", "KiB", "MiB", "GiB", "TiB"};
    constexpr size_t kSuffixCount = sizeof(kSuffixes) / sizeof(kSuffixes[0]);
    double value = static_cast<double>(bytes);
    size_t suffix = 0;
    while (value >= 1024.0 && suffix + 1 < kSuffixCount)
    {
        value /= 1024.0;
        ++suffix;
    }

    std::ostringstream oss;
    if (suffix == 0 || value >= 100.0)
        oss << std::fixed << std::setprecision(0);
    else if (value >= 10.0)
        oss << std::fixed << std::setprecision(1);
    else
        oss << std::fixed << std::setprecision(2);
    oss << value << " " << kSuffixes[suffix];
    return oss.str();
}

std::string formatFailureReason(const char* stage, const std::exception& e)
{
    std::string reason = stage;
    reason += " failed: ";
    reason += e.what();
    return reason;
}

size_t getDenseVoxelSafetyLimit(bool highMemoryMode)
{
    return highMemoryMode ? kHighMemoryDenseVoxelSafetyLimit : kDefaultDenseVoxelSafetyLimit;
}
}; // namespace

VoxelizationPass::VoxelizationPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice), polygonGroup(pDevice, VoxelizationBase::GlobalGridData), gridData(VoxelizationBase::GlobalGridData)
{
    mSceneNameIndex = 0;
    mSceneName = kSceneNames[mSceneNameIndex];
    mVoxelizationComplete = true;
    mSamplingComplete = true;
    mCompleteTimes = 0;
    pVBuffer_CPU = nullptr;

    mSampleFrequency = 1024;
    mVoxelResolution = 512;
    mLerpNormal = false;
    mAutoGenerate = false;
    mHighMemoryMode = false;
    mGenerationFailed = false;

    VoxelizationBase::UpdateVoxelGrid(nullptr, mVoxelResolution);

    mpDevice = pDevice;

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Linear)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpSampler = pDevice->createSampler(samplerDesc);

    parseProperties(props);
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
    auto& dict = renderData.getDictionary();
    if (!mpScene)
    {
        dict[VoxelizationProperties::kDictionaryCompleted] = false;
        dict[VoxelizationProperties::kDictionaryOutputPath] = std::string{};
        return;
    }

    if (mGenerationFailed)
    {
        dict[VoxelizationProperties::kDictionaryCompleted] = false;
        dict[VoxelizationProperties::kDictionaryOutputPath] = std::string{};
        return;
    }

    if (mVoxelizationComplete && mSamplingComplete)
        return;

    dict[VoxelizationProperties::kDictionaryCompleted] = false;
    dict[VoxelizationProperties::kDictionaryOutputPath] = std::string{};

    if (!mVoxelizationComplete)
    {
        try
        {
            voxelize(pRenderContext, renderData);
        }
        catch (const std::bad_alloc& e)
        {
            failGeneration(formatFailureReason("Voxelization", e));
            return;
        }
        catch (const std::exception& e)
        {
            failGeneration(formatFailureReason("Voxelization", e));
            return;
        }

        if (mGenerationFailed)
            return;

        if (!canFinalizeVoxelizationStage())
            return;

        mVoxelizationComplete = true;

        try
        {
            blockMap = mpDevice->createStructuredBuffer(sizeof(uint), 4 * gridData.totalBlockCount(), ResourceBindFlags::UnorderedAccess);
            pRenderContext->clearUAV(blockMap->getUAV().get(), uint4(0));
            onVoxelizationStageFinalized();
        }
        catch (const std::exception& e)
        {
            failGeneration(formatFailureReason("Block map allocation", e));
            return;
        }
    }
    else
    {
        if (mCompleteTimes < polygonGroup.size())
        {
            if (mCompleteTimes == 0)
                Tools::Profiler::BeginSample("Analyze Polygon");

            try
            {
                sample(pRenderContext, renderData);
            }
            catch (const std::bad_alloc& e)
            {
                failGeneration(formatFailureReason("Analyze Polygon", e));
                return;
            }
            catch (const std::exception& e)
            {
                failGeneration(formatFailureReason("Analyze Polygon", e));
                return;
            }

            if (mGenerationFailed)
                return;

            mCompleteTimes++;
        }
        else
        {
            try
            {
                pRenderContext->submit(true);
                Tools::Profiler::EndSample("Analyze Polygon");

                Tools::Profiler::BeginSample("Write File");
                ref<Buffer> cpuGBuffer = copyToCpu(mpDevice, pRenderContext, gBuffer);
                ref<Buffer> cpuBlockMap = copyToCpu(mpDevice, pRenderContext, blockMap);
                pRenderContext->submit(true);
                void* pGBuffer_CPU = cpuGBuffer->map();
                void* pBlockMap_CPU = cpuBlockMap->map();
                const auto outputPath = getOutputFilePath();
                write(getFileName(), pGBuffer_CPU, pVBuffer_CPU, pBlockMap_CPU);
                cpuGBuffer->unmap();
                cpuBlockMap->unmap();
                mSamplingComplete = true;
                dict[VoxelizationProperties::kDictionaryOutputPath] = outputPath.string();
                dict[VoxelizationProperties::kDictionaryCompleted] = true;
                Tools::Profiler::EndSample("Write File");
                Tools::Profiler::Print();
                Tools::Profiler::Reset();
            }
            catch (const std::bad_alloc& e)
            {
                failGeneration(formatFailureReason("Write File", e));
                return;
            }
            catch (const std::exception& e)
            {
                failGeneration(formatFailureReason("Write File", e));
                return;
            }
        }
    }
}

void VoxelizationPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void VoxelizationPass::setProperties(const Properties& props)
{
    parseProperties(props);

    if (mpScene)
    {
        VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
        if (mAutoGenerate && mVoxelizationComplete && mSamplingComplete)
            beginGeneration();
    }
}

Properties VoxelizationPass::getProperties() const
{
    Properties props;
    props[VoxelizationProperties::kSceneName] = mSceneName;
    props[VoxelizationProperties::kSampleFrequency] = mSampleFrequency;
    props[VoxelizationProperties::kVoxelResolution] = mVoxelResolution;
    props[VoxelizationProperties::kPolygonPerFrame] = polygonGroup.maxPolygonCount;
    props[VoxelizationProperties::kLerpNormal] = mLerpNormal;
    props[VoxelizationProperties::kAutoGenerate] = mAutoGenerate;
    props[VoxelizationProperties::kHighMemoryMode] = mHighMemoryMode;
    return props;
}

void VoxelizationPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {
        1, 2, 4, 8, 16, 32, 64, 128, 192, 224, 256, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1000, 1024,
    };
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(resolutions) / sizeof(uint); i++)
        {
            list.push_back({resolutions[i], std::to_string(resolutions[i])});
        }
        widget.dropdown("Voxel Resolution", list, mVoxelResolution);
    }

    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < kSceneNameCount; i++)
        {
            list.push_back({i, kSceneNames[i]});
        }
        if (widget.dropdown("Scene Name", list, mSceneNameIndex))
        {
            mSceneName = kSceneNames[mSceneNameIndex];
        }
    }

    static const uint sampleFrequencies[] = {0, 64, 256, 512, 1024, 2048, 4096};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(sampleFrequencies) / sizeof(uint); i++)
        {
            list.push_back({sampleFrequencies[i], std::to_string(sampleFrequencies[i])});
        }
        widget.dropdown("Sample Frequency", list, mSampleFrequency);
    }

    static const uint polygonPerFrames[] = {1000, 4000, 16000, 64000, 128000, 256000, 512000, 1024000};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(polygonPerFrames) / sizeof(uint); i++)
        {
            list.push_back({polygonPerFrames[i], std::to_string(polygonPerFrames[i])});
        }
        widget.dropdown("Polygon Per Frame", list, polygonGroup.maxPolygonCount);
    }

    widget.checkbox("LerpNormal", mLerpNormal);
    widget.checkbox("High Memory Mode", mHighMemoryMode);

    const size_t denseVoxelSafetyLimit = getDenseVoxelSafetyLimit(mHighMemoryMode);
    widget.text(
        "Dense Voxel Safety Limit: " + formatByteCount(denseVoxelSafetyLimit * sizeof(int)) + " (" +
        std::to_string(denseVoxelSafetyLimit) + " voxels)"
    );

    if (mpScene && mVoxelizationComplete && mSamplingComplete && widget.button("Generate"))
    {
        beginGeneration();
    }

    if (canCancelGeneration() && widget.button("Cancel"))
    {
        cancelGeneration();
    }

    widget.text("Estimated Peak Working Set: " + formatByteCount(estimatePeakWorkingSetBytes()));

    const std::string statusText = getGenerationStatusText();
    if (!statusText.empty())
        widget.textWrapped("Generation status: " + statusText);

    if (!mGenerationFailureReason.empty())
        widget.textWrapped("Last generation error: " + mGenerationFailureReason);
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mAnalyzePolygonPass = nullptr;
    VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);

    if (mpScene && mAutoGenerate && mVoxelizationComplete && mSamplingComplete)
        beginGeneration();
}

void VoxelizationPass::voxelize(RenderContext* pRenderContext, const RenderData& renderData) {}

void VoxelizationPass::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mAnalyzePolygonPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kAnalyzePolygonProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());
        mAnalyzePolygonPass = ComputePass::create(mpDevice, desc, defines, true);
    }

    mAnalyzePolygonPass->addDefine("LERP_NORMAL", mLerpNormal ? "1" : "0");

    ShaderVar var = mAnalyzePolygonPass->getRootVar();
    mpScene->bindShaderData(var["gScene"]);
    var["sampler"] = mpSampler;
    var[kGBuffer] = gBuffer;
    var[kPolygonRangeBuffer] = polygonRangeBuffer;
    var[kPolygonBuffer] = polygonGroup.get(mCompleteTimes);
    var[kBlockMap] = blockMap;

    uint groupVoxelCount = polygonGroup.getVoxelCount(mCompleteTimes);
    auto cb = var["CB"];
    cb["groupVoxelCount"] = groupVoxelCount;
    cb["sampleFrequency"] = mSampleFrequency;
    cb["gBufferOffset"] = polygonGroup.getVoxelOffset(mCompleteTimes);
    cb["blockCount"] = gridData.blockCount();

    auto cb_grid = var["GridData"];
    cb_grid["gridMin"] = gridData.gridMin;
    cb_grid["voxelSize"] = gridData.voxelSize;
    cb_grid["voxelCount"] = gridData.voxelCount;

    mAnalyzePolygonPass->execute(pRenderContext, uint3(groupVoxelCount, 1, 1)); // 每个体素执行一次，没有同步问题
}

std::string trim_non_alnum_ends(std::string s)
{
    auto is_alnum = [](unsigned char c) { return std::isalnum(c) != 0; };

    size_t b = 0;
    while (b < s.size() && !is_alnum((unsigned char)s[b]))
        ++b;

    size_t e = s.size();
    while (e > b && !is_alnum((unsigned char)s[e - 1]))
        --e;

    return s.substr(b, e - b);
}

std::string VoxelizationPass::getFileName()
{
    std::ostringstream oss;
    if (mSceneName == "Auto")
        oss << trim_non_alnum_ends(mpScene->getPath().stem().string());
    else
        oss << mSceneName;
    oss << "_";
    oss << ToString((int3)gridData.voxelCount);
    oss << "_";
    oss << std::to_string(mSampleFrequency);
    oss << ".bin";
    return oss.str();
}

std::filesystem::path VoxelizationPass::getOutputFilePath()
{
    return getVoxelizationResourceFolderPath() / getFileName();
}

void VoxelizationPass::write(std::string fileName, void* pGBuffer, void* pVBuffer, void* pBlockMap)
{
    const auto path = getVoxelizationResourceFolderPath() / fileName;
    std::ofstream f(path, std::ios::binary);
    f.write(reinterpret_cast<char*>(&gridData), sizeof(GridData));

    f.write(reinterpret_cast<const char*>(pVBuffer), gridData.totalVoxelCount() * sizeof(int));
    f.write(reinterpret_cast<const char*>(pGBuffer), gridData.solidVoxelCount * sizeof(VoxelData));
    f.write(reinterpret_cast<const char*>(pBlockMap), gridData.totalBlockCount() * sizeof(uint4));

    f.close();
    gVoxelizationFilesUpdated = true;
}

void VoxelizationPass::parseProperties(const Properties& props)
{
    for (const auto& [key, value] : props)
    {
        if (key == VoxelizationProperties::kSceneName)
        {
            mSceneName = value.operator std::string();
            mSceneNameIndex = getSceneNameIndex(mSceneName);
        }
        else if (key == VoxelizationProperties::kSampleFrequency)
        {
            mSampleFrequency = value;
        }
        else if (key == VoxelizationProperties::kVoxelResolution)
        {
            mVoxelResolution = std::max(1u, static_cast<uint32_t>(value));
        }
        else if (key == VoxelizationProperties::kPolygonPerFrame)
        {
            polygonGroup.maxPolygonCount = std::max(1u, static_cast<uint32_t>(value));
        }
        else if (key == VoxelizationProperties::kLerpNormal)
        {
            mLerpNormal = value;
        }
        else if (key == VoxelizationProperties::kAutoGenerate)
        {
            mAutoGenerate = value;
        }
        else if (key == VoxelizationProperties::kHighMemoryMode)
        {
            mHighMemoryMode = value;
        }
    }
}

void VoxelizationPass::beginGeneration()
{
    if (!mpScene)
        return;

    VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
    mGenerationFailed = false;
    mGenerationFailureReason.clear();

    std::string reason;
    if (!validateGenerationPlan(reason))
    {
        failGeneration(reason);
        return;
    }

    ImageLoader::Instance().setSceneName(mSceneName);
    mVoxelizationComplete = false;
    mSamplingComplete = false;
    mCompleteTimes = 0;
    requestRecompile();
}

void VoxelizationPass::failGeneration(const std::string& reason)
{
    mGenerationFailed = true;
    mGenerationFailureReason = reason;
    mVoxelizationComplete = true;
    mSamplingComplete = true;
    mCompleteTimes = 0;
    Tools::Profiler::Reset();
    logWarning("{}", reason);
}

bool VoxelizationPass::validateGenerationPlan(std::string& reason) const
{
    const size_t totalVoxelCount = gridData.totalVoxelCount();
    const size_t denseVoxelSafetyLimit = getDenseVoxelSafetyLimit(mHighMemoryMode);
    if (totalVoxelCount == 0)
    {
        reason = std::string(getGenerationBackendName()) + " aborted: voxel grid is empty.";
        return false;
    }

    if (totalVoxelCount > size_t(std::numeric_limits<int>::max()))
    {
        reason = std::string(getGenerationBackendName()) + " aborted: voxel grid exceeds the current 32-bit indexing limit (" +
                 std::to_string(totalVoxelCount) + " voxels).";
        return false;
    }

    if (totalVoxelCount > denseVoxelSafetyLimit)
    {
        reason = std::string(getGenerationBackendName()) + " aborted: dense voxel index volume would reach " +
                 formatByteCount(totalVoxelCount * sizeof(int)) + " for " + std::to_string(totalVoxelCount) +
                 " voxels, above the current safety limit of " + formatByteCount(denseVoxelSafetyLimit * sizeof(int)) +
                 " (" + std::to_string(denseVoxelSafetyLimit) + " voxels).";
        if (!mHighMemoryMode)
            reason += " Enable High Memory Mode or reduce voxelResolution before generating.";
        else
            reason += " Reduce voxelResolution before generating.";
        return false;
    }

    const size_t peakWorkingSetBytes = estimatePeakWorkingSetBytes();
    if (peakWorkingSetBytes > kPeakWorkingSetSafetyLimit)
    {
        reason = std::string(getGenerationBackendName()) + " aborted: estimated peak working set is " +
                 formatByteCount(peakWorkingSetBytes) + ", above the current safety limit of " +
                 formatByteCount(kPeakWorkingSetSafetyLimit) + ". Reduce voxelResolution or sampleFrequency.";
        return false;
    }

    return true;
}

size_t VoxelizationPass::estimatePeakWorkingSetBytes() const
{
    const size_t denseVoxelBytes = gridData.totalVoxelCount() * sizeof(int);
    const size_t blockMapBytes = size_t(gridData.totalBlockCount()) * sizeof(uint4);
    return denseVoxelBytes + blockMapBytes;
}
