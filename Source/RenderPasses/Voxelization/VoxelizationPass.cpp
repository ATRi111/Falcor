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
#include "VoxelizationPass.h"

namespace
{
const std::string kVoxelizationProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/Voxelization.cs.slang";
const std::string kOutputDiffuse = "diffuse";
const std::string kOutputEllipsoids = "ellipsoids";

}; // namespace

VoxelizationPass::VoxelizationPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mVoxelResolution = 256u;
    mSampleFrequency = 16u;
    mAutoLoD = true;
    mComplete = false;
    mDebug = false;

    VoxelizationBase::updateVoxelGrid(nullptr, mVoxelResolution);

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Linear)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpSampler = pDevice->createSampler(samplerDesc);
    mpDevice = pDevice;
}

RenderPassReflection VoxelizationPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addOutput(kOutputDiffuse, "Diffuse Voxel Texture")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::RGBA32Float)
        .texture3D(gridData.voxelCount.x, gridData.voxelCount.y, gridData.voxelCount.z, 1);

    reflector.addOutput(kOutputEllipsoids, "Ellipsoids")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.totalVoxelCount() * sizeof(Ellipsoid));
    return reflector;
}

void VoxelizationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (mComplete && !mDebug)
        return;

    ref<Texture> pDiffuse = renderData.getTexture(kOutputDiffuse);
    ref<Buffer> pEllipsoids = renderData.getResource(kOutputEllipsoids)->asBuffer();

    pRenderContext->clearUAV(pDiffuse->getUAV().get(), float4(0));
    if (!mVoxelizationPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kVoxelizationProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());

        mVoxelizationPass = ComputePass::create(mpDevice, desc, defines, true);
    }

    mVoxelizationPass->addDefine("AUTO_LOD", mAutoLoD ? "1" : "0");
    ShaderVar var = mVoxelizationPass->getRootVar();
    var["s"] = mpSampler;
    mpScene->bindShaderData(var["scene"]);
    var["gDiffuse"] = pDiffuse;
    var["gEllipsoids"] = pEllipsoids;

    auto cb_grid = var["GridData"];
    cb_grid["gridMin"] = gridData.gridMin;
    cb_grid["voxelSize"] = gridData.voxelSize;
    cb_grid["voxelCount"] = gridData.voxelCount;
    cb_grid["sampleFrequency"] = mSampleFrequency;

    uint meshCount = mpScene->getMeshCount();
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        uint triangleCount = meshDesc.getTriangleCount();

        auto cb_mesh = mVoxelizationPass->getRootVar()["MeshData"];
        cb_mesh["vertexCount"] = meshDesc.vertexCount;
        cb_mesh["vbOffset"] = meshDesc.vbOffset;
        cb_mesh["triangleCount"] = triangleCount;
        cb_mesh["ibOffset"] = meshDesc.ibOffset;
        cb_mesh["use16BitIndices"] = meshDesc.use16BitIndices();
        cb_mesh["materialID"] = meshDesc.materialID;
        mVoxelizationPass->execute(pRenderContext, uint3(triangleCount, 1, 1));
        pRenderContext->uavBarrier(pDiffuse.get());
        pRenderContext->uavBarrier(pEllipsoids.get());
    }
    mComplete = true;
}

void VoxelizationPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void VoxelizationPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {16, 32, 64, 128, 256, 400};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < 6; i++)
        {
            list.push_back({resolutions[i], std::to_string(resolutions[i])});
        }
        if (widget.dropdown("Voxel Resolution", list, mVoxelResolution))
        {
            VoxelizationBase::updateVoxelGrid(mpScene, mVoxelResolution);
            requestRecompile();
            mComplete = false;
        }
    }

    static const uint samplePoints[] = {1, 2, 4, 8, 16, 32, 64};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < 7; i++)
        {
            list.push_back({samplePoints[i], std::to_string(samplePoints[i])});
        }
        if (widget.dropdown("Sample Frequency", list, mSampleFrequency))
        {
            mComplete = false;
        }
    }

    if (widget.checkbox("Auto LoD", mAutoLoD))
        mComplete = false;
    if (widget.checkbox("Debug", mDebug))
        mComplete = false;

    widget.text("Voxel Size: " + ToString(gridData.voxelSize));
    widget.text("Voxel Count: " + ToString(gridData.voxelCount));
    widget.text("Grid Min: " + ToString(gridData.gridMin));
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    VoxelizationBase::updateVoxelGrid(mpScene, mVoxelResolution);
    mVoxelizationPass = nullptr;
    mComplete = false;
}
