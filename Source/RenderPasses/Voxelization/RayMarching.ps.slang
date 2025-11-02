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

HitResult leave(HitResult current, int3 directions, float3 direction, float3 reciprocal_direction)
{
    float3 border = current.cellInt + (directions + 1) / 2;
    float3 t = (border - current.cell) * reciprocal_direction;
    float tMin = 2.0f;
    int3 selectedDirection = 0;
    if (direction.x != 0 && t.x < tMin)
    {
        tMin = t.x;
        selectedDirection = uint3(directions.x, 0, 0);
    }
    if (direction.y != 0 && t.y < tMin)
    {
        tMin = t.y;
        selectedDirection = uint3(0, directions.y, 0);
    }
    if (direction.z != 0 && t.z < tMin)
    {
        tMin = t.z;
        selectedDirection = uint3(0, 0, directions.z);
    }
    current.cell += tMin * direction;
    current.cellInt += selectedDirection;
    return current;
}

float checkEllipsoid(Ellipsoid ellipsoid, float3 subVoxelOffset, float3 direction)
{
    float3 from = subVoxelOffset;
    float3 to = from + 2 * direction;
    // float2 u12 = clip(ellipsoid.min, ellipsoid.max, from, to);
    // if (u12.x >= 0)
    //     return ellipsoid.alpha;
    return 1;
}

// 统一用3D纹理坐标表示
HitResult rayMarching(float3 from, float3 to)
{
    HitResult current = { int3(-1), float3(-1) };
    // 计算光线与场景包围盒相交的部分
    float2 inOut = clip(float3(0), float3(1), from, to);
    if (inOut.x < 0)
        return current;

    float3 v = to - from;
    float3 direction = normalize(v * voxelCount);

    from = from + (inOut.x + 1e-5f) * v; // 避免边界处误差
    current.cell = from * voxelCount;
    current.cellInt = int3(current.cell);
    float3 reciprocal_direction = 1.0f / direction;
    // 可选的前进方向
    int3 directions = int3(sign(direction));

    uint maxTimes = voxelCount.x + voxelCount.y + voxelCount.z;
    for (uint i = 0; i < maxTimes; i++)
    {
        float accumulate = gDiffuse[current.cellInt].w;
        if (accumulate > 0)
        {
#if CHECK_ELLIPSOID
            int index = CellToIndex(current.cellInt, voxelCount);
            Ellipsoid ellipsoid = gEllipsoids[index];
            float alpha = checkEllipsoid(ellipsoid, current.cell - current.cellInt, direction);
            if (alpha > 0)
                return current;
#else
            return current;
#endif
        }
        current = leave(current, directions, direction, reciprocal_direction);
        if (any(current.cellInt < 0) || any(current.cellInt >= voxelCount))
            break;
    }
    return current;
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
    {
#if SHOW_VOXEL_INDEX
        psOut.color = float4(cellToColor(hit.cellInt), 1);
#else
        float4 diffuse = gDiffuse[hit.cellInt];
        psOut.color = diffuse / diffuse.w;
#endif
    }
    else
        psOut.color = float4(0, 0, 0, 1);
    return psOut;
}
