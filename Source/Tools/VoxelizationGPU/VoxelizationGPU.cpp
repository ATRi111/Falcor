#include "Falcor.h"
#include "Core/SampleApp.h"
#include "RenderGraph/RenderGraph.h"
#include "RenderGraph/RenderPassStandardFlags.h"
#include "RenderPasses/Voxelization/VoxelizationProperties.h"
#include "Scene/SceneBuilder.h"
#include "Utils/Logger.h"

#include <args.hxx>

#include <chrono>
#include <iostream>
#include <vector>

FALCOR_EXPORT_D3D12_AGILITY_SDK

using namespace Falcor;

namespace
{
const char kPassName[] = "VoxelizationPass";

std::filesystem::path findProjectRoot()
{
    std::vector<std::filesystem::path> searchRoots = {std::filesystem::current_path(), getRuntimeDirectory()};
    for (const auto& root : searchRoots)
    {
        auto candidate = std::filesystem::absolute(root);
        while (!candidate.empty())
        {
            if (
                std::filesystem::exists(candidate / "CMakeLists.txt") &&
                std::filesystem::exists(candidate / "Source" / "RenderPasses" / "Voxelization")
            )
            {
                return candidate;
            }

            const auto parent = candidate.parent_path();
            if (parent == candidate)
                break;
            candidate = parent;
        }
    }

    return std::filesystem::current_path();
}

std::filesystem::path resolveInputPath(const std::filesystem::path& path)
{
    if (path.is_absolute())
        return path;

    if (std::filesystem::exists(path))
        return std::filesystem::absolute(path);

    const auto projectPath = findProjectRoot() / path;
    if (std::filesystem::exists(projectPath))
        return projectPath;

    return std::filesystem::absolute(path);
}

Device::Type parseDeviceType(const std::string& value)
{
    if (value == "d3d12")
        return Device::Type::D3D12;
    if (value == "vulkan")
        return Device::Type::Vulkan;

    FALCOR_THROW("Invalid device type '{}'. Use 'd3d12' or 'vulkan'.", value);
}

struct ToolOptions
{
    std::filesystem::path scenePath;
    Properties passProperties;
    uint32_t maxFrames = 0;
    uint32_t timeoutSeconds = 0;
};

class VoxelizationGPUApp : public SampleApp
{
public:
    VoxelizationGPUApp(const SampleAppConfig& config, ToolOptions options) : SampleApp(config), mOptions(std::move(options)) {}

    const std::string& getOutputPath() const { return mOutputPath; }
    uint64_t getFrameCount() const { return mFrameCount; }

    void onLoad(RenderContext* pRenderContext) override
    {
        mpGraph = RenderGraph::create(getDevice(), "VoxelizationGPU");
        auto pPass = mpGraph->createPass(kPassName, "VoxelizationPass_GPU", mOptions.passProperties);
        if (!pPass)
            FALCOR_THROW("Failed to create render pass '{}'.", "VoxelizationPass_GPU");

        mpGraph->markOutput(std::string(kPassName) + ".dummy");
        mpGraph->onResize(getTargetFbo().get());

        auto& dict = mpGraph->getPassesDictionary();
        dict[VoxelizationProperties::kDictionaryCompleted] = false;
        dict[VoxelizationProperties::kDictionaryOutputPath] = std::string{};

        mpScene = SceneBuilder(getDevice(), mOptions.scenePath, Settings(), SceneBuilder::Flags::Default).getScene();
        mpGraph->setScene(mpScene);
        mStartTime = std::chrono::steady_clock::now();
    }

    void onResize(uint32_t width, uint32_t height) override
    {
        if (mpGraph)
            mpGraph->onResize(getTargetFbo().get());

        if (mpScene && height > 0)
            mpScene->setCameraAspectRatio(static_cast<float>(width) / static_cast<float>(height));
    }

