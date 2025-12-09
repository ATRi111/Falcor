/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#include "RayMarchingPass.h"
#include "Math/SphericalHarmonics.slang"
#include "RenderGraph/RenderPassStandardFlags.h"

namespace
{
const std::string kShaderFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/RayMarching.ps.slang";
const std::string kOutputColor = "color";
} // namespace

RayMarchingPass::RayMarchingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mpDevice = pDevice;
    mVisibilityBias = 1.f;
    mTransmittanceThreshould = 0.01f;
    mDebug = false;
    mUpdateScene = false;
    mCheckEllipsoid = true;
    mCheckVisibility = true;
    mCheckCoverage = true;
    mDrawMode = 0;
    mMaxBounce = 1;

    mSelectedUV = float2(0);

    mOptionsChanged = false;
    mFrameIndex = 0;

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Point, TextureFilteringMode::Point, TextureFilteringMode::Point)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpPointSampler = mpDevice->createSampler(samplerDesc);
}

RenderPassReflection RayMarchingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput(kVBuffer, kVBuffer)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::R32Uint)
        .texture3D(gridData.voxelCount.x, gridData.voxelCount.y, gridData.voxelCount.z, 1);

    reflector.addInput(kGBuffer, kGBuffer)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(VoxelData));

    reflector.addOutput(kOutputColor, "Color")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);
    return reflector;
}

void RayMarchingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        mOptionsChanged = false;
    }

    if (mUpdateScene)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        desc.addTypeConformances(mpScene->getTypeConformances());
        mpFullScreenPass = FullScreenPass::create(mpDevice, desc, mpScene->getSceneDefines());
        mUpdateScene = false;
    }
    mpFullScreenPass->addDefine("CHECK_ELLIPSOID", mCheckEllipsoid ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_VISIBILITY", mCheckVisibility ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_COVERAGE", mCheckCoverage ? "1" : "0");
    mpFullScreenPass->addDefine("DEBUG", mDebug ? "1" : "0");

    ref<Camera> pCamera = mpScene->getCamera();
    ref<Texture> pOutputColor = renderData.getTexture(kOutputColor);
    if (!mSelectedVoxel)
        mSelectedVoxel = mpDevice->createStructuredBuffer(sizeof(float4), 1, ResourceBindFlags::UnorderedAccess);

    mSelectedPixel = uint2(mSelectedUV.x * pOutputColor->getWidth(), mSelectedUV.y * pOutputColor->getHeight());

    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0));
    pRenderContext->clearUAV(mSelectedVoxel->getUAV().get(), float4(-1));

    auto var = mpFullScreenPass->getRootVar();
    mpScene->bindShaderData(var["scene"]);

    var[kVBuffer] = renderData.getTexture(kVBuffer);
    var[kGBuffer] = renderData.getResource(kGBuffer)->asBuffer();
    var["selectedVoxel"] = mSelectedVoxel;

    auto cb_GridData = var["GridData"];
    cb_GridData["gridMin"] = gridData.gridMin;
    cb_GridData["voxelSize"] = gridData.voxelSize;
    cb_GridData["voxelCount"] = gridData.voxelCount;
    cb_GridData["solidVoxelCount"] = (uint)gridData.solidVoxelCount;

    auto cb = var["CB"];
    cb["pixelCount"] = uint2(pOutputColor->getWidth(), pOutputColor->getHeight());
    cb["invVP"] = math::inverse(pCamera->getViewProjMatrixNoJitter());
    cb["visibilityBias"] = mVisibilityBias;
    cb["drawMode"] = mDrawMode;
    cb["maxBounce"] = mMaxBounce;
    cb["frameIndex"] = mFrameIndex;
    cb["transmittanceThreshould"] = mTransmittanceThreshould;
    mFrameIndex++;

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutputColor, 0);
    mpFullScreenPass->execute(pRenderContext, fbo);
}

void RayMarchingPass::renderUI(Gui::Widgets& widget)
{
    if (widget.checkbox("Debug", mDebug))
        mOptionsChanged = true;
    if (widget.checkbox("Check Ellipsoid", mCheckEllipsoid))
        mOptionsChanged = true;
    if (widget.checkbox("Check Visibility", mCheckVisibility))
        mOptionsChanged = true;
    if (widget.checkbox("Check Coverage", mCheckCoverage))
        mOptionsChanged = true;
    if (mCheckVisibility && widget.slider("Visibility Bias", mVisibilityBias, 0.0f, 5.0f))
        mOptionsChanged = true;
    if (widget.slider("Transmittance Threshould", mTransmittanceThreshould, 0.0f, 1.0f))
        mOptionsChanged = true;
    if (widget.dropdown("Draw Mode", reinterpret_cast<ABSDFDrawMode&>(mDrawMode)))
        mOptionsChanged = true;
    if (widget.slider("Max Bounce", mMaxBounce, 0u, 10u))
        mOptionsChanged = true;

    widget.text("Selected Pixel: " + ToString(mSelectedPixel));
}

void RayMarchingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mUpdateScene = true;
}

bool RayMarchingPass::onMouseEvent(const MouseEvent& mouseEvent)
{
    if (mouseEvent.type == MouseEvent::Type::ButtonDown &&
        mouseEvent.button == Input::MouseButton::Left)
    {
        mSelectedUV = mouseEvent.pos;

        return true;
    }
    return false;
}
