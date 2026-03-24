#include "VoxelDirectAOPass.h"
#include "Shading.slang"
#include "RenderGraph/RenderPassStandardFlags.h"

namespace
{
const std::string kShaderFile = "RenderPasses/Voxelization/VoxelDirectAO.ps.slang";
const std::string kOutputColor = "color";

enum class VoxelDirectAODrawMode : uint32_t
{
    Combined = 0,
    DirectOnly = 1,
    AOOnly = 2,
    NormalDebug = 3,
    CoverageDebug = 4,
};
} // namespace

VoxelDirectAOPass::VoxelDirectAOPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice), mpDevice(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mDrawMode = static_cast<uint32_t>(VoxelDirectAODrawMode::Combined);
    mShadowBias100 = 0.01f;
    mCheckEllipsoid = true;
    mCheckVisibility = true;
    mCheckCoverage = true;
    mUseMipmap = true;
    mUseEmissiveLight = false;
    mRenderBackground = true;
    mAOEnabled = true;
    mAOSampleCount = 8;
    mAORadius = 6.0f;
    mAOStrength = 1.0f;
    mClearColor = float3(0);

    mOptionsChanged = false;
    mFrameIndex = 0;
    mSelectedResolution = 0;
    mOutputResolution = uint2(1920, 1080);
}

RenderPassReflection VoxelDirectAOPass::reflect(const CompileData& compileData)
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

void VoxelDirectAOPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto pOutputColor = renderData.getTexture(kOutputColor);
    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0));

    if (!mpScene)
        return;

    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        mOptionsChanged = false;
    }

    FALCOR_PROFILE(pRenderContext, "VoxelDirectAO");

    ref<Camera> pCamera = mpScene->getCamera();

    if (!mpFullScreenPass)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        desc.addTypeConformances(mpScene->getTypeConformances());
        mpFullScreenPass = FullScreenPass::create(mpDevice, desc, mpScene->getSceneDefines());
    }

    mpFullScreenPass->addDefine("CHECK_ELLIPSOID", mCheckEllipsoid ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_VISIBILITY", mCheckVisibility ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_COVERAGE", mCheckCoverage ? "1" : "0");
    mpFullScreenPass->addDefine("USE_MIP_MAP", mUseMipmap ? "1" : "0");

    ref<EnvMap> pEnvMap = mpScene->getEnvMap();
    mpFullScreenPass->addDefine("USE_ENV_MAP", pEnvMap ? "1" : "0");
    if (pEnvMap)
    {
        if (!mpEnvMapSampler || mpEnvMapSampler->getEnvMap() != pEnvMap)
            mpEnvMapSampler = std::make_unique<EnvMapSampler>(mpDevice, pEnvMap);
    }

    if (mUseEmissiveLight)
    {
        if (gVoxelizationLightChanged)
        {
            mpScene->getILightCollection(pRenderContext);
            mpFullScreenPass->addDefine("USE_EMISSIVE_LIGHTS", mpScene->useEmissiveLights() ? "1" : "0");
            gVoxelizationLightChanged = false;
            pRenderContext->submit(true);
            return;
        }
    }
    else
    {
        mpFullScreenPass->addDefine("USE_EMISSIVE_LIGHTS", "0");
    }

    auto var = mpFullScreenPass->getRootVar();
    mpScene->bindShaderData(var["gScene"]);
    if (pEnvMap)
        mpEnvMapSampler->bindShaderData(var["gEnvMapSampler"]);

    var[kVBuffer] = renderData.getTexture(kVBuffer);
    var[kGBuffer] = renderData.getResource(kGBuffer)->asBuffer();
    var[kPBuffer] = renderData.getResource(kPBuffer)->asBuffer();
    var[kBlockMap] = renderData.getTexture(kBlockMap);

    auto cbGridData = var["GridData"];
    cbGridData["gridMin"] = gridData.gridMin;
    cbGridData["voxelSize"] = gridData.voxelSize;
    cbGridData["voxelCount"] = gridData.voxelCount;
    cbGridData["solidVoxelCount"] = static_cast<uint32_t>(gridData.solidVoxelCount);

    auto cb = var["CB"];
    cb["pixelCount"] = mOutputResolution;
    cb["blockCount"] = gridData.blockCount3D();
    cb["invVP"] = math::inverse(pCamera->getViewProjMatrixNoJitter());
    cb["shadowBias"] = mShadowBias100 / 100.0f / gridData.voxelSize.x;
    cb["drawMode"] = mDrawMode;
    cb["aoEnabled"] = mAOEnabled;
    cb["aoSampleCount"] = mAOSampleCount;
    cb["aoRadius"] = mAORadius;
    cb["aoStrength"] = mAOStrength;
    cb["frameIndex"] = mFrameIndex;
    cb["minPdf"] = 0.001f;
    cb["renderBackground"] = mRenderBackground;
    cb["clearColor"] = float4(mClearColor, 0);
    mFrameIndex++;

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutputColor, 0);
    mpFullScreenPass->execute(pRenderContext, fbo);
}