    void onFrameRender(RenderContext* pRenderContext, const ref<Fbo>& pTargetFbo) override
    {
        const float4 clearColor(0, 0, 0, 1);
        pRenderContext->clearFbo(pTargetFbo.get(), clearColor, 1.0f, 0, FboAttachmentType::All);

        mpGraph->compile(pRenderContext);

        if (mpScene)
        {
            const auto sceneUpdates = mpScene->update(pRenderContext, getGlobalClock().getTime());
            if (sceneUpdates != IScene::UpdateFlags::None)
                mpGraph->onSceneUpdates(pRenderContext, sceneUpdates);
        }

        mpGraph->getPassesDictionary()[kRenderPassRefreshFlags] = RenderPassRefreshFlags::None;
        mpGraph->execute(pRenderContext);

        if (mpGraph->getOutputCount() > 0)
        {
            ref<Texture> pOutTex = mpGraph->getOutput(0)->asTexture();
            if (pOutTex)
                pRenderContext->blit(pOutTex->getSRV(), pTargetFbo->getRenderTargetView(0));
        }

        ++mFrameCount;

        auto& dict = mpGraph->getPassesDictionary();
        if (dict.getValue<bool>(VoxelizationProperties::kDictionaryCompleted, false))
        {
            mOutputPath = dict.getValue<std::string>(VoxelizationProperties::kDictionaryOutputPath, std::string{});
            if (mOutputPath.empty())
                FALCOR_THROW("Voxelization completed without reporting an output path.");

            shutdown(0);
            return;
        }

        if (mOptions.maxFrames > 0 && mFrameCount >= mOptions.maxFrames)
            FALCOR_THROW("Voxelization did not finish within {} frames.", mOptions.maxFrames);

        if (mOptions.timeoutSeconds > 0)
        {
            const auto elapsedSeconds = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - mStartTime).count();
            if (elapsedSeconds >= mOptions.timeoutSeconds)
                FALCOR_THROW("Voxelization timed out after {} seconds.", mOptions.timeoutSeconds);
        }

        if (mFrameCount % 60 == 0)
            logInfo("Voxelization still running after {} frames.", mFrameCount);
    }

private:
    ToolOptions mOptions;
    ref<RenderGraph> mpGraph;
    ref<Scene> mpScene;
    std::chrono::steady_clock::time_point mStartTime{};
    uint64_t mFrameCount = 0;
    std::string mOutputPath;
};
} // namespace

