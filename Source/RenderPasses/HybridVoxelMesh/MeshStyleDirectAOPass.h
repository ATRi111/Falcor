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

class MeshStyleDirectAOPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(MeshStyleDirectAOPass, "MeshStyleDirectAOPass", "Mesh deterministic direct + AO pass built on top of GBufferRaster outputs.");

    enum class ViewMode : uint32_t
    {
        Combined,
        DirectOnly,
        AOOnly,
    };

    FALCOR_ENUM_INFO(
        ViewMode,
        {
            {ViewMode::Combined, "Combined"},
            {ViewMode::DirectOnly, "DirectOnly"},
            {ViewMode::AOOnly, "AOOnly"},
        }
    );

    static ref<MeshStyleDirectAOPass> create(ref<Device> pDevice, const Properties& props) { return make_ref<MeshStyleDirectAOPass>(pDevice, props); }

    MeshStyleDirectAOPass(ref<Device> pDevice, const Properties& props);

    Properties getProperties() const override;
    RenderPassReflection reflect(const CompileData& compileData) override;
    void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    void renderUI(Gui::Widgets& widget) override;
    void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;

    ViewMode getViewMode() const { return mViewMode; }
    void setViewMode(ViewMode mode) { mViewMode = mode; }

    float getShadowBias() const { return mShadowBias; }
    void setShadowBias(float value) { mShadowBias = std::max(0.0f, value); }

    bool getRenderBackground() const { return mRenderBackground; }
    void setRenderBackground(bool value) { mRenderBackground = value; }

    bool getAOEnabled() const { return mAOEnabled; }
    void setAOEnabled(bool value) { mAOEnabled = value; }

    float getAOStrength() const { return mAOStrength; }
    void setAOStrength(float value) { mAOStrength = std::clamp(value, 0.0f, 1.0f); }

    float getAORadius() const { return mAORadius; }
    void setAORadius(float value) { mAORadius = std::max(0.001f, value); }

    uint32_t getAOStepCount() const { return mAOStepCount; }
    void setAOStepCount(uint32_t value) { mAOStepCount = std::max(1u, value); }

    uint32_t getAODirectionSet() const { return mAODirectionSet; }
    void setAODirectionSet(uint32_t value) { mAODirectionSet = value >= 6 ? 6u : 4u; }

    float getAOContactStrength() const { return mAOContactStrength; }
    void setAOContactStrength(float value) { mAOContactStrength = std::max(0.0f, value); }

    bool getAOUseStableRotation() const { return mAOUseStableRotation; }
    void setAOUseStableRotation(bool value) { mAOUseStableRotation = value; }

private:
    ref<Scene> mpScene;
    ref<FullScreenPass> mpPass;
    ref<Fbo> mpFbo;

    ViewMode mViewMode = ViewMode::Combined;
    float mShadowBias = 0.001f;
    bool mRenderBackground = true;
    bool mAOEnabled = true;
    float mAOStrength = 0.55f;
    float mAORadius = 0.18f;
    uint32_t mAOStepCount = 3;
    uint32_t mAODirectionSet = 6;
    float mAOContactStrength = 0.75f;
    bool mAOUseStableRotation = true;
};

FALCOR_ENUM_REGISTER(MeshStyleDirectAOPass::ViewMode);
