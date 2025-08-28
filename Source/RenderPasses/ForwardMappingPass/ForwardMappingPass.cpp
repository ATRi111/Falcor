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
const std::string kInputViewpoint = "viewpoint";
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
        reflector.addInput(kInputViewpoint + si, "Viewpoint of Impostor" + si)
            .format(ResourceFormat::Unknown)
            .bindFlags(ResourceBindFlags::Constant)
            .rawBuffer(sizeof(Viewpoint));
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

void ForwardMappingPass::prepareVars(const RenderData& renderData)
{
    float3 currentFront = normalize(mpCamera->getTarget() - mpCamera->getPosition());
    float3 currentUp = mpCamera->getUpVector();
    float3 currentRight = cross(currentFront, currentUp);
    float3x3 currentBasis;
    currentBasis.setCol(0, currentRight);
    currentBasis.setCol(1, currentUp);
    currentBasis.setCol(2, currentFront);

    for (size_t i = 0; i < mImpostorCount; i++)
    {
        ref<Buffer> buffer = renderData.getResource("viewpoint" + std::to_string(i))->asBuffer();
        Viewpoint vp;
        buffer->getBlob(&vp, 0, sizeof(Viewpoint));
        float3 front = normalize(vp.target - vp.position);
        float3 up = normalize(vp.up);
        float3 right = cross(front, up);
        float3x3 originBasis;
        originBasis.setCol(0, right);
        originBasis.setCol(1, up);
        originBasis.setCol(2, front);
        float3x3 rotation = mul(inverse(currentBasis), originBasis); // 基变换矩阵

        float4x4 transform = float4x4(rotation);
        transform.setCol(3, float4(0.f, 0.f, 0.f, 1.f));
        transform = translate(transform, mpCamera->getPosition() - vp.position);
        mTransformMatrixes.push_back(transform);
    }
}

void ForwardMappingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    prepareVars(renderData);
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

    ref<Texture> mappedNDO = renderData.getTexture(kOutputMappedFloats);
    ref<Texture> mappedMCR = renderData.getTexture(kOutputMappedInts);
    ref<Texture> worldNormal = renderData.getTexture(kWorldNormal);

    pRenderContext->clearUAV(mappedNDO->getUAV().get(), float4(0.f, 0.f, 1.f, 0.f)); // 深度初始化为最大值
    pRenderContext->clearUAV(mappedMCR->getUAV().get(), float4());
    pRenderContext->clearUAV(worldNormal->getUAV().get(), float4(0.f, 0.f, 0.f, 1.f));

    for (size_t i = 0; i < mImpostorCount; i++)
    {
        ShaderVar var = mpComputePass->getRootVar();
        var["CB"]["transform"] = mTransformMatrixes[i];
        var["gPackedNDO"] = renderData.getTexture(kInputPackedNDO + std::to_string(i));
        var["gPackedMCR"] = renderData.getTexture(kInputPackedMCR + std::to_string(i));
        var["gMappedNDO"] = mappedNDO;
        var["gMappedMCR"] = mappedMCR;
        var["gWorldNormal"] = worldNormal;

        mpComputePass->execute(pRenderContext, uint3(mappedNDO->getWidth(), mappedNDO->getHeight(), 1));
    }

    pRenderContext->copyResource(renderData.getTexture(kOutputMappedFloats).get(), renderData.getTexture(kInputPackedNDO + "0").get());
    pRenderContext->copyResource(renderData.getTexture(kOutputMappedInts).get(), renderData.getTexture(kInputPackedMCR + "0").get());
}

void ForwardMappingPass::renderUI(Gui::Widgets& widget) {}

void ForwardMappingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpCamera = pScene->getCamera();
}