int runMain(int argc, char** argv)
{
    args::ArgumentParser parser("Headless GPU voxelization tool that reuses VoxelizationPass_GPU and writes the original .bin output.");
    parser.helpParams.programName = "VoxelizationGPU";

    args::HelpFlag helpFlag(parser, "help", "Display this help menu.", {'h', "help"});
    args::ValueFlag<std::string> deviceTypeFlag(parser, "d3d12|vulkan", "Graphics device type.", {'d', "device-type"});
    args::Flag listGPUsFlag(parser, "", "List available GPUs", {"list-gpus"});
    args::ValueFlag<uint32_t> gpuFlag(parser, "index", "Select specific GPU to use.", {"gpu"});
    args::ValueFlag<int32_t> verbosityFlag(
        parser,
        "verbosity",
        "Logging verbosity (0=disabled, 1=fatal, 2=error, 3=warning, 4=info, 5=debug).",
        {'v', "verbosity"},
        4
    );
    args::ValueFlag<uint32_t> voxelResolutionFlag(
        parser,
        "count",
        "Voxel resolution for the longest scene axis.",
        {"voxel-resolution"},
        512
    );
    args::ValueFlag<uint32_t> sampleFrequencyFlag(
        parser,
        "count",
        "Sample frequency used by AnalyzePolygon.",
        {"sample-frequency"},
        256
    );
    args::ValueFlag<uint32_t> polygonPerFrameFlag(
        parser,
        "count",
        "Maximum polygon count processed per frame.",
        {"polygon-per-frame"},
        256000
    );
    args::ValueFlag<std::string> sceneNameFlag(
        parser,
        "name",
        "Scene name used in the output file name. Use 'Auto' to derive it from the scene path.",
        {"scene-name"},
        "Auto"
    );
    args::ValueFlag<double> solidRateFlag(
        parser,
        "rate",
        "Estimated solid voxel ratio used to size GPU buffers.",
        {"solid-rate"},
        0.4
    );
    args::Flag lerpNormalFlag(parser, "", "Enable normal interpolation during AnalyzePolygon.", {"lerp-normal"});
    args::ValueFlag<uint32_t> maxFramesFlag(
        parser,
        "count",
        "Optional frame limit before aborting. 0 means unlimited.",
        {"max-frames"},
        0
    );
    args::ValueFlag<uint32_t> timeoutSecondsFlag(
        parser,
        "seconds",
        "Optional wall-clock timeout in seconds. 0 means unlimited.",
        {"timeout-seconds"},
        0
    );
    args::Positional<std::string> sceneFlag(parser, "scene", "Scene file to voxelize.", args::Options::Required);
    args::CompletionFlag completionFlag(parser, {"complete"});

    try
    {
        parser.ParseCLI(argc, argv);
    }
    catch (const args::Completion& e)
    {
        std::cout << e.what();
        return 0;
    }
    catch (const args::Help&)
    {
        std::cout << parser;
        return 0;
    }
    catch (const args::ParseError& e)
    {
        std::cerr << e.what() << std::endl;
        std::cerr << parser;
        return 1;
    }
    catch (const args::RequiredError& e)
    {
        std::cerr << e.what() << std::endl;
        std::cerr << parser;
        return 1;
    }

    const int32_t verbosity = args::get(verbosityFlag);
    if (verbosity < 0 || verbosity >= static_cast<int32_t>(Logger::Level::Count))
    {
        std::cerr << "Invalid verbosity level " << verbosity << std::endl;
        return 1;
    }
    Logger::setVerbosity(static_cast<Logger::Level>(verbosity));

    SampleAppConfig config;
    config.headless = true;
    config.showUI = false;
    config.windowDesc.title = "VoxelizationGPU";
    config.windowDesc.width = 1;
    config.windowDesc.height = 1;
    config.windowDesc.resizableWindow = false;

    if (deviceTypeFlag)
        config.deviceDesc.type = parseDeviceType(args::get(deviceTypeFlag));

    if (listGPUsFlag)
    {
        const auto gpus = Device::getGPUs(config.deviceDesc.type);
        for (size_t i = 0; i < gpus.size(); ++i)
            fmt::print("GPU {}: {}\n", i, gpus[i].name);
        return 0;
    }

    if (gpuFlag)
        config.deviceDesc.gpu = args::get(gpuFlag);

    ToolOptions options;
    options.scenePath = resolveInputPath(args::get(sceneFlag));
    if (!std::filesystem::exists(options.scenePath))
        FALCOR_THROW("Scene file '{}' does not exist.", options.scenePath.string());

    options.passProperties[VoxelizationProperties::kSceneName] = args::get(sceneNameFlag);
    options.passProperties[VoxelizationProperties::kSampleFrequency] = args::get(sampleFrequencyFlag);
    options.passProperties[VoxelizationProperties::kVoxelResolution] = args::get(voxelResolutionFlag);
    options.passProperties[VoxelizationProperties::kPolygonPerFrame] = args::get(polygonPerFrameFlag);
    options.passProperties[VoxelizationProperties::kLerpNormal] = bool(lerpNormalFlag);
    options.passProperties[VoxelizationProperties::kAutoGenerate] = true;
    options.passProperties[VoxelizationProperties::kSolidRate] = args::get(solidRateFlag);
    options.maxFrames = args::get(maxFramesFlag);
    options.timeoutSeconds = args::get(timeoutSecondsFlag);

    const auto startTime = std::chrono::steady_clock::now();
    VoxelizationGPUApp app(config, options);
    const int result = app.run();
    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startTime).count();

    if (result == 0)
    {
        logInfo("Voxelization finished in {} frames ({} ms).", app.getFrameCount(), elapsedMs);
        std::cout << app.getOutputPath() << std::endl;
    }

    return result;
}

int main(int argc, char** argv)
{
    return catchAndReportAllExceptions([&]() { return runMain(argc, argv); });
}
