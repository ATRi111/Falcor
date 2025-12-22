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
#include "VoxelizationPass_CPU.h"

namespace
{
const std::string kLoadMeshProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/LoadMesh.cs.slang";
}; // namespace

VoxelizationPass_CPU::VoxelizationPass_CPU(ref<Device> pDevice, const Properties& props) : VoxelizationPass(pDevice, props)
{
}

void VoxelizationPass_CPU::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    VoxelizationPass::setScene(pRenderContext, pScene);
    mLoadMeshPass = nullptr;
}

void VoxelizationPass_CPU::voxelize(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mLoadMeshPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kLoadMeshProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());

        mLoadMeshPass = ComputePass::create(mpDevice, desc, defines, true);
    }

    uint meshCount = mpScene->getMeshCount();
    uint vertexCount = 0;
    uint triangleCount = 0;
    for (MeshID meshID{ 0 }; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        vertexCount += meshDesc.vertexCount;
        triangleCount += meshDesc.getTriangleCount();
    }

    ref<Buffer> positions = mpDevice->createStructuredBuffer(sizeof(float3), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> normals = mpDevice->createStructuredBuffer(sizeof(float3), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> texCoords = mpDevice->createStructuredBuffer(sizeof(float2), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> triangles = mpDevice->createStructuredBuffer(sizeof(uint3), triangleCount, ResourceBindFlags::UnorderedAccess);

    ref<Buffer> cpuPositions = mpDevice->createBuffer(sizeof(float3) * vertexCount, ResourceBindFlags::None, MemoryType::ReadBack);
    ref<Buffer> cpuNormals = mpDevice->createBuffer(sizeof(float3) * vertexCount, ResourceBindFlags::None, MemoryType::ReadBack);
    ref<Buffer> cpuTexCoords = mpDevice->createBuffer(sizeof(float2) * vertexCount, ResourceBindFlags::None, MemoryType::ReadBack);
    ref<Buffer> cpuTriangles = mpDevice->createBuffer(sizeof(uint3) * triangleCount, ResourceBindFlags::None, MemoryType::ReadBack);

    std::vector<MeshHeader> meshList;

    ShaderVar var = mLoadMeshPass->getRootVar();
    mpScene->bindShaderData(var["scene"]);
    var["positions"] = positions;
    var["normals"] = normals;
    var["texCoords"] = texCoords;
    var["triangles"] = triangles;
    uint triangleOffset = 0;
    for (MeshID meshID{ 0 }; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        MeshHeader mesh = { meshDesc.materialID, meshDesc.vertexCount, meshDesc.getTriangleCount(), triangleOffset };
        meshList.push_back(mesh);

        auto meshData = mLoadMeshPass->getRootVar()["MeshData"];
        meshData["vertexCount"] = meshDesc.vertexCount;
        meshData["vbOffset"] = meshDesc.vbOffset;
        meshData["triangleCount"] = meshDesc.getTriangleCount();
        meshData["ibOffset"] = meshDesc.ibOffset;
        meshData["triOffset"] = triangleOffset;
        meshData["use16BitIndices"] = meshDesc.use16BitIndices();
        mLoadMeshPass->execute(pRenderContext, uint3(meshDesc.getTriangleCount(), 1, 1));
        pRenderContext->uavBarrier(positions.get());
        pRenderContext->uavBarrier(normals.get());
        pRenderContext->uavBarrier(texCoords.get());
        pRenderContext->uavBarrier(triangles.get());

        triangleOffset += meshDesc.getTriangleCount();
    }

    pRenderContext->copyResource(cpuPositions.get(), positions.get());
    pRenderContext->copyResource(cpuNormals.get(), normals.get());
    pRenderContext->copyResource(cpuTexCoords.get(), texCoords.get());
    pRenderContext->copyResource(cpuTriangles.get(), triangles.get());
    mpDevice->wait();

    float3* pPos = reinterpret_cast<float3*>(cpuPositions->map());
    float3* pNormal = reinterpret_cast<float3*>(cpuNormals->map());
    float2* pUV = reinterpret_cast<float2*>(cpuTexCoords->map());
    uint3* pTri = reinterpret_cast<uint3*>(cpuTriangles->map());
    SceneHeader header = { meshCount, vertexCount, triangleCount };

    meshSampler.reset();
    meshSampler.sampleAll(header, meshList, pPos, pNormal, pUV, pTri);
    gridData.solidVoxelCount = meshSampler.gBuffer.size();
    meshSampler.analyzeAll();
    cpuPositions->unmap();
    cpuNormals->unmap();
    cpuTexCoords->unmap();
    cpuTriangles->unmap();

    gBuffer = mpDevice->createStructuredBuffer(sizeof(VoxelData), gridData.solidVoxelCount, ResourceBindFlags::UnorderedAccess);
    polygonBuffer = mpDevice->createStructuredBuffer(sizeof(PolygonInVoxel), gridData.solidVoxelCount, ResourceBindFlags::ShaderResource);
    gBuffer->setBlob(meshSampler.gBuffer.data(), 0, gridData.solidVoxelCount * sizeof(VoxelData));
    polygonBuffer->setBlob(meshSampler.polygonBuffer.data(), 0, gridData.solidVoxelCount * sizeof(PolygonInVoxel));
    pVBuffer_CPU = meshSampler.vBuffer.data();

    mpDevice->wait();
}

void VoxelizationPass_CPU::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
    VoxelizationPass::sample(pRenderContext, renderData);
}

void VoxelizationPass_CPU::renderUI(Gui::Widgets& widget)
{
    VoxelizationPass::renderUI(widget);
    widget.checkbox("LerpNormal", meshSampler.lerpNormal);
}
