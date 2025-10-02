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
const std::string kVoxelizationProgramFile = "E:/Project/Falcor/Source/RenderPasses/GBuffer/GBuffer/Voxelization.3d.slang";
const std::string kOutputOccupancyMap = "occupancyMap";
const std::string kOutputGridData = "gridData";

std::string ToString(float3 v)
{
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(4);
    oss << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    return oss.str();
}
std::string ToString(uint3 v)
{
    std::ostringstream oss;
    oss << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    return oss.str();
}
}; // namespace

VoxelizationPass::VoxelizationPass(ref<Device> pDevice, const Properties& props) : GBuffer(pDevice)
{
    mVoxelResolution = 32u;
    mCullMode = RasterizerState::CullMode::None;
    mGridMin = float3(0);
    mVoxelSize = float3(1.f / mVoxelResolution);
    mVoxelCount = uint3(mVoxelResolution);
    mVoxelizationPass.pState = GraphicsState::create(mpDevice);
}

RenderPassReflection VoxelizationPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addOutput(kOutputOccupancyMap, "Output Occupancy Map")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::RG32Uint)
        .texture3D(mVoxelCount.x, mVoxelCount.y, mVoxelCount.z, 1);
    reflector.addOutput(kOutputGridData, "Output Grid Data")
        .bindFlags(ResourceBindFlags::Constant)
        .format(ResourceFormat::Unknown)
        .rawBuffer(sizeof(GridData));

    return reflector;
}

void VoxelizationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    GBuffer::execute(pRenderContext, renderData);
    if (!mpScene)
        return;

    if (is_set(mpScene->getUpdates(), IScene::UpdateFlags::RecompileNeeded))
    {
        recreatePrograms();
    }

    ref<Buffer> pGridData = renderData.getResource(kOutputGridData)->asBuffer();
    ref<Texture> pOccupancyMap = renderData.getTexture(kOutputOccupancyMap);

    updateVoxelGrid();
    GridData data = {mGridMin, mVoxelSize, mVoxelCount};
    pGridData->setBlob(&data, 0, sizeof(GridData));

    {
        // Create depth pass program.
        if (!mVoxelizationPass.pProgram)
        {
            ProgramDesc desc;
            desc.addShaderModules(mpScene->getShaderModules());
            desc.addShaderLibrary(kVoxelizationProgramFile).vsEntry("vsMain").psEntry("psMain");
            desc.addTypeConformances(mpScene->getTypeConformances());

            mVoxelizationPass.pProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
            mVoxelizationPass.pState->setProgram(mVoxelizationPass.pProgram);
        }

        if (!mVoxelizationPass.pVars)
            mVoxelizationPass.pVars = ProgramVars::create(mpDevice, mVoxelizationPass.pProgram.get());

        ShaderVar var = mVoxelizationPass.pVars->getRootVar();
        var["gOccupancyMap"] = pOccupancyMap;
        var["GridData"]["gridMin"] = mGridMin;
        var["GridData"]["voxelSize"] = mVoxelSize;
        var["GridData"]["voxelCount"] = mVoxelCount;

        mpScene->rasterize(pRenderContext, mVoxelizationPass.pState.get(), mVoxelizationPass.pVars.get(), mCullMode);
    }
    pRenderContext->clearUAV(pOccupancyMap->getUAV().get(), uint4(1));
}

void VoxelizationPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {16, 32, 64, 128, 256, 512};
    Gui::DropdownList list;
    for (uint32_t i = 0; i < 6; i++)
    {
        list.push_back({resolutions[i], std::to_string(resolutions[i])});
    }
    if (widget.dropdown("Voxel Resolution", list, mVoxelResolution))
    {
        updateVoxelGrid();
        requestRecompile();
    }

    widget.text("Voxel Size: " + ToString(mVoxelSize));
    widget.text("Voxel Count: " + ToString(float3(mVoxelCount)));
    widget.text("Grid Min: " + ToString(mGridMin));
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    GBuffer::setScene(pRenderContext, pScene);
    mpScene = pScene;
    recreatePrograms();
}

void VoxelizationPass::updateVoxelGrid()
{
    if (!mpScene)
        return;

    AABB aabb = mpScene->getSceneBounds();
    float3 diag = aabb.maxPoint - aabb.minPoint;
    float max = std::max(diag.z, std::max(diag.x, diag.y)) / mVoxelResolution;
    mVoxelSize = float3(max);
    float3 temp = diag / mVoxelSize;

    mVoxelCount = uint3((uint)math::ceil(temp.x / 4) * 4, (uint)math::ceil(temp.y / 4) * 4, (uint)math::ceil(temp.z / 4) * 4);
    mGridMin = aabb.center() - mVoxelSize * float3(mVoxelCount) / 2.f;
}

void VoxelizationPass::recreatePrograms()
{
    mVoxelizationPass.pVars = nullptr;
    mVoxelizationPass.pProgram = nullptr;
}
