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
#include "Scene/VertexAttrib.slangh"

import Scene.Raster;
import Utils.Math.MathHelpers;
import GBufferHelpers;
import Rendering.Materials.TexLODHelpers;

cbuffer PerFrameCB
{
    uint2 gFrameDim;
};

// GBuffer channels
struct GBufferPSOut
{
    float4 gPackedNDO : SV_TARGET0;
    float4 gPackedMCR : SV_TARGET1;
};

#define is_valid(name) (is_valid_##name != 0)

VSOut vsMain(VSIn vsIn)
{
    return defaultVS(vsIn);
}

float2 normalToOctoUV(float3 n)
{
    float2 p = float2(n.x, n.y) / dot(float3(1, 1, 1), n);
    if (n.z < 0)
        p = (1.0 - abs(p.yx)) * sign(p.xy);
    return p * 0.5 + 0.5;
}

[earlydepthstencil]
GBufferPSOut psMain(VSOut vsOut, uint triangleIndex: SV_PrimitiveID, float3 barycentrics: SV_Barycentrics)
{
    // Using vOut.posH.xy as pixel coordinate since it has the SV_Position semantic.
    int2 ipos = int2(vsOut.posH.xy);

    float3 faceNormal = gScene.getFaceNormalW(vsOut.instanceID, triangleIndex);
    VertexData v = prepareVertexData(vsOut, faceNormal);
    let lod = ImplicitLodTextureSampler();

#if USE_ALPHA_TEST
    if (gScene.materials.alphaTest(v, vsOut.materialID, lod))
        discard;
#endif
    const float3 viewDir = normalize(gScene.camera.getPosition() - v.posW);
    ShadingData sd = gScene.materials.prepareShadingData(v, vsOut.materialID, viewDir);

    uint hints = 0;
#if ADJUST_SHADING_NORMALS
    hints |= (uint)MaterialInstanceHints::AdjustShadingNormal;
#endif

    // Create material instance and query its properties.
    let mi = gScene.materials.getMaterialInstance(sd, lod, hints);
    let bsdfProperties = mi.getProperties(sd);

    const GBufferData gbuf = prepareGBufferData(sd, v, mi, bsdfProperties);

    const float4 texGrads = float4(ddx(sd.uv), ddy(sd.uv));

    GBufferPSOut psOut = {};

    float2 octo = normalToOctoUV(gbuf.normW.xyz);
    psOut.gPackedNDO = float4(octo.x, octo.y, vsOut.posH.z, gbuf.diffuseOpacity.w);
    psOut.gPackedMCR = float4(asfloat(gbuf.mtlData.x), gbuf.texC.x, gbuf.texC.y, 0);

    return psOut;
}
