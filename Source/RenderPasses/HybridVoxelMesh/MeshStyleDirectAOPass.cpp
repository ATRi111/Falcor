/***************************************************************************
 # Copyright (c) 2015-24, NVIDIA CORPORATION. All rights reserved.
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
#include "MeshStyleDirectAOPass.h"

namespace
{
const char kShaderFile[] = "RenderPasses/HybridVoxelMesh/MeshStyleDirectAOPass.ps.slang";

const char kViewMode[] = "viewMode";
const char kShadowBias[] = "shadowBias";
const char kRenderBackground[] = "renderBackground";
const char kAOEnabled[] = "aoEnabled";
const char kAOStrength[] = "aoStrength";
const char kAORadius[] = "aoRadius";
const char kAOStepCount[] = "aoStepCount";
const char kAODirectionSet[] = "aoDirectionSet";
const char kAOContactStrength[] = "aoContactStrength";
const char kAOUseStableRotation[] = "aoUseStableRotation";

const char kInputPosW[] = "posW";
const char kInputNormW[] = "normW";
const char kInputFaceNormalW[] = "faceNormalW";
const char kInputViewW[] = "viewW";
const char kInputDiffuseOpacity[] = "diffuseOpacity";
const char kInputSpecRough[] = "specRough";
const char kOutputColor[] = "color";
} // namespace

MeshStyleDirectAOPass::MeshStyleDirectAOPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("MeshStyleDirectAOPass requires Shader Model 6.5 support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::RaytracingTier1_1))
        FALCOR_THROW("MeshStyleDirectAOPass requires Raytracing Tier 1.1 support.");

    for (const auto& [key, value] : props)
    {
        if (key == kViewMode)
            mViewMode = value.operator ViewMode();
        else if (key == kShadowBias)
            setShadowBias(value);
        else if (key == kRenderBackground)
            mRenderBackground = value;
        else if (key == kAOEnabled)
            mAOEnabled = value;
        else if (key == kAOStrength)
            setAOStrength(value);
        else if (key == kAORadius)
            setAORadius(value);
        else if (key == kAOStepCount)
            setAOStepCount(uint32_t(value));
        else if (key == kAODirectionSet)
            setAODirectionSet(uint32_t(value));
        else if (key == kAOContactStrength)
            setAOContactStrength(value);
        else if (key == kAOUseStableRotation)
            mAOUseStableRotation = value;
        else
            logWarning("Unknown property '{}' in a MeshStyleDirectAOPass properties.", key);
    }

    mpFbo = Fbo::create(mpDevice);
}

Properties MeshStyleDirectAOPass::getProperties() const
{
    Properties props;
    props[kViewMode] = mViewMode;
    props[kShadowBias] = mShadowBias;
    props[kRenderBackground] = mRenderBackground;
    props[kAOEnabled] = mAOEnabled;
    props[kAOStrength] = mAOStrength;
    props[kAORadius] = mAORadius;
    props[kAOStepCount] = mAOStepCount;
    props[kAODirectionSet] = mAODirectionSet;
    props[kAOContactStrength] = mAOContactStrength;
    props[kAOUseStableRotation] = mAOUseStableRotation;
    return props;
}

RenderPassReflection MeshStyleDirectAOPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputPosW, "Mesh world position").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputNormW, "Mesh world normal").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputFaceNormalW, "Mesh world face normal").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputViewW, "Mesh world view direction").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputDiffuseOpacity, "Mesh diffuse albedo and opacity").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputSpecRough, "Mesh specular and roughness").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addOutput(kOutputColor, "Mesh style color").bindFlags(ResourceBindFlags::RenderTarget).format(ResourceFormat::RGBA32Float);
    return reflector;
}

void MeshStyleDirectAOPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto pOutput = renderData.getTexture(kOutputColor);
    FALCOR_ASSERT(pOutput);

    pRenderContext->clearRtv(pOutput->getRTV().get(), float4(0.f, 0.f, 0.f, 1.f));

    if (!mpScene)
        return;

    if (!mpPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());
        desc.setShaderModel(ShaderModel::SM6_5);
        mpPass = FullScreenPass::create(mpDevice, desc, mpScene->getSceneDefines());
    }

    auto var = mpPass->getRootVar();
    mpScene->bindShaderDataForRaytracing(pRenderContext, var["gScene"]);
    var["gPosW"] = renderData.getTexture(kInputPosW);
    var["gNormW"] = renderData.getTexture(kInputNormW);
    var["gFaceNormalW"] = renderData.getTexture(kInputFaceNormalW);
    var["gViewW"] = renderData.getTexture(kInputViewW);
    var["gDiffuseOpacity"] = renderData.getTexture(kInputDiffuseOpacity);
    var["gSpecRough"] = renderData.getTexture(kInputSpecRough);

    const auto pCamera = mpScene->getCamera();
    FALCOR_ASSERT(pCamera);

    mpPass->addDefine("USE_ENV_MAP", mpScene->getEnvMap() ? "1" : "0");

    var["PerFrameCB"]["gShadowBias"] = mShadowBias;
    var["PerFrameCB"]["gInvViewProj"] = math::inverse(pCamera->getViewProjMatrixNoJitter());
    var["PerFrameCB"]["gViewMode"] = uint32_t(mViewMode);
    var["PerFrameCB"]["gRenderBackground"] = mRenderBackground;
    var["PerFrameCB"]["gAOEnabled"] = mAOEnabled;
    var["PerFrameCB"]["gAOStrength"] = mAOStrength;
    var["PerFrameCB"]["gAORadius"] = mAORadius;
    var["PerFrameCB"]["gAOStepCount"] = mAOStepCount;
    var["PerFrameCB"]["gAODirectionSet"] = mAODirectionSet;
    var["PerFrameCB"]["gAOContactStrength"] = mAOContactStrength;
    var["PerFrameCB"]["gAOUseStableRotation"] = mAOUseStableRotation;

    mpFbo->attachColorTarget(pOutput, 0);
    mpPass->getState()->setFbo(mpFbo);
    mpPass->execute(pRenderContext, mpFbo);
}

void MeshStyleDirectAOPass::renderUI(Gui::Widgets& widget)
{
    widget.dropdown("View", mViewMode);
    widget.var("Shadow bias", mShadowBias, 0.0f, 0.02f, 0.0001f, false, "%.4f");
    widget.checkbox("Render background", mRenderBackground);
    widget.checkbox("AO enabled", mAOEnabled);
    widget.slider("AO strength", mAOStrength, 0.0f, 1.0f);
    widget.var("AO radius", mAORadius, 0.01f, 2.0f, 0.01f);
    widget.var("AO contact strength", mAOContactStrength, 0.0f, 2.0f, 0.01f);
    widget.var("AO step count", mAOStepCount, 1u, 8u, 1u);

    static const Gui::DropdownList kAODirectionSets = {
        {4u, "4 Directions"},
        {6u, "6 Directions"},
    };
    widget.dropdown("AO direction set", kAODirectionSets, mAODirectionSet);
    widget.checkbox("AO stable rotation", mAOUseStableRotation);
}

void MeshStyleDirectAOPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpPass = nullptr;
}
