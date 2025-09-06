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
#include "ReshadingPass.h"

namespace
{
const std::string kInputFilteredNDO = "filteredNDO";
const std::string kInputFilteredMCR = "filteredMCR";
const std::string kOutputColor = "color";
const std::string kOutputPosW = "posW";
const std::string kOutputGBufferUV = "GBufferUV";
const std::string kInputMatrix = "matrix";
const std::string kShaderFile = "E:/Project/Falcor/Source/RenderPasses/ReshadingPass/Reshading.ps.slang";
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, ReshadingPass>();
}

ref<ReshadingPass> ReshadingPass::create(ref<Device> pDevice, const Properties& props)
{
    return make_ref<ReshadingPass>(pDevice, props);
}

ReshadingPass::ReshadingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mpDevice = pDevice;
    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_UNIFORM);
    mCurrentLoDLevel = 0;
    mLoDLevel = 0;
    mLoDLevelFixed = false;
    mUpdateScene = false;
    mDebug = false;

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Point, TextureFilteringMode::Point, TextureFilteringMode::Point)
        .setAddressingMode(TextureAddressingMode::Border, TextureAddressingMode::Border, TextureAddressingMode::Border)
        .setBorderColor(float4());
    mpPointSampler = mpDevice->createSampler(samplerDesc);
}

RenderPassReflection ReshadingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputFilteredNDO, "Input normal, depth, opacity")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, RiLoDMipCount);
    reflector.addInput(kInputFilteredMCR, "Input material id, texCoord, roughness")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, RiLoDMipCount);

    reflector.addInput(kInputMatrix, "invVP of G-Buffer & Camera Matrix transform Screen-space TexCoord to GBuffer TexCoord")
        .format(ResourceFormat::Unknown)
        .bindFlags(ResourceBindFlags::Constant)
        .rawBuffer(sizeof(float4x4) + sizeof(float3x3));

    reflector.addOutput(kOutputColor, "Output color")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, 1);
    reflector.addOutput(kOutputPosW, "Output world position")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, 1);
    reflector.addOutput(kOutputGBufferUV, "Output G-Buffer UV")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RG32Float)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, 1);
    return reflector;
}

void ReshadingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (mUpdateScene)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        mpFullScreenPass = FullScreenPass::create(mpDevice, desc, mpScene->getSceneDefines());
        mUpdateScene = false;
    }

    const auto& pOutputColor = renderData.getTexture(kOutputColor);
    const auto& pOutputPosW = renderData.getTexture(kOutputPosW);
    const auto& pOutputGBufferUV = renderData.getTexture(kOutputGBufferUV);
    const auto& pFilteredNDO = renderData.getTexture(kInputFilteredNDO);
    const auto& pFilteredMCR = renderData.getTexture(kInputFilteredMCR);

    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0, 0, 0, 0));
    pRenderContext->clearRtv(pOutputPosW->getRTV().get(), float4(0, 0, 0, 0));
    pRenderContext->clearRtv(pOutputGBufferUV->getRTV().get(), float4(0, 0, 0, 0));

    ref<Buffer> buffer = renderData.getResource(kInputMatrix)->asBuffer();
    float3x3 homographMatrix;
    float4x4 invGBufferVP;
    buffer->getBlob(&invGBufferVP, 0, sizeof(float4x4));
    buffer->getBlob(&homographMatrix, sizeof(float4x4), sizeof(float3x3));
    mpFullScreenPass->addDefine("DEBUG", mDebug ? "1" : "0");

    // Bind resources to the full-screen pass
    auto var = mpFullScreenPass->getRootVar();
    var["gFilteredNDO"] = pFilteredNDO;
    var["gFilteredMCR"] = pFilteredMCR;
    var["gPointSampler"] = mpPointSampler;

    const auto& lights = mpScene->getLights();
    for (size_t i = 0; i < lights.size(); i++)
    {
        if (lights[i]->getType() == LightType::Directional)
        {
            var["DirectionalLightCB"]["lightPosW"] = lights[i]->getData().posW;
            var["DirectionalLightCB"]["lightDirW"] = lights[i]->getData().dirW;
            var["DirectionalLightCB"]["lightColor"] = lights[i]->getData().intensity;
            break;
        }
    }

    ref<Camera> camera = mpScene->getCamera();
    if (mLoDLevelFixed)
        mCurrentLoDLevel = math::clamp(mLoDLevel, 0.f, RiLoDMipCount - 1.0000001f);
    else
        mCurrentLoDLevel = CalculateLoDLevel(homographMatrix.getRow(0).x);
    float4x4 extendMatrix = float4x4(homographMatrix);
    var["CB"]["cameraPosW"] = camera->getPosition();
    var["CB"]["invVP"] = invGBufferVP;
    var["CB"]["extendMatrix"] = extendMatrix;
    int lowerLevel = (int)(math::floor(mCurrentLoDLevel));
    var["CB"]["lowerLevel"] = (int)(math::floor(mCurrentLoDLevel));
    var["CB"]["t"] = mCurrentLoDLevel - lowerLevel;

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutputColor, 0);
    fbo->attachColorTarget(pOutputPosW, 1);
    fbo->attachColorTarget(pOutputGBufferUV, 2);
    mpFullScreenPass->execute(pRenderContext, fbo);
}

void ReshadingPass::renderUI(Gui::Widgets& widget)
{
    widget.var("CurrentLoDLevel", mCurrentLoDLevel);
    widget.checkbox("FixedLoDLevel", mLoDLevelFixed);
    widget.var("LoDLevel", mLoDLevel);
    widget.checkbox("Debug", mDebug);
}

void ReshadingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mUpdateScene = true;
}
// sacleRate指一个像素边长对应到G-Buffer中的纹素边长
float ReshadingPass::CalculateLoDLevel(float scaleRate)
{
    float LoDLevel = math::log2(scaleRate);
    return math::clamp(LoDLevel, 0.f, RiLoDMipCount - 1.0000001f);
}
