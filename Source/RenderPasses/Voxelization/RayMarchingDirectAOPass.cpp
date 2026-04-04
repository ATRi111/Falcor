#include "RayMarchingDirectAOPass.h"
#include "Shading.slang"
#include "RenderGraph/RenderPassStandardFlags.h"
#include <algorithm>

namespace
{
const std::string kShaderFile = "RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang";
const std::string kOutputColor = "color";
const std::string kPropDrawMode = "drawMode";
const std::string kPropShadowBias = "shadowBias";
const std::string kPropCheckEllipsoid = "checkEllipsoid";
const std::string kPropCheckVisibility = "checkVisibility";
const std::string kPropCheckCoverage = "checkCoverage";
const std::string kPropUseMipmap = "useMipmap";
const std::string kPropRenderBackground = "renderBackground";
const std::string kPropOutputResolution = "outputResolution";
const std::string kPropTransmittanceThreshold = "transmittanceThreshold";
const std::string kPropAOEnabled = "aoEnabled";
const std::string kPropAOStrength = "aoStrength";
const std::string kPropAORadius = "aoRadius";
const std::string kPropAOStepCount = "aoStepCount";
const std::string kPropAODirectionSet = "aoDirectionSet";
const std::string kPropAOContactStrength = "aoContactStrength";
const std::string kPropAOUseStableRotation = "aoUseStableRotation";

enum class RayMarchingDirectAODrawMode : uint32_t
{
    Combined = 0,
    DirectOnly = 1,
    AOOnly = 2,
    NormalDebug = 3,
    CoverageDebug = 4,
};
} // namespace

RayMarchingDirectAOPass::RayMarchingDirectAOPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mDrawMode = static_cast<uint32_t>(RayMarchingDirectAODrawMode::Combined);
    mShadowBias100 = 0.01f;
    mCheckEllipsoid = true;
    mCheckVisibility = true;
    mCheckCoverage = true;
    mUseMipmap = true;
    mRenderBackground = true;
    mAOEnabled = true;
    mOptionsChanged = false;
    mAOUseStableRotation = true;
    mFrameIndex = 0;
    mAOStepCount = 3;
    mAODirectionSet = 6;
    mSelectedResolution = 0;
    mOutputResolution = uint2(1920, 1080);
    mAOStrength = 0.55f;
    mAORadius = 6.0f;
    mAOContactStrength = 0.75f;
    mTransmittanceThreshold100 = 5.0f;

    parseProperties(props);
}

void RayMarchingDirectAOPass::parseProperties(const Properties& props)
{
    for (const auto& [key, value] : props)
    {
        if (key == kPropDrawMode)
            mDrawMode = value;
        else if (key == kPropShadowBias)
            mShadowBias100 = value;
        else if (key == kPropCheckEllipsoid)
            mCheckEllipsoid = value;
        else if (key == kPropCheckVisibility)
            mCheckVisibility = value;
        else if (key == kPropCheckCoverage)
            mCheckCoverage = value;
        else if (key == kPropUseMipmap)
            mUseMipmap = value;
        else if (key == kPropRenderBackground)
            mRenderBackground = value;
        else if (key == kPropAOEnabled)
            mAOEnabled = value;
        else if (key == kPropAOStrength)
            mAOStrength = value;
        else if (key == kPropAORadius)
            mAORadius = value;
        else if (key == kPropAOStepCount)
            mAOStepCount = std::max(1u, uint32_t(value));
        else if (key == kPropAODirectionSet)
        {
            const uint32_t directionSet = value;
            mAODirectionSet = directionSet >= 6 ? 6u : 4u;
        }
        else if (key == kPropAOContactStrength)
            mAOContactStrength = value;
        else if (key == kPropAOUseStableRotation)
            mAOUseStableRotation = value;
        else if (key == kPropOutputResolution)
        {
            mSelectedResolution = value;
            mOutputResolution = mSelectedResolution == 0 ? uint2(1920, 1080) : uint2(mSelectedResolution, mSelectedResolution);
        }
        else if (key == kPropTransmittanceThreshold)
            mTransmittanceThreshold100 = value;
        else
            logWarning("Unknown property '{}' in RayMarchingDirectAOPass properties.", key);
    }
}

