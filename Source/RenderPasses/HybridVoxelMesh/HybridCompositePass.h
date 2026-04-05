/***************************************************************************
 # Copyright (c) 2015-24, NVIDIA CORPORATION. All rights reserved.
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
#include "Falcor.h"
#include "Core/Pass/FullScreenPass.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class HybridCompositePass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(HybridCompositePass, "HybridCompositePass", "Hybrid mesh/voxel composition pass.");

    enum class ViewMode : uint32_t
    {
        Composite,
        MeshOnly,
        VoxelOnly,
        BlendMask,
        RouteDebug,
        VoxelDepth,
        VoxelNormal,
        VoxelConfidence,
        VoxelRouteID,
        VoxelInstanceID,
        ObjectMismatch,
        DepthMismatch,
    };

    FALCOR_ENUM_INFO(
        ViewMode,
        {
            {ViewMode::Composite, "Composite"},
            {ViewMode::MeshOnly, "MeshOnly"},
            {ViewMode::VoxelOnly, "VoxelOnly"},
            {ViewMode::BlendMask, "BlendMask"},
            {ViewMode::RouteDebug, "RouteDebug"},
            {ViewMode::VoxelDepth, "VoxelDepth"},
            {ViewMode::VoxelNormal, "VoxelNormal"},
            {ViewMode::VoxelConfidence, "VoxelConfidence"},
            {ViewMode::VoxelRouteID, "VoxelRouteID"},
            {ViewMode::VoxelInstanceID, "VoxelInstanceID"},
            {ViewMode::ObjectMismatch, "ObjectMismatch"},
            {ViewMode::DepthMismatch, "DepthMismatch"},
        }
    );

    static ref<HybridCompositePass> create(ref<Device> pDevice, const Properties& props) { return make_ref<HybridCompositePass>(pDevice, props); }

    HybridCompositePass(ref<Device> pDevice, const Properties& props);

    Properties getProperties() const override;
    RenderPassReflection reflect(const CompileData& compileData) override;
    void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    void renderUI(Gui::Widgets& widget) override;
    void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

    ViewMode getViewMode() const { return mViewMode; }
    void setViewMode(ViewMode mode) { mViewMode = mode; }

private:
    ref<Scene> mpScene;
    ref<FullScreenPass> mpPass;
    ref<Fbo> mpFbo;

    ViewMode mViewMode = ViewMode::Composite;
};

FALCOR_ENUM_REGISTER(HybridCompositePass::ViewMode);
