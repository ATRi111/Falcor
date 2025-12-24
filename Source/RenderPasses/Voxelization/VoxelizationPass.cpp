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
#include "Image/ImageLoader.h"
#include <fstream>

namespace
{
const std::string kSamplePolygonProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/SamplePolygon.cs.slang";
}; // namespace

VoxelizationPass::VoxelizationPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice) , polygonGroup(pDevice,sizeof(PolygonInVoxel), 32768 * sizeof(PolygonInVoxel)), gridData(VoxelizationBase::GlobalGridData)
{
    mSceneNameIndex = 0;
    mSceneName = "Arcade";
    mVoxelizationComplete = true;
    mSamplingComplete = true;
    mCompleteTimes = 0;
    pVBuffer_CPU = nullptr;

    mSampleFrequency = 256;
    mVoxelResolution = 512;

    VoxelizationBase::UpdateVoxelGrid(nullptr, mVoxelResolution);

    mpDevice = pDevice;
}

RenderPassReflection VoxelizationPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    reflector.addOutput("dummy", "Dummy")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);
    return reflector;
}

void VoxelizationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene || mVoxelizationComplete && mSamplingComplete)
        return;

    if (!mVoxelizationComplete)
    {
        voxelize(pRenderContext, renderData);
        mVoxelizationComplete = true;
    }
    else
    {
        if (mCompleteTimes < polygonGroup.size())
        {
            sample(pRenderContext, renderData);
            mCompleteTimes++;
        }
        else
        {
            ref<Buffer> cpuGBuffer = mpDevice->createBuffer(gBuffer->getSize(), ResourceBindFlags::None, MemoryType::ReadBack);
            pRenderContext->copyResource(cpuGBuffer.get(), gBuffer.get());
            mpDevice->wait();
            void* pGBuffer_CPU = cpuGBuffer->map();
            write(getFileName(), pGBuffer_CPU, pVBuffer_CPU);
            cpuGBuffer->unmap();
            Tools::Profiler::Print();
            Tools::Profiler::Reset();
            mSamplingComplete = true;
        }
    }
}

void VoxelizationPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void VoxelizationPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = { 16, 32, 64, 128, 256, 512,1000, 1024 };
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

    static const std::string sceneNames[] = { "Arcade", "Tree", "BoxBunny", "Box","Chandelier" };
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(sceneNames) / sizeof(std::string); i++)
        {
            list.push_back({i, sceneNames[i]});
        }
        if (widget.dropdown("Scene Name", list, mSceneNameIndex))
        {
            mSceneName = sceneNames[mSceneNameIndex];
        }
    }

    static const uint sampleFrequencies[] = {0, 1, 2, 4, 8, 16, 32, 64, 128, 256};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < sizeof(sampleFrequencies) / sizeof(uint); i++)
        {
            list.push_back({sampleFrequencies[i], std::to_string(sampleFrequencies[i])});
        }
        widget.dropdown("Sample Frequency", list, mSampleFrequency);
    }

    if (mpScene && mVoxelizationComplete && mSamplingComplete && widget.button("Generate"))
    {
        ImageLoader::Instance().setSceneName(mSceneName);
        mVoxelizationComplete = false;
        mSamplingComplete = false;
        mCompleteTimes = 0;
    }
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mSamplePolygonPass = nullptr;
    VoxelizationBase::UpdateVoxelGrid(mpScene, mVoxelResolution);
}

void VoxelizationPass::voxelize(RenderContext* pRenderContext, const RenderData& renderData) {}

void VoxelizationPass::sample(RenderContext* pRenderContext, const RenderData& renderData)
{
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
    ShaderVar var = mSamplePolygonPass->getRootVar();
    var[kGBuffer] = gBuffer;
    var[kPolygonBuffer] = polygonGroup.get(mCompleteTimes);

    uint gBufferOffset = mCompleteTimes * polygonGroup.maxElementCountPerBuffer();
    uint elementCount = polygonGroup.getElementCountOfBuffer(mCompleteTimes);
    auto cb = var["CB"];
    cb["voxelCount"] = elementCount;
    cb["sampleFrequency"] = mSampleFrequency;
    cb["gBufferOffset"] = gBufferOffset;

    Tools::Profiler::BeginSample("Sample Polygons");
    mSamplePolygonPass->execute(pRenderContext, uint3(elementCount, 1, 1));
    mpDevice->wait();
    Tools::Profiler::EndSample("Sample Polygons");
}

std::string VoxelizationPass::getFileName() const
{
    std::ostringstream oss;
    oss << mSceneName;
    oss << "_";
    oss << ToString((int3)gridData.voxelCount);
    oss << "_";
    oss << std::to_string(mSampleFrequency);
    oss << ".bin";
    return oss.str();
}

void VoxelizationPass::write(std::string fileName, void* pGBuffer, void* pVBuffer)
{
    std::ofstream f;
    std::string s = VoxelizationBase::ResourceFolder + fileName;
    f.open(s, std::ios::binary);
    f.write(reinterpret_cast<char*>(&gridData), sizeof(GridData));

    f.write(reinterpret_cast<const char*>(pVBuffer), gridData.totalVoxelCount() * sizeof(int));
    f.write(reinterpret_cast<const char*>(pGBuffer), gridData.solidVoxelCount * sizeof(VoxelData));

    f.close();
    VoxelizationBase::FileUpdated = true;
}
