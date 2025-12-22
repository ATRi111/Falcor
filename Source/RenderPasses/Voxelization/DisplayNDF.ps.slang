#include "Math/VoxelizationUtility.slang"
#include "Shading.slang"
#include "Voxel/VoxelGrid.slang"
#include "VoxelizationShared.slang"

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

float3 pdfToColor(float pdf, float refPdf)
{
    float k = pdf / refPdf;
    // 蓝->青->绿->黄->红->黑渐变
    float3 c;
    c.r = smoothstep(0.4, 1.0, k) - smoothstep(1.0, 5.0, k);
    c.g = smoothstep(0.0, 0.4, k) - smoothstep(0.6, 1.0, k);
    c.b = smoothstep(0.4, 0.0, k);
    return c;
}

float3 calcColor(float2 localCoord, int offset, float3 v)
{
    NDF NDF = gBuffer[offset].ABSDF.NDF;
    float area = gBuffer[offset].ABSDF.area;
    // float3 n = NDF.getMainNormal(v);
    float3x3 rotMatrix = rotateMatrix(v, float3(0, 0, 1));

    float z = sqrt(1 - localCoord.x * localCoord.x - localCoord.y * localCoord.y);
    //中心对称，显示背面没有意义
    float3 direction = float3(localCoord.x, localCoord.y, z);
    direction = mul(rotMatrix, direction);
    float pdf = weightedGGX(NDF, direction) / area;
    float rough = 0.5f; //参考值
    float refPdf = 1.0 / (Pi * rough * rough);
    return pdfToColor(pdf, refPdf);
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = { float4(0) };
    float4 vo = selectedVoxel[0];
    if (vo.w > 0)
    {
        float2 localCoord = (texCoord - float2(0.25f, 1.0f / 18)) / float2(0.5f, 16.0f / 18); // 默认窗口为16:9
        localCoord = localCoord * 2 - 1; // 映射到[-1,1]
        if (length(localCoord) <= 1)
        {
            psOut.color = float4(calcColor(localCoord, (int)vo.w, vo.xyz), 1);
        }
    }
    return psOut;
}
