/*** Object-level hybrid mesh/voxel composition for plan5 Phase4. ***/

import Scene.Scene;
import Scene.HitInfo;
import Scene.SceneTypes;
import Utils.Math.MathHelpers;

Texture2D<float4> gMeshColor;
Texture2D<float4> gMeshPosW;
Texture2D<float4> gVoxelColor;
Texture2D<float4> gBlendMask;
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float> gVoxelDepth;
Texture2D<float4> gVoxelNormal;
Texture2D<float> gVoxelConfidence;
Texture2D<uint> gVoxelInstanceID;

cbuffer PerFrameCB
{
    uint gViewMode;
};

static const uint kViewModeComposite = 0;
static const uint kViewModeMeshOnly = 1;
static const uint kViewModeVoxelOnly = 2;
static const uint kViewModeBlendMask = 3;
static const uint kViewModeRouteDebug = 4;
static const uint kViewModeVoxelDepth = 5;
static const uint kViewModeVoxelNormal = 6;
static const uint kViewModeVoxelConfidence = 7;
static const uint kViewModeVoxelRouteID = 8;
static const uint kViewModeVoxelInstanceID = 9;
static const uint kViewModeObjectMismatch = 10;
static const uint kViewModeDepthMismatch = 11;
static const uint kInvalidVoxelInstanceID = 0xffffffffu;
static const float kMinDepthTolerance = 0.20f;
static const float kRelativeDepthTolerance = 0.05f;

struct CompositeState
{
    bool meshHitValid;
    GeometryInstanceRenderRoute route;
    uint meshInstanceID;
    float meshDepth;

    bool voxelHitValid;
    bool voxelIdentityValid;
    uint voxelInstanceID;
    float voxelDepth;
    float voxelConfidence;

    float baseMeshWeight;
    float effectiveMeshWeight;
    float effectiveVoxelWeight;
    float depthAgreement;

    bool objectMatch;
    bool objectMismatch;
};

float3 getRouteDebugColor(GeometryInstanceRenderRoute route)
{
    switch (route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        return float3(1.00f, 0.36f, 0.12f);
    case GeometryInstanceRenderRoute::VoxelOnly:
        return float3(0.12f, 0.68f, 1.00f);
    case GeometryInstanceRenderRoute::Blend:
    default:
        return float3(0.22f, 0.94f, 0.38f);
    }
}

float3 safeNormalizeDebug(float3 value)
{
    const float len2 = dot(value, value);
    return len2 > 1e-6f ? value * rsqrt(len2) : 0.f;
}

float getVoxelConfidence(int2 pixelPos)
{
    return saturate(gVoxelConfidence.Load(int3(pixelPos, 0)));
}

bool getVoxelIdentity(int2 pixelPos, out uint instanceID, out float confidence)
{
    confidence = getVoxelConfidence(pixelPos);
    instanceID = gVoxelInstanceID.Load(int3(pixelPos, 0));
    return instanceID != kInvalidVoxelInstanceID && confidence > 0.f;
}

float evalMeshDepth(int2 pixelPos, out bool isValid)
{
    const float4 meshPosW = gMeshPosW.Load(int3(pixelPos, 0));
    isValid = meshPosW.w > 0.f;
    if (!isValid)
        return 0.f;

    return length(meshPosW.xyz - gScene.camera.getPosition());
}

float evalDepthTolerance(float meshDepth, float voxelDepth)
{
    return max(kMinDepthTolerance, kRelativeDepthTolerance * max(meshDepth, voxelDepth));
}

float evalDepthAgreement(float meshDepth, float voxelDepth)
{
    if (meshDepth <= 0.f || voxelDepth <= 0.f)
        return 0.f;

    const float tolerance = evalDepthTolerance(meshDepth, voxelDepth);
    return saturate(1.f - abs(meshDepth - voxelDepth) / tolerance);
}

float3 evalVoxelDepthDebugColor(int2 pixelPos)
{
    const float depth = gVoxelDepth.Load(int3(pixelPos, 0));
    if (depth <= 0.f)
        return 0.f;

    const float mappedDepth = 1.f - exp(-depth / 6.f);
    return mappedDepth.xxx;
}

float3 evalVoxelNormalDebugColor(int2 pixelPos)
{
    const float confidence = getVoxelConfidence(pixelPos);
    if (confidence <= 0.f)
        return 0.f;

    const float3 normal = safeNormalizeDebug(gVoxelNormal.Load(int3(pixelPos, 0)).xyz);
    return normal * 0.5f + 0.5f;
}

