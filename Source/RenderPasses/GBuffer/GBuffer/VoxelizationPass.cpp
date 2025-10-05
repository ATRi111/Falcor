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
const std::string kMipOMProgramFile = "E:/Project/Falcor/Source/RenderPasses/GBuffer/GBuffer/MipOMGenerator.cs.slang";
const std::string kOutputOM = "OM";
const std::string kOutputMipOM = "mipOM";
const std::string kOutputGridData = "gridData";
const std::string kOutputColor = "color";

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
    mVoxelPerBit = uint3(4, 4, 4);
    minFactor = uint3(4, 2, 4) * mVoxelPerBit;

    updateVoxelGrid();

    mVoxelizationPass.pState = GraphicsState::create(mpDevice);
    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);

    mpFbo = Fbo::create(mpDevice);
}

RenderPassReflection VoxelizationPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addOutput(kOutputOM, "Occupancy Map")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::R32Uint)
        .texture3D(mVoxelCount.x, mVoxelCount.y, mVoxelCount.z, 1);
    reflector.addOutput(kOutputMipOM, "Mip Occupancy Map")
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::R32Uint)
        .texture3D(mMipOMSize.x, mMipOMSize.y, mMipOMSize.z, 1);

    reflector.addOutput(kOutputGridData, "Grid Data")
        .bindFlags(ResourceBindFlags::Constant)
        .format(ResourceFormat::Unknown)
        .rawBuffer(sizeof(GridData));
    reflector.addOutput(kOutputColor, "Color")
        .bindFlags(ResourceBindFlags::RenderTarget)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1, 1);

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
    ref<Texture> pOM = renderData.getTexture(kOutputOM);
    ref<Texture> pMipOM = renderData.getTexture(kOutputMipOM);
    ref<Texture> pAlpha = renderData.getTexture(kOutputColor);
    pRenderContext->clearFbo(mpFbo.get(), float4(0), 1.f, 0, FboAttachmentType::Color);

    GridData data = {mGridMin, mVoxelSize, mVoxelCount, mMipOMSize, mVoxelPerBit};
    pGridData->setBlob(&data, 0, sizeof(GridData));
    pRenderContext->clearUAV(pOM->getUAV().get(), uint4(0));

    {
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
        var["gOM"] = pOM;
        var["GridData"]["gridMin"] = mGridMin;
        var["GridData"]["voxelSize"] = mVoxelSize;
        var["GridData"]["voxelCount"] = mVoxelCount;

        mpFbo->attachColorTarget(pAlpha, 0);
        mVoxelizationPass.pState->setFbo(mpFbo);
        mpScene->rasterize(pRenderContext, mVoxelizationPass.pState.get(), mVoxelizationPass.pVars.get(), mCullMode);
    }
    {
        if (!mipOMPass)
        {
            ProgramDesc desc;
            desc.addShaderModules(mpScene->getShaderModules());
            desc.addShaderLibrary(kMipOMProgramFile).csEntry("main");
            // desc.addTypeConformances(mpScene->getTypeConformances());

            DefineList defines;
            defines.add(mpScene->getSceneDefines());
            defines.add(mpSampleGenerator->getDefines());
            // defines.add(getShaderDefines(renderData));

            mipOMPass = ComputePass::create(mpDevice, desc, defines, true);
        }
        ShaderVar var = mipOMPass->getRootVar();
        var["gOM"] = pOM;
        var["gMipOM"] = pMipOM;
        var["GridData"]["voxelCount"] = mVoxelCount;
        var["GridData"]["voxelPerBit"] = mVoxelPerBit;

        mipOMPass->execute(pRenderContext, mMipOMSize * uint3(4, 2, 4));
    }
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
    widget.text("MipOM Size: " + ToString(float3(mMipOMSize)));
}

void VoxelizationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    GBuffer::setScene(pRenderContext, pScene);
    mpScene = pScene;
    recreatePrograms();
    updateVoxelGrid();
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
    mMipOMSize = mVoxelCount / minFactor;
}

void VoxelizationPass::recreatePrograms()
{
    mVoxelizationPass.pVars = nullptr;
    mVoxelizationPass.pProgram = nullptr;
}
