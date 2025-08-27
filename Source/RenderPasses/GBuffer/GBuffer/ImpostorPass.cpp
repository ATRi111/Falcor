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
#include "ImpostorPass.h"
namespace
{
const std::string kDepthPassProgramFile = "E:/Project/Falcor/Source/RenderPasses/GBuffer/GBuffer/DepthPass.3d.slang";
const std::string kGBufferPassProgramFile = "E:/Project/Falcor/Source/RenderPasses/GBuffer/GBuffer/ImpostorRaster.3d.slang";
const RasterizerState::CullMode kDefaultCullMode = RasterizerState::CullMode::Back;
const ChannelList kImpostorChannels = {
    {"packedFloats", "gPackedFloats", "World normal(x,y), depth, opacity", false, ResourceFormat::RGBA32Float},
    {"packedInts", "gPackedInts", "Material id or counter, uv", false, ResourceFormat::RG32Uint},
};

const std::string kDepthName = "depth";

const std::string kCameraPosition = "cameraPosition";
const std::string kCameraTarget = "cameraTarget";
const std::string kCameraUp = "cameraUp";
const std::string kViewpointIndex = "viewpointIndex";
} // namespace

ImpostorPass::ImpostorPass(ref<Device> pDevice, const Properties& props) : GBuffer(pDevice), mComplete(false)
{
    // Check for required features.
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_2))
        FALCOR_THROW("GBufferRaster requires Shader Model 6.2 support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::Barycentrics))
        FALCOR_THROW("GBufferRaster requires pixel shader barycentrics support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::RasterizerOrderedViews))
        FALCOR_THROW("GBufferRaster requires rasterizer ordered views (ROVs) support.");

    parseProperties(props);

    // Initialize graphics state
    mDepthPass.pState = GraphicsState::create(mpDevice);
    mGBufferPass.pState = GraphicsState::create(mpDevice);

    // Set depth function
    DepthStencilState::Desc dsDesc;
    dsDesc.setDepthFunc(ComparisonFunc::Equal).setDepthWriteMask(false);
    ref<DepthStencilState> pDsState = DepthStencilState::create(dsDesc);
    mGBufferPass.pState->setDepthStencilState(pDsState);

    mpFbo = Fbo::create(mpDevice);
}

RenderPassReflection ImpostorPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;
    const uint2 sz = RenderPassHelpers::calculateIOSize(mOutputSizeSelection, mFixedOutputSize, compileData.defaultTexDims);
    reflector.addInternal(kDepthName, "Depth buffer")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::DepthStencil)
        .texture2D(sz.x, sz.y);

    addRenderPassOutputs(reflector, kImpostorChannels, ResourceBindFlags::RenderTarget, sz);

    return reflector;
}

void ImpostorPass::compile(RenderContext* pRenderContext, const CompileData& compileData)
{
    GBuffer::compile(pRenderContext, compileData);
}

void ImpostorPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mpScene == nullptr)
    {
        return;
    }

    if (mComplete)
    {
        pRenderContext->copyResource(renderData.getTexture("packedFloats").get(), cachedPackedFloats.get());
        pRenderContext->copyResource(renderData.getTexture("packedInts").get(), cachedPackedInts.get());
        return;
    }

    GBuffer::execute(pRenderContext, renderData);
    auto pDepth = renderData.getTexture(kDepthName);
    FALCOR_ASSERT(pDepth);
    updateFrameDim(uint2(pDepth->getWidth(), pDepth->getHeight()));

    pRenderContext->clearDsv(pDepth->getDSV().get(), 1.f, 0);

    const RasterizerState::CullMode cullMode = mForceCullMode ? mCullMode : kDefaultCullMode;

    // Check for scene changes.
    if (is_set(mpScene->getUpdates(), IScene::UpdateFlags::RecompileNeeded))
    {
        recreatePrograms();
    }

    mpScene->selectViewpoint(mViewpointIndex);

    mpScene->update(pRenderContext, 0.);

    // Depth pass.
    {
        // Create depth pass program.
        if (!mDepthPass.pProgram)
        {
            ProgramDesc desc;
            desc.addShaderModules(mpScene->getShaderModules());
            desc.addShaderLibrary(kDepthPassProgramFile).vsEntry("vsMain").psEntry("psMain");
            desc.addTypeConformances(mpScene->getTypeConformances());

            mDepthPass.pProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
            mDepthPass.pState->setProgram(mDepthPass.pProgram);
        }

        // Set program defines.
        mDepthPass.pState->getProgram()->addDefine("USE_ALPHA_TEST", mUseAlphaTest ? "1" : "0");

        // Create program vars.
        if (!mDepthPass.pVars)
            mDepthPass.pVars = ProgramVars::create(mpDevice, mDepthPass.pProgram.get());

        mpFbo->attachDepthStencilTarget(pDepth);
        mDepthPass.pState->setFbo(mpFbo);

        mpScene->rasterize(pRenderContext, mDepthPass.pState.get(), mDepthPass.pVars.get(), cullMode);
    }

    // GBuffer pass.
    {
        // Create GBuffer pass program.
        if (!mGBufferPass.pProgram)
        {
            ProgramDesc desc;
            desc.addShaderModules(mpScene->getShaderModules());
            desc.addShaderLibrary(kGBufferPassProgramFile).vsEntry("vsMain").psEntry("psMain");
            desc.addTypeConformances(mpScene->getTypeConformances());

            mGBufferPass.pProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
            mGBufferPass.pState->setProgram(mGBufferPass.pProgram);
        }

        // Set program defines.
        mGBufferPass.pProgram->addDefine("ADJUST_SHADING_NORMALS", mAdjustShadingNormals ? "1" : "0");
        mGBufferPass.pProgram->addDefine("USE_ALPHA_TEST", mUseAlphaTest ? "1" : "0");

        // For optional I/O resources, set 'is_valid_<name>' defines to inform the program of which ones it can access.
        // mGBufferPass.pProgram->addDefines(getValidResourceDefines(kGBufferChannels, renderData));
        mGBufferPass.pProgram->addDefines(getValidResourceDefines(kImpostorChannels, renderData));

        // Create program vars.
        if (!mGBufferPass.pVars)
            mGBufferPass.pVars = ProgramVars::create(mpDevice, mGBufferPass.pProgram.get());

        auto var = mGBufferPass.pVars->getRootVar();
        var["PerFrameCB"]["gFrameDim"] = mFrameDim;
        // for (size_t i = 0; i < kImpostorChannels.size(); ++i)
        //{
        //     ref<Texture> pTex = getOutput(renderData, kImpostorChannels[i].name);
        //     mpFbo->attachColorTarget(pTex, uint32_t(i));
        // }
        const uint2 size = uint2(pDepth->getWidth(), pDepth->getHeight());
        cachedPackedFloats =
            mpDevice->createTexture2D(size.x, size.y, ResourceFormat::RGBA32Float, 1, 1, nullptr, ResourceBindFlags::RenderTarget);
        cachedPackedInts =
            mpDevice->createTexture2D(size.x, size.y, ResourceFormat::RG32Uint, 1, 1, nullptr, ResourceBindFlags::RenderTarget);

        mpFbo->attachColorTarget(cachedPackedFloats, 0);
        mpFbo->attachColorTarget(cachedPackedInts, 1);

        mGBufferPass.pState->setFbo(mpFbo); // Sets the viewport

        // Rasterize the scene.
        mpScene->rasterize(pRenderContext, mGBufferPass.pState.get(), mGBufferPass.pVars.get(), cullMode);
        pRenderContext->copyResource(renderData.getTexture("packedFloats").get(), cachedPackedFloats.get());
        pRenderContext->copyResource(renderData.getTexture("packedInts").get(), cachedPackedInts.get());
    }
    mComplete = true;
}

void ImpostorPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    GBuffer::setScene(pRenderContext, pScene);
    mComplete = false;
    recreatePrograms();

    if (pScene)
    {
        if (pScene->getMeshVao() && pScene->getMeshVao()->getPrimitiveTopology() != Vao::Topology::TriangleList)
        {
            FALCOR_THROW("GBufferRaster: Requires triangle list geometry due to usage of SV_Barycentrics.");
        }
    }

    pScene->addViewpoint(mViewpoints.position, mViewpoints.target, mViewpoints.up);
}

void ImpostorPass::parseProperties(const Properties& props)
{
    GBuffer::parseProperties(props);
    for (const auto& [key, value] : props)
    {
        if (key == kCameraPosition)
            mViewpoints.position = value;
        if (key == kCameraTarget)
            mViewpoints.target = value;
        if (key == kCameraUp)
            mViewpoints.up = value;
        if (key == kViewpointIndex)
            mViewpointIndex = value;
    }
}

void ImpostorPass::onSceneUpdates(RenderContext* pRenderContext, IScene::UpdateFlags sceneUpdates) {}

void ImpostorPass::recreatePrograms()
{
    mDepthPass.pProgram = nullptr;
    mDepthPass.pVars = nullptr;
    mGBufferPass.pProgram = nullptr;
    mGBufferPass.pVars = nullptr;
}
