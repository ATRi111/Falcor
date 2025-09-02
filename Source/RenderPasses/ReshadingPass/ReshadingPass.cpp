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
    mLoDLevel = 0;
    mForceLoDLevel = -1;

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Point, TextureFilteringMode::Point, TextureFilteringMode::Point)
        .setAddressingMode(TextureAddressingMode::Clamp, TextureAddressingMode::Clamp, TextureAddressingMode::Clamp);
    mpPointSampler = mpDevice->createSampler(samplerDesc);

    mpFullScreenPass = FullScreenPass::create(mpDevice, kShaderFile);
}

RenderPassReflection ReshadingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputFilteredNDO, "Input normal, depth, opacity")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);
    reflector.addInput(kInputFilteredMCR, "Input material id, texCoord, roughness")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);

    reflector.addOutput(kOutputColor, "Output color")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, 1);
    return reflector;
}

void ReshadingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pOutput = renderData.getTexture(kOutputColor);
    pRenderContext->clearRtv(pOutput->getRTV().get(), float4(0, 0, 0, 0));
    if (!mpScene)
        return;

    const auto& pFilteredNDO = renderData.getTexture(kInputFilteredNDO);
    const auto& pFilteredMCR = renderData.getTexture(kInputFilteredMCR);

    if (!mpProgram)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
    }

    float LoDLevel = 0;

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
    if (mForceLoDLevel >= 0)
        mLoDLevel = math::clamp(mForceLoDLevel, 0.f, RiLoDMipCount - 1.0000001f);
    else
        mLoDLevel = CalculateSceneLoDLevel(camera);
    var["CameraCB"]["cameraPosW"] = camera->getPosition();
    var["CameraCB"]["invVP"] = camera->getInvViewProjMatrix();
    int lowerLevel = (int)(math::floor(mLoDLevel));
    var["CameraCB"]["lowerLevel"] = (int)(math::floor(mLoDLevel));
    var["CameraCB"]["t"] = mLoDLevel - lowerLevel;

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutput, 0);
    mpFullScreenPass->execute(pRenderContext, fbo);
}

void ReshadingPass::renderUI(Gui::Widgets& widget)
{
    widget.var("LoDLevel", mLoDLevel);
    widget.var("ForceLoDLevel", mForceLoDLevel);
}

void ReshadingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
}

float ReshadingPass::CalculateSceneLoDLevel(ref<Camera> camera)
{
    AABB aabb = mpScene->getSceneBounds();
    float size = math::length(aabb.maxPoint - aabb.minPoint);
    float distance = math::length(camera->getPosition() - aabb.center());
    float k = distance * camera->getFrameHeight() / camera->getFocalLength() / size;
    float LoDLevel = math::log2(k) - 1;
    return math::clamp(LoDLevel, 0.f, RiLoDMipCount - 1.0000001f);
}
