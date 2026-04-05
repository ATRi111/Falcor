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

class HybridBlendMaskPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(HybridBlendMaskPass, "HybridBlendMaskPass", "Route-aware mesh/voxel hybrid blend mask.");

    static ref<HybridBlendMaskPass> create(ref<Device> pDevice, const Properties& props) { return make_ref<HybridBlendMaskPass>(pDevice, props); }

    HybridBlendMaskPass(ref<Device> pDevice, const Properties& props);

    Properties getProperties() const override;
    RenderPassReflection reflect(const CompileData& compileData) override;
    void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    void renderUI(Gui::Widgets& widget) override;
    void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

    float getBlendStartDistance() const { return mBlendStartDistance; }
    void setBlendStartDistance(float value) { mBlendStartDistance = std::max(0.0f, value); }

    float getBlendEndDistance() const { return mBlendEndDistance; }
    void setBlendEndDistance(float value) { mBlendEndDistance = std::max(0.0f, value); }

    float getBlendExponent() const { return mBlendExponent; }
    void setBlendExponent(float value) { mBlendExponent = std::max(0.01f, value); }

private:
    ref<Scene> mpScene;
    ref<FullScreenPass> mpPass;
    ref<Fbo> mpFbo;

    float mBlendStartDistance = 1.50f;
    float mBlendEndDistance = 3.25f;
    float mBlendExponent = 1.0f;
};
