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
#include "HybridMeshDebugPass.h"
#include "HybridBlendMaskPass.h"
#include "HybridCompositePass.h"
#include "MeshStyleDirectAOPass.h"

namespace
{
const char kShaderFile[] = "RenderPasses/HybridVoxelMesh/HybridMeshDebugPass.ps.slang";

const char kViewMode[] = "viewMode";
const char kDepthRange[] = "depthRange";
const char kRenderBackground[] = "renderBackground";

const char kInputPosW[] = "posW";
const char kInputNormW[] = "normW";
const char kInputFaceNormalW[] = "faceNormalW";
const char kInputViewW[] = "viewW";
const char kInputDiffuseOpacity[] = "diffuseOpacity";
const char kInputSpecRough[] = "specRough";
const char kInputEmissive[] = "emissive";
const char kInputVBuffer[] = "vbuffer";
const char kOutputColor[] = "color";

void registerBindings(pybind11::module& m)
{
    pybind11::class_<HybridMeshDebugPass, RenderPass, ref<HybridMeshDebugPass>> pass(m, "HybridMeshDebugPass");
    pass.def_property(
        kViewMode,
        [](const HybridMeshDebugPass& self) { return enumToString(self.getViewMode()); },
        [](HybridMeshDebugPass& self, const std::string& value) { self.setViewMode(stringToEnum<HybridMeshDebugPass::ViewMode>(value)); }
    );
    pass.def_property(kDepthRange, &HybridMeshDebugPass::getDepthRange, &HybridMeshDebugPass::setDepthRange);
    pass.def_property(kRenderBackground, &HybridMeshDebugPass::getRenderBackground, &HybridMeshDebugPass::setRenderBackground);
}
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, HybridMeshDebugPass>();
    registry.registerClass<RenderPass, HybridBlendMaskPass>();
    registry.registerClass<RenderPass, HybridCompositePass>();
    registry.registerClass<RenderPass, MeshStyleDirectAOPass>();
    ScriptBindings::registerBinding(registerBindings);
}

HybridMeshDebugPass::HybridMeshDebugPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("HybridMeshDebugPass requires Shader Model 6.5 support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::RaytracingTier1_1))
        FALCOR_THROW("HybridMeshDebugPass requires Raytracing Tier 1.1 support.");

    for (const auto& [key, value] : props)
    {
        if (key == kViewMode)
            mViewMode = value.operator ViewMode();
        else if (key == kDepthRange)
            setDepthRange(value);
        else if (key == kRenderBackground)
            mRenderBackground = value;
        else
            logWarning("Unknown property '{}' in a HybridMeshDebugPass properties.", key);
    }

    mpFbo = Fbo::create(mpDevice);
}

Properties HybridMeshDebugPass::getProperties() const
{
    Properties props;
    props[kViewMode] = mViewMode;
    props[kDepthRange] = mDepthRange;
    props[kRenderBackground] = mRenderBackground;
    return props;
}

RenderPassReflection HybridMeshDebugPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputPosW, "Mesh world position").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputNormW, "Mesh world normal").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputFaceNormalW, "Mesh world face normal").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputViewW, "Mesh world view direction").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputDiffuseOpacity, "Mesh diffuse albedo and opacity").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputSpecRough, "Mesh specular and roughness").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputEmissive, "Mesh emissive").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVBuffer, "Mesh visibility buffer").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addOutput(kOutputColor, "Mesh debug color").bindFlags(ResourceBindFlags::RenderTarget).format(ResourceFormat::RGBA32Float);
    return reflector;
}

void HybridMeshDebugPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
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
    var["gEmissive"] = renderData.getTexture(kInputEmissive);
    var["gVBuffer"] = renderData.getTexture(kInputVBuffer);

    const auto pCamera = mpScene->getCamera();
    FALCOR_ASSERT(pCamera);

    mpPass->addDefine("USE_ENV_MAP", mpScene->getEnvMap() ? "1" : "0");

    var["PerFrameCB"]["gCameraPosW"] = pCamera->getPosition();
    var["PerFrameCB"]["gDepthRange"] = mDepthRange;
    var["PerFrameCB"]["gKeyLightDirW"] = mKeyLightDirW;
    var["PerFrameCB"]["gInvViewProj"] = math::inverse(pCamera->getViewProjMatrixNoJitter());
    var["PerFrameCB"]["gViewMode"] = uint32_t(mViewMode);
    var["PerFrameCB"]["gRenderBackground"] = mRenderBackground;

    mpFbo->attachColorTarget(pOutput, 0);
    mpPass->getState()->setFbo(mpFbo);
    mpPass->execute(pRenderContext, mpFbo);
}

void HybridMeshDebugPass::renderUI(Gui::Widgets& widget)
{
    widget.dropdown("View", mViewMode);
    widget.var("Depth range", mDepthRange, 0.1f, 100.f, 0.1f);
    widget.tooltip("World-space camera distance remap used by the Depth view.", true);
    widget.checkbox("Render background", mRenderBackground);
}

void HybridMeshDebugPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpPass = nullptr;
}
