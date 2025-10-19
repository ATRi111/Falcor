#include "VoxelizationShared.slang"
import Scene.SceneTypes;
__exported import Rendering.Materials.StandardMaterial;

Texture3D<float4> gDiffuse;
StructuredBuffer<Ellipsoid> gEllipsoids;

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

struct HitResult
{
    int3 cellInt;
    float3 cell;
}

struct PsOut
{
    float4 color : SV_Target0;
};

static const uint3 SubDivision = uint3(4, 2, 4);

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

float3 leave(float3 cell, int3 directions, float3 direction, float3 reciprocal_direction)
{
    float3 border = floor(cell + directions * 0.5 + 0.5);
    float3 t = (border - cell) * reciprocal_direction;
    float tMin = 1.733f;
    if (t.x > 0)
        tMin = min(tMin, t.x);
    if (t.y > 0)
        tMin = min(tMin, t.y);
    if (t.z > 0)
        tMin = min(tMin, t.z);
    cell += (tMin + 1e-5f) * direction; // 避免返回整数坐标
    return cell;
}

// 统一用3D纹理坐标表示
HitResult rayMarching(float3 from, float3 to)
{
    HitResult result = { int3(-1), float3(-1) };
    // 计算光线与场景包围盒相交的部分
    float2 inOut = clip(float3(0), float3(1), from, to);
    if (inOut.x < 0)
        return result;

    float3 v = to - from;
    float3 direction = normalize(v * voxelCount);

    from = from + (inOut.x + 1e-5f) * v; // 避免边界处误差
    float3 cell_OM = from * voxelCount;
    int3 cellInt_OM = int3(cell_OM);
    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));

    uint maxTimes = voxelCount.x + voxelCount.y + voxelCount.z;
    for (uint i = 0; i < maxTimes; i++)
    {
        // uint geom = gOM[cellInt_OM];
        float accumulate = gDiffuse[cellInt_OM].w;
        if (accumulate > 0)
        {
            result.cellInt = cellInt_OM;
            result.cell = cell_OM;
            return result;
        }
        cell_OM = leave(cell_OM, directions, direction, reciprocal_direction);
        cellInt_OM = int3(cell_OM);
        if (any(cellInt_OM < 0) || any(cellInt_OM >= voxelCount))
            break;
    }
    return result;
}

float3 screenCoordToGridCoord(float2 screenCoord, float NDCDepth)
{
    float4 NDC = float4(2 * screenCoord.x - 1, 1 - 2 * screenCoord.y, NDCDepth, 1);
    float4 temp = mul(invVP, NDC);
    float4 posWorld = temp / temp.w;
    float3 cell = (posWorld.xyz - gridMin) / voxelSize;
    return cell / voxelCount;
}

float3 cellToColor(uint3 cell)
{
    static float3 palette[6] = {
        float3(1.0, 0.0, 0.0), // 红
        float3(0.0, 1.0, 0.0), // 绿
        float3(0.0, 0.0, 1.0), // 蓝
        float3(1.0, 1.0, 0.0), // 黄
        float3(1.0, 0.0, 1.0), // 紫
        float3(0.0, 1.0, 1.0), // 青
    };
    uint h = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (cell.z * 83492791);
    h %= 6;
    return palette[h];
}

PsOut main(float2 texCoord: TEXCOORD, float4 pos: SV_POSITION)
{
    PsOut psOut = {};
    uint2 pixel = uint2(texCoord * pixelCount);
    float3 from = screenCoordToGridCoord(texCoord, 0);
    float3 to = screenCoordToGridCoord(texCoord, 1);
    HitResult hit = rayMarching(from, to);
    if (hit.cellInt.x >= 0)
#if SHOW_VOXEL_INDEX
    {
        psOut.color = float4(cellToColor(hit.cellInt), 1);
    }
#else
    {
        float4 diffuse = gDiffuse[hit.cellInt];
        psOut.color = diffuse / diffuse.w;
    }
#endif
    else
        psOut.color = float4(0, 0, 0, 1);

    return psOut;
}
