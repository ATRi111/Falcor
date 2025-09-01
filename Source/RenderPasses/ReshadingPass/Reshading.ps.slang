Texture2D<float4> gFilteredNDO;
Texture2D<float4> gFilteredMCR;
SamplerState gSampler;

cbuffer DirectionalLightCB
{
    float3 lightPosW;
    float3 lightColor;
    float3 lightDirW;
};

cbuffer CameraCB
{
    float3 cameraPosW;
    float4x4 invVP;
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

float4 main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION) : SV_TARGET
{
    float4 NDO = gFilteredNDO.Sample(gSampler, texCoord);
    if (NDO.w == 0)
        discard;
    float2 octoUV = NDO.xy;
    float4 NDC = float4(texCoord * 2 - 1, NDO.z, 1);
    float4 temp = mul(invVP, NDC);
    float4 posW = temp / temp.w;
    float3 normal = octoUVToNormal(octoUV);
    float3 viewW = normalize(cameraPosW - posW.xyz);
    float3 diff = float3(0.2, 0.2, 0.2);
    float3 spec = float3(0.8, 0.8, 0.8);
    float roughness = 0.1;
    float3 emissive = 0;

    float3 dirL = 0;
    float3 pointL = 0;

    dirL = Shading(viewW, normal, diff, spec, roughness);

    return float4(dirL + pointL + emissive, 1);
}