void VoxelDirectAOPass::compile(RenderContext* pRenderContext, const CompileData& compileData)
{
    gVoxelizationLightChanged = true;
}

void VoxelDirectAOPass::renderUI(Gui::Widgets& widget)
{
    if (widget.checkbox("AO Enabled", mAOEnabled))
        mOptionsChanged = true;
    if (widget.var("AO Sample Count", mAOSampleCount, 1u, 64u))
        mOptionsChanged = true;
    if (widget.var("AO Radius (voxels)", mAORadius, 0.0f, 32.0f, 0.1f))
        mOptionsChanged = true;
    if (widget.var("AO Strength", mAOStrength, 0.0f, 1.0f, 0.01f))
        mOptionsChanged = true;
    if (widget.checkbox("Use Emissive Light", mUseEmissiveLight))
    {
        gVoxelizationLightChanged = true;
        mOptionsChanged = true;
    }
    if (widget.checkbox("Check Ellipsoid", mCheckEllipsoid))
        mOptionsChanged = true;
    if (widget.checkbox("Check Visibility", mCheckVisibility))
        mOptionsChanged = true;
    if (widget.checkbox("Check Coverage", mCheckCoverage))
        mOptionsChanged = true;
    if (widget.checkbox("Use Mipmap", mUseMipmap))
        mOptionsChanged = true;
    if (widget.slider("Shadow Bias(x100)", mShadowBias100, 0.0f, 0.2f))
        mOptionsChanged = true;

    static const Gui::DropdownList kDrawModes = {
        {static_cast<uint32_t>(VoxelDirectAODrawMode::Combined), "Combined"},
        {static_cast<uint32_t>(VoxelDirectAODrawMode::DirectOnly), "DirectOnly"},
        {static_cast<uint32_t>(VoxelDirectAODrawMode::AOOnly), "AOOnly"},
        {static_cast<uint32_t>(VoxelDirectAODrawMode::NormalDebug), "NormalDebug"},
        {static_cast<uint32_t>(VoxelDirectAODrawMode::CoverageDebug), "CoverageDebug"},
    };
    if (widget.dropdown("Draw Mode", kDrawModes, mDrawMode))
        mOptionsChanged = true;

    if (widget.rgbColor("Clear Color", mClearColor))
        mOptionsChanged = true;
    if (widget.checkbox("Render Background", mRenderBackground))
        mOptionsChanged = true;

    static const uint32_t kResolutions[] = {0, 32, 64, 128, 256, 512, 1024};
    Gui::DropdownList resolutionList;
    for (uint32_t resolution : kResolutions)
        resolutionList.push_back({resolution, std::to_string(resolution)});

    if (widget.dropdown("Output Resolution", resolutionList, mSelectedResolution))
    {
        if (mSelectedResolution == 0)
            mOutputResolution = uint2(1920, 1080);
        else
            mOutputResolution = uint2(mSelectedResolution, mSelectedResolution);

        if (const auto camera = mpScene ? mpScene->getCamera() : nullptr)
            camera->setAspectRatio(mOutputResolution.x / static_cast<float>(mOutputResolution.y));

        requestRecompile();
    }
}

void VoxelDirectAOPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpFullScreenPass = nullptr;
    mpEnvMapSampler.reset();
    mFrameIndex = 0;
    gVoxelizationLightChanged = true;
}