float3 evalVoxelConfidenceDebugColor(int2 pixelPos)
{
    const float confidence = getVoxelConfidence(pixelPos);
    return lerp(float3(0.14f, 0.05f, 0.03f), float3(0.20f, 0.94f, 0.38f), confidence);
}

float3 evalVoxelRouteDebugColor(int2 pixelPos)
{
    uint instanceID = kInvalidVoxelInstanceID;
    float confidence = 0.f;
    if (!getVoxelIdentity(pixelPos, instanceID, confidence))
        return 0.f;

    const GeometryInstanceID geometryInstanceID = { instanceID };
    const float3 routeColor = getRouteDebugColor(gScene.getGeometryInstanceRenderRoute(geometryInstanceID));
    return lerp(float3(0.08f, 0.08f, 0.08f), routeColor, max(confidence, 0.25f));
}

float3 hashInstanceColor(uint instanceID)
{
    float3 p = frac(float(instanceID) * float3(0.1031f, 0.11369f, 0.13787f));
    p += dot(p, p.yzx + 19.19f);
    return frac((p.xxy + p.yzz) * p.zyx);
}

float3 evalVoxelInstanceDebugColor(int2 pixelPos)
{
    uint instanceID = kInvalidVoxelInstanceID;
    float confidence = 0.f;
    if (!getVoxelIdentity(pixelPos, instanceID, confidence))
        return 0.f;

    return lerp(float3(0.06f, 0.06f, 0.06f), hashInstanceColor(instanceID), max(confidence, 0.25f));
}

CompositeState evalCompositeState(int2 pixelPos)
{
    CompositeState state = {};
    state.route = GeometryInstanceRenderRoute::Blend;
    state.baseMeshWeight = saturate(gBlendMask.Load(int3(pixelPos, 0)).x);
    state.voxelDepth = gVoxelDepth.Load(int3(pixelPos, 0));
    state.voxelHitValid = state.voxelDepth > 0.f;
    state.voxelConfidence = getVoxelConfidence(pixelPos);
    state.voxelInstanceID = gVoxelInstanceID.Load(int3(pixelPos, 0));
    state.voxelIdentityValid = state.voxelHitValid && state.voxelInstanceID != kInvalidVoxelInstanceID && state.voxelConfidence > 0.f;

    const HitInfo meshHit = HitInfo(gVBuffer.Load(int3(pixelPos, 0)));
    if (meshHit.isValid())
    {
        state.meshDepth = evalMeshDepth(pixelPos, state.meshHitValid);
        if (state.meshHitValid)
        {
            state.meshInstanceID = meshHit.getInstanceID().index;
            state.route = gScene.getGeometryInstanceRenderRoute(meshHit.getInstanceID());
        }
    }

    state.depthAgreement = (state.meshHitValid && state.voxelHitValid) ? evalDepthAgreement(state.meshDepth, state.voxelDepth) : 0.f;
    state.objectMatch = state.meshHitValid && state.voxelIdentityValid && state.meshInstanceID == state.voxelInstanceID;
    state.objectMismatch = state.meshHitValid && state.voxelIdentityValid && state.meshInstanceID != state.voxelInstanceID;

    switch (state.route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        state.effectiveMeshWeight = 1.f;
        state.effectiveVoxelWeight = 0.f;
        break;
    case GeometryInstanceRenderRoute::VoxelOnly:
        state.effectiveMeshWeight = 0.f;
        state.effectiveVoxelWeight = 1.f;
        break;
    case GeometryInstanceRenderRoute::Blend:
    default:
        if (!state.meshHitValid)
        {
            state.effectiveVoxelWeight = state.voxelHitValid ? 1.f : 0.f;
        }
        else if (state.voxelHitValid && state.objectMatch)
        {
            state.effectiveVoxelWeight = saturate((1.f - state.baseMeshWeight) * state.voxelConfidence * state.depthAgreement);
        }
        else
        {
            state.effectiveVoxelWeight = 0.f;
        }
        state.effectiveMeshWeight = 1.f - state.effectiveVoxelWeight;
        break;
    }

    return state;
}

float3 evalCompositeColor(float3 meshColor, float3 voxelColor, CompositeState state)
{
    if (!state.meshHitValid)
        return voxelColor;

    switch (state.route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        return meshColor;
    case GeometryInstanceRenderRoute::VoxelOnly:
        return voxelColor;
    case GeometryInstanceRenderRoute::Blend:
    default:
        return lerp(meshColor, voxelColor, state.effectiveVoxelWeight);
    }
}

