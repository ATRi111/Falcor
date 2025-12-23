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
#include "VoxelizationPass_GPU.h"

namespace
{
const std::string kClipProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/ClipMesh.cs.slang";
const std::string kAnalyzeProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/AnalyzePolygon.cs.slang";

}; // namespace

VoxelizationPass_GPU::VoxelizationPass_GPU(ref<Device> pDevice, const Properties& props)
    : VoxelizationPass(pDevice, props)
{
    maxSolidVoxelCount = (uint)ceil(4294967296.0 / sizeof(PolygonInVoxel)); //缓冲区最大容量为4G

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Linear)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpSampler = pDevice->createSampler(samplerDesc);
}

void VoxelizationPass_GPU::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    VoxelizationPass::setScene(pRenderContext, pScene);
    mClipPass = nullptr;
    mAnalyzePass = nullptr;
}

void VoxelizationPass_GPU::voxelize(RenderContext* pRenderContext, const RenderData& renderData)
{
    gBuffer = mpDevice->createStructuredBuffer(sizeof(VoxelData), maxSolidVoxelCount, ResourceBindFlags::UnorderedAccess);
    vBuffer = mpDevice->createStructuredBuffer(sizeof(int), gridData.totalVoxelCount(), ResourceBindFlags::UnorderedAccess);
    solidVoxelCount = mpDevice->createStructuredBuffer(sizeof(uint), 2, ResourceBindFlags::UnorderedAccess);
    pRenderContext->clearUAV(solidVoxelCount->getUAV().get(), uint4(0));
    pRenderContext->clearUAV(vBuffer->getUAV().get(), uint4(0xFFFFFFFFu));

    if (!mClipPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kClipProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());

        mClipPass = ComputePass::create(mpDevice, desc, defines, true);
    }
    if (!mAnalyzePass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kAnalyzeProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());

        mAnalyzePass = ComputePass::create(mpDevice, desc, defines, true);
    }

    mClipPass->addDefine("DISABLE_LOCK", "1");
    ShaderVar var = mClipPass->getRootVar();
    var["s"] = mpSampler;
    mpScene->bindShaderData(var["scene"]);
    var[kGBuffer] = gBuffer;
    var[kVBuffer] = vBuffer;
    //TODO
    // var[kPolygonBuffer] = polygonGroup;
    var["solidVoxelCount"] = solidVoxelCount;

    auto cb_grid = var["GridData"];
    cb_grid["gridMin"] = gridData.gridMin;
    cb_grid["voxelSize"] = gridData.voxelSize;
    cb_grid["voxelCount"] = gridData.voxelCount;

    uint meshCount = mpScene->getMeshCount();
    for (MeshID meshID{ 0 }; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        uint triangleCount = meshDesc.getTriangleCount();

        auto cb_mesh = mClipPass->getRootVar()["MeshData"];
        cb_mesh["vertexCount"] = meshDesc.vertexCount;
        cb_mesh["vbOffset"] = meshDesc.vbOffset;
        cb_mesh["triangleCount"] = triangleCount;
        cb_mesh["ibOffset"] = meshDesc.ibOffset;
        cb_mesh["use16BitIndices"] = meshDesc.use16BitIndices();
        cb_mesh["materialID"] = meshDesc.materialID;
        mClipPass->execute(pRenderContext, uint3(triangleCount, 1, 1));
        pRenderContext->uavBarrier(gBuffer.get());
    }
    mpDevice->wait();

    ref<Buffer> cpuSolidVoxelCount = mpDevice->createStructuredBuffer(sizeof(uint), 2, ResourceBindFlags::None, MemoryType::ReadBack);
    cpuVBuffer = mpDevice->createBuffer(gridData.totalVoxelCount() * sizeof(int), ResourceBindFlags::None, MemoryType::ReadBack);
    pRenderContext->copyResource(cpuSolidVoxelCount.get(), solidVoxelCount.get());
    pRenderContext->copyResource(cpuVBuffer.get(), vBuffer.get());
    mpDevice->wait();
    uint* p = reinterpret_cast<uint*>(cpuSolidVoxelCount->map());
    pVBuffer_CPU = cpuVBuffer->map();
    gridData.solidVoxelCount = p[0];

    var = mAnalyzePass->getRootVar();
    var[kGBuffer] = gBuffer;
    //TODO
    //var[kPolygonBuffer] = polygonGroup;
    auto cb = var["CB"];
    cb["solidVoxelCount"] = p[0];
    mAnalyzePass->execute(pRenderContext, uint3(p[0], 1, 1));

    mpDevice->wait();
    cpuSolidVoxelCount->unmap();
}

void VoxelizationPass_GPU::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
    VoxelizationPass::sample(pRenderContext, renderData);
}
