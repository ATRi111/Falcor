import Scene.Raster;
import Utils.Math.MathHelpers;
import Rendering.Materials.TexLODHelpers;

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
    float4x4 invVP;        // 生成G-buffer所用相机的invVP
    float4x4 extendMatrix; // 当前纹理坐标到G-Buffer纹理坐标的变换矩阵(取左上角3x3)
    uint lowerLevel;
    float t;
};

struct PsOut
{
    float4 color : SV_Target0;
    float4 posW : SV_Target1;
    float2 GBufferUV : SV_Target2;
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
    float3 diffL = max(0, dot(l, n)) * diff * lightColor;
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

float3 calcView(float2 texCoord, float depth)
{
    float4 NDC = float4(2 * texCoord.x - 1, 1 - 2 * texCoord.y, depth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posW = temp / temp.w;
    return normalize(cameraPosW - posW.xyz);
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut ret = {};
    float3 coord = float3(texCoord, 1);
    float3x3 matrix = float3x3(extendMatrix);
    float3 GBufferCoord = mul(matrix, coord);
    float4 higherNDO = gFilteredNDO.SampleLevel(gPointSampler, GBufferCoord.xy, lowerLevel + 1);
    float4 lowerNDO = gFilteredNDO.SampleLevel(gPointSampler, GBufferCoord.xy, lowerLevel);
    float4 higherMCR = gFilteredMCR.SampleLevel(gPointSampler, GBufferCoord.xy, lowerLevel + 1);
    float4 lowerMCR = gFilteredMCR.SampleLevel(gPointSampler, GBufferCoord.xy, lowerLevel);

    bool[2] valids;
    float3[2] normals;
    float[2] depths;
    float3[2] diffs;
    float3[2] specs;
    float3[2] emmsives;
    float[2] roughnesss;
    float3[2] colors;
    float[2] opacitys;
    float3[2] views;
    float ambient = 0.02;

    if (lowerNDO.w != 0 && t != 1)
    {
        diffs[0] = 0.1;
        specs[0] = 0.9;
        roughnesss[0] = 0.5;
        emmsives[0] = 0;
        normals[0] = octoUVToNormal(lowerNDO.xy);
        depths[0] = lowerNDO.z;
        opacitys[0] = lowerNDO.w;
        valids[0] = true;
        views[0] = calcView(GBufferCoord.xy, lowerNDO.z);

        float4 NDC = float4(2 * GBufferCoord.x - 1, 1 - 2 * GBufferCoord.y, lowerNDO.z, 1);
        float4 temp = mul(invVP, NDC);
        ret.posW = temp / temp.w;
        ret.GBufferUV = GBufferCoord.xy;
    }
    else
    {
        ret.posW = 0;
        ret.GBufferUV = 0;
        valids[0] = false;
    }

    if (higherNDO.w != 0 && t != 0)
    {
        diffs[1] = 0.1;
        specs[1] = 0.9;
        roughnesss[1] = 0.5;
        emmsives[1] = 0;
        normals[1] = octoUVToNormal(higherNDO.xy);
        depths[1] = higherNDO.z;
        opacitys[1] = higherNDO.w;
        valids[1] = true;
        views[1] = calcView(GBufferCoord.xy, higherNDO.z);
    }
    else
    {
        valids[1] = false;
    }

    for (uint i = 0; i < 2; i++)
    {
        if (valids[i])
        {
            colors[i] = ambient + Shading(views[i], normals[i], diffs[i], specs[i], roughnesss[i]);
            colors[i] *= opacitys[i];
        }
        else
            colors[i] = 0;
    }

    float3 color = lerp(colors[0], colors[1], t);
    ret.color = float4(color, 1);
    return ret;
}
