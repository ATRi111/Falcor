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
#include "LoadMeshPass.h"
#include "MeshSampler.h"

namespace
{
const std::string kVoxelizationProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/LoadMesh.cs.slang";
}; // namespace

LoadMeshPass::LoadMeshPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mComplete = true;
    mSampleFrequency = 0;
    mVoxelResolution = 256;

    VoxelizationBase::updateVoxelGrid(nullptr, mVoxelResolution);

    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Linear)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    mpDevice = pDevice;
}

RenderPassReflection LoadMeshPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addOutput("dummy", "Dummy")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);
    return reflector;
}

void LoadMeshPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (mComplete)
        return;

    if (!mLoadMeshPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kVoxelizationProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());

        mLoadMeshPass = ComputePass::create(mpDevice, desc, defines, true);
    }

    uint meshCount = mpScene->getMeshCount();
    uint vertexCount = 0;
    uint triangleCount = 0;
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        vertexCount += meshDesc.vertexCount;
        triangleCount += meshDesc.getTriangleCount();
    }

    uint positionBytes = sizeof(float3) * vertexCount;
    uint texCoordBytes = sizeof(float2) * vertexCount;
    uint triangleBytes = sizeof(uint3) * triangleCount;
    ref<Buffer> positions = mpDevice->createStructuredBuffer(sizeof(float3), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> texCoords = mpDevice->createStructuredBuffer(sizeof(float2), vertexCount, ResourceBindFlags::UnorderedAccess);
    ref<Buffer> triangles = mpDevice->createStructuredBuffer(sizeof(uint3), triangleCount, ResourceBindFlags::UnorderedAccess);

    ref<Buffer> cpuPositions = mpDevice->createBuffer(positionBytes, ResourceBindFlags::None, MemoryType::ReadBack);
    ref<Buffer> cpuTexCoords = mpDevice->createBuffer(texCoordBytes, ResourceBindFlags::None, MemoryType::ReadBack);
    ref<Buffer> cpuTriangles = mpDevice->createBuffer(triangleBytes, ResourceBindFlags::None, MemoryType::ReadBack);

    std::vector<MeshHeader> meshList;

    ShaderVar var = mLoadMeshPass->getRootVar();
    mpScene->bindShaderData(var["scene"]);
    var["positions"] = positions;
    var["texCoords"] = texCoords;
    var["triangles"] = triangles;
    uint triangleOffset = 0;
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        MeshHeader mesh = {meshDesc.materialID, meshDesc.vertexCount, meshDesc.getTriangleCount(), triangleOffset};
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
        pRenderContext->uavBarrier(texCoords.get());
        pRenderContext->uavBarrier(triangles.get());

        triangleOffset += meshDesc.getTriangleCount();
    }

    pRenderContext->copyResource(cpuPositions.get(), positions.get());
    pRenderContext->copyResource(cpuTexCoords.get(), texCoords.get());
    pRenderContext->copyResource(cpuTriangles.get(), triangles.get());
    mpDevice->wait();

    float3* pPos = reinterpret_cast<float3*>(cpuPositions->map());
    float2* pUV = reinterpret_cast<float2*>(cpuTexCoords->map());
    uint3* pTri = reinterpret_cast<uint3*>(cpuTriangles->map());
    SceneHeader header = {meshCount, vertexCount, triangleCount};

    {
        MeshSampler meshSampler = {mSampleFrequency};
        meshSampler.sampleAll(header, meshList, pPos, pUV, pTri);
        meshSampler.write();
    }

    cpuPositions->unmap();
    cpuTexCoords->unmap();
    cpuTriangles->unmap();

    mComplete = true;
}

void LoadMeshPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void LoadMeshPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {16, 32, 64, 128, 256, 360};
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
        }
    }

    static const uint samplePoints[] = {0, 1, 2, 4, 8, 16, 32, 64, 128, 256};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < 10; i++)
        {
            list.push_back({samplePoints[i], std::to_string(samplePoints[i])});
        }
        widget.dropdown("Sample Frequency", list, mSampleFrequency);
    }

    if (widget.button("Generate"))
        mComplete = false;
}

void LoadMeshPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mLoadMeshPass = nullptr;
    VoxelizationBase::updateVoxelGrid(mpScene, mVoxelResolution);
}
