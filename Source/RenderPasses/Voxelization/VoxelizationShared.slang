#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

#define LOBE_COUNT 4
#define PI 3.14159265358

struct NDF
{
    float4 weightedNormals[LOBE_COUNT];
};

#if !defined(HOST_CODE)

struct Basis2
{
    float3 u;
    float3 w;
};
inline Basis2 orthonormal_basis(float3 v)
{
    Basis2 ret;
    float3 axis = (abs(v.z) < 0.999) ? float3(0, 0, 1) : float3(1, 0, 0);
    ret.u = normalize(cross(axis, v));
    ret.w = cross(v, ret.u);
    return ret;
}

float2x2 mulT(float2 a, float2 b)
{
    return float2x2(a.x * b.x, a.x * b.y, a.y * b.x, a.y * b.y);
}

struct Ellipse
{
    float2x2 M; // 默认中心位于原点,y^TMy <=1

    float area() { return PI / sqrt(determinant(M)); }

    // M=LL^T→(L^Ty)^T(L^Ty) <= 1
    float2x2 transfromToUnitCircle()
    {
        float a = M[0][0];
        float c = M[0][1];
        float b = M[1][1];

        float l00 = sqrt(a);
        float l10 = c / l00;
        float t = b - l10 * l10;
        float l11 = sqrt(t);

        return float2x2(l00, l10, 0.0f, l11);
    }
};
#endif

struct Ellipsoid
{
    float3 center; // 相对于所在体素左下角的偏移量（涉及求交运算时，以椭球的中心为原点）
    float3x3 B;    // x^T B x <=1
    float det;

#if !defined(HOST_CODE)
    Ellipse project(float3 v)
    {
        Basis2 basis = orthonormal_basis(v);
        float3 u = basis.u, w = basis.w;

        float3 Bu = mul(B, u), Bv = mul(B, v), Bw = mul(B, w);
        float2x2 A2 = float2x2(dot(u, Bu), dot(u, Bw), dot(w, Bu), dot(w, Bw));
        float2 b2 = float2(dot(u, Bv), dot(w, Bv));
        float2x2 B2 = mulT(b2, b2);
        float b = dot(v, Bv);

        float2x2 M = A2 - B2 / b;

        Ellipse e;
        e.M = M;
        return e;
    }

    bool contains(float3 p, float epsilon)
    {
        float3 offset = p - center;
        float d = dot(offset, mul(B, offset));
        return d <= (1.0 + epsilon);
    }
#endif
};

struct GridData
{
    float3 gridMin;
    float3 voxelSize;
    uint3 voxelCount;

    size_t totalVoxelCount() { return (size_t)voxelCount.x * (size_t)voxelCount.y * (size_t)voxelCount.z; }
};

// TODO:Z-Order Curve
inline int CellToIndex(int3 cell, uint3 size)
{
    return cell.x + cell.y * size.x + cell.z * size.x * size.y;
}

inline int3 IndexToCell(int index, uint3 size)
{
    int z = index / (size.x * size.y);
    int y = (index % (size.x * size.y)) / size.x;
    int x = index % size.x;
    return int3(x, y, z);
}

enum class ABSDFDrawMode : uint32_t
{
    Default,
    Diffuse,
    Specular,
    Flat,
    Normal,
    Ellipsoid,
};
FALCOR_ENUM_INFO(
    ABSDFDrawMode,
    {
        { ABSDFDrawMode::Default, "Default" },
        { ABSDFDrawMode::Diffuse, "Diffuse" },
        { ABSDFDrawMode::Specular, "Specular" },
        { ABSDFDrawMode::Flat, "Flat" },
        { ABSDFDrawMode::Normal, "Normal" },
        { ABSDFDrawMode::Ellipsoid, "Ellipsoid" },
    }
);
FALCOR_ENUM_REGISTER(ABSDFDrawMode);

END_NAMESPACE_FALCOR
