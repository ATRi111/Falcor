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
const std::string kOutputGridData = "gridData";
const std::string kOutputDiffuse = "diffuse";
const std::string kOutputEllipsoids = "ellipsoids";

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

VoxelizationPass::VoxelizationPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mVoxelResolution = 256u;
    mSampleFrequency = 16u;
    minFactor = uint3(1, 1, 1);
    mAutoLoD = true;
    mComplete = false;
    mDebug = false;

    updateVoxelGrid();

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(TextureFilteringMode::Linear, TextureFilteringMode::Linear, TextureFilteringMode::Linear)
        .setAddressingMode(TextureAddressingMode::Wrap, TextureAddressingMode::Wrap, TextureAddressingMode::Wrap);
    // Sampler::Desc samplerDesc;
    // samplerDesc.setFilterMode(TextureFilteringMode::Point, TextureFilteringMode::Point, TextureFilteringMode::Point)
    //     .setAddressingMode(TextureAddressingMode::Clamp, TextureAddressingMode::Clamp, TextureAddressingMode::Clamp);
    mpSampler = pDevice->createSampler(samplerDesc);
    mpDevice = pDevice;
}

RenderPassReflection VoxelizationPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addOutput(kOutputGridData, "Grid Data")
        .bindFlags(ResourceBindFlags::Constant)
        .format(ResourceFormat::Unknown)
        .rawBuffer(sizeof(GridData));

    reflector.addOutput(kOutputDiffuse, "Diffuse Voxel Texture")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::RGBA32Float)
        .texture3D(mVoxelCount.x, mVoxelCount.y, mVoxelCount.z, 1);

    reflector.addOutput(kOutputEllipsoids, "Ellipsoids")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(mVoxelCount.x * mVoxelCount.y * mVoxelCount.z * sizeof(Ellipsoid));
    return reflector;
}

void VoxelizationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (mComplete && !mDebug)
        return;

    ref<Buffer> pGridData = renderData.getResource(kOutputGridData)->asBuffer();
    ref<Texture> pDiffuse = renderData.getTexture(kOutputDiffuse);
    ref<Buffer> pEllipsoids = renderData.getResource(kOutputEllipsoids)->asBuffer();
    GridData data = {mGridMin, mVoxelSize, mVoxelCount};
    pGridData->setBlob(&data, 0, sizeof(GridData));

    // ref<Buffer> covariance =
    //     mpDevice->createBuffer(mVoxelCount.x * mVoxelCount.y * mVoxelCount.z * sizeof(Covariance), ResourceBindFlags::UnorderedAccess);
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
    auto gridData = var["GridData"];
    gridData["gridMin"] = mGridMin;
    gridData["voxelSize"] = mVoxelSize;
    gridData["voxelCount"] = mVoxelCount;
    gridData["sampleFrequency"] = mSampleFrequency;

    uint meshCount = mpScene->getMeshCount();
    for (MeshID meshID{0}; meshID.get() < meshCount; ++meshID)
    {
        MeshDesc meshDesc = mpScene->getMesh(meshID);
        uint triangleCount = meshDesc.getTriangleCount();

        auto meshData = mVoxelizationPass->getRootVar()["MeshData"];
        meshData["vertexCount"] = meshDesc.vertexCount;
        meshData["vbOffset"] = meshDesc.vbOffset;
        meshData["triangleCount"] = triangleCount;
        meshData["ibOffset"] = meshDesc.ibOffset;
        meshData["use16BitIndices"] = meshDesc.use16BitIndices();
        meshData["materialID"] = meshDesc.materialID;
        mVoxelizationPass->execute(pRenderContext, uint3(triangleCount, 1, 1));
        pRenderContext->uavBarrier(pDiffuse.get());
    }
    mComplete = true;
}

void VoxelizationPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void VoxelizationPass::renderUI(Gui::Widgets& widget)
{
    static const uint resolutions[] = {16, 32, 64, 128, 256, 512};
    {
        Gui::DropdownList list;
        for (uint32_t i = 0; i < 6; i++)
        {
            list.push_back({resolutions[i], std::to_string(resolutions[i])});
        }
        if (widget.dropdown("Voxel Resolution", list, mVoxelResolution))
        {
            updateVoxelGrid();
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

    widget.text("Voxel Size: " + ToString(mVoxelSize));
    widget.text("Voxel Count: " + ToString(float3(mVoxelCount)));
    widget.text("Grid Min: " + ToString(mGridMin));
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    updateVoxelGrid();
    mVoxelizationPass = nullptr;
    mComplete = false;
}

void VoxelizationPass::updateVoxelGrid()
{
    float3 diag;
    float length;
    float3 center;
    if (mpScene)
    {
        AABB aabb = mpScene->getSceneBounds();
        diag = aabb.maxPoint - aabb.minPoint;
        length = std::max(diag.z, std::max(diag.x, diag.y));
        center = aabb.center();
        diag *= 1.2f;
        length *= 1.2f;
    }
    else
    {
        diag = float3(1);
        length = 1.f;
        center = float3(0);
    }

    mVoxelSize = float3(length / mVoxelResolution);
    float3 temp = diag / mVoxelSize;

    mVoxelCount = uint3(
        (uint)math::ceil(temp.x / minFactor.x) * minFactor.x,
        (uint)math::ceil(temp.y / minFactor.y) * minFactor.y,
        (uint)math::ceil(temp.z / minFactor.z) * minFactor.z
    );
    mGridMin = center - 0.5f * mVoxelSize * float3(mVoxelCount);
}
