import Scene.SceneTypes;
__exported import Rendering.Materials.StandardMaterial;

Texture3D<uint> gOM;
Texture3D<uint> gMipOM;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
    uint3 mipOMSize;
    uint3 voxelPerBit;
}

cbuffer CB
{
    float stepLength;
    uint2 pixelCount;
    float4x4 invVP;
}

struct PsOut
{
    float4 color : SV_Target0;
};

enum SampleLevel
{
    SubVoxelOfOM,
    VoxelOfOM,
    SubVoxelOfMipOM,
    VoxelOfMipOM
};

float2 intersect(float p1, float p2, float p0, float q)
{
    float u1 = (p1 - p0) / q;
    float u2 = (p2 - p0) / q;
    if (u1 > u2)
    {
        float temp = u1;
        u1 = u2;
        u2 = temp;
    }
    return float2(u1, u2);
}
// 应当统一用3D纹理的纹理坐标计算
float2 clip(float3 minPoint, float3 maxPoint, float3 from, float3 to)
{
    float uIn = 0, uOut = 1;
    float3 v = to - from;

    float2 u12 = intersect(minPoint.x, maxPoint.x, from.x, v.x);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    u12 = intersect(minPoint.y, maxPoint.y, from.y, v.y);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    u12 = intersect(minPoint.z, maxPoint.z, from.z, v.z);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    return float2(uIn, uOut);
}

uint subVoxelOffsetToBit(float3 offset)
{
    uint3 index = uint3(floor(offset * float3(4, 2, 4)));
    uint x = (uint)(offset.x * 4);
    uint y = (uint)(offset.y * 2);
    uint z = (uint)(offset.z * 4);
    uint temp = index.x + (index.y << 2) + (index.z << 3);
    return 1u << temp;
}

bool sampleMipOM(float3 coord)
{
    uint3 mipCellInt = uint3(floor(coord * mipOMSize));
    uint mask = gMipOM[mipCellInt];
    return mask != 0;
}

bool sampleSubVoxelOfMipOM(float3 coord)
{
    float3 mipCell = coord * mipOMSize;
    uint3 mipCellInt = uint3(floor(mipCell));
    uint mask = gMipOM[mipCellInt];
    float3 offset = mipCell - mipCellInt;
    uint bit = subVoxelOffsetToBit(offset);
    return (bit & mask) != 0;
}

bool sampleOM(float3 coord)
{
    uint3 cellInt = uint3(floor(coord * voxelCount));
    uint mask = gOM[cellInt];
    return mask != 0;
}

bool sampleSubVoxelOfOM(float3 coord)
{
    float3 cell = coord * voxelCount;
    uint3 cellInt = uint3(floor(cell));
    uint mask = gOM[cellInt];
    float3 offset = cell - cellInt;
    uint bit = subVoxelOffsetToBit(offset);
    return (bit & mask) != 0;
}

// 统一用3D纹理坐标表示
float3 rayMarching(float3 from, float3 to)
{
    // 计算光线与场景包围盒相交的部分
    float2 inOut = clip(float3(0), float3(1), from, to);
    if (inOut.x < 0)
        return float3(-1);

    float3 v = to - from;
    float3[4] steps;
    steps[3] = clamp(stepLength, 0.04f, 1.0f) * normalize(v) / mipOMSize;
    for (int i = 2; i >= 0; i--)
        steps[i] = steps[i + 1] / 4;

    SampleLevel level = SampleLevel::VoxelOfMipOM;
    float3 step = steps[(int)level];
    float3 current = from + (inOut.x + 0.0001f) * v; // 避免边界处误差
    float3 test;
    int counter = 0; // 此值变为0时，允许采样层级提高
    while (true)
    {
        test = current + step;
        switch (level)
        {
        case SampleLevel::VoxelOfMipOM:
            if (sampleMipOM(current))
            {
                level = SampleLevel::SubVoxelOfMipOM;
                counter = 4;
            }
            else
            {
                current = test;
            }
            break;
        case SampleLevel::SubVoxelOfMipOM:
            if (sampleSubVoxelOfMipOM(current))
            {
                level = SampleLevel::VoxelOfOM;
                counter = 4;
            }
            else
            {
                current = test;
                counter--;
                if (counter <= 0)
                    level = SampleLevel::VoxelOfMipOM;
            }
            break;
        case SampleLevel::VoxelOfOM:
            if (sampleOM(current))
            {
                level = SampleLevel::SubVoxelOfOM;
                counter = 4;
            }
            else
            {
                current = test;
                counter--;
                if (counter <= 0)
                    level = SampleLevel::SubVoxelOfMipOM;
            }
            break;
        case SampleLevel::SubVoxelOfOM:
            if (sampleSubVoxelOfOM(current))
            {
                return current;
            }
            else
            {
                current = test;
                counter--;
                if (counter <= 0)
                    level = SampleLevel::VoxelOfOM;
            }
            break;
        }
        if (any(current < 0) || any(current > 1))
            break;
        step = steps[(int)level];
    }
    return float3(-1);
}

float3 screenCoordToGridCoord(float2 screenCoord, float NDCDepth)
{
    float4 NDC = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, NDCDepth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posWorld = temp / temp.w;
    float3 cell = (posWorld.xyz - gridMin) / voxelSize;
    return cell / voxelCount;
}
PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = {};
    uint2 pixel = uint2(texCoord * pixelCount);
    float3 from = screenCoordToGridCoord(texCoord, 0);
    float3 to = screenCoordToGridCoord(texCoord, 1);
    float3 hit = rayMarching(from, to);
    if (hit.x >= 0)
        psOut.color = float4(1, 1, 1, 1);
    else
        psOut.color = float4(0, 0, 0, 1);
    return psOut;
}
