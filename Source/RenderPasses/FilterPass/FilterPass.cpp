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
#include "FilterPass.h"

namespace
{
const std::string kFilterShaderFile = "E:/Project/Falcor/Source/RenderPasses/FilterPass/Filter.cs.slang";

const std::string kInputMappedNDO = "mappedNDO";
const std::string kInputMappedMCR = "mappedMCR";
const std::string kOutputFilteredNDO = "filteredNDO";
const std::string kOutputFilteredMCR = "filteredMCR";
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, FilterPass>();
}

FilterPass::FilterPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_UNIFORM);
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Point)
        .setAddressingMode(TextureAddressingMode::Border, TextureAddressingMode::Border, TextureAddressingMode::Border)
        .setBorderColor(float4());

    mpSampler = mpDevice->createSampler(samplerDesc);
}

RenderPassReflection FilterPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputMappedNDO, "Input normal, depth, opacity")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);
    reflector.addInput(kInputMappedMCR, "Input material id, texCoord, roughness")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);

    reflector.addOutput(kOutputFilteredNDO, "Output normal, depth, opacity")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);
    reflector.addOutput(kOutputFilteredMCR, "Output material id, texCoord, roughness")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);
    return reflector;
}

void FilterPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;
    if (!mpComputePass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kFilterShaderFile).csEntry("main");

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());
        mpComputePass = ComputePass::create(mpDevice, desc, defines, true);
    }

    ref<Texture> mappedNDO = renderData.getTexture(kInputMappedNDO);
    ref<Texture> mappedMCR = renderData.getTexture(kInputMappedMCR);
    ref<Texture> filteredNDO = renderData.getTexture(kOutputFilteredNDO);
    ref<Texture> filteredMCR = renderData.getTexture(kOutputFilteredMCR);

    pRenderContext->copyResource(filteredNDO.get(), mappedNDO.get());
    pRenderContext->copyResource(filteredMCR.get(), mappedMCR.get());
    return;

    blockCount = uint2(mappedNDO->getWidth() / blockSize, mappedNDO->getHeight() / blockSize); // 简单地认为能整除
    auto var = mpComputePass->getRootVar();
    var["gMappedNDO"] = mappedNDO;
    var["gMappedMCR"] = mappedMCR;
    var["gFilteredNDO"] = filteredNDO;
    var["gFilteredMCR"] = filteredMCR;
    var["gSampler"] = mpSampler;
    var["CB"]["blockSize"] = blockSize;
    mpComputePass->execute(pRenderContext, uint3(blockCount, 1));
}

void FilterPass::renderUI(Gui::Widgets& widget) {}

void FilterPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
}
