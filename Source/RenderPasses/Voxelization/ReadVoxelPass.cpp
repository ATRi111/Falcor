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
#include "ReadVoxelPass.h"

namespace
{
const std::string kVoxelizationProgramFile = "E:/Project/Falcor/Source/RenderPasses/Voxelization/Voxelization.cs.slang";
const std::string kOutputEllipsoids = "ellipsoids";
const std::string kOutputNDFLobes = "NDFLobes";

}; // namespace

ReadVoxelPass::ReadVoxelPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mComplete = true;
    selectedFile = 0;
    mpDevice = pDevice;
}

RenderPassReflection ReadVoxelPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput("dummy", "Dummy")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);

    const ChannelList& channels = VoxelizationBase::Channels;
    for (uint i = 0; i < channels.size(); i++)
    {
        const ChannelDesc& channel = channels[i];
        reflector.addOutput(channel.name, channel.desc)
            .bindFlags(ResourceBindFlags::ShaderResource)
            .format(channel.format)
            .texture3D(gridData.voxelCount.x, gridData.voxelCount.y, gridData.voxelCount.z, 1);
    }

    reflector.addOutput(kOutputEllipsoids, "Ellipsoids")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.totalVoxelCount() * sizeof(Ellipsoid));

    reflector.addOutput(kOutputNDFLobes, "NDF Lobes")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.totalVoxelCount() * sizeof(NDF));

    return reflector;
}

void ReadVoxelPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mComplete || ABSDFBuffer.empty())
        return;

    size_t voxelCount = gridData.totalVoxelCount();

    ref<Buffer> pNDFLobes = renderData.getResource(kOutputNDFLobes)->asBuffer();
    ref<Buffer> pEllipsoids = renderData.getResource(kOutputEllipsoids)->asBuffer();
    NDF* NDFLobesBuffer = new NDF[voxelCount];
    for (size_t i = 0; i < voxelCount; i++)
    {
        NDFLobesBuffer[i] = ABSDFBuffer[i].NDF;
    }

    pNDFLobes->setBlob(NDFLobesBuffer, 0, voxelCount * sizeof(NDF));
    pEllipsoids->setBlob(ellipsoidBuffer.data(), 0, voxelCount * sizeof(Ellipsoid));

    delete[] NDFLobesBuffer;

    const ChannelList& channels = VoxelizationBase::Channels;
    for (uint i_channel = 0; i_channel < channels.size(); i_channel++)
    {
        const ChannelDesc& channel = channels[i_channel];
        ref<Texture> pTexture = renderData.getTexture(channel.name);
        float* floatBuffer = nullptr;
        float3* float3Buffer = nullptr;
        switch (channel.format)
        {
        case ResourceFormat::R32Float:
            floatBuffer = new float[voxelCount];
            break;
        case ResourceFormat::RGB32Float:
            float3Buffer = new float3[voxelCount];
            break;
        default:
            continue;
        }

        if (channel.name == "diffuse")
        {
            for (size_t i = 0; i < voxelCount; i++)
            {
                float3Buffer[i] = ABSDFBuffer[i].diffuse;
            }
        }
        else if (channel.name == "specular")
        {
            for (size_t i = 0; i < voxelCount; i++)
            {
                float3Buffer[i] = ABSDFBuffer[i].specular;
            }
        }
        else if (channel.name == "roughness")
        {
            for (size_t i = 0; i < voxelCount; i++)
            {
                floatBuffer[i] = ABSDFBuffer[i].roughness;
            }
        }
        else if (channel.name == "area")
        {
            for (size_t i = 0; i < voxelCount; i++)
            {
                floatBuffer[i] = ABSDFBuffer[i].area;
            }
        }

        switch (channel.format)
        {
        case ResourceFormat::RGB32Float:
            pTexture->setSubresourceBlob(0, float3Buffer, voxelCount * sizeof(float3));
            break;
        case ResourceFormat::R32Float:
            pTexture->setSubresourceBlob(0, floatBuffer, voxelCount * sizeof(float));
            break;
        }

        delete[] floatBuffer;
        delete[] float3Buffer;
    }
    ABSDFBuffer.clear();
    ellipsoidBuffer.clear();

    mComplete = true;
}

void ReadVoxelPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void ReadVoxelPass::renderUI(Gui::Widgets& widget)
{
    if (VoxelizationBase::FileUpdated)
    {
        filePaths.clear();
        for (const auto& entry : std::filesystem::directory_iterator(VoxelizationBase::ResourceFolder))
        {
            if (std::filesystem::is_regular_file(entry))
            {
                filePaths.push_back(entry.path());
            }
        }
        VoxelizationBase::FileUpdated = false;
    }
    Gui::DropdownList list;
    for (uint i = 0; i < filePaths.size(); i++)
    {
        list.push_back({i, filePaths[i].filename().string()});
    }
    widget.dropdown("File", list, selectedFile);

    if (widget.button("Read"))
    {
        std::ifstream f;
        size_t offset = 0;

        f.open(filePaths[selectedFile], std::ios::binary | std::ios::ate);
        if (!f.is_open())
            return;

        size_t fileSize = std::filesystem::file_size(filePaths[selectedFile]);

        tryRead(f, offset, sizeof(GridData), &gridData, fileSize);
        size_t voxelCount = gridData.totalVoxelCount();
        reset(voxelCount);

        tryRead(f, offset, voxelCount * sizeof(ABSDF), ABSDFBuffer.data(), fileSize);

        tryRead(f, offset, voxelCount * sizeof(Ellipsoid), ellipsoidBuffer.data(), fileSize);

        f.close();

        requestRecompile();
        mComplete = false;
    }

    GridData& data = VoxelizationBase::GlobalGridData;
    widget.text("Voxel Size: " + ToString(data.voxelSize));
    widget.text("Voxel Count: " + ToString(data.voxelCount));
    widget.text("Grid Min: " + ToString(data.gridMin));
}

void ReadVoxelPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) {}

void ReadVoxelPass::reset(uint voxelCount)
{
    ABSDFBuffer.reserve(voxelCount);
    ABSDFBuffer.resize(voxelCount);
    ellipsoidBuffer.reserve(voxelCount);
    ellipsoidBuffer.resize(voxelCount);
}

bool ReadVoxelPass::tryRead(std::ifstream& f, size_t& offset, size_t bytes, void* dst, size_t fileSize)
{
    if (offset + bytes > fileSize)
        return false;
    f.seekg(offset, std::ios::beg);
    f.read(reinterpret_cast<char*>(dst), bytes);
    offset += bytes;
    return true;
}
