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
#include "RayMarchingPass.h"

namespace
{
const std::string kShaderFile = "E:/Project/Falcor/Source/RenderPasses/RayMarchingPass/RayMarching.ps.slang";
const std::string kInputOccupancyMap = "occupancyMap";
const std::string kInputGridData = "gridData";
const std::string kOutputColor = "color";
} // namespace

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, RayMarchingPass>();
}

RayMarchingPass::RayMarchingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mpDevice = pDevice;
    mUpdateScene = false;

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Point, TextureFilteringMode::Point, TextureFilteringMode::Point)
        .setAddressingMode(TextureAddressingMode::Border, TextureAddressingMode::Border, TextureAddressingMode::Border)
        .setBorderColor(float4());
    mpPointSampler = mpDevice->createSampler(samplerDesc);
}

RenderPassReflection RayMarchingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addInput(kInputOccupancyMap, "Input occupancy map").bindFlags(ResourceBindFlags::ShaderResource).texture3D(0, 0, 0, 1);
    reflector.addInput(kInputGridData, "Input grid data")
        .bindFlags(ResourceBindFlags::Constant)
        .format(ResourceFormat::Unknown)
        .rawBuffer(sizeof(GridData));

    reflector.addOutput(kOutputColor, "Output color")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);
    return reflector;
}

void RayMarchingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (mUpdateScene)
    {
        ProgramDesc desc;
        desc.addShaderLibrary(kShaderFile).psEntry("main");
        desc.setShaderModel(ShaderModel::SM6_5);
        desc.addTypeConformances(mpScene->getTypeConformances());
        mpFullScreenPass = FullScreenPass::create(mpDevice, desc, mpScene->getSceneDefines());
        mUpdateScene = false;
    }

    ref<Texture> pInputOccupancyMap = renderData.getTexture(kInputOccupancyMap);
    ref<Texture> pOutputColor = renderData.getTexture(kOutputColor);

    ref<Buffer> pGridData = renderData.getResource(kInputGridData)->asBuffer();
    GridData data;
    pGridData->getBlob(&data, 0, sizeof(GridData));
    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0));

    auto var = mpFullScreenPass->getRootVar();
    var["gOccupancyMap"] = pInputOccupancyMap;
    var["GridData"]["gridMin"] = data.gridMin;
    var["GridData"]["voxelSize"] = data.voxelSize;
    var["GridData"]["voxelCount"] = data.voxelCount;
    var["CB"]["pixelCount"] = uint2(pOutputColor->getWidth(), pOutputColor->getHeight());
    var["CB"]["invVP"] = math::inverse(mpScene->getCamera()->getViewProjMatrixNoJitter());

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutputColor, 0);
    mpFullScreenPass->execute(pRenderContext, fbo);
}

void RayMarchingPass::renderUI(Gui::Widgets& widget) {}

void RayMarchingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mUpdateScene = true;
}
