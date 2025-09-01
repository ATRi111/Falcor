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

struct Viewpoint
{
    float3 position;
    float3 target;
    float3 up;
    float cameraSize;

    Viewpoint()
    {
        position = float3(0, 0, 0);
        target = float3(1, 0, 0);
        up = float3(0, 1, 0);
        cameraSize = 0;
    }
};

class ImpostorPass : public GBuffer
{
public:
    FALCOR_PLUGIN_CLASS(ImpostorPass, "ImpostorPass", "Impostor generation pass.");

    static ref<ImpostorPass> create(ref<Device> pDevice, const Properties& props) { return make_ref<ImpostorPass>(pDevice, props); }

    ImpostorPass(ref<Device> pDevice, const Properties& props);

    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual void parseProperties(const Properties& props) override;
    void onSceneUpdates(RenderContext* pRenderContext, IScene::UpdateFlags sceneUpdates) override;

private:
    void recreatePrograms();
    void calculateViewPoint(float3 min, float3 max, uint32_t index);

    bool mComplete;

    Viewpoint mViewpoint;
    float4x4 invVP;
    uint32_t mViewpointIndex;
    float aspectRatio;

    std::vector<float3> mViewDirections;

    ref<Fbo> mpFbo;

    ref<Texture> cachedPackedNDO;
    ref<Texture> cachedPackedMCR;

    struct
    {
        ref<GraphicsState> pState;
        ref<Program> pProgram;
        ref<ProgramVars> pVars;
    } mDepthPass;

    // Rasterization resources
    struct
    {
        ref<GraphicsState> pState;
        ref<Program> pProgram;
        ref<ProgramVars> pVars;
    } mGBufferPass;
};
