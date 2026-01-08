#include "Shading.slang"
import Scene.SceneTypes;
import Scene.Scene;
import Scene.Lights.EnvMap;
import Rendering.Lights.EnvMapSampler;
import Rendering.Lights.EmissivePowerSampler;
import Rendering.Lights.EmissiveLightSamplerInterface;
import Utils.Sampling.SampleGeneratorInterface;

#define LIGHT_TYPES 3
#define MAX_LIGHT_COUNT 4

ParameterBlock<EmissivePowerSampler> gEmissiveSampler;
ParameterBlock<EnvMapSampler> gEnvMapSampler;

struct LightSample
{
    float3 l;
    float3 h;
    float distance;
    float3 lightColor;  //对于点光源和有向光，表示光照度；对于其他光源，表示亮度 
    float pdf;
};

bool inline sampleGeneralLight<S : ISampleGenerator>(float3 posW, float3 v, PrimitiveBSDF BSDF, inout S sg, inout LightSample ls)
{
    uint lightCount = min(gScene.lightCount, MAX_LIGHT_COUNT - 1);
    float totalIlluminance = 0;

    float3 lightColor = 0;
    float maxDistance = 0;

    float3[MAX_LIGHT_COUNT] lightColors;
    float[MAX_LIGHT_COUNT] illuminances;
    float3[MAX_LIGHT_COUNT] dirs;
    float[MAX_LIGHT_COUNT] maxDistances;

    for (uint i = 0; i < lightCount; i++)
    {
        LightData light = gScene.getLight(i);
        switch (light.type)
        {
        case LightType::Point:
            float3 toL = light.posW - posW;
            dirs[i] = normalize(toL);
            maxDistances[i] = length(toL);
            float sqrDistance = max(dot(toL, toL), 1e-4f);

            float spot = 1.0f;
            if (light.openingAngle < PI)
            {
                float cosTerm = dot(light.dirW, -dirs[i]);
                float cosOuter = light.cosOpeningAngle;
                float innerAng = max(light.openingAngle - light.penumbraAngle, 0.0f);
                float cosInner = cos(innerAng);

                float t = saturate((cosTerm - cosOuter) / max(cosInner - cosOuter, 1e-6f));
                spot = t * t * (3.0f - 2.0f * t);

                if (light.penumbraAngle <= 0.0f)
                    spot = (cosTerm >= cosOuter) ? 1.0f : 0.0f;
            }
            lightColors[i] = light.intensity * spot / sqrDistance;
            break;
        case LightType::Directional:
            dirs[i] = -light.dirW;
            lightColors[i] = light.intensity;
            maxDistances[i] = -1;
            break;
        }
        illuminances[i] = (lightColors[i].x + lightColors[i].y + lightColors[i].z);
        totalIlluminance += illuminances[i];
    }

    if (totalIlluminance == 0)
        return false;

    float r = Next(sg) * totalIlluminance;
    uint selected = lightCount;
    for (uint i = 0; i < lightCount; i++)
    {
        if (illuminances[i] > 0)
        {
            r -= illuminances[i];
            if (r <= 0)
            {
                selected = i;
                break;
            }
        }
    }
    if (selected >= lightCount)
        return false;
    ls.lightColor = lightColors[selected];
    ls.l = dirs[selected];
    ls.h = normalizeSafe(ls.l + v);
    ls.distance = maxDistances[selected];
    ls.pdf = illuminances[selected] / totalIlluminance;
    return true;
}

bool inline sampleEmmisive<S : ISampleGenerator>(float3 posW, float3 v, PrimitiveBSDF BSDF, inout S sg, inout LightSample ls)
{
    TriangleLightSample tls;
    bool valid = gEmissiveSampler.sampleLight(posW, float3(0, 0, 1), true, sg, tls);
    if (!valid)
        return false;
    ls.l = tls.dir;
    ls.h = normalizeSafe(ls.l + v);
    ls.distance = tls.distance;
    ls.lightColor = tls.Le;
    ls.pdf = tls.pdf;
    return true;
}

bool inline sampleEnvMap<S : ISampleGenerator>(float3 posW, float3 v, PrimitiveBSDF BSDF, inout S sg, inout LightSample ls)
{
    SurfaceBRDF BRDF = BSDF.surface;   //采样光源时不考虑delta lobe
    float bsdfWeight = BRDF.calcBRDFWeight();
    ls.pdf = 0;

    if (Next(sg) <= bsdfWeight)
    {
        BRDF.sample(v, ls.l, ls.h, sg);
    }
    else
    {
        EnvMapSample envSample;
        gEnvMapSampler.sample(Next2(sg), envSample);
        ls.l = envSample.dir;
        ls.h = normalizeSafe(ls.l + v);
    }
    if (bsdfWeight > 0)
        ls.pdf += bsdfWeight * BRDF.evalPdf(ls.l, v, ls.h);
    if (bsdfWeight < 1)
        ls.pdf += (1 - bsdfWeight) * gEnvMapSampler.evalPdf(ls.l);

    ls.lightColor = gEnvMapSampler.eval(ls.l);
    return true;
}

inline bool sampleLight<S : ISampleGenerator>(float3 posW, float3 v, PrimitiveBSDF BSDF, inout S sg, inout LightSample ls)
{
    float weights[LIGHT_TYPES]; // 一般光源，环境光，自发光
    weights[0] = gScene.getLightCount() > 0 ? 1 : 0;
#if USE_ENV_MAP
    weights[1] = 1;
#else
    weights[1] = 0;
#endif
#if USE_EMISSIVE_LIGHTS
    weights[2] = 1;
#else
    weights[2] = 0;
#endif
    float totalWeights = weights[0] + weights[1] + weights[2];
    if (totalWeights <= 0)
        return false;

    float r = Next(sg) * totalWeights;
    uint selected = 3;
    for (int i = 0; i < LIGHT_TYPES; ++i)
    {
        if (weights[i] <= 0)
            continue;
        r -= weights[i];
        if (r <= 0)
        {
            selected = i;
            break;
        }
    }
    if (selected >= LIGHT_TYPES)
        return false;
    float selectionPdf = weights[selected] / totalWeights;

    bool valid = false;
    switch (selected)
    {
    case 0:
        valid = sampleGeneralLight(posW, v, BSDF, sg, ls);
        break;
    case 1:
#if USE_ENV_MAP
        valid = sampleEnvMap(posW, v, BSDF, sg, ls);
#endif
        break;
    case 2:
#if USE_EMISSIVE_LIGHTS
        valid = sampleEmmisive(posW, v, BSDF, sg, ls);
#endif
        break;
    }
    if (!valid)
        return false;
    ls.pdf *= selectionPdf;
    return true;
}
