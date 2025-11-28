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

namespace
{
const std::string kLoadMeshProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/LoadMesh.cs.slang";
const std::string kSamplePolygonProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/SamplePolygon.cs.slang";
}; // namespace

LoadMeshPass::LoadMeshPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mSceneNameIndex = 0;
    mSceneName = "Arcade";
    mCPUComplete = true;
    mGPUComplete = true;
    mCompleteTimes = 0;

    mRepeatTimes = 1;
    mSampleFrequency = 16;
    mVoxelResolution = 256;

    VoxelizationBase::UpdateVoxelGrid(nullptr, mVoxelResolution);

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
    if (!mpScene || mCPUComplete && mGPUComplete)
        return;

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
    if (!mSamplePolygonPass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kSamplePolygonProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        mSamplePolygonPass = ComputePass::create(mpDevice, desc, defines, true);
    }


    size_t gBufferBytes = gridData.solidVoxelCount * sizeof(VoxelData);
    if (!mCPUComplete)
    {
        uint meshCount = mpScene->getMeshCount();
        uint vertexCount = 0;
        uint triangleCount = 0;
        for (MeshID meshID{ 0 }; meshID.get() < meshCount; ++meshID)
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
        SceneHeader header = { meshCount, vertexCount, triangleCount };

        meshSampler.reset();
        meshSampler.sampleAll(header, meshList, pPos, pUV, pTri);
        meshSampler.analyzeAll();
        cpuPositions->unmap();
        cpuTexCoords->unmap();
        cpuTriangles->unmap();

        gBuffer = mpDevice->createStructuredBuffer(sizeof(VoxelData), gridData.solidVoxelCount, ResourceBindFlags::UnorderedAccess);
        polygonBuffer = mpDevice->createStructuredBuffer(sizeof(PolygonInVoxel), gridData.solidVoxelCount, ResourceBindFlags::ShaderResource);
        gBuffer->setBlob(meshSampler.gBuffer.data(), 0, gBufferBytes);
        polygonBuffer->setBlob(meshSampler.polygonBuffer.data(), 0, gridData.solidVoxelCount * sizeof(PolygonInVoxel));

        mCPUComplete = true;
    }
    
    if (!mGPUComplete)
    {
        ShaderVar var = mSamplePolygonPass->getRootVar();
        var[kGBuffer] = gBuffer;
        var["polygonBuffer"] = polygonBuffer;

        auto cb = var["CB"];
        cb["solidVoxelCount"] = (uint)gridData.solidVoxelCount;
        cb["sampleFrequency"] = mSampleFrequency;
        cb["completeTimes"] = mCompleteTimes;
        cb["repeatTimes"] = mRepeatTimes;

        Tools::Profiler::BeginSample("Sample Polygons");
        mSamplePolygonPass->execute(pRenderContext, uint3((uint)gridData.solidVoxelCount, 1, 1));
        mpDevice->wait();
        Tools::Profiler::EndSample("Sample Polygons");
        mCompleteTimes++;

        if (mCompleteTimes >= mRepeatTimes)
        {
            ref<Buffer> cpuGBuffer = mpDevice->createBuffer(gBufferBytes, ResourceBindFlags::None, MemoryType::ReadBack);
            pRenderContext->copyResource(cpuGBuffer.get(), gBuffer.get());
            mpDevice->wait();
            memcpy(meshSampler.gBuffer.data(), cpuGBuffer->map(), gBufferBytes);
            cpuGBuffer->unmap();
            meshSampler.write(getFileName());
            Tools::Profiler::Print();
            Tools::Profiler::Reset();
            meshSampler.clear();
            mGPUComplete = true;
        }
    }
}

void LoadMeshPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void LoadMeshPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {16,32,64,128,256,512,1024};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(resolutions) / sizeof(uint); i++)
        {
            list.push_back({resolutions[i], std::to_string(resolutions[i])});
        }
        if (widget.dropdown("Voxel Resolution", list, mVoxelResolution))
        {
            VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
            requestRecompile();
        }
    }

    static const std::string sceneNames[] = { "Arcade"};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(sceneNames) / sizeof(std::string); i++)
        {
            list.push_back({ i, sceneNames[i] });
        }
        if (widget.dropdown("Scene Name", list, mSceneNameIndex))
        {
            mSceneName = sceneNames[mSceneNameIndex];
        }
    }

    static const uint samplePoints[] = {0, 1, 2, 4, 8, 16, 32, 64, 128, 256};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(samplePoints) / sizeof(uint); i++)
        {
            list.push_back({samplePoints[i], std::to_string(samplePoints[i])});
        }
        widget.dropdown("Sample Frequency", list, mSampleFrequency);
            
    }
    static const uint repeatTimes[] = { 0, 1, 2, 4, 8, 16, 32, 64, 128, 256 };
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(repeatTimes) / sizeof(uint); i++)
        {
            list.push_back({ repeatTimes[i], std::to_string(repeatTimes[i]) });
        }
        widget.dropdown("Repeat times", list, mRepeatTimes);
    }

    if (mpScene && mCPUComplete && mGPUComplete && widget.button("Generate"))
    {
        ImageLoader::Instance().setSceneName(mSceneName);
        mCPUComplete = false;
        mGPUComplete = false;
        mCompleteTimes = 0;
    }
}

void LoadMeshPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mLoadMeshPass = nullptr;
    VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
}

std::string LoadMeshPass::getFileName()
{
    std::ostringstream oss;
    oss << mSceneName;
    oss << "_";
    oss << ToString(gridData.voxelCount);
    oss << "_";
    oss << std::to_string(mSampleFrequency);
    oss << "_";
    oss << std::to_string(mRepeatTimes);
    oss << ".bin";
    return oss.str();
}
