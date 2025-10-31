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
const std::string kShaderFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/RayMarching.ps.slang";
const std::string kInputDiffuse = "diffuse";
const std::string kInputEllipsoids = "ellipsoids";
const std::string kOutputColor = "color";
} // namespace

RayMarchingPass::RayMarchingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mpDevice = pDevice;
    mUpdateScene = false;

    mShowVoxelIndex = false;
    mCheckEllipsoid = false;

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Point, TextureFilteringMode::Point, TextureFilteringMode::Point)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpPointSampler = mpDevice->createSampler(samplerDesc);
}

RenderPassReflection RayMarchingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput(kInputEllipsoids, "Ellipsoids")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(VoxelizationBase::GlobalGridData.totalVoxelCount() * sizeof(Ellipsoid));

    reflector.addInput(kInputDiffuse, "Diffuse")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::RGBA32Float)
        .texture3D(0, 0, 0, 1);

    reflector.addOutput(kOutputColor, "Color")
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
    mpFullScreenPass->addDefine("SHOW_VOXEL_INDEX", mShowVoxelIndex ? "1" : "0");
    mpFullScreenPass->addDefine("CHECK_ELLIPSOID", mCheckEllipsoid ? "1" : "0");

    ref<Camera> pCamera = mpScene->getCamera();

    ref<Texture> pDiffuse = renderData.getTexture(kInputDiffuse);
    ref<Buffer> pEllipsoids = renderData.getResource(kInputEllipsoids)->asBuffer();
    ref<Texture> pOutputColor = renderData.getTexture(kOutputColor);

    GridData& data = VoxelizationBase::GlobalGridData;

    pRenderContext->clearRtv(pOutputColor->getRTV().get(), float4(0));

    auto var = mpFullScreenPass->getRootVar();
    var["gDiffuse"] = pDiffuse;
    var["gEllipsoids"] = pEllipsoids;

    var["GridData"]["gridMin"] = data.gridMin;
    var["GridData"]["voxelSize"] = data.voxelSize;
    var["GridData"]["voxelCount"] = data.voxelCount;

    var["CB"]["pixelCount"] = uint2(pOutputColor->getWidth(), pOutputColor->getHeight());
    var["CB"]["invVP"] = math::inverse(pCamera->getViewProjMatrixNoJitter());

    ref<Fbo> fbo = Fbo::create(mpDevice);
    fbo->attachColorTarget(pOutputColor, 0);
    mpFullScreenPass->execute(pRenderContext, fbo);
}

void RayMarchingPass::renderUI(Gui::Widgets& widget)
{
    widget.checkbox("Show Voxel Index", mShowVoxelIndex);
    widget.checkbox("Check Ellipsoid", mCheckEllipsoid);
}

void RayMarchingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mUpdateScene = true;
}