Properties RayMarchingDirectAOPass::getProperties() const
{
    Properties props;
    props[kPropDrawMode] = mDrawMode;
    props[kPropShadowBias] = mShadowBias100;
    props[kPropCheckEllipsoid] = mCheckEllipsoid;
    props[kPropCheckVisibility] = mCheckVisibility;
    props[kPropCheckCoverage] = mCheckCoverage;
    props[kPropUseMipmap] = mUseMipmap;
    props[kPropRenderBackground] = mRenderBackground;
    props[kPropAOEnabled] = mAOEnabled;
    props[kPropAOStrength] = mAOStrength;
    props[kPropAORadius] = mAORadius;
    props[kPropAOStepCount] = mAOStepCount;
    props[kPropAODirectionSet] = mAODirectionSet;
    props[kPropAOContactStrength] = mAOContactStrength;
    props[kPropAOUseStableRotation] = mAOUseStableRotation;
    props[kPropOutputResolution] = mSelectedResolution;
    props[kPropTransmittanceThreshold] = mTransmittanceThreshold100;
    return props;
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
    ref<Texture> pOutputColor = renderData.getTexture(kOutputColor);
    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0));

    if (!mpScene)
        return;

    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        mFrameIndex = 0;
        mOptionsChanged = false;
    }

    if (!mpFullScreenPass)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        DefineList defines = mpScene->getSceneDefines();
        defines.add("CHECK_ELLIPSOID", mCheckEllipsoid ? "1" : "0");
        defines.add("CHECK_VISIBILITY", mCheckVisibility ? "1" : "0");
        defines.add("CHECK_COVERAGE", mCheckCoverage ? "1" : "0");
        defines.add("USE_MIP_MAP", mUseMipmap ? "1" : "0");
        mpFullScreenPass = FullScreenPass::create(mpDevice, desc, defines);
    }

    auto pEnvMap = mpScene->getEnvMap();
    mpFullScreenPass->addDefine("CHECK_ELLIPSOID", mCheckEllipsoid ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_VISIBILITY", mCheckVisibility ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_COVERAGE", mCheckCoverage ? "1" : "0");
    mpFullScreenPass->addDefine("USE_MIP_MAP", mUseMipmap ? "1" : "0");
    mpFullScreenPass->addDefine("USE_ENV_MAP", pEnvMap ? "1" : "0");

    ref<Camera> pCamera = mpScene->getCamera();
    auto var = mpFullScreenPass->getRootVar();
    mpScene->bindShaderData(var["gScene"]);
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
    cb["invVP"] = math::inverse(pCamera->getViewProjMatrixNoJitter());
    cb["shadowBias"] = mShadowBias100 / 100.0f / gridData.voxelSize.x;
    cb["drawMode"] = mDrawMode;
    cb["renderBackground"] = mRenderBackground;
    cb["transmittanceThreshold"] = mTransmittanceThreshold100 / 100.0f;
    cb["aoEnabled"] = mAOEnabled;
    cb["aoStrength"] = mAOStrength;
    cb["aoRadius"] = mAORadius;
    cb["aoStepCount"] = mAOStepCount;
    cb["aoDirectionSet"] = mAODirectionSet;
    cb["aoContactStrength"] = mAOContactStrength;
    cb["aoUseStableRotation"] = mAOUseStableRotation;

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
    static const Gui::DropdownList kDrawModes = {
        {static_cast<uint32_t>(RayMarchingDirectAODrawMode::Combined), "Combined"},
        {static_cast<uint32_t>(RayMarchingDirectAODrawMode::DirectOnly), "DirectOnly"},
        {static_cast<uint32_t>(RayMarchingDirectAODrawMode::AOOnly), "AOOnly"},
        {static_cast<uint32_t>(RayMarchingDirectAODrawMode::NormalDebug), "NormalDebug"},
        {static_cast<uint32_t>(RayMarchingDirectAODrawMode::CoverageDebug), "CoverageDebug"},
    };

    if (widget.dropdown("Draw Mode", kDrawModes, mDrawMode))
        mOptionsChanged = true;
    if (widget.checkbox("Render Background", mRenderBackground))
        mOptionsChanged = true;
    if (widget.checkbox("Use Mipmap", mUseMipmap))
        mOptionsChanged = true;
    if (widget.checkbox("AO Enabled", mAOEnabled))
        mOptionsChanged = true;
    if (widget.checkbox("AO Stable Rotation", mAOUseStableRotation))
        mOptionsChanged = true;
    if (widget.checkbox("Check Ellipsoid", mCheckEllipsoid))
        mOptionsChanged = true;
    if (widget.checkbox("Check Visibility", mCheckVisibility))
        mOptionsChanged = true;
    if (widget.checkbox("Check Coverage", mCheckCoverage))
        mOptionsChanged = true;
    if (widget.slider("AO Strength", mAOStrength, 0.0f, 1.0f))
        mOptionsChanged = true;
    if (widget.slider("AO Radius", mAORadius, 0.5f, 24.0f))
        mOptionsChanged = true;
    if (widget.slider("AO Contact Strength", mAOContactStrength, 0.0f, 2.0f))
        mOptionsChanged = true;
    if (widget.slider("AO Step Count", mAOStepCount, 1u, 8u))
        mOptionsChanged = true;
    static const Gui::DropdownList kAODirectionSets = {
        {4u, "4 Directions"},
        {6u, "6 Directions"},
    };
    if (widget.dropdown("AO Direction Set", kAODirectionSets, mAODirectionSet))
        mOptionsChanged = true;
    if (widget.slider("Shadow Bias(x100)", mShadowBias100, 0.0f, 0.2f))
        mOptionsChanged = true;
    if (widget.slider("Transmittance Threshold(x100)", mTransmittanceThreshold100, 0.0f, 10.0f))
        mOptionsChanged = true;

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

    if (const auto pCamera = mpScene ? mpScene->getCamera() : nullptr)
        pCamera->setAspectRatio(mOutputResolution.x / static_cast<float>(mOutputResolution.y));
}
