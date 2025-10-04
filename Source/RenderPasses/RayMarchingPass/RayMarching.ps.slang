import Scene.SceneTypes;
__exported import Rendering.Materials.StandardMaterial;

Texture3D<uint> gOccupancyMap;

cbuffer GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;
}

cbuffer CB
{
    uint2 pixelCount;
    float4x4 invVP;
}

struct PsOut
{
    float4 color : SV_Target0;
};

uint subVoxelOffsetToMask(float3 offset)
{
    uint x = (uint)(offset.x * 4);
    uint y = (uint)(offset.y * 2);
    uint z = (uint)(offset.z * 4);
    uint index = x + (y << 2) + (z << 3);
    return 1u << index;
}

float3 screenCoordToCell(float2 screenCoord, float NDCDepth)
{
    float4 NDC = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, NDCDepth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posWorld = temp / temp.w;
    return (posWorld.xyz - gridMin) / voxelSize;
}

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

float2 gridClip(float3 from, float3 to)
{
    float uIn = 0, uOut = 1;
    float3 v = to - from;

    float2 u12 = intersect(0, voxelCount.x, from.x, v.x);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    u12 = intersect(0, voxelCount.y, from.y, v.y);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    u12 = intersect(0, voxelCount.z, from.z, v.z);
    uIn = max(uIn, u12.x);
    uOut = min(uOut, u12.y);
    if (uIn > uOut)
        return float2(-1, -1);

    return float2(uIn, uOut);
}

bool sampleWithCell(float3 cell, float3 deltaCell)
{
    if (all(cell < voxelCount) && all(cell >= 0))
    {
        int3 cellInt = int3(floor(cell));
        uint occupancy = gOccupancyMap[cellInt];
        deltaCell *= 0.1f;
        float3 current;
        for (current = cell;; current += deltaCell)
        {
            float3 offset = current - cellInt;
            if (any(offset > 1) || any(offset < 0))
                break;

            uint mask = subVoxelOffsetToMask(offset);
            if ((occupancy & mask) != 0)
                return true;
        }
        for (current = cell - deltaCell;; current -= deltaCell)
        {
            float3 offset = current - cellInt;
            if (any(offset > 1) || any(offset < 0))
                break;

            uint mask = subVoxelOffsetToMask(offset);
            if ((occupancy & mask) != 0)
                return true;
        }
    }
    return false;
}

// 须传入体素网格坐标
bool rayMarching(float3 from, float3 to)
{
    float2 inOut = gridClip(from, to);
    if (inOut.x < 0)
        return false;

    float3 v = to - from;
    to = from + inOut.y * v;
    from = from + inOut.x * v;
    v = to - from;

    float step = 0.5f;
    uint n = (uint)floor(length(v) / step);
    float3 cell = from + inOut.x * v;
    float3 deltaCell = step * normalize(v);
    for (uint i = 0; i < n; i++)
    {
        if (sampleWithCell(cell, deltaCell))
            return true;
        cell += deltaCell;
    }

    return false;
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = {};
    uint2 pixel = uint2(texCoord * pixelCount);
    float3 from = screenCoordToCell(texCoord, 0);
    float3 to = screenCoordToCell(texCoord, 1);
    bool hit = rayMarching(from, to);
    if (hit)
        psOut.color = float4(1, 1, 1, 1);
    else
        psOut.color = float4(0, 0, 0, 1);
    return psOut;
}
