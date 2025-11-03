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
const std::string kOutputDiffuse = "diffuse";
const std::string kOutputEllipsoids = "ellipsoids";

}; // namespace

ReadVoxelPass::ReadVoxelPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mComplete = true;
    diffuseBuffer = nullptr;
    ellipsoids = nullptr;
    selectedFile = 0;
    mpDevice = pDevice;
}

ReadVoxelPass::~ReadVoxelPass()
{
    if (diffuseBuffer)
        free(diffuseBuffer);
}

RenderPassReflection ReadVoxelPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput("dummy", "Dummy")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);

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

void ReadVoxelPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mComplete || !diffuseBuffer)
        return;

    ref<Texture> pDiffuse = renderData.getTexture(kOutputDiffuse);
    ref<Buffer> pEllipsoids = renderData.getResource(kOutputEllipsoids)->asBuffer();

    pDiffuse->setSubresourceBlob(0, diffuseBuffer, gridData.totalVoxelCount() * sizeof(float4));
    if (gridData.totalVoxelCount() * sizeof(Ellipsoid) <= pEllipsoids->getElementCount())
        pEllipsoids->setBlob(ellipsoids, 0, gridData.totalVoxelCount() * sizeof(Ellipsoid));
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
        uint offset = 0;

        f.open(filePaths[selectedFile], std::ios::binary | std::ios::ate);
        if (!f.is_open())
            return;

        uint fileSize = std::filesystem::file_size(filePaths[selectedFile]);

        tryRead(f, offset, sizeof(GridData), &gridData, fileSize);
        uint voxelCount = gridData.totalVoxelCount();
        reset(voxelCount);

        tryRead(f, offset, voxelCount * sizeof(float4), diffuseBuffer, fileSize);

        tryRead(f, offset, voxelCount * sizeof(Ellipsoid), ellipsoids, fileSize);

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
    free(diffuseBuffer);
    diffuseBuffer = reinterpret_cast<float4*>(malloc(voxelCount * sizeof(float4)));
    free(ellipsoids);
    ellipsoids = reinterpret_cast<Ellipsoid*>(malloc(voxelCount * sizeof(Ellipsoid)));
}

bool ReadVoxelPass::tryRead(std::ifstream& f, uint& offset, uint bytes, void* dst, uint fileSize)
{
    if (offset + bytes > fileSize)
        return false;
    f.seekg(offset, std::ios::beg);
    f.read(reinterpret_cast<char*>(dst), bytes);
    offset += bytes;
    return true;
}
