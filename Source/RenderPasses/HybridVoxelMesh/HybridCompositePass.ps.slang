/*** Hybrid mesh/voxel composition for plan4 Phase4. ***/

Texture2D<float4> gMeshColor;
Texture2D<float4> gVoxelColor;
Texture2D<float4> gBlendMask;

cbuffer PerFrameCB
{
    uint gViewMode;
};

static const uint kViewModeComposite = 0;
static const uint kViewModeMeshOnly = 1;
static const uint kViewModeVoxelOnly = 2;
static const uint kViewModeBlendMask = 3;

float4 main(float2 texCoord : TEXCOORD, float4 pos : SV_Position) : SV_Target0
{
    const int2 pixelPos = int2(pos.xy);
    const float4 meshColor = gMeshColor.Load(int3(pixelPos, 0));
    const float4 voxelColor = gVoxelColor.Load(int3(pixelPos, 0));
    const float meshWeight = saturate(gBlendMask.Load(int3(pixelPos, 0)).x);

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
        color = meshWeight.xxx;
        break;
    case kViewModeComposite:
    default:
        color = lerp(voxelColor.rgb, meshColor.rgb, meshWeight);
        break;
    }

    return float4(color, 1.f);
}
