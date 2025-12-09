#include "Voxel/VoxelGrid.slang"
#include "Voxel/Shading.slang"
#include "VoxelizationShared.slang"
#include "Math/Sampling.slang"
#include "Math/Random.slang"
#include "Math/VoxelizationUtility.slang"
import Scene.SceneTypes;
import Scene.Scene;
import Rendering.Materials.StandardMaterial;
import Utils.Sampling.UniformSampleGenerator;

ParameterBlock<Scene> scene;
StructuredBuffer<VoxelData> gBuffer;
StructuredBuffer<float4> selectedVoxel; //前三个分量表示相机指向体素的方向

cbuffer CB
{
    uint2 pixelCount;
}

struct PsOut
{
    float4 color : SV_Target0;
};


PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = { float4(0) };
    uint2 pixel = uint2(texCoord * pixelCount);
    //TODO
    return psOut;
}
