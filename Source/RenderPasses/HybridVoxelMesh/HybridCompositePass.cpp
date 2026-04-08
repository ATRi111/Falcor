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
#include "HybridCompositePass.h"

namespace
{
const char kShaderFile[] = "RenderPasses/HybridVoxelMesh/HybridCompositePass.ps.slang";

const char kViewMode[] = "viewMode";

const char kInputMeshColor[] = "meshColor";
const char kInputMeshPosW[] = "meshPosW";
const char kInputVoxelColor[] = "voxelColor";
const char kInputVBuffer[] = "vbuffer";
const char kInputVoxelDepth[] = "voxelDepth";
const char kInputVoxelNormal[] = "voxelNormal";
const char kInputVoxelConfidence[] = "voxelConfidence";
const char kInputVoxelInstanceID[] = "voxelInstanceID";
const char kOutputColor[] = "color";
const char kHybridRequireFullMeshSource[] = "HybridMeshVoxel.requireFullMeshSource";
const char kHybridRequireFullVoxelSource[] = "HybridMeshVoxel.requireFullVoxelSource";

bool requiresFullMeshSource(HybridCompositePass::ViewMode viewMode)
{
    switch (viewMode)
    {
    case HybridCompositePass::ViewMode::MeshOnly:
    case HybridCompositePass::ViewMode::RouteDebug:
    case HybridCompositePass::ViewMode::ObjectMismatch:
    case HybridCompositePass::ViewMode::DepthMismatch:
        return true;
    default:
        return false;
    }
}

bool requiresFullVoxelSource(HybridCompositePass::ViewMode viewMode)
{
    switch (viewMode)
    {
    case HybridCompositePass::ViewMode::VoxelOnly:
    case HybridCompositePass::ViewMode::VoxelDepth:
    case HybridCompositePass::ViewMode::VoxelNormal:
    case HybridCompositePass::ViewMode::VoxelConfidence:
    case HybridCompositePass::ViewMode::VoxelRouteID:
    case HybridCompositePass::ViewMode::VoxelInstanceID:
    case HybridCompositePass::ViewMode::ObjectMismatch:
    case HybridCompositePass::ViewMode::DepthMismatch:
        return true;
    default:
        return false;
    }
}
} // namespace

HybridCompositePass::HybridCompositePass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("HybridCompositePass requires Shader Model 6.5 support.");

    for (const auto& [key, value] : props)
    {
        if (key == kViewMode)
            mViewMode = value.operator ViewMode();
        else
            logWarning("Unknown property '{}' in a HybridCompositePass properties.", key);
    }

    mpFbo = Fbo::create(mpDevice);
}

Properties HybridCompositePass::getProperties() const
{
    Properties props;
    props[kViewMode] = mViewMode;
    return props;
}

RenderPassReflection HybridCompositePass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputMeshColor, "Mesh style color").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputMeshPosW, "Mesh world position").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVoxelColor, "Voxel baseline color").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVBuffer, "Mesh visibility buffer").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVoxelDepth, "Voxel depth").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVoxelNormal, "Voxel normal").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVoxelConfidence, "Voxel identity confidence").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput(kInputVoxelInstanceID, "Voxel dominant instance ID").bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addOutput(kOutputColor, "Hybrid color").bindFlags(ResourceBindFlags::RenderTarget).format(ResourceFormat::RGBA32Float);
    return reflector;
}

void HybridCompositePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto pOutput = renderData.getTexture(kOutputColor);
    FALCOR_ASSERT(pOutput);

    auto& dict = renderData.getDictionary();
    dict[kHybridRequireFullMeshSource] = requiresFullMeshSource(mViewMode);
    dict[kHybridRequireFullVoxelSource] = requiresFullVoxelSource(mViewMode);

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
    var["gMeshColor"] = renderData.getTexture(kInputMeshColor);
    var["gMeshPosW"] = renderData.getTexture(kInputMeshPosW);
    var["gVoxelColor"] = renderData.getTexture(kInputVoxelColor);
    var["gVBuffer"] = renderData.getTexture(kInputVBuffer);
    var["gVoxelDepth"] = renderData.getTexture(kInputVoxelDepth);
    var["gVoxelNormal"] = renderData.getTexture(kInputVoxelNormal);
    var["gVoxelConfidence"] = renderData.getTexture(kInputVoxelConfidence);
    var["gVoxelInstanceID"] = renderData.getTexture(kInputVoxelInstanceID);
    var["PerFrameCB"]["gViewMode"] = uint32_t(mViewMode);

    mpFbo->attachColorTarget(pOutput, 0);
    mpPass->getState()->setFbo(mpFbo);
    mpPass->execute(pRenderContext, mpFbo);
}

void HybridCompositePass::renderUI(Gui::Widgets& widget)
{
    widget.dropdown("View", mViewMode);
}

void HybridCompositePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mpPass = nullptr;
}
