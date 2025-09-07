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
const std::string kInputInvVP = "impostorInvVP";
const std::string kInputPackedNDO = "packedNDO";
const std::string kInputPackedMCR = "packedMCR";
const std::string kImpostorCount = "impostorCount";
const std::string kOutputMappedNDO = "mappedNDO";
const std::string kOutputMappedMCR = "mappedMCR";
const std::string kOutputMatrix = "matrix";
const std::string kOutputPosW = "posW";
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

    reflector.addOutput(kOutputPosW, "World position")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(RiLoDOutputWidth, RiLoDOutputHeight, 1, 1);

    reflector.addOutput(kOutputMatrix, "invVP of G-Buffer Camera & Matrix transform Screen-space TexCoord to GBuffer TexCoord")
        .format(ResourceFormat::Unknown)
        .bindFlags(ResourceBindFlags::Constant)
        .rawBuffer(sizeof(float3x3) + sizeof(float4x4));

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
    mpCamera->setAspectRatio(RiLoDOutputWidth / (float)RiLoDOutputHeight);

    // 重建G-Buffer
    {
        ref<Texture> mappedNDO = renderData.getTexture(kOutputMappedNDO);
        ref<Texture> mappedMCR = renderData.getTexture(kOutputMappedMCR);
        ref<Texture> pPosW = renderData.getTexture(kOutputPosW);
        ref<Buffer> matrixBuffer = renderData.getResource(kOutputMatrix)->asBuffer();

        for (size_t mipLevel = 0; mipLevel < RiLoDMipCount; mipLevel++)
        {
            pRenderContext->clearUAV(mappedNDO->getUAV(mipLevel, 0, 1).get(), float4());
            pRenderContext->clearUAV(mappedMCR->getUAV(mipLevel, 0, 1).get(), float4());
        }
        pRenderContext->clearUAV(pPosW->getUAV().get(), float4());

        mpComputePass->addDefine("ENABLE_SUPERSAMPLING", mEnableSuperSampling ? "1" : "0");
        ShaderVar var = mpComputePass->getRootVar();
        float3x3 homographMatrix;
        float4x4 GBufferVP = CalculateProperViewProjMatrix(homographMatrix);
        float4x4 invGBufferVP = math::inverse(GBufferVP);
        matrixBuffer->setBlob(&invGBufferVP, 0, sizeof(float4x4));
        matrixBuffer->setBlob(&homographMatrix, sizeof(float4x4), sizeof(float3x3));

        var["CB"]["GBufferVP"] = GBufferVP;
        for (size_t i = 0; i < mImpostorCount; i++)
        {
            ref<Buffer> buffer = renderData.getResource(kInputInvVP + std::to_string(i))->asBuffer();
            float4x4 invVP;
            buffer->getBlob(&invVP, 0, sizeof(float4x4));
            ref<Texture> packedNDO = renderData.getTexture(kInputPackedNDO + std::to_string(i));
            ref<Texture> packedMCR = renderData.getTexture(kInputPackedMCR + std::to_string(i));

            var["CB"]["invOriginVP"] = invVP;
            var["gPosW"] = pPosW;
            for (size_t mipLevel = 0; mipLevel < RiLoDMipCount; mipLevel++)
            {
                mpComputePass->addDefine("WRITE_POSW", (mipLevel == 0) ? "1" : "0");
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
            pRenderContext->uavBarrier(mappedMCR.get());
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
    float cameraDistance = 2.f * maxDistance;
    float3 cameraPosition = aabb.center() - cameraDistance * front;
    float3 posW1 = aabb.center();
    float3 posW2 = posW1 + mpCamera->getUpVector();
    posW2 = posW2 - math::dot(posW2, front) * front; // 在任意正对相机的平面内选取两个参考点

    float4x4 GBufferVP = CalculateVP(cameraPosition, 4.f * maxDistance);
    // 计算相机移动导致视口坐标变化对应的单应性矩阵
    float scaleRate =
        CalculateHomographMatrix(mpCamera->getViewProjMatrixNoJitter(), GBufferVP, float4(posW1, 1), float4(posW2, 1), homographMatrix);

    if (scaleRate < 0.5f)
    {
        GBufferVP = mpCamera->getViewProjMatrixNoJitter();
        homographMatrix = float3x3::identity(); // 当前相机离场景过近时，重建时直接使用当前相机
    }
    else if (scaleRate < 1.0f)
    {
        cameraPosition = math::lerp(mpCamera->getPosition(), cameraPosition, 2.f * (scaleRate - 0.5f)); // 平滑过渡，避免相机抖动
        GBufferVP = CalculateVP(cameraPosition, 4.f * maxDistance);
        CalculateHomographMatrix(mpCamera->getViewProjMatrixNoJitter(), GBufferVP, float4(posW1, 1), float4(posW2, 1), homographMatrix);
    }
    return GBufferVP;
}

float2 ForwardMappingPass::WorldToTexCoord(float4 world, float4x4 VP)
{
    float4 clip = math::mul(VP, world);
    float4 NDC = clip / clip.w;
    float2 texCoord = float2(0.5f * NDC.x + 0.5f, 0.5f - 0.5f * NDC.y);
    return texCoord;
}

float ForwardMappingPass::CalculateHomographMatrix(
    float4x4 originVP,
    float4x4 targetVP,
    float4 point0,
    float4 point1,
    float3x3& homographMatrix
)
{
    float2 originTexCoord0 = WorldToTexCoord(point0, originVP);
    float2 originTexCoord1 = WorldToTexCoord(point1, originVP);
    float2 targetTexCoord0 = WorldToTexCoord(point0, targetVP);
    float2 targetTexCoord1 = WorldToTexCoord(point1, targetVP);

    float2 originMid = 0.5f * (originTexCoord0 + originTexCoord1);
    float2 targetMid = 0.5f * (targetTexCoord0 + targetTexCoord1);
    float3 origin = float3(originTexCoord1 - originTexCoord0, 0);
    float3 target = float3(targetTexCoord1 - targetTexCoord0, 0);
    // float scaleRate = math::dot(target, origin) / math::dot(origin, origin);
    float scaleRate = math::length(target) / math::length(origin);

    homographMatrix = float3x3::identity();
    float3x3 transform = float3x3::identity();
    transform.setCol(2, float3(-originMid.x, -originMid.y, 1));
    homographMatrix = math::mul(transform, homographMatrix); // 平移到原点
    float3x3 scale = float3x3::identity();
    scale.setRow(0, float3(scaleRate, 0, 0));
    scale.setRow(1, float3(0, scaleRate, 0));
    homographMatrix = math::mul(scale, homographMatrix); // 缩放
    transform = float3x3::identity();
    transform.setCol(2, float3(targetMid.x, targetMid.y, 1));
    homographMatrix = math::mul(transform, homographMatrix);
    return scaleRate;
}

float4x4 ForwardMappingPass::CalculateVP(float3 cameraPosition, float far)
{
    float3 front = math::normalize(mpCamera->getTarget() - mpCamera->getPosition());
    float fovY = 2.f * std::atan(0.5f * mpCamera->getFrameHeight() / mpCamera->getFocalLength());
    float4x4 viewMat =
        math::matrixFromLookAt(cameraPosition, cameraPosition + front, mpCamera->getUpVector(), math::Handedness::RightHanded);
    float4x4 projMat = math::perspective(fovY, RiLoDOutputWidth / (float)RiLoDOutputHeight, 0.1f, far);
    return mul(projMat, viewMat);
}
