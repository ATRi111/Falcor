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
#pragma once
#include "GBuffer.h"
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

struct GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
    uint3 mipOMSize;
    uint3 voxelPerBit;
};

class VoxelizationPass : public GBuffer
{
public:
    FALCOR_PLUGIN_CLASS(VoxelizationPass, "VoxelizationPass", "Insert pass description here.");

    static ref<VoxelizationPass> create(ref<Device> pDevice, const Properties& props) { return make_ref<VoxelizationPass>(pDevice, props); }

    VoxelizationPass(ref<Device> pDevice, const Properties& props);

    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

private:
    void updateVoxelGrid();
    void recreatePrograms();
    struct
    {
        ref<GraphicsState> pState;
        ref<Program> pProgram;
        ref<ProgramVars> pVars;
    } mVoxelizationPass;

    ref<ComputePass> mipOMPass;

    ref<SampleGenerator> mpSampleGenerator;
    ref<Fbo> mpFbo;
    ref<Scene> mpScene;
    uint mVoxelResolution; // X,Y,Z三个方向中，最长的边被划分的体素数量
    uint3 mVoxelCount;
    float3 mVoxelSize;
    float3 mGridMin;

    uint3 mVoxelPerBit; // mipOM的每个体素中的1bit对应OM中mVoxelPerBit个体素
    uint3 minFactor;    // OM的尺寸必须是minFactor的整数倍
    uint3 mMipOMSize;
};
