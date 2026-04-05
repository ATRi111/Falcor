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
#include "HybridBlendMaskPass.h"

namespace
{
const char kShaderFile[] = "RenderPasses/HybridVoxelMesh/HybridBlendMaskPass.ps.slang";

const char kBlendStartDistance[] = "blendStartDistance";
const char kBlendEndDistance[] = "blendEndDistance";
const char kBlendExponent[] = "blendExponent";

const char kInputPosW[] = "posW";
const char kInputVBuffer[] = "vbuffer";
const char kOutputMask[] = "mask";
} // namespace

HybridBlendMaskPass::HybridBlendMaskPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("HybridBlendMaskPass requires Shader Model 6.5 support.");

    for (const auto& [key, value] : props)
    {
        if (key == kBlendStartDistance)
            setBlendStartDistance(value);
        else if (key == kBlendEndDistance)
            setBlendEndDistance(value);
        else if (key == kBlendExponent)
            setBlendExponent(value);
        else
            logWarning("Unknown property '{}' in a HybridBlendMaskPass properties.", key);
    }

    mpFbo = Fbo::create(mpDevice);
}

Properties HybridBlendMaskPass::getProperties() const
{
    Properties props;
    props[kBlendStartDistance] = mBlendStartDistance;
    props[kBlendEndDistance] = mBlendEndDistance;
    props[kBlendExponent] = mBlendExponent;
    return props;
}

RenderPassReflection HybridBlendMaskPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputPosW, "Mesh world position").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVBuffer, "Mesh visibility buffer").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addOutput(kOutputMask, "Mesh weight mask").bindFlags(ResourceBindFlags::RenderTarget).format(ResourceFormat::RGBA32Float);
    return reflector;
}

void HybridBlendMaskPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto pOutput = renderData.getTexture(kOutputMask);
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

    const auto pCamera = mpScene->getCamera();
    FALCOR_ASSERT(pCamera);

    auto var = mpPass->getRootVar();
    mpScene->bindShaderDataForRaytracing(pRenderContext, var["gScene"]);
    var["gPosW"] = renderData.getTexture(kInputPosW);
    var["gVBuffer"] = renderData.getTexture(kInputVBuffer);
    var["PerFrameCB"]["gCameraPosW"] = pCamera->getPosition();
    var["PerFrameCB"]["gBlendStartDistance"] = mBlendStartDistance;
    var["PerFrameCB"]["gBlendEndDistance"] = mBlendEndDistance;
    var["PerFrameCB"]["gBlendExponent"] = mBlendExponent;

    mpFbo->attachColorTarget(pOutput, 0);
    mpPass->getState()->setFbo(mpFbo);
    mpPass->execute(pRenderContext, mpFbo);
}

void HybridBlendMaskPass::renderUI(Gui::Widgets& widget)
{
    widget.var("Blend start", mBlendStartDistance, 0.0f, 32.0f, 0.01f);
    widget.var("Blend end", mBlendEndDistance, 0.0f, 64.0f, 0.01f);
    widget.var("Blend exponent", mBlendExponent, 0.1f, 8.0f, 0.05f);
}

void HybridBlendMaskPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpPass = nullptr;
}
