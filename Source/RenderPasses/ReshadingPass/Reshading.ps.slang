#include "Scene/VertexAttrib.slangh"

import Scene.Raster;
import Utils.Math.MathHelpers;
import Rendering.Materials.TexLODHelpers;
import Scene.SceneTypes;
import Scene.ShadingData;
import Rendering.Materials.IMaterialInstance;
import Utils.Math.FormatConversion;
__exported import Rendering.Materials.StandardMaterial;
__exported import Scene.Material.ShadingUtils;

Texture2D<float4> gFilteredNDO;
Texture2D<float4> gFilteredMCR;
SamplerState gPointSampler;

cbuffer DirectionalLightCB
{
    float3 lightPosW;
    float3 lightColor;
    float3 lightDirW;
};

cbuffer CB
{
    float3 cameraPosW;
    float4x4 invVP;
};

struct PsOut
{
    float4 color : SV_Target0;
    float4 posW : SV_Target1;
    float4 materialID : SV_Target2;
    float2 materialUV : SV_Target3;
};

float NDC_GGX(float3 n, float3 h, float rough)
{
    float Pi = 3.14159265359;
    float rough2 = rough * rough;
    float temp = dot(n, h) * dot(n, h) * (rough2 - 1) + 1;
    return rough2 / Pi / temp / temp;
}
float3 Fresnel(float3 v, float3 h, float3 spec)
{
    return spec + (1 - spec) * pow(1 - dot(v, h), 5);
}
float SchlickGGX(float3 n, float3 x, float rough)
{
    float k = (rough + 1) * (rough + 1) / 8;
    float temp = max(0, dot(n, x));
    return temp / (temp * (1 - k) + k);
}
float SMT_SMITH(float3 n, float3 l, float3 v, float rough)
{
    return SchlickGGX(n, v, rough) * SchlickGGX(n, l, rough);
}
float3 Shading(float3 v, float3 n, float3 diff, float3 spec, float rough)
{
    float3 l = -lightDirW;
    float3 h = normalize(l + v);
    float3 diffL = (1 - Fresnel(v, h, spec)) * max(0, dot(l, n)) * diff * lightColor;
    float3 specL = NDC_GGX(n, h, rough) * Fresnel(v, h, spec) * SMT_SMITH(n, l, v, rough) / 4 / max(0.001, dot(n, v)) * lightColor;
    return diffL + specL;
}

float3 octoUVToNormal(float2 uv)
{
    float2 p = uv * 2 - 1;
    float3 n = float3(p, 1 - dot(1, abs(p)));
    if (n.z < 0)
    {
        n.xy = (1 - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

float3 calcPosW(float2 texCoord, float depth)
{
    float4 NDC = float4(2 * texCoord.x - 1, 1 - 2 * texCoord.y, depth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posW = temp / temp.w;
    return posW.xyz;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut ret = {};

    float4 NDO = gFilteredNDO.Sample(gPointSampler, texCoord.xy);
    float4 MCR = gFilteredMCR.Sample(gPointSampler, texCoord.xy);
    float3 color;

    float ambient = 0.02;
    float3 normal = octoUVToNormal(NDO.xy);
    float3 posW = calcPosW(texCoord, NDO.z);
    float3 view = normalize(cameraPosW - posW);
    float2 uv = MCR.yz;
    float opacity = NDO.w;
    if (opacity == 0)
        discard;

    float3 diff;
    float3 spec;
    float roughness;
    float3 emmision;

    #if DEBUG
    float3 dpdx = ddx(posW);
    float3 dpdy = ddy(posW);
    float2 duvdx = ddx(uv);
    float2 duvdy = ddy(uv);
    float3 tangent = (duvdy.y * dpdx - duvdx.y * dpdy) / (duvdx.x * duvdy.y - duvdy.x * duvdx.y);
    tangent = normalize(tangent - normal * dot(normal, tangent));
    float3 bitangent = cross(normal, tangent);
    float handiness = (dot(cross(normal, tangent), bitangent) > 0.0) ? 1.0 : -1.0;

    VertexData v = {};
    v.normalW = normal;
    v.texC = MCR.yz;
    v.posW = posW;
    v.faceNormalW = normalize(cross(dpdx, dpdy));
    v.tangentW = float4(tangent, handiness);
    ShadingData sd = gScene.materials.prepareShadingData(v, asuint(MCR.x), view);
    let lod = ImplicitLodTextureSampler();
    let mi = gScene.materials.getMaterialInstance(sd, lod, 0);
    BSDFProperties bsdf = mi.getProperties(sd);

    diff = float3(bsdf.diffuseReflectionAlbedo);
    spec = float3(bsdf.specularReflectance);
    roughness = bsdf.roughness;
    emmision = bsdf.emission;
#else
    diff = 0.9;
    spec = 0.9;
    roughness = 0.2;
    emmision = 0;
#endif

    color = ambient + emmision + Shading(view, normal, diff, spec, roughness);
    // color *= opacity;

    if (NDO.w != 0)
    {
        ret.posW = float4(calcPosW(texCoord, NDO.z), 1);
        uint ID = asuint(MCR.x);
        ret.materialID = 1 - float4(ID & 4, ID & 2, ID & 1, 1);
        ret.materialUV = MCR.yz;
    }
    else
    {
        ret.posW = 0;
        ret.materialID = 0;
        ret.materialUV = 0;
    }

    ret.color = float4(color, 1);
    return ret;
}
