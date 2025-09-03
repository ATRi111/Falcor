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
const std::string kDepthPassProgramFile = "E:/Project/Falcor/Source/RenderPasses/ForwardMappingPass/ForwardDepth.cs.slang";
const std::string kInputInvVP = "impostorInvVP";
const std::string kInputPackedNDO = "packedNDO";
const std::string kInputPackedMCR = "packedMCR";
const std::string kImpostorCount = "impostorCount";
const std::string kOutputMappedNDO = "mappedNDO";
const std::string kOutputMappedMCR = "mappedMCR";
const std::string kOutputMatrix = "matrix";
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, ForwardMappingPass>();
}

ForwardMappingPass::ForwardMappingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mImpostorCount = 1;
    mEnableSuperSampling = true;

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
            .bindFlags(ResourceBindFlags::ShaderResource)
            .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);
        reflector.addInput(kInputPackedMCR + si, "Packed MCR data from Impostor" + si)
            .format(ResourceFormat::RGBA32Float)
            .bindFlags(ResourceBindFlags::ShaderResource)
            .texture2D(RiLoDWidth, RiLoDHeight, 1, RiLoDMipCount);
        reflector.addInput(kInputInvVP + si, "Inverse viewProjectMatrix of Impostor" + si)
            .format(ResourceFormat::Unknown)
            .bindFlags(ResourceBindFlags::Constant)
            .rawBuffer(sizeof(float4x4));
    }

    reflector.addOutput(kOutputMappedNDO, "Mapped NDO data")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, RiLoDMipCount);
    reflector.addOutput(kOutputMappedMCR, "Mapped MCR data")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, RiLoDMipCount);

    reflector.addOutput(kOutputMatrix, "Screen-space TexCoord to GBuffer TexCoord")
        .format(ResourceFormat::Unknown)
        .bindFlags(ResourceBindFlags::Constant)
        .rawBuffer(sizeof(float3x3));

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
    if (!mpDepthPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kDepthPassProgramFile).csEntry("main");
        // desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());
        // defines.add(getShaderDefines(renderData));

        mpDepthPass = ComputePass::create(mpDevice, desc, defines, true);
    }
    mpCamera->setFocalLength(21.f);
    mpCamera->setFrameHeight(24.f);
    mpCamera->setAspectRatio(RiLoDOutputWidth / (float)RiLoDOutputHeight);

    // 重建G-Buffer
    {
        ref<Texture> mappedNDO = renderData.getTexture(kOutputMappedNDO);
        ref<Texture> mappedMCR = renderData.getTexture(kOutputMappedMCR);
        ref<Buffer> matrixBuffer = renderData.getResource(kOutputMatrix)->asBuffer();

        for (size_t mipLevel = 0; mipLevel < RiLoDMipCount; mipLevel++)
        {
            pRenderContext->clearUAV(mappedNDO->getUAV(mipLevel, 0, 1).get(), float4());
            pRenderContext->clearUAV(mappedMCR->getUAV(mipLevel, 0, 1).get(), float4());
        }
        mpComputePass->addDefine("ENABLE_SUPERSAMPLING", mEnableSuperSampling ? "1" : "0", true);
        ShaderVar var = mpComputePass->getRootVar();
        float3x3 homographMatrix;
        float4x4 GBufferVP = CalculateProperViewProjMatrix(homographMatrix);
        matrixBuffer->setBlob(&homographMatrix, 0, sizeof(float3x3));
        var["CB"]["GBufferVP"] = GBufferVP;

        for (size_t i = 0; i < mImpostorCount; i++)
        {
            ref<Buffer> buffer = renderData.getResource(kInputInvVP + std::to_string(i))->asBuffer();
            float4x4 invVP;
            buffer->getBlob(&invVP, 0, sizeof(float4x4));
            ref<Texture> packedNDO = renderData.getTexture(kInputPackedNDO + std::to_string(i));
            ref<Texture> packedMCR = renderData.getTexture(kInputPackedMCR + std::to_string(i));

            var["CB"]["invOriginVP"] = invVP;
            for (size_t mipLevel = 0; mipLevel < RiLoDMipCount; mipLevel++)
            {
                int width = packedNDO->getWidth() >> mipLevel;
                int height = packedNDO->getHeight() >> mipLevel;
                var["gPackedNDO"].setSrv(packedNDO->getSRV(mipLevel, 1, 0, 1));
                var["gPackedMCR"].setSrv(packedMCR->getSRV(mipLevel, 1, 0, 1));
                var["gMappedNDO"].setUav(mappedNDO->getUAV(mipLevel, 0, 1));
                var["gMappedMCR"].setUav(mappedMCR->getUAV(mipLevel, 0, 1));
                var["CB"]["width"] = width;
                var["CB"]["height"] = height;
                var["CB"]["outputWidth"] = RiLoDOutputWidth >> mipLevel;
                var["CB"]["outputHeight"] = RiLoDOutputHeight >> mipLevel;
                mpComputePass->execute(pRenderContext, uint3(width, height, 1));
            }
            pRenderContext->uavBarrier(mappedNDO.get()); // 不同层级可以并行重建，不同方向不可
        }
    }
}

