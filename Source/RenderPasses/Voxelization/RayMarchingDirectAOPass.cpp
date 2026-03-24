#include "RayMarchingDirectAOPass.h"
#include "Shading.slang"
#include "RenderGraph/RenderPassStandardFlags.h"

namespace
{
const std::string kShaderFile = "RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang";
const std::string kOutputColor = "color";
} // namespace

RayMarchingDirectAOPass::RayMarchingDirectAOPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mOptionsChanged = false;
    mFrameIndex = 0;
    mSelectedResolution = 0;
    mOutputResolution = uint2(1920, 1080);
}

RenderPassReflection RayMarchingDirectAOPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput(kVBuffer, kVBuffer)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::R32Uint)
        .texture3D(gridData.voxelCount.x, gridData.voxelCount.y, gridData.voxelCount.z, 1);

    reflector.addInput(kGBuffer, kGBuffer)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(PrimitiveBSDF));

    reflector.addInput(kPBuffer, kPBuffer)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(Ellipsoid));

    reflector.addInput(kBlockMap, kBlockMap)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::RGBA32Uint)
        .texture2D(gridData.blockCount().x, gridData.blockCount().y);

    reflector.addOutput(kOutputColor, "Color")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(mOutputResolution.x, mOutputResolution.y, 1, 1);

    return reflector;
}

void RayMarchingDirectAOPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        mOptionsChanged = false;
    }

    ref<Texture> pOutputColor = renderData.getTexture(kOutputColor);
    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0));

    if (!mpFullScreenPass)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        // Stage 1 uses a pure-color shader that does not import scene interfaces yet.
        // Passing scene type conformances here breaks startup when script and scene are loaded together.
        mpFullScreenPass = FullScreenPass::create(mpDevice, desc);
    }

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutputColor, 0);
    mpFullScreenPass->execute(pRenderContext, fbo);
    mFrameIndex++;
}

void RayMarchingDirectAOPass::compile(RenderContext* pRenderContext, const CompileData& compileData)
{
    mFrameIndex = 0;
}

void RayMarchingDirectAOPass::renderUI(Gui::Widgets& widget)
{
    static const uint kResolutions[] = {0, 32, 64, 128, 256, 512, 1024};
    Gui::DropdownList list;
    for (uint resolution : kResolutions)
        list.push_back({resolution, std::to_string(resolution)});

    if (widget.dropdown("Output Resolution", list, mSelectedResolution))
    {
        if (mSelectedResolution == 0)
            mOutputResolution = uint2(1920, 1080);
        else
            mOutputResolution = uint2(mSelectedResolution, mSelectedResolution);

        if (const auto pCamera = mpScene ? mpScene->getCamera() : nullptr)
            pCamera->setAspectRatio(mOutputResolution.x / static_cast<float>(mOutputResolution.y));

        mOptionsChanged = true;
        requestRecompile();
    }

    widget.text("Frame Index: " + std::to_string(mFrameIndex));
}

void RayMarchingDirectAOPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpFullScreenPass = nullptr;
    mFrameIndex = 0;
}
