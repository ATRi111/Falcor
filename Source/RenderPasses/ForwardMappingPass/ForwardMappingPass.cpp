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
#include "ForwardMappingPass.h"

namespace
{
const std::string kComputePassProgramFile = "E:/Project/Falcor/Source/RenderPasses/ForwardMappingPass/ForwardMapping.cs.slang";
const std::string kInputMatrix = "invVP";
const std::string kInputPackedNDO = "packedNDO";
const std::string kInputPackedMCR = "packedMCR";
const std::string kImpostorCount = "impostorCount";
const std::string kOutputMappedFloats = "mappedNDO";
const std::string kOutputMappedInts = "mappedMCR";
const std::string kWorldNormal = "worldNormal";
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, ForwardMappingPass>();
}

ForwardMappingPass::ForwardMappingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mImpostorCount = 1;
    for (const auto& [key, value] : props)
    {
        if (key == kImpostorCount)
            mImpostorCount = value;
    }
    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
}

RenderPassReflection ForwardMappingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    for (size_t i = 0; i < mImpostorCount; i++)
    {
        std::string si = std::to_string(i);
        reflector.addInput(kInputPackedNDO + si, "Packed NDO data from Impostor" + si)
            .format(ResourceFormat::RGBA32Float)
            .bindFlags(ResourceBindFlags::ShaderResource);
        reflector.addInput(kInputPackedMCR + si, "Packed MCR data from Impostor" + si)
            .format(ResourceFormat::RGBA32Float)
            .bindFlags(ResourceBindFlags::ShaderResource);
        reflector.addInput(kInputMatrix + si, "Inverse viewProjectMatrix of Impostor" + si)
            .format(ResourceFormat::Unknown)
            .bindFlags(ResourceBindFlags::Constant)
            .rawBuffer(sizeof(float4x4));
    }

    reflector.addOutput(kOutputMappedFloats, "Mapped NDO data")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);
    reflector.addOutput(kOutputMappedInts, "Mapped MCR data")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);
    reflector.addOutput(kWorldNormal, "World space normal")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);
    return reflector;
}

void ForwardMappingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (!mpComputePass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kComputePassProgramFile).csEntry("main");
        // desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());
        // defines.add(getShaderDefines(renderData));

        mpComputePass = ComputePass::create(mpDevice, desc, defines, true);
    }

    mpCamera->setFocalLength(21.f);
    mpCamera->setFrameHeight(24.f);
    ref<Texture> mappedNDO = renderData.getTexture(kOutputMappedFloats);
    ref<Texture> mappedMCR = renderData.getTexture(kOutputMappedInts);
    ref<Texture> worldNormal = renderData.getTexture(kWorldNormal);

    pRenderContext->clearUAV(mappedNDO->getUAV().get(), float4());
    pRenderContext->clearUAV(mappedMCR->getUAV().get(), float4());
    pRenderContext->clearUAV(worldNormal->getUAV().get(), float4());

    ShaderVar var = mpComputePass->getRootVar();
    var["CB"]["width"] = mappedNDO->getWidth();
    var["CB"]["height"] = mappedNDO->getHeight();
    var["CB"]["VP"] = mpCamera->getViewProjMatrix();
    var["gMappedNDO"] = mappedNDO;
    var["gMappedMCR"] = mappedMCR;
    var["gWorldNormal"] = worldNormal;
    for (size_t i = 0; i < mImpostorCount; i++)
    {
        ref<Buffer> buffer = renderData.getResource(kInputMatrix + std::to_string(i))->asBuffer();
        float4x4 invVP;
        buffer->getBlob(&invVP, 0, sizeof(float4x4));

        var["CB"]["invOriginVP"] = invVP;
        var["gPackedNDO"] = renderData.getTexture(kInputPackedNDO + std::to_string(i));
        var["gPackedMCR"] = renderData.getTexture(kInputPackedMCR + std::to_string(i));

        mpComputePass->execute(pRenderContext, uint3(mappedNDO->getWidth(), mappedNDO->getHeight(), 1));
        pRenderContext->uavBarrier(mappedNDO.get());
    }
}

void ForwardMappingPass::renderUI(Gui::Widgets& widget) {}

void ForwardMappingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpCamera = pScene->getCamera();
    mpScene->selectViewpoint(0);
}