void ForwardMappingPass::renderUI(Gui::Widgets& widget)
{
    widget.checkbox("EnableSuperSampling", mEnableSuperSampling);
}

void ForwardMappingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpCamera = pScene->getCamera();
}

float4x4 ForwardMappingPass::CalculateProperViewProjMatrix(float3x3& homographMatrix)
{
    // 计算合适的相机位置,及VP矩阵
    AABB aabb = mpScene->getSceneBounds();
    float3 front = math::normalize(mpCamera->getTarget() - mpCamera->getPosition());
    float3 points[8] = {};
    float xMin = aabb.minPoint.x;
    float yMin = aabb.minPoint.y;
    float zMin = aabb.minPoint.z;
    float xMax = aabb.maxPoint.x;
    float yMax = aabb.maxPoint.y;
    float zMax = aabb.maxPoint.z;
    points[0] = float3(xMin, yMin, zMin);
    points[1] = float3(xMin, yMin, zMax);
    points[2] = float3(xMin, yMax, zMin);
    points[3] = float3(xMin, yMax, zMax);
    points[4] = float3(xMax, yMin, zMin);
    points[5] = float3(xMax, yMin, zMax);
    points[6] = float3(xMax, yMax, zMin);
    points[7] = float3(xMax, yMax, zMax);
    float maxDistance = 0;
    for (size_t i = 0; i < 8; i++)
    {
        float3 v = points[i] - aabb.center();
        float3 projection = v - math::dot(v, front) * front;
        maxDistance = std::max(maxDistance, math::length(projection));
    }
    maxDistance *= 1.01f;
    float fovY = 2.0f * std::atan(0.5f * mpCamera->getFrameHeight() / mpCamera->getFocalLength());

    float4x4 viewMat = math::matrixFromLookAt(
        aabb.center() - 2.f * maxDistance * front, aabb.center(), mpCamera->getUpVector(), math::Handedness::RightHanded
    );
    float4x4 projMat = math::perspective(fovY, mpCamera->getAspectRatio(), mpCamera->getNearPlane(), 4.f * maxDistance);
    float4x4 VP = mul(projMat, viewMat);
    // 计算相机移动导致视口坐标变化对应的单应性矩阵
    float3 posW1 = aabb.center();
    float3 posW2 = posW1 + mpCamera->getUpVector();
    posW2 = posW2 - math::dot(posW2, front) * front; // 在任意正对相机的平面内选取两个参考点
    float2 screenTexCoord1 = WorldToTexCoord(float4(posW1, 1), mpCamera->getViewProjMatrixNoJitter());
    float2 screenTexCoord2 = WorldToTexCoord(float4(posW2, 1), mpCamera->getViewProjMatrixNoJitter());
    float2 GBufferTexCoord1 = WorldToTexCoord(float4(posW1, 1), VP);
    float2 GBufferTexCoord2 = WorldToTexCoord(float4(posW2, 1), VP);

    float2 screenMid = 0.5f * (screenTexCoord1 + screenTexCoord2);
    float2 GBufferMid = 0.5f * (GBufferTexCoord1 + GBufferTexCoord2);
    float scaleRate = math::length(GBufferTexCoord2 - GBufferTexCoord1) / math::length(screenTexCoord2 - screenTexCoord1);

    homographMatrix = float3x3::identity();
    float3x3 transform = float3x3::identity();
    transform.setCol(2, float3(-screenMid.x, -screenMid.y, 1));
    homographMatrix = math::mul(transform, homographMatrix); // 平移到原点
    float3x3 scale = float3x3::identity();
    scale.setRow(0, float3(scaleRate, 0, 0));
    scale.setRow(1, float3(0, scaleRate, 0));
    homographMatrix = math::mul(scale, homographMatrix); // 缩放
    transform.setCol(2, float3(GBufferMid.x, GBufferMid.y, 1));
    homographMatrix = math::mul(transform, homographMatrix);
    return VP;
}

float2 ForwardMappingPass::WorldToTexCoord(float4 world, float4x4 VP)
{
    float4 clip = math::mul(VP, world);
    float4 NDC = clip / clip.w;
    float4 texCoord = NDC * 0.5f + 0.5f;
    return float2(texCoord.x, texCoord.y);
}