float3 evalRouteDebugColor(CompositeState state, float3 compositeColor)
{
    if (!state.meshHitValid)
        return compositeColor;

    const float luma = dot(compositeColor, float3(0.299f, 0.587f, 0.114f));
    const float3 routeColor = getRouteDebugColor(state.route);
    return lerp(saturate(luma).xxx * 0.25f, routeColor, 0.85f);
}

float3 evalBlendMaskDebugColor(CompositeState state)
{
    if (!state.meshHitValid && !state.voxelHitValid)
        return 0.f;

    if (!state.meshHitValid)
        return lerp(float3(0.05f, 0.05f, 0.05f), getRouteDebugColor(GeometryInstanceRenderRoute::VoxelOnly), state.effectiveVoxelWeight);

    switch (state.route)
    {
    case GeometryInstanceRenderRoute::MeshOnly:
        return getRouteDebugColor(state.route);
    case GeometryInstanceRenderRoute::VoxelOnly:
        return getRouteDebugColor(state.route);
    case GeometryInstanceRenderRoute::Blend:
    default:
        return lerp(getRouteDebugColor(GeometryInstanceRenderRoute::VoxelOnly), getRouteDebugColor(GeometryInstanceRenderRoute::MeshOnly), state.effectiveMeshWeight);
    }
}

float3 evalObjectMismatchDebugColor(CompositeState state)
{
    if (!state.meshHitValid && !state.voxelHitValid)
        return 0.f;

    if (!state.meshHitValid || !state.voxelHitValid)
        return float3(0.12f, 0.18f, 0.44f);

    if (!state.voxelIdentityValid)
        return float3(0.46f, 0.32f, 0.08f);

    if (state.objectMismatch)
        return lerp(float3(0.20f, 0.05f, 0.05f), float3(1.00f, 0.12f, 0.08f), max(state.voxelConfidence, 0.35f));

    return lerp(float3(0.04f, 0.18f, 0.05f), float3(0.20f, 0.94f, 0.38f), max(state.voxelConfidence, 0.35f));
}

float3 evalDepthMismatchDebugColor(CompositeState state)
{
    if (!state.meshHitValid && !state.voxelHitValid)
        return 0.f;

    if (!state.meshHitValid || !state.voxelHitValid)
        return float3(0.10f, 0.18f, 0.46f);

    const float tolerance = evalDepthTolerance(state.meshDepth, state.voxelDepth);
    const float mismatch = saturate(abs(state.meshDepth - state.voxelDepth) / tolerance);
    return lerp(float3(0.16f, 0.92f, 0.28f), float3(1.00f, 0.16f, 0.06f), mismatch);
}

float4 main(float2 texCoord : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    const int2 pixelPos = int2(pos.xy);
    const float4 meshColor = gMeshColor.Load(int3(pixelPos, 0));
    const float4 voxelColor = gVoxelColor.Load(int3(pixelPos, 0));
    const CompositeState state = evalCompositeState(pixelPos);
    const float3 compositeColor = evalCompositeColor(meshColor.rgb, voxelColor.rgb, state);

    float3 color = 0.f;
    switch (gViewMode)
    {
    case kViewModeMeshOnly:
        color = meshColor.rgb;
        break;
    case kViewModeVoxelOnly:
        color = voxelColor.rgb;
        break;
    case kViewModeBlendMask:
        color = evalBlendMaskDebugColor(state);
        break;
    case kViewModeRouteDebug:
        color = evalRouteDebugColor(state, compositeColor);
        break;
    case kViewModeVoxelDepth:
        color = evalVoxelDepthDebugColor(pixelPos);
        break;
    case kViewModeVoxelNormal:
        color = evalVoxelNormalDebugColor(pixelPos);
        break;
    case kViewModeVoxelConfidence:
        color = evalVoxelConfidenceDebugColor(pixelPos);
        break;
    case kViewModeVoxelRouteID:
        color = evalVoxelRouteDebugColor(pixelPos);
        break;
    case kViewModeVoxelInstanceID:
        color = evalVoxelInstanceDebugColor(pixelPos);
        break;
    case kViewModeObjectMismatch:
        color = evalObjectMismatchDebugColor(state);
        break;
    case kViewModeDepthMismatch:
        color = evalDepthMismatchDebugColor(state);
        break;
    case kViewModeComposite:
    default:
        color = compositeColor;
        break;
    }

    return float4(color, 1.f);
}
